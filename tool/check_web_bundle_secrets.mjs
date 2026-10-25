#!/usr/bin/env node
// Fails (exit 1) if a built web bundle contains anything that looks like a
// private credential. Run after every `flutter build web`, before deploying:
//
//   node tool/check_web_bundle_secrets.mjs [buildDir=build/web] [secretsFile=secrets.json]
//
// Checks:
//   1. Every string value in the local secrets file (e.g. secrets.json) —
//      none may appear anywhere in the bundle.
//   2. Gemini/Google AI-style keys (`AQ.` prefix) — never public.
//   3. Google API keys (`AIza…`) other than the public client keys already
//      committed in lib/firebase_options.dart, web/index.html and
//      web/firebase-messaging-sw.js (Firebase web config / Maps keys are
//      public by design and must be restricted in Google Cloud instead).
//   4. Private key material / service-account JSON markers.
//
// Never prints a matched value — only its location and last 4 characters.
// Keep the secrets file to real secrets only: a non-secret define that the
// app legitimately compiles in (e.g. ENVIRONMENT=production) would be
// reported as a finding.

import fs from 'node:fs';
import path from 'node:path';

const repoRoot = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1')), '..');
const buildDir = path.resolve(process.argv[2] ?? path.join(repoRoot, 'build', 'web'));
const secretsFile = path.resolve(process.argv[3] ?? path.join(repoRoot, 'secrets.json'));

if (!fs.existsSync(buildDir)) {
  console.error(`Build directory not found: ${buildDir}`);
  process.exit(2);
}

const tail = (v) => `…${String(v).slice(-4)}`;

// 1. Values from the local secrets file (if present).
const secretValues = [];
if (fs.existsSync(secretsFile)) {
  const parsed = JSON.parse(fs.readFileSync(secretsFile, 'utf8'));
  for (const [k, v] of Object.entries(parsed)) {
    if (typeof v === 'string' && v.length >= 8) secretValues.push([k, v]);
  }
}

// 3. Public Google API keys already committed to the repo (allowed).
const publicKeys = new Set();
for (const rel of ['lib/firebase_options.dart', 'lib/firebase_options_dev.dart', 'web/index.html', 'web/firebase-messaging-sw.js']) {
  const f = path.join(repoRoot, rel);
  if (!fs.existsSync(f)) continue;
  for (const m of fs.readFileSync(f, 'utf8').matchAll(/AIza[0-9A-Za-z_-]{35}/g)) publicKeys.add(m[0]);
}

const textExt = new Set(['.js', '.mjs', '.json', '.html', '.css', '.map', '.txt', '.xml', '.webmanifest']);
function* walk(dir) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) yield* walk(p);
    else if (textExt.has(path.extname(e.name).toLowerCase())) yield p;
  }
}

const findings = [];
let scanned = 0;
for (const file of walk(buildDir)) {
  scanned++;
  const text = fs.readFileSync(file, 'utf8');
  const rel = path.relative(buildDir, file);
  for (const [k, v] of secretValues) {
    if (text.includes(v)) findings.push(`${rel}: value of secrets file key "${k}" (${tail(v)})`);
  }
  for (const m of text.matchAll(/AQ\.[A-Za-z0-9_-]{20,}/g)) {
    findings.push(`${rel}: Gemini/Google AI-style key (${tail(m[0])})`);
  }
  for (const m of text.matchAll(/AIza[0-9A-Za-z_-]{35}/g)) {
    if (!publicKeys.has(m[0])) findings.push(`${rel}: unrecognised Google API key (${tail(m[0])})`);
  }
  if (/-----BEGIN [A-Z ]*PRIVATE KEY-----|"private_key_id"\s*:/.test(text)) {
    findings.push(`${rel}: private key / service-account material`);
  }
  if (text.includes('GEMINI_API_KEY')) {
    findings.push(`${rel}: reference to GEMINI_API_KEY`);
  }
}

if (findings.length) {
  console.error(`✖ ${findings.length} possible secret(s) in ${buildDir}:`);
  for (const f of [...new Set(findings)]) console.error(`  - ${f}`);
  console.error('Do not deploy this build.');
  process.exit(1);
}
console.log(`✔ No secrets found in ${scanned} text files under ${buildDir} ` +
  `(${secretValues.length} secrets-file value(s) checked, ${publicKeys.size} public key(s) allow-listed).`);
