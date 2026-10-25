/**
 * Unit tests for the pure logic in rewards.ts. Runs via Node's built-in
 * test runner against the compiled output (see package.json's "test"
 * script) — no Firebase emulator, credentials, or network access required.
 */

import {test, describe} from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {join} from "node:path";
import {
  AI_VERIFICATION_ENABLED,
  levelForXp,
  leagueForXp,
  nextMondayMidnightUtc,
  resolveWeeklyXp,
  entitlementTierFromString,
  canUseAiVerification,
  periodQuotaFor,
  calendarDay,
  resolveStreakOutcome,
  parseGeminiResponse,
  isOwnedStoragePath,
  parseVerifyRequestData,
  isQuotaExhausted,
} from "./rewards";

describe("levelForXp", () => {
  test("level 1 at 0 xp", () => assert.equal(levelForXp(0), 1));
  test("level 1 just under the level-2 boundary", () => assert.equal(levelForXp(99), 1));
  test("level 2 exactly at the boundary", () => assert.equal(levelForXp(100), 2));
  test("level 11 at 1000 xp", () => assert.equal(levelForXp(1000), 11));
});

describe("leagueForXp", () => {
  test("seedling below the lowest threshold", () => assert.equal(leagueForXp(0), "seedling"));
  test("sprout exactly at its threshold", () => assert.equal(leagueForXp(300), "sprout"));
  test("wildflower exactly at its threshold", () => assert.equal(leagueForXp(700), "wildflower"));
  test("sprout just under the wildflower threshold", () => assert.equal(leagueForXp(699), "sprout"));
  test("aurora at and above the top threshold", () => {
    assert.equal(leagueForXp(20000), "aurora");
    assert.equal(leagueForXp(999999), "aurora");
  });
});

describe("resolveStreakOutcome", () => {
  const today = new Date(2026, 0, 15);
  const yesterday = new Date(2026, 0, 14);
  const twoDaysAgo = new Date(2026, 0, 13);
  const longAgo = new Date(2025, 11, 1);

  test("same-day completion leaves streak unchanged", () => {
    const r = resolveStreakOutcome(today, today, 5, 0);
    assert.deepEqual(r, {newStreak: 5, rainyDayConsumed: false});
  });

  test("consecutive-day completion increments streak", () => {
    const r = resolveStreakOutcome(today, yesterday, 5, 0);
    assert.deepEqual(r, {newStreak: 6, rainyDayConsumed: false});
  });

  test("one missed day with a freeze available consumes it, streak preserved", () => {
    const r = resolveStreakOutcome(today, twoDaysAgo, 5, 1);
    assert.deepEqual(r, {newStreak: 5, rainyDayConsumed: true});
  });

  test("one missed day with no freeze resets streak to 1", () => {
    const r = resolveStreakOutcome(today, twoDaysAgo, 5, 0);
    assert.deepEqual(r, {newStreak: 1, rainyDayConsumed: false});
  });

  test("long-lapsed streak resets to 1 regardless of freezes", () => {
    const r = resolveStreakOutcome(today, longAgo, 20, 3);
    assert.deepEqual(r, {newStreak: 1, rainyDayConsumed: false});
  });
});

describe("calendarDay", () => {
  test("truncates time-of-day, keeps the calendar date", () => {
    const d = new Date(2026, 2, 4, 23, 59, 59);
    const truncated = calendarDay(d);
    assert.equal(truncated.getFullYear(), 2026);
    assert.equal(truncated.getMonth(), 2);
    assert.equal(truncated.getDate(), 4);
    assert.equal(truncated.getHours(), 0);
  });
});

describe("nextMondayMidnightUtc", () => {
  test("from a Wednesday lands on the following Monday", () => {
    // 2026-08-05 is a Wednesday.
    const wed = new Date(Date.UTC(2026, 7, 5, 10, 0, 0));
    const next = nextMondayMidnightUtc(wed);
    assert.equal(next.getUTCFullYear(), 2026);
    assert.equal(next.getUTCMonth(), 7);
    assert.equal(next.getUTCDate(), 10); // 2026-08-10 is a Monday
    assert.equal(next.getUTCHours(), 0);
  });

  test("from a Monday itself rolls forward a full week, never returns today", () => {
    // 2026-08-10 is a Monday.
    const mon = new Date(Date.UTC(2026, 7, 10, 0, 0, 0));
    const next = nextMondayMidnightUtc(mon);
    assert.equal(next.getUTCDate(), 17);
  });

  test("from a Sunday lands on the very next day", () => {
    // 2026-08-09 is a Sunday.
    const sun = new Date(Date.UTC(2026, 7, 9, 12, 0, 0));
    const next = nextMondayMidnightUtc(sun);
    assert.equal(next.getUTCDate(), 10);
  });
});

describe("resolveWeeklyXp", () => {
  test("before the reset boundary, accumulates onto existing weeklyXp", () => {
    const now = new Date(Date.UTC(2026, 7, 5, 12, 0, 0));
    const resetDate = new Date(Date.UTC(2026, 7, 10, 0, 0, 0));
    const r = resolveWeeklyXp(now, 40, resetDate, 25);
    assert.equal(r.weeklyXp, 65);
    assert.equal(r.resetApplied, false);
    assert.equal(r.weeklyXpResetDate.getTime(), resetDate.getTime());
  });

  test("after the reset boundary, resets to just this award and rolls the boundary forward", () => {
    const now = new Date(Date.UTC(2026, 7, 11, 9, 0, 0));
    const resetDate = new Date(Date.UTC(2026, 7, 10, 0, 0, 0));
    const r = resolveWeeklyXp(now, 40, resetDate, 25);
    assert.equal(r.weeklyXp, 25);
    assert.equal(r.resetApplied, true);
    assert.equal(r.weeklyXpResetDate.getUTCDate(), 17);
  });

  test("a never-before-set reset date (epoch) always triggers a reset", () => {
    const now = new Date(Date.UTC(2026, 7, 5, 12, 0, 0));
    const r = resolveWeeklyXp(now, 0, new Date(0), 25);
    assert.equal(r.weeklyXp, 25);
    assert.equal(r.resetApplied, true);
  });
});

describe("entitlementTierFromString / canUseAiVerification / periodQuotaFor", () => {
  test("recognizes all three valid tier strings", () => {
    assert.equal(entitlementTierFromString("free"), "free");
    assert.equal(entitlementTierFromString("premium"), "premium");
    assert.equal(entitlementTierFromString("admin_test"), "admin_test");
  });

  test("defaults anything unrecognized (including missing/null/garbage) to free", () => {
    assert.equal(entitlementTierFromString(undefined), "free");
    assert.equal(entitlementTierFromString(null), "free");
    assert.equal(entitlementTierFromString("gold"), "free");
    assert.equal(entitlementTierFromString(123), "free");
  });

  test("only free is denied AI verification", () => {
    assert.equal(canUseAiVerification("free"), false);
    assert.equal(canUseAiVerification("premium"), true);
    assert.equal(canUseAiVerification("admin_test"), true);
  });

  test("quota is 0/30/unlimited(-1) for free/premium/admin_test", () => {
    assert.equal(periodQuotaFor("free"), 0);
    assert.equal(periodQuotaFor("premium"), 30);
    assert.equal(periodQuotaFor("admin_test"), -1);
  });
});

describe("isOwnedStoragePath", () => {
  test("accepts a path genuinely under the caller's own prefix", () => {
    assert.equal(
      isOwnedStoragePath("user123", "completion_photos/user123/photo.jpg"),
      true
    );
  });

  test("rejects a path under a different user's prefix", () => {
    assert.equal(
      isOwnedStoragePath("user123", "completion_photos/otherUser/photo.jpg"),
      false
    );
  });

  test("rejects a prefix-collision attack — one uid being a string-prefix of another must not match", () => {
    // Without the trailing slash after uid, "abc" would incorrectly match
    // "completion_photos/abc123/...", letting a user with uid "abc" read
    // uid "abc123"'s photos.
    assert.equal(
      isOwnedStoragePath("abc", "completion_photos/abc123/photo.jpg"),
      false
    );
  });

  test("rejects a path with no completion_photos/ prefix at all", () => {
    assert.equal(isOwnedStoragePath("user123", "other_bucket/user123/photo.jpg"), false);
  });

  test("rejects an empty storage path", () => {
    assert.equal(isOwnedStoragePath("user123", ""), false);
  });

  test("rejects the bare directory with no filename", () => {
    assert.equal(isOwnedStoragePath("user123", "completion_photos/user123"), false);
  });
});

describe("parseVerifyRequestData", () => {
  test("accepts a well-formed request", () => {
    const result = parseVerifyRequestData({
      challengeId: "day-5",
      storagePath: "completion_photos/uid/photo.jpg",
    });
    assert.deepEqual(result, {
      challengeId: "day-5",
      storagePath: "completion_photos/uid/photo.jpg",
    });
  });

  test("rejects null/undefined/non-object payloads", () => {
    assert.equal(parseVerifyRequestData(null), null);
    assert.equal(parseVerifyRequestData(undefined), null);
    assert.equal(parseVerifyRequestData("a string"), null);
    assert.equal(parseVerifyRequestData(42), null);
  });

  test("rejects a missing challengeId", () => {
    assert.equal(
      parseVerifyRequestData({storagePath: "completion_photos/uid/photo.jpg"}),
      null
    );
  });

  test("rejects a missing storagePath", () => {
    assert.equal(parseVerifyRequestData({challengeId: "day-5"}), null);
  });

  test("rejects non-string challengeId/storagePath (a client trying to smuggle an object/array)", () => {
    assert.equal(
      parseVerifyRequestData({challengeId: {$ne: null}, storagePath: "x"}),
      null
    );
    assert.equal(
      parseVerifyRequestData({challengeId: "day-5", storagePath: ["a", "b"]}),
      null
    );
  });

  test("rejects empty-string challengeId/storagePath", () => {
    assert.equal(
      parseVerifyRequestData({challengeId: "", storagePath: "completion_photos/uid/photo.jpg"}),
      null
    );
    assert.equal(
      parseVerifyRequestData({challengeId: "day-5", storagePath: ""}),
      null
    );
  });
});

describe("isQuotaExhausted", () => {
  test("free tier (quota 0) is always exhausted, even with zero prior usage", () => {
    assert.equal(isQuotaExhausted(0, 0), true);
  });

  test("premium tier: not exhausted while strictly under quota", () => {
    assert.equal(isQuotaExhausted(30, 29), false);
  });

  test("premium tier: exhausted exactly at the boundary", () => {
    assert.equal(isQuotaExhausted(30, 30), true);
  });

  test("premium tier: exhausted when somehow over quota (defensive, shouldn't normally happen)", () => {
    assert.equal(isQuotaExhausted(30, 31), true);
  });

  test("unlimited (-1) is never exhausted, no matter how high usage climbs", () => {
    assert.equal(isQuotaExhausted(-1, 0), false);
    assert.equal(isQuotaExhausted(-1, 1_000_000), false);
  });
});

describe("parseGeminiResponse", () => {
  test("parses a well-formed response and recomputes matches from confidence", () => {
    const r = parseGeminiResponse('{"matches": true, "confidence": 0.85, "reason": "Looks like a park"}');
    assert.equal(r.matches, true);
    assert.equal(r.confidence, 0.85);
    assert.equal(r.reason, "Looks like a park");
  });

  test("recomputes matches=false even if Gemini claims true, when confidence is below threshold", () => {
    const r = parseGeminiResponse('{"matches": true, "confidence": 0.4, "reason": "Not convincing"}');
    assert.equal(r.matches, false);
  });

  test("confidence exactly at the 0.6 threshold counts as a match", () => {
    const r = parseGeminiResponse('{"confidence": 0.6, "reason": "Borderline"}');
    assert.equal(r.matches, true);
  });

  test("tolerates markdown/prose wrapped around the JSON object", () => {
    const r = parseGeminiResponse('Sure! Here you go:\n```json\n{"matches": true, "confidence": 0.9, "reason": "Yes"}\n```');
    assert.equal(r.confidence, 0.9);
  });

  test("missing reason falls back to an empty string rather than throwing", () => {
    const r = parseGeminiResponse('{"confidence": 0.7}');
    assert.equal(r.reason, "");
  });

  test("throws when the response contains no JSON object at all", () => {
    assert.throws(() => parseGeminiResponse("I cannot verify this image."));
  });

  test("throws when confidence is missing or non-numeric", () => {
    assert.throws(() => parseGeminiResponse('{"reason": "no confidence field"}'));
    assert.throws(() => parseGeminiResponse('{"confidence": "high", "reason": "bad type"}'));
  });
});

describe("AI verification stays off (owner decision)", () => {
  test("the master switch is off", () => {
    assert.equal(AI_VERIFICATION_ENABLED, false);
  });
  test("verifyChallengeCompletion checks it before auth, data or the Gemini secret", () => {
    // The AI callable lives in aiVerification.ts (not exported for deploy; 7E).
    const src = readFileSync(join(__dirname, "..", "src", "aiVerification.ts"), "utf8");
    const start = src.indexOf("export const verifyChallengeCompletion");
    const guard = src.indexOf("if (!AI_VERIFICATION_ENABLED)", start);
    assert.ok(start > 0 && guard > start, "guard inside the handler");
    // Everything that reads data, Storage or Gemini comes after the guard.
    for (const later of ["request.auth", "challengeRef", ".download()", "verifyWithGemini("]) {
      const at = src.indexOf(later, start);
      assert.ok(at > guard, later);
    }
  });
});
