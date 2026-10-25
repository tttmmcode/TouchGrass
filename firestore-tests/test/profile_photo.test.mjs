// N-6 (Phase 6): a profile photo URL — shown to every signed-in user on the
// leaderboard — may only be null, the owner's own avatar in this app's
// Storage bucket, or the `picture` claim of the caller's verified ID token
// (Google sign-in). Arbitrary URLs are refused; legacy values stay readable.
import { describe, it, before, after, beforeEach } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
  doc, setDoc, getDoc, updateDoc, serverTimestamp, Timestamp,
} from 'firebase/firestore';
import { firestoreEnv, storedUser, defaultSettings, avatarUrl } from './helpers.mjs';

let env;
before(async () => { env = await firestoreEnv(); });
after(async () => { await env.cleanup(); });

const GOOGLE_PHOTO = 'https://lh3.googleusercontent.com/a/ACg8ocJx9_example=s96-c';
const LEGACY_EXTERNAL = 'https://legacy-host.example/old-avatar.png';

/** A signed-in context; Google sign-in tokens carry a `picture` claim. */
const ctx = (uid, picture) => env.authenticatedContext(uid, {
  email: `${uid}@example.test`, ...(picture ? { picture } : {}),
});

function newProfile(uid, photoUrl) {
  return {
    uid, email: `${uid}@example.test`, username: `${uid}_name`, displayName: 'Explorer',
    photoUrl, xp: 0, weeklyXp: 0,
    weeklyXpResetDate: Timestamp.fromMillis(Date.now() + 5 * 86400000),
    level: 1, streak: 0, longestStreak: 0, totalCompletions: 0,
    totalPhotosUploaded: 0, rainyDayCount: 0, currentLeague: 'seedling',
    createdAt: serverTimestamp(), lastActiveDate: serverTimestamp(),
    achievements: [], settings: defaultSettings(), frozenDates: [],
  };
}

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (c) => {
    const db = c.firestore();
    for (const u of ['alice', 'bob', 'mallory', 'newbie']) {
      await setDoc(doc(db, `usernames/${u}_name`), { uid: u });
    }
    await setDoc(doc(db, 'users/alice'), storedUser('alice'));
    await setDoc(doc(db, 'users/bob'), storedUser('bob'));
    // Written by an older app version before this rule existed.
    await setDoc(doc(db, 'users/legacy'), storedUser('legacy', { photoUrl: LEGACY_EXTERNAL }));
  });
});

const bad = [
  ['an arbitrary external URL', 'https://evil.example/pixel.png'],
  ['a Google-hosted URL that is not in the caller\'s token', GOOGLE_PHOTO],
  ['another user\'s avatar', avatarUrl('bob')],
  ['the right path in another Firebase bucket', avatarUrl('alice', 'evil-project.appspot.com')],
  ['a completion photo', avatarUrl('alice').replace('user_avatars%2Falice.png', 'completion_photos%2Falice%2F2026-10-01.jpg')],
  ['an avatar path with traversal', avatarUrl('alice').replace('user_avatars%2Falice.png', 'user_avatars%2Falice.png%2F..%2Fbob.png')],
  ['plain http', avatarUrl('alice').replace('https://', 'http://')],
  ['a javascript: URL', 'javascript:alert(1)'],
  ['an empty string', ''],
  ['a non-string value', 42],
  ['an over-long URL', avatarUrl('alice') + 'x'.repeat(2100)],
];

describe('profile photo — editing (Settings → change photo)', () => {
  it('ALLOWS the owner\'s own avatar from this app\'s bucket', async () => {
    await assertSucceeds(updateDoc(doc(ctx('alice').firestore(), 'users/alice'), { photoUrl: avatarUrl('alice') }));
  });
  it('ALLOWS removing the photo (null)', async () => {
    await assertSucceeds(updateDoc(doc(ctx('alice').firestore(), 'users/alice'), { photoUrl: null }));
  });
  it('ALLOWS keeping the Google photo the caller signed in with', async () => {
    await assertSucceeds(updateDoc(doc(ctx('alice', GOOGLE_PHOTO).firestore(), 'users/alice'), { photoUrl: GOOGLE_PHOTO }));
  });
  for (const [label, url] of bad) {
    it(`DENIES ${label}`, async () => {
      await assertFails(updateDoc(doc(ctx('alice').firestore(), 'users/alice'), { photoUrl: url }));
    });
  }
  it('DENIES a valid photo together with a protected field', async () => {
    await assertFails(updateDoc(doc(ctx('alice').firestore(), 'users/alice'), { photoUrl: avatarUrl('alice'), xp: 99999 }));
    await assertFails(updateDoc(doc(ctx('alice').firestore(), 'users/alice'), { photoUrl: avatarUrl('alice'), entitlementTier: 'premium' }));
  });
  it('DENIES setting a photo on another user\'s profile', async () => {
    await assertFails(updateDoc(doc(ctx('mallory').firestore(), 'users/alice'), { photoUrl: avatarUrl('alice') }));
  });
});

describe('profile photo — new accounts (sign-up)', () => {
  it('ALLOWS no photo (email / Apple sign-up)', async () => {
    await assertSucceeds(setDoc(doc(ctx('newbie').firestore(), 'users/newbie'), newProfile('newbie', null)));
  });
  it('ALLOWS the Google photo exactly as the ID token carries it', async () => {
    await assertSucceeds(setDoc(doc(ctx('newbie', GOOGLE_PHOTO).firestore(), 'users/newbie'), newProfile('newbie', GOOGLE_PHOTO)));
  });
  it('DENIES a Google photo when the token carries a different one', async () => {
    await assertFails(setDoc(doc(ctx('newbie', GOOGLE_PHOTO).firestore(), 'users/newbie'),
      newProfile('newbie', 'https://lh3.googleusercontent.com/a/someone-else')));
  });
  it('DENIES a photo URL on an account whose token has no picture', async () => {
    await assertFails(setDoc(doc(ctx('newbie').firestore(), 'users/newbie'), newProfile('newbie', GOOGLE_PHOTO)));
  });
  for (const [label, url] of bad.filter(([, u]) => u !== avatarUrl('bob'))) {
    it(`DENIES sign-up with ${label}`, async () => {
      await assertFails(setDoc(doc(ctx('newbie').firestore(), 'users/newbie'), newProfile('newbie', url)));
    });
  }
});

describe('profile photo — existing (legacy) data', () => {
  it('a legacy external URL stays readable by its owner', async () => {
    await assertSucceeds(getDoc(doc(ctx('legacy').firestore(), 'users/legacy')));
  });
  it('edits that don\'t touch the photo still work on a legacy profile', async () => {
    await assertSucceeds(updateDoc(doc(ctx('legacy').firestore(), 'users/legacy'), { displayName: 'Still me' }));
  });
  it('the leaderboard mirror can still match a legacy profile', async () => {
    const u = storedUser('legacy', { photoUrl: LEGACY_EXTERNAL });
    await assertSucceeds(setDoc(doc(ctx('legacy').firestore(), 'leaderboard_public/legacy'), {
      displayName: u.displayName, username: u.username, photoUrl: LEGACY_EXTERNAL,
      xp: u.xp, weeklyXp: u.weeklyXp, streak: u.streak, currentLeague: u.currentLeague,
    }));
  });
  it('but a legacy profile cannot switch to another external URL', async () => {
    await assertFails(updateDoc(doc(ctx('legacy').firestore(), 'users/legacy'), { photoUrl: 'https://evil.example/x.png' }));
  });
  it('and can replace it with an allowed avatar or remove it', async () => {
    await assertSucceeds(updateDoc(doc(ctx('legacy').firestore(), 'users/legacy'), { photoUrl: avatarUrl('legacy') }));
    await assertSucceeds(updateDoc(doc(ctx('legacy').firestore(), 'users/legacy'), { photoUrl: null }));
  });
});
