/**
 * Unit tests for the Phase 6 operator tools: JPEG metadata stripping,
 * historical-photo inventory/remediation (fakes), profile-photo inventory,
 * and the CLI safety guard. Real Storage/Firestore behavior is covered by
 * ops.emulator.test.ts.
 */
import {test, describe} from "node:test";
import assert from "node:assert/strict";
import {
  hasRemovableMetadata, inspectJpeg, orientationOnlyExif, stripJpegMetadata, validateStripped,
} from "./jpegMetadata";
import {
  FINAL_OUTCOMES, InventoryItem, ObjectInfo, PhotoStoreDeps, backupPathFor, inventoryPhotoMetadata,
  remediatePhotoMetadata,
} from "./photoMetadataJob";
import {metadataBackupPrefix} from "../accountDeletion";
import {classifyProfilePhoto, inventoryProfilePhotos} from "./profilePhotoInventory";
import {parseArgs, refusal, resumeOptions, summary} from "./opsCli";
import {ascii, exifSegment, jpeg, seg} from "./testJpeg";

const text = (b: Uint8Array) => Buffer.from(b).toString("latin1");

describe("jpegMetadata — inspect", () => {
  test("finds EXIF, GPS, orientation, XMP and comments", () => {
    const m = inspectJpeg(jpeg({jfif: true, exif: exifSegment({orientation: 6, gps: true}), xmp: true, comment: true}));
    assert.equal(m.kind, "jpeg");
    assert.equal(m.exif, true);
    assert.equal(m.gps, true);
    assert.equal(m.orientation, 6);
    assert.equal(m.xmp, true);
    assert.equal(m.otherMetadata, true);
  });
  test("an EXIF block with only an orientation tag is not removable metadata; one with more is", () => {
    assert.equal(hasRemovableMetadata(inspectJpeg(jpeg({exif: Array.from(orientationOnlyExif(6))}))), false);
    assert.equal(hasRemovableMetadata(inspectJpeg(jpeg({exif: exifSegment({orientation: 6})}))), true);
    const two = [...Array.from(orientationOnlyExif(6)), ...Array.from(orientationOnlyExif(6))];
    assert.equal(hasRemovableMetadata(inspectJpeg(jpeg({exif: two}))), true, "duplicate EXIF");
  });
  test("EXIF without GPS is not reported as GPS", () => {
    const m = inspectJpeg(jpeg({exif: exifSegment({})}));
    assert.equal(m.exif, true);
    assert.equal(m.gps, false);
  });
  test("a clean JPEG (JFIF + ICC only) has nothing to remove", () => {
    const m = inspectJpeg(jpeg({jfif: true, icc: true}));
    assert.equal(hasRemovableMetadata(m), false);
  });
  test("non-JPEG, malformed and cut-off inputs are classified, never thrown", () => {
    assert.equal(inspectJpeg(Uint8Array.from([0x89, 0x50, 0x4e, 0x47])).kind, "not-jpeg");
    assert.equal(inspectJpeg(Uint8Array.from([0xff, 0xd8, 0x00, 0x00])).kind, "malformed");
    const full = jpeg({exif: exifSegment({gps: true})});
    assert.equal(inspectJpeg(full.subarray(0, 30)).kind, "incomplete-header");
    assert.equal(inspectJpeg(new Uint8Array(0)).kind, "not-jpeg");
  });
  test("an EXIF block with a broken GPS pointer counts as possible GPS", () => {
    const e = exifSegment({gps: true});
    e.length -= 18; // drop the GPS sub-IFD the pointer refers to
    e[2] = (e.length - 2) >> 8;
    e[3] = (e.length - 2) & 0xff;
    assert.equal(inspectJpeg(jpeg({exif: e})).gps, true);
  });
});

describe("jpegMetadata — strip and validate", () => {
  test("removes EXIF/GPS, XMP, comments and vendor APPn; keeps JFIF and ICC; image data identical", () => {
    const original = jpeg({jfif: true, exif: exifSegment({gps: true}), xmp: true, comment: true, icc: true, app5: true});
    const out = stripJpegMetadata(original)!;
    assert.equal(validateStripped(original, out), null);
    const m = inspectJpeg(out);
    assert.equal(m.exif || m.gps || m.xmp || m.otherMetadata, false);
    assert.doesNotMatch(text(out), /GPSLatitude|30\.2,-97\.7|Cam\0|vendor/);
    assert.match(text(out), /JFIF/);
    assert.match(text(out), /ICC_PROFILE/);
    assert.ok(out.length < original.length);
  });
  for (let o = 2; o <= 8; o++) {
    test(`orientation ${o} is kept (orientation-only EXIF), everything else removed`, () => {
      const original = jpeg({jfif: true, exif: exifSegment({orientation: o, gps: true})});
      const out = stripJpegMetadata(original)!;
      assert.equal(validateStripped(original, out), null);
      const m = inspectJpeg(out);
      assert.equal(m.orientation, o);
      assert.equal(m.gps, false);
      assert.equal(m.exifOrientationOnly, true);
      assert.equal(hasRemovableMetadata(m), false, "nothing left to remove");
      assert.doesNotMatch(text(out), /Cam\0/);
    });
  }
  test("orientation 1 needs no EXIF at all", () => {
    const out = stripJpegMetadata(jpeg({exif: exifSegment({orientation: 1, gps: true})}))!;
    assert.equal(inspectJpeg(out).exif, false);
  });
  test("stripping is idempotent", () => {
    const once = stripJpegMetadata(jpeg({exif: exifSegment({orientation: 3, gps: true}), xmp: true}))!;
    const twice = stripJpegMetadata(once)!;
    assert.deepEqual(twice, once);
  });
  test("refuses incomplete or malformed input", () => {
    assert.equal(stripJpegMetadata(jpeg({exif: exifSegment({gps: true})}).subarray(0, 30)), null);
    assert.equal(stripJpegMetadata(Uint8Array.from([1, 2, 3])), null);
  });
  test("validation catches a replacement that changes image data or keeps GPS", () => {
    const original = jpeg({exif: exifSegment({gps: true})});
    const good = stripJpegMetadata(original)!;
    const tampered = Uint8Array.from(good);
    tampered[tampered.length - 4] ^= 0x01;
    assert.equal(validateStripped(original, tampered), "image-data-changed");
    assert.equal(validateStripped(original, original), "metadata-remains");
    assert.equal(validateStripped(original, Uint8Array.from([0xff, 0xd8])), "not-a-complete-jpeg");
  });
  test("orientationOnlyExif refuses invalid orientations", () => {
    assert.throws(() => orientationOnlyExif(0));
    assert.throws(() => orientationOnlyExif(9));
  });
});

// ── Inventory / remediation with an in-memory store ─────────────────────────

class FakeStore implements PhotoStoreDeps {
  objects = new Map<string, {data: Uint8Array; gen: number; info: ObjectInfo}>();
  reads: string[] = [];
  writes: string[] = [];
  copies: string[] = [];
  failRead = new Set<string>();
  failWrite = false;
  onBeforeWrite?: (name: string) => void;
  put(name: string, data: Uint8Array, token = "tok-1") {
    const prev = this.objects.get(name);
    const gen = (prev?.gen ?? 100) + 1;
    this.objects.set(name, {data, gen, info: {name, generation: gen, contentType: "image/jpeg",
      cacheControl: "private, max-age=300", metadata: {firebaseStorageDownloadTokens: token}}});
  }
  async listPage(prefix: string, max: number, token?: string) {
    const all = [...this.objects.keys()].filter((k) => k.startsWith(prefix)).sort();
    const start = token ? Number(token) : 0;
    const files = all.slice(start, start + max).map((k) => ({...this.objects.get(k)!.info}));
    return {files, nextPageToken: start + max < all.length ? String(start + max) : undefined};
  }
  private at(name: string, gen: string | number) {
    if (this.failRead.has(name)) throw new Error("read failed");
    const o = this.objects.get(name);
    if (!o || String(o.gen) !== String(gen)) throw Object.assign(new Error("not found"), {code: 404});
    return o;
  }
  async readHead(name: string, gen: string | number, n: number) {
    this.reads.push(`head:${name}`);
    return this.at(name, gen).data.subarray(0, n);
  }
  async readAll(name: string, gen: string | number) {
    this.reads.push(`all:${name}`);
    return this.at(name, gen).data;
  }
  async getInfo(name: string) {
    const o = this.objects.get(name);
    return o ? {...o.info, metadata: {...o.info.metadata}} : null;
  }
  async saveBackup(dest: string, data: Uint8Array, info: ObjectInfo) {
    this.copies.push(dest);
    // Same contract as adminPhotoStore: a new object without a download token.
    this.objects.set(dest, {data, gen: 1, info: {name: dest, generation: 1, contentType: info.contentType, metadata: {}}});
  }
  deleted: string[] = [];
  async deleteBackup(dest: string) {
    this.deleted.push(dest);
    this.objects.delete(dest);
  }
  async writeIfGeneration(name: string, gen: string | number, data: Uint8Array, info: ObjectInfo) {
    this.onBeforeWrite?.(name);
    if (this.failWrite) throw new Error("503");
    const o = this.objects.get(name);
    if (!o || String(o.gen) !== String(gen)) return false;
    this.writes.push(name);
    const next = o.gen + 1;
    this.objects.set(name, {data, gen: next, info: {...info, generation: next}});
    return true;
  }
}

const P = (uid: string, d: string) => `completion_photos/${uid}/${d}.jpg`;

function seeded(): FakeStore {
  const s = new FakeStore();
  s.put(P("alice", "2026-01-01"), jpeg({jfif: true, exif: exifSegment({orientation: 6, gps: true})}));
  s.put(P("alice", "2026-01-02"), jpeg({jfif: true})); // clean
  s.put(P("bob", "2026-01-01"), jpeg({xmp: true})); // XMP only
  s.put(P("bob", "1700000000000"), jpeg({exif: exifSegment({gps: true})})); // legacy name
  s.put("completion_photos/bob/notes.txt", Uint8Array.from(ascii("hello")));
  s.put(P("carol", "2026-01-03"), Uint8Array.from(ascii("PNG?")));
  return s;
}

describe("photo metadata inventory (read-only)", () => {
  test("counts every category and writes nothing", async () => {
    const s = seeded();
    const r = await inventoryPhotoMetadata(s);
    assert.equal(r.inspected, 6);
    assert.deepEqual(r.counts, {"gps": 2, "clean": 1, "other-metadata": 1, "skipped-name": 1, "not-jpeg": 1});
    assert.equal(r.needsRemediation, 3);
    assert.deepEqual(s.writes, []);
    assert.deepEqual(s.copies, []);
    assert.ok(s.reads.every((x) => x.startsWith("head:")), "inventory reads headers only");
  });
  test("the report never contains coordinates or image bytes", async () => {
    const r = await inventoryPhotoMetadata(seeded());
    assert.doesNotMatch(JSON.stringify(r), /30,15N|30\.2|GPSLatitude|xmpmeta/);
  });
  test("a per-object read failure is counted and the scan continues", async () => {
    const s = seeded();
    s.failRead.add(P("alice", "2026-01-01"));
    const r = await inventoryPhotoMetadata(s);
    assert.equal(r.counts.unreadable, 1);
    assert.equal(r.inspected, 6);
  });
  test("paginates and resumes", async () => {
    const s = seeded();
    const a = await inventoryPhotoMetadata(s, {pageSize: 2, maxObjects: 3});
    assert.equal(a.inspected, 3);
    assert.equal(a.limitReached, true);
    const b = await inventoryPhotoMetadata(s, {pageSize: 2, pageToken: a.nextPageToken});
    assert.equal(a.inspected + b.inspected, 6);
  });
  test("a header longer than the read window is flagged for a full read", async () => {
    const s = new FakeStore();
    const big = seg(0xe0, [...ascii("JFIF\0"), ...Array(3000).fill(0)]);
    s.put(P("dan", "2026-01-01"), Uint8Array.from([0xff, 0xd8, ...big, ...jpeg().subarray(2)]));
    const r = await inventoryPhotoMetadata(s, {headBytes: 1024});
    assert.equal(r.counts["header-beyond-read"], 1);
  });
});

describe("photo metadata remediation", () => {
  const items = async (s: FakeStore): Promise<InventoryItem[]> => (await inventoryPhotoMetadata(s)).items;

  test("dry-run validates replacements but writes and copies nothing", async () => {
    const s = seeded();
    const r = await remediatePhotoMetadata(s, await items(s), {runId: "r1", backup: true});
    assert.equal(r.mode, "dry-run");
    assert.equal(r.counts["would-rewrite"], 3);
    assert.deepEqual(s.writes, []);
    assert.deepEqual(s.copies, []);
  });
  test("anything other than mode \"execute\" is a dry-run", async () => {
    const s = seeded();
    for (const mode of [undefined, "EXECUTE", "delete"]) {
      await remediatePhotoMetadata(s, await items(s),
        {runId: "r1", backup: false, mode: mode as "execute"});
    }
    assert.deepEqual(s.writes, []);
  });
  test("execute: backs up, rewrites in place, keeps the download token and content type, and verifies", async () => {
    const s = seeded();
    const before = s.objects.get(P("alice", "2026-01-01"))!;
    const r = await remediatePhotoMetadata(s, await items(s), {runId: "r1", backup: true, mode: "execute"});
    assert.equal(r.counts.rewritten, 3);
    const after = s.objects.get(P("alice", "2026-01-01"))!;
    assert.equal(after.info.metadata?.firebaseStorageDownloadTokens, "tok-1");
    assert.equal(after.info.contentType, "image/jpeg");
    assert.equal(after.info.cacheControl, "private, max-age=300");
    const m = inspectJpeg(after.data);
    assert.equal(m.gps, false);
    assert.equal(m.orientation, 6, "still displays upright");
    assert.equal(validateStripped(before.data, after.data), null);
    // Reversible: the original is in the per-user, server-only backup
    // path (deleted with the account), with no download token.
    const backup = "metadata_backup/completion_photos/alice/r1/2026-01-01.jpg";
    assert.ok(s.copies.includes(backup));
    assert.deepEqual(s.objects.get(backup)!.data, before.data);
    assert.equal(s.objects.get(backup)!.info.metadata?.firebaseStorageDownloadTokens, undefined);
    // Clean photos and non-photos are untouched.
    assert.ok(!s.writes.includes(P("alice", "2026-01-02")));
    assert.ok(!s.writes.includes("completion_photos/bob/notes.txt"));
  });
  test("a photo replaced since the inventory is never overwritten", async () => {
    const s = seeded();
    const inv = await items(s);
    s.put(P("alice", "2026-01-01"), jpeg({jfif: true}), "tok-2"); // user re-uploaded
    const r = await remediatePhotoMetadata(s, inv, {runId: "r1", backup: false, mode: "execute"});
    assert.equal(r.entries.find((e) => e.name === P("alice", "2026-01-01"))!.outcome, "changed-since-inventory");
  });
  test("a photo replaced between the check and the write is not overwritten", async () => {
    const s = seeded();
    const inv = await items(s);
    s.onBeforeWrite = (name) => s.put(name, jpeg({jfif: true}), "tok-new");
    const r = await remediatePhotoMetadata(s, inv, {runId: "r1", backup: false, mode: "execute"});
    assert.equal(r.counts["changed-since-inventory"], 3);
    assert.deepEqual(s.writes, []);
  });
  test("a deleted photo is reported as gone", async () => {
    const s = seeded();
    const inv = await items(s);
    s.objects.delete(P("bob", "2026-01-01"));
    const r = await remediatePhotoMetadata(s, inv, {runId: "r1", backup: false, mode: "execute"});
    assert.equal(r.entries.find((e) => e.name === P("bob", "2026-01-01"))!.outcome, "gone");
  });
  test("write failures are recorded per object and the run continues", async () => {
    const s = seeded();
    s.failWrite = true;
    const r = await remediatePhotoMetadata(s, await items(s), {runId: "r1", backup: false, mode: "execute"});
    assert.equal(r.counts["write-failed"], 3);
  });
  test("re-running after success changes nothing", async () => {
    const s = seeded();
    await remediatePhotoMetadata(s, await items(s), {runId: "r1", backup: false, mode: "execute"});
    s.writes.length = 0;
    const again = await remediatePhotoMetadata(s, await items(s), {runId: "r2", backup: false, mode: "execute"});
    assert.deepEqual(s.writes, []);
    assert.equal(again.entries.length, 0, "nothing left that needs remediation");
  });
  test("backups live under the owner's account-deletion prefix", () => {
    assert.equal(backupPathFor(P("bob", "1700000000000"), "run-7"),
      "metadata_backup/completion_photos/bob/run-7/1700000000000.jpg");
    assert.ok(backupPathFor(P("bob", "2026-01-01"), "r").startsWith(metadataBackupPrefix("bob")));
    assert.throws(() => backupPathFor("user_avatars/bob.png", "r"));
  });
  test("an interrupted run resumes: finished photos are skipped, the rest completed", async () => {
    const s = seeded();
    const inv = await items(s);
    const first = await remediatePhotoMetadata(s, inv, {runId: "r1", backup: true, mode: "execute", maxObjects: 1});
    assert.equal(first.counts.rewritten, 1);
    const skipNames = first.entries.filter((e) => FINAL_OUTCOMES.has(e.outcome)).map((e) => e.name);
    s.writes.length = 0;
    const second = await remediatePhotoMetadata(s, inv, {runId: "r1", backup: true, mode: "execute", skipNames});
    assert.equal(second.counts.rewritten, 2);
    assert.ok(!s.writes.includes(first.entries[0].name), "the finished photo is not touched again");
    assert.equal((await inventoryPhotoMetadata(s)).needsRemediation, 0);
  });
  test("a failure after the backup copy is retried cleanly on the next run", async () => {
    const s = seeded();
    const inv = await items(s);
    s.failWrite = true; // e.g. connection lost right after the backup copy
    const first = await remediatePhotoMetadata(s, inv, {runId: "r1", backup: true, mode: "execute"});
    assert.equal(first.counts["write-failed"], 3);
    assert.deepEqual(s.writes, [], "nothing was overwritten");
    s.failWrite = false;
    const second = await remediatePhotoMetadata(s, inv, {runId: "r1", backup: true, mode: "execute"});
    assert.equal(second.counts.rewritten, 3, "same generations, so the retry proceeds");
  });
  test("bounded by maxObjects, and the run id is validated", async () => {
    const s = seeded();
    const r = await remediatePhotoMetadata(s, await items(s), {runId: "r1", backup: false, maxObjects: 1});
    assert.equal(r.entries.length, 1);
    await assert.rejects(remediatePhotoMetadata(s, [], {runId: "../x", backup: false}));
  });
});

describe("profile photo inventory", () => {
  const avatar = (uid: string, bucket = "touchgrass-today.firebasestorage.app") =>
    `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/user_avatars%2F${uid}.png?alt=media&token=t`;
  test("classifies stored values like the rules do", () => {
    assert.equal(classifyProfilePhoto(null, "a"), "none");
    assert.equal(classifyProfilePhoto(avatar("a"), "a"), "own-avatar");
    assert.equal(classifyProfilePhoto("https://lh3.googleusercontent.com/a/x", "a"), "google-photo");
    assert.equal(classifyProfilePhoto(avatar("b"), "a"), "external");
    assert.equal(classifyProfilePhoto(avatar("a", "evil.appspot.com"), "a"), "external");
    assert.equal(classifyProfilePhoto("https://evil.example/p.png", "a"), "external");
    assert.equal(classifyProfilePhoto("http://lh3.googleusercontent.com/a/x", "a"), "external");
    assert.equal(classifyProfilePhoto("not a url", "a"), "malformed");
    assert.equal(classifyProfilePhoto(42, "a"), "malformed");
    assert.equal(classifyProfilePhoto("", "a"), "malformed");
  });
  test("pages through users and reports counts (uids kept for the operator file only)", async () => {
    const users = Array.from({length: 7}, (_, i) => ({id: `u${i}`,
      photoUrl: i % 3 === 0 ? null : i % 3 === 1 ? avatar(`u${i}`) : "https://evil.example/x"}));
    const pages: number[] = [];
    const r = await inventoryProfilePhotos({
      async listUsers(limit, after) {
        pages.push(limit);
        const start = after ? users.findIndex((u) => u.id === after) + 1 : 0;
        return users.slice(start, start + limit);
      },
    }, {pageSize: 3});
    assert.equal(r.inspected, 7);
    assert.deepEqual(r.counts, {"none": 3, "own-avatar": 2, "external": 2});
    assert.deepEqual(r.uids.external, ["u2", "u5"]);
    assert.equal(r.uids["own-avatar"], undefined, "legitimate photos are counted, never listed");
    assert.deepEqual(pages, [3, 3, 3]);
  });
});

describe("ops CLI safety", () => {
  const emu = {FIRESTORE_EMULATOR_HOST: "127.0.0.1:8181", FIREBASE_STORAGE_EMULATOR_HOST: "127.0.0.1:9199"};
  test("parses commands and refuses unknown ones or options", () => {
    assert.equal(parseArgs(["orphan-photos", "--project", "touchgrass-today"]).execute, false);
    assert.throws(() => parseArgs(["drop-everything", "--project", "x-y-z1"]));
    assert.throws(() => parseArgs(["orphan-photos", "--project", "touchgrass-today", "--force"]));
    assert.throws(() => parseArgs(["orphan-photos"]), /--project/);
    assert.throws(() => parseArgs(["orphan-photos", "--project", "demo-p1p1", "--max", "-5"]));
  });
  test("a real project needs --real-project even for read-only commands", () => {
    const a = parseArgs(["photo-metadata-inventory", "--project", "touchgrass-today"]);
    assert.match(refusal(a, {})!, /--real-project/);
    // Phase 7G: the emulators only with a demo- project id.
    assert.match(refusal(a, emu)!, /demo-/);
    assert.equal(refusal(parseArgs(["photo-metadata-inventory", "--project", "demo-p1p1"]), emu), null);
    assert.match(refusal(parseArgs(["photo-metadata-inventory", "--project", "touchgrass-today", "--real-project"]), {})!,
      /--out/, "a real-project run must write its findings to a private file");
    assert.equal(refusal(parseArgs(["photo-metadata-inventory", "--project", "touchgrass-today", "--real-project",
      "--out", "../ops-out/metadata/inv.json"]), {}), null);
  });
  test("writing to a real project needs --execute AND a matching --confirm-project", () => {
    const base = ["orphan-photos", "--project", "touchgrass-today", "--real-project", "--execute",
      "--mode", "production-mutation", "--out", "../ops-out/cleanup/o.json"];
    assert.match(refusal(parseArgs(base), {})!, /--confirm-project/);
    assert.match(refusal(parseArgs([...base, "--confirm-project", "other-proj"]), {})!, /--confirm-project/);
    assert.equal(refusal(parseArgs([...base, "--confirm-project", "touchgrass-today"]), {}), null);
  });
  test("read-only commands refuse --execute; writes must record outcomes", () => {
    assert.match(refusal(parseArgs(["profile-photo-inventory", "--project", "demo-p1p1", "--execute"]), emu)!, /read-only/);
    assert.match(refusal(parseArgs(["orphan-photos", "--project", "demo-p1p1", "--execute", "--mode",
      "production-mutation"]), emu)!, /--out/);
    assert.match(refusal(parseArgs(["photo-metadata-remediate", "--project", "demo-p1p1"]), emu)!, /--manifest/);
  });
  test("stdout summary never carries names, uids or resume cursors", () => {
    const s = summary({inspected: 3, counts: {gps: 1}, items: [{name: "completion_photos/u/x.jpg"}],
      uids: {external: ["u1"]}, nextPageToken: "Q09NUExFVElPTl9QSE9UT1MvdTE=", nextStartAfter: "u9"});
    const text = JSON.stringify(s);
    assert.doesNotMatch(text, /completion_photos|u1|u9|Q09N/);
    assert.match(String(s.moreRemaining), /--resume/);
    assert.equal(summary({inspected: 1}).moreRemaining, undefined);
  });
  test("--resume continues from the previous run's private file", () => {
    assert.deepEqual(resumeOptions("photo-metadata-inventory", {command: "photo-metadata-inventory", nextPageToken: "t1"}),
      {pageToken: "t1"});
    assert.deepEqual(resumeOptions("profile-photo-inventory", {command: "profile-photo-inventory", nextStartAfter: "u5"}),
      {startAfter: "u5"});
    assert.deepEqual(resumeOptions("photo-metadata-remediate", {command: "photo-metadata-remediate", entries: [
      {name: "a", outcome: "rewritten"}, {name: "b", outcome: "write-failed"}, {name: "c", outcome: "already-clean"},
      {name: "d", outcome: "would-rewrite"}]}), {skipNames: ["a", "c"]});
    assert.throws(() => resumeOptions("orphan-photos", {command: "photo-metadata-inventory", nextPageToken: "t"}), /not "orphan-photos"/);
    assert.throws(() => resumeOptions("orphan-photos", {command: "orphan-photos"}), /nothing left/);
    const both = parseArgs(["orphan-photos", "--project", "demo-p1p1", "--resume", "o.json", "--page-token", "t"]);
    assert.match(refusal(both, emu)!, /either --resume/);
  });
});
