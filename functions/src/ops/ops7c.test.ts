/**
 * Phase 7C unit tests: metadata appended after the image (or between
 * scans), backup cleanup when an overwrite doesn't happen, download-token
 * rotation (fakes), and the CLI additions. Real Storage/Firestore behavior
 * is covered by ops7c.emulator.test.ts.
 */
import {test, describe} from "node:test";
import assert from "node:assert/strict";
import {hasRemovableMetadata, inspectJpeg, stripJpegMetadata, validateStripped} from "./jpegMetadata";
import {
  InventoryItem, ObjectInfo, PhotoStoreDeps, inventoryPhotoMetadata, remediatePhotoMetadata,
} from "./photoMetadataJob";
import {
  PhotoReference, ROTATION_FINAL, ROTATION_MARKER, ROTATION_NEW, ROTATION_STATE, ReferenceDeps, TokenObjectInfo,
  TokenStoreDeps, downloadUrl, objectNameFromUrl, rotatePhotoTokens, tokenTag,
} from "./photoTokenRotation";
import {NOT_TOUCHGRASS, PHOTO_REWRITE_LEASE, leaseFor, parseArgs, refusal, resumeOptions, summary} from "./opsCli";
import {ascii, exifSegment, jpeg, seg} from "./testJpeg";
import {experimentRefusal, interpretRevocation, redactState, type ExperimentState} from "./revocationExperiment";

const text = (b: Uint8Array) => Buffer.from(b).toString("latin1");
const cat = (...parts: Array<Uint8Array | number[]>) => Uint8Array.from(parts.flatMap((p) => Array.from(p)));

describe("jpegMetadata — data outside the header (Phase 7C)", () => {
  const withTrailer = () => cat(jpeg({jfif: true}), jpeg({exif: exifSegment({gps: true})}));
  const withAppBetweenScans = () => {
    const base = jpeg({jfif: true});
    return cat(base.subarray(0, base.length - 2), seg(0xe1, ascii("Exif\0\0Cam\0 GPS")), [0xff, 0xd9]);
  };

  test("an appended second image (MPF, with GPS) is found only with the whole file", () => {
    const full = inspectJpeg(withTrailer());
    assert.equal(full.trailingData, true);
    assert.equal(hasRemovableMetadata(full), true);
    const head = inspectJpeg(withTrailer().subarray(0, 40));
    assert.equal(head.trailingData, false, "a header read can't see it");
  });
  test("stripping ends at EOI: the appended image (and its GPS) is gone; image data identical", () => {
    const original = withTrailer();
    const out = stripJpegMetadata(original)!;
    assert.doesNotMatch(text(out), /Cam\0/);
    assert.deepEqual(Array.from(out.subarray(out.length - 2)), [0xff, 0xd9]);
    assert.equal(inspectJpeg(out).trailingData, false);
    assert.equal(validateStripped(original, out), null);
    assert.ok(out.length < original.length);
  });
  test("motion-photo video and vendor trailers are dropped too", () => {
    const original = cat(jpeg({exif: exifSegment({gps: true})}), ascii("\0\0\0\x18ftypmp42 \xa9xyz+30.2672-097.7431/"));
    const out = stripJpegMetadata(original)!;
    assert.doesNotMatch(text(out), /ftypmp42|30\.2672/);
    assert.equal(validateStripped(original, out), null);
  });
  test("APPn between scans is detected and dropped; the rest of the image is kept", () => {
    const original = withAppBetweenScans();
    assert.equal(inspectJpeg(original).afterScanMetadata, true);
    const out = stripJpegMetadata(original)!;
    assert.doesNotMatch(text(out), /Cam\0/);
    assert.equal(validateStripped(original, out), null);
  });
  test("validation refuses a replacement that still carries the trailer", () => {
    const original = withTrailer();
    assert.equal(validateStripped(original, original), "metadata-remains");
  });
  test("a JPEG that never reaches EOI is not stripped (left for review)", () => {
    const full = jpeg({exif: exifSegment({gps: true})});
    assert.equal(stripJpegMetadata(full.subarray(0, full.length - 2)), null);
  });
  test("stuffed bytes and restart markers stay in the image data", () => {
    const original = jpeg({exif: exifSegment({gps: true})});
    const sos = inspectJpeg(original).sosOffset!;
    const scanStart = sos + 10; // SOS header is 10 bytes in testJpeg
    const custom = cat(original.subarray(0, scanStart), [0x11, 0xff, 0x00, 0x22, 0xff, 0xd3, 0x33], [0xff, 0xd9]);
    const out = stripJpegMetadata(custom)!;
    assert.deepEqual(Array.from(out.subarray(out.length - 9)), [0x11, 0xff, 0x00, 0x22, 0xff, 0xd3, 0x33, 0xff, 0xd9]);
    assert.equal(validateStripped(custom, out), null);
  });
});

// ── Remediation: full-read inventory and backup cleanup ─────────────────────

class Store implements PhotoStoreDeps {
  objects = new Map<string, {data: Uint8Array; gen: number; info: ObjectInfo}>();
  deleted: string[] = [];
  failWrite = false;
  onBeforeWrite?: (name: string) => void;
  put(name: string, data: Uint8Array) {
    const gen = (this.objects.get(name)?.gen ?? 100) + 1;
    this.objects.set(name, {data, gen, info: {name, generation: gen, contentType: "image/jpeg",
      metadata: {firebaseStorageDownloadTokens: "tok-1"}}});
  }
  async listPage(prefix: string, max: number, token?: string) {
    const all = [...this.objects.keys()].filter((k) => k.startsWith(prefix)).sort();
    const start = token ? Number(token) : 0;
    return {files: all.slice(start, start + max).map((k) => ({...this.objects.get(k)!.info})),
      nextPageToken: start + max < all.length ? String(start + max) : undefined};
  }
  async readHead(name: string, gen: string | number, n: number) {
    return (await this.readAll(name, gen)).subarray(0, n);
  }
  async readAll(name: string, gen: string | number) {
    const o = this.objects.get(name);
    if (!o || String(o.gen) !== String(gen)) throw Object.assign(new Error("nf"), {code: 404});
    return o.data;
  }
  async getInfo(name: string) {
    const o = this.objects.get(name);
    return o ? {...o.info, metadata: {...o.info.metadata}} : null;
  }
  async saveBackup(dest: string, data: Uint8Array, info: ObjectInfo) {
    this.objects.set(dest, {data, gen: 1, info: {name: dest, generation: 1, contentType: info.contentType, metadata: {}}});
  }
  async deleteBackup(dest: string) {
    this.deleted.push(dest);
    this.objects.delete(dest);
  }
  async writeIfGeneration(name: string, gen: string | number, data: Uint8Array, info: ObjectInfo) {
    this.onBeforeWrite?.(name);
    if (this.failWrite) throw new Error("503");
    const o = this.objects.get(name);
    if (!o || String(o.gen) !== String(gen)) return false;
    this.objects.set(name, {data, gen: o.gen + 1, info: {...info, generation: o.gen + 1}});
    return true;
  }
  backups() {
    return [...this.objects.keys()].filter((k) => k.startsWith("metadata_backup/"));
  }
}

const TRAILER_ONLY = "completion_photos/eve/2026-02-01.jpg";
const GPS = "completion_photos/eve/2026-02-02.jpg";

function store(): Store {
  const s = new Store();
  s.put(TRAILER_ONLY, cat(jpeg({jfif: true}), jpeg({exif: exifSegment({gps: true})})));
  s.put(GPS, cat(jpeg({exif: exifSegment({gps: true})}), jpeg({exif: exifSegment({gps: true})})));
  return s;
}

describe("photo metadata job — Phase 7C", () => {
  test("a header-only inventory can't see an appended image; --full-read can", async () => {
    const s = store();
    // A photo larger than the header window, with an image appended after it.
    const primary = jpeg({jfif: true});
    s.put(TRAILER_ONLY, cat(primary.subarray(0, primary.length - 2), Array(3000).fill(0x12), [0xff, 0xd9],
      jpeg({exif: exifSegment({gps: true})})));
    const head = await inventoryPhotoMetadata(s, {headBytes: 1024});
    assert.equal(head.counts.clean, 1, "documented limitation of header reads");
    const full = await inventoryPhotoMetadata(s, {fullRead: true});
    assert.deepEqual(full.counts, {"appended-data": 1, "gps": 1});
    assert.equal(full.needsRemediation, 2);
  });
  test("--uid scope: the inventory reads only that user's photos", async () => {
    const s = store();
    s.put("completion_photos/eve2/2026-02-01.jpg", jpeg({exif: exifSegment({gps: true})}));
    const r = await inventoryPhotoMetadata(s, {uid: "eve2"});
    assert.deepEqual(r.items.map((i) => i.name), ["completion_photos/eve2/2026-02-01.jpg"]);
    await assert.rejects(inventoryPhotoMetadata(s, {uid: "../x"}), /uid/);
  });
  test("execute removes the appended image as well as header GPS, keeping the token", async () => {
    const s = store();
    const inv = await inventoryPhotoMetadata(s, {fullRead: true});
    const r = await remediatePhotoMetadata(s, inv.items, {runId: "r1", backup: true, mode: "execute"});
    assert.equal(r.counts.rewritten, 2);
    for (const name of [TRAILER_ONLY, GPS]) {
      const o = s.objects.get(name)!;
      assert.doesNotMatch(text(o.data), /Cam\0/);
      assert.equal(o.info.metadata?.firebaseStorageDownloadTokens, "tok-1");
    }
    assert.equal(s.backups().length, 2, "originals kept for recovery");
  });
  const raced = async (setup: (s: Store) => void): Promise<{s: Store; r: Awaited<ReturnType<typeof remediatePhotoMetadata>>}> => {
    const s = store();
    const inv: InventoryItem[] = (await inventoryPhotoMetadata(s, {fullRead: true})).items;
    setup(s);
    const r = await remediatePhotoMetadata(s, inv, {runId: "r1", backup: true, mode: "execute"});
    return {s, r};
  };
  test("photo deleted between backup and overwrite (e.g. account deletion): backup removed", async () => {
    const {s, r} = await raced((s) => {
      s.onBeforeWrite = (name) => s.objects.delete(name);
    });
    assert.equal(r.counts["changed-since-inventory"], 2);
    assert.deepEqual(s.backups(), [], "no copy outlives its photo");
    assert.ok(r.entries.every((e) => e.detail === "backup-removed" && e.backup === undefined));
  });
  test("photo replaced between backup and overwrite: backup removed", async () => {
    const {s, r} = await raced((s) => {
      s.onBeforeWrite = (name) => s.put(name, jpeg({jfif: true}));
    });
    assert.equal(r.counts["changed-since-inventory"], 2);
    assert.deepEqual(s.backups(), []);
  });
  test("write error after the backup: backup removed, failure recorded", async () => {
    const {s, r} = await raced((s) => {
      s.failWrite = true;
    });
    assert.equal(r.counts["write-failed"], 2);
    assert.deepEqual(s.backups(), []);
    assert.ok(r.entries.every((e) => e.detail === "Error; backup-removed"));
  });
  test("a backup that can't be removed is reported, never silently left", async () => {
    const {r} = await raced((s) => {
      s.failWrite = true;
      s.deleteBackup = async () => {
        throw new Error("503");
      };
    });
    assert.ok(r.entries.every((e) => e.backup && /backup-removal-failed/.test(e.detail ?? "")));
  });
});

// ── Token rotation (fakes) ──────────────────────────────────────────────────

const BUCKET = "touchgrass-today.firebasestorage.app";
const OLD = "11111111-1111-4111-8111-111111111111";
const url = (name: string, token: string) => downloadUrl(BUCKET, name, token);
const NOW = new Date("2026-10-20T12:00:00Z");
const OLD_TIME = "2026-10-01T00:00:00Z";
const TOKENS = "firebaseStorageDownloadTokens";
const list = (v: string | undefined) => (v ?? "").split(",").filter(Boolean);

class TokenStore implements TokenStoreDeps {
  objects = new Map<string, {data: Uint8Array; info: TokenObjectInfo}>();
  ops: string[] = [];
  /** Behave like the Storage emulator: a metadata patch MERGES token lists. */
  mergeTokens = false;
  onBeforePatch?: (name: string) => void;
  onBeforeRewrite?: (name: string) => void;
  failPatch = false;
  /** Called after every write, to check invariants. */
  afterWrite?: () => void;
  put(name: string, token = OLD, updated = OLD_TIME, extra: Record<string, string> = {}) {
    const gen = (Number(this.objects.get(name)?.info.generation ?? 100)) + 1;
    const data = Uint8Array.from(ascii(`bytes of ${name}`));
    this.objects.set(name, {data, info: {name, generation: gen, metageneration: 1, contentType: "image/jpeg",
      cacheControl: "private, max-age=300", md5Hash: `md5:${name}`, updated,
      metadata: {...(token ? {[TOKENS]: token} : {}), ...extra}}});
  }
  tokens(name: string) {
    return list(this.objects.get(name)?.info.metadata?.[TOKENS]);
  }
  async listPage(prefix: string, max: number, token?: string) {
    const all = [...this.objects.keys()].filter((k) => k.startsWith(prefix)).sort();
    const start = token ? Number(token) : 0;
    return {files: all.slice(start, start + max).map((k) => ({...this.objects.get(k)!.info})),
      nextPageToken: start + max < all.length ? String(start + max) : undefined};
  }
  async getInfo(name: string) {
    const o = this.objects.get(name);
    return o ? {...o.info, metadata: {...o.info.metadata}} : null;
  }
  async patchMetadataIfUnchanged(name: string, gen: string | number, metagen: string | number,
    metadata: Record<string, string>) {
    this.onBeforePatch?.(name);
    if (this.failPatch) throw new Error("503");
    const o = this.objects.get(name);
    if (!o || String(o.info.generation) !== String(gen) || String(o.info.metageneration) !== String(metagen)) return false;
    this.ops.push(`patch:${name}`);
    const next = {...o.info.metadata};
    for (const [k, v] of Object.entries(metadata)) {
      next[k] = k === TOKENS && this.mergeTokens ? [...new Set([...list(next[k]), ...list(v)])].join(",") : v;
    }
    o.info = {...o.info, metageneration: Number(o.info.metageneration) + 1, metadata: next};
    this.afterWrite?.();
    return true;
  }
  async readAll(name: string) {
    this.ops.push(`read:${name}`);
    return this.objects.get(name)!.data;
  }
  async rewriteIfGeneration(name: string, gen: string | number, data: Uint8Array,
    info: {contentType?: string; cacheControl?: string; metadata: Record<string, string>}) {
    this.onBeforeRewrite?.(name);
    const o = this.objects.get(name);
    if (!o || String(o.info.generation) !== String(gen)) return false;
    this.ops.push(`rewrite:${name}`);
    this.objects.set(name, {data, info: {...o.info, ...info, generation: Number(gen) + 1, metageneration: 1,
      updated: NOW.toISOString(), md5Hash: o.info.md5Hash, metadata: {...info.metadata}}});
    this.afterWrite?.();
    return true;
  }
}

class Refs implements ReferenceDeps {
  docs = new Map<string, {uid: string; photoUrl: unknown}>();
  queries: string[] = [];
  updates: string[] = [];
  onBeforeUpdate?: (path: string) => void;
  failUpdate = false;
  async findReferences(uid: string): Promise<PhotoReference[]> {
    this.queries.push(uid);
    return [...this.docs.entries()].filter(([, d]) => d.uid === uid).map(([path, d]) => ({path, photoUrl: d.photoUrl}));
  }
  async updateReference(path: string, objectName: string, newUrl: string) {
    this.onBeforeUpdate?.(path);
    if (this.failUpdate) throw new Error("503");
    const d = this.docs.get(path);
    if (!d || objectNameFromUrl(d.photoUrl, BUCKET) !== objectName) return false;
    d.photoUrl = newUrl;
    this.updates.push(path);
    return true;
  }
}

const A1 = "completion_photos/alice/2026-01-01.jpg";
const A2 = "completion_photos/alice/1700000000000.jpg";
const B1 = "completion_photos/bob/2026-01-01.jpg";

/** The fixtures, plus the invariant every write is checked against: no
 * saved link may ever point at a token its object no longer accepts. */
function world() {
  const st = new TokenStore();
  st.put(A1);
  st.put(A2);
  st.put(B1);
  const refs = new Refs();
  refs.docs.set("completions/alice_2026-01-01", {uid: "alice", photoUrl: url(A1, OLD)});
  refs.docs.set("users/alice/memories/alice_2026-01-01", {uid: "alice", photoUrl: url(A1, OLD)});
  refs.docs.set("completions/alice_legacy", {uid: "alice", photoUrl: url(A2, OLD)});
  refs.docs.set("completions/bob_2026-01-01", {uid: "bob", photoUrl: url(B1, OLD)});
  const broken: string[] = [];
  st.afterWrite = () => {
    for (const [path, d] of refs.docs) {
      const name = objectNameFromUrl(d.photoUrl, BUCKET);
      if (!name || !st.objects.has(name)) continue;
      const t = new URL(String(d.photoUrl)).searchParams.get("token") ?? "";
      if (!st.tokens(name).includes(t)) broken.push(path);
    }
  };
  return {st, refs, broken};
}
let n = 0;
const opts = (o: Partial<Parameters<typeof rotatePhotoTokens>[2]> = {}) => ({
  runId: "rot1", bucket: BUCKET, now: NOW, newToken: () => `new-${++n}`, ...o,
});
const tokenIn = (u: unknown) => new URL(String(u)).searchParams.get("token");

describe("download-token rotation (two-phase, Phase 7D)", () => {
  test("URL helpers: SDK-style URL round-trips; other buckets and hosts are rejected", () => {
    const u = url(A1, "t");
    assert.equal(u, `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/completion_photos%2Falice%2F2026-01-01.jpg?alt=media&token=t`);
    assert.equal(objectNameFromUrl(u, BUCKET), A1);
    assert.equal(objectNameFromUrl(u, "other.appspot.com"), null);
    assert.equal(objectNameFromUrl(u.replace("firebasestorage.googleapis.com", "evil.example"), BUCKET), null);
    assert.equal(objectNameFromUrl(u.replace("https:", "http:"), BUCKET), null);
    assert.equal(objectNameFromUrl(42, BUCKET), null);
    assert.equal(objectNameFromUrl("not a url", BUCKET), null);
  });
  test("tokenTag identifies a token without revealing it", () => {
    assert.match(tokenTag(OLD), /^[0-9a-f]{16}$/);
    assert.ok(!OLD.includes(tokenTag(OLD)));
    assert.notEqual(tokenTag("a"), tokenTag("b"));
  });
  test("dry-run: writes nothing, downloads no photo content, counts the links it would update", async () => {
    const {st, refs} = world();
    const r = await rotatePhotoTokens(st, refs, opts());
    assert.equal(r.mode, "dry-run");
    assert.equal(r.counts["would-rotate"], 3);
    assert.equal(r.referencesUpdated, 4);
    assert.deepEqual(st.ops, [], "no patch, read or rewrite");
    assert.deepEqual(refs.updates, []);
  });
  test("anything other than mode \"execute\" is a dry-run", async () => {
    const {st, refs} = world();
    for (const mode of [undefined, "EXECUTE", "delete"]) {
      await rotatePhotoTokens(st, refs, opts({mode: mode as "execute"}));
    }
    assert.deepEqual(st.ops, []);
  });
  test("execute (metadata): add → links → remove; no content read or rewritten; one new token left", async () => {
    const {st, refs, broken} = world();
    const r = await rotatePhotoTokens(st, refs, opts({mode: "execute"}));
    assert.equal(r.counts.rotated, 3);
    assert.equal(r.referencesUpdated, 4);
    assert.equal(r.removeVia, "metadata");
    assert.deepEqual(st.ops.filter((o) => !o.startsWith("patch:")), [], "photo bytes untouched");
    assert.equal(st.ops.filter((o) => o === `patch:${A1}`).length, 2, "add, then remove");
    const tokens = st.tokens(A1);
    assert.equal(tokens.length, 1);
    assert.notEqual(tokens[0], OLD);
    assert.equal(st.objects.get(A1)!.info.metadata![ROTATION_STATE], "done");
    assert.equal(st.objects.get(A1)!.info.metadata![ROTATION_MARKER], "rot1");
    assert.equal(refs.docs.get("completions/alice_2026-01-01")!.photoUrl, url(A1, tokens[0]));
    assert.equal(refs.docs.get("users/alice/memories/alice_2026-01-01")!.photoUrl, url(A1, tokens[0]));
    assert.equal(tokenIn(refs.docs.get("completions/bob_2026-01-01")!.photoUrl), st.tokens(B1)[0]);
    assert.deepEqual(refs.queries, ["alice", "bob"], "references fetched once per user");
    assert.deepEqual(broken, [], "no link ever pointed at a dead token");
  });
  test("execute (rewrite): same result; bytes re-uploaded identically; no link ever broken", async () => {
    const {st, refs, broken} = world();
    const before = st.objects.get(A1)!.data;
    const r = await rotatePhotoTokens(st, refs, opts({mode: "execute", removeVia: "rewrite"}));
    assert.equal(r.counts.rotated, 3);
    assert.deepEqual(st.objects.get(A1)!.data, before);
    assert.equal(st.tokens(A1).length, 1);
    assert.notEqual(st.tokens(A1)[0], OLD);
    assert.equal(st.objects.get(A1)!.info.contentType, "image/jpeg");
    assert.equal(st.objects.get(A1)!.info.cacheControl, "private, max-age=300");
    assert.deepEqual(broken, []);
  });
  test("a backend that MERGES token lists (like the emulator) is detected: verify-failed, never \"rotated\"", async () => {
    const {st, refs, broken} = world();
    st.mergeTokens = true;
    const r = await rotatePhotoTokens(st, refs, opts({mode: "execute"}));
    assert.equal(r.counts["verify-failed"], 3);
    assert.equal(r.counts.rotated, undefined);
    assert.ok(r.entries.every((e) => e.detail === "old-token-still-present"));
    assert.ok(st.tokens(A1).includes(OLD), "old token still valid: reported, not hidden");
    assert.deepEqual(broken, [], "links use the new, valid token");
  });
  test("the report never carries tokens, token tags or URLs", async () => {
    const {st, refs} = world();
    const r = await rotatePhotoTokens(st, refs, opts({mode: "execute"}));
    const json = JSON.stringify(r);
    assert.doesNotMatch(json, /token=|new-\d|1111-|firebasestorage\.googleapis/);
    assert.ok(!json.includes(st.objects.get(A1)!.info.metadata![ROTATION_NEW]));
  });
  test("recent uploads are left for a later run (their completion may still be saving)", async () => {
    const {st, refs} = world();
    st.put(A1, OLD, new Date(NOW.getTime() - 60_000).toISOString());
    const r = await rotatePhotoTokens(st, refs, opts({mode: "execute"}));
    assert.equal(r.entries.find((e) => e.name === A1)!.outcome, "too-recent");
    assert.equal(refs.docs.get("completions/alice_2026-01-01")!.photoUrl, url(A1, OLD));
  });
  test("an unknown change time is treated as recent (skipped, never guessed)", async () => {
    const {st, refs} = world();
    st.put(A1, OLD, "");
    const r = await rotatePhotoTokens(st, refs, opts({mode: "execute"}));
    assert.equal(r.entries.find((e) => e.name === A1)!.outcome, "too-recent");
  });
  test("a photo changed just before the token is added is left alone", async () => {
    const {st, refs} = world();
    st.onBeforePatch = (name) => {
      st.onBeforePatch = undefined;
      st.put(name, "user-reupload");
    };
    const r = await rotatePhotoTokens(st, refs, opts({mode: "execute"}));
    assert.equal(r.counts["changed-during-rotation"], 1);
    assert.equal(r.counts.rotated, 2);
  });
  test("a photo deleted before the old token is removed (account deletion) is not recreated", async () => {
    const {st, refs} = world();
    const r = await rotatePhotoTokens(st, refs, opts({mode: "execute", removeVia: "rewrite",
      beforeRemove: async (name) => {
        if (name === B1) st.objects.delete(name);
      }}));
    assert.equal(r.entries.find((e) => e.name === B1)!.outcome, "changed-during-rotation");
    assert.equal(st.objects.has(B1), false);
  });
  test("a link changed meanwhile is left alone and counted", async () => {
    const {st, refs} = world();
    refs.onBeforeUpdate = (path) => {
      if (path === "users/alice/memories/alice_2026-01-01") refs.docs.get(path)!.photoUrl = "https://example.test/other.jpg";
    };
    const r = await rotatePhotoTokens(st, refs, opts({mode: "execute"}));
    assert.equal(r.entries.find((x) => x.name === A1)!.refsChanged, 1);
    assert.equal(refs.docs.get("users/alice/memories/alice_2026-01-01")!.photoUrl, "https://example.test/other.jpg");
  });
  test("link updates fail: the OLD token stays valid (nothing breaks); a resume reuses the same new token and finishes", async () => {
    const {st, refs, broken} = world();
    refs.failUpdate = true;
    const first = await rotatePhotoTokens(st, refs, opts({mode: "execute"}));
    assert.equal(first.counts["references-failed"], 3);
    assert.ok(st.tokens(A1).includes(OLD), "old token kept while links still use it");
    assert.equal(st.tokens(A1).length, 2);
    assert.equal(st.objects.get(A1)!.info.metadata![ROTATION_STATE], "added");
    const added = st.tokens(A1)[1];
    refs.failUpdate = false;
    const second = await rotatePhotoTokens(st, refs, opts({mode: "execute"}));
    assert.equal(second.counts.rotated, 3);
    assert.deepEqual(st.tokens(A1), [added], "no third token: the added one was reused");
    assert.equal(refs.docs.get("completions/alice_2026-01-01")!.photoUrl, url(A1, added));
    assert.deepEqual(broken, []);
  });
  test("interrupted after the old token was removed: a resume only finishes links, no more writes", async () => {
    const {st, refs} = world();
    await rotatePhotoTokens(st, refs, opts({mode: "execute"}));
    st.ops.length = 0;
    const again = await rotatePhotoTokens(st, refs, opts({mode: "execute"}));
    assert.equal(again.counts["references-updated"], 3);
    assert.equal(again.referencesUpdated, 0, "links were already current");
    assert.deepEqual(st.ops, []);
  });
  test("a resume whose recorded token can't be found stops for review (never guesses)", async () => {
    const {st, refs} = world();
    st.put(A1, `${OLD},x`, OLD_TIME, {[ROTATION_MARKER]: "rot1", [ROTATION_STATE]: "added", [ROTATION_NEW]: "0000000000000000"});
    const r = await rotatePhotoTokens(st, refs, opts({mode: "execute"}));
    const e = r.entries.find((x) => x.name === A1)!;
    assert.equal(e.outcome, "verify-failed");
    assert.equal(e.detail, "added-token-not-found");
    assert.ok(st.tokens(A1).includes(OLD));
  });
  test("a NEW run id rotates again (a deliberate second rotation)", async () => {
    const {st, refs} = world();
    await rotatePhotoTokens(st, refs, opts({mode: "execute"}));
    const t1 = st.tokens(A1)[0];
    await rotatePhotoTokens(st, refs, opts({mode: "execute", runId: "rot2"}));
    assert.notEqual(st.tokens(A1)[0], t1);
    assert.equal(st.tokens(A1).length, 1);
  });
  test("resume skips finished photos and keeps going (bounded runs)", async () => {
    const {st, refs} = world();
    const first = await rotatePhotoTokens(st, refs, opts({mode: "execute", maxObjects: 1}));
    assert.equal(first.counts.rotated, 1);
    assert.equal(first.limitReached, true);
    const skipNames = first.entries.filter((e) => ROTATION_FINAL.has(e.outcome)).map((e) => e.name);
    st.ops.length = 0;
    const second = await rotatePhotoTokens(st, refs, opts({mode: "execute", skipNames}));
    assert.equal(second.counts.rotated, 2);
    assert.ok(!st.ops.some((o) => o.endsWith(first.entries[0].name)));
  });
  test("photos without a token, odd names and unsafe uids are skipped, never written", async () => {
    const st = new TokenStore();
    st.put("completion_photos/alice/2026-03-01.jpg", "");
    st.put("completion_photos/alice/notes.txt");
    st.put("completion_photos/../2026-03-01.jpg");
    st.put("completion_photos/alice/sub/2026-03-01.jpg");
    const r = await rotatePhotoTokens(st, new Refs(), opts({mode: "execute"}));
    assert.deepEqual(r.counts, {"no-token": 1, "skipped-name": 3});
    assert.deepEqual(st.ops, []);
  });
  test("a content mismatch after a rewrite is verify-failed", async () => {
    const {st, refs} = world();
    const orig = st.rewriteIfGeneration.bind(st);
    st.rewriteIfGeneration = async (name, gen, data, info) => {
      const ok = await orig(name, gen, data, info);
      st.objects.get(name)!.info.md5Hash = "different";
      return ok;
    };
    const r = await rotatePhotoTokens(st, refs, opts({mode: "execute", removeVia: "rewrite"}));
    assert.equal(r.counts["verify-failed"], 3);
    assert.ok(r.entries.every((e) => e.detail === "content-changed"));
  });
  test("write errors are recorded per photo (step and error class only) and the run continues", async () => {
    const {st, refs} = world();
    st.failPatch = true;
    const r = await rotatePhotoTokens(st, refs, opts({mode: "execute"}));
    assert.equal(r.counts["rotate-failed"], 3);
    assert.ok(r.entries.every((e) => e.detail === "Error" && e.step === "add"));
    assert.deepEqual(refs.updates, []);
  });
  test("--uid scope (canary): only that user's photos and links are touched", async () => {
    const {st, refs} = world();
    const r = await rotatePhotoTokens(st, refs, opts({mode: "execute", uid: "bob"}));
    assert.deepEqual(r.entries.map((e) => e.name), [B1]);
    assert.ok(st.ops.every((o) => o.endsWith(B1)));
    assert.deepEqual(st.tokens(A1), [OLD]);
    assert.equal(refs.docs.get("completions/alice_2026-01-01")!.photoUrl, url(A1, OLD));
    const none = await rotatePhotoTokens(st, refs, opts({mode: "execute", uid: "ali"}));
    assert.equal(none.inspected, 0, "\"ali\" must not match \"alice/…\"");
    await assert.rejects(rotatePhotoTokens(st, refs, opts({uid: "a/b"})), /uid/);
  });
  test("dry-run aggregates (Phase 7E): photos without references, stale links, predicted writes", async () => {
    const {st, refs} = world();
    st.put("completion_photos/carol/2026-02-02.jpg"); // no document names it (orphan)
    refs.docs.set("users/alice/memories/stale", {uid: "alice", photoUrl: url(A2, "revoked-long-ago")});
    const r = await rotatePhotoTokens(st, refs, opts());
    assert.equal(r.counts["would-rotate"], 4);
    assert.equal(r.photosWithoutReferences, 1);
    assert.equal(r.photosWithStaleReferences, 1, "A2 has a link whose token the object doesn't accept");
    assert.deepEqual(r.writes, {metadataPatches: 8, objectRewrites: 0, linkUpdates: 5});
    assert.deepEqual(st.ops, [], "still a pure dry-run");
    const rw = await rotatePhotoTokens(st, refs, opts({removeVia: "rewrite"}));
    assert.deepEqual(rw.writes, {metadataPatches: 4, objectRewrites: 4, linkUpdates: 5});
  });
  test("execute counts the writes it actually made", async () => {
    const {st, refs} = world();
    const r = await rotatePhotoTokens(st, refs, opts({mode: "execute"}));
    assert.deepEqual(r.writes, {metadataPatches: 6, objectRewrites: 0, linkUpdates: 4});
    assert.equal(st.ops.filter((o) => o.startsWith("patch:")).length, 6);
  });
  test("--stop-before-remove (revocation experiment): both tokens valid, links moved; a re-run removes the old one", async () => {
    const {st, refs, broken} = world();
    const first = await rotatePhotoTokens(st, refs, opts({mode: "execute", uid: "alice", stopBeforeRemove: true}));
    assert.equal(first.counts["awaiting-removal"], 2);
    assert.equal(st.tokens(A1).length, 2);
    assert.ok(st.tokens(A1).includes(OLD), "old link still works at the pause");
    const added = st.tokens(A1)[1];
    assert.equal(refs.docs.get("completions/alice_2026-01-01")!.photoUrl, url(A1, added), "links already moved");
    assert.ok(!ROTATION_FINAL.has("awaiting-removal"), "a resume continues these photos");
    const second = await rotatePhotoTokens(st, refs, opts({mode: "execute", uid: "alice"}));
    assert.equal(second.counts.rotated, 2);
    assert.deepEqual(st.tokens(A1), [added], "same new token kept; old removed");
    assert.deepEqual(broken, []);
  });
  test("run id and bucket are validated", async () => {
    const {st, refs} = world();
    await assert.rejects(rotatePhotoTokens(st, refs, opts({runId: "../x"})));
    await assert.rejects(rotatePhotoTokens(st, refs, opts({bucket: "Bad/Bucket"})));
  });
});

describe("ops CLI — Phase 7C additions", () => {
  const emu = {FIRESTORE_EMULATOR_HOST: "127.0.0.1:8181", FIREBASE_STORAGE_EMULATOR_HOST: "127.0.0.1:9199"};
  test("token rotation is a writing command with the same real-project guards", () => {
    const base = ["photo-token-rotate", "--project", "touchgrass-today", "--real-project", "--out",
      "../ops-out/rotation/o.json"];
    assert.equal(refusal(parseArgs(base), {}), null, "dry-run allowed with --real-project and --out");
    assert.match(refusal(parseArgs(["photo-token-rotate", "--project", "touchgrass-today"]), {})!, /--real-project/);
    const exec = [...base, "--execute", "--mode", "production-mutation"];
    assert.match(refusal(parseArgs(exec), {})!, /--confirm-project/);
    assert.equal(refusal(parseArgs([...exec, "--confirm-project", "touchgrass-today"]), {}), null);
    assert.match(refusal(parseArgs(["photo-token-rotate", "--project", "demo-p1p1", "--execute", "--mode",
      "production-mutation"]), emu)!, /--out/);
  });
  test("--run-id is validated; --full-read only applies to the inventory", () => {
    assert.throws(() => parseArgs(["photo-token-rotate", "--project", "demo-p1p1", "--run-id", "a/b"]), /--run-id/);
    assert.equal(parseArgs(["photo-metadata-inventory", "--project", "demo-p1p1", "--full-read"]).fullRead, true);
    assert.match(refusal(parseArgs(["photo-token-rotate", "--project", "demo-p1p1", "--full-read"]), emu)!, /--full-read/);
  });
  test("resuming a rotation reuses its run id and skips finished photos", () => {
    const prev = {command: "photo-token-rotate", mode: "execute", runId: "rot1", entries: [
      {name: "a", outcome: "rotated"}, {name: "b", outcome: "references-failed"}, {name: "c", outcome: "too-recent"},
      {name: "d", outcome: "references-updated"}]};
    assert.deepEqual(resumeOptions("photo-token-rotate", prev), {runId: "rot1", skipNames: ["a", "d"]});
    assert.throws(() => resumeOptions("photo-token-rotate", {...prev, mode: "dry-run"}, true), /--execute/,
      "an execute run never resumes from a dry-run file");
    assert.throws(() => resumeOptions("photo-token-rotate", {...prev, runId: "../x"}), /run id/);
    const both = parseArgs(["photo-token-rotate", "--project", "demo-p1p1", "--resume", "o.json", "--run-id", "x"]);
    assert.match(refusal(both, emu)!, /drop --run-id/);
  });
  test("stdout summary of a rotation carries counts only", () => {
    const s = summary({runId: "rot1", mode: "execute", counts: {rotated: 2}, referencesUpdated: 3,
      entries: [{name: "completion_photos/alice/2026-01-01.jpg", outcome: "rotated"}]});
    assert.doesNotMatch(JSON.stringify(s), /completion_photos|alice/);
  });
  test("--uid is validated and only allowed where it scopes the work", () => {
    assert.equal(parseArgs(["photo-token-rotate", "--project", "demo-p1p1", "--uid", "TestUid_123"]).uid, "TestUid_123");
    assert.throws(() => parseArgs(["photo-token-rotate", "--project", "demo-p1p1", "--uid", "a/b"]), /--uid/);
    assert.match(refusal(parseArgs(["orphan-photos", "--project", "demo-p1p1", "--uid", "u1"]), emu)!, /--uid is only/);
    assert.equal(refusal(parseArgs(["photo-metadata-inventory", "--project", "demo-p1p1", "--uid", "u1"]), emu), null);
  });
  test("--remove-via is validated and only allowed for token rotation", () => {
    assert.equal(parseArgs(["photo-token-rotate", "--project", "demo-p1p1", "--remove-via", "rewrite"]).removeVia, "rewrite");
    assert.equal(parseArgs(["photo-token-rotate", "--project", "demo-p1p1"]).removeVia, undefined, "default chosen by the tool");
    assert.throws(() => parseArgs(["photo-token-rotate", "--project", "demo-p1p1", "--remove-via", "delete"]), /--remove-via/);
    assert.match(refusal(parseArgs(["orphan-photos", "--project", "demo-p1p1", "--remove-via", "metadata"]), emu)!, /--remove-via/);
    assert.equal(parseArgs(["photo-token-rotate", "--project", "demo-p1p1", "--stop-before-remove"]).stopBeforeRemove, true);
    assert.match(refusal(parseArgs(["orphan-photos", "--project", "demo-p1p1", "--stop-before-remove"]), emu)!,
      /--stop-before-remove/);
  });
  test("remediation and rotation share one lease", () => {
    assert.equal(PHOTO_REWRITE_LEASE, "_ops/photoRewrite_lease");
  });
});

describe("dry-run safety before the production inventory (Phase 7F)", () => {
  const real = ["--project", "touchgrass-today", "--real-project", "--out", "../ops-out/rotation/o.json"];
  test("a dry-run takes no lease, so it writes nothing at all in the project", () => {
    for (const cmd of ["photo-token-rotate", "photo-metadata-remediate", "orphan-photos", "photo-metadata-inventory",
      "profile-photo-inventory"]) {
      assert.equal(leaseFor(parseArgs([cmd, ...real])), null, cmd);
    }
    const exec = [...real, "--execute", "--mode", "production-mutation", "--confirm-project", "touchgrass-today"];
    assert.equal(leaseFor(parseArgs(["photo-token-rotate", ...exec]))!.path, PHOTO_REWRITE_LEASE);
    assert.equal(leaseFor(parseArgs(["photo-metadata-remediate", ...exec]))!.path, PHOTO_REWRITE_LEASE);
    assert.equal(leaseFor(parseArgs(["orphan-photos", ...exec]))!.path, "_ops/orphanPhotoCleanup_lease");
  });
  test("the look-alike project and foreign buckets are refused", () => {
    assert.match(refusal(parseArgs(["photo-token-rotate", ...real.slice(2), "--project", NOT_TOUCHGRASS[0]]), {})!,
      /not the TouchGrass project/);
    const withBucket = (b: string) => refusal(parseArgs(["photo-token-rotate", ...real, "--bucket", b]), {});
    assert.match(withBucket("gen-lang-client-0754598293.firebasestorage.app")!, /must be exactly/);
    assert.equal(withBucket("touchgrass-today.firebasestorage.app"), null);
    // Phase 7G: an exact allowlist — the legacy appspot name isn't the bucket.
    assert.match(withBucket("touchgrass-today.appspot.com")!, /must be exactly/);
  });
  test("a capped dry-run resumes where its listing stopped; an execute run can't use it", () => {
    const prev = {command: "photo-token-rotate", mode: "dry-run", nextPageToken: "cursor-1", entries: []};
    assert.deepEqual(resumeOptions("photo-token-rotate", prev), {pageToken: "cursor-1"});
    assert.throws(() => resumeOptions("photo-token-rotate", prev, true), /--execute/);
    assert.throws(() => resumeOptions("photo-token-rotate", {...prev, nextPageToken: undefined}), /nothing left/);
  });
  test("--max: a capped run says so; the cursor stays out of stdout", async () => {
    const {st, refs} = world();
    const r = await rotatePhotoTokens(st, refs, opts({maxObjects: 2, pageSize: 2}));
    assert.equal(r.inspected, 2);
    assert.equal(r.limitReached, true);
    assert.ok(r.nextPageToken, "the private file keeps the cursor");
    const s = summary({...r});
    assert.equal(s.limitReached, true);
    assert.match(String(s.moreRemaining), /--resume/);
    assert.equal(s.nextPageToken, undefined);
    const all = await rotatePhotoTokens(st, refs, opts({maxObjects: 3}));
    assert.equal(all.limitReached, false, "exactly the cap with nothing left is complete");
    assert.equal(all.nextPageToken, undefined);
  });
  test("link anomalies the rotation can't follow are counted once per user", async () => {
    const {st, refs} = world();
    refs.docs.set("users/alice/memories/foreign", {uid: "alice", photoUrl: url(B1, OLD)});
    refs.docs.set("users/alice/memories/elsewhere",
      {uid: "alice", photoUrl: downloadUrl("gen-lang-client-0754598293.firebasestorage.app", A1, OLD)});
    refs.docs.set("users/alice/memories/garbled", {uid: "alice", photoUrl: "content://local/photo.jpg"});
    refs.docs.set("users/alice/memories/notoken", {uid: "alice", photoUrl: url(A1, "").replace(/&token=$/, "")});
    refs.docs.set("users/alice/memories/nophoto", {uid: "alice", photoUrl: ""});
    const r = await rotatePhotoTokens(st, refs, opts());
    assert.deepEqual(r.referenceAnomalies, {otherOwnerPath: 1, otherBucketOrHost: 1, unparseable: 1, withoutToken: 1});
    assert.deepEqual(st.ops, []);
    assert.doesNotMatch(JSON.stringify(summary({...r})), /alice|bob|token=/);
  });
});

describe("revocation experiment harness (Phase 7F)", () => {
  test("verdict: revoked only when the old URL is refused in every sample while the new link works", () => {
    const ok = {old: 403, current: 200};
    assert.equal(interpretRevocation([ok, ok, ok]), "revoked");
    assert.equal(interpretRevocation([ok, {old: 404, current: 200}, ok]), "revoked");
    assert.equal(interpretRevocation([ok, {old: 200, current: 200}, ok]), "not-revoked", "one success is enough");
    assert.equal(interpretRevocation([{old: 200, current: 200}]), "not-revoked");
    assert.equal(interpretRevocation([ok, ok]), "inconclusive", "too few samples");
    assert.equal(interpretRevocation([ok, {old: 403, current: 503}, ok]), "inconclusive", "service unhealthy");
    assert.equal(interpretRevocation([ok, {old: "error", current: 200}, ok]), "inconclusive", "network error");
    assert.equal(interpretRevocation([ok, {old: 500, current: 200}, ok]), "inconclusive");
  });
  test("refusals: production only for touchgrass-today with --confirm-project; a stage is required", () => {
    const f = (o: Record<string, string>) => new Map(Object.entries(o));
    const emu = {FIRESTORE_EMULATOR_HOST: "h", FIREBASE_STORAGE_EMULATOR_HOST: "h", FIREBASE_AUTH_EMULATOR_HOST: "h"};
    const m = {mode: "test-object-mutation"};
    assert.match(experimentRefusal("setup", f({state: "s", project: "touchgrass-today", ...m}), {})!, /confirm-project/);
    assert.equal(experimentRefusal("setup", f({state: "s", project: "touchgrass-today", "confirm-project": "touchgrass-today",
      ...m}), {}), null);
    // Phase 7G: production setup/cleanup must declare the test-object mode.
    assert.match(experimentRefusal("setup", f({state: "s", project: "touchgrass-today",
      "confirm-project": "touchgrass-today"}), {})!, /--mode test-object-mutation/);
    assert.match(experimentRefusal("cleanup", f({state: "s"}), {})!, /--mode test-object-mutation/);
    assert.equal(experimentRefusal("cleanup", f({state: "s", ...m}), {}), null);
    assert.equal(experimentRefusal("probe", f({state: "s", stage: "before"}), {}), null, "probe only reads");
    // Mixed or non-demo emulator environments are refused.
    assert.match(experimentRefusal("probe", f({state: "s", stage: "before"}), {FIRESTORE_EMULATOR_HOST: "h"})!, /mix/);
    assert.match(experimentRefusal("setup", f({state: "s", project: "touchgrass-today"}), emu)!, /demo-/);
    assert.match(experimentRefusal("setup", f({state: "s", project: "gen-lang-client-0754598293",
      "confirm-project": "gen-lang-client-0754598293", ...m}), {})!, /Only touchgrass-today/);
    assert.equal(experimentRefusal("setup", f({state: "s", project: "demo-x"}), emu), null, "rehearsal");
    assert.match(experimentRefusal("probe", f({state: "s"}), emu)!, /--stage/);
    assert.match(experimentRefusal("rotate", f({state: "s"}), emu)!, /setup, probe or cleanup/);
    assert.match(experimentRefusal("cleanup", f({}), emu)!, /--state/);
  });
  test("the record kept after cleanup has no passwords or tokens", () => {
    const st = {ownerPassword: "pw1", otherPassword: "pw2", oldToken: "tok", ownerUid: "u", probes: []} as unknown as ExperimentState;
    const r = JSON.stringify(redactState(st));
    assert.doesNotMatch(r, /pw1|pw2|tok"/);
    assert.match(r, /"ownerUid":"u"/);
  });
});
