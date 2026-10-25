/**
 * Completion-photo download-token rotation (Phase 7C, made two-phase in
 * 7D). An OPERATOR TOOL, not a deployed function — run through `opsCli.ts`
 * against an emulator or, only with explicit authorization, a real
 * project. Dry-run is the default and writes nothing.
 *
 * Why: a download-token URL (`…/o/<path>?alt=media&token=<t>`) opens a
 * photo for ANYONE holding it — Storage rules are not evaluated for it.
 * While the live rules let any signed-in user call getDownloadURL on any
 * user's photo (KNOWN_BUGS B12), such URLs could be collected, and they
 * stay valid after the rules are fixed. Rotating the token revokes every
 * copy of the old URL; the owner's own stored links are moved to the new
 * token so the app keeps showing the photo.
 *
 * Per photo `completion_photos/{uid}/{file}.jpg`, in an order that never
 * leaves the owner's saved link pointing at a dead token:
 *   1. skip it if it changed within `minAgeMs` (an upload whose completion
 *      may still be being saved with the current URL);
 *   2. ADD a new random token next to the existing one(s) — a metadata
 *      patch, conditional on the object's metageneration. The old links
 *      keep working;
 *   3. point the owner's references at the new token: `completions` with
 *      `userId == uid` and `users/{uid}/memories/*` whose `photoUrl` names
 *      this object. Each update is a transaction that changes `photoUrl`
 *      only if the document still names this object;
 *   4. only when every reference update succeeded, REMOVE the old token(s):
 *        - `removeVia: "metadata"` (default): a metadata patch leaving only
 *          the new token. No bytes are downloaded or rewritten.
 *        - `removeVia: "rewrite"`: rewrite the object with the same bytes
 *          and metadata carrying only the new token (generation-checked).
 *      Then VERIFY that the stored token list is exactly the new token and
 *      the content (MD5) is unchanged; anything else is `verify-failed`.
 *      The Storage emulator merges token lists on a metadata patch, so on
 *      the emulator "metadata" ends in `verify-failed` — the tool detects a
 *      backend that didn't remove the old token instead of claiming success.
 *      Which mode revokes in PRODUCTION is decided by the test-account
 *      canary (PHASE_7D_TOKEN_ROTATION_RUNBOOK.md), never assumed.
 * State lives on the object (`tgTokenRotation` = run id,
 * `tgTokenRotationState` = added|done, `tgTokenRotationNew` = a short hash
 * of the new token — never the token), so an interrupted run resumes
 * without issuing a second token.
 *
 * Tokens and URLs are never logged or written to the report; the report
 * holds object names and counts for the operator's private file only.
 *
 * Not covered: profile photos (`user_avatars/`). Their URLs are shown to
 * every signed-in user on the leaderboard by design (separate decision).
 */

import {createHash, randomUUID} from "node:crypto";
import {isSafeUid} from "../accountDeletion";

export const PHOTO_PREFIX = "completion_photos/";
const PHOTO_NAME = /^completion_photos\/([^/]+)\/(\d{4}-\d{2}-\d{2}|\d{10,16})\.jpg$/;
const TOKEN_KEY = "firebaseStorageDownloadTokens";
/** Custom-metadata key recording which run rotated the object. */
export const ROTATION_MARKER = "tgTokenRotation";
/** "added" (new token present, old still valid) or "done" (old removed). */
export const ROTATION_STATE = "tgTokenRotationState";
/** First 16 hex chars of SHA-256(new token): identifies it on resume. */
export const ROTATION_NEW = "tgTokenRotationNew";

export interface TokenObjectInfo {
  name: string;
  generation?: string | number;
  metageneration?: string | number;
  contentType?: string;
  cacheControl?: string;
  md5Hash?: string;
  /** RFC 3339 time of the last change (Cloud Storage `updated`). */
  updated?: string;
  metadata?: Record<string, string>;
}

export interface TokenStoreDeps {
  listPage(prefix: string, maxResults: number, pageToken?: string):
    Promise<{files: TokenObjectInfo[]; nextPageToken?: string}>;
  getInfo(name: string): Promise<TokenObjectInfo | null>;
  /** Patches the given custom-metadata keys only if the object is still at
   * [generation] and [metageneration]; false when it changed or is gone. */
  patchMetadataIfUnchanged(name: string, generation: string | number, metageneration: string | number,
    metadata: Record<string, string>): Promise<boolean>;
  readAll(name: string, generation: string | number): Promise<Uint8Array>;
  /** Replaces the object (data AND all metadata) only if it is still at
   * [generation]; false when it changed or is gone. */
  rewriteIfGeneration(name: string, generation: string | number, data: Uint8Array,
    info: {contentType?: string; cacheControl?: string; metadata: Record<string, string>}): Promise<boolean>;
}

export interface PhotoReference {
  /** Firestore document path. */
  path: string;
  photoUrl: unknown;
}

export interface ReferenceDeps {
  /** Documents that may name [uid]'s photos: `completions` where
   * `userId == uid`, and every `users/{uid}/memories` document. Only the
   * `photoUrl` field is needed (the admin adapter reads nothing else). */
  findReferences(uid: string): Promise<PhotoReference[]>;
  /** Sets `photoUrl` of [path] to [url] only if the stored value still
   * names [objectName] in this bucket (checked in a transaction). */
  updateReference(path: string, objectName: string, url: string): Promise<boolean>;
}

/** The object a Firebase Storage download URL points at, if it is in
 * [bucket]; null for anything else. */
export function objectNameFromUrl(url: unknown, bucket: string): string | null {
  if (typeof url !== "string") return null;
  let u: URL;
  try {
    u = new URL(url);
  } catch {
    return null;
  }
  if (u.protocol !== "https:" || u.hostname !== "firebasestorage.googleapis.com") return null;
  const m = /^\/v0\/b\/([^/]+)\/o\/([^/]+)$/.exec(u.pathname);
  if (!m || m[1] !== bucket) return null;
  try {
    return decodeURIComponent(m[2]);
  } catch {
    return null;
  }
}

/** The token a download URL carries ("" when none). */
function tokenOf(url: unknown): string {
  try {
    return typeof url === "string" ? new URL(url).searchParams.get("token") ?? "" : "";
  } catch {
    return "";
  }
}

/** A download URL exactly as the Firebase client SDKs format it. */
export function downloadUrl(bucket: string, name: string, token: string): string {
  return `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/${encodeURIComponent(name)}` +
    `?alt=media&token=${encodeURIComponent(token)}`;
}

/** Short, non-reversible identifier of a token (safe to store in metadata). */
export function tokenTag(token: string): string {
  return createHash("sha256").update(token).digest("hex").slice(0, 16);
}

const tokenList = (v: string | undefined) => (v ?? "").split(",").map((t) => t.trim()).filter(Boolean);

export type RotationOutcome =
  | "would-rotate"
  | "rotated"
  | "references-updated"
  | "too-recent"
  | "no-token"
  | "skipped-name"
  | "changed-during-rotation"
  | "gone"
  | "rotate-failed"
  | "verify-failed"
  | "references-failed"
  | "awaiting-removal";

/** Outcomes after which a photo needs nothing more from this run. */
export const ROTATION_FINAL: ReadonlySet<RotationOutcome> = new Set<RotationOutcome>(
  ["rotated", "references-updated", "no-token", "skipped-name", "gone"]);

export interface RotationOptions {
  /** "dry-run" (default) writes nothing; only exactly "execute" writes. */
  mode?: "dry-run" | "execute";
  runId: string;
  bucket: string;
  now: Date;
  /** How the old token is removed (step 4); decided by the canary. */
  removeVia?: "metadata" | "rewrite";
  /** Photos changed more recently than this are left for a later run. */
  minAgeMs?: number;
  maxObjects?: number;
  pageSize?: number;
  pageToken?: string;
  /** Names an earlier run already finished (resume). */
  skipNames?: Iterable<string>;
  /** Only this user's photos (`completion_photos/{uid}/`) — for the
   * canary run on a test account. */
  uid?: string;
  /** Test hook: the new token for a photo (default: a random UUID). */
  newToken?: () => string;
  /** Stop after step 3 (new token added, links moved, old token still
   * valid) — the controlled revocation experiment checks both links here,
   * then re-runs with the same run id to remove the old token. */
  stopBeforeRemove?: boolean;
  /** Test hook: runs between steps 3 and 4. */
  beforeRemove?: (name: string) => Promise<void>;
}

export interface RotationEntry {
  name: string;
  generationBefore?: string | number;
  generationAfter?: string | number;
  outcome: RotationOutcome;
  /** Which step it ended at: add | references | remove | verify. */
  step?: string;
  /** Owner documents naming this object, and how many of them carry a
   * token the object no longer accepts (a stale, already-broken link). */
  refsTotal?: number;
  refsStale?: number;
  /** References pointed at the new token / already current / that no
   * longer named this object when updated. */
  refsUpdated?: number;
  refsCurrent?: number;
  refsChanged?: number;
  detail?: string;
}

export interface RotationReport {
  mode: "dry-run" | "execute";
  removeVia: "metadata" | "rewrite";
  inspected: number;
  counts: Partial<Record<RotationOutcome, number>>;
  referencesUpdated: number;
  /** Eligible photos that no owner document names (orphans or legacy). */
  photosWithoutReferences: number;
  /** Eligible photos with at least one owner link carrying a token the
   * object doesn't accept (inconsistent saved links). */
  photosWithStaleReferences: number;
  /** Production writes this run made, or (dry-run) would make. */
  writes: {metadataPatches: number; objectRewrites: number; linkUpdates: number};
  /** Owner documents (of the users whose photos this run reached) whose
   * non-empty `photoUrl` the rotation can't follow (Phase 7F):
   * - otherOwnerPath: names an object in this bucket that isn't under the
   *   document owner's own `completion_photos/{uid}/` (another user's photo,
   *   or a different folder) — such a link would break when that object is
   *   rotated, because only its owner's documents are updated;
   * - otherBucketOrHost: a Storage link to another bucket, or another host;
   * - unparseable: not an https URL;
   * - withoutToken: names a photo here but carries no token. */
  referenceAnomalies: {otherOwnerPath: number; otherBucketOrHost: number; unparseable: number; withoutToken: number};
  limitReached: boolean;
  nextPageToken?: string;
  /** Operator's private file only — names, never tokens or URLs. */
  entries: RotationEntry[];
}

/** Rotates the download token of every completion photo (bounded per run). */
export async function rotatePhotoTokens(
  store: TokenStoreDeps,
  refs: ReferenceDeps,
  opts: RotationOptions
): Promise<RotationReport> {
  const mode = opts.mode === "execute" ? "execute" : "dry-run";
  const removeVia = opts.removeVia === "rewrite" ? "rewrite" : "metadata";
  if (!/^[A-Za-z0-9_-]{1,64}$/.test(opts.runId)) throw new Error("runId must be 1–64 of [A-Za-z0-9_-]");
  if (!/^[a-z0-9][a-z0-9._-]{2,221}$/.test(opts.bucket)) throw new Error("bucket name is invalid");
  const minAgeMs = Math.max(opts.minAgeMs ?? 10 * 60 * 1000, 0);
  const maxObjects = Math.max(opts.maxObjects ?? 200, 1);
  const pageSize = Math.min(Math.max(opts.pageSize ?? 200, 1), 1000);
  const newToken = opts.newToken ?? (() => randomUUID());
  if (opts.uid !== undefined && !isSafeUid(opts.uid)) throw new Error("uid is invalid");
  const prefix = opts.uid === undefined ? PHOTO_PREFIX : `${PHOTO_PREFIX}${opts.uid}/`;
  const skip = new Set(opts.skipNames ?? []);
  const report: RotationReport = {
    mode, removeVia, inspected: 0, counts: {}, referencesUpdated: 0, photosWithoutReferences: 0,
    photosWithStaleReferences: 0, writes: {metadataPatches: 0, objectRewrites: 0, linkUpdates: 0},
    referenceAnomalies: {otherOwnerPath: 0, otherBucketOrHost: 0, unparseable: 0, withoutToken: 0},
    limitReached: false, entries: [],
  };
  const record = (e: RotationEntry) => {
    report.entries.push(e);
    report.counts[e.outcome] = (report.counts[e.outcome] ?? 0) + 1;
    report.referencesUpdated += e.refsUpdated ?? 0;
    report.writes.linkUpdates += e.refsUpdated ?? 0;
    if (e.refsTotal === 0) report.photosWithoutReferences++;
    if ((e.refsStale ?? 0) > 0) report.photosWithStaleReferences++;
  };
  /** Counts the owner's links to [name] and how many are already stale. */
  const describeRefs = async (name: string, uid: string, tokens: string[], entry: RotationEntry) => {
    const mine = (await referencesOf(uid)).filter((r) => objectNameFromUrl(r.photoUrl, opts.bucket) === name);
    entry.refsTotal = mine.length;
    entry.refsStale = mine.filter((r) => !tokens.includes(tokenOf(r.photoUrl))).length;
  };

  // References are fetched once per user (listing is sorted by name, so a
  // user's photos are contiguous).
  let refsUid: string | undefined;
  let refsCache: PhotoReference[] = [];
  const referencesOf = async (uid: string) => {
    if (refsUid !== uid) {
      refsCache = await refs.findReferences(uid);
      refsUid = uid;
      countAnomalies(uid, refsCache);
    }
    return refsCache;
  };
  /** Classifies, once per user, the links the rotation can't follow. */
  const countAnomalies = (uid: string, found: PhotoReference[]) => {
    const a = report.referenceAnomalies;
    for (const r of found) {
      if (typeof r.photoUrl !== "string" || r.photoUrl === "") continue;
      const name = objectNameFromUrl(r.photoUrl, opts.bucket);
      if (name === null) {
        let https = false;
        try {
          https = new URL(r.photoUrl).protocol === "https:";
        } catch {
          // not a URL
        }
        if (https) a.otherBucketOrHost++;
        else a.unparseable++;
      } else if (!name.startsWith(`${PHOTO_PREFIX}${uid}/`)) {
        a.otherOwnerPath++;
      } else if (tokenOf(r.photoUrl) === "") {
        a.withoutToken++;
      }
    }
  };

  /** Points every reference to [name] at [token]; counts what happened. */
  const reconcile = async (name: string, uid: string, token: string, entry: RotationEntry, write: boolean) => {
    entry.refsUpdated = 0;
    entry.refsCurrent = 0;
    entry.refsChanged = 0;
    const url = downloadUrl(opts.bucket, name, token);
    for (const r of await referencesOf(uid)) {
      if (objectNameFromUrl(r.photoUrl, opts.bucket) !== name) continue;
      if (tokenOf(r.photoUrl) === token) {
        entry.refsCurrent++;
        continue;
      }
      if (!write) {
        entry.refsUpdated++;
        continue;
      }
      if (await refs.updateReference(r.path, name, url)) {
        entry.refsUpdated++;
        r.photoUrl = url; // keep the per-user cache current
      } else {
        entry.refsChanged++;
      }
    }
  };

  /** Step 4 and verification for one photo whose links are on [token]. */
  const removeOldTokens = async (name: string, token: string, entry: RotationEntry): Promise<void> => {
    entry.step = "remove";
    await opts.beforeRemove?.(name);
    const info = await store.getInfo(name);
    if (!info || info.generation === undefined || info.metageneration === undefined) {
      record({...entry, outcome: "changed-during-rotation", detail: "gone-before-remove"});
      return;
    }
    if (!tokenList(info.metadata?.[TOKEN_KEY]).includes(token)) {
      record({...entry, outcome: "changed-during-rotation", detail: "new-token-missing"});
      return;
    }
    const metadata = {...(info.metadata ?? {}), [TOKEN_KEY]: token, [ROTATION_STATE]: "done"};
    const written = removeVia === "rewrite" ?
      await store.rewriteIfGeneration(name, info.generation, await store.readAll(name, info.generation),
        {contentType: info.contentType, cacheControl: info.cacheControl, metadata}) :
      await store.patchMetadataIfUnchanged(name, info.generation, info.metageneration,
        {[TOKEN_KEY]: token, [ROTATION_STATE]: "done"});
    if (!written) {
      // Links already use the new token, which stays valid: nothing broke.
      record({...entry, outcome: "changed-during-rotation"});
      return;
    }
    if (removeVia === "rewrite") report.writes.objectRewrites++;
    else report.writes.metadataPatches++;
    entry.step = "verify";
    const after = await store.getInfo(name);
    entry.generationAfter = after?.generation;
    const left = tokenList(after?.metadata?.[TOKEN_KEY]);
    if (!after) {
      record({...entry, outcome: "verify-failed", detail: "gone-after-remove"});
    } else if (left.length !== 1 || left[0] !== token) {
      record({...entry, outcome: "verify-failed", detail: "old-token-still-present"});
    } else if (info.md5Hash !== undefined && after.md5Hash !== info.md5Hash) {
      record({...entry, outcome: "verify-failed", detail: "content-changed"});
    } else {
      record({...entry, outcome: "rotated"});
    }
  };

  let pageToken = opts.pageToken;
  for (;;) {
    const room = maxObjects - report.inspected;
    if (room <= 0) {
      report.limitReached = true;
      break;
    }
    const page = await store.listPage(prefix, Math.min(pageSize, room), pageToken);
    for (const listed of page.files) {
      if (skip.has(listed.name)) continue;
      report.inspected++;
      const m = PHOTO_NAME.exec(listed.name);
      const entry: RotationEntry = {name: listed.name, generationBefore: listed.generation, outcome: "skipped-name"};
      if (!m || !isSafeUid(m[1])) {
        record(entry);
        continue;
      }
      const uid = m[1];
      let added = false;
      try {
        const info = await store.getInfo(listed.name);
        if (!info || info.generation === undefined) {
          record({...entry, outcome: "gone"});
          continue;
        }
        entry.generationBefore = info.generation;
        const custom = {...(info.metadata ?? {})};
        const tokens = tokenList(custom[TOKEN_KEY]);
        const ours = custom[ROTATION_MARKER] === opts.runId;

        if (ours && custom[ROTATION_STATE] === "done" && tokens.length === 1) {
          // Finished by an interrupted attempt of this run: links only.
          added = true;
          entry.step = "references";
          await describeRefs(listed.name, uid, tokens, entry);
          await reconcile(listed.name, uid, tokens[0], entry, mode === "execute");
          record({...entry, outcome: mode === "execute" ? "references-updated" : "would-rotate"});
          continue;
        }
        let token: string | undefined;
        if (ours && custom[ROTATION_STATE] === "added") {
          // Step 2 done by an interrupted attempt: reuse its token.
          token = tokens.find((t) => tokenTag(t) === custom[ROTATION_NEW]);
          if (!token) {
            record({...entry, outcome: "verify-failed", detail: "added-token-not-found"});
            continue;
          }
        } else {
          if (tokens.length === 0) {
            record({...entry, outcome: "no-token"});
            continue;
          }
          const changedAt = Date.parse(info.updated ?? "");
          if (!Number.isFinite(changedAt) || opts.now.getTime() - changedAt < minAgeMs) {
            record({...entry, outcome: "too-recent"});
            continue;
          }
        }
        await describeRefs(listed.name, uid, tokens, entry);
        if (mode !== "execute") {
          await reconcile(listed.name, uid, token ?? "(new)", entry, false);
          if (!token) report.writes.metadataPatches++; // add
          if (!opts.stopBeforeRemove) {
            if (removeVia === "rewrite") report.writes.objectRewrites++;
            else report.writes.metadataPatches++;
          }
          record({...entry, outcome: "would-rotate"});
          continue;
        }
        if (!token) {
          // Step 2: add the new token; every existing link keeps working.
          entry.step = "add";
          if (info.metageneration === undefined) {
            record({...entry, outcome: "rotate-failed", detail: "no-metageneration"});
            continue;
          }
          token = newToken();
          const ok = await store.patchMetadataIfUnchanged(listed.name, info.generation, info.metageneration, {
            [TOKEN_KEY]: [...tokens, token].join(","),
            [ROTATION_MARKER]: opts.runId,
            [ROTATION_STATE]: "added",
            [ROTATION_NEW]: tokenTag(token),
          });
          if (!ok) {
            record({...entry, outcome: "changed-during-rotation"});
            continue;
          }
          report.writes.metadataPatches++;
        }
        added = true;
        // Step 3: links → new token.
        entry.step = "references";
        await reconcile(listed.name, uid, token, entry, true);
        if (opts.stopBeforeRemove) {
          // Controlled experiment: both tokens valid, links on the new one.
          // Re-running with the same run id (without this option) removes
          // the old token.
          record({...entry, outcome: "awaiting-removal"});
          continue;
        }
        // Step 4: only now remove the old token(s).
        await removeOldTokens(listed.name, token, entry);
      } catch (e) {
        // Error class only: messages can contain object paths. If the new
        // token was added, the old one is still valid: nothing is broken,
        // and a resume continues from the recorded state.
        const name = e instanceof Error ? e.name : "error";
        const failedAt = entry.step ?? "add";
        record({
          ...entry, outcome: added && failedAt === "references" ? "references-failed" : "rotate-failed",
          step: failedAt, detail: name,
        });
      }
    }
    pageToken = page.nextPageToken;
    if (!pageToken) break;
  }
  if (pageToken) report.nextPageToken = pageToken;
  return report;
}

// ── Firebase Admin adapters ────────────────────────────────────────────────

/** Subset of @google-cloud/storage's Bucket used here. */
export interface AdminTokenBucket {
  getFiles(query: {prefix: string; maxResults: number; pageToken?: string; autoPaginate: false}):
    Promise<[Array<{name: string; metadata: Record<string, unknown>}>, ({pageToken?: string} | null | undefined)?, unknown?]>;
  file(name: string, options?: {generation?: string | number}): {
    download(): Promise<[Buffer]>;
    getMetadata(): Promise<[Record<string, unknown>, ...unknown[]]>;
    setMetadata(metadata: Record<string, unknown>, options?: {ifMetagenerationMatch?: string | number}):
      Promise<unknown>;
    save(data: Buffer, options: {resumable: false; contentType?: string; metadata: Record<string, unknown>;
      preconditionOpts?: {ifGenerationMatch?: string | number}}): Promise<void>;
  };
}

function toInfo(name: string, m: Record<string, unknown>): TokenObjectInfo {
  return {
    name,
    generation: m.generation as string | number | undefined,
    metageneration: m.metageneration as string | number | undefined,
    contentType: m.contentType as string | undefined,
    cacheControl: m.cacheControl as string | undefined,
    md5Hash: m.md5Hash as string | undefined,
    updated: m.updated as string | undefined,
    metadata: m.metadata as Record<string, string> | undefined,
  };
}

export function adminTokenStore(bucket: AdminTokenBucket): TokenStoreDeps {
  const httpCode = (e: unknown) => Number((e as {code?: unknown}).code);
  /** Current metadata, or null if gone. */
  const current = async (name: string) => {
    try {
      return (await bucket.file(name).getMetadata())[0];
    } catch (e) {
      if (httpCode(e) === 404) return null;
      throw e;
    }
  };
  return {
    async listPage(prefix, maxResults, pageToken) {
      const [files, next] = await bucket.getFiles({prefix, maxResults, pageToken, autoPaginate: false});
      return {files: files.map((f) => toInfo(f.name, f.metadata)), nextPageToken: next?.pageToken ?? undefined};
    },
    async getInfo(name) {
      const m = await current(name);
      return m ? toInfo(name, m) : null;
    },
    async patchMetadataIfUnchanged(name, generation, metageneration, metadata) {
      // Read-check first (the Storage emulator ignores preconditions), then
      // the atomic ifMetagenerationMatch that real Cloud Storage enforces.
      const m = await current(name);
      if (!m || String(m.generation) !== String(generation) ||
          String(m.metageneration) !== String(metageneration)) return false;
      try {
        await bucket.file(name).setMetadata({metadata}, {ifMetagenerationMatch: metageneration});
        return true;
      } catch (e) {
        if (httpCode(e) === 412 || httpCode(e) === 404) return false;
        throw e;
      }
    },
    async readAll(name, generation) {
      const [buf] = await bucket.file(name, {generation}).download();
      return new Uint8Array(buf);
    },
    async rewriteIfGeneration(name, generation, data, info) {
      const m = await current(name);
      if (!m || String(m.generation) !== String(generation)) return false;
      try {
        await bucket.file(name).save(Buffer.from(data), {
          resumable: false,
          contentType: info.contentType,
          metadata: {
            contentType: info.contentType,
            ...(info.cacheControl ? {cacheControl: info.cacheControl} : {}),
            metadata: info.metadata,
          },
          preconditionOpts: {ifGenerationMatch: generation},
        });
        return true;
      } catch (e) {
        if (httpCode(e) === 412 || httpCode(e) === 404) return false;
        throw e;
      }
    },
  };
}

/** Subset of firebase-admin Firestore used here. */
type AdminRefQuery = {get(): Promise<{docs: Array<{ref: {path: string}; get(f: string): unknown}>}>};
export interface AdminRefDb {
  collection(path: string): {
    where(field: string, op: "==", value: string): {select(...fields: string[]): AdminRefQuery};
    select(...fields: string[]): AdminRefQuery;
  };
  doc(path: string): unknown;
  runTransaction<T>(fn: (tx: {
    get(ref: unknown): Promise<{exists: boolean; get(f: string): unknown}>;
    update(ref: unknown, data: Record<string, unknown>): unknown;
  }) => Promise<T>): Promise<T>;
}

export function adminReferenceDeps(db: AdminRefDb, bucket: string): ReferenceDeps {
  return {
    async findReferences(uid) {
      if (!isSafeUid(uid)) return [];
      // Field mask: only `photoUrl` leaves Firestore — never captions,
      // locations or anything else in these documents (Phase 7F).
      const [completions, memories] = await Promise.all([
        db.collection("completions").where("userId", "==", uid).select("photoUrl").get(),
        db.collection(`users/${uid}/memories`).select("photoUrl").get(),
      ]);
      return [...completions.docs, ...memories.docs].map((d) => ({path: d.ref.path, photoUrl: d.get("photoUrl")}));
    },
    async updateReference(path, objectName, url) {
      const ref = db.doc(path);
      return db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (!snap.exists || objectNameFromUrl(snap.get("photoUrl"), bucket) !== objectName) return false;
        tx.update(ref, {photoUrl: url});
        return true;
      });
    },
  };
}
