// Phase 7C: release gate for photo privacy. Runs the SAME security
// properties against both Storage rulesets that can be deployed:
//   FINAL   — storage.rules (firebase.json; the coordinated release)
//   INTERIM — deploy/interim/storage.interim.rules (containment for the
//             live web app until that release)
// so neither can regress — e.g. the profile-photo listing hole that Phase
// 7B found in INTERIM (T33) and Phase 7C found in FINAL.
//
// Three layers:
//   1. Behaviour: each case is run on the emulator and must give the
//      expected ALLOW/DENY. Prints `PARITY|<ruleset>|<id>|<actual>|<expected>|<desc>`
//      (used for PHASE_7C_STORAGE_SECURITY_TEST_MATRIX.md).
//   2. Intentional differences: the only cases where FINAL and INTERIM may
//      differ, each with its reason. Any other difference fails.
//   3. Static grant inventory: every non-`false` grant in each file must be
//      in the expected table below, so a new or widened grant (another
//      `allow read`, a `{x=**}` grant) fails until it is reviewed here.
// Emulator only (demo- project).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, it, after } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import {
  ref, uploadBytes, getBytes, getDownloadURL, getMetadata, updateMetadata, deleteObject, listAll,
} from 'firebase/storage';
import { doc, setDoc, deleteDoc } from 'firebase/firestore';
import { PROJECT_ID, authed } from './helpers.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..', '..');
const FILES = {
  FINAL: path.join(root, 'storage.rules'),
  INTERIM: path.join(root, 'deploy', 'interim', 'storage.interim.rules'),
};
const RULESETS = Object.fromEntries(Object.entries(FILES).map(([k, f]) => [k, fs.readFileSync(f, 'utf8')]));
const FIRESTORE_RULES = fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8');
// Firestore runs too: FINAL checks that the uploader's profile exists
// (Phase 7F, a cross-service read of users/{uid}).
const envFor = (rules) => initializeTestEnvironment({
  projectId: PROJECT_ID, storage: { rules }, firestore: { rules: FIRESTORE_RULES },
});
/** Users with a profile document. Mallory has one too, so a denial of her
 * writes is about ownership, never a missing profile. */
const PROFILES = ['alice', 'bob', 'mallory'];

const MB = 1024 * 1024;
const DATED = 'completion_photos/alice/2026-01-01.jpg';
const LEGACY = 'completion_photos/alice/1760900000000.jpg';
const AVATAR = 'user_avatars/alice.png';
const jpeg = { contentType: 'image/jpeg' };
const png = { contentType: 'image/png' };
const bytes = (n) => new Uint8Array(n);

const seed = async (env, profiles = PROFILES) => {
  await env.clearStorage();
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    for (const uid of profiles) await setDoc(doc(ctx.firestore(), 'users', uid), { uid });
    const s = ctx.storage();
    for (const p of [DATED, LEGACY]) await uploadBytes(ref(s, p), bytes(4), jpeg);
    await uploadBytes(ref(s, 'completion_photos/bob/2026-01-01.jpg'), bytes(4), jpeg);
    await uploadBytes(ref(s, AVATAR), bytes(4), png);
    await uploadBytes(ref(s, 'user_avatars/bob.png'), bytes(4), png);
    await uploadBytes(ref(s, 'metadata_backup/completion_photos/alice/run1/2026-01-01.jpg'), bytes(4), jpeg);
  });
};

const st = (env, uid) => (uid ? authed(env, uid) : env.unauthenticatedContext()).storage();
const outcome = (p) => p.then(() => 'ALLOW', (e) => {
  if (String(e?.code ?? e).includes('unauthorized') || String(e?.code).includes('permission')) return 'DENY';
  throw e; // any other error is a test failure, not a denial
});
const up = (e, uid, p, n, meta) => uploadBytes(ref(st(e, uid), p), bytes(n), meta);
const today = 'completion_photos/alice/2026-10-19.jpg';

// [id, description, op, expected] — expected is the SAME for FINAL and
// INTERIM unless the id is listed in DIFFERENCES.
const CASES = [
  // ── Challenge photos: reads and listing ──────────────────────────────────
  ['P01', 'unauthenticated: read a challenge photo', (e) => getBytes(ref(st(e), DATED)), 'DENY'],
  ['P02', 'unauthenticated: list a user\'s photos', (e) => listAll(ref(st(e), 'completion_photos/alice')), 'DENY'],
  ['P03', 'non-owner: read another user\'s photo', (e) => getBytes(ref(st(e, 'mallory'), DATED)), 'DENY'],
  ['P04', 'non-owner: read a legacy-named photo', (e) => getBytes(ref(st(e, 'mallory'), LEGACY)), 'DENY'],
  ['P05', 'non-owner: get a download URL (token) for another user\'s photo', (e) => getDownloadURL(ref(st(e, 'mallory'), DATED)), 'DENY'],
  ['P06', 'non-owner: read another user\'s photo metadata', (e) => getMetadata(ref(st(e, 'mallory'), DATED)), 'DENY'],
  ['P07', 'non-owner: list another user\'s photos', (e) => listAll(ref(st(e, 'mallory'), 'completion_photos/alice')), 'DENY'],
  ['P08', 'signed-in: list the completion_photos root (all uids)', (e) => listAll(ref(st(e, 'mallory'), 'completion_photos')), 'DENY'],
  ['P09', 'signed-in: list the bucket root', (e) => listAll(ref(st(e, 'mallory'), '')), 'DENY'],
  ['P10', 'owner: read own photos (date and legacy names)', async (e) => { await getBytes(ref(st(e, 'alice'), DATED)); await getBytes(ref(st(e, 'alice'), LEGACY)); }, 'ALLOW'],
  ['P11', 'owner: own download URL and metadata', async (e) => { await getDownloadURL(ref(st(e, 'alice'), DATED)); await getMetadata(ref(st(e, 'alice'), DATED)); }, 'ALLOW'],
  ['P12', 'owner: list own folder', (e) => listAll(ref(st(e, 'alice'), 'completion_photos/alice')), 'ALLOW'],
  ['P13', 'owner (alice): list a look-alike uid folder (alice2)', (e) => listAll(ref(st(e, 'alice'), 'completion_photos/alice2')), 'DENY'],
  // ── Challenge photos: uploads ────────────────────────────────────────────
  ['P20', 'owner: upload {yyyy-MM-dd}.jpg image/jpeg', (e) => up(e, 'alice', today, 10, jpeg), 'ALLOW'],
  ['P21', 'owner: upload 10 MB − 1 byte (limit is < 10 MB)', (e) => up(e, 'alice', today, 10 * MB - 1, jpeg), 'ALLOW'],
  ['P22', 'owner: upload exactly 10 MB', (e) => up(e, 'alice', today, 10 * MB, jpeg), 'DENY'],
  ['P23', 'owner: upload 10 MB + 1 byte', (e) => up(e, 'alice', today, 10 * MB + 1, jpeg), 'DENY'],
  ['P24', 'owner: upload image/png, image/webp, image/heic, image/heif', async (e) => {
    for (const t of ['image/png', 'image/webp', 'image/heic', 'image/heif']) await up(e, 'alice', today, 10, { contentType: t });
  }, 'ALLOW'],
  ['P25', 'owner: upload image/svg+xml', (e) => up(e, 'alice', today, 10, { contentType: 'image/svg+xml' }), 'DENY'],
  ['P26', 'owner: upload image/gif', (e) => up(e, 'alice', today, 10, { contentType: 'image/gif' }), 'DENY'],
  ['P27', 'owner: upload text/html', (e) => up(e, 'alice', today, 10, { contentType: 'text/html' }), 'DENY'],
  ['P28', 'owner: upload application/octet-stream', (e) => up(e, 'alice', today, 10, { contentType: 'application/octet-stream' }), 'DENY'],
  ['P29', 'owner: name 2026-10-19.jpeg', (e) => up(e, 'alice', 'completion_photos/alice/2026-10-19.jpeg', 10, jpeg), 'DENY'],
  ['P30', 'owner: name 2026-10-19.JPG', (e) => up(e, 'alice', 'completion_photos/alice/2026-10-19.JPG', 10, jpeg), 'DENY'],
  ['P31', 'owner: name 2026-10-19.jpg.html', (e) => up(e, 'alice', 'completion_photos/alice/2026-10-19.jpg.html', 10, jpeg), 'DENY'],
  ['P32', 'owner: name x2026-10-19.jpg (prefix)', (e) => up(e, 'alice', 'completion_photos/alice/x2026-10-19.jpg', 10, jpeg), 'DENY'],
  ['P33', 'owner: name 123456789.jpg (9 digits)', (e) => up(e, 'alice', 'completion_photos/alice/123456789.jpg', 10, jpeg), 'DENY'],
  ['P34', 'owner: name of 17 digits', (e) => up(e, 'alice', 'completion_photos/alice/12345678901234567.jpg', 10, jpeg), 'DENY'],
  ['P35', 'owner: nested path in own folder', (e) => up(e, 'alice', 'completion_photos/alice/sub/2026-10-19.jpg', 10, jpeg), 'DENY'],
  ['P36', 'owner: upload directly at completion_photos/{uid} (no file name)', (e) => up(e, 'alice', 'completion_photos/alice', 10, jpeg), 'DENY'],
  ['P37', 'owner: legacy {timestamp}.jpg upload (13 digits)', (e) => up(e, 'alice', 'completion_photos/alice/1760999999999.jpg', 10, jpeg), 'DENY'],
  ['P38', 'non-owner: upload into another user\'s folder', (e) => up(e, 'mallory', today, 10, jpeg), 'DENY'],
  ['P39', 'non-owner: overwrite another user\'s photo', (e) => up(e, 'mallory', DATED, 10, jpeg), 'DENY'],
  ['P40', 'non-owner: change another user\'s photo metadata', (e) => updateMetadata(ref(st(e, 'mallory'), DATED), { contentType: 'text/html' }), 'DENY'],
  ['P41', 'non-owner: delete another user\'s photo', (e) => deleteObject(ref(st(e, 'mallory'), DATED)), 'DENY'],
  ['P42', 'unauthenticated: upload into a user folder', (e) => up(e, undefined, today, 10, jpeg), 'DENY'],
  ['P43', 'owner: delete own photo', (e) => deleteObject(ref(st(e, 'alice'), DATED)), 'DENY'],
  // ── Profile photos ───────────────────────────────────────────────────────
  ['P50', 'signed-in: list all avatars (user_avatars/)', (e) => listAll(ref(st(e, 'mallory'), 'user_avatars')), 'DENY'],
  ['P51', 'signed-in: list "another user\'s avatar directory" (user_avatars/alice)', (e) => listAll(ref(st(e, 'mallory'), 'user_avatars/alice')), 'DENY'],
  ['P52', 'owner: list own avatar prefix', (e) => listAll(ref(st(e, 'alice'), 'user_avatars/alice')), 'DENY'],
  ['P53', 'signed-in: GET one avatar (leaderboard)', (e) => getBytes(ref(st(e, 'mallory'), AVATAR)), 'ALLOW'],
  ['P54', 'signed-in: avatar download URL + metadata (single object)', async (e) => { await getDownloadURL(ref(st(e, 'mallory'), AVATAR)); await getMetadata(ref(st(e, 'mallory'), AVATAR)); }, 'ALLOW'],
  ['P55', 'unauthenticated: read an avatar', (e) => getBytes(ref(st(e), AVATAR)), 'DENY'],
  ['P56', 'owner: upload own {uid}.png image/png', (e) => up(e, 'alice', AVATAR, 10, png), 'ALLOW'],
  ['P57', 'owner: avatar 5 MB − 1 byte', (e) => up(e, 'alice', AVATAR, 5 * MB - 1, png), 'ALLOW'],
  ['P58', 'owner: avatar exactly 5 MB', (e) => up(e, 'alice', AVATAR, 5 * MB, png), 'DENY'],
  ['P59', 'owner: avatar 5 MB + 1 byte', (e) => up(e, 'alice', AVATAR, 5 * MB + 1, png), 'DENY'],
  ['P60', 'owner: avatar declared image/svg+xml', (e) => up(e, 'alice', AVATAR, 10, { contentType: 'image/svg+xml' }), 'DENY'],
  ['P61', 'owner: avatar declared text/html', (e) => up(e, 'alice', AVATAR, 10, { contentType: 'text/html' }), 'DENY'],
  ['P62', 'owner: avatar named {uid}.jpg', (e) => up(e, 'alice', 'user_avatars/alice.jpg', 10, jpeg), 'DENY'],
  ['P63', 'owner: avatar nested under own uid', (e) => up(e, 'alice', 'user_avatars/alice/x.png', 10, png), 'DENY'],
  ['P64', 'owner: avatar named {uid}.png.html', (e) => up(e, 'alice', 'user_avatars/alice.png.html', 10, png), 'DENY'],
  ['P65', 'non-owner: upload into another user\'s avatar path', (e) => up(e, 'mallory', 'user_avatars/alice.png', 10, png), 'DENY'],
  ['P66', 'non-owner: create an avatar for a uid that has none', (e) => up(e, 'mallory', 'user_avatars/carol.png', 10, png), 'DENY'],
  ['P67', 'non-owner: change another user\'s avatar metadata', (e) => updateMetadata(ref(st(e, 'mallory'), AVATAR), { contentType: 'text/html' }), 'DENY'],
  ['P68', 'non-owner: delete another user\'s avatar', (e) => deleteObject(ref(st(e, 'mallory'), AVATAR)), 'DENY'],
  ['P69', 'owner: delete own avatar', (e) => deleteObject(ref(st(e, 'alice'), AVATAR)), 'DENY'],
  ['P70', 'unauthenticated: upload an avatar', (e) => up(e, undefined, 'user_avatars/alice.png', 10, png), 'DENY'],
  // ── Late uploads after account deletion (Phase 7F) ───────────────────────
  // dave is signed in (an unexpired ID token) but has no profile document —
  // what a second device sees once deleteAccount has removed users/{uid}.
  ['P71', 'signed in without a profile (deleted account): upload own challenge photo', (e) => up(e, 'dave', 'completion_photos/dave/2026-10-19.jpg', 10, jpeg), 'DENY'],
  ['P72', 'signed in without a profile (deleted account): upload own avatar', (e) => up(e, 'dave', 'user_avatars/dave.png', 10, png), 'DENY'],
  ['P73', 'signed in without a profile: other upload rules still apply (.jpeg name)', (e) => up(e, 'dave', 'completion_photos/dave/2026-10-19.jpeg', 10, jpeg), 'DENY'],
  // ── Everything else ──────────────────────────────────────────────────────
  ['P80', 'owner: read own metadata backup (server-only)', (e) => getBytes(ref(st(e, 'alice'), 'metadata_backup/completion_photos/alice/run1/2026-01-01.jpg')), 'DENY'],
  ['P81', 'owner: list own metadata backups', (e) => listAll(ref(st(e, 'alice'), 'metadata_backup/completion_photos/alice')), 'DENY'],
  ['P82', 'signed-in: list metadata_backup root', (e) => listAll(ref(st(e, 'mallory'), 'metadata_backup')), 'DENY'],
  ['P83', 'signed-in: write an unrelated path', (e) => up(e, 'alice', 'public/alice.jpg', 10, jpeg), 'DENY'],
  ['P84', 'signed-in: write a metadata backup', (e) => up(e, 'alice', 'metadata_backup/completion_photos/alice/x/2026-01-01.jpg', 10, jpeg), 'DENY'],
  // Documented limitation, asserted so it stays visible: rules see the
  // DECLARED content type, never the bytes.
  ['P90', 'owner: non-image bytes declared image/jpeg (limitation)', (e) => uploadBytes(ref(st(e, 'alice'), today), new TextEncoder().encode('<html>x</html>'), jpeg), 'ALLOW'],
];

// The ONLY permitted FINAL/INTERIM differences: id → {FINAL, INTERIM, why}.
// Each is owner-only (never reaches another user's data) and ends when
// INTERIM is replaced by FINAL in the coordinated release.
const DIFFERENCES = {
  P37: {
    FINAL: 'DENY', INTERIM: 'ALLOW',
    why: 'The live web app names new photos {Date.now()}.jpg; the new app uses {yyyy-MM-dd}.jpg (one object per completion, D-13).',
  },
  P43: {
    FINAL: 'DENY', INTERIM: 'ALLOW',
    why: 'INTERIM keeps the live rules\' owner delete. FINAL leaves deletion to the server-side deleteAccount (D-04). Owner-only either way.',
  },  P71: {
    FINAL: 'DENY', INTERIM: 'ALLOW',
    why: 'FINAL requires users/{uid} (Phase 7F): closes the late-upload window after deleteAccount. INTERIM serves the live client, which never calls deleteAccount.',
  },
  P72: {
    FINAL: 'DENY', INTERIM: 'ALLOW',
    why: 'Same profile requirement for avatars (Phase 7F). Either way an owner can only write their own avatar path.',
  },
};

function expectedFor(ruleset, id, shared) {
  return DIFFERENCES[id]?.[ruleset] ?? shared;
}

for (const [name, rules] of Object.entries(RULESETS)) {
  describe(`${name} Storage rules — release privacy properties`, () => {
    let env;
    after(async () => { await env?.cleanup(); });
    for (const [id, desc, op, shared] of CASES) {
      const expected = expectedFor(name, id, shared);
      it(`${id} ${desc} → ${expected}`, async () => {
        env ??= await envFor(rules);
        await seed(env);
        const actual = await outcome(op(env));
        console.log(`PARITY|${name}|${id}|${actual}|${expected}|${desc}`);
        assert.equal(actual, expected);
      });
    }
  });
}

describe('FINAL and INTERIM differ only where documented', () => {
  it('every DIFFERENCES entry names a real case, both outcomes, and a reason', () => {
    const ids = new Set(CASES.map(([id]) => id));
    for (const [id, d] of Object.entries(DIFFERENCES)) {
      assert.ok(ids.has(id), `${id} is not a case`);
      assert.notEqual(d.FINAL, d.INTERIM, `${id} is not actually a difference`);
      assert.ok(d.why.length > 20, `${id} needs a reason`);
    }
  });
});

// ── Token URLs: what rules can NOT do (documented limitation) ────────────
describe('download-token URLs bypass the rules (both rulesets)', () => {
  for (const [name, rules] of Object.entries(RULESETS)) {
    it(`${name}: an owner's token URL opens for an unauthenticated client; a wrong token does not`, async () => {
      const env = await envFor(rules);
      try {
        await seed(env);
        const url = await getDownloadURL(ref(st(env, 'alice'), DATED));
        // A non-owner can't obtain the URL through the SDK…
        assert.equal(await outcome(getDownloadURL(ref(st(env, 'mallory'), DATED))), 'DENY');
        // …but anyone who HAS it can download, without signing in: rules
        // are not evaluated for token URLs. Only rotating the token (or
        // deleting the object) revokes it.
        const res = await fetch(url);
        assert.equal(res.status, 200);
        const forged = url.replace(/token=[^&]+/, 'token=00000000-0000-0000-0000-000000000000');
        assert.notEqual((await fetch(forged)).status, 200);
        console.log(`PARITY|${name}|P91|ALLOW|ALLOW|token URL opens without auth (limitation)`);
      } finally {
        await env.cleanup();
      }
    });
  }
});

describe('FINAL: the new app\'s complete Storage sequence', () => {
  it('upload dated photo → URL → upload avatar → URL → list own; no listing elsewhere', async () => {
    const env = await envFor(RULESETS.FINAL);
    try {
      await seed(env, [...PROFILES, 'carol']); // carol signed in, so her profile exists
      const s = st(env, 'carol');
      const photo = ref(s, 'completion_photos/carol/2026-10-19.jpg');
      await uploadBytes(photo, bytes(64), jpeg);
      assert.match(await getDownloadURL(photo), /token=/);
      await uploadBytes(photo, bytes(65), jpeg); // retry overwrites the same object (D-13)
      const avatar = ref(s, 'user_avatars/carol.png');
      await uploadBytes(avatar, bytes(64), png);
      assert.match(await getDownloadURL(avatar), /token=/);
      assert.equal((await listAll(ref(s, 'completion_photos/carol'))).items.length, 1);
      assert.equal(await outcome(listAll(ref(s, 'user_avatars'))), 'DENY');
    } finally {
      await env.cleanup();
    }
  });
});

describe('FINAL: a deleted account\'s still-valid session can\'t upload or come back (Phase 7G)', () => {
  it('upload OK → deleteAccount (marker, profile deleted) → upload DENIED → profile re-creation DENIED → upload DENIED', async () => {
    const env = await envFor(RULESETS.FINAL);
    try {
      await seed(env, [...PROFILES, 'erin']);
      const s = st(env, 'erin');
      const photo = ref(s, 'completion_photos/erin/2026-10-21.jpg');
      assert.equal(await outcome(uploadBytes(photo, bytes(16), jpeg)), 'ALLOW', 'normal upload while the profile exists');
      // What deleteAccount does (Admin SDK, rules bypassed): marker first,
      // then the profile.
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), 'deletedAccounts/erin'), { markedAt: new Date(), expiresAt: new Date(Date.now() + 7200000) });
        await deleteDoc(doc(ctx.firestore(), 'users/erin'));
      });
      // The other device still has erin's unexpired ID token.
      assert.equal(await outcome(uploadBytes(photo, bytes(17), jpeg)), 'DENY', 'challenge photo after deletion');
      assert.equal(await outcome(uploadBytes(ref(s, 'user_avatars/erin.png'), bytes(8), png)), 'DENY', 'avatar after deletion');
      const recreate = setDoc(doc(authed(env, 'erin').firestore(), 'users/erin'), { uid: 'erin' });
      assert.equal(await outcome(recreate), 'DENY', 'profile re-creation after deletion');
      assert.equal(await outcome(uploadBytes(photo, bytes(18), jpeg)), 'DENY', 'still no upload');
      // Nobody else is affected.
      assert.equal(await outcome(uploadBytes(ref(st(env, 'alice'), 'completion_photos/alice/2026-10-21.jpg'), bytes(16), jpeg)), 'ALLOW');
    } finally {
      await env.cleanup();
    }
  });
});

// ── Static grant inventory ───────────────────────────────────────────────

/** Every `allow` statement as {path, ops, cond}, with `match` paths joined
 * and the `/b/{bucket}/o` prefix removed. String literals and comments are
 * skipped so braces inside regexes don't confuse the nesting. */
export function grants(source) {
  const out = [];
  const stack = [];
  let buf = '';
  for (let i = 0; i < source.length; i++) {
    const c = source[i];
    if (c === '/' && source[i + 1] === '/') {
      while (i < source.length && source[i] !== '\n') i++;
      continue;
    }
    if (c === '\'' || c === '"') {
      let j = i + 1;
      while (j < source.length && source[j] !== c) j += source[j] === '\\' ? 2 : 1;
      buf += source.slice(i, j + 1);
      i = j;
      continue;
    }
    if (c === '{' && buf.endsWith('/')) {
      // A path wildcard such as /{userId} or /{allPaths=**}, not a block.
      const j = source.indexOf('}', i);
      buf += source.slice(i, j + 1);
      i = j;
    } else if (c === '{' && /^\s*match\s/.test(buf)) {
      stack.push(buf.trim().replace(/^match\s+/, ''));
      buf = '';
    } else if (c === '{' && /^\s*(service|function)\s/.test(buf)) {
      stack.push(null);
      buf = '';
    } else if (c === '}' && buf.trim() === '') {
      stack.pop();
      buf = '';
    } else if (c === ';') {
      const s = buf.trim().replace(/\s+/g, ' ');
      const m = /^allow ([a-z, ]+?)\s*:\s*if (.+)$/.exec(s);
      if (m) {
        const full = stack.filter(Boolean).join('').replace(/^\/b\/\{bucket\}\/o/, '');
        out.push({ path: full, ops: m[1].split(',').map((o) => o.trim()), cond: m[2].trim() });
      } else if (/^allow\b/.test(s)) {
        throw new Error(`Unparsed allow statement: ${s}`);
      }
      buf = '';
    } else {
      buf += c;
    }
  }
  assert.equal(stack.length, 0, 'unbalanced braces');
  return out;
}

/** "path op" for every grant whose condition isn't literally `false`. */
const granted = (source) => grants(source)
  .filter((g) => g.cond !== 'false')
  .flatMap((g) => g.ops.map((op) => `${g.path} ${op}`))
  .sort();

const OWNER = 'request.auth.uid == userId';
const EXPECTED_GRANTS = {
  FINAL: [
    '/completion_photos/{userId} list',
    '/completion_photos/{userId}/{fileName} create',
    '/completion_photos/{userId}/{fileName} read',
    '/completion_photos/{userId}/{fileName} update',
    '/user_avatars/{fileName} create',
    '/user_avatars/{fileName} get',
    '/user_avatars/{fileName} update',
  ],
  INTERIM: [
    '/completion_photos/{userId} list',
    '/completion_photos/{userId}/{fileName} create',
    '/completion_photos/{userId}/{fileName} delete',
    '/completion_photos/{userId}/{fileName} read',
    '/completion_photos/{userId}/{fileName} update',
    '/user_avatars/{fileName} create',
    '/user_avatars/{fileName} get',
    '/user_avatars/{fileName} update',
  ],
};

describe('static grant inventory (fails on any new or widened grant)', () => {
  it('the parser sees nested blocks, strings with braces and multi-line conditions', () => {
    const g = grants(`service firebase.storage { match /b/{bucket}/o {
      function f() { return 'a{1}' == 'b'; }
      match /x/{id} { allow read: if f()
        && id.matches('[0-9]{4}'); allow write: if false; }
      match /{all=**} { allow read, write: if false; } } }`);
    assert.deepEqual(g.map((x) => `${x.path}|${x.ops.join('+')}|${x.cond === 'false'}`),
      ['/x/{id}|read|false', '/x/{id}|write|true', '/{all=**}|read+write|true']);
  });

  for (const name of Object.keys(RULESETS)) {
    describe(name, () => {
      const src = RULESETS[name];
      it('grants exactly the reviewed (path, operation) set', () => {
        assert.deepEqual(granted(src), [...EXPECTED_GRANTS[name]].sort());
      });
      it('no listing anywhere except a user\'s own completion folder', () => {
        for (const g of grants(src).filter((x) => x.cond !== 'false')) {
          if (g.ops.some((o) => o === 'read' || o === 'list')) {
            assert.match(g.path, /^\/completion_photos\/\{userId\}(\/\{fileName\})?$/, `${g.path} ${g.ops} can list`);
            assert.ok(g.cond.includes(OWNER), `${g.path} ${g.ops} is not owner-only`);
          }
        }
      });
      it('a recursive wildcard ({x=**}) never grants anything', () => {
        for (const g of grants(src).filter((x) => /=\*\*\}/.test(x.path))) {
          assert.equal(g.cond, 'false', `${g.path} grants ${g.ops}`);
        }
      });
      it('every completion-photo grant is owner-only; every write is signed-in', () => {
        for (const g of grants(src).filter((x) => x.cond !== 'false')) {
          if (g.path.startsWith('/completion_photos/')) assert.ok(g.cond.includes(OWNER), `${g.path} ${g.ops}`);
          if (g.ops.some((o) => ['write', 'create', 'update', 'delete'].includes(o))) {
            assert.ok(g.cond.startsWith('isSignedIn()'), `${g.path} ${g.ops}`);
          }
        }
      });
      it('uploads are bounded: image types and a size limit on every create/update', () => {
        for (const g of grants(src).filter((x) => x.cond !== 'false' && x.ops.some((o) => o === 'create' || o === 'update'))) {
          assert.ok(g.cond.includes('isAllowedImage()'), `${g.path}: no content-type check`);
          assert.match(g.cond, /request\.resource\.size < \d+ \* 1024 \* 1024/, `${g.path}: no size limit`);
        }
        assert.doesNotMatch(src.replace(/\/\/.*$/gm, ''), /image\/svg|image\/\*|image\/gif/, 'SVG/GIF/wildcard type allowed');
      });
      if (name === 'FINAL') {
        it('every create/update requires the uploader\'s profile, checked last (Phase 7F late-upload window)', () => {
          const writes = grants(src).filter((x) => x.cond !== 'false' && x.ops.some((o) => o === 'create' || o === 'update'));
          assert.ok(writes.length >= 2);
          for (const g of writes) assert.match(g.cond, /&& hasProfile\(\)$/, `${g.path}: profile check missing or not last`);
          assert.match(src, /firestore\.exists\(\/databases\/\(default\)\/documents\/users\/\$\(request\.auth\.uid\)\)/);
        });
      }
    });
  }

  it('the release config deploys FINAL; the interim config deploys only INTERIM', () => {
    const main = JSON.parse(fs.readFileSync(path.join(root, 'firebase.json'), 'utf8'));
    assert.equal(main.storage.rules, 'storage.rules');
    const interim = JSON.parse(fs.readFileSync(path.join(root, 'deploy', 'interim', 'firebase.interim-storage.json'), 'utf8'));
    assert.deepEqual(interim, { storage: { rules: 'storage.interim.rules' } });
  });

  it('project and bucket agree everywhere (Phase 7D): .firebaserc, firebase_options.dart, firestore.rules', () => {
    const rc = JSON.parse(fs.readFileSync(path.join(root, '.firebaserc'), 'utf8'));
    assert.equal(rc.projects.default, 'touchgrass-today');
    const options = fs.readFileSync(path.join(root, 'lib', 'firebase_options.dart'), 'utf8');
    const buckets = new Set([...options.matchAll(/storageBucket: '([^']+)'/g)].map((m) => m[1]));
    const projects = new Set([...options.matchAll(/projectId: '([^']+)'/g)].map((m) => m[1]));
    assert.deepEqual([...projects], ['touchgrass-today']);
    assert.deepEqual([...buckets], ['touchgrass-today.firebasestorage.app']);
    // The profile-photo URL rule hard-codes the bucket (regex-escaped).
    const fsRules = fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8');
    assert.match(fsRules, /touchgrass-today\[\.\]firebasestorage\[\.\]app/);
    assert.doesNotMatch(fsRules + options, /gen-lang-client-/, 'the look-alike project must never be referenced');
  });
});
