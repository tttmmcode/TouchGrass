// Phase 7A: what happens to the web app that is LIVE today (built from the
// committed code, HEAD 67c5a38, whose firestore.rules are byte-identical to
// the live ones) once the LOCAL rules are deployed. Its write shapes are
// taken from that commit (lib/services/storage_service.dart,
// completion_repository.dart, user_repository.dart).
//
// Result: profile, username and leaderboard writes keep working, but the
// completion flow does NOT — so the local rules must ship together with a
// new web build (PHASE_7A_DEPLOYMENT_MANIFEST.md, coordinated window).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, it, before, after, beforeEach } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, setDoc, updateDoc, serverTimestamp } from 'firebase/firestore';
import { ref, uploadBytes } from 'firebase/storage';
import { PROJECT_ID, authed, storedUser, completionDoc, dateKey, levelForXp, leagueForXp } from './helpers.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const legacyPhoto = (uid, ts = 1760900000000) =>
  `https://firebasestorage.googleapis.com/v0/b/touchgrass-today.firebasestorage.app/o/completion_photos%2F${uid}%2F${ts}.jpg?alt=media&token=abc`;

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules: fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8') },
    storage: { rules: fs.readFileSync(path.join(root, 'storage.rules'), 'utf8') },
  });
});
after(async () => { await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.clearStorage();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users/alice'), storedUser('alice'));
    await setDoc(doc(db, 'usernames/alice_name'), { uid: 'alice' });
  });
});

const db = (uid) => authed(env, uid).firestore();

describe('live web app (HEAD 67c5a38) under the LOCAL rules — still works', () => {
  it('profile edit (display name + lastActiveDate)', async () => {
    await assertSucceeds(updateDoc(doc(db('alice'), 'users/alice'), { displayName: 'Alice B', lastActiveDate: serverTimestamp() }));
  });
  it('username claim', async () => {
    await assertSucceeds(setDoc(doc(db('alice'), 'usernames/alice_new'), { uid: 'alice' }));
  });
  it('leaderboard mirror equal to the profile', async () => {
    const u = storedUser('alice');
    await assertSucceeds(setDoc(doc(db('alice'), 'leaderboard_public/alice'), {
      displayName: u.displayName, username: u.username, photoUrl: null, xp: u.xp,
      weeklyXp: u.weeklyXp, streak: u.streak, currentLeague: u.currentLeague,
    }));
  });
  it('avatar upload to user_avatars/{uid}.png', async () => {
    await assertSucceeds(uploadBytes(ref(authed(env, 'alice').storage(), 'user_avatars/alice.png'),
      new Uint8Array(10), { contentType: 'image/png' }));
  });
});

describe('live web app (HEAD 67c5a38) under the LOCAL rules — BREAKS (needs the new web build)', () => {
  it('completion photo upload named {timestamp}.jpg is DENIED', async () => {
    await assertFails(uploadBytes(ref(authed(env, 'alice').storage(), 'completion_photos/alice/1760900000000.jpg'),
      new Uint8Array(10), { contentType: 'image/jpeg' }));
  });
  it('completion document pointing at a {timestamp}.jpg photo is DENIED', async () => {
    const id = dateKey(0);
    await assertFails(setDoc(doc(db('alice'), `completions/alice_${id}`),
      completionDoc('alice', id, serverTimestamp, { photoUrl: legacyPhoto('alice') })));
  });
  it('reward update written separately (no lastCompletionId / lastCompletionDate) is DENIED', async () => {
    const xp = 150;
    await assertFails(updateDoc(doc(db('alice'), 'users/alice'), {
      xp, weeklyXp: xp, level: levelForXp(xp), currentLeague: leagueForXp(xp),
      streak: 2, longestStreak: 2, totalCompletions: 2, lastActiveDate: serverTimestamp(),
    }));
  });
});
