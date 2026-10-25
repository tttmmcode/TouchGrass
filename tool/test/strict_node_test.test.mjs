// Tests for tool/strict_node_test.mjs: a suite whose describe() throws must
// fail the run even though Node 22's own runner exits 0 for it.
//   node --test "tool/test/*.test.mjs"
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { isFailureLine } from '../strict_node_test.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const wrapper = path.join(here, '..', 'strict_node_test.mjs');

function fixtureDir(files) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'strict-node-test-'));
  for (const [name, body] of Object.entries(files)) fs.writeFileSync(path.join(dir, name), body);
  return dir;
}
const run = (dir, ...files) => spawnSync(process.execPath, [wrapper, ...files.map((f) => path.join(dir, f))],
  { encoding: 'utf8' });

const PASSING = "import { it } from 'node:test';\nit('fine', () => {});\n";
const BROKEN_SUITE = "import { describe, it } from 'node:test';\nlet env;\n" +
  "describe('broken', () => { env.x(); it('never runs', () => {}); });\n";
const FAILING = "import { it } from 'node:test';\nit('fails', () => { throw new Error('x'); });\n";

describe('strict_node_test', () => {
  test('passes when every test passes', () => {
    const dir = fixtureDir({ 'a.test.mjs': PASSING });
    assert.equal(run(dir, 'a.test.mjs').status, 0);
  });
  test('FAILS when a suite throws while being built (Node 22 alone exits 0)', () => {
    const dir = fixtureDir({ 'a.test.mjs': PASSING, 'b.test.mjs': BROKEN_SUITE });
    const r = run(dir, 'a.test.mjs', 'b.test.mjs');
    assert.equal(r.status, 1);
    assert.match(r.stdout, /not ok \d+ - broken/);
  });
  test('FAILS when an ordinary test fails', () => {
    const dir = fixtureDir({ 'a.test.mjs': FAILING });
    assert.notEqual(run(dir, 'a.test.mjs').status, 0);
  });
  test('recognises failure lines, nested or not, but not TODOs or passes', () => {
    assert.equal(isFailureLine('not ok 5 - creates after account deletion'), true);
    assert.equal(isFailureLine('    not ok 2 - DENIES x'), true);
    assert.equal(isFailureLine('ok 5 - fine'), false);
    assert.equal(isFailureLine('not ok 3 - later # TODO'), false);
    assert.equal(isFailureLine('# fail 0'), false);
  });
});
