// Shared harness for the real-browser journeys (Phase 8).
//
// The app under test is a web build made with TG_FIREBASE_ENV=emulator, so
// it talks ONLY to the local Firebase Emulator Suite under the
// `demo-touchgrass-dev` project (which no real project backs). The harness
// refuses to start unless the emulators answer on localhost, and the
// browser blocks every request to a real Firebase/Google backend, so a
// misconfigured build fails instead of touching production.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright-core';

export const EMULATOR_PROJECT = 'demo-touchgrass-dev';
export const PORTS = { auth: 9099, firestore: 8080, storage: 9199, functions: 5001 };

/** Hosts a real-backend request would go to; the browser aborts them. */
const PRODUCTION_HOSTS = [
  'firestore.googleapis.com', 'firebasestorage.googleapis.com', 'identitytoolkit.googleapis.com',
  'securetoken.googleapis.com', 'cloudfunctions.net', 'firebaseinstallations.googleapis.com',
  'firebase.googleapis.com', 'firebaselogging-pa.googleapis.com', 'google-analytics.com',
  'googletagmanager.com', 'generativelanguage.googleapis.com',
];

const TYPES = {
  '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.json': 'application/json',
  '.wasm': 'application/wasm', '.png': 'image/png', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml',
  '.ttf': 'font/ttf', '.otf': 'font/otf', '.css': 'text/css', '.ico': 'image/x-icon', '.webp': 'image/webp',
};

/** Serves [dir] like Firebase Hosting with the app's SPA rewrite. */
export function serve(dir, port) {
  const root = path.resolve(dir);
  const server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://localhost');
    let file = path.join(root, decodeURIComponent(url.pathname));
    if (!file.startsWith(root)) {
      res.writeHead(403).end();
      return;
    }
    if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) file = path.join(root, 'index.html');
    res.writeHead(200, { 'content-type': TYPES[path.extname(file)] ?? 'application/octet-stream' });
    fs.createReadStream(file).pipe(res);
  });
  return new Promise((resolve) => server.listen(port, '127.0.0.1', () => resolve(server)));
}

/** Throws unless every emulator answers locally. */
export async function requireEmulators() {
  for (const [name, port] of Object.entries(PORTS)) {
    try {
      await fetch(`http://127.0.0.1:${port}/`);
    } catch {
      throw new Error(`The ${name} emulator isn't running on 127.0.0.1:${port}. Start the suite first (see e2e/README.md).`);
    }
  }
}

/** Deletes all emulator data for the demo project (never a real project). */
export async function resetEmulators() {
  const p = EMULATOR_PROJECT;
  await fetch(`http://127.0.0.1:${PORTS.firestore}/emulator/v1/projects/${p}/databases/(default)/documents`, { method: 'DELETE' });
  await fetch(`http://127.0.0.1:${PORTS.auth}/emulator/v1/projects/${p}/accounts`, { method: 'DELETE' });
  const base = `http://127.0.0.1:${PORTS.storage}/v0/b/${STORAGE_BUCKET}/o`;
  const owner = { Authorization: 'Bearer owner' };
  const list = await (await fetch(base, { headers: owner })).json();
  for (const item of list.items ?? []) {
    await fetch(`${base}/${encodeURIComponent(item.name)}`, { method: 'DELETE', headers: owner });
  }
}

export const STORAGE_BUCKET = `${EMULATOR_PROJECT}.appspot.com`;

/** Admin (rules-bypassing) reads of the EMULATOR only, for assertions. */
export const emulatorAdmin = {
  async doc(path) {
    const r = await fetch(`http://127.0.0.1:${PORTS.firestore}/v1/projects/${EMULATOR_PROJECT}/databases/(default)/documents/${path}`,
      { headers: { Authorization: 'Bearer owner' } });
    return r.status === 404 ? null : r.json();
  },
  async list(path) {
    const r = await fetch(`http://127.0.0.1:${PORTS.firestore}/v1/projects/${EMULATOR_PROJECT}/databases/(default)/documents/${path}`,
      { headers: { Authorization: 'Bearer owner' } });
    return (await r.json()).documents ?? [];
  },
  async objects(prefix = '') {
    const r = await fetch(`http://127.0.0.1:${PORTS.storage}/v0/b/${STORAGE_BUCKET}/o?prefix=${encodeURIComponent(prefix)}`,
      { headers: { Authorization: 'Bearer owner' } });
    return (await r.json()).items ?? [];
  },
  async objectBytes(name) {
    const r = await fetch(`http://127.0.0.1:${PORTS.storage}/v0/b/${STORAGE_BUCKET}/o/${encodeURIComponent(name)}?alt=media`,
      { headers: { Authorization: 'Bearer owner' } });
    return Buffer.from(await r.arrayBuffer());
  },
  async authUsers() {
    const r = await fetch(`http://127.0.0.1:${PORTS.auth}/identitytoolkit.googleapis.com/v1/projects/${EMULATOR_PROJECT}/accounts:query`,
      { method: 'POST', headers: { Authorization: 'Bearer owner', 'content-type': 'application/json' }, body: '{}' });
    return (await r.json()).userInfo ?? [];
  },
};

/** Opens Chrome (the installed one: nothing is downloaded). */
export async function launch({ headless = true } = {}) {
  const browser = await chromium.launch({ channel: 'chrome', headless });
  return browser;
}

const logs = new WeakMap();
/** The log [newPage] keeps for [page]. */
export const logOf = (page) => logs.get(page);

/** A page that records console errors and failed requests, and blocks
 * every production backend host. */
export async function newPage(browser, { width = 1280, height = 900, ...rest } = {}) {
  const context = await browser.newContext({ viewport: { width, height }, ...rest });
  const page = await context.newPage();
  // Generous: Flutter web on a busy machine can take seconds per step.
  page.setDefaultTimeout(60000);
  const log = { consoleErrors: [], failedRequests: [], blockedProduction: [], recentConsole: [], httpErrors: [], recentRequests: [] };
  logs.set(page, log);
  await context.route('**/*', (route) => {
    const host = new URL(route.request().url()).hostname;
    if (PRODUCTION_HOSTS.some((h) => host === h || host.endsWith(`.${h}`))) {
      log.blockedProduction.push(`${host}${new URL(route.request().url()).pathname.slice(0, 80)}`);
      return route.abort();
    }
    return route.continue();
  });
  page.on('console', (m) => {
    if (m.type() === 'error') log.consoleErrors.push(m.text().slice(0, 300));
    log.recentConsole = [...log.recentConsole.slice(-14), `${m.type()}: ${m.text().slice(0, 200)}`];
  });
  // Paths only (no query strings, which can carry keys or tokens).
  page.on('request', (r) => {
    const u = new URL(r.url());
    if (Object.values(PORTS).map(String).includes(u.port)) {
      log.recentRequests = [...log.recentRequests.slice(-14), `${r.method()} ${u.port}${u.pathname.slice(0, 90)}`];
    }
  });
  page.on('response', (r) => {
    if (r.status() >= 400) log.httpErrors.push(`${r.status()} ${new URL(r.url()).host}${new URL(r.url()).pathname}`);
  });
  page.on('requestfailed', (r) => log.failedRequests.push(`${new URL(r.url()).host} ${r.failure()?.errorText ?? ''}`));
  return { page, context, log };
}

/** Turns on Flutter's accessibility tree so elements can be found by role
 * and label (the same tree screen readers use). */
export async function enableSemantics(page) {
  // A hash-only navigation keeps the running app (and its tree).
  if (await page.locator('flt-semantics').count()) return;
  await page.waitForSelector('flt-semantics-placeholder', { state: 'attached', timeout: 120000 });
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await page.waitForSelector('flt-semantics', { state: 'attached', timeout: 30000 });
}

/** Lists the labelled accessibility nodes on screen (for diagnostics). */
export async function semanticsSummary(page) {
  return page.evaluate(() => [...document.querySelectorAll('flt-semantics [aria-label], flt-semantics[aria-label], flt-semantics input, flt-semantics [role]')]
    .map((e) => `${e.getAttribute('role') ?? e.tagName.toLowerCase()}: ${(e.getAttribute('aria-label') ?? e.textContent ?? '').slice(0, 80)}`)
    .filter((s, i, a) => a.indexOf(s) === i));
}

/** Types into the text field labelled [name] the way a person does: click
 * it, select what's there, type. (Playwright's `fill` can hit a field
 * element Flutter has just rebuilt.) */
export async function typeInto(page, name, text) {
  const field = page.getByRole('textbox', { name, exact: true });
  await field.click();
  await page.keyboard.press('Control+A');
  await page.keyboard.type(text, { delay: 15 });
  await page.waitForTimeout(150);
}

/** Waits until some accessibility node's label or text matches [re]. */
export async function waitForText(page, re, timeout = 60000) {
  await page.waitForFunction((src) => {
    const r = new RegExp(src);
    return [...document.querySelectorAll('flt-semantics, flt-semantics *')]
      .some((e) => r.test(e.getAttribute('aria-label') ?? '') || r.test(e.textContent ?? ''));
  }, re.source, { timeout });
}

/** Scrolls the screen (Flutter scrolls, not the DOM) until [locator] is in
 * the accessibility tree — Flutter only exposes what's on screen. */
export async function scrollTo(page, locator, { maxSteps = 25, step = 350 } = {}) {
  const vp = page.viewportSize();
  await page.mouse.move(vp.width / 2, vp.height / 2);
  if (await locator.count()) return locator;
  // Start from the top: screens keep their scroll position.
  for (let i = 0; i < 4; i++) {
    await page.mouse.wheel(0, -4000);
    await page.waitForTimeout(250);
  }
  for (let i = 0; i < maxSteps; i++) {
    if (await locator.count()) return locator;
    await page.mouse.wheel(0, step);
    await page.waitForTimeout(400);
  }
  throw new Error('not found after scrolling');
}
