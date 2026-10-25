# Phase 7A — Release Runbook

This runbook supersedes `PHASE_6_RELEASE_RUNBOOK.md` wherever they differ: the backup paths, the deployment order, and the live facts found in Phase 7A. Every step is labelled:

- **LOCAL / READ-ONLY**: safe; changes nothing in production.
- **OWNER ACTION**: needs your accounts, keys or a Mac; doesn't change Firebase data or rules.
- **⚠️ PRODUCTION — REQUIRES SEPARATE AUTHORIZATION**: changes the live project or store listings. Do it only when you decide to, one change at a time.

No passwords or keys appear in this document. `<…>` marks a value you supply.

## Overall order

| # | Step | Label | Section |
|---|---|---|---|
| 1 | Close the live photo exposure (interim Storage rules) | ⚠️ PRODUCTION | §5.2 |
| 2 | Deploy the composite indexes | ⚠️ PRODUCTION | §5.3 |
| 3 | Register the apps and run FlutterFire | OWNER ACTION | §1 |
| 4 | Create and back up the upload key | OWNER ACTION | §2 |
| 5 | Restrict the Maps keys (one per platform) | OWNER ACTION, partly ⚠️ | §9 |
| 6 | Deploy `deleteAccount`, then run the two-account test | ⚠️ PRODUCTION | §6, §8 |
| 7 | Coordinated window: rules + new web build | ⚠️ PRODUCTION | §5.5 |
| 8 | Photo inventories (dry runs, read-only) | ⚠️ PRODUCTION (reads private data) | §7 |
| 9 | Privacy policy and store forms | OWNER ACTION | §10 |
| 10 | iOS on a Mac | OWNER ACTION | §11 |
| 11 | Android release build and verification | OWNER ACTION / LOCAL | §3 |

Steps 1 and 2 don't depend on anything else and fix problems that are live today.

---

## §1 Firebase app registration and FlutterFire — OWNER ACTION

The live project has Android and iOS apps only for `com.example.touchgrass`, verified read-only. The app's real ID is **`com.touchgrass.app`** on both platforms (`android/app/build.gradle.kts`, `ios/Runner.xcodeproj`).

1. Firebase console → project **touchgrass-today** → Project settings → General → **Add app → Android**.
   - Package name: `com.touchgrass.app`. Nickname: e.g. "TouchGrass Android".
   - Add SHA fingerprints now or later (step 3). Click through; you'll download the config in step 4.
2. **Add app → Apple (iOS)**.
   - Bundle ID `com.touchgrass.app`. Team ID and App Store ID are optional now.
3. **SHA fingerprints** (Android app → Add fingerprint; add both SHA-1 and SHA-256 for each key). They are needed for Google sign-in, and each key covers different builds:

   | Key | Covers | How to get it |
   |---|---|---|
   | Debug keystore | Debug builds on developer machines | `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android` (each developer machine has its own) |
   | Upload key (§2) | Release builds you install yourself (e.g. the APK from §3) | `keytool -list -v -keystore <upload.jks> -alias upload` |
   | **Play App Signing key** | **Every build installed from Google Play**, including the internal-testing track, because Google re-signs them | Play Console → your app → Test and release → App integrity → App signing → "App signing key certificate". Available only after you create the app in Play Console. |

   One fingerprint doesn't cover the others. If the Play one is missing, Google sign-in fails only for Play installs (error 10, `DEVELOPER_ERROR`).
4. Regenerate the native config. On a Mac if you can, so the iOS plist is placed in Xcode too:
   ```
   dart pub global activate flutterfire_cli
   flutterfire configure --project=touchgrass-today --platforms=android,ios,web \
     --android-package-name=com.touchgrass.app --ios-bundle-id=com.touchgrass.app
   ```
   This rewrites `lib/firebase_options.dart`, `android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist` and the `flutter` block of `firebase.json`.
5. Review the diff:
   - `projectId` must stay `touchgrass-today`;
   - `storageBucket` must stay `touchgrass-today.firebasestorage.app` (`firestore.rules` hard-codes it in `isAllowedProfilePhoto`);
   - the web app IDs should be unchanged.
6. iOS Google sign-in: from the new `GoogleService-Info.plist`, add to `ios/Runner/Info.plist`:
   - `GIDClientID` = its `CLIENT_ID`;
   - a URL type whose scheme is its `REVERSED_CLIENT_ID`.
7. **LOCAL / READ-ONLY:** run `node tool/check_firebase_config.mjs --live`.
   - Every LOCAL check except the iOS entitlements and Maps-key lines should pass (those are handled in §9 and §11).
   - The LIVE checks must show both apps registered and at least one SHA fingerprint.
   - Note: local files alone never prove registration; that's what `--live` adds.
8. **LOCAL:** run `flutter test`, `flutter build apk --debug` (the X-5 gate now passes), and `bash tool/test_android_gates.sh`.

## §2 Android upload key — OWNER ACTION

1. Create the key **outside the repository**, e.g. in `~/keys/`. `keytool` ships with the Android Studio JBR.
   ```
   keytool -genkeypair -v -keystore ~/keys/touchgrass-upload.jks -alias upload \
     -keyalg RSA -keysize 4096 -validity 10000 -storetype PKCS12
   ```
   - Choose a strong password. PKCS12 uses one password for both the store and the key.
   - Never use the TEST keys made by `tool/test_android_gates.sh`; they are deleted after each run.
2. Back it up **before** the first upload. Losing it means asking Google for an upload-key reset.
   - Save the `.jks` file and its password in a password manager.
   - Keep an offline encrypted copy as well.
3. Create `android/key.properties`. It is git-ignored by `android/.gitignore`; check with `git check-ignore -v android/key.properties`.
   ```
   storeFile=<absolute path to touchgrass-upload.jks>
   storePassword=<password>
   keyAlias=upload
   keyPassword=<password>
   ```
   Restrict it to your user account. A relative `storeFile` is resolved from `android/app`.
4. Add `MAPS_API_KEY=<Android-restricted key from §9>` to `android/local.properties`, which is also git-ignored.
5. Record the fingerprint: `keytool -list -v -keystore ~/keys/touchgrass-upload.jks -alias upload` (SHA-1 and SHA-256). Add both to Firebase (§1.3).
6. Google Play App Signing:
   - Create the app in Play Console and accept Play App Signing (Google holds the app-signing key; you keep the upload key).
   - After the first upload, copy the **app signing** SHA-1 and SHA-256 into Firebase (§1.3) and into the Android Maps key restriction (§9).

## §3 Release build and signing verification — OWNER ACTION (local build)

1. Build:
   ```
   flutter build appbundle --release -P uploadCrashlyticsMapping=true
   ```
   - The `-P` flag uploads R8 mapping files to Crashlytics. Use it only for the build you'll upload, and only after §1, so mappings go to the right Firebase app.
   - The build **stops** with a "TouchGrass build stopped" list if `google-services.json` lacks `com.touchgrass.app`, if `key.properties` is missing or incomplete, if the keystore path is wrong, or if `MAPS_API_KEY` is empty. There is no debug-key fallback.
2. Check the AAB signer:
   ```
   keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab
   ```
   The SHA-256 must equal your **upload** key (§2.5) and must **not** equal the debug key.
3. Check the package, version and debuggability. Either:
   - `java -jar bundletool.jar dump manifest --bundle build/app/outputs/bundle/release/app-release.aab`: expect `package="com.touchgrass.app"`, the `versionCode`/`versionName` from `pubspec.yaml` (`1.0.0+1` → 1 / 1.0.0), and **no** `android:debuggable="true"`; or
   - build an APK and run `aapt2 dump badging` on it.
4. **LOCAL / READ-ONLY:** `bash tool/test_android_gates.sh --full`.
   - Uses a throwaway copy and a test key.
   - Proves each gate case, a debug build without signing material, and a test-key release whose APK passes `apksigner verify`, is signed by that key and not the debug key, is `com.touchgrass.app` and not debuggable, and ran no Crashlytics upload.
5. Uploading to Play is out of scope for this phase; nothing is published.

## §4 Live rules export and comparison — LOCAL / READ-ONLY

```
node tool/export_live_rules.mjs --project touchgrass-today
```

What it does:
- Uses the Firebase CLI's existing login and never logs in.
- Reads the live rules only through the CLI's MCP tool `get_security_rules`. The tool must be marked `readOnlyHint`; it GETs the Rules API (list releases, get ruleset).
- Reads the live indexes with `firebase firestore:indexes`.
- Writes `ops-out/live-rules/touchgrass-today-<UTC>/`:
  - `firestore.rules`, `storage.rules`, `firestore.indexes.json`, `meta.json`;
  - `comparison.md`: a diff, the `match` blocks only in live (a deploy removes their access), risky patterns, and an index comparison.
- `ops-out/` is git-ignored and is not referenced by `firebase.json`, so a snapshot can't be deployed by accident. **Never copy a snapshot over the repo's rules.**
- To re-compare after editing the local rules: `node tool/export_live_rules.mjs --compare-only <snapshot dir>`.

The 2026-10-19 result is summarised in `PHASE_7A_DEPLOYMENT_MANIFEST.md`:
- live Firestore = `HEAD` `firestore.rules`;
- live Storage = an unrecorded open-read ruleset;
- no indexes.

## §5 Rules, indexes and hosting

### 5.1 Pre-checks before ANY rules deploy — LOCAL / READ-ONLY

1. `node tool/export_live_rules.mjs --project touchgrass-today`. Confirm `comparison.md` shows the same live state as the manifest. If the live rules changed since 2026-10-19, stop and re-review.
2. `cd firestore-tests && npm test` (emulator, `demo-` project). Expect all tests to pass (347 at Phase 7A).
3. `git diff` the rules files against what you reviewed.

### 5.2 S-1 interim Storage rules — ⚠️ PRODUCTION — REQUIRES SEPARATE AUTHORIZATION

```
firebase deploy --only storage --config deploy/interim/firebase.interim-storage.json --project touchgrass-today
```

- This deploys only `deploy/interim/storage.interim.rules`, which is compatible with the live web app and the new app (manifest S-1).
- `--config` points the CLI at that folder, so `--project` is required.
- Optional preview first: add `--dry-run`. It validates and compiles without releasing. Its own help says it "may still enable APIs on the target project", so treat it as part of the same authorization.

### 5.3 I-1 Firestore indexes — ⚠️ PRODUCTION — REQUIRES SEPARATE AUTHORIZATION

```
firebase firestore:indexes --project touchgrass-today          # read-only: expect none
firebase deploy --only firestore:indexes --project touchgrass-today
```

- If the CLI offers to delete indexes that aren't in the file, answer **No**. There were none at Phase 7A.
- Wait until Console → Firestore → Indexes shows both as **Enabled**.
- `firebase.json` now references the indexes file. As a result, a bare `--only firestore` deploys rules **and** indexes, so always name the target: `firestore:rules` or `firestore:indexes`.

### 5.4 Smoke test after S-1 — OWNER ACTION

1. In the live web app, signed in as test user A: open the Journal, and A's photos load. Complete a challenge with a photo; it saves.
2. Change the profile photo; it works now. It was denied before S-1.
3. Firebase console → Storage → Rules → **Rules Playground**. This is a simulation; nothing is read or changed.
   - Simulate `get` on `/b/touchgrass-today.firebasestorage.app/o/completion_photos/<A uid>/x.jpg` as authenticated uid `<B uid>`. It must be **denied**.
   - The same request as `<A uid>` must be **allowed**.
4. Check the Storage rules metrics: denied requests should not spike for legitimate traffic.

### 5.5 Coordinated window: R-1 + S-2 + H-1 — ⚠️ PRODUCTION — REQUIRES SEPARATE AUTHORIZATION

**Prerequisites:**
- §5.1 is done;
- I-1 is Enabled;
- F-1 is deployed (§6), or you accept that Delete account says "isn't available right now".

**Steps:**
1. **LOCAL:** build the web app and scan it.
   ```
   flutter build web --release
   node tool/check_web_bundle_secrets.mjs
   ```
   Never pass `--dart-define-from-file=secrets.json`. The scan must be clean.
2. Deploy both rulesets, then the web build **straight away**:
   ```
   firebase deploy --only firestore:rules,storage --project touchgrass-today
   firebase deploy --only hosting --project touchgrass-today        # both sites: today + main
   ```
3. Smoke test with a **new** account, and repeat with an existing account:
   1. sign up (Google and email);
   2. first completion with a photo, which also tests the index;
   3. Journal entry present;
   4. leaderboard shows the user;
   5. change avatar;
   6. Settings → Remove saved locations;
   7. send feedback;
   8. reroll limit (3).
4. **Rollback (together):**
   - Hosting → release history → roll back to the previous release;
   - **and** Firestore and Storage → Rules → history → restore the previous versions. The old web app needs the old rules.

## §6 `deleteAccount` deployment — ⚠️ PRODUCTION — REQUIRES SEPARATE AUTHORIZATION

| Item | Value |
|---|---|
| Function / source | `deleteAccount` in `functions/src/index.ts` → `functions/src/accountDeletion.ts`; codebase `default`, source `functions/` |
| Runtime | Node 22 (`engines.node`), firebase-functions 7.4.0 (v2 `onCall`), region `us-central1`, timeout 300 s, default memory, **no secrets** |
| Plan | Blaze. **Verified** read-only: "Billing Enabled: Yes". |
| APIs | The first deploy enables Cloud Functions, Cloud Build, Artifact Registry and Cloud Run; accept these. The CLI may ask about an Artifact Registry cleanup policy; choose per your cost preference. |
| Deployer IAM | Project Owner or Firebase Admin; or Cloud Functions Developer + Service Account User on the runtime service account + Cloud Build Editor + Artifact Registry Writer |
| Runtime IAM | Default compute service account. Needs Auth user admin, Firestore read/write and Storage object admin (the default Editor grant covers these). |

1. **LOCAL / READ-ONLY:** confirm the target and the current state.
   ```
   firebase use                                   # → touchgrass-today
   firebase functions:list --project touchgrass-today   # expect: none (2026-10-19)
   ```
2. **LOCAL:** `cd functions && npm ci && npm run build && npm test && npm run lint`.
   - All must pass, using Node 22.
   - The emulator suite is optional: `npm run test:emulator`, with Java 21+.
3. **⚠️ PRODUCTION:** deploy only this function:
   ```
   firebase deploy --only functions:deleteAccount --project touchgrass-today
   ```
   - **Never** use `--only functions` or a bare `firebase deploy`. Either would also try to deploy `verifyChallengeCompletion`, which needs `GEMINI_API_KEY` and must stay off.
   - If the CLI mentions `GEMINI_API_KEY` or `verifyChallengeCompletion`, **abort**.
4. `firebase functions:list --project touchgrass-today` should now show only `deleteAccount(us-central1)`, callable, nodejs22.
5. Run the controlled test (§8).
6. **Rollback:** `firebase functions:delete deleteAccount --region us-central1 --project touchgrass-today`.

**Dependency on rules:** none at the rules level, because the function uses the Admin SDK. Only the new app (H-1 or the mobile builds) calls it. Deploy F-1 before or with H-1, so the Delete account button works from day one.

## §7 Photo inventories (dry runs) — ⚠️ PRODUCTION — REQUIRES SEPARATE AUTHORIZATION (reads private data; writes nothing)

**Prerequisites:**
- Google Cloud CLI installed, then `gcloud auth application-default login` with an account that has **Storage Object Viewer** on the bucket and **Cloud Datastore Viewer** on Firestore.
- Never use a service-account key file.
- Build the tools: `cd functions && npm ci && npm run build`. All paths below are relative to `functions/`.
- Create a folder for the output (`ops-out/` is git-ignored): `mkdir ../ops-out`.

**Completion-photo GPS inventory.** It reads only the first 128 KB of each photo:
```
node lib/ops/opsCli.js photo-metadata-inventory --project touchgrass-today --real-project \
  --out ../ops-out/photo-inventory-1.json --max 5000
```
- stdout shows counts only: `clean`, `gps`, `other-metadata`, `not-jpeg`, `malformed`, `header-beyond-read`, `unreadable`, `skipped-name`, and `needsRemediation`.
- Object names and resume cursors are written only to the `--out` file, with owner-only permissions.
- If stdout says `moreRemaining`, continue with `--resume ../ops-out/photo-inventory-1.json --out ../ops-out/photo-inventory-2.json`.

**Profile-photo inventory:**
```
node lib/ops/opsCli.js profile-photo-inventory --project touchgrass-today --real-project \
  --out ../ops-out/profile-photos-1.json
```
- Counts: `none`, `own-avatar`, `google-photo`, `external`, `malformed`.
- The `--out` file lists uids **only** for `external` and `malformed`.
- Resume with `--resume`, as above.

**Reviewing the results:**
- `gps` > 0 means that many historical photos still carry a location inside the file.
- Even after S-1 these photos are readable by anyone holding their download URL. That is only their owner, unless a URL was shared.
- `external` > 0 means that many leaderboard photos load from third-party servers (N-6b).

**Remediation is a separate authorization:**
- **GPS strip:**
  1. Dry run: `photo-metadata-remediate --manifest <inventory --out> --out <file>`.
  2. Execute: `--execute --confirm-project touchgrass-today --run-id <id>`.
  - The tool rewrites photos losslessly in place, keeping each photo's link, and skips any that changed.
  - Backups go to `metadata_backup/completion_photos/{uid}/{run-id}/…`. They are new objects with **no download token**, and account deletion removes them.
  - Resume an interrupted run with `--resume <previous --out>`; finished photos are skipped.
  - **Delete the backups once verified:** `gcloud storage rm "gs://touchgrass-today.firebasestorage.app/metadata_backup/completion_photos/*/<run-id>/**"`.
- **External profile photos:** set `photoUrl` to null for the listed uids, and update their leaderboard mirror. Sign-in is unaffected (`photoUrl` plays no part in auth), and Google photos and own avatars are kept. A script needs approval first; none is included.

## §8 Controlled two-account deletion test — ⚠️ PRODUCTION — after §6, with authorization

**Accounts:** use two dedicated test accounts that you create, never real users:
- **A** will be deleted;
- **B** is the control.

**Setup:** for each account, in the app:
1. sign up, claim a username, set a profile photo;
2. complete one challenge with a photo;
3. send one feedback message;
4. stay visible on the leaderboard.

**Before deleting, record (read-only, Console):**
- Firestore:
  - `users/<uid>` and its `challenges` and `memories`;
  - `completions` where `userId == <uid>`;
  - `usernames` where `uid == <uid>`;
  - `feedback` where `userId == <uid>`;
  - `leaderboard_public/<uid>`.
- Storage:
  - `completion_photos/<uid>/`;
  - `user_avatars/<uid>.png`.
- Authentication: the users list.

**Test:**
1. Sign in as A on two devices or browsers (D1, D2).
2. On D1: Settings → Delete account → confirm → re-authenticate. Expect success and a return to the sign-in screen.
3. Verify A's records listed above are **all gone**, including the Auth user.
4. Verify every B item is **unchanged**, and that B can sign in and see its data.
5. On D2, which is still signed in as A: within an hour, any write must fail once its ID token expires (refresh tokens were revoked). Confirm D2 is signed out or shows errors, and that no new A records appear.
6. **Repeat and interrupt:**
   1. Create account A2 and start a deletion.
   2. Cut the network (airplane mode) right after confirming.
   3. Expect "We couldn't confirm that your account was deleted… retrying is safe".
   4. Reconnect. If A2 still exists, sign in (re-authentication within 5 minutes) and delete again; it must complete.
   5. Check that nothing of A2 remains and B is intact.
7. **Ownership:** call the callable directly, as test account A3, asking for B.
   1. Sign in to the web app as A3, and copy A3's ID token. It's in DevTools → Application → IndexedDB → `firebaseLocalStorageDb`, under `stsTokenManager.accessToken`. Treat it as a secret and don't save it.
   2. Within 5 minutes of signing in, run:
      ```
      curl -X POST -H "Authorization: Bearer <A3 ID token>" -H "Content-Type: application/json" \
        -d '{"data":{"uid":"<B uid>"}}' https://us-central1-touchgrass-today.cloudfunctions.net/deleteAccount
      ```
   3. The function ignores request data, so only **A3** is deleted. Confirm B is intact.
8. **Stale sign-in:** repeat step 7 for a new test account, using an ID token from a sign-in **more than 5 minutes** old. Refresh the token without re-authenticating; `auth_time` stays old. Expect `FAILED_PRECONDITION` ("please sign in again"), with nothing deleted.

**Expected log lines:** Cloud Logging, service `deleteaccount`, shows `Account deleted` with counts. Any `Account deletion incomplete` line means a failure that a retry resolves.

**Failure conditions (stop and investigate):**
- any B record changed;
- any A record remaining after success was reported;
- success shown while records remain;
- repeated `incomplete` errors.

## §9 Maps API key restrictions — OWNER ACTION, partly ⚠️ PRODUCTION

**What the app uses** (verified in code):

| Platform | Maps API | Key source |
|---|---|---|
| Android | **Maps SDK for Android** (`google_maps_flutter`) | `MAPS_API_KEY` in `android/local.properties` → manifest placeholder |
| iOS | **Maps SDK for iOS** | `MAPS_API_KEY` in `ios/Flutter/MapsApiKey.xcconfig` (git-ignored; Phase 7A) → `Info.plist` `GMSApiKey` → `AppDelegate`. Release and Profile builds stop if the file is missing. |
| Web | **Maps JavaScript API** (with the `geometry` library) | Inline in `web/index.html` (normal for web) |

- Place names come from the device's own geocoder (the `geocoding` plugin), not the Geocoding API.
- Weather comes from Open-Meteo, with no key.
- There is no server-side Maps key.

**Today one key (fingerprint `#97425825`) serves all three platforms**: web, the old hard-coded iOS key, and Android `local.properties`. A Google Cloud key carries only one kind of application restriction, so it can't be restricted correctly for three platforms.

**Steps** (Google Cloud console → APIs & Services → Credentials, project `touchgrass-today`):
1. **Create an Android key.**
   - Application restriction: Android apps. Add package `com.touchgrass.app` with the SHA-1 of:
     - the Play App Signing key (Play installs);
     - the upload key (sideloaded release builds);
     - optionally your debug key (or use a separate development key).
   - API restriction: Maps SDK for Android only.
   - Put it in `android/local.properties`.
2. **Create an iOS key.**
   - Application restriction: iOS apps, bundle ID `com.touchgrass.app`.
   - API restriction: Maps SDK for iOS only.
   - Put it in `ios/Flutter/MapsApiKey.xcconfig` (copy the `.example`).
3. **Restrict the existing key `#97425825` to the web** (⚠️ PRODUCTION: the live website uses it).
   - Application restriction: Websites: `https://touchgrass.web.app/*`, `https://touchgrass-today.web.app/*`, `https://touchgrass-today.firebaseapp.com/*`, `https://touchgrass.firebaseapp.com/*`, plus `http://localhost/*` only if you develop against it (better: a separate development key).
   - API restriction: Maps JavaScript API only.
   - Do this **after** steps 1–2 are in your builds, because any Android or iOS build still using that key will stop showing maps.
4. Optionally rotate `#97425825`, since it has been public in git history and the live site. Rotation isn't required once it is referrer-restricted. If you rotate: create the new web key, update `web/index.html`, redeploy hosting, then delete the old key.
5. **LOCAL:** `node tool/check_firebase_config.mjs`. `maps.separateKeysPerPlatform` must pass, and `maps.androidKey`, `maps.iosKey` and `maps.webKey` must be present.
6. Watch APIs & Services → Metrics per key for 48 hours, looking for errors such as `RefererNotAllowedMapError` or `API_KEY_ANDROID_APP_BLOCKED`.

The Firebase API keys in `firebase_options.dart` are separate. Leave them unrestricted unless you follow Firebase's own guidance, because wrong restrictions break sign-in.

## §10 Privacy policy and store disclosures — OWNER ACTION

Use `PHASE_7A_PRIVACY_DISCLOSURE_DRAFT.md`. Nothing has been published.
1. Resolve its open questions, marked **[OWNER]**.
2. Publish the policy at a stable URL you control.
3. Put that URL in Play Console and App Store Connect.
4. Fill in Play Data safety and Apple App Privacy from the draft's tables.
5. Add the account-deletion web link that Play asks for (draft §6).
6. Don't publish wording about deletion until F-1 is deployed, or until the policy says how to request deletion by email in the meantime.

## §11 iOS on a Mac — OWNER ACTION

Nothing here has been built. Phase 7A ran on Windows, so these steps are statically prepared only.

1. **Tools:**
   - the current Xcode from the App Store; confirm the minimum with `flutter doctor -v` for Flutter 3.44.1;
   - Flutter 3.44.1 (`flutter --version`);
   - CocoaPods (`brew install cocoapods`, or `sudo gem install cocoapods`).
2. **Setup:**
   1. Run `flutter pub get`.
   2. Do §1 on the Mac: `flutterfire configure` places `GoogleService-Info.plist` and adds it to the Runner target.
   3. Add `GIDClientID` and the `REVERSED_CLIENT_ID` URL scheme (§1.6).
   4. Copy `ios/Flutter/MapsApiKey.xcconfig.example` to `MapsApiKey.xcconfig` and add the iOS key (§9).
3. **Pods:**
   1. `cd ios && pod install`. `ios/Podfile` is new in Phase 7A, from Flutter's template with `platform :ios, '14.0'`, which `google_maps_flutter_ios` needs.
   2. Open `Runner.xcworkspace`, not the `.xcodeproj`.
   3. Keep `Podfile.lock` under version control.
4. **Signing & Capabilities** (Runner target):
   - choose your Team; Automatic signing;
   - add **Sign in with Apple**;
   - add **Push Notifications**;
   - Background Modes: Remote notifications (and Background fetch, which `Info.plist` already lists).
   - Xcode creates `Runner/Runner.entitlements` and sets `CODE_SIGN_ENTITLEMENTS`.
5. **Apple Developer and Firebase:**
   - the App ID `com.touchgrass.app` has Sign in with Apple and Push enabled;
   - create an APNs auth key, and upload it in Firebase → Project settings → Cloud Messaging → Apple app;
   - Firebase Authentication → Sign-in method → Apple is enabled.
6. **Checks:** run `node tool/check_firebase_config.mjs --platform ios --live`. Every check should pass.
7. **Device build:** `flutter run --release` on a physical iPhone. Then test:
   - email, Google and Apple sign-in;
   - Delete account (after §6), with each sign-in provider;
   - camera and photo-library permission prompts (the texts were updated in Phase 6);
   - location permission and the Settings → "Save location with adventures" toggle;
   - notifications (allow and deny);
   - the map showing tiles, which proves the iOS key and its restriction;
   - a photo upload with a completion;
   - leaderboard; Remove saved locations.
8. **Archive:** `flutter build ipa --release` (or Xcode → Product → Archive). Then Xcode Organizer → Validate App.
9. **Requirements to verify yourself** (not verified in Phase 7A; check Apple's current guidelines):
   - **Sign in with Apple token revocation.** Apple's account-deletion guidance asks apps with Sign in with Apple to revoke the user's Apple tokens when the account is deleted. TouchGrass deletes the Firebase user but **does not call Apple's revoke endpoint**.
     - Option: in the Apple re-authentication step of Delete account, call `FirebaseAuth.instance.revokeTokenWithAuthorizationCode(<authorizationCode>)` before calling `deleteAccount`.
     - This needs device testing. It is **not implemented**.
   - **Privacy manifest.** After archiving, Xcode → Organizer → Generate Privacy Report. Check that every SDK's `PrivacyInfo.xcprivacy` is present, and whether the app needs its own.
   - **Export compliance.** Decide on `ITSAppUsesNonExemptEncryption`; the app uses only standard HTTPS.
   - **App Privacy answers.** Use draft §5.
10. Uploading to App Store Connect and submitting are out of scope; nothing is published.

## §12 Monitoring and recovery

| Signal | Where | Action |
|---|---|---|
| Rules denials spike | Firestore and Storage → Usage | After S-1: roll back S-1 if legitimate uploads fail. After R-1: make sure H-1 is live. |
| `FAILED_PRECONDITION` (missing index) | Crashlytics, browser console | Check that I-1 is Enabled |
| `Account deletion incomplete` | Cloud Logging, service `deleteaccount` | Retry is safe; if one user fails repeatedly, inspect the error class in the log |
| Google sign-in error 10 | Device logs | A SHA fingerprint is missing (§1.3); re-download `google-services.json` |
| Map blank / key errors | APIs & Services → Metrics; device log "no Google Maps key" | Key restriction or a missing key file (§9) |

**Recovery points:**
- Rules history in the console (instant restore).
- Hosting release history.
- `firebase functions:delete deleteAccount`.
- The `ops-out/live-rules/` snapshots, which record what was live before each change.
- Firestore has **no backups and no point-in-time recovery** (verified). Consider enabling PITR or scheduled backups and delete protection before the release. These are paid resources; decide before enabling.
