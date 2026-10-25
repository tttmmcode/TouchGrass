// N-1: feedback is a narrowly validated, write-only, rate-capped path.
import { describe, it, before, after, beforeEach } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
  doc, setDoc, getDoc, getDocs, updateDoc, deleteDoc, collection, serverTimestamp, Timestamp,
} from 'firebase/firestore';
import { firestoreEnv, authed, dateKey, countFulfilled } from './helpers.mjs';

let env;
before(async () => { env = await firestoreEnv(); });
after(async () => { await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled((ctx) =>
    setDoc(doc(ctx.firestore(), `feedback/bob_${dateKey(0)}_1`), {
      type: 'bug', message: 'bob private report', userId: 'bob', createdAt: Timestamp.now(),
    }));
});

const today = dateKey(0);
const db = (uid = 'alice') => authed(env, uid).firestore();
const fb = (o = {}) => ({
  type: 'feedback', message: 'Love the app!', userId: 'alice',
  createdAt: serverTimestamp(), appVersion: '1.0.0', ...o,
});
const ref = (id, d = db()) => doc(d, `feedback/${id}`);

describe('feedback — create', () => {
  it('ALLOWS a valid feedback message', async () => {
    await assertSucceeds(setDoc(ref(`alice_${today}_1`), fb()));
  });
  it('ALLOWS a valid bug report without appVersion', async () => {
    const { appVersion: _omit, ...noVersion } = fb({ type: 'bug' });
    await assertSucceeds(setDoc(ref(`alice_${today}_1`), noVersion));
  });
  it('ALLOWS a 1-character and a 1000-character message (boundaries)', async () => {
    await assertSucceeds(setDoc(ref(`alice_${today}_1`), fb({ message: 'x' })));
    await assertSucceeds(setDoc(ref(`alice_${today}_2`), fb({ message: 'x'.repeat(1000) })));
  });
  for (const [label, o] of [
    ['an empty message', { message: '' }],
    ['a 1001-character message (boundary)', { message: 'x'.repeat(1001) }],
    ['a non-string message', { message: { html: '<b>x</b>' } }],
    ['an unknown type', { type: 'admin_request' }],
    ['another user\'s userId', { userId: 'bob' }],
    ['a client-chosen createdAt', { createdAt: Timestamp.fromDate(new Date('2020-01-01')) }],
    ['an over-long appVersion', { appVersion: 'v'.repeat(33) }],
    ['a privilege field', { isAdmin: true }],
    ['a status field the client should not set', { status: 'resolved' }],
  ]) {
    it(`DENIES feedback with ${label}`, async () => {
      await assertFails(setDoc(ref(`alice_${today}_1`), fb(o)));
    });
  }
  it('DENIES a missing required field (no userId)', async () => {
    const { userId: _omit, ...noUser } = fb();
    await assertFails(setDoc(ref(`alice_${today}_1`), noUser));
  });
  it('DENIES unauthenticated submissions', async () => {
    await assertFails(setDoc(ref(`alice_${today}_1`, env.unauthenticatedContext().firestore()), fb()));
  });
  it('DENIES writing into another user\'s ID space', async () => {
    await assertFails(setDoc(ref(`bob_${today}_2`), fb()));
  });
  for (const [label, id] of [
    ['a free-form ID', 'my-feedback'],
    ['slot 0', `alice_${today}_0`],
    ['slot 6 (over the daily cap of 5)', `alice_${today}_6`],
    ['a date 10 days ago', `alice_${dateKey(-10)}_1`],
    ['a date 10 days ahead', `alice_${dateKey(10)}_1`],
  ]) {
    it(`DENIES ${label}`, async () => { await assertFails(setDoc(ref(id), fb())); });
  }
  it('ALLOWS exactly 5 submissions per day and no 6th (daily cap)', async () => {
    for (let n = 1; n <= 5; n++) await assertSucceeds(setDoc(ref(`alice_${today}_${n}`), fb()));
    await assertFails(setDoc(ref(`alice_${today}_6`), fb()));
  });
  it('DENIES re-using a slot (overwriting a submission)', async () => {
    await assertSucceeds(setDoc(ref(`alice_${today}_1`), fb()));
    await assertFails(setDoc(ref(`alice_${today}_1`), fb({ message: 'edited' })));
  });
  it('lets exactly ONE of two concurrent writes to the same slot succeed', async () => {
    const wins = await countFulfilled([
      setDoc(ref(`alice_${today}_1`), fb({ message: 'A' })),
      setDoc(ref(`alice_${today}_1`, db()), fb({ message: 'B' })),
    ]);
    if (wins !== 1) throw new Error(`expected exactly 1 successful write, got ${wins}`);
  });
});

describe('feedback — no client access after submission', () => {
  it('DENIES the author reading their own feedback', async () => {
    await assertSucceeds(setDoc(ref(`alice_${today}_1`), fb()));
    await assertFails(getDoc(ref(`alice_${today}_1`)));
  });
  it('DENIES reading another user\'s feedback', async () => {
    await assertFails(getDoc(ref(`bob_${today}_1`)));
  });
  it('DENIES listing the feedback collection', async () => {
    await assertFails(getDocs(collection(db(), 'feedback')));
  });
  it('DENIES editing feedback', async () => {
    await assertFails(updateDoc(ref(`bob_${today}_1`, db('bob')), { message: 'changed' }));
  });
  it('DENIES deleting feedback (own or others\')', async () => {
    await assertFails(deleteDoc(ref(`bob_${today}_1`, db('bob'))));
    await assertFails(deleteDoc(ref(`bob_${today}_1`)));
  });
});
