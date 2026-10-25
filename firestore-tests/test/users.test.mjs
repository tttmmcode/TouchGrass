// D-02 (reward / profile forgery) and D-07 (entitlement-grant lockout).
import { describe, it, before, after, beforeEach } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
  doc, setDoc, updateDoc, deleteDoc, getDoc, writeBatch, serverTimestamp,
  Timestamp, arrayUnion, increment,
} from 'firebase/firestore';
import {
  firestoreEnv, authed, storedUser, defaultSettings, dateKey, completionDoc,
  levelForXp, leagueForXp, countFulfilled, avatarUrl,
} from './helpers.mjs';

let env;
before(async () => { env = await firestoreEnv(); });
after(async () => { await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users/alice'), storedUser('alice'));
    await setDoc(doc(db, 'usernames/alice_name'), { uid: 'alice' });
    await setDoc(doc(db, 'usernames/alice_new'), { uid: 'alice' });
    await setDoc(doc(db, 'usernames/bob_name'), { uid: 'bob' });
    await setDoc(doc(db, 'usernames/mallory_name'), { uid: 'mallory' });
    await setDoc(doc(db, 'users/bob'), storedUser('bob', { entitlementTier: 'premium' }));
    // An older-schema document missing several reward fields.
    await setDoc(doc(db, 'users/legacy'), {
      uid: 'legacy', email: 'legacy@example.test', username: 'legacy_name',
      displayName: 'Legacy', xp: 300, level: 4, streak: 2,
      createdAt: Timestamp.now(), lastActiveDate: Timestamp.now(),
      settings: { profilePublic: true },
    });
  });
});

/** The document the app writes for a brand-new account (UserModel.initial +
 * server timestamps for createdAt/lastActiveDate). */
function newProfile(uid, overrides = {}) {
  return {
    uid,
    email: `${uid}@example.test`,
    username: `${uid}_name`,
    displayName: 'Explorer',
    photoUrl: null,
    xp: 0, weeklyXp: 0,
    weeklyXpResetDate: Timestamp.fromMillis(Date.now() + 5 * 86400000),
    level: 1, streak: 0, longestStreak: 0, totalCompletions: 0,
    totalPhotosUploaded: 0, rainyDayCount: 0, currentLeague: 'seedling',
    createdAt: serverTimestamp(), lastActiveDate: serverTimestamp(),
    achievements: [], settings: defaultSettings(), frozenDates: [],
    ...overrides,
  };
}

describe('users — create (D-02: initial account values)', () => {
  it('ALLOWS a genuine new profile with default values', async () => {
    await assertSucceeds(setDoc(doc(authed(env, 'mallory').firestore(), 'users/mallory'), newProfile('mallory')));
  });
  for (const [label, overrides] of [
    ['xp = 5,000,000', { xp: 5000000, level: 50001, currentLeague: 'aurora' }],
    ['weeklyXp = 99,999', { weeklyXp: 99999 }],
    ['streak = 365', { streak: 365, longestStreak: 365 }],
    ['pre-earned achievements', { achievements: ['streak_100'] }],
    ['streakFreezesOwned = 999', { settings: { ...defaultSettings(), streakFreezesOwned: 999 } }],
    ['self-granted entitlementTier', { entitlementTier: 'premium' }],
    ['backdated createdAt (Member Since forgery)', { createdAt: Timestamp.fromDate(new Date('2001-01-01')) }],
    ['username not claimed by the caller', { username: 'bob_name' }],
    ['mismatched uid field', { uid: 'alice' }],
    ['email that is not the signed-in email', { email: 'someone@else.test' }],
  ]) {
    it(`DENIES ${label}`, async () => {
      await assertFails(setDoc(doc(authed(env, 'mallory').firestore(), 'users/mallory'), newProfile('mallory', overrides)));
    });
  }
  it('DENIES creating another user\'s document', async () => {
    await assertFails(setDoc(doc(authed(env, 'mallory').firestore(), 'users/carol'), newProfile('carol')));
  });
});

// Phase 7G: deleteAccount writes deletedAccounts/{uid} before it deletes
// the profile. A device still holding the deleted account's ID token (up to
// 1 h) must not be able to re-create the profile — storage.rules let a uid
// upload only while its profile exists.
describe('users — no re-creation after account deletion (Phase 7G)', () => {
  const markDeleted = (uid) => env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `deletedAccounts/${uid}`), {
      markedAt: Timestamp.now(), expiresAt: Timestamp.fromMillis(Date.now() + 7200000),
    });
  });
  it('DENIES re-creating a deleted account\'s profile, even a genuine-looking one', async () => {
    await markDeleted('mallory');
    await assertFails(setDoc(doc(authed(env, 'mallory').firestore(), 'users/mallory'), newProfile('mallory')));
  });
  it('another account\'s marker doesn\'t affect a genuine sign-up', async () => {
    await markDeleted('carol');
    await assertSucceeds(setDoc(doc(authed(env, 'mallory').firestore(), 'users/mallory'), newProfile('mallory')));
  });
  it('DENIES clients reading, creating or deleting deletion markers (server-only)', async () => {
    await markDeleted('mallory');
    const db = authed(env, 'mallory').firestore();
    await assertFails(getDoc(doc(db, 'deletedAccounts/mallory')));
    await assertFails(deleteDoc(doc(db, 'deletedAccounts/mallory')));
    await assertFails(setDoc(doc(db, 'deletedAccounts/mallory'), { markedAt: Timestamp.now() }));
    await assertFails(setDoc(doc(authed(env, 'alice').firestore(), 'deletedAccounts/alice'), { markedAt: Timestamp.now() }));
  });
  it('an existing profile is unaffected by a marker (updates still follow the normal rules)', async () => {
    await markDeleted('alice');
    await assertSucceeds(updateDoc(doc(authed(env, 'alice').firestore(), 'users/alice'), { displayName: 'Alice A.' }));
  });
});

describe('users — profile edits', () => {
  const alice = () => doc(authed(env, 'alice').firestore(), 'users/alice');
  for (const [label, data] of [
    ['displayName', { displayName: 'Alice A.' }],
    ['fcmToken', { fcmToken: 'token-123' }],
    ['clearing fcmToken on sign-out', { fcmToken: '' }],
    ['settings.locationEnabled', { 'settings.locationEnabled': false }],
    ['settings.companionType', { 'settings.companionType': 'pebble' }],
    ['settings.profilePublic', { 'settings.profilePublic': false }],
    ['settings.preferredCategories', { 'settings.preferredCategories': ['nature'] }],
    ['lastActiveDate = server time (sign-in)', { lastActiveDate: serverTimestamp() }],
    ['username → a claim the caller owns', { username: 'alice_new' }],
    ['profile photo only (current app: avatars are not adventure photos)', { photoUrl: avatarUrl('alice') }],
    ['profile photo + totalPhotosUploaded +1 (older app versions)', { photoUrl: avatarUrl('alice'), totalPhotosUploaded: increment(1) }],
  ]) {
    it(`ALLOWS ${label}`, async () => { await assertSucceeds(updateDoc(alice(), data)); });
  }
  for (const [label, data] of [
    ['xp change outside a completion', { xp: 4100, level: 42, currentLeague: 'mountain' }],
    ['repeated +4000 xp (audit V-4)', { xp: 4100 }],
    ['streak change outside a completion', { streak: 2 }],
    ['adding achievements outside a completion', { achievements: arrayUnion('streak_100') }],
    ['settings.streakFreezesOwned = 999', { 'settings.streakFreezesOwned': 999 }],
    ['unknown settings key', { 'settings.isAdmin': true }],
    ['createdAt rewrite', { createdAt: Timestamp.fromDate(new Date('2001-01-01')) }],
    ['uid rewrite', { uid: 'bob' }],
    ['self-grant entitlementTier', { entitlementTier: 'premium' }],
    ['username → someone else\'s claim', { username: 'bob_name' }],
    ['username → unclaimed name', { username: 'nobody_has_this' }],
    ['totalPhotosUploaded +5', { totalPhotosUploaded: increment(5) }],
    ['lastActiveDate backdated', { lastActiveDate: Timestamp.fromDate(new Date('2020-01-01')) }],
    ['email rewrite', { email: 'other@example.test' }],
    ['lastCompletionDate outside a completion', { lastCompletionDate: serverTimestamp() }],
    ['unknown field', { isModerator: true }],
  ]) {
    it(`DENIES ${label}`, async () => { await assertFails(updateDoc(alice(), data)); });
  }
  it('ALLOWS profile edits on an older document missing reward fields', async () => {
    await assertSucceeds(updateDoc(doc(authed(env, 'legacy').firestore(), 'users/legacy'), { fcmToken: 't' }));
  });
});

describe('users — streak-freeze purchase', () => {
  beforeEach(async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), 'users/alice'), storedUser('alice', { xp: 1000 })));
  });
  const ref = () => doc(authed(env, 'alice').firestore(), 'users/alice');
  it('ALLOWS spending exactly 200 XP for one freeze', async () => {
    await assertSucceeds(updateDoc(ref(), {
      xp: 800, level: levelForXp(800), currentLeague: leagueForXp(800), 'settings.streakFreezesOwned': 4,
    }));
  });
  it('DENIES a free freeze (no XP spent)', async () => {
    await assertFails(updateDoc(ref(), { 'settings.streakFreezesOwned': 4 }));
  });
  it('DENIES two freezes for the price of one', async () => {
    await assertFails(updateDoc(ref(), {
      xp: 800, level: levelForXp(800), currentLeague: leagueForXp(800), 'settings.streakFreezesOwned': 5,
    }));
  });
  it('DENIES a purchase that would take XP below zero', async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), 'users/alice'), storedUser('alice', { xp: 150 })));
    await assertFails(updateDoc(ref(), {
      xp: -50, level: 0, currentLeague: 'seedling', 'settings.streakFreezesOwned': 4,
    }));
  });
});

/** The batched write CameraNotifier now performs: create the completion and
 * apply its reward in one atomic commit. */
function rewardBatch(db, uid, { day = dateKey(0), completion = {}, user = {} } = {}) {
  const id = `${uid}_${day}`;
  const b = writeBatch(db);
  b.set(doc(db, `completions/${id}`), completionDoc(uid, day, serverTimestamp, completion));
  b.update(doc(db, `users/${uid}`), {
    lastCompletionId: id, lastActiveDate: serverTimestamp(), lastCompletionDate: serverTimestamp(), ...user,
  });
  return b.commit();
}

// alice starts at xp 100, streak 1, longestStreak 1, totalCompletions 1,
// achievements ['first_touch'], 3 freezes.
const newDayReward = (extra = {}) => ({
  xp: 150, weeklyXp: 150, level: 2, currentLeague: 'seedling',
  streak: 2, longestStreak: 2, totalCompletions: 2, rainyDayCount: 0,
  ...extra,
});

describe('users — completion reward batch (D-02)', () => {
  const db = () => authed(env, 'alice').firestore();
  it('ALLOWS a genuine new-day completion (+50 XP, streak +1)', async () => {
    await assertSucceeds(rewardBatch(db(), 'alice', { user: newDayReward() }));
  });
  it('ALLOWS a same-day resubmission that awards nothing (completion records 0 XP)', async () => {
    await assertSucceeds(rewardBatch(db(), 'alice', { completion: { xpAwarded: 0 }, user: {} }));
  });
  it('ALLOWS an earned achievement with its exact XP bonus (streak_3 = +50)', async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), 'users/alice'), storedUser('alice', { streak: 2, longestStreak: 2 })));
    await assertSucceeds(rewardBatch(db(), 'alice', {
      user: newDayReward({
        xp: 200, weeklyXp: 200, level: 3, streak: 3, longestStreak: 3,
        achievements: arrayUnion('streak_3'), 'achievementTimestamps.streak_3': serverTimestamp(),
      }),
    }));
  });
  it('ALLOWS a same-day resubmission that only grants a newly qualifying achievement', async () => {
    // alice has 100 XP but no xp_100 yet: the app awards just its +25 bonus.
    await assertSucceeds(rewardBatch(db(), 'alice', {
      completion: { xpAwarded: 0 },
      user: {
        xp: 125, weeklyXp: 125, level: 2, achievements: arrayUnion('xp_100'),
        'achievementTimestamps.xp_100': serverTimestamp(),
      },
    }));
  });
  it('ALLOWS a Rainy Day (freeze) absorbing one missed day', async () => {
    await assertSucceeds(rewardBatch(db(), 'alice', {
      user: newDayReward({
        streak: 1, longestStreak: 1, rainyDayCount: 1, 'settings.streakFreezesOwned': 2,
        frozenDates: arrayUnion('2026-01-01'),
      }),
    }));
  });
  it('ALLOWS a streak reset to 1', async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), 'users/alice'), storedUser('alice', { streak: 5, longestStreak: 5 })));
    await assertSucceeds(rewardBatch(db(), 'alice', { user: newDayReward({ streak: 1, longestStreak: 5 }) }));
  });
  it('ALLOWS the 7-day milestone freeze bonus (+1)', async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), 'users/alice'), storedUser('alice', {
        streak: 6, longestStreak: 6, achievements: ['first_touch', 'streak_3'],
      })));
    await assertSucceeds(rewardBatch(db(), 'alice', {
      user: newDayReward({
        xp: 250, weeklyXp: 250, level: 3, streak: 7, longestStreak: 7,
        achievements: arrayUnion('streak_7'), 'achievementTimestamps.streak_7': serverTimestamp(),
        'settings.streakFreezesOwned': 4,
      }),
    }));
  });
  it('ALLOWS a weekly reset (weeklyXp restarts at this award)', async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), 'users/alice'), storedUser('alice', {
        weeklyXp: 900, weeklyXpResetDate: Timestamp.fromMillis(Date.now() - 86400000),
      })));
    await assertSucceeds(rewardBatch(db(), 'alice', {
      user: newDayReward({ weeklyXp: 50, weeklyXpResetDate: Timestamp.fromMillis(Date.now() + 4 * 86400000) }),
    }));
  });
  it("ALLOWS a brand-new account's first completion: +XP, streak 0 → 1 (D-01)", async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), 'users/alice'), storedUser('alice', {
        xp: 0, weeklyXp: 0, level: 1, streak: 0, longestStreak: 0, totalCompletions: 0, achievements: [],
      })));
    await assertSucceeds(rewardBatch(db(), 'alice', {
      completion: { xpAwarded: 25 },
      user: {
        xp: 50, weeklyXp: 50, level: 1, streak: 1, longestStreak: 1, totalCompletions: 1,
        achievements: arrayUnion('first_touch'), 'achievementTimestamps.first_touch': serverTimestamp(),
      },
    }));
  });

  for (const [label, opts] of [
    ['+4000 XP for one completion', { user: newDayReward({ xp: 4100, weeklyXp: 4100, level: 42, currentLeague: 'mountain' }) }],
    ['more XP than the completion awards', { completion: { xpAwarded: 25 }, user: newDayReward() }],
    ['xpAwarded = 100000 on the completion', { completion: { xpAwarded: 100000 }, user: newDayReward({ xp: 100100, weeklyXp: 100100, level: 1002, currentLeague: 'aurora' }) }],
    ['XP without counting the completion', { user: newDayReward({ totalCompletions: 1 }) }],
    ['level not matching XP', { user: newDayReward({ level: 9 }) }],
    ['league not matching XP', { user: newDayReward({ currentLeague: 'aurora' }) }],
    ['streak +5', { user: newDayReward({ streak: 6, longestStreak: 6 }) }],
    ['longestStreak inflated', { user: newDayReward({ longestStreak: 50 }) }],
    ['unearned achievement (streak_30 at streak 2)', { user: newDayReward({ xp: 450, weeklyXp: 450, level: 5, currentLeague: 'sprout', achievements: arrayUnion('streak_30') }) }],
    ['invented achievement id', { user: newDayReward({ achievements: arrayUnion('made_up') }) }],
    ['achievement bonus XP without the achievement', { user: newDayReward({ xp: 450, weeklyXp: 450, level: 5, currentLeague: 'sprout' }) }],
    ['free streak freezes', { user: newDayReward({ 'settings.streakFreezesOwned': 10 }) }],
    ['weeklyXp inflated', { user: newDayReward({ weeklyXp: 9999 }) }],
    ['completion dated 10 days ago', { day: dateKey(-10), user: newDayReward() }],
    ['completion dated 10 days ahead', { day: dateKey(10), user: newDayReward() }],
    ['lastCompletionDate backdated', { user: newDayReward({ lastCompletionDate: Timestamp.fromDate(new Date('2020-01-01')) }) }],
    ['XP when the completion records 0 XP', { completion: { xpAwarded: 0 }, user: newDayReward() }],
    ['no XP when the completion records a 50-XP award', { user: {} }],
    ['fabricated AI verdict on the completion', { completion: { verificationResult: { matches: true, confidence: 0.99, reason: 'x' } }, user: newDayReward() }],
  ]) {
    it(`DENIES ${label}`, async () => { await assertFails(rewardBatch(db(), 'alice', opts)); });
  }

  it('DENIES re-using an existing completion to award XP again', async () => {
    await assertSucceeds(rewardBatch(db(), 'alice', { user: newDayReward() }));
    await assertFails(updateDoc(doc(db(), 'users/alice'), {
      lastCompletionId: 'alice_' + dateKey(0), xp: 200, weeklyXp: 200, level: 3, totalCompletions: 3,
      lastActiveDate: serverTimestamp(),
    }));
  });
  it('DENIES an XP award with no completion in the same batch', async () => {
    await assertFails(updateDoc(doc(db(), 'users/alice'), {
      lastCompletionId: 'alice_' + dateKey(0), ...newDayReward(), lastActiveDate: serverTimestamp(),
    }));
  });
  it('DENIES a second completion for the same day', async () => {
    await assertSucceeds(rewardBatch(db(), 'alice', { user: newDayReward() }));
    await assertFails(rewardBatch(db(), 'alice', { user: {} }));
  });
  it('DENIES a reward batch that does not stamp lastCompletionDate (D-01)', async () => {
    const d = db();
    const id = `alice_${dateKey(0)}`;
    const b = writeBatch(d);
    b.set(doc(d, `completions/${id}`), completionDoc('alice', dateKey(0), serverTimestamp));
    b.update(doc(d, 'users/alice'), { lastCompletionId: id, lastActiveDate: serverTimestamp(), ...newDayReward() });
    await assertFails(b.commit());
  });
  it('lets exactly ONE of two concurrent same-day submissions commit (retry / double-tap / 2 devices)', async () => {
    const wins = await countFulfilled([
      rewardBatch(authed(env, 'alice').firestore(), 'alice', { user: newDayReward() }),
      rewardBatch(authed(env, 'alice').firestore(), 'alice', { user: newDayReward() }),
    ]);
    if (wins !== 1) throw new Error(`expected exactly 1 committed submission, got ${wins}`);
  });
  it('DENIES writing a completion-reward batch for another user', async () => {
    await assertFails(rewardBatch(authed(env, 'mallory').firestore(), 'alice', { user: newDayReward() }));
  });
});

describe('users — D-07 server-granted entitlement', () => {
  const bob = () => authed(env, 'bob').firestore();
  it('ALLOWS a premium user to update their FCM token', async () => {
    await assertSucceeds(updateDoc(doc(bob(), 'users/bob'), { fcmToken: 'tok' }));
  });
  it('ALLOWS a premium user to receive a normal completion reward', async () => {
    await assertSucceeds(rewardBatch(bob(), 'bob', { user: newDayReward() }));
  });
  it('DENIES a premium user changing their own tier', async () => {
    await assertFails(updateDoc(doc(bob(), 'users/bob'), { entitlementTier: 'admin_test' }));
  });
  it('DENIES a premium user removing their tier field', async () => {
    // Full overwrite of bob's profile without the server-set tier field.
    await assertFails(setDoc(doc(bob(), 'users/bob'), storedUser('bob')));
  });
  it('DENIES a free user granting themselves premium', async () => {
    await assertFails(updateDoc(doc(authed(env, 'alice').firestore(), 'users/alice'), { entitlementTier: 'premium' }));
  });
  it('DENIES client writes to aiUsage counters', async () => {
    await assertFails(setDoc(doc(bob(), 'users/bob/aiUsage/2026-10'), { verificationCount: 0 }));
  });
});

describe('users — isolation and deletion', () => {
  it('ALLOWS the owner to read their own profile', async () => {
    await assertSucceeds(getDoc(doc(authed(env, 'alice').firestore(), 'users/alice')));
  });
  it('DENIES reading another user\'s private profile', async () => {
    await assertFails(getDoc(doc(authed(env, 'mallory').firestore(), 'users/alice')));
  });
  it('DENIES unauthenticated reads', async () => {
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'users/alice')));
  });
  it('DENIES editing another user\'s profile', async () => {
    await assertFails(updateDoc(doc(authed(env, 'mallory').firestore(), 'users/alice'), { displayName: 'pwned' }));
  });
  // Account deletion (D-04) is Phase 2; client deletion stays denied until
  // that architecture is approved — asserted so a change is deliberate.
  it('DENIES client deletion of a profile (D-04 deferred to Phase 2)', async () => {
    await assertFails(deleteDoc(doc(authed(env, 'alice').firestore(), 'users/alice')));
  });
});
