#!/usr/bin/env node
// Exports the LIVE Firestore and Storage security rules and Firestore
// indexes of a Firebase project, READ-ONLY, and compares them with the
// local files that a deploy would publish (Phase 7A).
//
//   node tool/export_live_rules.mjs --project touchgrass-today
//   node tool/export_live_rules.mjs --compare-only <snapshot dir>
//
// How it reads production (nothing else is called):
// - rules: the Firebase CLI's own MCP server (`firebase mcp`), tool
//   `get_security_rules`, which is annotated readOnlyHint and only issues
//   GET requests to the Firebase Rules API (releases list + ruleset get).
//   The tool is refused unless the server reports it as read-only.
// - indexes: `firebase firestore:indexes` (lists; never changes anything).
// It uses the CLI's existing login and never reads, prints or stores a
// credential. If the CLI is not logged in it stops; it never logs in.
//
// Output goes to ops-out/live-rules/<UTC stamp>/ (git-ignored, owner-only
// file mode; nothing under ops-out/ is referenced by firebase.json, so a
// snapshot can never be deployed by accident). Local rules are never
// modified. Exit: 0 = exported (and compared), 2 = refused/usage, 1 = error.

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const sha256 = (s) => crypto.createHash('sha256').update(s, 'utf8').digest('hex');
const normalize = (s) => s.replace(/\r\n/g, '\n').replace(/[ \t]+$/gm, '').replace(/\n+$/, '\n');

// ── Comparison (pure; unit-tested) ───────────────────────────────────────────

/** Line diff (LCS) as unified-style hunks with [context] lines. */
export function lineDiff(a, b, context = 3) {
  const x = normalize(a).split('\n');
  const y = normalize(b).split('\n');
  const n = x.length;
  const m = y.length;
  const lcs = Array.from({ length: n + 1 }, () => new Uint32Array(m + 1));
  for (let i = n - 1; i >= 0; i--) {
    for (let j = m - 1; j >= 0; j--) {
      lcs[i][j] = x[i] === y[j] ? lcs[i + 1][j + 1] + 1 : Math.max(lcs[i + 1][j], lcs[i][j + 1]);
    }
  }
  const ops = [];
  let i = 0;
  let j = 0;
  while (i < n || j < m) {
    if (i < n && j < m && x[i] === y[j]) { ops.push([' ', x[i], i, j]); i++; j++; }
    else if (j < m && (i >= n || lcs[i][j + 1] >= lcs[i + 1][j])) { ops.push(['+', y[j], i, j]); j++; }
    else { ops.push(['-', x[i], i, j]); i++; }
  }
  const out = [];
  let k = 0;
  while (k < ops.length) {
    if (ops[k][0] === ' ') { k++; continue; }
    let start = Math.max(0, k - context);
    let end = k;
    // Extend while changes are within 2*context of each other.
    for (let p = k; p < ops.length; p++) {
      if (ops[p][0] !== ' ') end = p;
      else if (p - end > 2 * context) break;
    }
    const stop = Math.min(ops.length, end + context + 1);
    out.push(`@@ live line ${ops[start][2] + 1}, local line ${ops[start][3] + 1} @@`);
    for (let p = start; p < stop; p++) out.push(`${ops[p][0]}${ops[p][1]}`);
    k = stop;
  }
  return out.join('\n');
}

const matches = (t) => new Set([...t.matchAll(/^\s*match\s+(\S+)\s*\{/gm)].map((m) => m[1]));
const functions = (t) => new Set([...t.matchAll(/^\s*function\s+(\w+)\s*\(/gm)].map((m) => m[1]));
const minus = (a, b) => [...a].filter((v) => !b.has(v)).sort();

/** Patterns that make a ruleset dangerous whatever the app does. */
export function riskyPatterns(rules) {
  const t = rules.replace(/\/\/.*$/gm, '');
  const found = [];
  if (/allow\s+[^;]*:\s*if\s+true\s*;/.test(t)) found.push('an `allow … : if true` grant (open to everyone)');
  if (/request\.time\s*<\s*timestamp\.date\(/.test(t)) found.push('a time-limited "test mode" grant (`request.time < timestamp.date(…)`)');
  if (/allow\s+(read|write)(\s*,\s*(read|write))?\s*:\s*if\s+request\.auth\s*!=\s*null\s*;/.test(t)) {
    found.push('an allow-any-signed-in-user grant (`if request.auth != null` alone)');
  }
  if (!/match\s+\/\{(document|allPaths)=\*\*\}\s*\{\s*allow\s+read\s*,\s*write\s*:\s*if\s+false\s*;/.test(t)) {
    found.push('no explicit catch-all deny (`match /{document=**}` / `/{allPaths=**}` … `if false`)');
  }
  if (!/rules_version\s*=\s*'2'/.test(t)) found.push("not rules_version '2' (recursive wildcards behave differently)");
  return found;
}

/** Structured comparison of one live ruleset with the local file. */
export function compareRuleset(name, live, local) {
  if (live === null) {
    return { name, identical: false, liveMissing: true, risksLive: [], risksLocal: riskyPatterns(local), diff: '' };
  }
  const identical = normalize(live) === normalize(local);
  return {
    name,
    identical,
    liveSha256: sha256(normalize(live)),
    localSha256: sha256(normalize(local)),
    matchesOnlyLive: minus(matches(live), matches(local)),
    matchesOnlyLocal: minus(matches(local), matches(live)),
    functionsOnlyLive: minus(functions(live), functions(local)),
    functionsOnlyLocal: minus(functions(local), functions(live)),
    risksLive: riskyPatterns(live),
    risksLocal: riskyPatterns(local),
    diff: identical ? '' : lineDiff(live, local),
  };
}

const indexKey = (ix) => `${ix.collectionGroup}|${ix.queryScope ?? 'COLLECTION'}|` +
  (ix.fields ?? []).filter((f) => f.fieldPath !== '__name__')
    .map((f) => `${f.fieldPath}:${f.order ?? f.arrayConfig ?? (f.vectorConfig ? JSON.stringify(f.vectorConfig) : '')}`)
    .join(',');

/** Composite indexes present only locally (a deploy adds them) or only
 * live (a deploy would offer to DELETE them). */
export function compareIndexes(live, local) {
  const l = new Map((live?.indexes ?? []).map((ix) => [indexKey(ix), ix]));
  const r = new Map((local?.indexes ?? []).map((ix) => [indexKey(ix), ix]));
  return {
    onlyLocal: [...r.keys()].filter((k) => !l.has(k)).sort(),
    onlyLive: [...l.keys()].filter((k) => !r.has(k)).sort(),
    fieldOverridesLive: (live?.fieldOverrides ?? []).length,
    fieldOverridesLocal: (local?.fieldOverrides ?? []).length,
  };
}

export function renderReport({ project, at, rules, indexes, firebaseJsonIndexes }) {
  const lines = [`# Live vs local rules — ${project}`, '', `Exported ${at} (read-only). **Do not deploy anything from this folder.**`, ''];
  for (const r of rules) {
    lines.push(`## ${r.name}`, '');
    if (r.liveMissing) { lines.push('No live ruleset was found (service not set up, or no release).', ''); continue; }
    lines.push(r.identical ? '**Identical** to the local file (ignoring line endings / trailing spaces).' :
      '**Differs** from the local file — a deploy would replace the live version with the local one.', '');
    lines.push(`- live sha256 \`${r.liveSha256.slice(0, 12)}…\`, local \`${r.localSha256.slice(0, 12)}…\``);
    if (r.matchesOnlyLive.length) lines.push(`- \`match\` blocks only LIVE (a deploy REMOVES access they grant): ${r.matchesOnlyLive.map((m) => `\`${m}\``).join(', ')}`);
    if (r.matchesOnlyLocal.length) lines.push(`- \`match\` blocks only LOCAL (new paths): ${r.matchesOnlyLocal.map((m) => `\`${m}\``).join(', ')}`);
    if (r.functionsOnlyLive.length) lines.push(`- functions only live: ${r.functionsOnlyLive.join(', ')}`);
    if (r.functionsOnlyLocal.length) lines.push(`- functions only local: ${r.functionsOnlyLocal.join(', ')}`);
    lines.push(`- risky patterns in LIVE: ${r.risksLive.length ? r.risksLive.join('; ') : 'none found'}`);
    lines.push(`- risky patterns in LOCAL: ${r.risksLocal.length ? r.risksLocal.join('; ') : 'none found'}`, '');
    if (!r.identical) lines.push('```diff', '--- live', '+++ local', r.diff, '```', '');
  }
  lines.push('## Firestore indexes', '');
  if (!indexes) lines.push('Live indexes were not exported.');
  else {
    lines.push(`- \`firebase.json\` references an indexes file: ${firebaseJsonIndexes ? 'yes' : '**no** (a deploy would never send firestore.indexes.json)'}`);
    lines.push(`- only in local file (deploy ADDS): ${indexes.onlyLocal.length ? indexes.onlyLocal.map((k) => `\`${k}\``).join(', ') : 'none'}`);
    lines.push(`- only live (deploy would offer to DELETE): ${indexes.onlyLive.length ? indexes.onlyLive.map((k) => `\`${k}\``).join(', ') : 'none'}`);
    lines.push(`- field overrides: live ${indexes.fieldOverridesLive}, local ${indexes.fieldOverridesLocal}`);
  }
  lines.push('');
  return lines.join('\n');
}

// ── Read-only retrieval ──────────────────────────────────────────────────────

const firebaseCmd = () => process.env.FIREBASE_BIN || 'firebase';

/**
 * Talks to `firebase mcp` over stdio (JSON-RPC 2.0, one message per line),
 * calls ONLY a tool named *get_security_rules that the server marks
 * read-only, and returns {firestore, storage} rule texts (null if none).
 */
export function fetchLiveRules({ cwd, cmd = firebaseCmd(), args = ['mcp'], timeoutMs = 120000 }) {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, { cwd, stdio: ['pipe', 'pipe', 'pipe'], shell: process.platform === 'win32' && !cmd.endsWith('.js') && !cmd.includes('node') });
    const pending = new Map();
    let buf = '';
    let stderr = '';
    let nextId = 1;
    const timer = setTimeout(() => finish(new Error('Timed out waiting for the Firebase MCP server')), timeoutMs);
    const finish = (err, value) => {
      clearTimeout(timer);
      child.stdin.end();
      child.kill();
      for (const p of pending.values()) p.reject(err ?? new Error('closed'));
      pending.clear();
      if (err) reject(err); else resolve(value);
    };
    child.stdout.on('data', (d) => {
      buf += d.toString('utf8');
      let nl;
      while ((nl = buf.indexOf('\n')) >= 0) {
        const line = buf.slice(0, nl).trim();
        buf = buf.slice(nl + 1);
        if (!line.startsWith('{')) continue;
        let msg;
        try { msg = JSON.parse(line); } catch { continue; }
        if (msg.id !== undefined && pending.has(msg.id)) {
          const p = pending.get(msg.id);
          pending.delete(msg.id);
          if (msg.error) p.reject(new Error(`MCP error: ${msg.error.message ?? 'unknown'}`));
          else p.resolve(msg.result);
        }
      }
    });
    child.stderr.on('data', (d) => { stderr = (stderr + d.toString('utf8')).slice(-4000); });
    child.on('error', (e) => finish(e));
    child.on('exit', (code) => { if (pending.size) finish(new Error(`Firebase MCP server exited (${code})`)); });
    const send = (method, params, notify = false) => {
      const msg = { jsonrpc: '2.0', method, ...(params ? { params } : {}) };
      if (notify) { child.stdin.write(JSON.stringify(msg) + '\n'); return Promise.resolve(); }
      const id = nextId++;
      child.stdin.write(JSON.stringify({ ...msg, id }) + '\n');
      return new Promise((res, rej) => pending.set(id, { resolve: res, reject: rej }));
    };
    (async () => {
      await send('initialize', {
        protocolVersion: '2025-06-18',
        capabilities: {},
        clientInfo: { name: 'touchgrass-export-live-rules', version: '1.0.0' },
      });
      await send('notifications/initialized', null, true);
      const { tools = [] } = await send('tools/list', {});
      const tool = tools.find((t) => /(^|_)get_security_rules$/.test(t.name));
      if (!tool) throw new Error('The Firebase MCP server offers no get_security_rules tool (is the CLI logged in and the project set?)');
      if (tool.annotations?.readOnlyHint !== true) throw new Error(`Refusing: ${tool.name} is not marked read-only`);
      const get = async (type) => {
        const r = await send('tools/call', { name: tool.name, arguments: { type } });
        const text = (r?.content ?? []).filter((c) => c.type === 'text').map((c) => c.text).join('');
        if (r?.isError) {
          if (/No active .* rules were found/i.test(text)) return null;
          throw new Error(`get_security_rules(${type}) failed: ${text.slice(0, 300)}`);
        }
        return text;
      };
      const firestore = await get('firestore');
      const storage = await get('storage');
      finish(null, { firestore, storage, toolName: tool.name });
    })().catch((e) => finish(new Error(`${e.message}${stderr ? `\n(stderr tail) ${stderr.split('\n').slice(-3).join(' ')}` : ''}`)));
  });
}

function run(cmd, args, cwd) {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, { cwd, shell: process.platform === 'win32' });
    let out = '';
    let err = '';
    child.stdout.on('data', (d) => { out += d; });
    child.stderr.on('data', (d) => { err += d; });
    child.on('error', reject);
    child.on('exit', (code) => (code === 0 ? resolve(out) : reject(new Error(`${cmd} ${args[0]} exited ${code}: ${err.slice(-300)}`))));
  });
}

function writePrivate(file, text) {
  fs.writeFileSync(file, text, { encoding: 'utf8', mode: 0o600 });
}

function readJson(p) {
  try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch { return null; }
}

export function compareSnapshot(dir, root = repoRoot) {
  const read = (p) => (fs.existsSync(p) ? fs.readFileSync(p, 'utf8') : null);
  const fj = readJson(path.join(root, 'firebase.json')) ?? {};
  const fsRulesPath = path.join(root, fj.firestore?.rules ?? 'firestore.rules');
  const stRulesPath = path.join(root, fj.storage?.rules ?? 'storage.rules');
  const meta = readJson(path.join(dir, 'meta.json')) ?? {};
  const rules = [
    compareRuleset('Firestore rules', read(path.join(dir, 'firestore.rules')), read(fsRulesPath) ?? ''),
    compareRuleset('Storage rules', read(path.join(dir, 'storage.rules')), read(stRulesPath) ?? ''),
  ];
  const liveIdx = readJson(path.join(dir, 'firestore.indexes.json'));
  const indexes = liveIdx ? compareIndexes(liveIdx, readJson(path.join(root, 'firestore.indexes.json'))) : null;
  return { project: meta.project ?? '?', at: meta.exportedAt ?? '?', rules, indexes, firebaseJsonIndexes: Boolean(fj.firestore?.indexes) };
}

async function main(argv) {
  const opt = (k) => { const i = argv.indexOf(k); return i >= 0 ? argv[i + 1] : undefined; };
  const compareOnly = opt('--compare-only');
  if (compareOnly) {
    const result = compareSnapshot(path.resolve(compareOnly));
    const report = renderReport(result);
    writePrivate(path.join(path.resolve(compareOnly), 'comparison.md'), report);
    summarize(result, path.resolve(compareOnly));
    return 0;
  }
  const project = opt('--project');
  const rc = readJson(path.join(repoRoot, '.firebaserc'));
  if (!project || !/^[a-z0-9-]{4,40}$/.test(project)) {
    console.error('Usage: node tool/export_live_rules.mjs --project <firebase project id>');
    return 2;
  }
  // The MCP server resolves the project from .firebaserc in the repo, so
  // only the default project can be read unambiguously.
  if (rc?.projects?.default !== project) {
    console.error(`Refusing: --project ${project} is not the .firebaserc default (${rc?.projects?.default ?? 'none'}).`);
    return 2;
  }
  const stamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\..*/, 'Z');
  const dir = path.join(repoRoot, opt('--out') ?? path.join('ops-out', 'live-rules'), `${project}-${stamp}`);
  if (!path.resolve(dir).startsWith(path.join(repoRoot, 'ops-out'))) {
    console.error('Refusing: snapshots must stay under ops-out/ (git-ignored, never deployed).');
    return 2;
  }
  const live = await fetchLiveRules({ cwd: repoRoot });
  let liveIndexes = null;
  try {
    const out = await run(firebaseCmd(), ['firestore:indexes', '--project', project], repoRoot);
    liveIndexes = JSON.parse(out.slice(out.indexOf('{')));
  } catch (e) {
    console.error(`Indexes not exported: ${e.message.split('\n')[0]}`);
  }
  fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
  writePrivate(path.join(dir, 'README.txt'),
    'Read-only snapshot of PRODUCTION rules for review. Never copy these files over the\n' +
    'repository rules and never deploy from this folder. Not source; git-ignored.\n');
  if (live.firestore !== null) writePrivate(path.join(dir, 'firestore.rules'), live.firestore);
  if (live.storage !== null) writePrivate(path.join(dir, 'storage.rules'), live.storage);
  if (liveIndexes) writePrivate(path.join(dir, 'firestore.indexes.json'), JSON.stringify(liveIndexes, null, 2) + '\n');
  writePrivate(path.join(dir, 'meta.json'), JSON.stringify({
    project, exportedAt: new Date().toISOString(), via: `firebase mcp ${live.toolName} (readOnlyHint) + firebase firestore:indexes`,
    firestoreFound: live.firestore !== null, storageFound: live.storage !== null, indexesFound: Boolean(liveIndexes),
  }, null, 2) + '\n');
  const result = compareSnapshot(dir);
  writePrivate(path.join(dir, 'comparison.md'), renderReport(result));
  summarize(result, dir);
  return 0;
}

function summarize(result, dir) {
  for (const r of result.rules) {
    console.log(`${r.name}: ${r.liveMissing ? 'no live ruleset' : r.identical ? 'IDENTICAL to local' : 'DIFFERS from local'}` +
      (r.risksLive?.length ? ` — live risks: ${r.risksLive.length}` : ''));
  }
  if (result.indexes) {
    console.log(`Indexes: ${result.indexes.onlyLocal.length} only local, ${result.indexes.onlyLive.length} only live; ` +
      `firebase.json references an indexes file: ${result.firebaseJsonIndexes ? 'yes' : 'no'}`);
  }
  console.log(`Snapshot and comparison: ${path.relative(repoRoot, dir)}`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).then((code) => process.exit(code), (e) => {
    console.error(`Failed: ${e.message}`);
    process.exit(1);
  });
}
