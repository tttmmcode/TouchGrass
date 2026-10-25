// Phase 7H: ordinary development and test commands can never reach the
// production Firebase project, and no test script can pass while a suite
// silently failed to run.
//   node --test "tool/test/*.test.mjs"
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const scripts = (pkg) => JSON.parse(fs.readFileSync(path.join(root, pkg, 'package.json'), 'utf8')).scripts;
const PACKAGES = ['functions', 'firestore-tests'];

describe('dev and test scripts never target production (Phase 7H)', () => {
  for (const pkg of PACKAGES) {
    test(`${pkg}: every emulator or shell script names a demo- project`, () => {
      for (const [name, cmd] of Object.entries(scripts(pkg))) {
        if (!/emulators:(start|exec)|functions:shell/.test(cmd)) continue;
        assert.match(cmd, /--project demo-[a-z0-9-]+/, `${pkg} script "${name}" must pass --project demo-…`);
      }
    });
    test(`${pkg}: every node test run goes through the strict wrapper`, () => {
      for (const [name, cmd] of Object.entries(scripts(pkg))) {
        assert.doesNotMatch(cmd, /node --test\b/, `${pkg} script "${name}" runs node --test directly`);
      }
    });
  }
  test('functions: serve starts the data emulators too (a lone Functions emulator uses the real database)', () => {
    const serve = scripts('functions').serve;
    for (const emulator of ['functions', 'firestore', 'storage', 'auth']) {
      assert.match(serve, new RegExp(`--only [a-z,]*\\b${emulator}\\b`), emulator);
    }
  });
  test('the only deploy script stays an explicit, functions-only command', () => {
    for (const pkg of PACKAGES) {
      for (const [name, cmd] of Object.entries(scripts(pkg))) {
        if (!/firebase deploy/.test(cmd)) continue;
        assert.equal(name, 'deploy', `${pkg} script "${name}" deploys`);
        assert.match(cmd, /--only functions\b/);
      }
    }
  });
});
