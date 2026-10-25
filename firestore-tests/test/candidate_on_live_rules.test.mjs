// Phase 7I: what the NEW web client (the candidate) can and can't do against
// the rules that are LIVE today, before any rules deploy:
// - Firestore: HEAD 67c5a38's firestore.rules (fixtures/live-firestore-67c5a38.rules,
//   verified byte-identical to the live ruleset on 2026-10-24);
// - Storage: deploy/interim/storage.interim.rules (the live interim rules).
// Write shapes are the candidate's (lib/, Phase 7H), as the other suites
// model them for the final rules.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, it, before, after, beforeEach } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import {
  doc, setDoc, updateDoc, deleteField, writeBatch, serverTimestamp, Timestamp, GeoPoint,
} from 'firebase/firestore';
import { ref, uploadBytes } from 'firebase/storage';
import {
  PROJECT_ID, authed, storedUser, defaultSettings, completionDoc, challengeDoc, photoUrl, avatarUrl, dateKey,
} from './helpers.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..', '..');
const today = dateKey(0);
const id = (uid = 'alice') => `${uid}_${today}`;
const HONOR = { reason: 'Completed on the honor system with your photo.' };
const jpeg = { contentType: 'image/jpeg' };

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules: fs.readFileSync(path.join(here, 'fixtures', 'live-firestore-67c5a38.rules'), 'utf8') },
    storage: { rules: fs.readFileSync(path.join(root, 'deploy', 'interim', 'storage.interim.rules'), 'utf8') },
  });
});
after(async () => { await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.clearStorage();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const d = ctx.firestore();
    await setDoc(doc(d, 'users/alice'), storedUser('alice'));
    await setDoc(doc(d, 'usernames/alice_name'), { uid: 'alice' });
    await setDoc(doc(d, `users/alice/challenges/${today}`), challengeDoc('alice', today));
  });
});

const db = (uid = 'alice') => authed(env, uid).firestore();
const st = (uid = 'alice') => authed(env, uid).storage();

const newProfile = (uid) => ({
  uid, email: `${uid}@example.test`, username: `${uid}_name`, displayName: 'Explorer', photoUrl: null,
  xp: 0, weeklyXp: 0, weeklyXpResetDate: Timestamp.fromMillis(Date.now() + 5 * 86400000),
  level: 1, streak: 0, longestStreak: 0, totalCompletions: 0, totalPhotosUploaded: 0, rainyDayCount: 0,
  currentLeague: 'seedling', createdAt: serverTimestamp(), lastActiveDate: serverTimestamp(),
  achievements: [], settings: defaultSettings(), frozenDates: [],
});
const memory = (o = {}) => ({
  userId: 'alice', challengeId: today, challengeDay: 3, challengeTitle: 'Find a leaf',
  challengeCategory: 'nature', photoUrl: photoUrl('alice', `${today}.jpg`), xpEarned: 50,
  verificationMethod: 'auto_approved', completionDate: Timestamp.now(), createdAt: serverTimestamp(), ...o,
});
const completion = (o = {}) => completionDoc('alice', today, serverTimestamp, { verificationResult: HONOR, ...o });
const reward = {
  xp: 150, weeklyXp: 150, level: 2, currentLeague: 'seedling', streak: 2, longestStreak: 2,
  totalCompletions: 2, rainyDayCount: 0,
};

/** The candidate's completion commit (UserRepository.commitCompletion). */
function completionBatch(d, { withMemory = true, location = false } = {}) {
  const b = writeBatch(d);
  b.set(doc(d, `completions/${id()}`), completion(location ? { location: new GeoPoint(1, 2) } : {}));
  b.update(doc(d, 'users/alice'), {
    ...reward, lastCompletionId: id(), lastActiveDate: serverTimestamp(), lastCompletionDate: serverTimestamp(),
  });
  if (withMemory) b.set(doc(d, `users/alice/memories/${id()}`), memory());
  return b.commit();
}

const seed = (p, data) => env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), p), data));

describe('candidate web client under the LIVE rules (Phase 7I)', () => {
  describe('works today', () => {
    it('sign-up: username claim, then the new profile', async () => {
      await assertSucceeds(setDoc(doc(db('carol'), 'usernames/carol_name'), { uid: 'carol' }));
      await assertSucceeds(setDoc(doc(db('carol'), 'users/carol'), newProfile('carol')));
    });
    it('returning sign-in: lastActiveDate and the leaderboard mirror', async () => {
      await assertSucceeds(updateDoc(doc(db(), 'users/alice'), { lastActiveDate: serverTimestamp() }));
      const u = storedUser('alice');
      await assertSucceeds(setDoc(doc(db(), 'leaderboard_public/alice'), {
        displayName: u.displayName, username: u.username, photoUrl: u.photoUrl, xp: u.xp,
        weeklyXp: u.weeklyXp, streak: u.streak, currentLeague: u.currentLeague,
      }, { merge: true }));
    });
    it('profile photo upload (user_avatars/{uid}.png)', async () => {
      await assertSucceeds(uploadBytes(ref(st(), 'user_avatars/alice.png'), new Uint8Array(10), { contentType: 'image/png' }));
      await assertSucceeds(updateDoc(doc(db(), 'users/alice'), { photoUrl: avatarUrl('alice') }));
    });
    it('challenge photo upload to the fixed path completion_photos/{uid}/{date}.jpg', async () => {
      await assertSucceeds(uploadBytes(ref(st(), `completion_photos/alice/${today}.jpg`), new Uint8Array(10), jpeg));
    });
  });

  describe('works today', () => {
    it('daily challenge: create and reroll', async () => {
      const { deleteDoc } = await import('firebase/firestore');
      await env.withSecurityRulesDisabled((ctx) => deleteDoc(doc(ctx.firestore(), `users/alice/challenges/${today}`)));
      await assertSucceeds(setDoc(doc(db(), `users/alice/challenges/${today}`), challengeDoc('alice', today)));
      await assertSucceeds(setDoc(doc(db(), `users/alice/challenges/${today}`),
        challengeDoc('alice', today, { title: 'Reroll 1', rerollCount: 1 })));
    });
    it('Journal repair, caption edit, marking the challenge completed', async () => {
      await seed(`completions/${id()}`, completionDoc('alice', today, () => Timestamp.now(), { verificationResult: HONOR }));
      await assertSucceeds(setDoc(doc(db(), `users/alice/memories/${id()}`), memory()));
      await assertSucceeds(updateDoc(doc(db(), `users/alice/memories/${id()}`),
        { caption: 'Nice', captionUpdatedAt: serverTimestamp() }));
      await assertSucceeds(updateDoc(doc(db(), `users/alice/challenges/${today}`),
        { isCompleted: true, completionDate: Timestamp.now() }));
    });
    it('settings, leaderboard opt-out, username change, streak-freeze purchase', async () => {
      await assertSucceeds(updateDoc(doc(db(), 'users/alice'), { 'settings.locationEnabled': false }));
      const d = db();
      const b = writeBatch(d);
      b.set(doc(d, 'usernames/alice_new'), { uid: 'alice' });
      b.delete(doc(d, 'usernames/alice_name'));
      await assertSucceeds(b.commit());
      await assertSucceeds(updateDoc(doc(db(), 'users/alice'), { username: 'alice_new' }));
      await seed('users/alice', storedUser('alice', { xp: 1000, username: 'alice_new' }));
      await assertSucceeds(updateDoc(doc(db(), 'users/alice'), {
        xp: 500, level: 6, currentLeague: 'sprout', 'settings.streakFreezesOwned': 4,
      }));
    });
  });

  // The candidate must NOT be served to real users before the final
  // firestore.rules are deployed: its core flow is refused today.
  describe('BREAKS until the final Firestore rules are deployed', () => {
    it('completing a challenge: the completion batch is DENIED (lastCompletionId / lastCompletionDate)', async () => {
      await assertFails(completionBatch(db()));
      await assertFails(completionBatch(db(), { withMemory: false }));
      await assertFails(completionBatch(db(), { location: true }));
    });
    it('feedback is DENIED (no feedback rule is live)', async () => {
      await assertFails(setDoc(doc(db(), `feedback/alice_${today}_1`), {
        type: 'feedback', message: 'hi', userId: 'alice', createdAt: serverTimestamp(), appVersion: '1.0.0',
      }));
    });
    it('"Remove saved locations" is DENIED for completions and Journal entries', async () => {
      await seed(`completions/${id()}`, completionDoc('alice', today, () => Timestamp.now(),
        { verificationResult: HONOR, location: new GeoPoint(1, 2) }));
      await assertFails(updateDoc(doc(db(), `completions/${id()}`), { location: deleteField() }));
      await seed(`users/alice/memories/${id()}`,
        { ...memory({ latitude: 1, longitude: 2, locationName: 'x' }), createdAt: Timestamp.now() });
      await assertFails(updateDoc(doc(db(), `users/alice/memories/${id()}`),
        { latitude: deleteField(), longitude: deleteField(), locationName: deleteField() }));
    });
  });
});
