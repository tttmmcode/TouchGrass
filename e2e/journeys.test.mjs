// Real-browser user journeys (Phase 8) — Chrome drives a web build made with
// TG_FIREBASE_ENV=emulator against the local Emulator Suite. Synthetic
// accounts, a synthetic photo and synthetic coordinates only; nothing here
// can reach a real Firebase project (see harness.mjs).
//
//   E2E_WEB_DIR=<build dir> npm test        (see e2e/README.md)
import { describe, test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as h from './harness.mjs';
import { hasExifOrGps, makeSyntheticPhoto } from './photo.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const ART = path.join(here, 'artifacts');
const PHOTO = path.join(ART, 'synthetic-photo.jpg');
const PORT = 5055;
const APP = `http://127.0.0.1:${PORT}/`;
const PASSWORD = 'Synthetic-Pass-123';
// Synthetic coordinates (open ocean); used only to prove saved locations
// can be removed.
const SYNTHETIC_LOCATION = { latitude: 0.5, longitude: -30.5 };

const WEB = process.env.E2E_WEB_DIR;
let server;
let browser;

const fields = (doc) => doc?.fields ?? {};
const str = (v) => v?.stringValue;
const int = (v) => (v?.integerValue === undefined ? undefined : Number(v.integerValue));

async function shot(page, name) {
  await page.screenshot({ path: path.join(ART, `journey-${name}.png`) });
}

/** A fresh browser context on the app, accessibility tree on. */
async function open(opts = {}) {
  const ctx = await h.newPage(browser, opts);
  await ctx.page.goto(APP);
  await h.enableSemantics(ctx.page);
  return ctx;
}

/** Dismisses the explanation dialogs the app shows before permissions. */
async function dismissDialogs(page, seen = []) {
  for (let i = 0; i < 4; i++) {
    await page.waitForTimeout(1500);
    const dialog = page.locator('[role=alertdialog]');
    if (await dialog.count() === 0) return seen;
    seen.push(((await dialog.first().textContent()) ?? '').slice(0, 60));
    await dialog.getByRole('button').last().click();
  }
  return seen;
}

/** Waits for the URL, reporting what's on screen if it never comes. */
async function expectUrl(page, re, timeout = 60000) {
  try {
    await page.waitForURL(re, { timeout });
  } catch (e) {
    await shot(page, 'debug-url');
    const log = h.logOf(page);
    throw new Error(`${re} not reached (at ${new URL(page.url()).hash}); on screen: ${(await h.semanticsSummary(page)).join(' | ').slice(0, 1500)}`
      + `
console: ${log.recentConsole.join(' || ')}
http errors: ${log.httpErrors.slice(-10).join(' || ')}
failed: ${log.failedRequests.slice(-6).join(' || ')}
emulator requests: ${log.recentRequests.join(' || ')}`);
  }
}

async function signUp(page, { name, email }) {
  await page.getByRole('button', { name: 'Continue with Email' }).click();
  await page.getByRole('button', { name: 'Create account →' }).click();
  await h.typeInto(page, 'Your name', name);
  await h.typeInto(page, 'Email address', email);
  await h.typeInto(page, 'Password', PASSWORD);
  await h.typeInto(page, 'Confirm password', PASSWORD);
  await page.getByRole('button', { name: 'Create Account' }).last().click();
  await expectUrl(page, /#\/onboarding/, 60000);
  // Advance page by page until the last one; on a busy machine a click can
  // land mid-animation, so re-check each time instead of counting clicks.
  const letsGo = page.getByRole('button', { name: /^Let's go/ });
  for (let i = 0; i < 20 && await letsGo.count() === 0; i++) {
    const cont = page.getByRole('button', { name: 'Continue' });
    if (await cont.count()) await cont.first().click();
    await page.waitForTimeout(1200);
  }
  await letsGo.click();
  await expectUrl(page, /#\/home/, 60000);
  return dismissDialogs(page);
}

async function signIn(page, email) {
  await page.getByRole('button', { name: 'Continue with Email' }).click();
  await h.typeInto(page, 'Email address', email);
  await h.typeInto(page, 'Password', PASSWORD);
  await page.getByRole('button', { name: 'Sign In' }).last().click();
  await expectUrl(page, /#\/home/, 60000);
  await dismissDialogs(page);
}

async function uidOf(email) {
  const u = (await h.emulatorAdmin.authUsers()).find((x) => x.email === email);
  assert.ok(u, `no Auth user for ${email}`);
  return u.localId;
}

/** Opens Settings by its URL (works from any screen; the session is
 * restored on load). */
async function openSettings(page) {
  await page.goto(`${APP}#/profile/settings`);
  await h.enableSemantics(page);
  await expectUrl(page, /#\/profile\/settings/);
  await dismissDialogs(page);
  // The tab shell keeps Settings alive (and scrolled); entries are found
  // with h.scrollTo, which starts from the top.
  await page.getByRole('button', { name: 'Back', exact: true }).waitFor();
}

/** Waits for [locator], dismissing any explanation dialog that appears
 * meanwhile (permission primers can show late on a busy machine). */
async function waitPastDialogs(page, locator, seen = [], ms = 120000) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    if (await locator.count()) return locator;
    await dismissDialogs(page, seen);
  }
  await shot(page, 'debug-not-shown');
  throw new Error(`not shown in time; on screen: ${(await h.semanticsSummary(page)).join(' | ').slice(0, 1500)}`);
}

/** A Settings entry by name, scrolled into view. */
const settingsButton = (page, name) => h.scrollTo(page,
  page.getByRole('button', typeof name === 'string' ? { name, exact: true } : { name }).first());

async function waitFor(check, what, ms = 30000) {
  const end = Date.now() + ms;
  for (;;) {
    const v = await check();
    if (v) return v;
    if (Date.now() > end) throw new Error(`timed out waiting for ${what}`);
    await new Promise((r) => setTimeout(r, 500));
  }
}

before(async () => {
  assert.ok(WEB, 'set E2E_WEB_DIR to an emulator build (TG_FIREBASE_ENV=emulator)');
  await h.requireEmulators();
  await h.resetEmulators();
  server = await h.serve(WEB, PORT);
  browser = await h.launch();
  const probe = await browser.newPage();
  await makeSyntheticPhoto(probe, PHOTO);
  await probe.close();
});

after(async () => {
  await browser?.close();
  server?.close();
});

describe('web journeys on the emulators (Phase 8)', () => {
  const maya = { name: 'Maya E2E', email: 'maya.e2e@example.test' };
  let ctx;

  test('signed out, a direct link to Settings goes to sign-in', async () => {
    const c = await h.newPage(browser);
    await c.page.goto(`${APP}#/profile/settings`);
    await c.page.waitForURL(/#\/login/, { timeout: 60000 });
    assert.deepEqual(c.log.blockedProduction, []);
    await c.context.close();
  });

  test('sign-up keeps the typed name; no reminder prompt; today\'s challenge is ready', async () => {
    ctx = await open({
      width: 390, height: 844,
      permissions: ['geolocation'], geolocation: SYNTHETIC_LOCATION,
    });
    const { page } = ctx;
    const dialogs = await signUp(page, maya);
    await waitPastDialogs(page, page.getByRole('button', { name: "Start today's challenge" }), dialogs);
    assert.ok(!dialogs.some((d) => /Never miss an adventure|reminders/i.test(d)),
      `no reminder permission prompt (reminders don't exist): ${dialogs}`);
    await shot(page, '1-home-phone');
    const uid = await uidOf(maya.email);
    const profile = fields(await h.emulatorAdmin.doc(`users/${uid}`));
    assert.equal(str(profile.displayName), maya.name);
    assert.equal(profile.fcmToken, undefined, 'no notification token is stored');
    const challenges = await h.emulatorAdmin.list(`users/${uid}/challenges`);
    assert.equal(challenges.length, 1);
  });

  test('completing the challenge with a photo saves the completion, Journal entry, XP and streak — and strips GPS', async () => {
    const { page } = ctx;
    const uid = await uidOf(maya.email);
    await page.getByRole('button', { name: "Start today's challenge" }).click();
    const chooser = page.waitForEvent('filechooser', { timeout: 30000 });
    await page.getByRole('button', { name: 'Choose from Gallery' }).click();
    await (await chooser).setFiles(PHOTO);
    await page.getByRole('button', { name: /^Submit Photo/ }).click();
    await page.getByRole('button', { name: 'Save to Journal' }).waitFor({ timeout: 60000 });
    await shot(page, '2-caption-step');
    await h.typeInto(page, 'Write your adventure story…', 'Synthetic journey note');
    await page.getByRole('button', { name: 'Save to Journal' }).click();
    await h.waitForText(page, /Adventure Complete!/);
    await shot(page, '3-complete');

    const completions = await waitFor(async () => {
      const all = await h.emulatorAdmin.list('completions');
      return all.length ? all : null;
    }, 'the completion');
    const c = fields(completions[0]);
    assert.equal(str(c.userId), uid);
    assert.equal(str(c.verificationResult?.mapValue?.fields?.reason), 'Completed on the honor system with your photo.');
    assert.ok(c.location, 'location saved (setting on, permission granted)');
    const entries = await h.emulatorAdmin.list(`users/${uid}/memories`);
    assert.equal(entries.length, 1);
    assert.equal(str(fields(entries[0]).caption), 'Synthetic journey note');
    const user = fields(await h.emulatorAdmin.doc(`users/${uid}`));
    assert.equal(int(user.streak), 1);
    assert.ok(int(user.xp) >= 25);
    const objects = await h.emulatorAdmin.objects(`completion_photos/${uid}/`);
    assert.equal(objects.length, 1);
    const bytes = await h.emulatorAdmin.objectBytes(objects[0].name);
    assert.ok(bytes.length > 1000, 'a real image was stored');
    assert.equal(hasExifOrGps(bytes), false, 'EXIF/GPS removed before upload');
    await page.getByRole('button', { name: 'Continue' }).click();
  });

  // Emulator builds never save the session on web (main.dart: a restore
  // runs before the emulator is connected and would go to the real Auth
  // service), so a reload signs out. Production builds keep it.
  test('a reload reaches no real service; after signing in, the day stays done', async () => {
    const { page, log } = ctx;
    await page.reload();
    await h.enableSemantics(page);
    await expectUrl(page, /#\/login/, 60000);
    assert.deepEqual(log.blockedProduction, [], 'the reload sent nothing to a real service');
    await signIn(page, maya.email);
    await page.waitForTimeout(3000);
    assert.equal(await page.getByRole('button', { name: "Start today's challenge" }).count(), 0,
      'today is shown as done, not startable again');
    await shot(page, '4-after-reload');
  });

  test('feedback is sent and stored for the signed-in user', async () => {
    const { page } = ctx;
    await openSettings(page);
    await (await settingsButton(page, 'Send Feedback')).click();
    await page.locator('[role=alertdialog]').first().waitFor();
    await h.typeInto(page, 'Feature ideas, general feedback, anything…', 'Synthetic feedback from the journey test');
    await h.waitForText(page, /9[0-9]{2} characters remaining/);
    await page.getByRole('button', { name: 'Send', exact: true }).click();
    const fb = await waitFor(async () => {
      const all = await h.emulatorAdmin.list('feedback');
      return all.length ? all : null;
    }, 'the feedback document');
    assert.equal(str(fields(fb[0]).message), 'Synthetic feedback from the journey test');
    assert.equal(str(fields(fb[0]).userId), await uidOf(maya.email));
  });

  test('"Remove saved locations" removes them from the completion and the Journal entry', async () => {
    const { page } = ctx;
    const uid = await uidOf(maya.email);
    await openSettings(page);
    await (await settingsButton(page, /Remove saved locations/)).click();
    await page.getByRole('button', { name: 'Remove' }).click();
    await waitFor(async () => {
      const c = fields((await h.emulatorAdmin.list('completions'))[0]);
      const m = fields((await h.emulatorAdmin.list(`users/${uid}/memories`))[0]);
      return !c.location && !m.latitude && !m.longitude;
    }, 'locations to be removed');
    await shot(page, '5-locations-removed');
  });

  test('"Show on Leaderboard" off persists across a reload and removes the public entry', async () => {
    const { page } = ctx;
    const uid = await uidOf(maya.email);
    assert.ok(await h.emulatorAdmin.doc(`leaderboard_public/${uid}`), 'public entry exists first');
    await openSettings(page);
    // By role and name: the switch must be announced with its label.
    await (await h.scrollTo(page, page.getByRole('switch', { name: /Show on Leaderboard/ }))).click();
    await waitFor(async () => !(await h.emulatorAdmin.doc(`leaderboard_public/${uid}`)), 'the public entry to be removed');
    await page.reload();
    await h.enableSemantics(page);
    await expectUrl(page, /#\/login/, 60000);
    await signIn(page, maya.email);
    const profile = fields(await h.emulatorAdmin.doc(`users/${uid}`));
    assert.equal(profile.settings.mapValue.fields.profilePublic.booleanValue, false);
  });

  test('sign out, then sign back in', async () => {
    const { page } = ctx;
    await openSettings(page);
    await (await settingsButton(page, 'Sign Out')).click();
    await page.locator('[role=alertdialog]').getByRole('button', { name: 'Sign Out' }).click();
    await expectUrl(page, /#\/login/, 60000);
    await signIn(page, maya.email);
    await shot(page, '6-signed-back-in');
  });

  test('account deletion removes the account and its data, then confirms', async () => {
    const { page } = ctx;
    const uid = await uidOf(maya.email);
    await openSettings(page);
    await (await settingsButton(page, 'Delete Account')).click();
    await page.getByRole('button', { name: 'Delete Forever' }).click();
    await h.typeInto(page, 'Password', PASSWORD);
    await page.getByRole('button', { name: 'Delete Account' }).last().click();
    await expectUrl(page, /#\/login/, 180000);
    await h.waitForText(page, /Your account and the data saved with it were deleted/);
    await shot(page, '7-deleted');

    assert.equal((await h.emulatorAdmin.authUsers()).some((u) => u.localId === uid), false, 'Auth user gone');
    assert.equal(await h.emulatorAdmin.doc(`users/${uid}`), null, 'profile gone');
    assert.equal((await h.emulatorAdmin.list(`users/${uid}/memories`)).length, 0, 'Journal gone');
    assert.equal((await h.emulatorAdmin.list('completions')).length, 0, 'completions gone');
    assert.equal((await h.emulatorAdmin.list('feedback')).length, 0, 'feedback gone');
    assert.equal((await h.emulatorAdmin.objects(`completion_photos/${uid}/`)).length, 0, 'photos gone');
    const marker = fields(await h.emulatorAdmin.doc(`deletedAccounts/${uid}`));
    assert.deepEqual(Object.keys(marker).sort(), ['expiresAt', 'markedAt'], 'marker keeps timestamps only');
    assert.deepEqual(ctx.log.blockedProduction, [], 'nothing tried to reach production');
    assert.deepEqual(ctx.log.consoleErrors, [], 'no console errors during the whole journey');
    await ctx.context.close();
  });

  test('reroll on a fresh account: counter goes down and is saved', async () => {
    const c = await open({ width: 1280, height: 900 });
    await signUp(c.page, { name: 'Reroll E2E', email: 'reroll.e2e@example.test' });
    const uid = await uidOf('reroll.e2e@example.test');
    await c.page.getByRole('button', { name: /3 of 3 rerolls left/ }).click();
    await c.page.getByRole('button', { name: /2 of 3 rerolls left/ }).waitFor({ timeout: 60000 });
    const ch = await h.emulatorAdmin.list(`users/${uid}/challenges`);
    assert.equal(int(fields(ch[0]).rerollCount), 1);
    await shot(c.page, '8-desktop-after-reroll');
    assert.deepEqual(c.log.blockedProduction, []);
    await c.context.close();
  });
});
