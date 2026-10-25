/**
 * Unit tests for the abandoned-photo cleanup (audit D-16) with in-memory
 * fakes — failure injection, limits and boundaries. The real Storage +
 * Firestore path is covered by orphanPhotoCleanup.emulator.test.ts.
 */
import {test, describe} from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {join} from "node:path";
import {
  CleanupDeps, CleanupOptions, GRACE_DAYS, ListedFile, classifyFile, runOrphanPhotoCleanup,
} from "./orphanPhotoCleanup";

const DAY = 86_400_000;
const NOW = new Date("2026-10-19T12:00:00Z");
const dateKey = (daysAgo: number) =>
  new Date(Date.UTC(2026, 9, 19) - daysAgo * DAY).toISOString().slice(0, 10);
const iso = (daysAgo: number) => new Date(NOW.getTime() - daysAgo * DAY).toISOString();

/** An old, fully-described completion photo. */
function photo(uid: string, daysAgo: number, o: Partial<ListedFile> = {}): ListedFile {
  return {
    name: `completion_photos/${uid}/${dateKey(daysAgo)}.jpg`,
    generation: "1700000000000001",
    timeCreated: iso(daysAgo),
    updated: iso(daysAgo),
    ...o,
  };
}

class Fake implements CleanupDeps {
  files: ListedFile[] = [];
  docs = new Set<string>();
  deleted: string[] = [];
  listCalls = 0;
  failList = false;
  failLookups = 0; // fail the next N docsExist calls
  failDeleteFor = new Set<string>();
  onBeforeDelete?: (name: string) => void;

  async listPage(prefix: string, maxResults: number, pageToken?: string) {
    this.listCalls++;
    if (this.failList) throw Object.assign(new Error("storage/unauthorized"), {code: 403});
    const all = this.files.filter((f) => f.name.startsWith(prefix));
    const start = pageToken ? Number(pageToken) : 0;
    const files = all.slice(start, start + maxResults);
    const next = start + maxResults < all.length ? String(start + maxResults) : undefined;
    return {files, nextPageToken: next};
  }
  async docsExist(paths: string[]) {
    if (this.failLookups > 0) {
      this.failLookups--;
      throw new Error("firestore unavailable");
    }
    return paths.map((p) => this.docs.has(p));
  }
  async deleteIfUnchanged(name: string, generation: string | number) {
    this.onBeforeDelete?.(name);
    if (this.failDeleteFor.has(name)) throw new Error("storage 503");
    const i = this.files.findIndex((f) => f.name === name);
    if (i < 0 || this.files[i].generation !== generation) return false;
    this.files.splice(i, 1);
    this.deleted.push(name);
    return true;
  }
  /** A user profile exists for [uid] (so their orphans are eligible). */
  user(uid: string) {
    this.docs.add(`users/${uid}`);
    return this;
  }
}

const run = (f: Fake, o: Partial<CleanupOptions> = {}) =>
  runOrphanPhotoCleanup(f, {now: NOW, ...o});
const del = (f: Fake, o: Partial<CleanupOptions> = {}) => run(f, {mode: "delete", ...o});

describe("orphan photo cleanup — eligibility", () => {
  test("a photo with its completion is kept, even in delete mode", async () => {
    const f = new Fake().user("alice");
    f.files.push(photo("alice", 30));
    f.docs.add(`completions/alice_${dateKey(30)}`);
    const r = await del(f);
    assert.equal(r.retained, 1);
    assert.equal(r.eligible, 0);
    assert.deepEqual(f.deleted, []);
  });

  test("a photo with only a Journal entry is kept", async () => {
    const f = new Fake().user("alice");
    f.files.push(photo("alice", 30));
    f.docs.add(`users/alice/memories/alice_${dateKey(30)}`);
    const r = await del(f);
    assert.equal(r.skipped["has-journal-entry"], 1);
    assert.deepEqual(f.deleted, []);
  });

  test("a new photo with no completion yet (in-progress or retrying) is kept", async () => {
    const f = new Fake().user("alice");
    f.files.push(photo("alice", 0), photo("alice", 1), photo("alice", 3));
    const r = await del(f);
    assert.equal(r.skipped["too-recent"], 3);
    assert.deepEqual(f.deleted, []);
  });

  test("an old date whose object was re-uploaded recently (a retry) is kept", async () => {
    const f = new Fake().user("alice");
    f.files.push(photo("alice", 30, {updated: iso(1)}));
    const r = await del(f);
    assert.equal(r.skipped["too-recent"], 1);
    assert.deepEqual(f.deleted, []);
  });

  test("an old photo with no completion, entry or retry is deleted in delete mode", async () => {
    const f = new Fake().user("alice");
    f.files.push(photo("alice", 30));
    const r = await del(f);
    assert.equal(r.eligible, 1);
    assert.equal(r.deleted, 1);
    assert.deepEqual(f.deleted, [`completion_photos/alice/${dateKey(30)}.jpg`]);
  });

  test("photos of a deleted account (no profile) are left to account deletion", async () => {
    const f = new Fake();
    f.files.push(photo("ghost", 30));
    const r = await del(f);
    assert.equal(r.skipped["no-user-profile"], 1);
    assert.deepEqual(f.deleted, []);
  });

  test("avatars and other namespaces are never touched", async () => {
    const f = new Fake().user("alice");
    f.files.push({...photo("alice", 30), name: "user_avatars/alice.png"});
    const r = await del(f);
    assert.equal(r.inspected, 0); // listed by the completion_photos/ prefix only
    assert.equal(f.files.length, 1);
    // Even if a listing returned one, the name check refuses it.
    assert.equal(classifyFile({...photo("alice", 30), name: "user_avatars/alice.png"}, NOW),
      "unrecognised-name");
  });

  for (const [label, name, reason] of [
    ["legacy {timestamp}.jpg", "completion_photos/alice/1700000000000.jpg", "legacy-name"],
    ["nested folder", `completion_photos/alice/x/${dateKey(30)}.jpg`, "unrecognised-name"],
    ["impossible date", "completion_photos/alice/2026-02-30.jpg", "unrecognised-name"],
    ["unsafe uid", `completion_photos/../${dateKey(30)}.jpg`, "unrecognised-name"],
    ["not a .jpg", `completion_photos/alice/${dateKey(30)}.png`, "unrecognised-name"],
    ["the folder itself", "completion_photos/alice/", "unrecognised-name"],
  ] as const) {
    test(`malformed path is skipped: ${label}`, async () => {
      const f = new Fake().user("alice");
      f.files.push({...photo("alice", 30), name});
      const r = await del(f);
      assert.equal(r.skipped[reason], 1);
      assert.deepEqual(f.deleted, []);
    });
  }

  for (const [label, o] of [
    ["no timeCreated", {timeCreated: undefined}],
    ["no updated", {updated: undefined}],
    ["unparseable time", {timeCreated: "yesterday"}],
    ["no generation", {generation: undefined}],
  ] as const) {
    test(`missing metadata is skipped, never guessed: ${label}`, async () => {
      const f = new Fake().user("alice");
      f.files.push(photo("alice", 30, o));
      const r = await del(f);
      assert.equal(r.skipped["missing-metadata"], 1);
      assert.deepEqual(f.deleted, []);
    });
  }

  test("grace-period boundaries: exactly GRACE_DAYS old is eligible, one day less is not", () => {
    assert.equal(GRACE_DAYS, 7);
    // Date boundary (object itself old).
    assert.equal(typeof classifyFile(photo("a", 7, {timeCreated: iso(30), updated: iso(30)}), NOW), "object");
    assert.equal(classifyFile(photo("a", 6, {timeCreated: iso(30), updated: iso(30)}), NOW), "too-recent");
    // Object-age boundary (date itself old).
    assert.equal(typeof classifyFile(photo("a", 30, {timeCreated: iso(30), updated: iso(7)}), NOW), "object");
    const justUnder = new Date(NOW.getTime() - 7 * DAY + 1000).toISOString();
    assert.equal(classifyFile(photo("a", 30, {updated: justUnder}), NOW), "too-recent");
  });
});

describe("orphan photo cleanup — safety", () => {
  test("dry-run (the default) deletes nothing, but reports the same candidates", async () => {
    const f = new Fake().user("alice");
    f.files.push(photo("alice", 30), photo("alice", 40), photo("alice", 2));
    let deleteCalls = 0;
    f.onBeforeDelete = () => deleteCalls++;
    const r = await run(f);
    assert.equal(r.mode, "dry-run");
    assert.equal(r.eligible, 2);
    assert.equal(r.deleted, 0);
    assert.equal(deleteCalls, 0);
    assert.equal(f.files.length, 3);
    // Same eligibility in delete mode.
    const d = await del(f);
    assert.equal(d.eligible, 2);
  });

  test("anything other than mode \"delete\" is a dry-run", async () => {
    const f = new Fake().user("alice");
    f.files.push(photo("alice", 30));
    for (const mode of [undefined, "DELETE", "true", "dry-run"]) {
      const r = await run(f, {mode: mode as CleanupOptions["mode"]});
      assert.equal(r.mode, "dry-run");
    }
    assert.equal(f.files.length, 1);
  });

  test("a Storage permission error stops the run and deletes nothing", async () => {
    const f = new Fake().user("alice");
    f.files.push(photo("alice", 30));
    f.failList = true;
    await assert.rejects(del(f), /unauthorized/);
    assert.equal(f.files.length, 1);
  });

  test("a Firestore lookup failure skips that page — never treated as \"orphaned\"", async () => {
    const f = new Fake().user("alice");
    f.files.push(photo("alice", 30), photo("alice", 31), photo("alice", 32));
    f.failLookups = 1;
    const r = await del(f, {pageSize: 2});
    assert.equal(r.skipped["lookup-failed"], 2);
    // The next page's lookup works, so only that page is processed.
    assert.equal(r.deleted, 1);
    assert.equal(f.files.length, 2);
  });

  test("a lookup failure during the pre-delete re-check counts as a failure, deletes nothing", async () => {
    const f = new Fake().user("alice");
    f.files.push(photo("alice", 30));
    const orig = f.docsExist.bind(f);
    let calls = 0;
    f.docsExist = async (p) => {
      if (++calls === 2) throw new Error("unavailable");
      return orig(p);
    };
    const r = await del(f);
    assert.equal(r.deleteFailed, 1);
    assert.equal(f.files.length, 1);
  });

  test("a completion created between the scan and the delete keeps the photo", async () => {
    const f = new Fake().user("alice");
    f.files.push(photo("alice", 30));
    const orig = f.docsExist.bind(f);
    let calls = 0;
    f.docsExist = async (p) => {
      if (++calls === 2) f.docs.add(`completions/alice_${dateKey(30)}`);
      return orig(p);
    };
    const r = await del(f);
    assert.equal(r.skipped["changed-before-delete"], 1);
    assert.equal(r.deleted, 0);
    assert.equal(f.files.length, 1);
  });

  test("a photo replaced after listing (new generation) is not deleted", async () => {
    const f = new Fake().user("alice");
    f.files.push(photo("alice", 30));
    f.onBeforeDelete = () => {
      f.files[0] = {...f.files[0], generation: "1700000000000002"};
    };
    const r = await del(f);
    assert.equal(r.skipped["changed-before-delete"], 1);
    assert.equal(f.files.length, 1);
  });

  test("a per-object delete failure is counted and the run continues", async () => {
    const f = new Fake().user("alice");
    f.files.push(photo("alice", 30), photo("alice", 31), photo("alice", 32));
    f.failDeleteFor.add(`completion_photos/alice/${dateKey(31)}.jpg`);
    const r = await del(f);
    assert.equal(r.deleteFailed, 1);
    assert.equal(r.deleted, 2);
    assert.deepEqual(f.files.map((x) => x.name), [`completion_photos/alice/${dateKey(31)}.jpg`]);
  });

  test("repeated execution is idempotent: a second run deletes nothing more", async () => {
    const f = new Fake().user("alice");
    f.files.push(photo("alice", 30), photo("alice", 31));
    f.docs.add(`completions/alice_${dateKey(31)}`);
    assert.equal((await del(f)).deleted, 1);
    const again = await del(f);
    assert.equal(again.deleted, 0);
    assert.equal(again.retained, 1);
    assert.equal(f.files.length, 1);
  });
});

describe("orphan photo cleanup — bounded work", () => {
  test("paginates and reports where to continue", async () => {
    const f = new Fake().user("alice");
    for (let i = 0; i < 9; i++) f.files.push(photo("alice", 30 + i));
    const first = await run(f, {pageSize: 2, maxObjects: 5});
    assert.equal(first.inspected, 5);
    assert.equal(first.limitReached, true);
    assert.ok(first.nextPageToken);
    const rest = await run(f, {pageSize: 2, maxObjects: 100, pageToken: first.nextPageToken});
    assert.equal(rest.inspected, 4);
    assert.equal(rest.nextPageToken, undefined);
    assert.equal(first.eligible + rest.eligible, 9);
  });

  test("never deletes more than maxDeletes in one run", async () => {
    const f = new Fake().user("alice");
    for (let i = 0; i < 6; i++) f.files.push(photo("alice", 30 + i));
    const r = await del(f, {maxDeletes: 2});
    assert.equal(r.deleted, 2);
    assert.equal(r.eligible, 6);
    assert.equal(r.limitReached, true);
    assert.equal(f.files.length, 4);
  });

  test("maxDeletes = 0 deletes nothing even in delete mode", async () => {
    const f = new Fake().user("alice");
    f.files.push(photo("alice", 30));
    const r = await del(f, {maxDeletes: 0});
    assert.equal(r.deleted, 0);
    assert.equal(f.files.length, 1);
  });

  test("page size is clamped to the Storage maximum (1000)", async () => {
    const f = new Fake().user("alice");
    const seen: number[] = [];
    const orig = f.listPage.bind(f);
    f.listPage = async (p, max, t) => {
      seen.push(max);
      return orig(p, max, t);
    };
    await run(f, {pageSize: 50_000, maxObjects: 50_000});
    assert.deepEqual(seen, [1000]);
  });
});

describe("orphan photo cleanup — per-object outcome codes", () => {
  test("every inspected object gets exactly one reason or outcome", async () => {
    const f = new Fake().user("alice");
    f.files.push(
      photo("alice", 30), // orphan
      photo("alice", 31), // has completion
      photo("alice", 2), // too recent
      {...photo("alice", 40), name: "completion_photos/alice/1700000000000.jpg"}, // legacy
      photo("ghost", 30), // no profile
    );
    f.docs.add(`completions/alice_${dateKey(31)}`);
    const dry = await run(f, {collectOutcomes: true});
    assert.equal(dry.outcomes!.length, dry.inspected);
    const by = Object.fromEntries(dry.outcomes!.map((o) => [o.name, o.outcome]));
    assert.equal(by[`completion_photos/alice/${dateKey(30)}.jpg`], "eligible");
    assert.equal(by[`completion_photos/alice/${dateKey(31)}.jpg`], "has-completion");
    assert.equal(by[`completion_photos/alice/${dateKey(2)}.jpg`], "too-recent");
    assert.equal(by["completion_photos/alice/1700000000000.jpg"], "legacy-name");
    assert.equal(by[`completion_photos/ghost/${dateKey(30)}.jpg`], "no-user-profile");

    const wet = await run(f, {mode: "delete", collectOutcomes: true, maxDeletes: 1});
    assert.equal(wet.outcomes!.find((o) => o.outcome === "deleted")?.name, `completion_photos/alice/${dateKey(30)}.jpg`);
  });

  test("outcomes are off by default (the scheduled job logs counts only)", async () => {
    const f = new Fake().user("alice");
    f.files.push(photo("alice", 30));
    assert.equal((await run(f)).outcomes, undefined);
  });

  test("delete-limit and delete-failed are recorded per object", async () => {
    const f = new Fake().user("alice");
    f.files.push(photo("alice", 30), photo("alice", 31), photo("alice", 32));
    f.failDeleteFor.add(`completion_photos/alice/${dateKey(30)}.jpg`);
    const r = await run(f, {mode: "delete", collectOutcomes: true, maxDeletes: 2});
    const codes = r.outcomes!.map((o) => o.outcome).sort();
    assert.deepEqual(codes, ["delete-failed", "delete-limit", "deleted"]);
  });
});

describe("orphan photo cleanup — not deployable by accident", () => {
  test("index.ts does not export or import the scheduled job", () => {
    const index = readFileSync(join(__dirname, "..", "src", "index.ts"), "utf8");
    assert.doesNotMatch(index, /orphanPhotoCleanup/);
  });
});
