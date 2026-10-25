// "Remove saved locations" (audit D-09, Phase 5): the owner may DELETE the
// optional location fields from their own completions and Journal entries
// — and nothing else. No value can be set, changed or added this way, no
// other field can ride along, and nobody else's data can be touched.
import { describe, it, before, after, beforeEach } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
  doc, setDoc, getDoc, updateDoc, deleteDoc, deleteField, writeBatch,
  serverTimestamp, Timestamp, GeoPoint,
} from 'firebase/firestore';
import {
  firestoreEnv, authed, storedUser, dateKey, completionDoc, photoUrl,
} from './helpers.mjs';

let env;
before(async () => { env = await firestoreEnv(); });
after(async () => { await env.cleanup(); });

const day = dateKey(-30); // an old adventure: outside the ±1-day create window
const cid = (uid = 'alice') => `${uid}_${day}`;
const db = (uid = 'alice') => authed(env, uid).firestore();
const cRef = (d = db(), uid = 'alice') => doc(d, `completions/${cid(uid)}`);
const mRef = (d = db(), uid = 'alice') => doc(d, `users/${uid}/memories/${cid(uid)}`);

const memoryWithLocation = (uid) => ({
  userId: uid, challengeId: day, challengeDay: 3, challengeTitle: 'Find a leaf',
  challengeCategory: 'nature', photoUrl: photoUrl(uid, `${day}.jpg`), xpEarned: 50,
  verificationMethod: 'auto_approved', completionDate: Timestamp.now(),
  createdAt: Timestamp.now(), caption: 'Sunny walk',
  latitude: 51.5, longitude: -0.12, locationName: 'Hyde Park',
  weatherCondition: 'Clear', weatherEmoji: '☀️',
});

const locationKeys = { latitude: deleteField(), longitude: deleteField(),
  locationName: deleteField(), weatherCondition: deleteField(), weatherEmoji: deleteField() };

async function seed(uid, { withLocation = true } = {}) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const f = ctx.firestore();
    await setDoc(doc(f, `users/${uid}`), storedUser(uid));
    await setDoc(doc(f, `completions/${cid(uid)}`), completionDoc(uid, day, () => Timestamp.now(),
      withLocation ? { location: new GeoPoint(51.5, -0.12), caption: 'Sunny walk' } : {}));
    const m = memoryWithLocation(uid);
    if (!withLocation) {
      for (const k of Object.keys(locationKeys)) delete m[k];
    }
    await setDoc(doc(f, `users/${uid}/memories/${cid(uid)}`), m);
  });
}

async function read(path) {
  let data;
  await env.withSecurityRulesDisabled(async (ctx) => {
    data = (await getDoc(doc(ctx.firestore(), path))).data();
  });
  return data;
}

beforeEach(async () => {
  await env.clearFirestore();
  await seed('alice');
  await seed('bob');
});

describe('completions — removing the saved location', () => {
  it('ALLOWS the owner to delete `location`; every other field is unchanged', async () => {
    const before = await read(`completions/${cid()}`);
    await assertSucceeds(updateDoc(cRef(), { location: deleteField() }));
    const after = await read(`completions/${cid()}`);
    const { location, ...rest } = before;
    if (location === undefined) throw new Error('fixture had no location');
    if ('location' in after) throw new Error('location still present');
    if (JSON.stringify(Object.keys(after).sort()) !== JSON.stringify(Object.keys(rest).sort())) {
      throw new Error('other fields changed');
    }
    if (after.xpAwarded !== rest.xpAwarded || after.photoUrl !== rest.photoUrl
        || after.caption !== rest.caption || !after.completedAt.isEqual(rest.completedAt)) {
      throw new Error('a non-location field changed');
    }
  });
  it('DENIES another user removing it', async () => {
    await assertFails(updateDoc(cRef(db('bob')), { location: deleteField() }));
  });
  it('DENIES an unauthenticated caller', async () => {
    await assertFails(updateDoc(cRef(env.unauthenticatedContext().firestore()), { location: deleteField() }));
  });
  it('DENIES changing the location to a new value', async () => {
    await assertFails(updateDoc(cRef(), { location: new GeoPoint(1, 1) }));
  });
  it('DENIES adding a location to a completion that has none', async () => {
    await env.clearFirestore();
    await seed('alice', { withLocation: false });
    await assertFails(updateDoc(cRef(), { location: new GeoPoint(1, 1) }));
  });
  it('DENIES a no-op "removal" on a completion without a location', async () => {
    await env.clearFirestore();
    await seed('alice', { withLocation: false });
    await assertFails(updateDoc(cRef(), { location: deleteField() }));
  });
  for (const [label, extra] of [
    ['raising xpAwarded', { xpAwarded: 100 }],
    ['swapping the photo', { photoUrl: photoUrl('alice', 'other.jpg') }],
    ['deleting the caption', { caption: deleteField() }],
    ['rewriting completedAt', { completedAt: Timestamp.fromDate(new Date('2020-01-01')) }],
    ['changing the owner', { userId: 'bob' }],
  ]) {
    it(`DENIES removing the location while ${label}`, async () => {
      await assertFails(updateDoc(cRef(), { location: deleteField(), ...extra }));
    });
  }
  it('still DENIES deleting the completion', async () => {
    await assertFails(deleteDoc(cRef()));
  });
  it('DENIES using the removal to re-award XP for an existing completion', async () => {
    const d = db();
    const b = writeBatch(d);
    b.update(cRef(d), { location: deleteField() });
    b.update(doc(d, 'users/alice'), {
      xp: 150, weeklyXp: 150, level: 2, streak: 2, longestStreak: 2, totalCompletions: 2,
      lastCompletionId: cid(), lastActiveDate: serverTimestamp(), lastCompletionDate: serverTimestamp(),
    });
    await assertFails(b.commit());
    const after = await read(`completions/${cid()}`);
    if (!('location' in after)) throw new Error('denied batch must write nothing');
  });
});

describe('Journal entries — removing saved location fields', () => {
  it('ALLOWS the owner to delete all location fields; caption, photo and XP stay', async () => {
    await assertSucceeds(updateDoc(mRef(), locationKeys));
    const after = await read(`users/alice/memories/${cid()}`);
    for (const k of Object.keys(locationKeys)) {
      if (k in after) throw new Error(`${k} still present`);
    }
    if (after.caption !== 'Sunny walk' || after.xpEarned !== 50
        || after.photoUrl !== photoUrl('alice', `${day}.jpg`)) {
      throw new Error('a non-location field changed');
    }
  });
  it('DENIES another user removing them', async () => {
    await assertFails(updateDoc(mRef(db('bob'), 'alice'), locationKeys));
  });
  it('DENIES an unauthenticated caller', async () => {
    await assertFails(updateDoc(mRef(env.unauthenticatedContext().firestore()), locationKeys));
  });
  it('DENIES leaving some location fields behind (all-or-nothing)', async () => {
    await assertFails(updateDoc(mRef(), { latitude: deleteField() }));
  });
  it('DENIES rewriting a place name or weather', async () => {
    await assertFails(updateDoc(mRef(), { locationName: 'Somewhere else' }));
    await assertFails(updateDoc(mRef(), { ...locationKeys, weatherEmoji: '🌧️' }));
  });
  it('DENIES adding location fields to an entry that has none', async () => {
    await env.clearFirestore();
    await seed('alice', { withLocation: false });
    await assertFails(updateDoc(mRef(), { latitude: 1, longitude: 1 }));
  });
  for (const [label, extra] of [
    ['inflating xpEarned', { xpEarned: 5000 }],
    ['swapping the photo', { photoUrl: photoUrl('alice', 'other.jpg') }],
    ['editing the caption', { caption: 'edited', captionUpdatedAt: serverTimestamp() }],
    ['changing the owner', { userId: 'bob' }],
  ]) {
    it(`DENIES removing locations while ${label}`, async () => {
      await assertFails(updateDoc(mRef(), { ...locationKeys, ...extra }));
    });
  }
  it('still ALLOWS editing the caption on its own', async () => {
    await assertSucceeds(updateDoc(mRef(), { caption: 'Lovely', captionUpdatedAt: serverTimestamp() }));
  });
});

describe('the user profile is untouched by the removal', () => {
  it('a removal batch over completion + entry leaves XP and streak exactly as they were', async () => {
    const before = await read('users/alice');
    const d = db();
    const b = writeBatch(d);
    b.update(cRef(d), { location: deleteField() });
    b.update(mRef(d), locationKeys);
    await assertSucceeds(b.commit());
    const after = await read('users/alice');
    for (const k of ['xp', 'weeklyXp', 'level', 'streak', 'longestStreak', 'totalCompletions']) {
      if (after[k] !== before[k]) throw new Error(`${k} changed`);
    }
  });
});
