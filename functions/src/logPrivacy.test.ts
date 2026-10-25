/**
 * Phase 8: Cloud Functions logs carry no user identifiers, object paths,
 * photo URLs or raw error messages (which can contain paths). Checks every
 * logger call in deployable and dormant function code.
 */
import {test} from "node:test";
import assert from "node:assert/strict";
import {readdirSync, readFileSync} from "node:fs";
import {join} from "node:path";

const SRC = join(__dirname, "..", "src");
// `.name` (an error's class) is allowed; identifiers and raw errors aren't.
const FORBIDDEN = /\b(uid|userId|completionId|storagePath|photoUrl|email|displayName|username)\b|String\(e\)|\$\{|,\s*e\s*\)/;

test("no logger call includes identifiers, paths or raw errors", () => {
  const offenders: string[] = [];
  for (const file of readdirSync(SRC)) {
    if (!file.endsWith(".ts") || file.includes(".test.")) continue;
    const text = readFileSync(join(SRC, file), "utf8");
    // Each logger call up to its closing parenthesis on the same statement.
    for (const m of text.matchAll(/logger\.(info|warn|error|debug|log)\(([\s\S]*?)\);/g)) {
      const args = m[2].replace(/"[^"]*"/g, '""');
      if (FORBIDDEN.test(args)) offenders.push(`${file}: ${m[0].replace(/\s+/g, " ").slice(0, 120)}`);
    }
  }
  assert.deepEqual(offenders, []);
});
