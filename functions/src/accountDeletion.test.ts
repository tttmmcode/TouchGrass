/**
 * Unit tests for the account-deletion request guard and Auth-step
 * idempotency. Data cleanup itself is verified against the real emulators
 * in accountDeletion.emulator.test.ts (`npm run test:emulator`).
 */
import {test, describe} from "node:test";
import assert from "node:assert/strict";
import {
  RECENT_SIGN_IN_SECONDS,
  checkDeletionRequest,
  isRecentSignIn,
  isSafeUid,
  performAccountDeletion,
  DeletionDeps,
} from "./accountDeletion";

const NOW = 1_800_000_000;

describe("checkDeletionRequest", () => {
  test("refuses unauthenticated callers", () => {
    assert.equal(checkDeletionRequest(undefined, NOW), "unauthenticated");
  });
  test("allows a caller who signed in just now", () => {
    assert.equal(checkDeletionRequest({uid: "alice", token: {auth_time: NOW - 10}}, NOW), null);
  });
  test("allows a sign-in exactly at the freshness limit (boundary)", () => {
    assert.equal(
      checkDeletionRequest({uid: "alice", token: {auth_time: NOW - RECENT_SIGN_IN_SECONDS}}, NOW),
      null
    );
  });
  test("refuses a sign-in one second past the limit (boundary)", () => {
    assert.equal(
      checkDeletionRequest({uid: "alice", token: {auth_time: NOW - RECENT_SIGN_IN_SECONDS - 1}}, NOW),
      "requires-recent-login"
    );
  });
  test("refuses a token with no auth_time", () => {
    assert.equal(checkDeletionRequest({uid: "alice", token: {}}, NOW), "requires-recent-login");
  });
  test("refuses a non-numeric auth_time", () => {
    assert.equal(checkDeletionRequest({uid: "alice", token: {auth_time: "now"}}, NOW), "requires-recent-login");
  });
  test("refuses a uid that could escape its own path", () => {
    assert.equal(checkDeletionRequest({uid: "../alice", token: {auth_time: NOW}}, NOW), "invalid-uid");
    assert.equal(checkDeletionRequest({uid: "", token: {auth_time: NOW}}, NOW), "invalid-uid");
  });
});

describe("isRecentSignIn / isSafeUid", () => {
  test("tolerates small clock skew but not far-future auth_time", () => {
    assert.equal(isRecentSignIn(NOW + 30, NOW), true);
    assert.equal(isRecentSignIn(NOW + 3600, NOW), false);
  });
  test("accepts ordinary Firebase uids", () => {
    assert.equal(isSafeUid("Xy9AbcDEF123ghiJKL456mnoPQ78"), true);
  });
  test("rejects path separators and non-strings", () => {
    assert.equal(isSafeUid("a/b"), false);
    assert.equal(isSafeUid(42), false);
  });
});

type Step = "revoke" | "photos" | "avatar" | "query" | "batch" | "leaderboard" | "tombstone" | "userTree" |
  "deleteUser";

/**
 * In-memory stand-ins that record every call in order. [fail] makes one
 * step throw (once, or always), [docs] seeds how many documents each
 * owner-field query returns before it runs dry.
 */
function fakeDeps(o: {
  /** Keyed by step name, or by the full call (e.g. "query:usernames.uid==alice"). */
  fail?: Record<string, unknown>;
  failOnce?: boolean;
  docs?: number;
  deleteUser?: (uid: string) => Promise<void>;
  revoke?: (uid: string) => Promise<void>;
} = {}): DeletionDeps & {calls: string[]} {
  const calls: string[] = [];
  const fail = {...(o.fail ?? {})};
  const step = async (name: Step, detail = "") => {
    const call = detail ? `${name}:${detail}` : name;
    calls.push(call);
    const key = call in fail ? call : name in fail ? name : undefined;
    if (key !== undefined) {
      const err = fail[key];
      if (o.failOnce) delete fail[key];
      throw err;
    }
  };
  let remaining = o.docs ?? 0;
  const query = (col: string, field: string, value: string) => {
    const q = {
      where: () => q,
      limit: () => q,
      get: async () => {
        await step("query", `${col}.${field}==${value}`);
        const n = Math.min(remaining, 400);
        remaining -= n;
        const docs = Array.from({length: n}, () => ({ref: {}}));
        return {empty: n === 0, size: n, docs};
      },
    };
    return q;
  };
  const db = {
    collection: (col: string) => ({
      where: (field: string, _op: string, value: string) => query(col, field, value),
      doc: (id: string) => ({
        delete: () => step("leaderboard", `${col}/${id}`),
        set: () => step("tombstone", `${col}/${id}`),
      }),
    }),
    doc: (path: string) => ({path}),
    batch: () => ({delete: () => undefined, commit: () => step("batch")}),
    recursiveDelete: () => step("userTree"),
  };
  return {
    calls,
    db: db as unknown as DeletionDeps["db"],
    bucket: {
      deleteFiles: (opts: {prefix: string}) => step("photos", opts.prefix),
      file: (name: string) => ({delete: () => step("avatar", name)}),
    },
    auth: {
      revokeRefreshTokens: o.revoke ?? (() => step("revoke")),
      deleteUser: o.deleteUser ?? (() => step("deleteUser")),
    },
  };
}

const ORDER = [
  "revoke",
  // The deleted-account marker comes BEFORE any data is deleted (Phase 7H;
  // in 7G it came just before the profile): firestore.rules then refuse a
  // stale session's creates while the deletions below run.
  "tombstone:deletedAccounts/alice",
  "photos:completion_photos/alice/",
  "photos:metadata_backup/completion_photos/alice/",
  "avatar:user_avatars/alice.png",
  "query:completions.userId==alice",
  "query:usernames.uid==alice",
  "query:feedback.userId==alice",
  "leaderboard:leaderboard_public/alice",
  "userTree",
  // Second Storage sweep (Phase 7D): uploads made meanwhile by another,
  // still-valid session.
  "photos:completion_photos/alice/",
  "photos:metadata_backup/completion_photos/alice/",
  "avatar:user_avatars/alice.png",
  "deleteUser",
];

describe("performAccountDeletion — order, ownership and retries", () => {
  test("revokes sessions, deletes only the caller's data, and deletes the Auth user last", async () => {
    const deps = fakeDeps();
    await performAccountDeletion(deps, "alice");
    assert.deepEqual(deps.calls, ORDER);
  });

  test("an account with no data at all still succeeds", async () => {
    const deps = fakeDeps({docs: 0});
    const report = await performAccountDeletion(deps, "alice");
    assert.deepEqual(report, {completions: 0, usernames: 0, feedback: 0});
  });

  test("pages through more owned documents than one batch holds", async () => {
    const deps = fakeDeps({docs: 900});
    const report = await performAccountDeletion(deps, "alice");
    // 900 completions → batches of 400, 400, 100, then an empty page.
    assert.equal(report.completions, 900);
    assert.equal(deps.calls.filter((c) => c === "batch").length, 3);
  });

  test("refuses an unsafe uid before touching anything", async () => {
    for (const uid of ["", "a/b", "..", "."]) {
      const deps = fakeDeps();
      await assert.rejects(performAccountDeletion(deps, uid));
      assert.deepEqual(deps.calls, []);
    }
  });

  for (const [i, failing] of ORDER.entries()) {
    // A repeated call (the second Storage sweep) fails at its first
    // occurrence; that case is already covered.
    if (ORDER.indexOf(failing) !== i) continue;
    test(`a failure at "${failing}" is reported, stops later steps, and a retry finishes`, async () => {
      const deps = fakeDeps({fail: {[failing]: new Error(`${failing} failed`)}, failOnce: true});
      await assert.rejects(performAccountDeletion(deps, "alice"));
      // Nothing after the failing step ran; the Auth user survives unless
      // the failure was the Auth deletion itself.
      assert.deepEqual(deps.calls, ORDER.slice(0, i + 1));
      deps.calls.length = 0;
      await performAccountDeletion(deps, "alice");
      assert.deepEqual(deps.calls, ORDER);
    });
  }

  test("treats an already-deleted Auth user as done (retry after a lost response)", async () => {
    const gone = async () => {
      throw Object.assign(new Error("gone"), {code: "auth/user-not-found"});
    };
    const deps = fakeDeps({deleteUser: gone, revoke: gone});
    await performAccountDeletion(deps, "alice");
    assert.ok(deps.calls.includes("userTree"), "data cleanup still runs");
  });

  test("accepts the Admin SDK's errorInfo.code shape too", async () => {
    const gone = async () => {
      throw Object.assign(new Error("gone"), {errorInfo: {code: "auth/user-not-found"}});
    };
    await performAccountDeletion(fakeDeps({deleteUser: gone}), "alice");
  });

  test("reports any other Auth failure as an error — never as success", async () => {
    await assert.rejects(
      performAccountDeletion(fakeDeps({deleteUser: async () => {
        throw Object.assign(new Error("boom"), {code: "auth/internal-error"});
      }}), "alice")
    );
  });

  test("a failure in the second Storage sweep is reported and the Auth user survives for a retry", async () => {
    let photoCalls = 0;
    const deps = fakeDeps();
    const original = deps.bucket.deleteFiles;
    deps.bucket.deleteFiles = async (opts) => {
      if (opts.prefix === "completion_photos/alice/" && ++photoCalls === 2) throw new Error("503");
      return original(opts);
    };
    await assert.rejects(performAccountDeletion(deps, "alice"));
    assert.ok(deps.calls.includes("userTree"));
    assert.ok(!deps.calls.includes("deleteUser"), "never reports success with files possibly left");
  });

  test("a revocation failure deletes nothing", async () => {
    const deps = fakeDeps({revoke: async () => {
      throw Object.assign(new Error("boom"), {code: "auth/internal-error"});
    }});
    await assert.rejects(performAccountDeletion(deps, "alice"));
    assert.deepEqual(deps.calls, []);
  });
});
