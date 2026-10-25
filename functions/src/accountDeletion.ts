/**
 * Server-side account deletion (audit D-04).
 *
 * The client can't delete a user's data itself (firestore.rules /
 * storage.rules deny those deletes on purpose), so the `deleteAccount`
 * callable in index.ts runs this with the Admin SDK. Dependencies are
 * injected so the whole flow is testable against the local emulators
 * (accountDeletion.emulator.test.ts) and with fakes (accountDeletion.test.ts).
 *
 * Design:
 * - **Authenticated + authorized:** the uid always comes from the verified
 *   ID token, never from request data, so a caller can only delete their
 *   own account.
 * - **Recent sign-in required:** the token's `auth_time` must be within
 *   RECENT_SIGN_IN_SECONDS — the client re-authenticates first, mirroring
 *   Firebase Auth's own requires-recent-login rule for deleting a user.
 * - **Retry-safe / idempotent:** every step deletes "whatever is still
 *   there", so re-running after a partial failure resumes cleanly.
 * - **Other sessions signed out first:** refresh tokens are revoked before
 *   any data is deleted, so another signed-in device can't keep writing
 *   for longer than its current ID token lives (at most an hour). The
 *   caller can still sign in again and retry (revocation doesn't block
 *   new sign-ins).
 * - **Auth account last:** if anything earlier fails, the user can still
 *   sign in and retry. Success is reported only after every step,
 *   including the Auth deletion, has completed.
 */

import type {Firestore, Query} from "firebase-admin/firestore";

/** Where the photo-metadata operator tool (ops/photoMetadataJob.ts) keeps
 * the originals it replaced, per user, so they are deleted with the
 * account. Server-only: storage.rules deny all client access. */
export function metadataBackupPrefix(uid: string): string {
  return `metadata_backup/completion_photos/${uid}/`;
}

/** Server-only markers of deleted accounts (Phase 7G); see deleteUserData. */
export const DELETED_ACCOUNTS = "deletedAccounts";
/** A deleted account's ID tokens die within an hour of the revocation that
 * starts the deletion; the marker's suggested lifetime adds a margin. */
export const DELETED_ACCOUNT_MARKER_TTL_MS = 2 * 60 * 60 * 1000;

/** How fresh the caller's sign-in must be, in seconds. */
export const RECENT_SIGN_IN_SECONDS = 5 * 60;

/** Subset of a firebase-admin Storage bucket this flow uses. */
export interface BucketLike {
  deleteFiles(options: {prefix: string; force?: boolean}): Promise<unknown>;
  file(name: string): {delete(options?: {ignoreNotFound?: boolean}): Promise<unknown>};
}

/** Subset of firebase-admin Auth this flow uses. */
export interface AuthLike {
  revokeRefreshTokens(uid: string): Promise<void>;
  deleteUser(uid: string): Promise<void>;
}

/** The Firebase Auth error code of [e], if any. */
function authErrorCode(e: unknown): string | undefined {
  return (e as {code?: string}).code ?? (e as {errorInfo?: {code?: string}}).errorInfo?.code;
}

export interface DeletionDeps {
  db: Firestore;
  bucket: BucketLike;
  auth: AuthLike;
}

/** Why a deletion request was refused before any data was touched. */
export type DeletionRefusal = "unauthenticated" | "requires-recent-login" | "invalid-uid";

/** Firebase uids are opaque but never contain path separators; refuse
 * anything that could escape the user's own document/prefix. */
export function isSafeUid(uid: unknown): uid is string {
  return typeof uid === "string" && uid.length > 0 && uid.length <= 128 &&
    !uid.includes("/") && uid !== "." && uid !== "..";
}

/** True when the ID token's `auth_time` (seconds) is recent enough. */
export function isRecentSignIn(authTimeSeconds: unknown, nowSeconds: number): boolean {
  if (typeof authTimeSeconds !== "number" || !Number.isFinite(authTimeSeconds)) return false;
  const age = nowSeconds - authTimeSeconds;
  // A small negative age tolerates clock skew; anything older is refused.
  return age >= -60 && age <= RECENT_SIGN_IN_SECONDS;
}

/** Decides whether a callable request may proceed. Null = allowed. */
export function checkDeletionRequest(
  auth: {uid: string; token: {auth_time?: unknown}} | undefined,
  nowSeconds: number
): DeletionRefusal | null {
  if (!auth) return "unauthenticated";
  if (!isSafeUid(auth.uid)) return "invalid-uid";
  if (!isRecentSignIn(auth.token.auth_time, nowSeconds)) return "requires-recent-login";
  return null;
}

export interface DeletionReport {
  completions: number;
  usernames: number;
  feedback: number;
}

async function deleteQueryResults(db: Firestore, query: Query): Promise<number> {
  let deleted = 0;
  // Page through in batches of 400 (under the 500-write batch limit) until
  // nothing matches — safe to repeat after a partial failure.
  for (;;) {
    const snap = await query.limit(400).get();
    if (snap.empty) return deleted;
    const batch = db.batch();
    snap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
    deleted += snap.size;
  }
}

/**
 * Deletes every piece of data owned by [uid], in an order chosen so that a
 * failure at any step leaves the account still usable for a retry:
 *   1. Storage: completion photos (`completion_photos/{uid}/…`), any
 *      server-side metadata backups of them, and the avatar.
 *   2. Top-level docs keyed to the user: completions, username claims,
 *      leaderboard mirror, feedback.
 *   3. A "deleted account" marker (`deletedAccounts/{uid}`, Phase 7G), then
 *      the user document and all its subcollections (challenges, memories,
 *      aiUsage) — last, since the app needs it to show the account. The
 *      marker is written first so there is never a moment when the profile
 *      is gone but could be re-created: firestore.rules refuse to create a
 *      profile for a uid that has a marker, so another device still holding
 *      an unexpired ID token can't re-create the profile and, through it,
 *      upload again (storage.rules require the profile). It holds only
 *      timestamps; `expiresAt` is for an optional Firestore TTL policy.
 *   4. Storage again (Phase 7D): another device's ID token stays valid for
 *      up to an hour after its refresh token is revoked, so it could upload
 *      a photo while steps 2–3 run. The second sweep removes it; orphan
 *      cleanup never would (it skips users without a profile).
 * Throws on any failure; never reports partial success.
 */
export async function deleteUserData(deps: DeletionDeps, uid: string): Promise<DeletionReport> {
  if (!isSafeUid(uid)) throw new Error("Refusing to delete data for an invalid uid");
  const {db, bucket} = deps;

  // First (Phase 7H): from now on firestore.rules refuse every client
  // create for this uid, so a device still holding its ID token can't add
  // a completion, feedback or username claim behind the deletions below.
  const now = Date.now();
  await db.collection(DELETED_ACCOUNTS).doc(uid).set({
    markedAt: new Date(now),
    expiresAt: new Date(now + DELETED_ACCOUNT_MARKER_TTL_MS),
  });

  await deleteUserFiles(bucket, uid);

  const completions = await deleteQueryResults(
    db, db.collection("completions").where("userId", "==", uid));
  const usernames = await deleteQueryResults(
    db, db.collection("usernames").where("uid", "==", uid));
  const feedback = await deleteQueryResults(
    db, db.collection("feedback").where("userId", "==", uid));
  await db.collection("leaderboard_public").doc(uid).delete();

  await db.recursiveDelete(db.collection("users").doc(uid));

  await deleteUserFiles(bucket, uid); // late uploads from another session

  return {completions, usernames, feedback};
}

/** The user's photos, metadata backups and avatar. */
async function deleteUserFiles(bucket: BucketLike, uid: string): Promise<void> {
  // The trailing slash matters: "alice" must not match "alice2/…".
  await bucket.deleteFiles({prefix: `completion_photos/${uid}/`, force: true});
  await bucket.deleteFiles({prefix: metadataBackupPrefix(uid), force: true});
  await bucket.file(`user_avatars/${uid}.png`).delete({ignoreNotFound: true});
}

/**
 * Full deletion (idempotent): revoke other sessions, delete all user data,
 * then the Auth account. A revocation failure stops before any data is
 * touched; "user not found" at either Auth step means it is already done.
 */
export async function performAccountDeletion(deps: DeletionDeps, uid: string): Promise<DeletionReport> {
  if (!isSafeUid(uid)) throw new Error("Refusing to delete an invalid uid");
  try {
    await deps.auth.revokeRefreshTokens(uid);
  } catch (e) {
    if (authErrorCode(e) !== "auth/user-not-found") throw e;
  }
  const report = await deleteUserData(deps, uid);
  try {
    await deps.auth.deleteUser(uid);
  } catch (e) {
    // Already gone (e.g. a retry after the Auth step succeeded but the
    // response was lost) counts as done; anything else is a real failure.
    if (authErrorCode(e) !== "auth/user-not-found") throw e;
  }
  return report;
}
