// Phase 7H: after deleteAccount, a device that still holds the deleted
// account's ID token (up to 1 h) must not be able to create anything that
// nothing would ever delete. deleteAccount writes deletedAccounts/{uid}
// before it deletes any data; every client create rule checks it.
// (Profile re-creation is covered in users.test.mjs; late photo uploads in
// storage_release_parity.test.mjs.)
import { describe, it, before, after, beforeEach } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc, deleteDoc, serverTimestamp, Timestamp } from 'firebase/firestore';
import {
  firestoreEnv, authed, storedUser, dateKey, challengeDoc, completionDoc, photoUrl,
} from './helpers.mjs';

let env;
before(async () => { env = await firestoreEnv(); });
after(async () => { await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users/alice'), storedUser('alice'));
    await setDoc(doc(db, 'users/bob'), storedUser('bob'));
  });
});

const today = dateKey(0);
const memId = (uid) => `${uid}_${today}`;

/** What deleteAccount leaves behind: the marker, and (by the time its
 * Firestore step finishes) no profile. [keepProfile] models the moment
 * between writing the marker and deleting the profile. */
const deleteAccount = (uid, { keepProfile = false } = {}) => env.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  await setDoc(doc(db, `deletedAccounts/${uid}`), {
    markedAt: Timestamp.now(), expiresAt: Timestamp.fromMillis(Date.now() + 2 * 3600000),
  });
  if (!keepProfile) await deleteDoc(doc(db, `users/${uid}`));
});

/** One of every document a client can create, as the app writes it. The
 * client is made when a write runs (the emulator env exists only then). */
const db = (uid) => authed(env, uid).firestore();
const CREATES = [
  ['a daily challenge', (uid) => setDoc(doc(db(uid), `users/${uid}/challenges/${today}`), challengeDoc(uid, today))],
  ['a completion', (uid) => setDoc(doc(db(uid), `completions/${memId(uid)}`), completionDoc(uid, today, serverTimestamp))],
  ['feedback', (uid) => setDoc(doc(db(uid), `feedback/${uid}_${today}_1`), {
    type: 'feedback', message: 'hi', userId: uid, createdAt: serverTimestamp(),
  })],
  ['a username claim', (uid) => setDoc(doc(db(uid), `usernames/${uid}_late`), { uid })],
];

/** A Journal entry needs its completion to exist first. */
const seedCompletion = (uid) => env.withSecurityRulesDisabled((ctx) =>
  setDoc(doc(ctx.firestore(), `completions/${memId(uid)}`), completionDoc(uid, today, () => Timestamp.now())));
const journalEntry = (uid) => setDoc(doc(authed(env, uid).firestore(), `users/${uid}/memories/${memId(uid)}`), {
  userId: uid, challengeId: today, challengeDay: 3, challengeTitle: 'Find a leaf',
  challengeCategory: 'nature', photoUrl: photoUrl(uid, `${today}.jpg`), xpEarned: 50,
  verificationMethod: 'auto_approved', completionDate: Timestamp.now(), createdAt: serverTimestamp(),
});

describe('creates after account deletion (Phase 7H)', () => {
  for (const [label, write] of CREATES) {
    it(`control: a live account can create ${label}`, async () => {
      await assertSucceeds(write('alice'));
    });
  }
  it('control: a live account can create a Journal entry', async () => {
    await seedCompletion('alice');
    await assertSucceeds(journalEntry('alice'));
  });

  for (const keepProfile of [false, true]) {
    const when = keepProfile ? 'while deletion is still running (profile not yet deleted)' : 'once deleted';
    describe(`a stale session ${when}`, () => {
      for (const [label, write] of CREATES) {
        it(`DENIES creating ${label}`, async () => {
          await deleteAccount('alice', { keepProfile });
          await assertFails(write('alice'));
        });
      }
      it('DENIES creating a Journal entry', async () => {
        await seedCompletion('alice');
        await deleteAccount('alice', { keepProfile });
        await assertFails(journalEntry('alice'));
      });
    });
  }

  it('an EXPIRED marker (a failed deletion never retried) no longer blocks the account that still exists', async () => {
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'deletedAccounts/alice'), {
      markedAt: Timestamp.fromMillis(Date.now() - 3 * 3600000),
      expiresAt: Timestamp.fromMillis(Date.now() - 3600000),
    }));
    for (const [, write] of CREATES) await assertSucceeds(write('alice'));
    await seedCompletion('alice');
    await assertSucceeds(journalEntry('alice'));
  });

  it('another account\'s deletion doesn\'t affect anyone else', async () => {
    await deleteAccount('bob');
    for (const [, write] of CREATES) await assertSucceeds(write('alice'));
    await seedCompletion('alice');
    await assertSucceeds(journalEntry('alice'));
  });
});
