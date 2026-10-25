/**
 * Account deletion against the REAL local emulators (Firestore, Storage,
 * Auth) using the Admin SDK — demo project only, never production.
 *
 *   cd functions && npm run test:emulator
 *
 * (Needs Java 21+ for the emulators — see firestore-tests/README.md.)
 */
import {test, describe, before, beforeEach} from "node:test";
import assert from "node:assert/strict";
import {initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {getAuth} from "firebase-admin/auth";
import {DELETED_ACCOUNTS, DeletionDeps, performAccountDeletion} from "./accountDeletion";

const PROJECT = process.env.GCLOUD_PROJECT ?? "demo-touchgrass-fn";
if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
  throw new Error("Run via `npm run test:emulator` — refusing to touch a real project.");
}
initializeApp({projectId: PROJECT, storageBucket: `${PROJECT}.appspot.com`});
const db = getFirestore();
const bucket = getStorage().bucket();
const auth = getAuth();
const realDeps: DeletionDeps = {db, bucket, auth};

async function clearAll(): Promise<void> {
  for (const c of ["users", "completions", "usernames", "leaderboard_public", "feedback", DELETED_ACCOUNTS]) {
    await db.recursiveDelete(db.collection(c));
  }
  await bucket.deleteFiles({force: true}).catch(() => undefined);
  const users = await auth.listUsers();
  if (users.users.length) await auth.deleteUsers(users.users.map((u) => u.uid));
}

async function seedUser(uid: string, completions = 2): Promise<void> {
  await auth.createUser({uid, email: `${uid}@example.test`});
  const userRef = db.collection("users").doc(uid);
  await userRef.set({uid, username: `${uid}_name`, xp: 100});
  await userRef.collection("challenges").doc("2026-10-17").set({title: "t"});
  await userRef.collection("memories").doc(`${uid}_2026-10-17`).set({caption: "c"});
  await userRef.collection("aiUsage").doc("2026-10").set({verificationCount: 1});
  for (let i = 0; i < completions; i++) {
    await db.collection("completions").doc(`${uid}_d${i}`).set({userId: uid, xpAwarded: 25});
  }
  await db.collection("usernames").doc(`${uid}_name`).set({uid});
  await db.collection("leaderboard_public").doc(uid).set({displayName: uid, xp: 100});
  await db.collection("feedback").doc(`${uid}_2026-10-17_1`).set({userId: uid, message: "hi"});
  await bucket.file(`completion_photos/${uid}/1.jpg`).save(Buffer.from([1]));
  await bucket.file(`completion_photos/${uid}/2.jpg`).save(Buffer.from([2]));
  await bucket.file(`user_avatars/${uid}.png`).save(Buffer.from([3]));
  // An original kept by the photo-metadata tool (ops/photoMetadataJob.ts).
  await bucket.file(`metadata_backup/completion_photos/${uid}/run1/2026-10-17.jpg`).save(Buffer.from([4]));
}

/** Everything that exists for [uid], as counts — all zero = fully deleted. */
async function footprint(uid: string): Promise<Record<string, number>> {
  const exists = async (p: Promise<[boolean]>) => ((await p)[0] ? 1 : 0);
  const count = async (q: FirebaseFirestore.Query) => (await q.get()).size;
  const userRef = db.collection("users").doc(uid);
  return {
    userDoc: (await userRef.get()).exists ? 1 : 0,
    challenges: await count(userRef.collection("challenges")),
    memories: await count(userRef.collection("memories")),
    aiUsage: await count(userRef.collection("aiUsage")),
    completions: await count(db.collection("completions").where("userId", "==", uid)),
    usernames: await count(db.collection("usernames").where("uid", "==", uid)),
    leaderboard: (await db.collection("leaderboard_public").doc(uid).get()).exists ? 1 : 0,
    feedback: await count(db.collection("feedback").where("userId", "==", uid)),
    photos: (await bucket.getFiles({prefix: `completion_photos/${uid}/`}))[0].length,
    metadataBackups: (await bucket.getFiles({prefix: `metadata_backup/completion_photos/${uid}/`}))[0].length,
    avatar: await exists(bucket.file(`user_avatars/${uid}.png`).exists()),
    authUser: await auth.getUser(uid).then(() => 1, () => 0),
  };
}
const GONE = {
  userDoc: 0, challenges: 0, memories: 0, aiUsage: 0, completions: 0, usernames: 0,
  leaderboard: 0, feedback: 0, photos: 0, metadataBackups: 0, avatar: 0, authUser: 0,
};

describe("account deletion (emulators)", () => {
  before(clearAll);
  beforeEach(async () => {
    await clearAll();
    await seedUser("alice");
    await seedUser("alice2"); // uid-prefix collision guard
    await seedUser("bob");
  });

  test("removes every document, file and the Auth user owned by the caller", async () => {
    await performAccountDeletion(realDeps, "alice");
    assert.deepEqual(await footprint("alice"), GONE);
  });

  test("leaves a deleted-account marker holding only timestamps, for the deleted uid only (Phase 7G)", async () => {
    const before = Date.now();
    await performAccountDeletion(realDeps, "alice");
    const marker = await db.collection(DELETED_ACCOUNTS).doc("alice").get();
    assert.equal(marker.exists, true);
    assert.deepEqual(Object.keys(marker.data()!).sort(), ["expiresAt", "markedAt"], "no personal data");
    const expires = marker.get("expiresAt").toMillis();
    assert.ok(expires >= before + 2 * 60 * 60 * 1000 - 5000 && expires <= Date.now() + 2 * 60 * 60 * 1000 + 5000);
    assert.equal((await db.collection(DELETED_ACCOUNTS).get()).size, 1, "bob and alice2 have none");
    // A retry rewrites the same marker; it never fails on it.
    await performAccountDeletion(realDeps, "alice");
    assert.equal((await db.collection(DELETED_ACCOUNTS).get()).size, 1);
  });

  test("leaves other users untouched — including one whose uid starts with the same prefix", async () => {
    const bobBefore = await footprint("bob");
    const alice2Before = await footprint("alice2");
    await performAccountDeletion(realDeps, "alice");
    assert.deepEqual(await footprint("bob"), bobBefore);
    assert.deepEqual(await footprint("alice2"), alice2Before);
  });

  test("is idempotent — a repeated request succeeds and changes nothing more", async () => {
    await performAccountDeletion(realDeps, "alice");
    await performAccountDeletion(realDeps, "alice");
    assert.deepEqual(await footprint("alice"), GONE);
  });

  test("handles more completions than one batch (pagination)", async () => {
    await clearAll();
    await seedUser("alice", 450);
    const report = await performAccountDeletion(realDeps, "alice");
    assert.equal(report.completions, 450);
    assert.deepEqual(await footprint("alice"), GONE);
  });

  test("an early failure reports an error, keeps the account usable, and a retry finishes", async () => {
    const failingStorage: DeletionDeps = {
      ...realDeps,
      bucket: {
        deleteFiles: async () => {
          throw new Error("storage unavailable");
        },
        file: (n: string) => bucket.file(n),
      },
    };
    await assert.rejects(performAccountDeletion(failingStorage, "alice"));
    const after = await footprint("alice");
    assert.equal(after.authUser, 1, "Auth user must survive so the user can retry");
    assert.equal(after.userDoc, 1, "nothing after the failed step may run");

    await performAccountDeletion(realDeps, "alice");
    assert.deepEqual(await footprint("alice"), GONE);
  });

  test("a failure at the final Auth step is reported, and a retry completes it", async () => {
    const failingAuth: DeletionDeps = {
      ...realDeps,
      auth: {
        revokeRefreshTokens: (uid: string) => auth.revokeRefreshTokens(uid),
        deleteUser: async () => {
          throw Object.assign(new Error("auth backend error"), {code: "auth/internal-error"});
        },
      },
    };
    await assert.rejects(performAccountDeletion(failingAuth, "alice"));
    assert.equal((await footprint("alice")).authUser, 1);

    await performAccountDeletion(realDeps, "alice");
    assert.deepEqual(await footprint("alice"), GONE);
  });

  test("revokes the user's other sessions before deleting anything", async () => {
    const failingStorage: DeletionDeps = {
      ...realDeps,
      bucket: {
        deleteFiles: async () => {
          throw new Error("storage unavailable");
        },
        file: (n: string) => bucket.file(n),
      },
    };
    const before = (await auth.getUser("alice")).tokensValidAfterTime;
    await new Promise((r) => setTimeout(r, 1100)); // revocation has 1 s resolution
    await assert.rejects(performAccountDeletion(failingStorage, "alice"));
    const after = (await auth.getUser("alice")).tokensValidAfterTime;
    assert.notEqual(after, before, "refresh tokens must be revoked first");
    assert.equal((await footprint("alice")).userDoc, 1);
  });

  test("an Auth account with no Firestore or Storage data is deleted cleanly", async () => {
    await auth.createUser({uid: "empty", email: "empty@example.test"});
    const report = await performAccountDeletion(realDeps, "empty");
    assert.deepEqual(report, {completions: 0, usernames: 0, feedback: 0});
    assert.deepEqual(await footprint("empty"), GONE);
  });

  test("data left behind after the Auth user is already gone is still removed", async () => {
    await auth.deleteUser("alice");
    await performAccountDeletion(realDeps, "alice");
    assert.deepEqual(await footprint("alice"), GONE);
  });

  // ── Phase 7D ──────────────────────────────────────────────────────────────

  test("two concurrent requests (e.g. a double tap or two devices) both finish; nothing is left", async () => {
    const bobBefore = await footprint("bob");
    const results = await Promise.allSettled([
      performAccountDeletion(realDeps, "alice"),
      performAccountDeletion(realDeps, "alice"),
    ]);
    // At least one succeeds; a loser may fail mid-way, and its retry is safe.
    assert.ok(results.some((r) => r.status === "fulfilled"));
    if (results.some((r) => r.status === "rejected")) await performAccountDeletion(realDeps, "alice");
    assert.deepEqual(await footprint("alice"), GONE);
    assert.deepEqual(await footprint("bob"), bobBefore, "another user is untouched");
  });

  test("a photo uploaded by another session while deletion runs is removed too (second sweep)", async () => {
    const racing: DeletionDeps = {
      ...realDeps,
      db: new Proxy(db, {
        get(target, prop, receiver) {
          if (prop === "recursiveDelete") {
            return async (...args: Parameters<typeof db.recursiveDelete>) => {
              // Another device, still holding a valid ID token, uploads now.
              await bucket.file("completion_photos/alice/2026-10-20.jpg").save(Buffer.from([9]));
              return target.recursiveDelete(...args);
            };
          }
          const v = Reflect.get(target, prop, receiver);
          return typeof v === "function" ? v.bind(target) : v;
        },
      }),
    };
    await performAccountDeletion(racing, "alice");
    assert.deepEqual(await footprint("alice"), GONE);
  });

  // ── Phase 7E: data-shape matrix and partial failures ─────────────────────

  for (const completions of [0, 1, 3]) {
    for (const photos of [true, false]) {
      test(`a user with ${completions} completion(s), ${photos ? "with" : "without"} photos, is fully deleted`, async () => {
        await clearAll();
        await seedUser("carol", completions);
        if (!photos) {
          await bucket.deleteFiles({prefix: "completion_photos/carol/", force: true});
          await bucket.file("user_avatars/carol.png").delete({ignoreNotFound: true});
        }
        await seedUser("dave");
        const daveBefore = await footprint("dave");
        const report = await performAccountDeletion(realDeps, "carol");
        assert.equal(report.completions, completions);
        assert.deepEqual(await footprint("carol"), GONE);
        assert.deepEqual(await footprint("dave"), daveBefore);
      });
    }
  }

  test("a failure in the SECOND Storage sweep leaves the Auth user for a retry, which finishes", async () => {
    let photoSweeps = 0;
    const flaky: DeletionDeps = {
      ...realDeps,
      bucket: {
        deleteFiles: async (o: {prefix: string; force?: boolean}) => {
          if (o.prefix === "completion_photos/alice/" && ++photoSweeps === 2) throw new Error("storage unavailable");
          return bucket.deleteFiles(o);
        },
        file: (n: string) => bucket.file(n),
      },
    };
    await assert.rejects(performAccountDeletion(flaky, "alice"));
    const mid = await footprint("alice");
    assert.equal(mid.authUser, 1, "never reported as deleted while cleanup may be incomplete");
    assert.equal(mid.userDoc, 0, "Firestore steps before the sweep completed");
    await performAccountDeletion(realDeps, "alice");
    assert.deepEqual(await footprint("alice"), GONE);
  });

  test("the user's photo download links stop working once the account is deleted", async () => {
    const name = "completion_photos/alice/2026-10-19.jpg";
    await bucket.file(name).save(Buffer.from([7]), {
      resumable: false,
      metadata: {contentType: "image/jpeg", metadata: {firebaseStorageDownloadTokens: "tok-del"}},
    });
    const host = process.env.FIREBASE_STORAGE_EMULATOR_HOST;
    assert.ok(host, "Storage emulator required");
    const url = `http://${host}/v0/b/${bucket.name}/o/${encodeURIComponent(name)}?alt=media&token=tok-del`;
    assert.equal((await fetch(url)).status, 200, "precondition: the link works");
    await performAccountDeletion(realDeps, "alice");
    assert.notEqual((await fetch(url)).status, 200, "the bearer link must be dead");
  });
});
