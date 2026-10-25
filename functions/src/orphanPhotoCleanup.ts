/**
 * Abandoned completion-photo cleanup (audit D-16, Phase 5).
 *
 * NOT DEPLOYED AND NOT SCHEDULED. Nothing in index.ts exports a trigger for
 * this module, so `firebase deploy` cannot ship it by accident; see
 * orphanPhotoCleanupJob.ts and REMEDIATION_CHECKLIST.md (Phase 5, D-16).
 *
 * The app uploads a completion photo to `completion_photos/{uid}/{date}.jpg`
 * BEFORE committing the completion (audit D-13). If that commit never
 * succeeds the photo is left behind — at most one per user per date, since a
 * retry overwrites the same object. This module finds such photos and, only
 * in explicit delete mode, removes them.
 *
 * A photo is ELIGIBLE only if every check below passes; anything uncertain
 * is skipped, never deleted:
 *   1. Its name is exactly `completion_photos/{uid}/{yyyy-MM-dd}.jpg` with a
 *      safe uid and a real calendar date. Legacy `{timestamp}.jpg` photos
 *      (referenced by older completions under a different name), avatars and
 *      anything else are skipped.
 *   2. The date is at least GRACE_DAYS before today (UTC). firestore.rules
 *      only accept a completion whose date is within ±1 day of server time,
 *      and an offline-queued commit is checked at the server's time when it
 *      arrives — so after two days no client can ever create the completion
 *      for that date. GRACE_DAYS = 7 leaves wide margin for time zones,
 *      clock skew and slow retries.
 *   3. The object itself (created AND last updated) is at least GRACE_DAYS
 *      old; missing or unreadable timestamps or generation → skipped.
 *   4. Firestore has no `completions/{uid}_{date}`, no Journal entry
 *      `users/{uid}/memories/{uid}_{date}`, and the user profile still
 *      exists (photos of deleted accounts are left to account deletion).
 *      Any lookup failure → the whole page is skipped.
 * In delete mode each candidate is re-checked right before deletion, and the
 * delete is conditional on the object's generation, so a photo replaced or
 * linked meanwhile is never removed.
 *
 * If `verifyChallengeCompletion` (AI verification, index.ts — disabled and
 * not deployed) is ever enabled, re-evaluate check 2: it can create a
 * completion without the ±1-day window.
 */

import {isSafeUid} from "./accountDeletion";

export const PHOTO_PREFIX = "completion_photos/";
export const GRACE_DAYS = 7;
const DAY_MS = 86_400_000;

export type SkipReason =
  | "unrecognised-name"
  | "legacy-name"
  | "too-recent"
  | "missing-metadata"
  | "has-completion"
  | "has-journal-entry"
  | "no-user-profile"
  | "lookup-failed"
  | "changed-before-delete";

export interface ListedFile {
  name: string;
  generation?: string | number;
  timeCreated?: string;
  updated?: string;
}

export interface CleanupDeps {
  /** One page of objects under [prefix]. */
  listPage(prefix: string, maxResults: number, pageToken?: string):
    Promise<{files: ListedFile[]; nextPageToken?: string}>;
  /** For each path, whether that Firestore document exists (one call). */
  docsExist(paths: string[]): Promise<boolean[]>;
  /** Deletes the object only if it is still at [generation]. Resolves false
   * when it changed or is already gone (nothing deleted). */
  deleteIfUnchanged(name: string, generation: string | number): Promise<boolean>;
}

export interface CleanupOptions {
  /** "dry-run" (default) deletes nothing. Deletion needs exactly "delete". */
  mode?: "dry-run" | "delete";
  now: Date;
  pageToken?: string;
  pageSize?: number;
  /** Stop after inspecting this many objects (bounded work per run). */
  maxObjects?: number;
  /** Never delete more than this many objects in one run. */
  maxDeletes?: number;
  /** Also return one outcome code per inspected object (for an operator's
   * local dry-run file; the scheduled job never logs these). */
  collectOutcomes?: boolean;
}

/** Per-object result: a skip reason, or what happened to an eligible one. */
export type CleanupOutcome = SkipReason | "eligible" | "deleted" | "delete-failed" | "delete-limit";

export interface CleanupReport {
  mode: "dry-run" | "delete";
  inspected: number;
  retained: number;
  eligible: number;
  deleted: number;
  deleteFailed: number;
  skipped: Partial<Record<SkipReason, number>>;
  /** Where the next run should continue; absent when the listing ended. */
  nextPageToken?: string;
  /** True when maxObjects or maxDeletes stopped the run early. */
  limitReached: boolean;
  /** Only with `collectOutcomes`. */
  outcomes?: Array<{name: string; outcome: CleanupOutcome}>;
}

interface Candidate {
  file: ListedFile;
  uid: string;
  date: string;
}

const NAME = /^completion_photos\/([^/]+)\/(\d{4})-(\d{2})-(\d{2})\.jpg$/;
const LEGACY_NAME = /^completion_photos\/[^/]+\/\d+\.jpg$/;

function utcDayStart(t: Date): number {
  return Date.UTC(t.getUTCFullYear(), t.getUTCMonth(), t.getUTCDate());
}

/** Steps 1–3 (no I/O): a candidate, or why the file is skipped. */
export function classifyFile(file: ListedFile, now: Date): Candidate | SkipReason {
  const m = NAME.exec(file.name);
  if (!m) return LEGACY_NAME.test(file.name) ? "legacy-name" : "unrecognised-name";
  const [, uid, y, mo, d] = m;
  if (!isSafeUid(uid)) return "unrecognised-name";
  const dateMs = Date.UTC(Number(y), Number(mo) - 1, Number(d));
  const check = new Date(dateMs);
  if (check.getUTCFullYear() !== Number(y) || check.getUTCMonth() !== Number(mo) - 1 ||
      check.getUTCDate() !== Number(d)) {
    return "unrecognised-name"; // e.g. 2026-02-30
  }
  const cutoff = utcDayStart(now) - GRACE_DAYS * DAY_MS;
  if (dateMs > cutoff) return "too-recent";

  const created = Date.parse(file.timeCreated ?? "");
  const updated = Date.parse(file.updated ?? "");
  if (!Number.isFinite(created) || !Number.isFinite(updated) ||
      file.generation === undefined || file.generation === "") {
    return "missing-metadata";
  }
  const ageLimit = now.getTime() - GRACE_DAYS * DAY_MS;
  if (created > ageLimit || updated > ageLimit) return "too-recent";
  return {file, uid, date: `${y}-${mo}-${d}`};
}

/** The documents whose existence decides a candidate, in a fixed order. */
function lookupPaths(c: Candidate): [string, string, string] {
  const id = `${c.uid}_${c.date}`;
  return [`completions/${id}`, `users/${c.uid}/memories/${id}`, `users/${c.uid}`];
}

function verdict([completion, entry, user]: boolean[]): SkipReason | "eligible" {
  if (completion) return "has-completion";
  if (entry) return "has-journal-entry";
  if (!user) return "no-user-profile";
  return "eligible";
}

/**
 * Inspects up to `maxObjects` completion photos, starting at `pageToken`,
 * and deletes eligible ones only when `mode === "delete"`. Listing errors
 * throw (nothing is deleted); lookup errors skip that page; per-object
 * delete failures are counted and the run continues.
 */
export async function runOrphanPhotoCleanup(
  deps: CleanupDeps,
  opts: CleanupOptions
): Promise<CleanupReport> {
  const mode = opts.mode === "delete" ? "delete" : "dry-run";
  const pageSize = Math.min(Math.max(opts.pageSize ?? 500, 1), 1000);
  const maxObjects = Math.max(opts.maxObjects ?? 2000, 1);
  const maxDeletes = Math.max(opts.maxDeletes ?? 100, 0);
  const report: CleanupReport = {
    mode, inspected: 0, retained: 0, eligible: 0, deleted: 0, deleteFailed: 0,
    skipped: {}, limitReached: false, ...(opts.collectOutcomes ? {outcomes: []} : {}),
  };
  const note = (name: string, outcome: CleanupOutcome) => report.outcomes?.push({name, outcome});
  const skip = (r: SkipReason, name: string) => {
    report.skipped[r] = (report.skipped[r] ?? 0) + 1;
    note(name, r);
  };

  let token = opts.pageToken;
  for (;;) {
    const room = maxObjects - report.inspected;
    if (room <= 0) {
      report.limitReached = true;
      break;
    }
    const page = await deps.listPage(PHOTO_PREFIX, Math.min(pageSize, room), token);
    report.inspected += page.files.length;

    const candidates: Candidate[] = [];
    for (const f of page.files) {
      const c = classifyFile(f, opts.now);
      if (typeof c === "string") skip(c, f.name);
      else candidates.push(c);
    }

    let found: boolean[] = [];
    try {
      found = candidates.length ? await deps.docsExist(candidates.flatMap(lookupPaths)) : [];
    } catch {
      for (const c of candidates) skip("lookup-failed", c.file.name);
      candidates.length = 0;
    }

    for (let i = 0; i < candidates.length; i++) {
      const name = candidates[i].file.name;
      const v = verdict(found.slice(i * 3, i * 3 + 3));
      if (v === "has-completion" || v === "has-journal-entry") {
        report.retained++;
        skip(v, name);
        continue;
      }
      if (v !== "eligible") {
        skip(v, name);
        continue;
      }
      report.eligible++;
      if (mode !== "delete") {
        note(name, "eligible");
        continue;
      }
      if (report.deleted + report.deleteFailed >= maxDeletes) {
        report.limitReached = true;
        note(name, "delete-limit");
        continue;
      }
      const result = await deleteCandidate(deps, candidates[i]);
      if (result === "deleted") report.deleted++;
      else if (result === "delete-failed") report.deleteFailed++;
      if (result === "changed-before-delete") skip(result, name);
      else note(name, result);
    }

    token = page.nextPageToken;
    if (!token) break;
  }
  if (token) report.nextPageToken = token;
  return report;
}

async function deleteCandidate(
  deps: CleanupDeps,
  c: Candidate
): Promise<"deleted" | "delete-failed" | "changed-before-delete"> {
  try {
    // Re-check immediately before deleting: a completion or Journal entry
    // created since the scan means the photo is in use.
    if (verdict(await deps.docsExist(lookupPaths(c))) !== "eligible") return "changed-before-delete";
    return await deps.deleteIfUnchanged(c.file.name, c.file.generation!) ? "deleted" : "changed-before-delete";
  } catch {
    return "delete-failed";
  }
}

// ── Firebase Admin adapters ─────────────────────────────────────────────────

/** Subset of the Admin SDK used by [adminCleanupDeps] (keeps this module
 * free of a hard firebase-admin import, so it is testable with fakes). */
export interface AdminBucketLike {
  getFiles(query: {prefix: string; maxResults: number; pageToken?: string; autoPaginate: false}):
    Promise<[Array<{name: string; metadata: {generation?: string | number; timeCreated?: string; updated?: string}}>,
      ({pageToken?: string} | null | undefined)?, unknown?]>;
  file(name: string): {
    getMetadata(): Promise<[{generation?: string | number}, ...unknown[]]>;
    delete(options?: {ifGenerationMatch?: string | number}): Promise<unknown>;
  };
}

export interface AdminFirestoreLike {
  doc(path: string): unknown;
  getAll(...refs: unknown[]): Promise<Array<{exists: boolean}>>;
}

export function adminCleanupDeps(db: AdminFirestoreLike, bucket: AdminBucketLike): CleanupDeps {
  return {
    async listPage(prefix, maxResults, pageToken) {
      const [files, next] = await bucket.getFiles({prefix, maxResults, pageToken, autoPaginate: false});
      return {
        files: files.map((f) => ({
          name: f.name,
          generation: f.metadata.generation,
          timeCreated: f.metadata.timeCreated,
          updated: f.metadata.updated,
        })),
        nextPageToken: next?.pageToken ?? undefined,
      };
    },
    async docsExist(paths) {
      const out: boolean[] = [];
      // getAll in chunks (one RPC each) to bound request size.
      for (let i = 0; i < paths.length; i += 300) {
        // Empty field mask (Phase 7G): existence only — no completion,
        // Journal or profile fields (captions, locations) are read.
        const snaps = await db.getAll(...paths.slice(i, i + 300).map((p) => db.doc(p)), {fieldMask: []});
        out.push(...snaps.map((s) => s.exists));
      }
      return out;
    },
    async deleteIfUnchanged(name, generation) {
      try {
        const file = bucket.file(name);
        // Read-check first (also works on the Storage emulator, which
        // ignores preconditions), then the atomic ifGenerationMatch that
        // real Cloud Storage enforces (412 if replaced in between).
        const [meta] = await file.getMetadata();
        if (String(meta.generation) !== String(generation)) return false;
        await file.delete({ifGenerationMatch: generation});
        return true;
      } catch (e) {
        const code = Number((e as {code?: unknown}).code);
        if (code === 404 || code === 412) return false; // gone, or replaced
        throw e;
      }
    },
  };
}
