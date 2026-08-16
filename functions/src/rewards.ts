/**
 * Pure reward/entitlement/verification-parsing logic for TouchGrass's Cloud
 * Function — deliberately free of any `firebase-admin`/`firebase-functions`
 * import (except the lightweight `HttpsError` type used to fail
 * `parseGeminiResponse` the same way the callable does) so this module can
 * be unit-tested with plain `node:test`, without triggering
 * `admin.initializeApp()` or requiring emulator/credential setup.
 *
 * Every function here mirrors a Dart equivalent by hand — see each
 * function's doc comment for the exact source. Keep them in sync; there is
 * no shared source of truth between this Node project and the Flutter app.
 */

import {HttpsError} from "firebase-functions/v2/https";

// ── Constants mirrored from the Flutter app ─────────────────────────────────
// lib/core/constants/app_constants.dart and lib/models/league_definition.dart.

export const XP_PER_LEVEL = 100;
export const AI_CONFIDENCE_THRESHOLD = 0.6;
export const GEMINI_MODEL = "gemini-2.5-flash";

const LEAGUE_THRESHOLDS: Array<{ id: string; minXp: number }> = [
  {id: "aurora", minXp: 20000},
  {id: "sky_trail", minXp: 10000},
  {id: "summit", minXp: 6000},
  {id: "mountain", minXp: 3000},
  {id: "forest", minXp: 1500},
  {id: "wildflower", minXp: 700},
  {id: "sprout", minXp: 300},
  {id: "seedling", minXp: 0},
];

export function levelForXp(xp: number): number {
  return Math.floor(xp / XP_PER_LEVEL) + 1;
}

export function leagueForXp(xp: number): string {
  const found = LEAGUE_THRESHOLDS.find((l) => xp >= l.minXp);
  return found ? found.id : "seedling";
}

// ── Weekly XP reset — ported 1:1 from AppConstants.nextMondayMidnightUtc /
// the weekly-reset branch of awardCompletionRewards in
// lib/core/constants/app_constants.dart and
// lib/repositories/user_repository.dart.

/** Next Monday midnight UTC, relative to `now`. */
export function nextMondayMidnightUtc(now: Date): Date {
  const weekday = now.getUTCDay() === 0 ? 7 : now.getUTCDay(); // Mon=1…Sun=7
  const daysUntilMonday = (1 - weekday + 7) % 7;
  const days = daysUntilMonday === 0 ? 7 : daysUntilMonday;
  return new Date(Date.UTC(
    now.getUTCFullYear(),
    now.getUTCMonth(),
    now.getUTCDate() + days
  ));
}

export interface WeeklyXpOutcome {
  weeklyXp: number;
  weeklyXpResetDate: Date;
  resetApplied: boolean;
}

/** Mirrors the weekly-reset branch of awardCompletionRewards in
 * lib/repositories/user_repository.dart exactly — reset if we've passed
 * this week's reset boundary, otherwise accumulate. */
export function resolveWeeklyXp(
  now: Date,
  currentWeeklyXp: number,
  currentWeeklyXpResetDate: Date,
  xpAwarded: number
): WeeklyXpOutcome {
  const needsReset = now.getTime() > currentWeeklyXpResetDate.getTime();
  return {
    weeklyXp: needsReset ? xpAwarded : currentWeeklyXp + xpAwarded,
    weeklyXpResetDate: needsReset ?
      nextMondayMidnightUtc(now) :
      currentWeeklyXpResetDate,
    resetApplied: needsReset,
  };
}

// ── Entitlement — mirrors lib/models/entitlement.dart exactly.

export type EntitlementTier = "free" | "premium" | "admin_test";

export function entitlementTierFromString(value: unknown): EntitlementTier {
  return value === "premium" || value === "admin_test" ? value : "free";
}

export function canUseAiVerification(tier: EntitlementTier): boolean {
  return tier !== "free";
}

/** -1 means unlimited (admin_test only — never client-grantable). */
export function periodQuotaFor(tier: EntitlementTier): number {
  switch (tier) {
    case "premium":
      return 30;
    case "admin_test":
      return -1;
    case "free":
    default:
      return 0;
  }
}

/** `quota` of -1 means unlimited (never exhausted, regardless of `used`).
 * `used` is read from `users/{uid}/aiUsage/{periodKey}`, a subcollection
 * with `allow write: if false` in firestore.rules — a client can inflate
 * its own quota only by inflating [EntitlementTier] itself, which is
 * separately blocked (not in `isValidUserWrite()`'s allow-list). */
export function isQuotaExhausted(quota: number, used: number): boolean {
  return quota >= 0 && used >= quota;
}

// ── Streak transition — ported 1:1 from resolveStreakOutcome in
// lib/repositories/user_repository.dart. Keep these in sync; see that
// function's doc comment for why calendar-field arithmetic is used instead
// of Duration subtraction (DST safety).

export interface StreakOutcome {
  newStreak: number;
  rainyDayConsumed: boolean;
}

export function calendarDay(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

export function resolveStreakOutcome(
  today: Date,
  lastActiveDay: Date,
  currentStreak: number,
  freezesOwned: number
): StreakOutcome {
  const yesterday = new Date(
    today.getFullYear(),
    today.getMonth(),
    today.getDate() - 1
  );
  const twoDaysAgo = new Date(
    today.getFullYear(),
    today.getMonth(),
    today.getDate() - 2
  );

  if (lastActiveDay.getTime() === today.getTime()) {
    return {newStreak: currentStreak, rainyDayConsumed: false};
  }
  if (lastActiveDay.getTime() === yesterday.getTime()) {
    return {newStreak: currentStreak + 1, rainyDayConsumed: false};
  }
  if (lastActiveDay.getTime() === twoDaysAgo.getTime() && freezesOwned > 0) {
    return {newStreak: currentStreak, rainyDayConsumed: true};
  }
  return {newStreak: 1, rainyDayConsumed: false};
}

// ── Request validation ───────────────────────────────────────────────────────
// Extracted from the callable handler in index.ts so the actual security
// check (not just the shape check) has direct unit test coverage, not just
// implicit coverage via an end-to-end call this environment can't make.

/** The photo must live under this exact user's own Storage prefix — a
 * malicious client could otherwise point this function at someone else's
 * uploaded photo (or an arbitrary object) by ID guessing. The trailing
 * slash after [uid] is deliberate and load-bearing: without it, a uid that
 * is a string-prefix of another uid (e.g. "abc" vs. "abc123") would
 * incorrectly match that other user's path. */
export function isOwnedStoragePath(uid: string, storagePath: string): boolean {
  return storagePath.startsWith(`completion_photos/${uid}/`);
}

export interface VerifyRequestShape {
  challengeId: string;
  storagePath: string;
}

/** Validates the raw callable request payload's shape — returns the
 * narrowed, non-empty-string fields, or `null` if either is missing/not a
 * string. Ownership ([isOwnedStoragePath]) is a separate, deliberately
 * distinct check — this only validates shape, never trust. */
export function parseVerifyRequestData(data: unknown): VerifyRequestShape | null {
  if (typeof data !== "object" || data === null) return null;
  const {challengeId, storagePath} = data as Record<string, unknown>;
  if (!challengeId || typeof challengeId !== "string") return null;
  if (!storagePath || typeof storagePath !== "string") return null;
  return {challengeId, storagePath};
}

// ── Gemini verification ─────────────────────────────────────────────────────

export interface VerificationResult {
  matches: boolean;
  confidence: number;
  reason: string;
}

/** Mirrors GeminiService's prompt in lib/services/gemini_service.dart exactly
 * — the two must agree on the response contract even though only one of them
 * ends up live in production. */
export function buildPrompt(
  challengeTitle: string,
  challengeDescription: string,
  challengeCategory: string
): string {
  return `You are verifying whether a photo matches an outdoor challenge for a mobile app.
Be encouraging and lenient — if the user made a genuine attempt, accept it.

Respond ONLY with a valid JSON object (no markdown, no explanation):
{"matches": true, "confidence": 0.85, "reason": "Brief reason here"}

Rules:
- confidence is 0.0-1.0
- matches is true when confidence >= 0.6
- reason is one short sentence

Challenge: "${challengeTitle}". Description: ${challengeDescription}. Category: ${challengeCategory}.`;
}

/** Mirrors GeminiService.parseVerificationResult — recomputes `matches` from
 * the confidence threshold rather than trusting Gemini's own `matches`
 * field, same as the client-side parser does. */
export function parseGeminiResponse(text: string): VerificationResult {
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start === -1 || end === -1 || end <= start) {
    throw new HttpsError("internal", "Gemini response contained no JSON object");
  }
  const parsed = JSON.parse(text.substring(start, end + 1));
  const confidence = Number(parsed.confidence);
  if (Number.isNaN(confidence)) {
    throw new HttpsError("internal", "Gemini response was missing a numeric confidence");
  }
  return {
    matches: confidence >= AI_CONFIDENCE_THRESHOLD,
    confidence,
    reason: typeof parsed.reason === "string" ? parsed.reason : "",
  };
}
