/**
 * Phase 7G: proof that every operator command's dry-run is read-only.
 *
 * Each command runs through the real `runCommand` (the same dispatch the
 * CLI uses, Admin adapters included) against fakes that expose ONLY an
 * explicit allowlist of read methods. Any other method — set, update,
 * delete, runTransaction (leases), batch, save, setMetadata, deleteFiles,
 * copy, … — is recorded and throws. A control test shows the same guard
 * does catch writes when `--execute` is used, so "no violations" means
 * something.
 */
import {test, describe} from "node:test";
import assert from "node:assert/strict";
import {execFileSync} from "node:child_process";
import {existsSync, mkdtempSync, rmSync, writeFileSync} from "node:fs";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {
  type OpsClients, OPS_OUT_DIR, adcWellKnownFile, credentialsRefusal, environmentRefusal, forOutFile, insideOpsOut,
  parseArgs, refusal, resumeOptions, runCommand, safeErrorLabel,
} from "./opsCli";
import {downloadUrl} from "./photoTokenRotation";
import {exifSegment, jpeg} from "./testJpeg";

const BUCKET = "touchgrass-today.firebasestorage.app";
const NOW = new Date("2026-10-21T12:00:00Z");
const OLD = "2026-09-01T00:00:00Z";

const BUCKET_READS = new Set(["name", "getFiles", "file"]);
const FILE_READS = new Set(["name", "getMetadata", "download", "exists"]);
const DB_READS = new Set(["collection", "doc", "getAll"]);
const QUERY_READS = new Set(["where", "select", "orderBy", "limit", "startAfter", "get"]);
const DOC_READS = new Set(["path", "id", "get"]);

/** Wraps [target] so only [reads] are usable; anything else is a violation. */
function guarded<T extends object>(target: T, label: string, reads: Set<string>, log: string[]): T {
  return new Proxy(target, {
    get(t, prop, recv) {
      if (typeof prop !== "string") return Reflect.get(t, prop, recv);
      if (prop === "then") return undefined; // not a promise
      if (!reads.has(prop)) {
        return () => {
          log.push(`${label}.${prop}`);
          throw new Error(`write attempted: ${label}.${prop}`);
        };
      }
      const v = Reflect.get(t, prop, recv);
      return typeof v === "function" ? v.bind(t) : v;
    },
  });
}

interface Obj {data: Uint8Array; meta: Record<string, unknown>}

function world(opts: {failMetadataFor?: string; failDownload?: boolean} = {}) {
  const log: string[] = [];
  const objects = new Map<string, Obj>();
  const put = (name: string, data: Uint8Array, token = "tok-1") => objects.set(name, {data, meta: {
    name, generation: "101", metageneration: "1", md5Hash: `md5-${name}`, updated: OLD, timeCreated: OLD,
    contentType: name.endsWith(".png") ? "image/png" : "image/jpeg", metadata: {firebaseStorageDownloadTokens: token},
  }});
  put("completion_photos/alice/2026-09-01.jpg", jpeg({jfif: true, exif: exifSegment({gps: true})}));
  put("completion_photos/alice/1700000000000.jpg", jpeg({jfif: true}));
  put("completion_photos/bob/2026-09-02.jpg", jpeg({xmp: true}));
  put("completion_photos/orphan/2026-08-01.jpg", jpeg({jfif: true}));
  put("user_avatars/alice.png", Uint8Array.from([0x89, 0x50, 0x4e, 0x47]));

  const docs = new Map<string, Record<string, unknown>>([
    ["users/alice", {photoUrl: "https://lh3.googleusercontent.com/a/x", email: "secret@example.test"}],
    ["users/bob", {photoUrl: null}],
    ["completions/alice_2026-09-01", {userId: "alice", photoUrl: downloadUrl(BUCKET, "completion_photos/alice/2026-09-01.jpg", "tok-1")}],
    ["completions/bob_2026-09-02", {userId: "bob", photoUrl: downloadUrl(BUCKET, "completion_photos/bob/2026-09-02.jpg", "tok-1")}],
    ["users/alice/memories/2026-09-01", {photoUrl: downloadUrl(BUCKET, "completion_photos/alice/2026-09-01.jpg", "tok-1")}],
  ]);

  const fileOf = (name: string) => guarded({
    name,
    async getMetadata() {
      if (opts.failMetadataFor === name) throw Object.assign(new Error("503"), {code: 503});
      const o = objects.get(name);
      if (!o) throw Object.assign(new Error("404"), {code: 404});
      return [{...o.meta}];
    },
    async download(o?: {start?: number; end?: number}) {
      if (opts.failDownload) throw Object.assign(new Error("503"), {code: 503});
      const d = objects.get(name)!.data;
      return [Buffer.from(o?.end !== undefined ? d.slice(o.start ?? 0, o.end + 1) : d)];
    },
    async exists() {
      return [objects.has(name)];
    },
  }, `file(${name})`, FILE_READS, log);

  const bucket = guarded({
    name: BUCKET,
    async getFiles(q: {prefix: string; maxResults: number; pageToken?: string}) {
      const all = [...objects.keys()].filter((k) => k.startsWith(q.prefix)).sort();
      const start = q.pageToken ? Number(q.pageToken) : 0;
      const page = all.slice(start, start + q.maxResults);
      const next = start + q.maxResults < all.length ? {pageToken: String(start + q.maxResults)} : null;
      return [page.map((n) => ({name: n, metadata: {...objects.get(n)!.meta}})), next];
    },
    file: (name: string) => fileOf(name),
  }, "bucket", BUCKET_READS, log);

  const snap = (path: string) => {
    const d = docs.get(path);
    return {id: path.split("/").pop()!, ref: {path}, exists: d !== undefined, get: (f: string) => d?.[f]};
  };
  const query = (coll: string, filter?: [string, unknown], after?: string, limit?: number): object => guarded({
    where: (f: string, _op: string, v: unknown) => query(coll, [f, v], after, limit),
    select: () => query(coll, filter, after, limit),
    orderBy: () => query(coll, filter, after, limit),
    limit: (n: number) => query(coll, filter, after, n),
    startAfter: (id: string) => query(coll, filter, id, limit),
    async get() {
      let paths = [...docs.keys()].filter((p) => p.startsWith(`${coll}/`) && p.split("/").length === coll.split("/").length + 1)
        .sort();
      if (filter) paths = paths.filter((p) => docs.get(p)![filter[0]] === filter[1]);
      if (after) paths = paths.filter((p) => p.split("/").pop()! > after);
      if (limit) paths = paths.slice(0, limit);
      const out = paths.map(snap);
      return {docs: out, size: out.length};
    },
  }, `query(${coll})`, QUERY_READS, log);
  const db = guarded({
    collection: (c: string) => query(c),
    doc: (path: string) => guarded({path, id: path.split("/").pop(), get: async () => snap(path)}, `doc(${path})`,
      DOC_READS, log),
    async getAll(...refs: Array<{path?: string}>) {
      return refs.filter((r) => typeof r?.path === "string").map((r) => snap(r.path!));
    },
  }, "db", DB_READS, log);

  const clients = {db, bucket, documentId: "__name__", now: NOW} as unknown as OpsClients;
  return {log, clients, objects};
}

const real = ["--project", "touchgrass-today", "--real-project", "--out", "../ops-out/test/x.json"];
const run = (argv: string[], w: ReturnType<typeof world>, resume = {}) =>
  runCommand(parseArgs(argv), resume, w.clients) as Promise<Record<string, unknown>>;

describe("every dry-run is read-only (Phase 7G)", () => {
  test("photo-token-rotate dry-run: lists, reads metadata and photoUrl fields; writes nothing", async () => {
    const w = world();
    const r = await run(["photo-token-rotate", ...real, "--max", "1000"], w);
    assert.deepEqual(w.log, []);
    assert.equal(r.mode, "dry-run");
    assert.equal(r.operationMode, "read-only");
    assert.equal(r.bucket, BUCKET);
    assert.equal((r.counts as Record<string, number>)["would-rotate"], 4);
    assert.equal(r.photosWithoutReferences, 2, "the orphan and alice's legacy photo, which no document names");
  });
  test("photo-token-rotate dry-run resumed from a capped run: still nothing written", async () => {
    const w = world();
    const first = await run(["photo-token-rotate", ...real, "--max", "2"], w);
    assert.equal(first.limitReached, true);
    const resume = resumeOptions("photo-token-rotate", {command: "photo-token-rotate", ...first});
    const second = await run(["photo-token-rotate", ...real], w, resume);
    assert.equal(second.inspected, 2);
    assert.deepEqual(w.log, []);
  });
  test("photo-token-rotate dry-run with a failing object: recorded per photo, nothing written", async () => {
    const w = world({failMetadataFor: "completion_photos/bob/2026-09-02.jpg"});
    const r = await run(["photo-token-rotate", ...real], w);
    assert.equal((r.counts as Record<string, number>)["rotate-failed"], 1);
    assert.deepEqual(w.log, []);
  });
  test("photo-metadata-inventory (header and --full-read, --uid): reads bytes; writes nothing", async () => {
    for (const extra of [[], ["--full-read"], ["--uid", "alice"]]) {
      const w = world();
      const r = await run(["photo-metadata-inventory", ...real, ...extra], w);
      assert.deepEqual(w.log, [], extra.join(" "));
      assert.ok(Number(r.inspected) > 0);
    }
  });
  test("photo-metadata-inventory with unreadable photos: counted, nothing written", async () => {
    const w = world({failDownload: true});
    const r = await run(["photo-metadata-inventory", ...real], w);
    assert.equal((r.counts as Record<string, number>).unreadable, 4);
    assert.deepEqual(w.log, []);
  });
  test("photo-metadata-remediate dry-run: validates in memory; no backup, rewrite or lease", async () => {
    const w = world();
    const inv = await run(["photo-metadata-inventory", ...real, "--full-read"], w);
    const dir = mkdtempSync(join(tmpdir(), "tg-ro-"));
    try {
      const manifest = join(dir, "inv.json");
      writeFileSync(manifest, JSON.stringify({command: "photo-metadata-inventory", ...inv}));
      const r = await run(["photo-metadata-remediate", ...real, "--manifest", manifest], w);
      assert.ok(Number((r.counts as Record<string, number>)["would-rewrite"]) >= 1);
      assert.deepEqual(w.log, []);
    } finally {
      rmSync(dir, {recursive: true, force: true});
    }
  });
  test("orphan-photos dry-run: existence checks only; deletes nothing, takes no lease", async () => {
    const w = world();
    const r = await run(["orphan-photos", ...real], w);
    assert.deepEqual(w.log, []);
    assert.equal(r.mode, "dry-run");
    assert.equal(r.deleted, 0);
  });
  test("profile-photo-inventory: reads photoUrl fields; writes nothing", async () => {
    const w = world();
    const r = await run(["profile-photo-inventory", ...real], w);
    assert.deepEqual(w.log, []);
    assert.ok(r.inspected !== undefined || r.counts !== undefined);
  });
  test("control: the guard DOES catch writes — an --execute rotation is stopped at its lease", async () => {
    const w = world();
    await assert.rejects(run(["photo-token-rotate", ...real, "--execute", "--mode", "production-mutation",
      "--confirm-project", "touchgrass-today"], w), /write attempted/);
    assert.ok(w.log.some((l) => l.endsWith(".runTransaction")), w.log.join(","));
  });
});

describe("operation modes and environment allowlists (Phase 7G)", () => {
  const emu = {FIRESTORE_EMULATOR_HOST: "h:1", FIREBASE_STORAGE_EMULATOR_HOST: "h:2"};
  test("writing needs --execute AND an explicit mutation mode; a mode without --execute is refused", () => {
    const base = ["photo-token-rotate", ...real, "--confirm-project", "touchgrass-today"];
    assert.match(refusal(parseArgs([...base, "--execute"]), {})!, /--mode/);
    assert.match(refusal(parseArgs([...base, "--mode", "production-mutation"]), {})!, /needs --execute/);
    assert.equal(refusal(parseArgs([...base, "--execute", "--mode", "production-mutation"]), {}), null);
    assert.throws(() => parseArgs([...base, "--mode", "yolo"]), /--mode must be/);
  });
  test("test-object-mutation only for a token rotation scoped to one account", () => {
    const base = [...real, "--execute", "--mode", "test-object-mutation", "--confirm-project", "touchgrass-today"];
    assert.match(refusal(parseArgs(["photo-token-rotate", ...base]), {})!, /--uid/);
    assert.equal(refusal(parseArgs(["photo-token-rotate", ...base, "--uid", "testUid1"]), {}), null);
    assert.match(refusal(parseArgs(["orphan-photos", ...base]), {})!, /only for photo-token-rotate/);
  });
  test("exact production allowlist; demo- ids on the emulators; mixed environments fail closed", () => {
    assert.equal(environmentRefusal("touchgrass-today", undefined, {}), null);
    assert.equal(environmentRefusal("touchgrass-today", BUCKET, {}), null);
    assert.match(environmentRefusal("touchgrass-today", "touchgrass-today.appspot.com", {})!, /must be exactly/);
    assert.match(environmentRefusal("touchgrass-staging", undefined, {})!, /not on the production allowlist/);
    assert.match(environmentRefusal("gen-lang-client-0754598293", undefined, {})!, /not the TouchGrass project/);
    assert.equal(environmentRefusal("demo-x1", undefined, emu), null);
    assert.match(environmentRefusal("touchgrass-today", undefined, emu)!, /demo-/);
    assert.match(environmentRefusal("demo-x1", undefined, {FIRESTORE_EMULATOR_HOST: "h:1"})!, /different environments/);
    assert.match(environmentRefusal("demo-x1", undefined, {FIREBASE_STORAGE_EMULATOR_HOST: "h:2"})!, /different environments/);
    assert.match(environmentRefusal("touchgrass-today", undefined, {GCLOUD_PROJECT: "other-proj"})!, /doesn't match/);
    assert.equal(environmentRefusal("touchgrass-today", undefined, {GOOGLE_CLOUD_PROJECT: "touchgrass-today"}), null);
  });
  test("real-project output only under ops-out/", () => {
    const at = (out: string) => refusal(parseArgs(["photo-token-rotate", "--project", "touchgrass-today", "--real-project",
      "--out", out]), {});
    assert.equal(at("../ops-out/rotation/dry-1.json"), null);
    assert.match(at("dry-1.json")!, /ops-out/);
    assert.match(at("../build/web/dry-1.json")!, /ops-out/);
    assert.match(at("../ops-outside/dry-1.json")!, /ops-out/);
  });
});

describe("the CLI never echoes private files, and never overwrites output (Phase 7G)", () => {
  const cli = join(__dirname, "opsCli.js");
  // Fake emulator hosts: these refusals happen before any client exists.
  const env = {...process.env, FIRESTORE_EMULATOR_HOST: "127.0.0.1:1", FIREBASE_STORAGE_EMULATOR_HOST: "127.0.0.1:2",
    GCLOUD_PROJECT: "demo-cli"};
  const fail = (args: string[]) => {
    try {
      execFileSync(process.execPath, [cli, ...args], {env, encoding: "utf8", stdio: "pipe"});
      return {code: 0, stderr: ""};
    } catch (e) {
      const err = e as {status: number; stderr: string};
      return {code: err.status, stderr: err.stderr};
    }
  };
  test("an existing --out file is refused (exit 2) and left untouched", () => {
    const dir = mkdtempSync(join(tmpdir(), "tg-out-"));
    try {
      const out = join(dir, "earlier.json");
      writeFileSync(out, "{\"keep\":true}");
      const r = fail(["photo-token-rotate", "--project", "demo-cli", "--out", out]);
      assert.equal(r.code, 2);
      assert.match(r.stderr, /existing file/);
    } finally {
      rmSync(dir, {recursive: true, force: true});
    }
  });
  test("a malformed --resume file: a fixed message, never its contents", () => {
    const dir = mkdtempSync(join(tmpdir(), "tg-res-"));
    try {
      const bad = join(dir, "bad.json");
      writeFileSync(bad, "{\"nextPageToken\": \"completion_photos/SECRET-UID/2026-01-01.jpg\" oops");
      const r = fail(["photo-token-rotate", "--project", "demo-cli", "--resume", bad]);
      assert.equal(r.code, 2);
      assert.match(r.stderr, /can't be read as JSON/);
      assert.doesNotMatch(r.stderr, /SECRET-UID|completion_photos/);
    } finally {
      rmSync(dir, {recursive: true, force: true});
    }
  });
});

describe("AC-1 readiness (Phase 7H)", () => {
  test("--out must be inside THIS repository's ops-out/, not any folder of that name", () => {
    assert.equal(insideOpsOut("../ops-out/rotation/dry-1.json"), true);
    assert.equal(insideOpsOut(join(OPS_OUT_DIR, "rotation", "dry-1.json")), true);
    assert.equal(insideOpsOut(OPS_OUT_DIR), false, "the folder itself is not a file in it");
    assert.equal(insideOpsOut(join(tmpdir(), "ops-out", "dry-1.json")), false);
    assert.equal(insideOpsOut("../ops-out/../build/x.json"), false);
    const at = (out: string) => refusal(parseArgs(["photo-token-rotate", "--project", "touchgrass-today", "--real-project",
      "--out", out]), {});
    assert.match(at(join(tmpdir(), "ops-out", "dry-1.json"))!, /this repository's/);
  });
  test("credentials: refused with the exact command when no ADC file exists; the file is never read", () => {
    const none = () => false;
    const msg = credentialsRefusal({APPDATA: "C:/Users/x/AppData/Roaming"}, none, "win32")!;
    assert.match(msg, /gcloud auth application-default login/);
    assert.match(msg, /Nothing was contacted/);
    const seen: string[] = [];
    const only = (p: string) => (seen.push(p), p === adcWellKnownFile({APPDATA: "C:/A"}, "win32"));
    assert.equal(credentialsRefusal({APPDATA: "C:/A"}, only, "win32"), null);
    assert.match(seen[0], /gcloud[\\/]application_default_credentials\.json$/);
    assert.equal(credentialsRefusal({CLOUDSDK_CONFIG: "/cfg"}, (p) => p === join("/cfg", "application_default_credentials.json")),
      null);
    assert.match(credentialsRefusal({GOOGLE_APPLICATION_CREDENTIALS: "/missing.json"}, none)!, /doesn't exist/);
    assert.equal(credentialsRefusal({GOOGLE_APPLICATION_CREDENTIALS: "/k.json"}, (p) => p === "/k.json"), null);
  });
  test("the read-only rotation --out file has aggregates and hashed outcomes — no names, uids or generations", async () => {
    const w = world();
    const args = parseArgs(["photo-token-rotate", ...real, "--max", "1000"]);
    const r = await runCommand(args, {}, w.clients) as Record<string, unknown>;
    const saved = forOutFile(args, r);
    const text = JSON.stringify(saved);
    assert.doesNotMatch(text, /alice|bob|orphan|completion_photos|tok-1|generation/);
    assert.deepEqual(saved.counts, r.counts);
    assert.deepEqual(saved.referenceAnomalies, r.referenceAnomalies);
    const entries = saved.entries as Array<Record<string, unknown>>;
    assert.equal(entries.length, (r.entries as unknown[]).length);
    assert.ok(entries.every((e) => /^[0-9a-f]{16}$/.test(String(e.nameTag)) && typeof e.outcome === "string"));
    assert.deepEqual(w.log, []);
  });
  test("execute runs and other commands keep their files unchanged (resume and manifests need names)", () => {
    const result = {entries: [{name: "completion_photos/a/2026-01-01.jpg", outcome: "rotated"}]};
    const exec = parseArgs(["photo-token-rotate", ...real, "--execute", "--mode", "production-mutation",
      "--confirm-project", "touchgrass-today"]);
    assert.equal(forOutFile(exec, result), result);
    assert.equal(forOutFile(parseArgs(["photo-metadata-inventory", ...real]), result), result);
  });
  test("errors: class plus a short code only — never the message", () => {
    assert.equal(safeErrorLabel(Object.assign(new Error("gs://b/completion_photos/uid/x.jpg denied"), {code: 403})),
      "Error (code 403)");
    assert.equal(safeErrorLabel(Object.assign(new Error("x"), {code: "PERMISSION_DENIED"})), "Error (code PERMISSION_DENIED)");
    assert.equal(safeErrorLabel(Object.assign(new Error("x"), {code: "completion_photos/uid/x.jpg"})), "Error");
    assert.equal(safeErrorLabel("boom"), "error");
  });
  test("CLI: a real-project run without ADC is refused before anything is contacted or created", () => {
    const cfg = mkdtempSync(join(tmpdir(), "tg-noadc-"));
    const outDir = join(OPS_OUT_DIR, `test-7h-${process.pid}-${Date.now()}`);
    try {
      const env: Record<string, string | undefined> = {...process.env, APPDATA: cfg, CLOUDSDK_CONFIG: cfg};
      for (const k of ["GOOGLE_APPLICATION_CREDENTIALS", "FIRESTORE_EMULATOR_HOST", "FIREBASE_STORAGE_EMULATOR_HOST",
        "GCLOUD_PROJECT", "GOOGLE_CLOUD_PROJECT"]) delete env[k];
      let code = 0;
      let stderr = "";
      try {
        execFileSync(process.execPath, [join(__dirname, "opsCli.js"), "photo-token-rotate", "--project", "touchgrass-today",
          "--real-project", "--out", join(outDir, "dry-1.json"), "--max", "1000"], {env, encoding: "utf8", stdio: "pipe"});
      } catch (e) {
        code = (e as {status: number}).status;
        stderr = (e as {stderr: string}).stderr;
      }
      assert.equal(code, 2);
      assert.match(stderr, /gcloud auth application-default login/);
      assert.equal(existsSync(outDir), false, "no output folder before credentials are confirmed");
    } finally {
      rmSync(cfg, {recursive: true, force: true});
      rmSync(outDir, {recursive: true, force: true});
    }
  });
});
