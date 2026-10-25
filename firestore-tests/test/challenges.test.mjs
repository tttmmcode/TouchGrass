// D-06 reroll cap (3 per user per day), S-6/S-7 challenge & completion
// forgery, and memory ↔ completion integrity.
import { describe, it, before, after, beforeEach } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
  doc, setDoc, updateDoc, deleteDoc, getDoc, serverTimestamp, Timestamp,
} from 'firebase/firestore';
import {
  firestoreEnv, authed, storedUser, dateKey, challengeDoc, completionDoc,
  photoUrl, countFulfilled,
} from './helpers.mjs';

let env;
before(async () => { env = await firestoreEnv(); });
after(async () => { await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled((ctx) =>
    setDoc(doc(ctx.firestore(), 'users/alice'), storedUser('alice')));
});

const today = dateKey(0);
const aliceDb = () => authed(env, 'alice').firestore();
const chRef = (id = today, db = aliceDb()) => doc(db, `users/alice/challenges/${id}`);
const seedChallenge = (overrides = {}, id = today) =>
  env.withSecurityRulesDisabled((ctx) =>
    setDoc(doc(ctx.firestore(), `users/alice/challenges/${id}`), challengeDoc('alice', id, overrides)));

describe('challenges — creation (S-7)', () => {
  it('ALLOWS today\'s template challenge', async () => {
    await assertSucceeds(setDoc(chRef(), challengeDoc('alice', today)));
  });
  it('ALLOWS tomorrow/yesterday (UTC) to cover every timezone', async () => {
    await assertSucceeds(setDoc(chRef(dateKey(1)), challengeDoc('alice', dateKey(1))));
    await assertSucceeds(setDoc(chRef(dateKey(-1)), challengeDoc('alice', dateKey(-1))));
  });
  for (const [label, id, o] of [
    ['xpReward = 100000 (read by the Cloud Function)', today, { xpReward: 100000 }],
    ['xpReward not matching difficulty', today, { difficulty: 'easy', xpReward: 100 }],
    ['a pre-spent reroll counter', today, { rerollCount: 2 }],
    ['a negative reroll counter', today, { rerollCount: -5 }],
    ['pre-completed', today, { isCompleted: true }],
    ['claimed as AI-generated', today, { aiGenerated: true }],
    ['a date 10 days ago', dateKey(-10), {}],
    ['an ID that is not a date', 'bonus-challenge', {}],
    ['challengeId field ≠ document ID', today, { challengeId: dateKey(1) }],
    ['another user\'s userId', today, { userId: 'bob' }],
  ]) {
    it(`DENIES a challenge with ${label}`, async () => {
      await assertFails(setDoc(chRef(id), challengeDoc('alice', id === 'bonus-challenge' ? id : id, o)));
    });
  }
  it('DENIES creating a challenge in another user\'s subcollection', async () => {
    await assertFails(setDoc(doc(authed(env, 'mallory').firestore(), `users/alice/challenges/${today}`), challengeDoc('alice', today)));
  });
});

describe('challenges — reroll cap: 3 per day (D-06)', () => {
  const reroll = (n, o = {}) => setDoc(chRef(), challengeDoc('alice', today, { title: `Reroll ${n}`, rerollCount: n, ...o }));
  it('ALLOWS rerolls 1, 2 and 3 in sequence', async () => {
    await seedChallenge();
    await assertSucceeds(reroll(1));
    await assertSucceeds(reroll(2));
    await assertSucceeds(reroll(3));
  });
  it('DENIES the 4th reroll (boundary)', async () => {
    await seedChallenge({ rerollCount: 3 });
    await assertFails(reroll(4));
  });
  it('DENIES skipping the counter (0 → 2)', async () => {
    await seedChallenge();
    await assertFails(reroll(2));
  });
  it('DENIES resetting the counter (3 → 0)', async () => {
    await seedChallenge({ rerollCount: 3 });
    await assertFails(reroll(0));
  });
  it('DENIES a reroll that keeps the counter unchanged', async () => {
    await seedChallenge({ rerollCount: 1 });
    await assertFails(reroll(1));
  });
  it('DENIES rerolling a challenge that is already completed', async () => {
    await seedChallenge({ isCompleted: true });
    await assertFails(reroll(1));
  });
  it('DENIES a reroll that raises xpReward beyond its difficulty', async () => {
    await seedChallenge();
    await assertFails(reroll(1, { xpReward: 100 }));
  });
  it('lets exactly ONE of two concurrent rerolls from the same state succeed', async () => {
    await seedChallenge({ rerollCount: 2 });
    const wins = await countFulfilled([reroll(3, { title: 'A' }), reroll(3, { title: 'B' })]);
    if (wins !== 1) throw new Error(`expected exactly 1 successful reroll, got ${wins}`);
  });
  it('DENIES dodging the cap by deleting and recreating today\'s challenge', async () => {
    await seedChallenge({ rerollCount: 3 });
    await assertFails(deleteDoc(chRef()));
  });
  it('ALLOWS marking the challenge completed', async () => {
    await seedChallenge();
    await assertSucceeds(updateDoc(chRef(), { isCompleted: true, completionDate: Timestamp.now() }));
  });
  it('DENIES sneaking other changes into the completion mark', async () => {
    await seedChallenge();
    await assertFails(updateDoc(chRef(), { isCompleted: true, completionDate: Timestamp.now(), xpReward: 100 }));
  });
});

describe('completions — standalone writes (S-6)', () => {
  const ref = (day = today, db = aliceDb()) => doc(db, `completions/alice_${day}`);
  it('ALLOWS an honor-system completion for today', async () => {
    await assertSucceeds(setDoc(ref(), completionDoc('alice', today, serverTimestamp)));
  });
  it('ALLOWS a 0-XP completion record (same-day resubmission, D-01)', async () => {
    await assertSucceeds(setDoc(ref(), completionDoc('alice', today, serverTimestamp, { xpAwarded: 0 })));
  });
  it('ALLOWS a manual-override completion', async () => {
    await assertSucceeds(setDoc(ref(), completionDoc('alice', today, serverTimestamp, {
      overrideUsed: true, verificationResult: { reason: 'Manually submitted by user after verification failed.' },
    })));
  });
  for (const [label, o, day] of [
    ['a fabricated AI verdict (matches/confidence)', { verificationResult: { matches: true, confidence: 0.99, reason: 'x' } }],
    ['xpAwarded = 100000', { xpAwarded: 100000 }],
    ['xpAwarded not in the difficulty table (30)', { xpAwarded: 30 }],
    ['a client-chosen completedAt', { completedAt: Timestamp.fromDate(new Date('2020-01-01')) }],
    ['another user\'s photo', { photoUrl: photoUrl('bob', `${today}.jpg`) }],
    ['a photo not named for its date (orphan-prone legacy name, D-13)', { photoUrl: photoUrl('alice') }],
    ['another day\'s photo', { photoUrl: photoUrl('alice', `${dateKey(-1)}.jpg`) }],
    ['a non-Storage photo URL', { photoUrl: 'https://evil.test/x.jpg' }],
    ['an unknown field', { verified: true }],
    ['a date 10 days ago', {}, dateKey(-10)],
  ]) {
    it(`DENIES a completion with ${label}`, async () => {
      const d = day ?? today;
      await assertFails(setDoc(ref(d), completionDoc('alice', d, serverTimestamp, o)));
    });
  }
  it('DENIES a completion whose ID does not match uid_challengeId', async () => {
    await assertFails(setDoc(doc(aliceDb(), `completions/alice_${dateKey(1)}`), completionDoc('alice', today, serverTimestamp)));
  });
  it('DENIES creating a completion as another user', async () => {
    await assertFails(setDoc(ref(today, authed(env, 'mallory').firestore()), completionDoc('alice', today, serverTimestamp)));
  });
  it('DENIES overwriting or deleting a completion', async () => {
    await assertSucceeds(setDoc(ref(), completionDoc('alice', today, serverTimestamp)));
    await assertFails(setDoc(ref(), completionDoc('alice', today, serverTimestamp, { caption: 'edit' })));
    await assertFails(deleteDoc(ref()));
  });
  it('ALLOWS the owner to read their completion; DENIES others', async () => {
    await assertSucceeds(setDoc(ref(), completionDoc('alice', today, serverTimestamp)));
    await assertSucceeds(getDoc(ref()));
    await assertFails(getDoc(ref(today, authed(env, 'mallory').firestore())));
  });
});

describe('memories — must mirror the user\'s own completion', () => {
  const memId = `alice_${today}`;
  const memory = (o = {}) => ({
    userId: 'alice', challengeId: today, challengeDay: 3, challengeTitle: 'Find a leaf',
    challengeCategory: 'nature', photoUrl: photoUrl('alice', `${today}.jpg`), xpEarned: 50,
    verificationMethod: 'auto_approved', completionDate: Timestamp.now(),
    createdAt: serverTimestamp(), ...o,
  });
  const mRef = (db = aliceDb()) => doc(db, `users/alice/memories/${memId}`);
  beforeEach(async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), `completions/${memId}`), completionDoc('alice', today, () => Timestamp.now())));
  });
  it('ALLOWS a memory for the user\'s own completion', async () => {
    await assertSucceeds(setDoc(mRef(), memory()));
  });
  for (const [label, o] of [
    ['a different photo', { photoUrl: photoUrl('alice', 'other.jpg') }],
    ['inflated xpEarned', { xpEarned: 5000 }],
    ['a claimed AI verification', { verificationMethod: 'ai_verified' }],
    ['another user\'s userId', { userId: 'bob' }],
  ]) {
    it(`DENIES a memory with ${label}`, async () => { await assertFails(setDoc(mRef(), memory(o))); });
  }
  it('DENIES a memory with no matching completion', async () => {
    await assertFails(setDoc(doc(aliceDb(), 'users/alice/memories/alice_2001-01-01'), memory({ challengeId: '2001-01-01' })));
  });
  it('ALLOWS editing the caption; DENIES editing anything else', async () => {
    await assertSucceeds(setDoc(mRef(), memory()));
    await assertSucceeds(updateDoc(mRef(), { caption: 'Lovely day', captionUpdatedAt: serverTimestamp() }));
    await assertFails(updateDoc(mRef(), { xpEarned: 500 }));
  });
  it('DENIES reading another user\'s memories', async () => {
    await assertSucceeds(setDoc(mRef(), memory()));
    await assertFails(getDoc(mRef(authed(env, 'mallory').firestore())));
  });
});
