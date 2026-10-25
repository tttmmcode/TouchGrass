/**
 * Abandoned-photo cleanup against the REAL local emulators (Storage,
 * Firestore) through the Admin SDK adapters — demo project only, never
 * production.
 *
 *   cd functions && npm run test:emulator
 *
 * The emulator stamps every object with the current time, so the run's
 * "now" is moved 30 days ahead to make seeded photos old enough.
 */
import {test, describe, before, beforeEach} from "node:test";
import assert from "node:assert/strict";
import {initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {adminCleanupDeps, runOrphanPhotoCleanup} from "./orphanPhotoCleanup";

const PROJECT = process.env.GCLOUD_PROJECT ?? "demo-touchgrass-fn";
if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST) {
  throw new Error("Run via `npm run test:emulator` — refusing to touch a real project.");
}
initializeApp({projectId: PROJECT, storageBucket: `${PROJECT}.appspot.com`});
const db = getFirestore();
const bucket = getStorage().bucket();
const deps = adminCleanupDeps(db, bucket);
const LATER = new Date(Date.now() + 30 * 86_400_000);
const OLD = "2026-01-05"; // well before LATER − 7 days
const OLDER = "2026-01-04";

async function clearAll(): Promise<void> {
  for (const c of ["users", "completions"]) await db.recursiveDelete(db.collection(c));
  await bucket.deleteFiles({force: true}).catch(() => undefined);
}
const put = (name: string) => bucket.file(name).save(Buffer.from([0xff, 0xd8, 0xff, 0xd9]));
const exists = async (name: string) => (await bucket.file(name).exists())[0];

describe("orphan photo cleanup (emulators)", () => {
  before(clearAll);
  beforeEach(async () => {
    await clearAll();
    await db.doc("users/alice").set({uid: "alice"});
    await db.doc("users/bob").set({uid: "bob"});
    await put(`completion_photos/alice/${OLD}.jpg`); // has a completion
    await db.doc(`completions/alice_${OLD}`).set({userId: "alice"});
    await put(`completion_photos/alice/${OLDER}.jpg`); // orphan
    await put(`completion_photos/bob/${OLD}.jpg`); // has only a Journal entry
    await db.doc(`users/bob/memories/bob_${OLD}`).set({userId: "bob"});
    await put("completion_photos/bob/1700000000000.jpg"); // legacy name
    await put("completion_photos/ghost/2026-01-05.jpg"); // no profile
    await put("user_avatars/alice.png"); // other namespace
  });

  test("dry-run finds exactly the orphan and deletes nothing", async () => {
    const r = await runOrphanPhotoCleanup(deps, {now: LATER});
    assert.equal(r.mode, "dry-run");
    assert.equal(r.inspected, 5);
    assert.equal(r.eligible, 1);
    assert.equal(r.deleted, 0);
    assert.equal(r.retained, 2);
    assert.equal(r.skipped["legacy-name"], 1);
    assert.equal(r.skipped["no-user-profile"], 1);
    assert.equal(await exists(`completion_photos/alice/${OLDER}.jpg`), true);
  });

  test("delete mode removes only the orphan; everything else stays", async () => {
    const r = await runOrphanPhotoCleanup(deps, {now: LATER, mode: "delete"});
    assert.equal(r.deleted, 1);
    assert.equal(await exists(`completion_photos/alice/${OLDER}.jpg`), false);
    for (const kept of [
      `completion_photos/alice/${OLD}.jpg`, `completion_photos/bob/${OLD}.jpg`,
      "completion_photos/bob/1700000000000.jpg", "completion_photos/ghost/2026-01-05.jpg",
      "user_avatars/alice.png",
    ]) {
      assert.equal(await exists(kept), true, kept);
    }
  });

  test("with the real clock, freshly uploaded photos are never eligible", async () => {
    const r = await runOrphanPhotoCleanup(deps, {now: new Date(), mode: "delete"});
    assert.equal(r.eligible, 0);
    assert.equal(r.deleted, 0);
  });

  test("a repeated run is a no-op", async () => {
    await runOrphanPhotoCleanup(deps, {now: LATER, mode: "delete"});
    const again = await runOrphanPhotoCleanup(deps, {now: LATER, mode: "delete"});
    assert.equal(again.deleted, 0);
    assert.equal(again.eligible, 0);
  });

  test("pagination over the real listing reaches every object", async () => {
    let token: string | undefined;
    let inspected = 0;
    let eligible = 0;
    let runs = 0;
    do {
      const r = await runOrphanPhotoCleanup(deps, {now: LATER, pageSize: 2, maxObjects: 2, pageToken: token});
      inspected += r.inspected;
      eligible += r.eligible;
      token = r.nextPageToken;
      runs++;
    } while (token && runs < 10);
    assert.equal(inspected, 5);
    assert.equal(eligible, 1);
  });

  test("the generation precondition refuses to delete a replaced object", async () => {
    const name = `completion_photos/alice/${OLDER}.jpg`;
    const [meta] = await bucket.file(name).getMetadata();
    await put(name); // replaced: new generation
    assert.equal(await deps.deleteIfUnchanged(name, meta.generation!), false);
    assert.equal(await exists(name), true);
  });
});
