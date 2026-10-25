/**
 * Historical completion-photo metadata: inventory and remediation
 * (Phase 6, N-7). An OPERATOR TOOL, not a deployed function — run through
 * `opsCli.ts` against an emulator or, only with explicit authorization, a
 * real project. Dry-run is the default and writes nothing.
 *
 * Inventory reads only the first `headBytes` of each photo (header
 * metadata lives before the image data) and reports COUNTS per category.
 * Data APPENDED after the image (a second MPF image with its own EXIF/GPS,
 * motion-photo video; Phase 7C) is only visible with `fullRead`, which
 * downloads every photo in full. Object names go
 * only into the returned manifest (for the operator's local file) — never
 * into logs — and no coordinates, image bytes or URLs are reported.
 *
 * Remediation, per photo that has removable metadata:
 *   1. download the exact generation that was inspected;
 *   2. strip it losslessly (jpegMetadata.ts) and validate the result
 *      (complete JPEG, no GPS/XMP, same orientation, identical image data);
 *   3. optionally save the original bytes to a server-only backup path,
 *      `metadata_backup/completion_photos/{uid}/{runId}/{file}` — per user,
 *      so account deletion removes it (accountDeletion.ts). Written as a
 *      NEW object, not a Storage copy: a copy would inherit the original's
 *      download token, and a token URL bypasses storage.rules (which deny
 *      all client access to backups);
 *   4. overwrite IN PLACE, only if the object is still at that generation,
 *      keeping its content type, cache control and custom metadata —
 *      including `firebaseStorageDownloadTokens`, so the download URL saved
 *      in the completion and Journal entry keeps working;
 *   5. re-read and confirm the token and the absence of metadata.
 * If the overwrite does not happen after a backup was saved (the photo
 * changed or was deleted meanwhile — e.g. by account deletion — or the
 * write failed), that backup is deleted again, so no copy outlives the
 * photo it was made from.
 * Re-running is safe: clean photos are skipped, and a photo changed since
 * inspection is never overwritten. A run interrupted part-way is resumed
 * with `skipNames` (the names a previous run already finished).
 */

import {isSafeUid, metadataBackupPrefix} from "../accountDeletion";
import {hasRemovableMetadata, inspectJpeg, stripJpegMetadata, validateStripped} from "./jpegMetadata";

export const PHOTO_PREFIX = "completion_photos/";
/** Date-named (current) and timestamp-named (legacy) completion photos. */
const PHOTO_NAME = /^completion_photos\/[^/]+\/(\d{4}-\d{2}-\d{2}|\d{10,16})\.jpg$/;

export type InventoryCategory =
  | "clean"
  | "gps"
  | "other-metadata"
  | "appended-data"
  | "not-jpeg"
  | "malformed"
  | "header-beyond-read"
  | "unreadable"
  | "skipped-name";

export interface ObjectInfo {
  name: string;
  generation?: string | number;
  contentType?: string;
  cacheControl?: string;
  metadata?: Record<string, string>;
}

export interface PhotoStoreDeps {
  listPage(prefix: string, maxResults: number, pageToken?: string):
    Promise<{files: ObjectInfo[]; nextPageToken?: string}>;
  /** The first [bytes] bytes of that exact generation. */
  readHead(name: string, generation: string | number, bytes: number): Promise<Uint8Array>;
  /** The whole object at that exact generation. */
  readAll(name: string, generation: string | number): Promise<Uint8Array>;
  /** Current metadata (generation included), or null if gone. */
  getInfo(name: string): Promise<ObjectInfo | null>;
  /** Stores [data] (the original bytes) as a new object at [destination]
   * with no download token, so no token URL can reach the backup. */
  saveBackup(destination: string, data: Uint8Array, info: ObjectInfo): Promise<void>;
  /** Deletes a backup this run wrote (already gone counts as done). */
  deleteBackup(destination: string): Promise<void>;
  /** Writes [data] only if the object is still at [generation]; false otherwise. */
  writeIfGeneration(name: string, generation: string | number, data: Uint8Array, info: ObjectInfo): Promise<boolean>;
}

export interface InventoryOptions {
  pageToken?: string;
  maxObjects?: number;
  pageSize?: number;
  headBytes?: number;
  /** Download each photo in full, so data appended after the image is
   * found too. More egress; same privacy rules (nothing but counts and
   * names in the manifest). */
  fullRead?: boolean;
  /** Only this user's photos (`completion_photos/{uid}/`) — for a sample
   * or canary run on a test account. */
  uid?: string;
}

export interface InventoryItem {
  name: string;
  generation: string | number;
  category: InventoryCategory;
}

export interface InventoryReport {
  inspected: number;
  counts: Partial<Record<InventoryCategory, number>>;
  /** Photos with removable metadata (gps + other-metadata + appended-data). */
  needsRemediation: number;
  nextPageToken?: string;
  limitReached: boolean;
  /** For the operator's local manifest only — never log this. */
  items: InventoryItem[];
}

function categorize(head: Uint8Array): InventoryCategory {
  const m = inspectJpeg(head);
  if (m.kind === "not-jpeg") return "not-jpeg";
  if (m.kind === "malformed") return "malformed";
  if (m.kind === "incomplete-header") {
    // Metadata seen so far still counts; otherwise the header is longer
    // than what was read, so a full read is needed to decide.
    if (m.gps) return "gps";
    if (hasRemovableMetadata(m)) return "other-metadata";
    return "header-beyond-read";
  }
  if (m.gps) return "gps";
  if (!hasRemovableMetadata(m)) return "clean";
  const headerOnly = (m.exif && !m.exifOrientationOnly) || m.xmp || m.otherMetadata;
  return headerOnly ? "other-metadata" : "appended-data";
}

const NEEDS_REMEDIATION: ReadonlySet<InventoryCategory> =
  new Set<InventoryCategory>(["gps", "other-metadata", "appended-data"]);

/** Read-only scan; never writes. Listing errors throw; per-object read
 * errors are counted as "unreadable" and the scan continues. */
export async function inventoryPhotoMetadata(
  deps: PhotoStoreDeps,
  opts: InventoryOptions = {}
): Promise<InventoryReport> {
  const maxObjects = Math.max(opts.maxObjects ?? 1000, 1);
  const pageSize = Math.min(Math.max(opts.pageSize ?? 500, 1), 1000);
  const headBytes = Math.min(Math.max(opts.headBytes ?? 128 * 1024, 1024), 1024 * 1024);
  const report: InventoryReport = {inspected: 0, counts: {}, needsRemediation: 0, limitReached: false, items: []};
  const count = (c: InventoryCategory) => {
    report.counts[c] = (report.counts[c] ?? 0) + 1;
  };
  if (opts.uid !== undefined && !isSafeUid(opts.uid)) throw new Error("uid is invalid");
  const prefix = opts.uid === undefined ? PHOTO_PREFIX : `${PHOTO_PREFIX}${opts.uid}/`;
  let token = opts.pageToken;
  for (;;) {
    const room = maxObjects - report.inspected;
    if (room <= 0) {
      report.limitReached = true;
      break;
    }
    const page = await deps.listPage(prefix, Math.min(pageSize, room), token);
    for (const f of page.files) {
      report.inspected++;
      let category: InventoryCategory;
      if (!PHOTO_NAME.test(f.name) || f.generation === undefined || f.generation === "") {
        category = "skipped-name";
      } else {
        try {
          category = categorize(opts.fullRead ?
            await deps.readAll(f.name, f.generation) :
            await deps.readHead(f.name, f.generation, headBytes));
        } catch {
          category = "unreadable";
        }
      }
      count(category);
      if (NEEDS_REMEDIATION.has(category)) report.needsRemediation++;
      if (f.generation !== undefined) report.items.push({name: f.name, generation: f.generation, category});
    }
    token = page.nextPageToken;
    if (!token) break;
  }
  if (token) report.nextPageToken = token;
  return report;
}

export type RemediationOutcome =
  | "would-rewrite"
  | "rewritten"
  | "already-clean"
  | "changed-since-inventory"
  | "gone"
  | "not-strippable"
  | "validation-failed"
  | "write-failed"
  | "verify-failed";

export interface RemediationOptions {
  /** "dry-run" (default) writes nothing; only exactly "execute" writes. */
  mode?: "dry-run" | "execute";
  runId: string;
  /** Copy each original to its per-user backup path before overwriting. */
  backup: boolean;
  /** At most this many photos processed (bounded work per run). */
  maxObjects?: number;
  /** Names already finished by an earlier run (resume): not processed and
   * not counted against maxObjects. */
  skipNames?: Iterable<string>;
}

export interface RemediationEntry {
  name: string;
  generationBefore: string | number;
  generationAfter?: string | number;
  backup?: string;
  outcome: RemediationOutcome;
  detail?: string;
}

export interface RemediationReport {
  mode: "dry-run" | "execute";
  counts: Partial<Record<RemediationOutcome, number>>;
  /** The reversible manifest (operator's local file only). */
  entries: RemediationEntry[];
}

export const BACKUP_PREFIX = "metadata_backup/";

/** Outcomes after which a photo needs no further run (resume skips them). */
export const FINAL_OUTCOMES: ReadonlySet<RemediationOutcome> = new Set<RemediationOutcome>(
  ["rewritten", "already-clean", "gone", "not-strippable", "validation-failed"]);

/** Backup location of [name] (`completion_photos/{uid}/{file}`) for [runId]. */
export function backupPathFor(name: string, runId: string): string {
  const m = /^completion_photos\/([^/]+)\/([^/]+)$/.exec(name);
  if (!m) throw new Error("Not a completion photo name");
  return `${metadataBackupPrefix(m[1])}${runId}/${m[2]}`;
}

/** Remediates the inventory items that need it (gps / other-metadata /
 * appended-data / header-beyond-read). Per-object failures are recorded and
 * the run continues; nothing is overwritten without a validated
 * replacement. Every photo processed is read in full, so appended data is
 * removed even when a header-only inventory listed it for header metadata. */
export async function remediatePhotoMetadata(
  deps: PhotoStoreDeps,
  items: InventoryItem[],
  opts: RemediationOptions
): Promise<RemediationReport> {
  const mode = opts.mode === "execute" ? "execute" : "dry-run";
  if (!/^[A-Za-z0-9_-]{1,64}$/.test(opts.runId)) throw new Error("runId must be 1–64 of [A-Za-z0-9_-]");
  const report: RemediationReport = {mode, counts: {}, entries: []};
  const record = (e: RemediationEntry) => {
    report.entries.push(e);
    report.counts[e.outcome] = (report.counts[e.outcome] ?? 0) + 1;
  };
  const skip = new Set(opts.skipNames ?? []);
  const todo = items.filter((i) => !skip.has(i.name) &&
    (NEEDS_REMEDIATION.has(i.category) || i.category === "header-beyond-read"));
  const limit = Math.max(opts.maxObjects ?? 200, 0);
  for (const item of todo.slice(0, limit)) {
    const base = {name: item.name, generationBefore: item.generation};
    let backup: string | undefined;
    let overwritten = false;
    // A backup without the overwrite it protects is removed again, so no
    // copy outlives its photo (e.g. account deletion ran meanwhile).
    const dropBackup = async (): Promise<string | undefined> => {
      if (!backup || overwritten) return undefined;
      try {
        await deps.deleteBackup(backup);
        return "backup-removed";
      } catch {
        return "backup-removal-failed";
      }
    };
    try {
      const info = await deps.getInfo(item.name);
      if (!info) {
        record({...base, outcome: "gone"});
        continue;
      }
      if (String(info.generation) !== String(item.generation)) {
        record({...base, outcome: "changed-since-inventory"});
        continue;
      }
      const original = await deps.readAll(item.name, item.generation);
      if (!hasRemovableMetadata(inspectJpeg(original))) {
        record({...base, outcome: "already-clean"});
        continue;
      }
      const stripped = stripJpegMetadata(original);
      if (!stripped) {
        record({...base, outcome: "not-strippable"});
        continue;
      }
      const invalid = validateStripped(original, stripped);
      if (invalid) {
        record({...base, outcome: "validation-failed", detail: invalid});
        continue;
      }
      if (mode !== "execute") {
        record({...base, outcome: "would-rewrite"});
        continue;
      }
      if (opts.backup) {
        backup = backupPathFor(item.name, opts.runId);
        await deps.saveBackup(backup, original, info);
      }
      const written = await deps.writeIfGeneration(item.name, item.generation, stripped, {
        name: item.name,
        contentType: info.contentType ?? "image/jpeg",
        cacheControl: info.cacheControl,
        metadata: info.metadata,
      });
      if (!written) {
        const detail = await dropBackup();
        record({...base, backup: detail === "backup-removed" ? undefined : backup, outcome: "changed-since-inventory", detail});
        continue;
      }
      overwritten = true;
      const after = await deps.getInfo(item.name);
      const tokenKept = (after?.metadata?.firebaseStorageDownloadTokens ?? "") ===
        (info.metadata?.firebaseStorageDownloadTokens ?? "");
      const clean = after && !hasRemovableMetadata(inspectJpeg(await deps.readAll(item.name, after.generation!)));
      record({
        ...base, backup, generationAfter: after?.generation,
        outcome: tokenKept && clean ? "rewritten" : "verify-failed",
        detail: tokenKept ? undefined : "download-token-changed",
      });
    } catch (e) {
      const removed = await dropBackup();
      const kept = backup && removed !== "backup-removed" ? backup : undefined;
      record({
        ...base, backup: kept, outcome: "write-failed",
        detail: [e instanceof Error ? e.name : "error", removed].filter(Boolean).join("; "),
      });
    }
  }
  return report;
}

// ── Firebase Admin adapter ─────────────────────────────────────────────────

/** Subset of @google-cloud/storage's Bucket used here. */
export interface AdminPhotoBucket {
  getFiles(query: {prefix: string; maxResults: number; pageToken?: string; autoPaginate: false}):
    Promise<[Array<{name: string; metadata: Record<string, unknown>}>, ({pageToken?: string} | null | undefined)?, unknown?]>;
  file(name: string, options?: {generation?: string | number}): {
    download(options?: {start?: number; end?: number}): Promise<[Buffer]>;
    delete(options?: {ignoreNotFound?: boolean}): Promise<unknown>;
    getMetadata(): Promise<[Record<string, unknown>, ...unknown[]]>;
    save(data: Buffer, options: {resumable: false; contentType?: string; metadata: Record<string, unknown>;
      preconditionOpts?: {ifGenerationMatch?: string | number}}): Promise<void>;
  };
}

function toInfo(name: string, m: Record<string, unknown>): ObjectInfo {
  return {
    name,
    generation: m.generation as string | number | undefined,
    contentType: m.contentType as string | undefined,
    cacheControl: m.cacheControl as string | undefined,
    metadata: m.metadata as Record<string, string> | undefined,
  };
}

export function adminPhotoStore(bucket: AdminPhotoBucket): PhotoStoreDeps {
  const httpCode = (e: unknown) => Number((e as {code?: unknown}).code);
  return {
    async listPage(prefix, maxResults, pageToken) {
      const [files, next] = await bucket.getFiles({prefix, maxResults, pageToken, autoPaginate: false});
      return {files: files.map((f) => toInfo(f.name, f.metadata)), nextPageToken: next?.pageToken ?? undefined};
    },
    async readHead(name, generation, bytes) {
      const [buf] = await bucket.file(name, {generation}).download({start: 0, end: bytes - 1});
      return new Uint8Array(buf);
    },
    async readAll(name, generation) {
      const [buf] = await bucket.file(name, {generation}).download();
      return new Uint8Array(buf);
    },
    async getInfo(name) {
      try {
        const [m] = await bucket.file(name).getMetadata();
        return toInfo(name, m);
      } catch (e) {
        if (httpCode(e) === 404) return null;
        throw e;
      }
    },
    async saveBackup(destination, data, info) {
      // A fresh Admin SDK upload: no firebaseStorageDownloadTokens.
      await bucket.file(destination).save(Buffer.from(data), {
        resumable: false,
        contentType: info.contentType ?? "image/jpeg",
        metadata: {
          contentType: info.contentType ?? "image/jpeg",
          metadata: {backupOfGeneration: String(info.generation ?? "")},
        },
      });
    },
    async deleteBackup(destination) {
      if (!destination.startsWith(BACKUP_PREFIX)) throw new Error("Not a backup path");
      await bucket.file(destination).delete({ignoreNotFound: true});
    },
    async writeIfGeneration(name, generation, data, info) {
      // Read-check first (the Storage emulator ignores preconditions), then
      // the atomic ifGenerationMatch that real Cloud Storage enforces.
      const [current] = await bucket.file(name).getMetadata();
      if (String(current.generation) !== String(generation)) return false;
      try {
        await bucket.file(name).save(Buffer.from(data), {
          resumable: false,
          contentType: info.contentType,
          metadata: {
            contentType: info.contentType,
            ...(info.cacheControl ? {cacheControl: info.cacheControl} : {}),
            metadata: info.metadata ?? {},
          },
          preconditionOpts: {ifGenerationMatch: generation},
        });
        return true;
      } catch (e) {
        if (httpCode(e) === 412) return false;
        throw e;
      }
    },
  };
}
