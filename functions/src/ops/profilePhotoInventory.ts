/**
 * Read-only inventory of stored profile photo URLs (Phase 6, N-6).
 *
 * firestore.rules now only accept a new or changed `photoUrl` that is null,
 * the owner's own avatar in this app's bucket, or their sign-in provider's
 * `picture` claim. Values written before that rule are left as they are
 * (no migration), so this counts what is stored today. It never writes and
 * never reports URLs — only counts, plus the uids that need action
 * ("external" and "malformed") for the operator's local file (the
 * migration plan in PHASE_7A_RELEASE_RUNBOOK.md clears only those, after
 * approval). Legitimate photos are counted, never listed.
 */

export type ProfilePhotoCategory = "none" | "own-avatar" | "google-photo" | "external" | "malformed";

export const APP_STORAGE_BUCKET = "touchgrass-today.firebasestorage.app";

/** The same decision as firestore.rules' isAllowedProfilePhoto, minus the
 * token claim (not available offline): Google profile-photo hosts are
 * reported separately as "google-photo". */
export function classifyProfilePhoto(url: unknown, uid: string, bucket = APP_STORAGE_BUCKET): ProfilePhotoCategory {
  if (url === null || url === undefined) return "none";
  if (typeof url !== "string" || url.length === 0 || url.length > 2048) return "malformed";
  let u: URL;
  try {
    u = new URL(url);
  } catch {
    return "malformed";
  }
  if (u.protocol !== "https:" || u.username || u.password || (u.port && u.port !== "443")) return "external";
  const host = u.hostname.toLowerCase();
  if (host === "googleusercontent.com" || host.endsWith(".googleusercontent.com")) return "google-photo";
  const avatarPath = `/v0/b/${bucket}/o/user_avatars%2F${uid}.png`;
  if (host === "firebasestorage.googleapis.com" && u.pathname === avatarPath) return "own-avatar";
  return "external";
}

export interface ProfileDoc {
  id: string;
  photoUrl: unknown;
}

export interface ProfilePhotoDeps {
  /** One page of user documents ordered by document ID. */
  listUsers(limit: number, startAfterId?: string): Promise<ProfileDoc[]>;
}

export interface ProfilePhotoReport {
  inspected: number;
  counts: Partial<Record<ProfilePhotoCategory, number>>;
  /** uids needing action — "external" / "malformed" only (operator's
   * local file only). */
  uids: Partial<Record<ProfilePhotoCategory, string[]>>;
  /** Continue from here when the run stopped at maxDocs. */
  nextStartAfter?: string;
}

export async function inventoryProfilePhotos(
  deps: ProfilePhotoDeps,
  opts: {pageSize?: number; maxDocs?: number; startAfter?: string; bucket?: string} = {}
): Promise<ProfilePhotoReport> {
  const pageSize = Math.min(Math.max(opts.pageSize ?? 300, 1), 500);
  const maxDocs = Math.max(opts.maxDocs ?? 10_000, 1);
  const report: ProfilePhotoReport = {inspected: 0, counts: {}, uids: {}};
  let after = opts.startAfter;
  while (report.inspected < maxDocs) {
    const want = Math.min(pageSize, maxDocs - report.inspected);
    const page = await deps.listUsers(want, after);
    for (const d of page) {
      const c = classifyProfilePhoto(d.photoUrl, d.id, opts.bucket);
      report.counts[c] = (report.counts[c] ?? 0) + 1;
      if (c === "external" || c === "malformed") (report.uids[c] ??= []).push(d.id);
    }
    report.inspected += page.length;
    if (page.length < want) return report; // end of the collection
    after = page[page.length - 1].id;
  }
  report.nextStartAfter = after;
  return report;
}

/** Subset of firebase-admin Firestore used by [adminProfileDeps]. */
export interface AdminUsersDb {
  collection(path: string): {
    select(...fields: string[]): {
      orderBy(field: unknown): {
        limit(n: number): {
          startAfter(id: string): {get(): Promise<{docs: Array<{id: string; get(f: string): unknown}>}>};
          get(): Promise<{docs: Array<{id: string; get(f: string): unknown}>}>;
        };
      };
    };
    orderBy(field: unknown): {
      limit(n: number): {
        startAfter(id: string): {get(): Promise<{docs: Array<{id: string; get(f: string): unknown}>}>};
        get(): Promise<{docs: Array<{id: string; get(f: string): unknown}>}>;
      };
    };
  };
}

export function adminProfileDeps(db: AdminUsersDb, documentId: unknown): ProfilePhotoDeps {
  return {
    async listUsers(limit, startAfterId) {
      // Field mask (Phase 7G): only photoUrl leaves Firestore — never the
      // profile's email, settings or anything else.
      const q = db.collection("users").select("photoUrl").orderBy(documentId).limit(limit);
      const snap = await (startAfterId ? q.startAfter(startAfterId) : q).get();
      return snap.docs.map((d) => ({id: d.id, photoUrl: d.get("photoUrl")}));
    },
  };
}
