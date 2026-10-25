#!/usr/bin/env node
// Checks that the app's Firebase / Google client configuration is complete
// and consistent across Android, iOS, web and the Dart code before a
// release build (Phase 6 X-5; extended in Phase 7A).
//
//   node tool/check_firebase_config.mjs                     # all platforms
//   node tool/check_firebase_config.mjs --platform android  # android|ios|web
//   node tool/check_firebase_config.mjs --live              # + read-only Firebase checks
//   node tool/check_firebase_config.mjs --json
//
// LOCAL checks read repository files only. A local file that looks right
// does NOT prove an app is registered in Firebase — `--live` asks the
// Firebase CLI (already logged in; never logs in) with read-only commands:
// `apps:list` and `apps:android:sha:list`. Nothing is ever created or changed.
//
// Never prints an API key or other secret: keys are reported as present /
// missing / placeholder, and compared by hash only. Firebase client config
// (API keys, app IDs) is public by design; this guards against shipping a
// build wired to the wrong, a placeholder or a different-environment app.
//
// Exit: 0 = no FAIL (WARNs allowed), 1 = at least one FAIL, 2 = usage error.

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

export const EXPECTED = { androidPackage: 'com.touchgrass.app', iosBundle: 'com.touchgrass.app', minIos: 14 };
const PLACEHOLDER = /^(demo-|your[-_]|example|test-project|changeme|todo|placeholder|xxx)/i;
const API_KEY = /^AIza[0-9A-Za-z_-]{35}$/;
const keyHash = (k) => crypto.createHash('sha256').update(k).digest('hex').slice(0, 8);

function files(root) {
  const text = (rel) => {
    const p = path.join(root, rel);
    return fs.existsSync(p) ? fs.readFileSync(p, 'utf8') : null;
  };
  const json = (rel) => {
    const t = text(rel);
    if (t === null) return { state: 'missing', value: null };
    try { return { state: 'ok', value: JSON.parse(t) }; } catch { return { state: 'invalid', value: null }; }
  };
  return { text, json };
}

const plistValue = (plist, key) => plist && new RegExp(`<key>${key}</key>\\s*<string>([^<]*)</string>`).exec(plist)?.[1];
const keyState = (k) => (!k ? 'missing' : PLACEHOLDER.test(k) || !API_KEY.test(k) ? 'placeholder or malformed' : 'present');

/** Every LOCAL check (repository files only). */
export function checkLocal(root, { platform = 'all', expected = EXPECTED } = {}) {
  const { text, json } = files(root);
  const results = [];
  const add = (id, plat, ok, detail, warnOnly = false) =>
    results.push({ id, platform: plat, scope: 'local', level: ok ? 'PASS' : warnOnly ? 'WARN' : 'FAIL', detail });

  // ── Dart (flutterfire) options ───────────────────────────────────────────
  const options = text('lib/firebase_options.dart') ?? '';
  const block = (name) => new RegExp(`static const FirebaseOptions ${name} = FirebaseOptions\\(([\\s\\S]*?)\\);`).exec(options)?.[1] ?? '';
  const field = (b, f) => new RegExp(`${f}:\\s*'([^']+)'`).exec(b)?.[1];
  const opt = Object.fromEntries(['web', 'android', 'ios'].map((p) => [p, {
    projectId: field(block(p), 'projectId'), appId: field(block(p), 'appId'), apiKey: field(block(p), 'apiKey'),
    bucket: field(block(p), 'storageBucket'), iosBundleId: field(block(p), 'iosBundleId'),
  }]));
  const project = opt.android.projectId ?? opt.web.projectId;
  add('dart.firebaseOptions', 'shared', options.length > 0, options ? 'lib/firebase_options.dart present' : 'lib/firebase_options.dart missing — run `flutterfire configure`');
  const projects = Object.values(opt).map((o) => o.projectId);
  add('dart.singleProject', 'shared', projects.every((p) => p && p === projects[0]) && !PLACEHOLDER.test(projects[0] ?? ''),
    `projectId per platform (web, android, ios): ${projects.join(', ')}`);
  for (const p of ['web', 'android', 'ios']) {
    add(`dart.${p}ApiKey`, p, keyState(opt[p].apiKey) === 'present', `firebase_options ${p} apiKey: ${keyState(opt[p].apiKey)}`);
  }

  const fj = json('firebase.json');
  const rc = json('.firebaserc');
  add('firebaserc.defaultProject', 'shared', rc.value?.projects?.default === project,
    `.firebaserc default=${rc.value?.projects?.default ?? rc.state} (firebase_options: ${project})`);
  const fjApps = fj.value?.flutter?.platforms?.dart?.['lib/firebase_options.dart']?.configurations ?? {};
  const fjMismatch = ['android', 'ios', 'web'].filter((p) => fjApps[p] && fjApps[p] !== opt[p].appId);
  add('firebase.json.flutterAppIds', 'shared', fjMismatch.length === 0,
    fjMismatch.length ? `firebase.json flutter app IDs differ from firebase_options for: ${fjMismatch.join(', ')} (re-run flutterfire configure)` : 'firebase.json flutter app IDs match firebase_options');
  add('firebase.json.indexes', 'shared', Boolean(fj.value?.firestore?.indexes),
    fj.value?.firestore?.indexes ? `deploys ${fj.value.firestore.indexes}` : 'firebase.json does not reference firestore.indexes.json, so composite indexes are never deployed');

  // Storage bucket: options, native config and the rules' profile-photo pattern must agree.
  const buckets = new Set(Object.values(opt).map((o) => o.bucket).filter(Boolean));
  const rulesBucket = /firebasestorage\[\.\]googleapis\[\.\]com\/v0\/b\/'\s*\+\s*'([^']+)\/o\/user_avatars/.exec(text('firestore.rules') ?? '')?.[1]?.replace(/\[\.\]/g, '.');
  if (rulesBucket) buckets.add(rulesBucket);
  add('shared.storageBucket', 'shared', buckets.size === 1,
    `storage buckets in firebase_options${rulesBucket ? ' and firestore.rules' : ''}: ${[...buckets].join(', ') || 'none'}`);

  // ── Android ──────────────────────────────────────────────────────────────
  const gradle = text('android/app/build.gradle.kts') ?? '';
  const appId = /applicationId\s*=\s*"([^"]+)"/.exec(gradle)?.[1];
  const namespace = /namespace\s*=\s*"([^"]+)"/.exec(gradle)?.[1];
  add('android.applicationId', 'android', appId === expected.androidPackage, `applicationId=${appId ?? 'missing'} (expected ${expected.androidPackage})`);
  add('android.namespace', 'android', Boolean(namespace) && namespace === appId, `namespace=${namespace ?? 'missing'}`);
  const gs = json('android/app/google-services.json');
  add('android.google-services.json', 'android', gs.state === 'ok',
    gs.state === 'ok' ? 'present and valid JSON' : gs.state === 'invalid' ? 'android/app/google-services.json is not valid JSON — download it again'
      : 'android/app/google-services.json is missing — download it after registering the Android app');
  const clients = gs.value?.client ?? [];
  const pkgOf = (c) => c?.client_info?.android_client_info?.package_name;
  const androidClient = clients.find((c) => pkgOf(c) === appId);
  add('android.firebaseAppForPackage', 'android', Boolean(androidClient),
    `google-services.json has apps for: ${clients.map(pkgOf).join(', ') || 'none'} (needs ${appId})`);
  const gsProject = gs.value?.project_info?.project_id;
  add('android.projectMatches', 'android', Boolean(gsProject) && !PLACEHOLDER.test(gsProject) && gsProject === project,
    `google-services.json project_id=${gsProject ?? 'missing'}, firebase_options=${project}`);
  const sdkAppId = androidClient?.client_info?.mobilesdk_app_id;
  const projNum = gs.value?.project_info?.project_number;
  add('android.appIdFormat', 'android', Boolean(sdkAppId) && /^1:\d+:android:[0-9a-f]+$/.test(sdkAppId) && sdkAppId.split(':')[1] === projNum,
    androidClient ? `mobilesdk_app_id ${/^1:\d+:android:[0-9a-f]+$/.test(sdkAppId ?? '') ? 'well-formed' : 'malformed'}; project number ${sdkAppId?.split(':')[1] === projNum ? 'matches' : 'differs'}` : 'no client for this package');
  const gsKey = androidClient?.api_key?.[0]?.current_key;
  add('android.apiKey', 'android', keyState(gsKey) === 'present', `google-services.json api key: ${androidClient ? keyState(gsKey) : 'no client'}`);
  add('dart.androidAppIdMatches', 'android', Boolean(sdkAppId) && opt.android.appId === sdkAppId,
    sdkAppId ? `firebase_options android appId ${opt.android.appId === sdkAppId ? 'matches' : 'differs from'} google-services.json` : 'nothing to compare: no google-services.json client for this package');
  const signInClient = (androidClient?.oauth_client ?? []).some((o) => o.client_type === 1 && o.android_info?.package_name === appId && o.android_info?.certificate_hash);
  add('android.googleSignInFingerprint', 'android', signInClient,
    signInClient ? 'an Android OAuth client with a certificate fingerprint is present' :
      'no Android OAuth client with a SHA fingerprint: Google sign-in fails (DEVELOPER_ERROR 10). Add the debug/upload/Play signing SHA-1 + SHA-256 in Firebase, then download google-services.json again', true);
  const localProps = text('android/local.properties') ?? '';
  const androidMaps = /^MAPS_API_KEY=(.*)$/m.exec(localProps)?.[1]?.trim();
  add('maps.androidKey', 'android', keyState(androidMaps) === 'present', `android/local.properties MAPS_API_KEY: ${keyState(androidMaps)}`);

  // ── iOS ──────────────────────────────────────────────────────────────────
  const pbx = text('ios/Runner.xcodeproj/project.pbxproj') ?? '';
  const bundleIds = [...new Set([...pbx.matchAll(/PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);/g)].map((m) => m[1].trim()))].filter((b) => !b.endsWith('.RunnerTests'));
  const bundleId = bundleIds.length === 1 ? bundleIds[0] : null;
  add('ios.bundleId', 'ios', bundleId === expected.iosBundle, `Runner PRODUCT_BUNDLE_IDENTIFIER: ${bundleIds.join(', ') || 'missing'} (expected ${expected.iosBundle})`);
  add('dart.iosBundleIdMatches', 'ios', opt.ios.iosBundleId === bundleId, `firebase_options iosBundleId=${opt.ios.iosBundleId ?? 'missing'}, Xcode=${bundleId}`);
  const gsi = text('ios/Runner/GoogleService-Info.plist');
  add('ios.GoogleService-Info.plist', 'ios', Boolean(gsi), gsi ? 'present' : 'missing — download it after registering the iOS app (flutterfire configure can place it)');
  add('ios.plistBundleIdMatches', 'ios', plistValue(gsi, 'BUNDLE_ID') === bundleId, `plist BUNDLE_ID=${plistValue(gsi, 'BUNDLE_ID') ?? 'n/a'}`);
  add('ios.plistProjectMatches', 'ios', plistValue(gsi, 'PROJECT_ID') === project, `plist PROJECT_ID=${plistValue(gsi, 'PROJECT_ID') ?? 'n/a'}`);
  add('ios.plistAppIdMatchesDart', 'ios', Boolean(gsi) && plistValue(gsi, 'GOOGLE_APP_ID') === opt.ios.appId,
    gsi ? `GOOGLE_APP_ID ${plistValue(gsi, 'GOOGLE_APP_ID') === opt.ios.appId ? 'matches' : 'differs from'} firebase_options ios appId` : 'n/a');
  const info = text('ios/Runner/Info.plist') ?? '';
  const clientId = plistValue(info, 'GIDClientID') || plistValue(gsi, 'CLIENT_ID');
  add('ios.googleSignInClientId', 'ios', Boolean(clientId),
    clientId ? 'Google sign-in client ID available (GIDClientID or plist CLIENT_ID)' : 'no GIDClientID in Info.plist and no CLIENT_ID in GoogleService-Info.plist: Google sign-in crashes on iOS');
  const reversed = plistValue(gsi, 'REVERSED_CLIENT_ID');
  const hasScheme = Boolean(reversed) && info.includes(`<string>${reversed}</string>`);
  add('ios.googleSignInUrlScheme', 'ios', hasScheme,
    reversed ? `REVERSED_CLIENT_ID URL scheme ${hasScheme ? 'present' : 'missing from Info.plist CFBundleURLTypes'}` : 'no REVERSED_CLIENT_ID (needs GoogleService-Info.plist with Google sign-in enabled)');
  const targets = [...pbx.matchAll(/IPHONEOS_DEPLOYMENT_TARGET = ([0-9.]+);/g)].map((m) => Number(m[1]));
  add('ios.deploymentTarget', 'ios', targets.length > 0 && targets.every((t) => t >= expected.minIos),
    `IPHONEOS_DEPLOYMENT_TARGET: ${targets.join(', ') || 'missing'} (google_maps_flutter_ios needs ${expected.minIos}.0)`);
  const podPlatform = Number(/^\s*platform\s+:ios,\s*'([0-9.]+)'/m.exec(text('ios/Podfile') ?? '')?.[1] ?? NaN);
  add('ios.podfilePlatform', 'ios', podPlatform >= expected.minIos, Number.isNaN(podPlatform) ? 'ios/Podfile missing or has no `platform :ios`' : `Podfile platform :ios ${podPlatform}`);
  const entPath = /CODE_SIGN_ENTITLEMENTS = ([^;]+);/.exec(pbx)?.[1]?.replace(/"/g, '').trim();
  const ent = entPath ? text(path.join('ios', entPath)) : null;
  add('ios.entitlements.signInWithApple', 'ios', Boolean(ent?.includes('com.apple.developer.applesignin')),
    ent ? `${entPath}: Sign in with Apple ${ent.includes('com.apple.developer.applesignin') ? 'present' : 'missing'}` : 'no CODE_SIGN_ENTITLEMENTS file: add "Sign in with Apple" and "Push Notifications" in Xcode → Signing & Capabilities');
  add('ios.entitlements.push', 'ios', Boolean(ent?.includes('aps-environment')), ent ? `aps-environment ${ent.includes('aps-environment') ? 'present' : 'missing'}` : 'aps-environment needed for push notifications');
  const appDelegate = text('ios/Runner/AppDelegate.swift') ?? '';
  add('ios.mapsKeyNotCommitted', 'ios', !/AIza[0-9A-Za-z_-]{35}/.test(appDelegate), /AIza/.test(appDelegate) ? 'AppDelegate.swift hard-codes a Maps key' : 'AppDelegate.swift reads the key from the build configuration');
  const xc = text('ios/Flutter/MapsApiKey.xcconfig');
  const iosMaps = /^\s*MAPS_API_KEY\s*=\s*(\S*)\s*$/m.exec(xc ?? '')?.[1];
  const plistWired = plistValue(info, 'GMSApiKey') === '$(MAPS_API_KEY)';
  add('maps.iosKey', 'ios', plistWired && keyState(iosMaps) === 'present',
    !plistWired ? 'Info.plist GMSApiKey is not $(MAPS_API_KEY)' : xc === null ? 'ios/Flutter/MapsApiKey.xcconfig missing (copy the .example; release builds stop without it)' : `MapsApiKey.xcconfig MAPS_API_KEY: ${keyState(iosMaps)}`);

  // ── Web ──────────────────────────────────────────────────────────────────
  const indexHtml = text('web/index.html') ?? '';
  const webMaps = /maps\.googleapis\.com\/maps\/api\/js\?key=([^&"']+)/.exec(indexHtml)?.[1];
  add('maps.webKey', 'web', keyState(webMaps) === 'present', `web/index.html Maps JavaScript key: ${keyState(webMaps)}`);

  // ── Keys shared across platforms ─────────────────────────────────────────
  const keys = [['android', androidMaps], ['ios', iosMaps], ['web', webMaps]].filter(([, k]) => keyState(k) === 'present');
  const shared = [];
  for (let i = 0; i < keys.length; i++) for (let j = i + 1; j < keys.length; j++) if (keys[i][1] === keys[j][1]) shared.push(`${keys[i][0]}+${keys[j][0]}`);
  add('maps.separateKeysPerPlatform', 'shared', shared.length === 0,
    shared.length ? `the same Maps key (#${keyHash(keys.find(([p]) => shared[0].startsWith(p))[1])}) is used by ${shared.join(', ')}: a key carries only ONE kind of application restriction (Android apps, iOS apps or websites), so it can't be locked down for both — create one key per platform`
      : `Maps keys are distinct per platform (${keys.map(([p, k]) => `${p} #${keyHash(k)}`).join(', ') || 'none configured'})`, true);

  return platform === 'all' ? results : results.filter((r) => r.platform === platform || r.platform === 'shared');
}

// ── LIVE (read-only Firebase CLI) ────────────────────────────────────────────

export function runFirebaseCli(args, cwd) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.env.FIREBASE_BIN || 'firebase', args, { cwd, shell: process.platform === 'win32' });
    let out = '';
    child.stdout.on('data', (d) => { out += d; });
    child.on('error', reject);
    child.on('exit', (code) => (code === 0 ? resolve(out) : reject(new Error(`firebase ${args[0]} exited ${code}`))));
  });
}

/** Read-only registration checks. [run] executes a firebase CLI command and
 * returns stdout; only `apps:list` and `apps:android:sha:list` are used. */
export async function checkLive({ project, expected = EXPECTED, localAndroidAppId, localIosAppId, run }) {
  const results = [];
  const add = (id, plat, ok, detail, warnOnly = false) =>
    results.push({ id, platform: plat, scope: 'live', level: ok ? 'PASS' : warnOnly ? 'WARN' : 'FAIL', detail });
  const parse = (s) => JSON.parse(s.slice(s.indexOf('{')));
  if (!/^[a-z0-9-]{4,40}$/.test(project ?? '')) {
    add('live.project', 'shared', false, 'no valid Firebase project ID in .firebaserc; live checks skipped');
    return results;
  }
  let apps;
  try {
    apps = parse(await run(['apps:list', '--json', '--project', project])).result ?? [];
  } catch (e) {
    add('live.appsList', 'shared', false, `could not list apps read-only (${e.message}); is the Firebase CLI logged in? This tool never logs in.`);
    return results;
  }
  const android = apps.find((a) => a.platform === 'ANDROID' && a.namespace === expected.androidPackage);
  const ios = apps.find((a) => a.platform === 'IOS' && a.namespace === expected.iosBundle);
  const others = (p) => apps.filter((a) => a.platform === p).map((a) => a.namespace).join(', ') || 'none';
  add('live.androidAppRegistered', 'android', Boolean(android),
    android ? `registered in ${project}` : `no Android app for ${expected.androidPackage} in ${project} (registered: ${others('ANDROID')})`);
  add('live.iosAppRegistered', 'ios', Boolean(ios),
    ios ? `registered in ${project}` : `no iOS app for ${expected.iosBundle} in ${project} (registered: ${others('IOS')})`);
  if (android) {
    add('live.androidLocalConfigIsThisApp', 'android', localAndroidAppId === android.appId,
      localAndroidAppId === android.appId ? 'google-services.json belongs to the registered app' : 'local google-services.json / firebase_options belong to a different app — download the config again');
    try {
      const shas = parse(await run(['apps:android:sha:list', android.appId, '--json', '--project', project])).result ?? [];
      add('live.androidShaFingerprints', 'android', shas.length > 0,
        shas.length ? `${shas.length} SHA fingerprint(s) registered` : 'no SHA fingerprints: Google sign-in will fail. Add debug, upload-key and Play app-signing SHA-1/SHA-256');
    } catch (e) {
      add('live.androidShaFingerprints', 'android', false, `could not list fingerprints (${e.message})`);
    }
  }
  if (ios) {
    add('live.iosLocalConfigIsThisApp', 'ios', localIosAppId === ios.appId,
      localIosAppId === ios.appId ? 'firebase_options ios appId belongs to the registered app' : 'firebase_options ios appId belongs to a different app — run flutterfire configure');
  }
  return results;
}

// ── CLI ──────────────────────────────────────────────────────────────────────

export function render(results, { live }) {
  const mark = { PASS: '✔', WARN: '!', FAIL: '✖' };
  const lines = ['LOCAL checks (repository files only — a matching file does NOT prove the app is registered in Firebase):'];
  for (const r of results.filter((x) => x.scope === 'local')) lines.push(`${mark[r.level]} ${r.id} — ${r.detail}`);
  if (live) {
    lines.push('', 'LIVE checks (read-only Firebase CLI):');
    for (const r of results.filter((x) => x.scope === 'live')) lines.push(`${mark[r.level]} ${r.id} — ${r.detail}`);
  } else {
    lines.push('', 'LIVE registration not checked (run with --live; uses the existing CLI login, read-only).');
  }
  const n = (l) => results.filter((r) => r.level === l).length;
  lines.push('', `${n('PASS')} passed, ${n('WARN')} warnings, ${n('FAIL')} failed.`);
  return lines.join('\n');
}

async function main(argv) {
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
  const i = argv.indexOf('--platform');
  const platform = i >= 0 ? argv[i + 1] : 'all';
  if (!['all', 'android', 'ios', 'web'].includes(platform)) {
    console.error('--platform must be android, ios, web or all');
    return 2;
  }
  const results = checkLocal(root, { platform });
  const live = argv.includes('--live');
  if (live) {
    const { text, json } = files(root);
    const project = json('.firebaserc').value?.projects?.default;
    const opts = text('lib/firebase_options.dart') ?? '';
    const appIdOf = (name) => new RegExp(`static const FirebaseOptions ${name} = FirebaseOptions\\([\\s\\S]*?appId:\\s*'([^']+)'`).exec(opts)?.[1];
    const liveResults = await checkLive({
      project, localAndroidAppId: appIdOf('android'), localIosAppId: appIdOf('ios'),
      run: (args) => runFirebaseCli(args, root),
    });
    results.push(...(platform === 'all' ? liveResults : liveResults.filter((r) => r.platform === platform || r.platform === 'shared')));
  }
  if (argv.includes('--json')) console.log(JSON.stringify({ results }, null, 2));
  else console.log(render(results, { live }));
  return results.some((r) => r.level === 'FAIL') ? 1 : 0;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).then((code) => process.exit(code), (e) => {
    console.error(`Could not run: ${e.message}`);
    process.exit(2);
  });
}
