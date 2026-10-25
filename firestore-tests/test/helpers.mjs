// Shared fixtures for the emulator-only rules tests. Everything here runs
// against a `demo-` project on the local emulator — it cannot reach
// production, and no real user data is used.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { Timestamp } from 'firebase/firestore';

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, '..', '..');

export const PROJECT_ID = 'demo-touchgrass-rules';
export const BUCKET = `${PROJECT_ID}.appspot.com`;

/** Firestore-only environment (keeps Firestore suites independent of
 * storage.rules compiling, and vice versa). */
export function firestoreEnv() {
  return initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(path.join(repoRoot, 'firestore.rules'), 'utf8'),
    },
  });
}

/** Storage environment. Firestore runs too (with the real rules): the
 * final storage.rules read users/{uid} to check the uploader's profile
 * exists (Phase 7F); seed it with [seedProfiles]. */
export function storageEnv(rulesFile = 'storage.rules') {
  return initializeTestEnvironment({
    projectId: PROJECT_ID,
    storage: {
      rules: fs.readFileSync(path.join(repoRoot, rulesFile), 'utf8'),
    },
    firestore: {
      rules: fs.readFileSync(path.join(repoRoot, 'firestore.rules'), 'utf8'),
    },
  });
}

/** Creates a minimal users/{uid} profile for each uid (rules bypassed) —
 * every real signed-in user has one, created at sign-in. */
export async function seedProfiles(env, uids) {
  const { doc, setDoc } = await import('firebase/firestore');
  await env.withSecurityRulesDisabled(async (ctx) => {
    for (const uid of uids) await setDoc(doc(ctx.firestore(), 'users', uid), { uid });
  });
}

/** Authenticated context whose ID token carries an email, like a real
 * email/Google sign-in. */
export const authed = (env, uid) =>
  env.authenticatedContext(uid, { email: `${uid}@example.test` });

/** UTC calendar date key `yyyy-MM-dd`, offset by [days]. The rules accept
 * challenge/completion date keys within ±1 day of server time to cover
 * every real-world UTC offset (−12h … +14h). */
export function dateKey(days = 0) {
  const d = new Date(Date.now() + days * 86400000);
  return d.toISOString().slice(0, 10);
}

export const levelForXp = (xp) => Math.floor(xp / 100) + 1;
export function leagueForXp(xp) {
  return xp >= 20000 ? 'aurora' : xp >= 10000 ? 'sky_trail' : xp >= 6000 ? 'summit'
    : xp >= 3000 ? 'mountain' : xp >= 1500 ? 'forest' : xp >= 700 ? 'wildflower'
    : xp >= 300 ? 'sprout' : 'seedling';
}

export const defaultSettings = () => ({
  notificationsEnabled: true,
  streakFreezesOwned: 3,
  locationEnabled: true,
  profilePublic: true,
  companionType: 'sprout',
  preferredCategories: [],
});

/** A stored user document as the app writes it (seeded with rules off). */
export function storedUser(uid, overrides = {}) {
  const now = Timestamp.now();
  const xp = overrides.xp ?? 100;
  return {
    uid,
    email: `${uid}@example.test`,
    username: `${uid}_name`,
    displayName: uid,
    photoUrl: null,
    xp,
    weeklyXp: xp,
    weeklyXpResetDate: Timestamp.fromMillis(Date.now() + 3 * 86400000),
    level: levelForXp(xp),
    streak: 1,
    longestStreak: 1,
    totalCompletions: 1,
    totalPhotosUploaded: 0,
    rainyDayCount: 0,
    currentLeague: leagueForXp(xp),
    createdAt: now,
    lastActiveDate: now,
    achievements: ['first_touch'],
    settings: defaultSettings(),
    frozenDates: [],
    ...overrides,
  };
}

/** A profile photo URL exactly as Storage's getDownloadURL returns it for
 * the app's avatar path (the only Storage photo the rules accept). */
export const avatarUrl = (uid, bucket = 'touchgrass-today.firebasestorage.app') =>
  `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/user_avatars%2F${uid}.png?alt=media&token=1b2c3d4e`;

export const photoUrl = (uid, file = '1700000000000.jpg') =>
  `https://firebasestorage.googleapis.com/v0/b/touchgrass-today.firebasestorage.app/o/completion_photos%2F${uid}%2F${file}?alt=media&token=abc`;

/** A completion exactly as CompletionModel.toFirestore() writes it
 * (honor-system verification — client-side AI is disabled). */
export function completionDoc(uid, challengeId, serverTimestamp, overrides = {}) {
  return {
    userId: uid,
    challengeId,
    challengeTitle: 'Find a leaf',
    challengeEmoji: '🍃',
    challengeCategory: 'nature',
    // The app's fixed per-completion path: completion_photos/{uid}/{date}.jpg.
    photoUrl: photoUrl(uid, `${challengeId}.jpg`),
    verificationResult: {
      reason: 'Honor-system approved — AI verification is a premium feature.',
      aiLocked: true,
    },
    completedAt: serverTimestamp(),
    xpAwarded: 50,
    overrideUsed: false,
    ...overrides,
  };
}

/** A per-user challenge document as ChallengeModel.toFirestore() writes it. */
export function challengeDoc(uid, id, overrides = {}) {
  const now = Timestamp.now();
  return {
    challengeId: id,
    userId: uid,
    dayNumber: 3,
    title: 'Find a leaf',
    description: 'Go outside and find a leaf.',
    objective: 'Find a leaf.',
    successCriteria: 'A leaf',
    difficulty: 'medium',
    estimatedMinutes: 15,
    xpReward: 50,
    challengeCategory: 'nature',
    emoji: '🍃',
    generatedAt: now,
    expiresAt: Timestamp.fromMillis(Date.now() + 86400000),
    challengeVersion: 2,
    isCompleted: false,
    rerollCount: 0,
    aiGenerated: false,
    ...overrides,
  };
}

/** Settles a list of promises and counts how many succeeded. */
export async function countFulfilled(promises) {
  const results = await Promise.allSettled(promises);
  return results.filter((r) => r.status === 'fulfilled').length;
}
