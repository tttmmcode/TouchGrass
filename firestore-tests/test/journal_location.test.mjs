// D-13: completion + reward + Journal entry are one atomic batch; Journal
// repair is create-only and can't double-write or touch rewards.
// D-09: optional location data is only stored while the owner's
// settings.locationEnabled is on.
import { describe, it, before, after, beforeEach } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
  doc, setDoc, getDoc, writeBatch, serverTimestamp, Timestamp, GeoPoint,
} from 'firebase/firestore';
import {
  firestoreEnv, authed, storedUser, defaultSettings, dateKey, completionDoc,
  photoUrl, countFulfilled,
} from './helpers.mjs';

let env;
before(async () => { env = await firestoreEnv(); });
after(async () => { await env.cleanup(); });

const today = dateKey(0);
const id = (uid = 'alice', day = today) => `${uid}_${day}`;
const seedUser = (uid, settings = {}) => env.withSecurityRulesDisabled((ctx) =>
  setDoc(doc(ctx.firestore(), `users/${uid}`), storedUser(uid, {
    settings: { ...defaultSettings(), ...settings },
  })));

beforeEach(async () => {
  await env.clearFirestore();
  await seedUser('alice');
  await seedUser('bob');
});

const db = (uid = 'alice') => authed(env, uid).firestore();

/** A Journal entry exactly as journalEntryForCompletion() builds it. */
const memory = (uid = 'alice', day = today, o = {}) => ({
  userId: uid, challengeId: day, challengeDay: 3, challengeTitle: 'Find a leaf',
  challengeCategory: 'nature', photoUrl: photoUrl(uid, `${day}.jpg`), xpEarned: 50,
  verificationMethod: 'auto_approved', completionDate: Timestamp.now(),
  createdAt: serverTimestamp(), ...o,
});

// alice (xp 100, streak 1, 3 freezes, ['first_touch']) completing a 50-XP
// challenge on a new day — the same reward the users suite uses.
const newDayReward = {
  xp: 150, weeklyXp: 150, level: 2, currentLeague: 'seedling',
  streak: 2, longestStreak: 2, totalCompletions: 2, rainyDayCount: 0,
};

/** completion + reward + Journal entry, as UserRepository.commitCompletion
 * writes them with a journalEntry builder. */
function fullBatch(d, { completion = {}, mem = {}, includeMemory = true } = {}) {
  const b = writeBatch(d);
  b.set(doc(d, `completions/${id()}`), completionDoc('alice', today, serverTimestamp, completion));
  b.update(doc(d, 'users/alice'), {
    ...newDayReward, lastCompletionId: id(), lastActiveDate: serverTimestamp(),
    lastCompletionDate: serverTimestamp(),
  });
  if (includeMemory) b.set(doc(d, `users/alice/memories/${id()}`), memory('alice', today, mem));
  return b.commit();
}

async function exists(path) {
  let found = false;
  await env.withSecurityRulesDisabled(async (ctx) => {
    found = (await getDoc(doc(ctx.firestore(), path))).exists();
  });
  return found;
}

async function seedCompletion(uid, o = {}) {
  await env.withSecurityRulesDisabled((ctx) =>
    setDoc(doc(ctx.firestore(), `completions/${id(uid)}`),
      completionDoc(uid, today, () => Timestamp.now(), o)));
}

describe('D-13 — completion, reward and Journal entry commit together', () => {
  it('ALLOWS the full batch (completion + reward + Journal entry)', async () => {
    await assertSucceeds(fullBatch(db()));
    if (!(await exists(`users/alice/memories/${id()}`))) throw new Error('Journal entry missing');
  });
  it('ALLOWS the batch for a same-day 0-XP completion with a 0-XP entry', async () => {
    const d = db(); // one Firestore instance per batch
    const b = writeBatch(d);
    b.set(doc(d, `completions/${id()}`), completionDoc('alice', today, serverTimestamp, { xpAwarded: 0 }));
    b.update(doc(d, 'users/alice'), {
      lastCompletionId: id(), lastActiveDate: serverTimestamp(), lastCompletionDate: serverTimestamp(),
    });
    b.set(doc(d, `users/alice/memories/${id()}`), memory('alice', today, { xpEarned: 0 }));
    await assertSucceeds(b.commit());
  });
  for (const [label, mem] of [
    ['an entry showing XP that was not granted', { xpEarned: 100 }],
    ['an entry with a different photo', { photoUrl: photoUrl('alice', `${dateKey(-1)}.jpg`) }],
    ['an entry claiming AI verification', { verificationMethod: 'ai_verified' }],
  ]) {
    it(`DENIES the whole batch with ${label} — and nothing is saved`, async () => {
      await assertFails(fullBatch(db(), { mem }));
      if (await exists(`completions/${id()}`)) throw new Error('completion saved without its entry');
    });
  }
  it('lets exactly ONE of two concurrent full batches succeed (no duplicate XP or entry)', async () => {
    const wins = await countFulfilled([fullBatch(db()), fullBatch(db())]);
    if (wins !== 1) throw new Error(`expected exactly 1 successful batch, got ${wins}`);
  });
  it('DENIES a retried batch after success (nothing counted twice)', async () => {
    await assertSucceeds(fullBatch(db()));
    await assertFails(fullBatch(db()));
  });
});

describe('D-13 — Journal repair for an existing completion', () => {
  beforeEach(async () => { await seedCompletion('alice'); });
  it('ALLOWS creating the missing entry for the owner\'s completion', async () => {
    await assertSucceeds(setDoc(doc(db(), `users/alice/memories/${id()}`), memory()));
  });
  it('DENIES overwriting an entry that already exists (repeat / concurrent repair)', async () => {
    await assertSucceeds(setDoc(doc(db(), `users/alice/memories/${id()}`), memory()));
    await assertFails(setDoc(doc(db(), `users/alice/memories/${id()}`), memory('alice', today, { caption: 'x' })));
  });
  it('lets exactly ONE of two concurrent repairs create the entry', async () => {
    const wins = await countFulfilled([
      setDoc(doc(db(), `users/alice/memories/${id()}`), memory()),
      setDoc(doc(db(), `users/alice/memories/${id()}`), memory()),
    ]);
    // The second write finds the entry already there, so it is an update —
    // which the rules deny for anything but the caption.
    if (wins !== 1) throw new Error(`expected exactly 1 successful repair, got ${wins}`);
  });
  it('DENIES a repair that changes XP', async () => {
    await assertFails(setDoc(doc(db(), `users/alice/memories/${id()}`), memory('alice', today, { xpEarned: 100 })));
  });
  it('DENIES another user writing into alice\'s Journal', async () => {
    await assertFails(setDoc(doc(db('bob'), `users/alice/memories/${id()}`), memory()));
  });
  it('DENIES alice creating an entry for bob\'s completion in her own Journal', async () => {
    await seedCompletion('bob');
    await assertFails(setDoc(doc(db(), `users/alice/memories/${id('bob')}`), memory('alice', today, {
      photoUrl: photoUrl('bob', `${today}.jpg`),
    })));
  });
  it('DENIES reading another user\'s Journal entry', async () => {
    await assertSucceeds(setDoc(doc(db(), `users/alice/memories/${id()}`), memory()));
    await assertFails(getDoc(doc(db('bob'), `users/alice/memories/${id()}`)));
  });
});

describe('D-09 — location setting ON (or never set)', () => {
  it('ALLOWS a completion with a location', async () => {
    await assertSucceeds(setDoc(doc(db(), `completions/${id()}`),
      completionDoc('alice', today, serverTimestamp, { location: new GeoPoint(30.2, -97.7) })));
  });
  it('ALLOWS a Journal entry with coordinates, place name and weather', async () => {
    await seedCompletion('alice', { location: new GeoPoint(30.2, -97.7) });
    await assertSucceeds(setDoc(doc(db(), `users/alice/memories/${id()}`), memory('alice', today, {
      latitude: 30.2, longitude: -97.7, locationName: 'Zilker Park', weatherCondition: 'Clear', weatherEmoji: '☀️',
    })));
  });
  it('ALLOWS location data when the setting was never stored (default on)', async () => {
    await env.withSecurityRulesDisabled((ctx) => {
      const u = storedUser('alice');
      delete u.settings.locationEnabled;
      return setDoc(doc(ctx.firestore(), 'users/alice'), u);
    });
    await assertSucceeds(setDoc(doc(db(), `completions/${id()}`),
      completionDoc('alice', today, serverTimestamp, { location: new GeoPoint(1, 2) })));
  });
});

describe('D-09 — location setting OFF', () => {
  beforeEach(async () => { await seedUser('alice', { locationEnabled: false }); });
  it('DENIES a completion with a location', async () => {
    await assertFails(setDoc(doc(db(), `completions/${id()}`),
      completionDoc('alice', today, serverTimestamp, { location: new GeoPoint(30.2, -97.7) })));
  });
  it('ALLOWS a completion without a location', async () => {
    await assertSucceeds(setDoc(doc(db(), `completions/${id()}`), completionDoc('alice', today, serverTimestamp)));
  });
  for (const [label, o] of [
    ['coordinates', { latitude: 30.2, longitude: -97.7 }],
    ['a place name', { locationName: 'Zilker Park' }],
    ['weather', { weatherCondition: 'Clear', weatherEmoji: '☀️' }],
  ]) {
    it(`DENIES a Journal entry with ${label}`, async () => {
      await seedCompletion('alice');
      await assertFails(setDoc(doc(db(), `users/alice/memories/${id()}`), memory('alice', today, o)));
    });
  }
  it('ALLOWS a Journal entry without location data', async () => {
    await seedCompletion('alice');
    await assertSucceeds(setDoc(doc(db(), `users/alice/memories/${id()}`), memory()));
  });
  it('DENIES the full batch if any write carries location data — nothing is saved', async () => {
    await assertFails(fullBatch(db(), { mem: { latitude: 1, longitude: 2 } }));
    if (await exists(`completions/${id()}`)) throw new Error('completion saved');
  });
  it('ALLOWS the full batch without location data', async () => {
    await assertSucceeds(fullBatch(db()));
  });
  it('does not affect other users (bob, setting on, may still save location)', async () => {
    await assertSucceeds(setDoc(doc(db('bob'), `completions/${id('bob')}`),
      completionDoc('bob', today, serverTimestamp, { location: new GeoPoint(1, 2) })));
  });
});
