/**
 * TouchGrass Cloud Functions — the DEPLOY ENTRY POINT.
 *
 * Exports only `deleteAccount` (audit D-04). AI photo verification
 * (`verifyChallengeCompletion`, ./aiVerification.ts) is disabled and is
 * deliberately NOT exported: firebase-tools resolves every param declared
 * by the loaded code before applying `--only`, so its GEMINI_API_KEY
 * secret would otherwise be demanded by any functions deploy (Phase 7E).
 * A test (index.test.ts) pins this: the entry point must declare no
 * secret params and export exactly `deleteAccount`.
 */

import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import {initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {getAuth} from "firebase-admin/auth";
import {checkDeletionRequest, performAccountDeletion} from "./accountDeletion";

initializeApp();
const db = getFirestore();
const storage = getStorage();

// ── Account deletion (audit D-04) ────────────────────────────────────────────

/**
 * Deletes the CALLER's account: every user-owned document and file, then the
 * Firebase Auth user. The uid comes only from the verified ID token. The
 * client must re-authenticate first (recent `auth_time`). Idempotent — a
 * retry after any failure resumes where it stopped. Responds with
 * `{deleted: true}` only after every step, including Auth deletion,
 * succeeded; any failure is reported as an error, never as success.
 *
 * NOT DEPLOYED: requires the Blaze plan (see REMEDIATION_CHECKLIST.md D-04).
 */
export const deleteAccount = onCall(
  {region: "us-central1", timeoutSeconds: 300},
  async (request) => {
    const refusal = checkDeletionRequest(request.auth, Date.now() / 1000);
    if (refusal === "unauthenticated") {
      throw new HttpsError("unauthenticated", "Sign in to delete your account.");
    }
    if (refusal === "requires-recent-login") {
      throw new HttpsError(
        "failed-precondition",
        "For your security, please sign in again, then delete your account."
      );
    }
    if (refusal !== null) {
      throw new HttpsError("permission-denied", "This account can't be deleted here.");
    }
    const uid = request.auth!.uid;
    try {
      const report = await performAccountDeletion(
        {db, bucket: storage.bucket(), auth: getAuth()},
        uid
      );
      logger.info("Account deleted", {uid, ...report});
      return {deleted: true};
    } catch (e) {
      logger.error("Account deletion incomplete — safe to retry", {uid, error: String(e)});
      throw new HttpsError(
        "internal",
        "We couldn't finish deleting your account. Please try again — " +
          "anything already removed stays removed."
      );
    }
  }
);
