// Phase 7B: before/after security matrix for the photo-privacy containment.
// Every case runs against
//   LIVE    — fixtures/live-storage-2026-10-19.rules, byte-identical to the
//             ruleset exported read-only from touchgrass-today (sha256
//             c550222392960371d52680406c5b18657b20a530de5f7ce84f1d18c04729579d)
//   INTERIM — deploy/interim/storage.interim.rules (the file to deploy)
// and asserts the expected outcome for each. Prints one
// `MATRIX|<ruleset>|<id>|<actual>|<expected>` line per case (used for
// PHASE_7B_STORAGE_TEST_MATRIX.md). Emulator only (demo- project).
//
// The live web app's Storage calls (from its public main.dart.js, 2026-10-19):
//   completion: completion_photos/{uid}/{Date.now()}.jpg, image/jpeg, <10 MB, then getDownloadURL
//   avatar:     user_avatars/{uid}.png, image/png, <5 MB, then getDownloadURL; delete (not-found tolerated)
//   deletion:   listAll(completion_photos/{uid}) then delete each item
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, it, after } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import {
  ref, uploadBytes, getBytes, getDownloadURL, getMetadata, updateMetadata, deleteObject, listAll,
} from 'firebase/storage';
import { PROJECT_ID, authed } from './helpers.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..', '..');
const RULESETS = {
  LIVE: fs.readFileSync(path.join(here, 'fixtures', 'live-storage-2026-10-19.rules'), 'utf8'),
  INTERIM: fs.readFileSync(path.join(root, 'deploy', 'interim', 'storage.interim.rules'), 'utf8'),
};

const A = 'alice';
const TS = 'completion_photos/alice/1760900000000.jpg';
const DATED = 'completion_photos/alice/2026-01-01.jpg';
const jpeg = { contentType: 'image/jpeg' };
const png = { contentType: 'image/png' };
const bytes = (n) => new Uint8Array(n);

const seed = async (env) => {
  await env.clearStorage();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const st = ctx.storage();
    for (const p of [TS, DATED]) await uploadBytes(ref(st, p), bytes(4), jpeg);
    await uploadBytes(ref(st, 'user_avatars/alice.png'), bytes(4), png);
    await uploadBytes(ref(st, 'metadata_backup/completion_photos/alice/run1/2026-01-01.jpg'), bytes(4), jpeg);
    await uploadBytes(ref(st, 'misc/alice.jpg'), bytes(4), jpeg);
  });
};

const st = (env, uid) => (uid ? authed(env, uid) : env.unauthenticatedContext()).storage();
const outcome = (p) => p.then(() => 'ALLOW', (e) => {
  if (String(e?.code ?? e).includes('unauthorized') || String(e?.code).includes('permission')) return 'DENY';
  throw e; // any other error is a test failure, not a denial
});

// [id, description, (env) => Promise, expected LIVE, expected INTERIM]
const CASES = [
  ['T01', 'unauthenticated: read a challenge photo', (e) => getBytes(ref(st(e), DATED)), 'DENY', 'DENY'],
  ['T02', 'unauthenticated: list a user\'s photos', (e) => listAll(ref(st(e), 'completion_photos/alice')), 'DENY', 'DENY'],
  ['T03', 'non-owner: read another user\'s photo', (e) => getBytes(ref(st(e, 'mallory'), TS)), 'ALLOW', 'DENY'],
  ['T04', 'non-owner: get a download URL (token) for another user\'s photo', (e) => getDownloadURL(ref(st(e, 'mallory'), DATED)), 'ALLOW', 'DENY'],
  ['T05', 'non-owner: read another user\'s photo metadata', (e) => getMetadata(ref(st(e, 'mallory'), DATED)), 'ALLOW', 'DENY'],
  ['T06', 'non-owner: list another user\'s photos', (e) => listAll(ref(st(e, 'mallory'), 'completion_photos/alice')), 'ALLOW', 'DENY'],
  ['T07', 'signed-in: list ALL users\' folders (completion_photos root)', (e) => listAll(ref(st(e, 'mallory'), 'completion_photos')), 'ALLOW', 'DENY'],
  ['T08', 'signed-in: list the bucket root', (e) => listAll(ref(st(e, 'mallory'), '')), 'DENY', 'DENY'],
  ['T09', 'owner: read own photos (both name styles)', async (e) => { await getBytes(ref(st(e, A), TS)); await getBytes(ref(st(e, A), DATED)); }, 'ALLOW', 'ALLOW'],
  ['T10', 'owner: get own download URL (live app after upload)', (e) => getDownloadURL(ref(st(e, A), TS)), 'ALLOW', 'ALLOW'],
  ['T11', 'owner: list own folder (live app account deletion)', (e) => listAll(ref(st(e, A), 'completion_photos/alice')), 'ALLOW', 'ALLOW'],
  ['T12', 'owner: upload {timestamp}.jpg image/jpeg (live app)', (e) => uploadBytes(ref(st(e, A), 'completion_photos/alice/1760999999999.jpg'), bytes(10), jpeg), 'ALLOW', 'ALLOW'],
  ['T13', 'owner: upload {yyyy-MM-dd}.jpg (new app)', (e) => uploadBytes(ref(st(e, A), 'completion_photos/alice/2026-10-19.jpg'), bytes(10), jpeg), 'ALLOW', 'ALLOW'],
  ['T14', 'owner: upload text/html into own folder', (e) => uploadBytes(ref(st(e, A), 'completion_photos/alice/2026-10-19.jpg'), bytes(10), { contentType: 'text/html' }), 'ALLOW', 'DENY'],
  ['T15', 'owner: upload SVG (can carry script)', (e) => uploadBytes(ref(st(e, A), 'completion_photos/alice/2026-10-19.jpg'), new TextEncoder().encode('<svg/>'), { contentType: 'image/svg+xml' }), 'ALLOW', 'DENY'],
  ['T16', 'owner: upload 10 MB (limit is < 10 MB)', (e) => uploadBytes(ref(st(e, A), 'completion_photos/alice/2026-10-19.jpg'), bytes(10 * 1024 * 1024), jpeg), 'ALLOW', 'DENY'],
  ['T17', 'owner: upload just under 10 MB', (e) => uploadBytes(ref(st(e, A), 'completion_photos/alice/2026-10-19.jpg'), bytes(10 * 1024 * 1024 - 1), jpeg), 'ALLOW', 'ALLOW'],
  ['T18', 'owner: upload to a nested path in own folder', (e) => uploadBytes(ref(st(e, A), 'completion_photos/alice/sub/2026-10-19.jpg'), bytes(10), jpeg), 'ALLOW', 'DENY'],
  ['T19', 'owner: upload an arbitrary name (page.html as image/jpeg)', (e) => uploadBytes(ref(st(e, A), 'completion_photos/alice/page.html'), bytes(10), jpeg), 'ALLOW', 'DENY'],
  ['T20', 'non-owner: upload a new file into another user\'s folder', (e) => uploadBytes(ref(st(e, 'mallory'), 'completion_photos/alice/2026-10-19.jpg'), bytes(10), jpeg), 'DENY', 'DENY'],
  ['T21', 'non-owner: overwrite another user\'s existing photo', (e) => uploadBytes(ref(st(e, 'mallory'), DATED), bytes(10), jpeg), 'DENY', 'DENY'],
  ['T22', 'non-owner: delete another user\'s photo', (e) => deleteObject(ref(st(e, 'mallory'), DATED)), 'DENY', 'DENY'],
  ['T23', 'non-owner: change another user\'s photo metadata', (e) => updateMetadata(ref(st(e, 'mallory'), DATED), { contentType: 'text/html' }), 'DENY', 'DENY'],
  ['T24', 'unauthenticated: upload into a user folder', (e) => uploadBytes(ref(st(e), 'completion_photos/alice/2026-10-19.jpg'), bytes(10), jpeg), 'DENY', 'DENY'],
  ['T25', 'owner: delete own photo (live app account deletion)', (e) => deleteObject(ref(st(e, A), DATED)), 'ALLOW', 'ALLOW'],
  ['T26', 'owner: upload avatar user_avatars/{uid}.png image/png (live app)', (e) => uploadBytes(ref(st(e, 'bob'), 'user_avatars/bob.png'), bytes(10), png), 'DENY', 'ALLOW'],
  ['T27', 'signed-in: read another user\'s avatar (leaderboard)', (e) => getBytes(ref(st(e, 'mallory'), 'user_avatars/alice.png')), 'DENY', 'ALLOW'],
  ['T28', 'unauthenticated: read an avatar', (e) => getBytes(ref(st(e), 'user_avatars/alice.png')), 'DENY', 'DENY'],
  ['T29', 'non-owner: overwrite another user\'s avatar', (e) => uploadBytes(ref(st(e, 'mallory'), 'user_avatars/alice.png'), bytes(10), png), 'DENY', 'DENY'],
  ['T30', 'owner: avatar of 5 MB (limit is < 5 MB)', (e) => uploadBytes(ref(st(e, 'bob'), 'user_avatars/bob.png'), bytes(5 * 1024 * 1024), png), 'DENY', 'DENY'],
  ['T31', 'owner: avatar with a non-image type', (e) => uploadBytes(ref(st(e, 'bob'), 'user_avatars/bob.png'), bytes(10), { contentType: 'text/html' }), 'DENY', 'DENY'],
  ['T32', 'owner: delete own avatar (no client delete either way)', (e) => deleteObject(ref(st(e, A), 'user_avatars/alice.png')), 'DENY', 'DENY'],
  // Phase 7B fix: INTERIM originally used `allow read` (includes list) and
  // ALLOWED this; it now grants `get` only.
  ['T33', 'signed-in: list all avatars (user_avatars/)', (e) => listAll(ref(st(e, 'mallory'), 'user_avatars')), 'DENY', 'DENY'],
  ['T38', 'owner: get own avatar download URL (live app after upload)', (e) => getDownloadURL(ref(st(e, A), 'user_avatars/alice.png')), 'DENY', 'ALLOW'],
  ['T34', 'owner: read own metadata backup (server-only)', (e) => getBytes(ref(st(e, A), 'metadata_backup/completion_photos/alice/run1/2026-01-01.jpg')), 'DENY', 'DENY'],
  ['T35', 'signed-in: read an unrelated path', (e) => getBytes(ref(st(e, A), 'misc/alice.jpg')), 'DENY', 'DENY'],
  ['T36', 'signed-in: write an unrelated path', (e) => uploadBytes(ref(st(e, A), 'public/alice.jpg'), bytes(10), jpeg), 'DENY', 'DENY'],
  // Limitation, asserted so it stays visible: rules see the DECLARED type,
  // not the bytes.
  ['T37', 'owner: non-image bytes declared as image/jpeg (rules can\'t inspect bytes)', (e) => uploadBytes(ref(st(e, A), 'completion_photos/alice/2026-10-19.jpg'), new TextEncoder().encode('<html>x</html>'), jpeg), 'ALLOW', 'ALLOW'],
];

for (const [name, rules] of Object.entries(RULESETS)) {
  describe(`${name} Storage rules`, () => {
    let env;
    after(async () => { await env?.cleanup(); });
    for (const [id, desc, op, expLive, expInterim] of CASES) {
      const expected = name === 'LIVE' ? expLive : expInterim;
      it(`${id} ${desc} → ${expected}`, async () => {
        env ??= await initializeTestEnvironment({ projectId: PROJECT_ID, storage: { rules } });
        await seed(env);
        const actual = await outcome(op(env));
        console.log(`MATRIX|${name}|${id}|${actual}|${expected}|${desc}`);
        assert.equal(actual, expected);
      });
    }
  });
}

describe('INTERIM: the live web app\'s complete Storage sequence', () => {
  it('upload completion → URL → upload avatar → URL → list own → delete own', async () => {
    const env = await initializeTestEnvironment({ projectId: PROJECT_ID, storage: { rules: RULESETS.INTERIM } });
    try {
      await seed(env);
      const s = st(env, 'carol');
      const photo = ref(s, `completion_photos/carol/${Date.now()}.jpg`);
      await uploadBytes(photo, bytes(64), jpeg);
      assert.match(await getDownloadURL(photo), /token=/);
      const avatar = ref(s, 'user_avatars/carol.png');
      await uploadBytes(avatar, bytes(64), png);
      assert.match(await getDownloadURL(avatar), /token=/);
      const listing = await listAll(ref(s, 'completion_photos/carol'));
      assert.equal(listing.items.length, 1);
      await Promise.all(listing.items.map((i) => deleteObject(i)));
      assert.equal((await listAll(ref(s, 'completion_photos/carol'))).items.length, 0);
    } finally {
      await env.cleanup();
    }
  });
});
