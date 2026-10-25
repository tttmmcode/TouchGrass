// D-02 (leaderboard mirror forgery) and D-03 (username takeover / races).
import { describe, it, before, after, beforeEach } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, deleteDoc, writeBatch } from 'firebase/firestore';
import { firestoreEnv, authed, storedUser, countFulfilled } from './helpers.mjs';

let env;
before(async () => { env = await firestoreEnv(); });
after(async () => { await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users/alice'), storedUser('alice', { xp: 1600 }));
    await setDoc(doc(db, 'usernames/alice_name'), { uid: 'alice' });
    await setDoc(doc(db, 'leaderboard_public/bob'), {
      displayName: 'bob', username: 'bob_name', photoUrl: null, xp: 10, weeklyXp: 10, streak: 1, currentLeague: 'seedling',
    });
  });
});

/** Exactly what UserRepository._syncPublicMirror writes for alice. */
const mirrorOf = (overrides = {}) => ({
  displayName: 'alice', username: 'alice_name', photoUrl: null,
  xp: 1600, weeklyXp: 1600, streak: 1, currentLeague: 'forest', ...overrides,
});

describe('leaderboard_public (D-02)', () => {
  const ref = (uid = 'alice', as = 'alice') => doc(authed(env, as).firestore(), `leaderboard_public/${uid}`);
  it('ALLOWS a mirror that matches the owner\'s profile', async () => {
    await assertSucceeds(setDoc(ref(), mirrorOf()));
  });
  it('ALLOWS a partial merge that keeps the mirror consistent', async () => {
    await assertSucceeds(setDoc(ref(), mirrorOf()));
    await assertSucceeds(setDoc(ref(), { xp: 1600 }, { merge: true }));
  });
  for (const [label, o] of [
    ['xp = 99,999,999 (audit V-4)', { xp: 99999999 }],
    ['weeklyXp = 99,999,999', { weeklyXp: 99999999 }],
    ['streak = 9999', { streak: 9999 }],
    ['league = aurora', { currentLeague: 'aurora' }],
    ['someone else\'s display name', { displayName: 'bob' }],
    ['an extra field', { email: 'alice@example.test' }],
  ]) {
    it(`DENIES a mirror with ${label}`, async () => { await assertFails(setDoc(ref(), mirrorOf(o))); });
  }
  it('DENIES writing another user\'s mirror', async () => {
    await assertFails(setDoc(ref('bob', 'mallory'), { displayName: 'x', username: 'x', photoUrl: null, xp: 0, weeklyXp: 0, streak: 0, currentLeague: 'seedling' }));
  });
  it('DENIES a mirror for a user with no profile', async () => {
    await assertFails(setDoc(ref('ghost', 'ghost'), mirrorOf()));
  });
  it('ALLOWS signed-in users to read the leaderboard', async () => {
    await assertSucceeds(getDoc(doc(authed(env, 'mallory').firestore(), 'leaderboard_public/bob')));
  });
  it('DENIES unauthenticated leaderboard reads', async () => {
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'leaderboard_public/bob')));
  });
  it('ALLOWS the owner to remove their mirror (opt out)', async () => {
    await assertSucceeds(deleteDoc(doc(authed(env, 'bob').firestore(), 'leaderboard_public/bob')));
  });
  it('DENIES removing someone else\'s mirror', async () => {
    await assertFails(deleteDoc(doc(authed(env, 'mallory').firestore(), 'leaderboard_public/bob')));
  });
});

describe('usernames (D-03)', () => {
  const db = (uid) => authed(env, uid).firestore();
  it('ALLOWS claiming an unclaimed username for yourself', async () => {
    await assertSucceeds(setDoc(doc(db('mallory'), 'usernames/mallory_name'), { uid: 'mallory' }));
  });
  it('DENIES claiming a username on behalf of another uid', async () => {
    await assertFails(setDoc(doc(db('mallory'), 'usernames/free_name'), { uid: 'alice' }));
  });
  it('DENIES taking over an existing claim (audit V-4)', async () => {
    await assertFails(setDoc(doc(db('mallory'), 'usernames/alice_name'), { uid: 'mallory' }));
  });
  it('DENIES re-writing even your own claim (claims are create-only)', async () => {
    await assertFails(setDoc(doc(db('alice'), 'usernames/alice_name'), { uid: 'alice' }));
  });
  it('DENIES extra fields on a claim', async () => {
    await assertFails(setDoc(doc(db('mallory'), 'usernames/m2'), { uid: 'mallory', verified: true }));
  });
  it('ALLOWS releasing your own claim', async () => {
    await assertSucceeds(deleteDoc(doc(db('alice'), 'usernames/alice_name')));
  });
  it('DENIES releasing someone else\'s claim', async () => {
    await assertFails(deleteDoc(doc(db('mallory'), 'usernames/alice_name')));
  });
  it('ALLOWS an atomic rename (claim new + release old in one batch)', async () => {
    const d = db('alice');
    const b = writeBatch(d);
    b.set(doc(d, 'usernames/alice_renamed'), { uid: 'alice' });
    b.delete(doc(d, 'usernames/alice_name'));
    await assertSucceeds(b.commit());
  });
  it('lets exactly ONE of two concurrent claims for the same name succeed', async () => {
    const wins = await countFulfilled([
      setDoc(doc(db('mallory'), 'usernames/contested'), { uid: 'mallory' }),
      setDoc(doc(db('carol'), 'usernames/contested'), { uid: 'carol' }),
    ]);
    if (wins !== 1) throw new Error(`expected exactly 1 successful claim, got ${wins}`);
  });
});
