// Tests for tool/export_live_rules.mjs — offline: a fake MCP server stands
// in for `firebase mcp`, so nothing here contacts Firebase.
//   node --test "tool/test/*.test.mjs"
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  lineDiff, riskyPatterns, compareRuleset, compareIndexes, renderReport, fetchLiveRules, compareSnapshot,
} from '../export_live_rules.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const fake = path.join(here, 'fixtures', 'fake_mcp.mjs');
const repoRoot = path.resolve(here, '..', '..');

const SAFE = `rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{uid} { allow read: if request.auth.uid == uid; }
    match /{document=**} { allow read, write: if false; }
  }
}
`;

describe('riskyPatterns', () => {
  test('a locked-down ruleset has none', () => assert.deepEqual(riskyPatterns(SAFE), []));
  test('flags test-mode, open, any-signed-in and missing catch-all', () => {
    const r = riskyPatterns(`rules_version = '2';
service cloud.firestore { match /databases/{database}/documents {
  match /{document=**} { allow read, write: if request.time < timestamp.date(2026, 1, 1); }
  match /a/{x} { allow read: if true; }
  match /b/{x} { allow read, write: if request.auth != null; }
} }`);
    assert.equal(r.length, 4);
    assert.match(r.join('|'), /test mode/);
    assert.match(r.join('|'), /if true/);
    assert.match(r.join('|'), /signed-in/);
    assert.match(r.join('|'), /catch-all/);
  });
  test('commented-out grants are ignored', () => {
    assert.deepEqual(riskyPatterns(SAFE.replace('match /users', '// allow read: if true;\n    match /users')), []);
  });
});

describe('compareRuleset / lineDiff', () => {
  test('identical modulo CRLF and trailing spaces', () => {
    const r = compareRuleset('Firestore', SAFE.replace(/\n/g, '\r\n'), SAFE.replace('{ allow read', '{ allow read  '.trimEnd()));
    assert.equal(r.identical, true);
    assert.equal(r.diff, '');
  });
  test('reports added/removed match blocks and functions, and a diff', () => {
    const local = SAFE.replace('    match /{document=**}', '    function isOwner(u) { return true; }\n    match /feedback/{id} { allow create: if false; }\n    match /{document=**}');
    const live = SAFE.replace('    match /users/{uid} { allow read: if request.auth.uid == uid; }\n', '    match /legacy/{x} { allow read: if true; }\n');
    const r = compareRuleset('Firestore', live, local);
    assert.equal(r.identical, false);
    assert.deepEqual(r.matchesOnlyLive, ['/legacy/{x}']);
    assert.deepEqual(r.matchesOnlyLocal, ['/feedback/{id}', '/users/{uid}']);
    assert.deepEqual(r.functionsOnlyLocal, ['isOwner']);
    assert.match(r.diff, /^-    match \/legacy/m);
    assert.match(r.diff, /^\+    match \/feedback/m);
    assert.ok(r.risksLive.some((x) => x.includes('if true')));
  });
  test('lineDiff hunks carry context and line numbers', () => {
    const a = Array.from({ length: 30 }, (_, i) => `l${i}`).join('\n');
    const b = a.replace('l15', 'L15');
    const d = lineDiff(a, b);
    assert.match(d, /^@@ live line 13, local line 13 @@/);
    assert.match(d, /^-l15$/m);
    assert.match(d, /^\+L15$/m);
    assert.ok(!d.includes('l5\n'));
  });
  test('missing live ruleset is reported, not treated as identical', () => {
    const r = compareRuleset('Storage', null, SAFE);
    assert.equal(r.liveMissing, true);
    assert.equal(r.identical, false);
  });
});

describe('compareIndexes', () => {
  const ix = (g, ...f) => ({ collectionGroup: g, queryScope: 'COLLECTION', fields: f.map(([p, o]) => ({ fieldPath: p, order: o })) });
  test('local-only indexes would be added; live-only would be offered for deletion', () => {
    const r = compareIndexes(
      { indexes: [ix('old', ['a', 'ASCENDING'], ['b', 'DESCENDING'])], fieldOverrides: [] },
      { indexes: [ix('completions', ['userId', 'ASCENDING'], ['completedAt', 'DESCENDING'])], fieldOverrides: [] });
    assert.deepEqual(r.onlyLocal, ['completions|COLLECTION|userId:ASCENDING,completedAt:DESCENDING']);
    assert.deepEqual(r.onlyLive, ['old|COLLECTION|a:ASCENDING,b:DESCENDING']);
  });
  test('implicit __name__ fields do not make equal indexes differ', () => {
    const live = { indexes: [{ ...ix('c', ['u', 'ASCENDING']), fields: [{ fieldPath: 'u', order: 'ASCENDING' }, { fieldPath: '__name__', order: 'ASCENDING' }] }] };
    assert.deepEqual(compareIndexes(live, { indexes: [ix('c', ['u', 'ASCENDING'])] }).onlyLocal, []);
  });
  test('the repo index file versus an empty live project', () => {
    const local = JSON.parse(fs.readFileSync(path.join(repoRoot, 'firestore.indexes.json'), 'utf8'));
    const r = compareIndexes({ indexes: [], fieldOverrides: [] }, local);
    assert.equal(r.onlyLocal.length, local.indexes.length);
  });
});

describe('fetchLiveRules (fake MCP server)', () => {
  const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), 'tg-rules-'));
  const withEnv = async (env, fn) => {
    const saved = { ...process.env };
    Object.assign(process.env, env);
    try { return await fn(); } finally { process.env = saved; }
  };
  test('calls only the read-only rules tool and returns both rulesets', async () => {
    const logFile = path.join(tmp(), 'calls.log');
    const r = await withEnv({ FAKE_LOG: logFile }, () =>
      fetchLiveRules({ cwd: repoRoot, cmd: process.execPath, args: [fake], timeoutMs: 15000 }));
    assert.match(r.firestore, /live firestore/);
    assert.match(r.storage, /live storage/);
    const calls = fs.readFileSync(logFile, 'utf8').trim().split('\n');
    assert.deepEqual(calls, [
      'initialize', 'notifications/initialized', 'tools/list',
      'tools/call firebase_get_security_rules(firestore)', 'tools/call firebase_get_security_rules(storage)',
    ]);
  });
  test('refuses a rules tool that is not marked read-only', async () => {
    await withEnv({ FAKE_RO: '0' }, () => assert.rejects(
      fetchLiveRules({ cwd: repoRoot, cmd: process.execPath, args: [fake], timeoutMs: 15000 }), /not marked read-only/));
  });
  test('a project without Storage rules yields null, not an error', async () => {
    const r = await withEnv({ FAKE_NO_STORAGE: '1' }, () =>
      fetchLiveRules({ cwd: repoRoot, cmd: process.execPath, args: [fake], timeoutMs: 15000 }));
    assert.equal(r.storage, null);
  });
});

describe('compareSnapshot + renderReport', () => {
  test('renders a review report that never suggests deploying the snapshot', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tg-snap-'));
    fs.writeFileSync(path.join(dir, 'firestore.rules'), SAFE);
    fs.writeFileSync(path.join(dir, 'firestore.indexes.json'), '{"indexes":[],"fieldOverrides":[]}');
    fs.writeFileSync(path.join(dir, 'meta.json'), '{"project":"demo-x","exportedAt":"t"}');
    const result = compareSnapshot(dir);
    const md = renderReport(result);
    assert.match(md, /Do not deploy anything from this folder/);
    assert.match(md, /## Firestore rules\n\n\*\*Differs\*\*/);
    assert.match(md, /No live ruleset was found/); // storage absent in this snapshot
    assert.match(md, /only in local file \(deploy ADDS\): `completions/);
  });
});
