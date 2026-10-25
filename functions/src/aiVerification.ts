/**
 * AI photo verification (`verifyChallengeCompletion`) — DISABLED and
 * deliberately NOT exported from index.ts (Phase 7E).
 *
 * Why it lives here: firebase-tools resolves EVERY param a codebase
 * declares before it applies `--only` (deploy/functions/prepare.js →
 * build.resolveBackend). While this callable was in index.ts, its
 * `defineSecret("GEMINI_API_KEY")` meant even
 * `firebase deploy --only functions:deleteAccount` would prompt for — and
 * create — that secret in Secret Manager, or fail non-interactively. AI
 * stays off (X-1 / D-06); re-enabling it means re-exporting this module
 * from index.ts in a reviewed change, with its own deploy approval.
 *
 * Original description:
 * TouchGrass server-side challenge verification (Phase 11 — see KNOWN_BUGS.md
 * B1/B2 and the master implementation report for full context).
 *
 * NOT YET DEPLOYED. This file is real, complete code — not a stub — but it
 * has never been built, deployed, or run against live Firebase infrastructure
 * in this environment (no Blaze billing configured, no way to test it here).
 * See functions/README.md for exactly what's required before it can go live,
 * and why the Flutter client still calls Gemini directly today rather than
 * this function.
 *
 * Replaces the client-authoritative flow in lib/services/gemini_service.dart
 * + lib/repositories/user_repository.dart's awardCompletionRewards with a
 * server-authoritative one:
 *   1. Client uploads the photo to Storage (unchanged — same owner-scoped
 *      path/rules as today).
 *   2. Client calls this callable function with {challengeId, storagePath}.
 *   3. This function verifies the caller's Firebase Auth identity (never a
 *      client-supplied uid), loads the challenge from Firestore, checks for
 *      an existing completion (idempotent — never awards twice), downloads
 *      the photo from Storage via the Admin SDK, calls Gemini with a
 *      server-held secret, and — only if Gemini says it matches — computes
 *      XP/streak/level/league/weeklyXp authoritatively and writes the
 *      completion + user update + leaderboard mirror in one transaction.
 *   4. The client only ever receives the *result*; it never gets to declare
 *      verified=true, a confidence score, or an XP amount itself.
 *
 * Pure reward/entitlement/parsing logic lives in ./rewards.ts (no Firebase
 * imports there, so it's unit-testable — see index.test.ts) and is imported
 * below rather than redefined.
 */

import {onCall, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import {getApps, initializeApp} from "firebase-admin/app";
import {FieldValue, Timestamp, getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {GoogleGenerativeAI} from "@google/generative-ai";
import {
  AI_VERIFICATION_ENABLED,
  GEMINI_MODEL,
  buildPrompt,
  calendarDay,
  canUseAiVerification,
  entitlementTierFromString,
  isOwnedStoragePath,
  isQuotaExhausted,
  leagueForXp,
  levelForXp,
  parseGeminiResponse,
  parseVerifyRequestData,
  periodQuotaFor,
  resolveStreakOutcome,
  resolveWeeklyXp,
  VerificationResult,
} from "./rewards";

if (getApps().length === 0) initializeApp();
const db = getFirestore();
const storage = getStorage();

// Set once, externally, via:
//   firebase functions:secrets:set GEMINI_API_KEY
// Never committed to source control, never hardcoded here.
const geminiApiKey = defineSecret("GEMINI_API_KEY");

async function verifyWithGemini(
  imageBytes: Buffer,
  challengeTitle: string,
  challengeDescription: string,
  challengeCategory: string
): Promise<VerificationResult> {
  const genAI = new GoogleGenerativeAI(geminiApiKey.value());
  const model = genAI.getGenerativeModel({model: GEMINI_MODEL});

  const result = await model.generateContent([
    buildPrompt(challengeTitle, challengeDescription, challengeCategory),
    {
      inlineData: {
        mimeType: "image/jpeg",
        data: imageBytes.toString("base64"),
      },
    },
  ]);

  const text = result.response.text();
  if (!text) {
    throw new HttpsError("internal", "Empty response from Gemini");
  }
  return parseGeminiResponse(text);
}

// ── Main callable ────────────────────────────────────────────────────────────

interface VerifyRequestData {
  challengeId: string;
  storagePath: string;
}

interface VerifyResponseData {
  matches: boolean;
  confidence: number;
  reason: string;
  xpAwarded: number;
  newXp: number;
  newLevel: number;
  newStreak: number;
  newLeague: string;
  alreadyCompletedToday: boolean;
}

export const verifyChallengeCompletion = onCall<VerifyRequestData, Promise<VerifyResponseData>>(
  {secrets: [geminiApiKey], region: "us-central1", timeoutSeconds: 60},
  async (request) => {
    // 0. AI verification is switched off (see AI_VERIFICATION_ENABLED):
    // refuse before touching any data or the Gemini secret.
    if (!AI_VERIFICATION_ENABLED) {
      throw new HttpsError("failed-precondition", "AI photo verification is turned off.");
    }
    // 1. Authenticate — never trust a client-supplied uid, only the token
    // Firebase Auth itself verified for this request.
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in to verify a completion.");
    }
    const uid = request.auth.uid;

    const parsed = parseVerifyRequestData(request.data);
    if (!parsed) {
      throw new HttpsError(
        "invalid-argument",
        "challengeId and storagePath are both required strings."
      );
    }
    const {challengeId, storagePath} = parsed;
    if (!isOwnedStoragePath(uid, storagePath)) {
      throw new HttpsError(
        "permission-denied",
        "storagePath must be under the caller's own completion_photos/ prefix."
      );
    }

    // 2. Validate the challenge exists and belongs to this user.
    const challengeRef = db
      .collection("users")
      .doc(uid)
      .collection("challenges")
      .doc(challengeId);
    const challengeSnap = await challengeRef.get();
    if (!challengeSnap.exists) {
      throw new HttpsError("not-found", "No such challenge for this user.");
    }
    const challenge = challengeSnap.data()!;

    // 3. Idempotency — the completion doc ID is deterministic
    // (`${uid}_${challengeId}`), matching CompletionRepository's own scheme,
    // so a retried/duplicated call can never award twice.
    const completionId = `${uid}_${challengeId}`;
    const completionRef = db.collection("completions").doc(completionId);
    const existingCompletion = await completionRef.get();
    if (existingCompletion.exists) {
      const existing = existingCompletion.data()!;
      logger.info(`Completion ${completionId} already exists — returning cached result, not re-awarding.`);
      return {
        matches: true,
        confidence: existing.verificationResult?.confidence ?? 1,
        reason: "Already verified.",
        xpAwarded: 0,
        newXp: existing.xpAwarded ?? 0,
        newLevel: levelForXp(existing.xpAwarded ?? 0),
        newStreak: 0,
        newLeague: "",
        alreadyCompletedToday: true,
      };
    }

    // 4. Entitlement + quota — server-side, before spending a Gemini call.
    // entitlementTier lives on the user doc but is never client-writable
    // (see lib/models/entitlement.dart); periodKey is the calendar month
    // ("2026-08") so quota resets naturally each month with no cron job.
    const userForEntitlement = (await db.collection("users").doc(uid).get()).data();
    const tier = entitlementTierFromString(userForEntitlement?.entitlementTier);
    if (!canUseAiVerification(tier)) {
      throw new HttpsError(
        "permission-denied",
        "AI verification isn't available on your current plan."
      );
    }
    const periodKey = new Date().toISOString().slice(0, 7); // "YYYY-MM"
    const usageRef = db
      .collection("users")
      .doc(uid)
      .collection("aiUsage")
      .doc(periodKey);
    const quota = periodQuotaFor(tier);
    const usageSnap = await usageRef.get();
    const used = usageSnap.data()?.verificationCount ?? 0;
    if (isQuotaExhausted(quota, used)) {
      throw new HttpsError(
        "resource-exhausted",
        `You've used all ${quota} AI verifications for this period.`
      );
    }

    // 5. Retrieve the image via the Admin SDK (server-controlled — the
    // client never hands over raw bytes it could substitute after the
    // fact).
    let imageBytes: Buffer;
    try {
      const [bytes] = await storage.bucket().file(storagePath).download();
      imageBytes = bytes;
    } catch (e) {
      logger.error("Failed to download completion photo from Storage", e);
      throw new HttpsError("not-found", "Could not retrieve the uploaded photo.");
    }

    // 6. Call Gemini with the server-side secret — never exposed to the
    // client in any build.
    let verification: VerificationResult;
    try {
      verification = await verifyWithGemini(
        imageBytes,
        String(challenge.title ?? ""),
        String(challenge.description ?? ""),
        String(challenge.challengeCategory ?? "")
      );
    } catch (e) {
      await usageRef.set(
        {
          verificationCount: FieldValue.increment(1),
          failedRequests: FieldValue.increment(1),
          lastUsageAt: FieldValue.serverTimestamp(),
        },
        {merge: true}
      );
      throw e;
    }

    if (!verification.matches) {
      // Not a completion — nothing is written, no reward is granted. Still
      // counts against quota (it was a real Gemini call), tracked as
      // "rejected" rather than "failed" (failed = the request itself broke;
      // rejected = it ran fine and genuinely didn't match).
      await usageRef.set(
        {
          verificationCount: FieldValue.increment(1),
          rejectedVerifications: FieldValue.increment(1),
          lastUsageAt: FieldValue.serverTimestamp(),
        },
        {merge: true}
      );
      return {
        matches: false,
        confidence: verification.confidence,
        reason: verification.reason,
        xpAwarded: 0,
        newXp: 0,
        newLevel: 0,
        newStreak: 0,
        newLeague: "",
        alreadyCompletedToday: false,
      };
    }

    await usageRef.set(
      {
        verificationCount: FieldValue.increment(1),
        successfulVerifications: FieldValue.increment(1),
        lastUsageAt: FieldValue.serverTimestamp(),
      },
      {merge: true}
    );

    // 7. Compute authoritative rewards and write completion + user update
    // transactionally — either both happen or neither does.
    const userRef = db.collection("users").doc(uid);
    const result = await db.runTransaction(async (tx) => {
      const userSnap = await tx.get(userRef);
      if (!userSnap.exists) {
        throw new HttpsError("not-found", "User document not found.");
      }
      const user = userSnap.data()!;

      const now = new Date();
      const today = calendarDay(now);
      // "Already completed today?" uses lastCompletionDate only — never
      // lastActiveDate, which every sign-in refreshes (audit D-01). Legacy
      // accounts without the field fall back to their latest completion.
      let lastCompletionRaw: Date = user.lastCompletionDate?.toDate?.() ?? new Date(0);
      if (!user.lastCompletionDate) {
        const latest = await tx.get(
          db.collection("completions").where("userId", "==", uid)
            .orderBy("completedAt", "desc").limit(1)
        );
        lastCompletionRaw = latest.docs[0]?.get("completedAt")?.toDate?.() ?? new Date(0);
      }
      const lastActive = calendarDay(lastCompletionRaw);
      const freezesOwned = user.settings?.streakFreezesOwned ?? 0;

      const streakOutcome = resolveStreakOutcome(
        today,
        lastActive,
        user.streak ?? 0,
        freezesOwned
      );

      const isNewCompletionToday = lastActive.getTime() !== today.getTime();
      const xpReward = Number(challenge.xpReward ?? 0);
      const xpAwarded = isNewCompletionToday ? xpReward : 0;
      const newXp = (user.xp ?? 0) + xpAwarded;
      const newLevel = levelForXp(newXp);
      const newLeague = leagueForXp(newXp);
      const newStreak = streakOutcome.newStreak;
      const newLongestStreak = Math.max(user.longestStreak ?? 0, newStreak);
      const newTotalCompletions =
        (user.totalCompletions ?? 0) + (isNewCompletionToday ? 1 : 0);
      const newFreezesOwned = streakOutcome.rainyDayConsumed ?
        freezesOwned - 1 :
        freezesOwned;

      // Weekly XP — mirrors the reset-vs-accumulate branch in
      // awardCompletionRewards (lib/repositories/user_repository.dart) —
      // only recomputed/written when this completion actually awards XP.
      const currentWeeklyXpResetDate =
        user.weeklyXpResetDate?.toDate?.() ?? new Date(0);
      const weeklyOutcome = resolveWeeklyXp(
        now,
        user.weeklyXp ?? 0,
        currentWeeklyXpResetDate,
        xpAwarded
      );
      const newWeeklyXp = isNewCompletionToday ?
        weeklyOutcome.weeklyXp :
        user.weeklyXp ?? 0;

      tx.set(completionRef, {
        userId: uid,
        challengeId,
        photoUrl: storagePath,
        verificationResult: {
          matches: true,
          confidence: verification.confidence,
          reason: verification.reason,
        },
        completedAt: FieldValue.serverTimestamp(),
        xpAwarded,
        source: "cloud_function",
      });

      // Mirrors the Dart client's `if (needsWeeklyReset && isNewCompletionToday)`
      // guard — only bump the reset boundary on the completion that actually
      // triggers it, not on every write.
      const weeklyResetUpdate = isNewCompletionToday && weeklyOutcome.resetApplied ?
        {
          weeklyXpResetDate: Timestamp.fromDate(
            weeklyOutcome.weeklyXpResetDate
          ),
        } :
        {};

      tx.update(userRef, {
        xp: newXp,
        weeklyXp: newWeeklyXp,
        level: newLevel,
        currentLeague: newLeague,
        streak: newStreak,
        longestStreak: newLongestStreak,
        totalCompletions: newTotalCompletions,
        lastActiveDate: FieldValue.serverTimestamp(),
        lastCompletionDate: FieldValue.serverTimestamp(),
        lastCompletionId: completionId,
        "settings.streakFreezesOwned": newFreezesOwned,
        ...weeklyResetUpdate,
      });

      // Keep the public leaderboard mirror in lock-step with the write
      // above — see _syncPublicMirror in lib/repositories/user_repository.dart,
      // which this must stay consistent with. Mirrors only the fields that
      // collection actually needs (see firestore.rules'
      // leaderboard_public/{userId} allow-list).
      const mirrorRef = db.collection("leaderboard_public").doc(uid);
      tx.set(
        mirrorRef,
        {
          displayName: user.displayName ?? "",
          username: user.username ?? "",
          photoUrl: user.photoUrl ?? "",
          xp: newXp,
          weeklyXp: newWeeklyXp,
          streak: newStreak,
          currentLeague: newLeague,
        },
        {merge: true}
      );

      return {newXp, newLevel, newStreak, newLeague, xpAwarded};
    });

    logger.info(`Completion ${completionId} verified and awarded for uid ${uid}.`);

    return {
      matches: true,
      confidence: verification.confidence,
      reason: verification.reason,
      xpAwarded: result.xpAwarded,
      newXp: result.newXp,
      newLevel: result.newLevel,
      newStreak: result.newStreak,
      newLeague: result.newLeague,
      alreadyCompletedToday: false,
    };
  }
);
