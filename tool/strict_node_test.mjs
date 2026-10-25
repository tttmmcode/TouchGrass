// Runs `node --test <args…>` and fails if ANY test or suite failed.
//
// Why (Phase 7H): Node 22's test runner exits 0 and reports "# fail 0" when
// a describe() callback throws while its suite is being built (e.g. a
// fixture used before `before()` ran) — the whole suite silently never
// runs. This wrapper also treats every TAP "not ok" line as a failure.
//
//   node tool/strict_node_test.mjs [node --test options] <files/globs…>
import { spawn } from 'node:child_process';
import { pathToFileURL } from 'node:url';

/** True when a TAP line reports a failed test or suite (not a TODO). */
export function isFailureLine(line) {
  return /^\s*not ok \d+\b/.test(line) && !/#\s*TODO\b/i.test(line);
}

function main(args) {
  // A runner started from inside another test run inherits this variable
  // and then reports to that parent instead of exiting with its own result.
  const env = { ...process.env };
  delete env.NODE_TEST_CONTEXT;
  const child = spawn(process.execPath, ['--test', '--test-reporter=tap', ...args], {
    stdio: ['inherit', 'pipe', 'inherit'],
    env,
  });
  let failed = false;
  let rest = '';
  child.stdout.on('data', (chunk) => {
    process.stdout.write(chunk);
    const lines = (rest + chunk.toString('utf8')).split('\n');
    rest = lines.pop();
    if (lines.some(isFailureLine)) failed = true;
  });
  child.on('close', (code, signal) => {
    if (isFailureLine(rest)) failed = true;
    if (code !== 0) process.exit(code ?? 1);
    if (signal) process.exit(1);
    if (failed) {
      console.error('strict_node_test: a test or suite reported "not ok" although node --test exited 0.');
      process.exit(1);
    }
    process.exit(0);
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2));
}
