/**
 * Phase 6 operator tools against the REAL local emulators (Storage,
 * Firestore) — demo project only, never production.
 *
 *   cd functions && npm run test:emulator
 *
 * Note: the Storage emulator ignores `ifGenerationMatch` preconditions
 * (verified in Phase 5), so the atomic replace-protection is only enforced
 * by real Cloud Storage; the read-check before each write is what runs here.
 */
import {test, describe, before, beforeEach} from "node:test";
import assert from "node:assert/strict";
import {initializeApp} from "firebase-admin/app";
import {FieldPath, getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {inspectJpeg} from "./jpegMetadata";
import {adminPhotoStore, backupPathFor, inventoryPhotoMetadata, remediatePhotoMetadata} from "./photoMetadataJob";
import {adminProfileDeps, inventoryProfilePhotos} from "./profilePhotoInventory";
import {acquireLease} from "./lease";
import {adminCleanupDeps, runOrphanPhotoCleanup} from "../orphanPhotoCleanup";
import {exifSegment, jpeg} from "./testJpeg";

const PROJECT = process.env.GCLOUD_PROJECT ?? "demo-touchgrass-fn";
if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST) {
  throw new Error("Run via `npm run test:emulator` — refusing to touch a real project.");
}
const BUCKET = `${PROJECT}.appspot.com`;
initializeApp({projectId: PROJECT, storageBucket: BUCKET});
const db = getFirestore();
const bucket = getStorage().bucket(BUCKET);
const store = adminPhotoStore(bucket);

async function clearAll(): Promise<void> {
  for (const c of ["users", "completions", "_ops"]) await db.recursiveDelete(db.collection(c));
  await bucket.deleteFiles({force: true}).catch(() => undefined);
}

async function putPhoto(name: string, bytes: Uint8Array, token = "tok-abc"): Promise<void> {
  await bucket.file(name).save(Buffer.from(bytes), {
    resumable: false,
    metadata: {contentType: "image/jpeg", cacheControl: "private, max-age=300",
      metadata: {firebaseStorageDownloadTokens: token}},
  });
}

/** Downloads through the Firebase Storage REST path the app's saved
 * download URLs use (emulator host). */
async function downloadViaUrl(name: string, token: string): Promise<Uint8Array> {
  const host = process.env.FIREBASE_STORAGE_EMULATOR_HOST!;
  const url = `http://${host}/v0/b/${BUCKET}/o/${encodeURIComponent(name)}?alt=media&token=${token}`;
  const res = await fetch(url);
  assert.equal(res.status, 200, "the saved download URL still works");
  return new Uint8Array(await res.arrayBuffer());
}

const GPS_ROTATED = `completion_photos/alice/2026-01-01.jpg`;
const CLEAN = `completion_photos/alice/2026-01-02.jpg`;
const XMP = `completion_photos/bob/2026-01-01.jpg`;

describe("historical photo metadata (emulators)", () => {
  before(clearAll);
  beforeEach(async () => {
    await clearAll();
    await putPhoto(GPS_ROTATED, jpeg({jfif: true, exif: exifSegment({orientation: 6, gps: true})}));
    await putPhoto(CLEAN, jpeg({jfif: true}));
    await putPhoto(XMP, jpeg({xmp: true}), "tok-bob");
    await bucket.file("user_avatars/alice.png").save(Buffer.from([0x89, 0x50]));
  });

  test("inventory counts categories from header reads and writes nothing", async () => {
    const [before] = await bucket.getFiles();
    const r = await inventoryPhotoMetadata(store);
    assert.deepEqual(r.counts, {"gps": 1, "clean": 1, "other-metadata": 1});
    const [after] = await bucket.getFiles();
    assert.deepEqual(after.map((f) => [f.name, f.metadata.generation]), before.map((f) => [f.name, f.metadata.generation]));
  });

  test("dry-run remediation writes nothing", async () => {
    const inv = await inventoryPhotoMetadata(store);
    const r = await remediatePhotoMetadata(store, inv.items, {runId: "dry1", backup: true});
    assert.equal(r.counts["would-rewrite"], 2);
    const [files] = await bucket.getFiles({prefix: "metadata_backup/"});
    assert.equal(files.length, 0);
  });

  test("execute strips in place; the saved download URL, token and content type keep working", async () => {
    const original = await downloadViaUrl(GPS_ROTATED, "tok-abc");
    const inv = await inventoryPhotoMetadata(store);
    const r = await remediatePhotoMetadata(store, inv.items, {runId: "run1", backup: true, mode: "execute"});
    assert.equal(r.counts.rewritten, 2);

    const [meta] = await bucket.file(GPS_ROTATED).getMetadata();
    assert.equal(meta.metadata?.firebaseStorageDownloadTokens, "tok-abc");
    assert.equal(meta.contentType, "image/jpeg");
    assert.equal(meta.cacheControl, "private, max-age=300");
    const now = await downloadViaUrl(GPS_ROTATED, "tok-abc");
    const m = inspectJpeg(now);
    assert.equal(m.gps, false);
    assert.equal(m.orientation, 6);
    assert.ok(now.length < original.length);

    // Reversible: the original sits in the per-user, server-only backup
    // path — a new object with no download token, so the original's token
    // URL can't reach it.
    const backupName = backupPathFor(GPS_ROTATED, "run1");
    assert.equal(backupName, "metadata_backup/completion_photos/alice/run1/2026-01-01.jpg");
    const [backup] = await bucket.file(backupName).download();
    assert.deepEqual(new Uint8Array(backup), original);
    const [backupMeta] = await bucket.file(backupName).getMetadata();
    assert.equal(backupMeta.metadata?.firebaseStorageDownloadTokens, undefined);
    await assert.rejects(downloadViaUrl(backupName, "tok-abc"), "the original's token must not open the backup");
    // Clean photo and avatar untouched.
    assert.equal((await bucket.file(CLEAN).getMetadata())[0].generation, inv.items.find((i) => i.name === CLEAN)!.generation);
    assert.equal((await bucket.file("user_avatars/alice.png").exists())[0], true);

    // A second inventory finds nothing left to fix.
    const again = await inventoryPhotoMetadata(store);
    assert.equal(again.needsRemediation, 0);
  });

  test("a photo re-uploaded after the inventory is left alone", async () => {
    const inv = await inventoryPhotoMetadata(store);
    await putPhoto(GPS_ROTATED, jpeg({jfif: true}), "tok-new");
    const r = await remediatePhotoMetadata(store, inv.items, {runId: "run2", backup: false, mode: "execute"});
    assert.equal(r.entries.find((e) => e.name === GPS_ROTATED)!.outcome, "changed-since-inventory");
    const [meta] = await bucket.file(GPS_ROTATED).getMetadata();
    assert.equal(meta.metadata?.firebaseStorageDownloadTokens, "tok-new");
  });
});

describe("profile photo inventory (emulator)", () => {
  before(clearAll);
  test("counts stored photo kinds without writing", async () => {
    const avatar = (uid: string) =>
      `https://firebasestorage.googleapis.com/v0/b/touchgrass-today.firebasestorage.app/o/user_avatars%2F${uid}.png?alt=media&token=t`;
    await db.doc("users/a").set({photoUrl: null});
    await db.doc("users/b").set({photoUrl: avatar("b")});
    await db.doc("users/c").set({photoUrl: "https://lh3.googleusercontent.com/a/x"});
    await db.doc("users/d").set({photoUrl: "https://evil.example/p.png"});
    await db.doc("users/e").set({displayName: "no photo field"});
    const r = await inventoryProfilePhotos(
      adminProfileDeps(db as unknown as Parameters<typeof adminProfileDeps>[0], FieldPath.documentId()),
      {pageSize: 2});
    assert.equal(r.inspected, 5);
    assert.deepEqual(r.counts, {"none": 2, "own-avatar": 1, "google-photo": 1, "external": 1});
    assert.deepEqual(r.uids.external, ["d"]);
    assert.equal((await db.doc("users/d").get()).get("photoUrl"), "https://evil.example/p.png");
  });
});

describe("cleanup lease (emulator)", () => {
  before(clearAll);
  test("only one holder at a time; a released or expired lease can be taken", async () => {
    let now = 1_000_000;
    const clock = () => now;
    const a = await acquireLease(db, "_ops/test_lease", "A", 60_000, clock);
    assert.ok(a);
    assert.equal(await acquireLease(db, "_ops/test_lease", "B", 60_000, clock), null);
    await a!.release();
    const b = await acquireLease(db, "_ops/test_lease", "B", 60_000, clock);
    assert.ok(b);
    now += 61_000; // B crashed without releasing: its lease expires
    assert.ok(await acquireLease(db, "_ops/test_lease", "C", 60_000, clock));
  });
  test("concurrent attempts: exactly one wins", async () => {
    const results = await Promise.all(["P", "Q", "R", "S"].map((h) =>
      acquireLease(db, "_ops/race_lease", h, 60_000)));
    assert.equal(results.filter(Boolean).length, 1);
  });
});

describe("abandoned-photo cleanup — synthetic volume (emulators)", () => {
  before(clearAll);
  test("100 users × typical history: only true orphans are eligible", async () => {
    // Synthetic library: 100 users, each with 3 old completed photos;
    // 6 old abandoned photos; 10 fresh photos without a completion yet;
    // 4 legacy-named photos; 2 photos of a deleted account.
    const later = new Date(Date.now() + 30 * 86_400_000);
    // Seeded in small parallel batches: ~420 simultaneous requests can make
    // the local Storage emulator drop connections (ECONNABORTED).
    const writes: Array<() => Promise<unknown>> = [];
    for (let u = 0; u < 100; u++) {
      writes.push(() => db.doc(`users/u${u}`).set({uid: `u${u}`}));
      for (let d = 1; d <= 3; d++) {
        const date = `2026-02-0${d}`;
        writes.push(() => db.doc(`completions/u${u}_${date}`).set({userId: `u${u}`}));
        writes.push(() => putPhoto(`completion_photos/u${u}/${date}.jpg`, jpeg()));
      }
    }
    for (let i = 0; i < 6; i++) writes.push(() => putPhoto(`completion_photos/u${i}/2026-03-0${i + 1}.jpg`, jpeg()));
    for (let i = 0; i < 4; i++) writes.push(() => putPhoto(`completion_photos/u${i}/170000000000${i}.jpg`, jpeg()));
    for (let i = 0; i < 2; i++) writes.push(() => putPhoto(`completion_photos/gone/2026-03-0${i + 1}.jpg`, jpeg()));
    for (let i = 0; i < writes.length; i += 20) await Promise.all(writes.slice(i, i + 20).map((w) => w()));
    // Dated within the last 6 days (relative to the run's clock): a
    // completion could still arrive for them, so they must be kept.
    for (let i = 0; i < 10; i++) {
      const k = new Date(later.getTime() - (i % 6) * 86_400_000).toISOString().slice(0, 10);
      await putPhoto(`completion_photos/u${50 + i}/${k}.jpg`, jpeg());
    }

    const r = await runOrphanPhotoCleanup(adminCleanupDeps(db, bucket), {now: later, pageSize: 100, maxObjects: 1000});
    assert.equal(r.inspected, 322);
    assert.equal(r.retained, 300);
    assert.equal(r.eligible, 6);
    assert.equal(r.skipped["legacy-name"], 4);
    assert.equal(r.skipped["no-user-profile"], 2);
    assert.equal(r.skipped["too-recent"], 10);
    assert.equal(r.deleted, 0, "dry-run");
  });
});
