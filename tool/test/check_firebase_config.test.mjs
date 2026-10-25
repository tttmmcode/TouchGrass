// Tests for tool/check_firebase_config.mjs against synthetic projects in a
// temp folder. Offline: live checks use a fake CLI runner.
//   node --test "tool/test/*.test.mjs"
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { checkLocal, checkLive, render } from '../check_firebase_config.mjs';

// Syntactically valid but fake keys (AIza + 35 chars) — never real ones.
const fakeKey = (tag) => `AIza${tag.padEnd(35, 'x')}`.slice(0, 39);
const K = { web: fakeKey('TESTWEB'), android: fakeKey('TESTAND'), ios: fakeKey('TESTIOS'),
  mapsAndroid: fakeKey('MAPSAND'), mapsIos: fakeKey('MAPSIOS'), mapsWeb: fakeKey('MAPSWEB') };
const PKG = 'com.touchgrass.app';
const REV = 'com.googleusercontent.apps.123-abc';

function validProject(overrides = {}) {
  const f = {
    '.firebaserc': JSON.stringify({ projects: { default: 'tg-prod' } }),
    'firebase.json': JSON.stringify({
      firestore: { rules: 'firestore.rules', indexes: 'firestore.indexes.json' },
      flutter: { platforms: { dart: { 'lib/firebase_options.dart': { projectId: 'tg-prod',
        configurations: { android: '1:123:android:abc', ios: '1:123:ios:def', web: '1:123:web:0aa' } } } } },
    }),
    'firestore.rules': "url.matches('https://firebasestorage[.]googleapis[.]com/v0/b/'\n + 'tg-prod[.]firebasestorage[.]app/o/user_avatars%2F' + uid)",
    'lib/firebase_options.dart': `class DefaultFirebaseOptions {
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: '${K.web}',
    appId: '1:123:web:0aa',
    projectId: 'tg-prod',
    storageBucket: 'tg-prod.firebasestorage.app',
  );
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: '${K.android}',
    appId: '1:123:android:abc',
    projectId: 'tg-prod',
    storageBucket: 'tg-prod.firebasestorage.app',
  );
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: '${K.ios}',
    appId: '1:123:ios:def',
    projectId: 'tg-prod',
    storageBucket: 'tg-prod.firebasestorage.app',
    iosBundleId: '${PKG}',
  );
}`,
    'android/app/build.gradle.kts': `android {\n  namespace = "${PKG}"\n  defaultConfig {\n    applicationId = "${PKG}"\n  }\n}`,
    'android/app/google-services.json': JSON.stringify({
      project_info: { project_number: '123', project_id: 'tg-prod', storage_bucket: 'tg-prod.firebasestorage.app' },
      client: [{
        client_info: { mobilesdk_app_id: '1:123:android:abc', android_client_info: { package_name: PKG } },
        oauth_client: [{ client_id: 'x', client_type: 1, android_info: { package_name: PKG, certificate_hash: 'ab12' } }],
        api_key: [{ current_key: K.android }],
      }],
    }),
    'android/local.properties': `sdk.dir=C:\\sdk\nMAPS_API_KEY=${K.mapsAndroid}\n`,
    'ios/Runner.xcodeproj/project.pbxproj': [
      'PRODUCT_BUNDLE_IDENTIFIER = com.touchgrass.app;', 'PRODUCT_BUNDLE_IDENTIFIER = com.touchgrass.app.RunnerTests;',
      'IPHONEOS_DEPLOYMENT_TARGET = 14.0;', 'CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;'].join('\n'),
    'ios/Runner/Runner.entitlements': '<key>com.apple.developer.applesignin</key><array><string>Default</string></array>\n<key>aps-environment</key><string>production</string>',
    'ios/Runner/GoogleService-Info.plist': `<dict>
<key>CLIENT_ID</key><string>123-abc.apps.googleusercontent.com</string>
<key>REVERSED_CLIENT_ID</key><string>${REV}</string>
<key>API_KEY</key><string>${K.ios}</string>
<key>BUNDLE_ID</key><string>${PKG}</string>
<key>PROJECT_ID</key><string>tg-prod</string>
<key>GOOGLE_APP_ID</key><string>1:123:ios:def</string>
</dict>`,
    'ios/Runner/Info.plist': `<dict>
<key>GMSApiKey</key>
<string>$(MAPS_API_KEY)</string>
<key>CFBundleURLTypes</key><array><dict><key>CFBundleURLSchemes</key><array><string>${REV}</string></array></dict></array>
</dict>`,
    'ios/Runner/AppDelegate.swift': 'let mapsKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey")',
    'ios/Podfile': "platform :ios, '14.0'\n",
    'ios/Flutter/MapsApiKey.xcconfig': `MAPS_API_KEY = ${K.mapsIos}\n`,
    'web/index.html': `<script src="https://maps.googleapis.com/maps/api/js?key=${K.mapsWeb}&libraries=geometry"></script>`,
    ...overrides,
  };
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'tg-cfg-'));
  for (const [rel, content] of Object.entries(f)) {
    if (content === null) continue;
    fs.mkdirSync(path.dirname(path.join(root, rel)), { recursive: true });
    fs.writeFileSync(path.join(root, rel), content);
  }
  return root;
}

const failed = (rs) => rs.filter((r) => r.level === 'FAIL').map((r) => r.id).sort();
const byId = (rs, id) => rs.find((r) => r.id === id);

describe('local checks', () => {
  test('a complete, consistent project passes with no warnings', () => {
    const rs = checkLocal(validProject());
    assert.deepEqual(failed(rs), []);
    assert.deepEqual(rs.filter((r) => r.level === 'WARN'), []);
  });

  test('missing vs malformed google-services.json are reported differently', () => {
    const missing = byId(checkLocal(validProject({ 'android/app/google-services.json': null })), 'android.google-services.json');
    assert.equal(missing.level, 'FAIL');
    assert.match(missing.detail, /missing/);
    const bad = byId(checkLocal(validProject({ 'android/app/google-services.json': '{"client": [' })), 'android.google-services.json');
    assert.match(bad.detail, /not valid JSON/);
  });

  test('config registered for another package (the X-5 situation) fails', () => {
    const gs = JSON.parse(fs.readFileSync(path.join(validProject(), 'android/app/google-services.json'), 'utf8'));
    gs.client[0].client_info.android_client_info.package_name = 'com.example.touchgrass';
    const rs = checkLocal(validProject({ 'android/app/google-services.json': JSON.stringify(gs) }));
    assert.ok(failed(rs).includes('android.firebaseAppForPackage'));
    assert.match(byId(rs, 'android.firebaseAppForPackage').detail, /com\.example\.touchgrass.*needs com\.touchgrass\.app/);
    assert.ok(failed(rs).includes('dart.androidAppIdMatches'));
  });

  test('placeholder project IDs and API keys fail', () => {
    const root = validProject();
    const opts = fs.readFileSync(path.join(root, 'lib/firebase_options.dart'), 'utf8')
      .replaceAll("'tg-prod'", "'your-project-id'").replace(K.web, 'YOUR_API_KEY');
    const rs = checkLocal(validProject({ 'lib/firebase_options.dart': opts }));
    assert.ok(failed(rs).includes('dart.singleProject'));
    assert.ok(failed(rs).includes('dart.webApiKey'));
    assert.match(byId(rs, 'dart.webApiKey').detail, /placeholder/);
  });

  test('config from the wrong environment (another project) fails', () => {
    const gs = JSON.parse(fs.readFileSync(path.join(validProject(), 'android/app/google-services.json'), 'utf8'));
    gs.project_info.project_id = 'tg-staging';
    gs.project_info.project_number = '999';
    gs.client[0].client_info.mobilesdk_app_id = '1:999:android:abc';
    const plist = fs.readFileSync(path.join(validProject(), 'ios/Runner/GoogleService-Info.plist'), 'utf8')
      .replace('<string>tg-prod</string>', '<string>tg-staging</string>');
    const rs = checkLocal(validProject({
      'android/app/google-services.json': JSON.stringify(gs),
      'ios/Runner/GoogleService-Info.plist': plist,
      '.firebaserc': JSON.stringify({ projects: { default: 'tg-staging' } }),
    }));
    for (const id of ['android.projectMatches', 'dart.androidAppIdMatches', 'ios.plistProjectMatches', 'firebaserc.defaultProject']) {
      assert.ok(failed(rs).includes(id), id);
    }
  });

  test('a storage bucket that differs from the rules\' bucket fails', () => {
    const rs = checkLocal(validProject({ 'firestore.rules': "'https://firebasestorage[.]googleapis[.]com/v0/b/' + 'other[.]appspot[.]com/o/user_avatars%2F'" }));
    assert.ok(failed(rs).includes('shared.storageBucket'));
  });

  test('indexes not wired into firebase.json fail', () => {
    const fj = JSON.parse(fs.readFileSync(path.join(validProject(), 'firebase.json'), 'utf8'));
    delete fj.firestore.indexes;
    assert.ok(failed(checkLocal(validProject({ 'firebase.json': JSON.stringify(fj) }))).includes('firebase.json.indexes'));
  });

  test('Android sign-in without a SHA fingerprint is a warning with the fix', () => {
    const gs = JSON.parse(fs.readFileSync(path.join(validProject(), 'android/app/google-services.json'), 'utf8'));
    gs.client[0].oauth_client = [];
    const r = byId(checkLocal(validProject({ 'android/app/google-services.json': JSON.stringify(gs) })), 'android.googleSignInFingerprint');
    assert.equal(r.level, 'WARN');
    assert.match(r.detail, /SHA/);
  });

  test('iOS: hard-coded Maps key, old Podfile platform, missing key file and entitlements fail', () => {
    const rs = checkLocal(validProject({
      'ios/Runner/AppDelegate.swift': `GMSServices.provideAPIKey("${K.mapsIos}")`,
      'ios/Podfile': "# platform :ios, '13.0'\n",
      'ios/Flutter/MapsApiKey.xcconfig': null,
      'ios/Runner/Runner.entitlements': null,
    }));
    for (const id of ['ios.mapsKeyNotCommitted', 'ios.podfilePlatform', 'maps.iosKey', 'ios.entitlements.signInWithApple', 'ios.entitlements.push']) {
      assert.ok(failed(rs).includes(id), id);
    }
  });

  test('one Maps key on several platforms is flagged — by hash, never by value', () => {
    const rs = checkLocal(validProject({ 'web/index.html': `<script src="https://maps.googleapis.com/maps/api/js?key=${K.mapsAndroid}"></script>` }));
    const r = byId(rs, 'maps.separateKeysPerPlatform');
    assert.equal(r.level, 'WARN');
    assert.match(r.detail, /android\+web/);
    assert.match(r.detail, /#[0-9a-f]{8}/);
  });

  test('no output format ever contains an API key value', () => {
    const rs = checkLocal(validProject({ 'web/index.html': `<script src="https://maps.googleapis.com/maps/api/js?key=${K.mapsAndroid}"></script>` }));
    const out = render(rs, { live: false }) + JSON.stringify(rs);
    for (const k of Object.values(K)) assert.ok(!out.includes(k), 'a key value was printed');
    assert.match(render(rs, { live: false }), /does NOT prove the app is registered/);
  });

  test('--platform filtering keeps shared checks', () => {
    const rs = checkLocal(validProject(), { platform: 'android' });
    assert.ok(rs.every((r) => r.platform === 'android' || r.platform === 'shared'));
    assert.ok(rs.some((r) => r.id === 'android.applicationId'));
    assert.ok(!rs.some((r) => r.id.startsWith('ios.')));
  });
});

describe('live checks (fake read-only CLI)', () => {
  const fakeRun = (apps, shas = []) => {
    const calls = [];
    const run = async (args) => {
      calls.push(args[0]);
      if (args[0] === 'apps:list') return JSON.stringify({ status: 'success', result: apps });
      if (args[0] === 'apps:android:sha:list') return JSON.stringify({ status: 'success', result: shas });
      throw new Error(`unexpected command ${args[0]}`);
    };
    return { run, calls };
  };
  const registered = [
    { platform: 'ANDROID', namespace: PKG, appId: '1:123:android:abc' },
    { platform: 'IOS', namespace: PKG, appId: '1:123:ios:def' },
  ];

  test('registered apps with fingerprints and matching local config pass', async () => {
    const { run, calls } = fakeRun(registered, [{ shaHash: 'x', certType: 'SHA_256' }]);
    const rs = await checkLive({ project: 'tg-prod', localAndroidAppId: '1:123:android:abc', localIosAppId: '1:123:ios:def', run });
    assert.deepEqual(failed(rs), []);
    assert.deepEqual([...new Set(calls)].sort(), ['apps:android:sha:list', 'apps:list'], 'only read-only commands');
  });
  test('only com.example.touchgrass registered (today\'s state) fails both platforms', async () => {
    const { run } = fakeRun([{ platform: 'ANDROID', namespace: 'com.example.touchgrass', appId: 'a' }, { platform: 'IOS', namespace: 'com.example.touchgrass', appId: 'b' }]);
    const rs = await checkLive({ project: 'tg-prod', run });
    assert.deepEqual(failed(rs), ['live.androidAppRegistered', 'live.iosAppRegistered']);
    assert.match(byId(rs, 'live.androidAppRegistered').detail, /registered: com\.example\.touchgrass/);
  });
  test('no fingerprints, or local config from another app, fail', async () => {
    const { run } = fakeRun(registered, []);
    const rs = await checkLive({ project: 'tg-prod', localAndroidAppId: '1:123:android:old', localIosAppId: '1:123:ios:def', run });
    assert.deepEqual(failed(rs), ['live.androidLocalConfigIsThisApp', 'live.androidShaFingerprints']);
  });
  test('a logged-out CLI is reported, never logged in', async () => {
    const rs = await checkLive({ project: 'tg-prod', run: async () => { throw new Error('exited 1'); } });
    assert.equal(rs.length, 1);
    assert.match(rs[0].detail, /never logs in/);
  });
});
