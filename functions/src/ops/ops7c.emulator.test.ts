/**
 * Phase 7C operator tools against the REAL local emulators (Storage,
 * Firestore) — demo project only, never production.
 *
 *   cd functions && npm run test:emulator
 *
 * The key evidence here: after a token rotation, the OLD download URL no
 * longer opens the photo, the owner's stored links open it with the new
 * token, and the bytes are unchanged. Emulator behaviour is evidence for
 * the tool's logic, not proof of production behaviour — the runbook
 * requires a canary on a test account first.
 */
import {test, describe, beforeEach, before, after} from "node:test";
import assert from "node:assert/strict";
import {execFileSync} from "node:child_process";
import {mkdtempSync, readFileSync, rmSync} from "node:fs";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {getApps, initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {inspectJpeg} from "./jpegMetadata";
import {adminPhotoStore, inventoryPhotoMetadata, remediatePhotoMetadata} from "./photoMetadataJob";
import {ROTATION_MARKER, adminReferenceDeps, adminTokenStore, downloadUrl, rotatePhotoTokens} from "./photoTokenRotation";
import {acquireLease} from "./lease";
import {PHOTO_REWRITE_LEASE} from "./opsCli";
import {exifSegment, jpeg} from "./testJpeg";
import {getAuth} from "firebase-admin/auth";
import {
  type ExperimentDeps, cleanupExperiment, probeExperiment, setupExperiment,
} from "./revocationExperiment";

const PROJECT = process.env.GCLOUD_PROJECT ?? "demo-touchgrass-fn";
if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST) {
  throw new Error("Run via `npm run test:emulator` — refusing to touch a real project.");
}
const BUCKET = `${PROJECT}.appspot.com`;
if (getApps().length === 0) initializeApp({projectId: PROJECT, storageBucket: BUCKET});
const db = getFirestore();
const bucket = getStorage().bucket(BUCKET);

const A1 = "completion_photos/alice/2026-01-01.jpg";
const A2 = "completion_photos/alice/1700000000000.jpg";
const B1 = "completion_photos/bob/2026-01-01.jpg";
const OLD_A = "aaaaaaaa-0000-4000-8000-000000000001";
const OLD_B = "bbbbbbbb-0000-4000-8000-000000000002";
const LATER = () => new Date(Date.now() + 3_600_000); // objects were just created

const cat = (...parts: Uint8Array[]) => Uint8Array.from(parts.flatMap((p) => Array.from(p)));

async function clearAll(): Promise<void> {
  for (const c of ["users", "completions", "_ops"]) await db.recursiveDelete(db.collection(c));
  await bucket.deleteFiles({force: true}).catch(() => undefined);
}

async function putPhoto(name: string, bytes: Uint8Array, token: string): Promise<void> {
  await bucket.file(name).save(Buffer.from(bytes), {
    resumable: false,
    metadata: {contentType: "image/jpeg", cacheControl: "private, max-age=300",
      metadata: {firebaseStorageDownloadTokens: token}},
  });
}

/** Fetches through the Firebase Storage REST path download URLs use. */
async function fetchWithToken(name: string, token: string): Promise<{status: number; bytes?: Uint8Array}> {
  const host = process.env.FIREBASE_STORAGE_EMULATOR_HOST!;
  const res = await fetch(`http://${host}/v0/b/${BUCKET}/o/${encodeURIComponent(name)}?alt=media&token=${token}`);
  return res.status === 200 ? {status: 200, bytes: new Uint8Array(await res.arrayBuffer())} : {status: res.status};
}

const tokenIn = (url: unknown) => new URL(String(url)).searchParams.get("token")!;

describe("download-token rotation (emulators)", () => {
  const photoA1 = jpeg({jfif: true, exif: exifSegment({gps: true})});
  beforeEach(async () => {
    await clearAll();
    await putPhoto(A1, photoA1, OLD_A);
    await putPhoto(A2, jpeg({jfif: true}), OLD_A);
    await putPhoto(B1, jpeg({xmp: true}), OLD_B);
    await db.doc("completions/alice_2026-01-01").set({userId: "alice", photoUrl: downloadUrl(BUCKET, A1, OLD_A)});
    await db.doc("users/alice/memories/alice_2026-01-01").set({photoUrl: downloadUrl(BUCKET, A1, OLD_A)});
    await db.doc("completions/alice_1700000000000").set({userId: "alice", photoUrl: downloadUrl(BUCKET, A2, OLD_A)});
    await db.doc("completions/bob_2026-01-01").set({userId: "bob", photoUrl: downloadUrl(BUCKET, B1, OLD_B)});
    // A link to another user's photo stored in Alice's data is never touched
    // by Bob's rotation (only Bob's own documents are searched).
    await db.doc("users/alice/memories/odd").set({photoUrl: downloadUrl(BUCKET, B1, OLD_B)});
  });

  test("dry-run changes nothing (objects, tokens, links)", async () => {
    const [before] = await bucket.getFiles({prefix: "completion_photos/"});
    const r = await rotatePhotoTokens(adminTokenStore(bucket), adminReferenceDeps(db as never, BUCKET),
      {runId: "dry", bucket: BUCKET, now: LATER()});
    assert.equal(r.counts["would-rotate"], 3);
    const [after] = await bucket.getFiles({prefix: "completion_photos/"});
    assert.deepEqual(after.map((f) => [f.name, f.metadata.generation]), before.map((f) => [f.name, f.metadata.generation]));
    assert.equal((await fetchWithToken(A1, OLD_A)).status, 200);
    assert.equal(tokenIn((await db.doc("completions/alice_2026-01-01").get()).get("photoUrl")), OLD_A);
    // Phase 7F: the field-masked reference query still finds every link, and
    // Alice's link to Bob's photo is reported (Bob's rotation can't follow it).
    assert.equal(r.photosWithoutReferences, 0);
    assert.deepEqual(r.referenceAnomalies, {otherOwnerPath: 1, otherBucketOrHost: 0, unparseable: 0, withoutToken: 0});
  });

  test("the CLI dry-run (as run against production) writes nothing — not even its lease (Phase 7F)", async () => {
    const [before] = await bucket.getFiles({prefix: ""});
    const dir = mkdtempSync(join(tmpdir(), "tg-dry-"));
    try {
      const out = join(dir, "dry.json");
      const stdout = execFileSync(process.execPath, [join(__dirname, "opsCli.js"), "photo-token-rotate",
        "--project", PROJECT, "--bucket", BUCKET, "--out", out, "--max", "1000"], {encoding: "utf8"});
      const summary = JSON.parse(stdout);
      assert.equal(summary.mode, "dry-run");
      assert.equal(summary.bucket, BUCKET);
      assert.equal(summary.limitReached, false);
      assert.doesNotMatch(stdout, /alice|bob|completion_photos|token=/, "stdout: counts only");
      const file = JSON.parse(readFileSync(out, "utf8"));
      assert.equal(file.inspected, 3);
      assert.doesNotMatch(JSON.stringify(file), /token=|aaaaaaaa-|bbbbbbbb-/, "file: names, never tokens");
    } finally {
      rmSync(dir, {recursive: true, force: true});
    }
    assert.equal((await db.doc(PHOTO_REWRITE_LEASE).get()).exists, false, "no lease document was written");
    assert.equal((await db.collection("_ops").get()).size, 0);
    const [after] = await bucket.getFiles({prefix: ""});
    assert.deepEqual(after.map((f) => [f.name, f.metadata.generation, f.metadata.metageneration]),
      before.map((f) => [f.name, f.metadata.generation, f.metadata.metageneration]));
  });

  test("EVERY CLI dry-run command leaves Storage and Firestore exactly as they were (Phase 7G)", async () => {
    /** Every document (with its update time) under every collection, recursively. */
    const firestoreSnapshot = async (): Promise<string[]> => {
      const out: string[] = [];
      const walk = async (cols: FirebaseFirestore.CollectionReference[]): Promise<void> => {
        for (const col of cols) {
          for (const ref of await col.listDocuments()) {
            const snap = await ref.get();
            out.push(`${ref.path}@${snap.exists ? snap.updateTime!.toMillis() : "-"}`);
            await walk(await ref.listCollections());
          }
        }
      };
      await walk(await db.listCollections());
      return out.sort();
    };
    // A read retried on a dropped connection: the subprocess runs below take
    // long enough for the emulator to close this process's idle socket.
    const storageSnapshot = async (): Promise<string[]> => {
      for (let attempt = 1; ; attempt++) {
        try {
          return (await bucket.getFiles({prefix: ""}))[0]
            .map((f) => `${f.name}@${f.metadata.generation}/${f.metadata.metageneration}`).sort();
        } catch (e) {
          if (attempt >= 5 || !/ECONNRESET|socket hang up/.test(String(e))) throw e;
          // Several pooled sockets can be stale at once: wait for them to be
          // discarded before the next attempt (Phase 7H).
          await new Promise((r) => setTimeout(r, 250 * attempt));
        }
      }
    };
    const fsBefore = await firestoreSnapshot();
    const stBefore = await storageSnapshot();
    assert.ok(fsBefore.length >= 5 && stBefore.length === 3, "fixtures present");

    const dir = mkdtempSync(join(tmpdir(), "tg-dry-all-"));
    const cli = (...args: string[]) => execFileSync(process.execPath, [join(__dirname, "opsCli.js"), ...args,
      "--project", PROJECT, "--bucket", BUCKET], {encoding: "utf8"});
    try {
      const outputs = [
        cli("photo-metadata-inventory", "--out", join(dir, "inv.json")),
        cli("photo-metadata-inventory", "--full-read", "--out", join(dir, "inv-full.json")),
        cli("photo-metadata-remediate", "--manifest", join(dir, "inv-full.json"), "--out", join(dir, "rem.json")),
        // Phase 7H: into a folder that doesn't exist yet (created before any read).
        cli("photo-token-rotate", "--out", join(dir, "rotation", "dry-1.json")),
        cli("orphan-photos", "--out", join(dir, "orphans.json")),
        cli("profile-photo-inventory", "--out", join(dir, "profiles.json")),
      ];
      for (const stdout of outputs) {
        assert.equal(JSON.parse(stdout).operationMode, "read-only");
        assert.doesNotMatch(stdout, /alice|bob|completion_photos|token=/, "stdout: counts only");
      }
      assert.equal(JSON.parse(outputs[2]).mode, "dry-run");
      assert.ok(Number(JSON.parse(outputs[2]).counts["would-rewrite"]) >= 1, "remediation would act on the GPS photo");
      // Phase 7H (AC-1): the read-only rotation file keeps aggregates and
      // hashed per-photo outcomes — no object names, uids or tokens.
      const rot = readFileSync(join(dir, "rotation", "dry-1.json"), "utf8");
      assert.doesNotMatch(rot, /alice|bob|completion_photos|token=|generation/);
      const saved = JSON.parse(rot);
      assert.equal(saved.operationMode, "read-only");
      assert.ok(saved.entries.length >= 1 && saved.entries.every((e: {nameTag: string}) => /^[0-9a-f]{16}$/.test(e.nameTag)));
    } finally {
      rmSync(dir, {recursive: true, force: true});
    }
    assert.deepEqual(await storageSnapshot(), stBefore, "no object written, rewritten, re-tokened or deleted");
    assert.deepEqual(await firestoreSnapshot(), fsBefore, "no document created, updated or deleted (no leases)");
  });

  test("execute (rewrite): the OLD URL stops working; links open the same bytes with the new token", async () => {
    assert.equal((await fetchWithToken(A1, OLD_A)).status, 200, "precondition: old URL works");
    const r = await rotatePhotoTokens(adminTokenStore(bucket), adminReferenceDeps(db as never, BUCKET),
      {runId: "rot1", bucket: BUCKET, now: LATER(), mode: "execute", removeVia: "rewrite"});
    assert.equal(r.counts.rotated, 3);
    assert.equal(r.referencesUpdated, 4);

    // Revoked: every old token URL is refused.
    for (const [name, old] of [[A1, OLD_A], [A2, OLD_A], [B1, OLD_B]]) {
      assert.notEqual((await fetchWithToken(name, old)).status, 200, `${name}: old token must be revoked`);
    }
    // The owner's links use the new token and return identical bytes.
    const newA1 = tokenIn((await db.doc("completions/alice_2026-01-01").get()).get("photoUrl"));
    assert.notEqual(newA1, OLD_A);
    assert.equal(tokenIn((await db.doc("users/alice/memories/alice_2026-01-01").get()).get("photoUrl")), newA1);
    const got = await fetchWithToken(A1, newA1);
    assert.equal(got.status, 200);
    assert.deepEqual(got.bytes, photoA1);
    const [meta] = await bucket.file(A1).getMetadata();
    assert.equal(meta.metadata?.firebaseStorageDownloadTokens, newA1, "exactly one token");
    assert.equal(meta.metadata?.[ROTATION_MARKER], "rot1");
    assert.equal(meta.contentType, "image/jpeg");
    assert.equal(meta.cacheControl, "private, max-age=300");
    // Bob's completion points at Bob's new token; the odd link inside
    // Alice's data still holds Bob's old (now revoked) token — not updated
    // across users.
    const newB1 = tokenIn((await db.doc("completions/bob_2026-01-01").get()).get("photoUrl"));
    assert.equal((await fetchWithToken(B1, newB1)).status, 200);
    assert.equal(tokenIn((await db.doc("users/alice/memories/odd").get()).get("photoUrl")), OLD_B);
  });

  test("between adding the new token and removing the old one, BOTH the old URL and the updated link work", async () => {
    const seen: number[] = [];
    await rotatePhotoTokens(adminTokenStore(bucket), adminReferenceDeps(db as never, BUCKET), {
      runId: "rot1", bucket: BUCKET, now: LATER(), mode: "execute", removeVia: "rewrite", uid: "alice",
      beforeRemove: async (name) => {
        if (name !== A1) return;
        const linked = tokenIn((await db.doc("completions/alice_2026-01-01").get()).get("photoUrl"));
        assert.notEqual(linked, OLD_A, "links already moved to the new token");
        seen.push((await fetchWithToken(A1, OLD_A)).status, (await fetchWithToken(A1, linked)).status);
      },
    });
    assert.deepEqual(seen, [200, 200], "no moment where the saved link is dead");
    assert.notEqual((await fetchWithToken(A1, OLD_A)).status, 200, "and the old one is revoked at the end");
  });

  test("execute (metadata) on the EMULATOR: it merges token lists, so the tool reports verify-failed — never a false \"rotated\"", async () => {
    const r = await rotatePhotoTokens(adminTokenStore(bucket), adminReferenceDeps(db as never, BUCKET),
      {runId: "rot1", bucket: BUCKET, now: LATER(), mode: "execute", uid: "alice"});
    assert.equal(r.counts.rotated, undefined);
    assert.equal(r.counts["verify-failed"], 2);
    assert.ok(r.entries.every((e) => e.detail === "old-token-still-present"));
    // Nothing broken: the links use the new token, which works.
    const linked = tokenIn((await db.doc("completions/alice_2026-01-01").get()).get("photoUrl"));
    assert.equal((await fetchWithToken(A1, linked)).status, 200);
    // And the photo bytes were never rewritten.
    assert.deepEqual((await fetchWithToken(A1, linked)).bytes, photoA1);
  });

  test("re-running the same run id writes nothing more and leaves links current", async () => {
    const deps = [adminTokenStore(bucket), adminReferenceDeps(db as never, BUCKET)] as const;
    const o = {runId: "rot1", bucket: BUCKET, now: LATER(), mode: "execute" as const, removeVia: "rewrite" as const};
    await rotatePhotoTokens(...deps, o);
    const [before] = await bucket.getFiles({prefix: "completion_photos/"});
    const again = await rotatePhotoTokens(...deps, o);
    assert.equal(again.counts["references-updated"], 3);
    assert.equal(again.referencesUpdated, 0, "links were already current");
    const [after] = await bucket.getFiles({prefix: "completion_photos/"});
    assert.deepEqual(after.map((f) => [f.metadata.generation, f.metadata.metageneration]),
      before.map((f) => [f.metadata.generation, f.metadata.metageneration]));
  });

  test("a just-uploaded photo is left alone (its completion may still be saving)", async () => {
    const r = await rotatePhotoTokens(adminTokenStore(bucket), adminReferenceDeps(db as never, BUCKET),
      {runId: "rot1", bucket: BUCKET, now: new Date(), mode: "execute"});
    assert.equal(r.counts["too-recent"], 3);
    assert.equal((await fetchWithToken(A1, OLD_A)).status, 200);
  });

  test("a photo deleted before the old token is removed (account deletion) is not recreated", async () => {
    const r = await rotatePhotoTokens(adminTokenStore(bucket), adminReferenceDeps(db as never, BUCKET), {
      runId: "rot1", bucket: BUCKET, now: LATER(), mode: "execute", removeVia: "rewrite",
      beforeRemove: async (name) => {
        if (name === B1) await bucket.file(B1).delete();
      },
    });
    assert.equal(r.entries.find((e) => e.name === B1)!.outcome, "changed-during-rotation");
    assert.equal((await bucket.file(B1).exists())[0], false);
  });
});

describe("revocation experiment harness — rehearsal (Phase 7F, emulators)", () => {
  const deps = (): ExperimentDeps => ({
    auth: getAuth() as never,
    db: db as never,
    bucket: bucket as never,
    endpoints: {
      storageBase: `http://${process.env.FIREBASE_STORAGE_EMULATOR_HOST}`,
      signInUrl: `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=emu`,
    },
    fetch,
    sleep: async () => undefined,
  });
  // The probes' signed-in reads go through Storage rules: load the rules
  // that are LIVE in production (the interim file), not the deny-all
  // startup placeholder, and put the placeholder back afterwards.
  const setRules = async (file: string) => {
    const res = await fetch(`http://${process.env.FIREBASE_STORAGE_EMULATOR_HOST}/internal/setRules`, {
      method: "PUT", headers: {"content-type": "application/json"},
      body: JSON.stringify({rules: {files: [{name: "storage.rules", content: readFileSync(file, "utf8")}]}}),
    });
    assert.equal(res.ok, true, `loading ${file}`);
  };
  before(() => setRules(join(__dirname, "..", "..", "..", "deploy", "interim", "storage.interim.rules")));
  after(() => setRules(join(__dirname, "..", "..", "..", "firestore-tests", "placeholder.storage.rules")));
  const rotate = (uid: string, o: Partial<Parameters<typeof rotatePhotoTokens>[2]>) => rotatePhotoTokens(
    adminTokenStore(bucket), adminReferenceDeps(db as never, BUCKET),
    {runId: "exp1", bucket: BUCKET, now: LATER(), mode: "execute", uid, ...o});

  for (const [removeVia, expected] of [["rewrite", "revoked"], ["metadata", "not-revoked"]] as const) {
    test(`setup → before → paused → after (${removeVia}): verdict ${expected}; cleanup leaves nothing`, async () => {
      if (!process.env.FIREBASE_AUTH_EMULATOR_HOST) throw new Error("needs the Auth emulator");
      await clearAll();
      const d = deps();
      const s = await setupExperiment(d, PROJECT);
      const before = await probeExperiment(d, s, "before");
      assert.equal(before.passed, true, JSON.stringify(before.checks));

      const paused = await rotate(s.ownerUid, {stopBeforeRemove: true});
      assert.equal(paused.counts["awaiting-removal"], 1);
      assert.equal(paused.referencesUpdated, 1, "the Journal link moved to the new token");
      const atPause = await probeExperiment(d, s, "paused");
      assert.equal(atPause.passed, true, JSON.stringify(atPause.checks));

      const done = await rotate(s.ownerUid, {removeVia});
      const after = await probeExperiment(d, s, "after", {samples: 3});
      assert.equal(after.verdict, expected);
      if (expected === "revoked") {
        assert.equal(done.counts.rotated, 1);
        assert.equal(after.passed, true, JSON.stringify(after.checks));
      } else {
        // The emulator merges token lists: the tool says verify-failed and
        // the harness says not-revoked — neither claims success.
        assert.equal(done.counts["verify-failed"], 1);
        assert.equal(after.passed, false);
        assert.equal(after.checks["original URL refused (verdict revoked)"], false);
      }
      assert.doesNotMatch(JSON.stringify([before, atPause, after]), new RegExp(`${s.oldToken}|token=|${s.ownerPassword}`));

      const cleaned = await cleanupExperiment(d, s);
      assert.deepEqual(Object.values(cleaned), [true, true, true], JSON.stringify(cleaned));
      await assert.rejects(getAuth().getUser(s.ownerUid));
      await assert.rejects(getAuth().getUser(s.otherUid));
    });
  }
});

describe("historical metadata job — Phase 7C (emulators)", () => {
  const P = "completion_photos/carol/2026-01-01.jpg";
  beforeEach(clearAll);

  test("full-read inventory finds an appended image; remediation removes it and keeps the URL working", async () => {
    await putPhoto(P, cat(jpeg({jfif: true}), jpeg({exif: exifSegment({gps: true})})), "tok-c");
    const store = adminPhotoStore(bucket);
    const inv = await inventoryPhotoMetadata(store, {fullRead: true});
    assert.deepEqual(inv.counts, {"appended-data": 1});
    const r = await remediatePhotoMetadata(store, inv.items, {runId: "r1", backup: true, mode: "execute"});
    assert.equal(r.counts.rewritten, 1);
    const got = await fetchWithToken(P, "tok-c");
    assert.equal(got.status, 200);
    assert.equal(inspectJpeg(got.bytes!).trailingData, false);
    assert.doesNotMatch(Buffer.from(got.bytes!).toString("latin1"), /Cam\0/);
  });

  test("photo deleted between backup and overwrite: no backup is left behind", async () => {
    await putPhoto(P, jpeg({exif: exifSegment({gps: true})}), "tok-c");
    const store = adminPhotoStore(bucket);
    const inv = await inventoryPhotoMetadata(store);
    const racing = {...store, async writeIfGeneration(...a: Parameters<typeof store.writeIfGeneration>) {
      await bucket.file(P).delete(); // e.g. deleteAccount ran meanwhile
      return store.writeIfGeneration(...a);
    }};
    const r = await remediatePhotoMetadata(racing, inv.items, {runId: "r1", backup: true, mode: "execute"});
    assert.notEqual(r.entries[0].outcome, "rewritten");
    assert.match(r.entries[0].detail ?? "", /backup-removed/);
    const [left] = await bucket.getFiles({prefix: "metadata_backup/"});
    assert.deepEqual(left.map((f) => f.name), []);
    assert.equal((await bucket.file(P).exists())[0], false, "the photo is not recreated");
  });

  test("remediation and rotation can't run at the same time (shared lease)", async () => {
    const first = await acquireLease(db, PHOTO_REWRITE_LEASE, "run-a", 60_000);
    assert.ok(first);
    assert.equal(await acquireLease(db, PHOTO_REWRITE_LEASE, "run-b", 60_000), null);
    await first.release();
    assert.ok(await acquireLease(db, PHOTO_REWRITE_LEASE, "run-b", 60_000));
  });
});
