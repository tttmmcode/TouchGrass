// tool/rules_for_env.mjs: non-production rules differ from the committed
// production rules ONLY in the Storage host and bucket literals.
//   node --test "tool/test/*.test.mjs"
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { firestoreRulesFor, storageRulesFor, PROD_BUCKET, DEV_PROJECT } from '../rules_for_env.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const prod = fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8');
const storage = fs.readFileSync(path.join(root, 'storage.rules'), 'utf8');

/** Lines that differ between a and b (same line count expected). */
function changedLines(a, b) {
  const x = a.split('\n');
  const y = b.split('\n');
  assert.equal(x.length, y.length, 'line count changed');
  return x.map((l, i) => [l, y[i]]).filter(([l, m]) => l !== m);
}
const body = (generated) => generated.slice(generated.indexOf('\n') + 1);

describe('rules_for_env (Phase 8)', () => {
  test('development: only the profile-photo bucket changes', () => {
    const dev = firestoreRulesFor('development', prod);
    assert.match(dev, /^\/\/ GENERATED .* "development"/);
    const diff = changedLines(prod, body(dev));
    assert.equal(diff.length, 1);
    assert.match(diff[0][1], new RegExp(`${DEV_PROJECT}\\[\\.\\]firebasestorage\\[\\.\\]app/o/user_avatars`));
    assert.doesNotMatch(dev, /touchgrass-today/);
  });
  test('emulator: only the two Storage hosts and the bucket change', () => {
    const emu = firestoreRulesFor('emulator', prod);
    const diff = changedLines(prod, body(emu));
    assert.equal(diff.length, 3, diff.map((d) => d[1]).join('\n'));
    for (const [, line] of diff) {
      assert.match(line, /localhost\|127\[\.\]0\[\.\]0\[\.\]1\):9199|demo-touchgrass-dev\[\.\]appspot\[\.\]com/);
    }
    assert.ok(!emu.includes(PROD_BUCKET));
  });
  test('the committed production rules still pin production values', () => {
    assert.ok(prod.includes('touchgrass-today[.]firebasestorage[.]app/o/user_avatars'));
    assert.doesNotMatch(prod, /localhost|127\[\.\]0|9199|demo-/);
  });
  test('fails loudly when the expected pattern is missing', () => {
    assert.throws(() => firestoreRulesFor('development', prod.replace('user_avatars%2F', 'avatars%2F')), /expected 1/);
    assert.throws(() => firestoreRulesFor('staging', prod), /unknown environment/);
  });
  test('storage rules carry no environment-specific value', () => {
    assert.equal(body(storageRulesFor('emulator', storage)), storage);
    assert.throws(() => storageRulesFor('emulator', `${storage}// ${PROD_BUCKET}`), /environment-specific/);
  });
});
