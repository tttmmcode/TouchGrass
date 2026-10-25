// Phase 7A gap coverage: operator-only data (cleanup lease, metadata
// backups), read-only catalogues, and the list QUERIES the app actually
// runs (rules are evaluated against the query's constraints).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, it, before, after, beforeEach } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import {
  doc, getDoc, setDoc, collection, query, where, orderBy, limit, getDocs, Timestamp,
} from 'firebase/firestore';
import { ref, getBytes, listAll, uploadBytes } from 'firebase/storage';
import { PROJECT_ID, authed, storedUser } from './helpers.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');

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
    await setDoc(doc(db, 'leaderboard_public/alice'), { displayName: 'alice', xp: 100, weeklyXp: 100, currentLeague: 'seedling' });
    await setDoc(doc(db, 'completions/alice_2026-01-01'), { userId: 'alice', completedAt: Timestamp.now() });
    await setDoc(doc(db, 'users/alice/memories/alice_2026-01-01'), { userId: 'alice', completionDate: Timestamp.now() });
    await setDoc(doc(db, '_ops/orphanPhotoCleanup_lease'), { holder: 'job', expiresAt: Timestamp.now() });
    await setDoc(doc(db, 'challenges/c1'), { title: 'x' });
    await setDoc(doc(db, 'achievements/first_touch'), { title: 'x' });
    const st = ctx.storage();
    await uploadBytes(ref(st, 'metadata_backup/completion_photos/alice/run1/2026-01-01.jpg'), new Uint8Array([1]), { contentType: 'image/jpeg' });
    await uploadBytes(ref(st, 'metadata_backup/run1/completion_photos/alice/2026-01-01.jpg'), new Uint8Array([1]), { contentType: 'image/jpeg' });
  });
});

const db = (uid) => authed(env, uid).firestore();
const anon = () => env.unauthenticatedContext().firestore();

describe('operator-only data is never client-accessible', () => {
  it('DENIES reading or writing the cleanup lease (_ops/…), signed in or not', async () => {
    await assertFails(getDoc(doc(db('alice'), '_ops/orphanPhotoCleanup_lease')));
    await assertFails(setDoc(doc(db('alice'), '_ops/orphanPhotoCleanup_lease'), { holder: 'me' }));
    await assertFails(getDoc(doc(anon(), '_ops/orphanPhotoCleanup_lease')));
  });
  it('DENIES the photo owner reading or listing metadata backups (both layouts)', async () => {
    const st = authed(env, 'alice').storage();
    await assertFails(getBytes(ref(st, 'metadata_backup/completion_photos/alice/run1/2026-01-01.jpg')));
    await assertFails(getBytes(ref(st, 'metadata_backup/run1/completion_photos/alice/2026-01-01.jpg')));
    await assertFails(listAll(ref(st, 'metadata_backup/completion_photos/alice')));
  });
  it('DENIES writing into metadata_backup/', async () => {
    await assertFails(uploadBytes(ref(authed(env, 'alice').storage(), 'metadata_backup/completion_photos/alice/x/2026-01-02.jpg'),
      new Uint8Array([1]), { contentType: 'image/jpeg' }));
  });
});

describe('read-only catalogues', () => {
  it('ALLOWS signed-in reads; DENIES unauthenticated reads', async () => {
    await assertSucceeds(getDoc(doc(db('alice'), 'challenges/c1')));
    await assertSucceeds(getDoc(doc(db('alice'), 'achievements/first_touch')));
    await assertFails(getDoc(doc(anon(), 'challenges/c1')));
    await assertFails(getDoc(doc(anon(), 'achievements/first_touch')));
  });
  it('DENIES client writes', async () => {
    await assertFails(setDoc(doc(db('alice'), 'challenges/c2'), { title: 'x' }));
    await assertFails(setDoc(doc(db('alice'), 'achievements/new'), { title: 'x' }));
  });
});

describe('list queries the app runs', () => {
  it('ALLOWS the owner\'s completions query (userId == me, newest first) — the composite-index query', async () => {
    await assertSucceeds(getDocs(query(collection(db('alice'), 'completions'),
      where('userId', '==', 'alice'), orderBy('completedAt', 'desc'), limit(1))));
  });
  it('DENIES querying another user\'s completions, or all completions', async () => {
    await assertFails(getDocs(query(collection(db('mallory'), 'completions'), where('userId', '==', 'alice'))));
    await assertFails(getDocs(collection(db('alice'), 'completions')));
  });
  it('ALLOWS a signed-in league query on the leaderboard mirror; DENIES unauthenticated', async () => {
    await assertSucceeds(getDocs(query(collection(db('mallory'), 'leaderboard_public'), where('currentLeague', '==', 'seedling'))));
    await assertFails(getDocs(query(collection(anon(), 'leaderboard_public'), where('currentLeague', '==', 'seedling'))));
  });
  it('DENIES listing private profiles or feedback', async () => {
    await assertFails(getDocs(collection(db('alice'), 'users')));
    await assertFails(getDocs(collection(db('alice'), 'feedback')));
  });
  it('ALLOWS listing your own Journal; DENIES another user\'s', async () => {
    await assertSucceeds(getDocs(query(collection(db('alice'), 'users/alice/memories'), orderBy('completionDate', 'desc'))));
    await assertFails(getDocs(collection(db('mallory'), 'users/alice/memories')));
  });
});
