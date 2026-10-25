# TouchGrass — Phase 6 release runbook

For the app owner. Every step is reproducible and contains **no secrets**.

Commands that change production are marked **⚠️ PRODUCTION**. Each one needs your explicit go-ahead at the time you run it. Everything else is read-only or local. Run the steps in order: later steps assume the earlier ones are done.

Project: **`touchgrass-today`**. Android application ID and iOS bundle ID: **`com.touchgrass.app`**.

---

## 1. Register the apps in Firebase and download their config (X-5)

**Why.** Firebase currently has only `com.example.touchgrass` (Android and iOS). This was re-read on 2026-10-19 with `firebase apps:list` and `apps:sdkconfig`. The Android app has no SHA fingerprints. Every Android build now stops with "google-services.json has no Firebase app for 'com.touchgrass.app'". Do **not** change the application ID to get around this.

1. **⚠️ PRODUCTION (adds apps; deletes nothing).** In the Firebase console: Project settings → *Your apps* → **Add app** → Android.
   - Package name: `com.touchgrass.app`.
   - Add the **SHA-1 and SHA-256** of your upload key (step 3.4) and of your debug key: `keytool -list -v -alias androiddebugkey -keystore %USERPROFILE%\.android\debug.keystore -storepass android`.
   - After you enrol in Play App Signing, also add the **Play app-signing key** fingerprints (Play Console → Setup → App integrity).
2. **⚠️ PRODUCTION.** Add app → iOS, with bundle ID `com.touchgrass.app` and your App Store ID if you have one.
3. Download both files:
   - `google-services.json` → `android/app/google-services.json` (replace the old one);
   - `GoogleService-Info.plist` → `ios/Runner/GoogleService-Info.plist`.
4. Regenerate the Dart options: `dart pub global activate flutterfire_cli`, then `flutterfire configure --project=touchgrass-today --platforms=android,ios,web`. When prompted, pick the **new** `com.touchgrass.app` apps.
5. Google sign-in on iOS: copy `REVERSED_CLIENT_ID` from the plist into `ios/Runner/Info.plist` → `CFBundleURLTypes` → `CFBundleURLSchemes`.
6. Verify (read-only): `node tool/check_firebase_config.mjs` should show every line **✔** except the iOS entitlements, which come from step 5.2 on a Mac.
7. Keep the old `com.example.touchgrass` apps until the new builds are live. Deleting them breaks any installed old build.

## 2. Firebase CLI sign-in (owner)

- `firebase login`, or `firebase login --reauth` if the token has expired. Then check with `firebase projects:list`; it should list `touchgrass-today`.
- Read-only checks used in this phase:
  - `firebase apps:list --project touchgrass-today`
  - `firebase apps:android:sha:list <appId> --project touchgrass-today`
- Never paste CLI tokens into files or chats. For CI, use a scoped service account through your CI's secret store, not `login:ci` tokens committed anywhere.

## 3. Android signing: create, protect, back up (X-6)

Release builds now **refuse to build** without a complete `android/key.properties`. There is no debug-key fallback, by design.

1. Create the upload key **outside the repo**. Choose the passwords yourself and enter them at the prompts; don't type them on the command line.
   ```
   keytool -genkeypair -v -keystore %USERPROFILE%\keys\touchgrass-upload.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000
   ```
   `keytool` comes with Android Studio: `"C:\Program Files\Android\Android Studio1\jbr\bin\keytool.exe"` on this machine.
2. Create `android/key.properties`. It is gitignored (`android/.gitignore` → `key.properties`; check with `git check-ignore -v android/key.properties`):
   ```
   storeFile=C:/Users/<you>/keys/touchgrass-upload.jks
   storePassword=<your store password>
   keyAlias=upload
   keyPassword=<your key password>
   ```
3. Make sure `android/local.properties` has `MAPS_API_KEY=<your Android Maps key>`. Release builds stop without it, because the map would not load.
4. Certificate fingerprints for Firebase (step 1.1): `keytool -list -v -keystore %USERPROFILE%\keys\touchgrass-upload.jks -alias upload`.
5. **Back up now.** Copy the `.jks` and both passwords into your password manager, **and** make an offline copy (an encrypted USB drive). Losing the upload key means a Play support reset. Never email it or commit it.
6. Enrol in **Play App Signing** when creating the app in Play Console. Google then holds the app-signing key, and yours is only the upload key.
7. If the setup is incomplete, the build error lists exactly what is missing, for example "key.properties has no 'keyAlias'". Fix it and re-run. Nothing is half-signed.

## 4. Android signed build and verification

```
flutter clean
flutter build appbundle --release                 # for Play
flutter build apk --release                       # for side-loaded testing
# Store build with readable Crashlytics stack traces (contacts Firebase):
flutter build appbundle --release -P uploadCrashlyticsMapping=true   # ⚠️ PRODUCTION (uploads the mapping file)
```

Verify the artifact (read-only; build-tools path from your Android SDK):
```
%LOCALAPPDATA%\Android\Sdk\build-tools\35.0.1\apksigner.bat verify --verbose --print-certs build\app\outputs\flutter-apk\app-release.apk
%LOCALAPPDATA%\Android\Sdk\build-tools\35.0.1\aapt2.exe dump badging build\app\outputs\flutter-apk\app-release.apk
```
Expected:
- the signer's SHA-256 equals your upload key's (step 3.4), **not** the debug key's;
- `package: name='com.touchgrass.app'`;
- no `application-debuggable`;
- `versionCode` and `versionName` match `pubspec.yaml`.

For the AAB: `jarsigner -verify -verbose -certs build\app\outputs\bundle\release\app-release.aab`.

## 5. iOS (needs a Mac with Xcode 16 or later)

Not verified in this phase: development is on Windows.

1. `flutter pub get && cd ios && pod install --repo-update`. The deployment target is now **iOS 14.0**, as `google_maps_flutter_ios` requires.
2. In Xcode, open `ios/Runner.xcworkspace` → Runner → **Signing & Capabilities**:
   - Team: your Apple Developer team. Bundle ID: `com.touchgrass.app`.
   - Add **Sign in with Apple** and **Push Notifications**. This creates `Runner.entitlements` with `com.apple.developer.applesignin` and `aps-environment`. Also add **Background Modes → Remote notifications**; `Info.plist` already lists it.
3. Apple Developer portal:
   - an App ID for `com.touchgrass.app` with Sign in with Apple and Push enabled;
   - an APNs **auth key**, uploaded in Firebase → Project settings → Cloud Messaging (⚠️ PRODUCTION config);
   - a distribution certificate and an App Store provisioning profile (or automatic signing).
4. The Maps iOS key in `ios/Runner/AppDelegate.swift` is a public client key. Restrict it to the bundle ID in Google Cloud → Credentials (X-4).
5. Build and check:
   ```
   flutter build ios --release --no-codesign      # compile check
   flutter build ipa --release                    # signed archive (uses Xcode signing)
   codesign -dv --verbose=4 build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app
   security cms -D -i build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app/embedded.mobileprovision | plutil -p - | grep -E "application-identifier|aps-environment|applesignin"
   node tool/check_firebase_config.mjs            # should be all ✔
   ```
6. On a real device: sign in with Google and Apple, take a photo, receive a test push, and deep-link from a notification.

## 6. Capture the live rules and compare them (X-2), before any deploy

1. Firebase console → Firestore → **Rules**: copy the published rules into `live/firestore.rules.<date>`, a local folder outside git. Do the same for Storage → Rules → `live/storage.rules.<date>`. The console's rules history keeps earlier versions too.
2. Compare: `git diff --no-index live/firestore.rules.<date> firestore.rules`, and the same for `storage.rules`. Read every difference. If the live rules allow something that the local rules deny and the current app relies on, stop and report it.
3. Never copy live rules over the local files automatically. The local files are the reviewed, tested version (310 emulator tests).

## 7. Staged deployment ⚠️ PRODUCTION (each stage needs its own approval)

The deployment manifest, the reasons for this order and what can fail at each stage are in `PHASE_6_SECURITY_REVIEW.md` → "Deployment manifest". Short version:

| Stage | What | Command | Old app versions afterwards |
|---|---|---|---|
| 0 | Prerequisites | Blaze confirmed; budget alert; live rules exported (step 6); APIs enabled: Cloud Functions, Cloud Build, Artifact Registry, Cloud Run, Eventarc, Secret Manager (only if AI is ever enabled) | — |
| 1 | Firestore + Storage rules | `firebase deploy --only firestore:rules,storage --project touchgrass-today` | Keep working, but an old client can no longer *set* an arbitrary profile photo URL (legitimate flows are unaffected). |
| 2 | Indexes (no change this phase) | `firebase deploy --only firestore:indexes --project touchgrass-today` | — |
| 3 | `deleteAccount` only | `firebase deploy --only functions:deleteAccount --project touchgrass-today` (**never** a bare `functions`) | Old clients have no server deletion; nothing changes for them. |
| 4 | App release | Upload the AAB and IPA built in steps 4 and 5 | — |
| 5 | Cleanup job (optional) | After a separate approval: add the export (see `functions/src/orphanPhotoCleanupJob.ts`), then `firebase deploy --only functions:orphanPhotoCleanupJob` in dry-run | — |

After each stage:
- **Rules:** run the app (old and new build) through sign-in, completing a challenge, the Journal, the leaderboard, changing your photo, feedback, and Remove saved locations.
- **Functions:** `firebase functions:list` and the logs in the console.
- **Billing:** check the billing report after 24 hours.

Rollback:
- **Rules:** re-publish the saved live version in the console (step 6) or deploy the previous file.
- **Functions:** `firebase functions:delete <name> --project touchgrass-today` (⚠️ PRODUCTION).
- **App:** halt the staged rollout in Play Console or App Store Connect.

## 8. Controlled account-deletion test (after stages 1, 3 and 4)

Use two owner-controlled test accounts (A to delete, B as a bystander), never a real user's.

1. **Seed A:** complete a challenge with a photo, set an avatar, claim a username, send feedback, appear on the leaderboard. Note A's uid.
2. **Negative tests:**
   - with a session older than 5 minutes → "please sign in again", and nothing is deleted;
   - cancel the re-authentication → nothing is deleted.
3. **Positive test:** delete → the app shows success only after the server confirms. In the console, confirm these are all gone:
   - `users/{uid}` and its subcollections;
   - `completions` where `userId == uid`;
   - `usernames` where `uid == uid`;
   - `feedback` where `userId == uid`;
   - `leaderboard_public/{uid}`;
   - `completion_photos/{uid}/`;
   - `user_avatars/{uid}.png`;
   - the Auth user.
4. **Bystander:** B is unchanged.
5. **Repeat:** call it again from a still-signed-in second device. Expect either "deleted" (idempotent) or "sign in again". The Auth account no longer exists, and refresh tokens were revoked first.
6. **Logs:** Cloud Logging → `deleteAccount` shows "Account deleted" with counts, and no stack traces visible to users.
7. **Analytics data at Google:** to also remove A's events, use the GA4 **User Deletion API**, or Analytics → Admin → Data deletion requests, with A's uid as the user ID. Data retention (Admin → Data settings) governs everyone else's events.

## 9. Historical photo metadata: dry-run audit (N-7)

**Background.** Photos uploaded before the Phase 4 fix may contain EXIF/XMP GPS. The tool reads only the first 128 KB of each photo, where metadata lives, and prints **counts only**. Object names go only to the `--out` file. Coordinates and image bytes are never printed.

1. Rehearse against the emulators first, from `functions/`:
   ```
   npm run build
   firebase emulators:exec --config ../firestore-tests/firebase.json --only firestore,storage --project demo-touchgrass-fn "node lib/ops/opsCli.js photo-metadata-inventory --project demo-touchgrass-fn --bucket demo-touchgrass-fn.appspot.com --out ops-out/inventory.json"
   ```
2. **Real project (reads private photos; needs your authorization):** `gcloud auth application-default login`, then:
   ```
   node lib/ops/opsCli.js photo-metadata-inventory --project touchgrass-today --real-project --out ops-out/inventory.json
   ```
   - stdout shows counts per category: `clean`, `gps`, `other-metadata`, `not-jpeg`, `malformed`, `header-beyond-read`, `unreadable`, `skipped-name`.
   - Large libraries: add `--max 1000` and re-run with `--page-token <nextPageToken>`.
   - `ops-out/` is gitignored.
3. **Remediation dry-run** (validates every replacement, writes nothing):
   ```
   node lib/ops/opsCli.js photo-metadata-remediate --project touchgrass-today --real-project --manifest ops-out/inventory.json --out ops-out/remediation-dry.json
   ```
   Every entry should be `would-rewrite`. Investigate any `validation-failed` or `not-strippable`.
4. **⚠️ PRODUCTION: execute** (overwrites photos in place):
   ```
   node lib/ops/opsCli.js photo-metadata-remediate --project touchgrass-today --real-project --execute --confirm-project touchgrass-today --run-id 2026xxxx --manifest ops-out/inventory.json --out ops-out/remediation-run.json
   ```
   - Each photo keeps its path, download token, content type and cache control, so saved links keep working.
   - The original is copied to `metadata_backup/<run-id>/…`, which storage.rules make server-only.
   - A photo changed since the inventory is skipped.
5. **Verify:** re-run the inventory. Expect `gps: 0` and `other-metadata: 0`. Open a few Journal entries in the app.
6. **⚠️ PRODUCTION: delete the backups** once verified, within about 7 days, because they still contain GPS. In the Cloud console, delete the `metadata_backup/<run-id>/` folder, or run `gsutil -m rm -r gs://touchgrass-today.firebasestorage.app/metadata_backup/<run-id>`.
7. **Recovery** (from `remediation-run.json`): copy `metadata_backup/<run-id>/<name>` back over `<name>`, keeping the `firebaseStorageDownloadTokens` metadata.

**Limitations:**
- This inventory is the only reliable way to know which photos are affected. Phase 6 did not scan production.
- The Storage emulator doesn't enforce `ifGenerationMatch`. The tool also re-checks the generation itself, but the atomic guarantee is only tested on real Cloud Storage.

## 10. Abandoned-photo cleanup (D-16)

- **Dry-run CLI** (writes nothing; lists every object's reason in `--out`):
  ```
  node lib/ops/opsCli.js orphan-photos --project touchgrass-today --real-project --out ops-out/orphans-dry.json
  ```
  - stdout shows `inspected`, `retained`, `eligible`, and `skipped` by reason.
  - The `--out` file lists one entry per object, e.g. `{name, outcome: "eligible" | "has-completion" | "too-recent" | "legacy-name" | …}`.
- **Synthetic volume (emulator test):** in a library of 322 photos (300 completed, 6 abandoned more than 7 days ago, 10 recent, 4 legacy-named, 2 of a deleted account), exactly the **6** abandoned photos are eligible. Expect real volumes of the same order: at most one per abandoned day per user.
- **⚠️ PRODUCTION: manual delete run.** Add `--execute --confirm-project touchgrass-today` to the dry-run command. Limits: ≤ 2000 inspected and ≤ 100 deleted per run. A lease (`_ops/orphanPhotoCleanup_lease`) prevents overlapping runs.
- **Scheduled job (separate approval):** enable it only after **two weekly dry-runs** whose eligible counts look plausible (no spike), and after the rules (stage 1) have been live for 7 days.
- **Monitoring:**
  - `_ops/orphanPhotoCleanup.lastReport` and the Cloud Logging entries "Orphan photo cleanup".
  - Alert if `eligible` exceeds 50 or `deleteFailed` is above 0.
  - Disable by pausing the Cloud Scheduler job or setting `ORPHAN_PHOTO_CLEANUP_MODE=dry-run`.
  - Deleted orphans are not recoverable, which is why dry-run comes first.

## 11. Legacy profile photo URLs (N-6)

- **Inventory** (read-only; counts per kind, with uids in `--out`):
  ```
  node lib/ops/opsCli.js profile-photo-inventory --project touchgrass-today --real-project --out ops-out/profile-photos.json
  ```
- **Migration plan (not implemented; needs approval).**
  - **Who:** only the uids listed under `external`.
  - **Change:** set `users/{uid}.photoUrl` and `leaderboard_public/{uid}.photoUrl` to `null` with the Admin SDK, in batches of 200, logging counts only.
  - **Effect:** the affected users see initials and can upload a new photo.
  - **Before then:** current app versions already refuse to load such URLs.

## 12. Monitoring, recovery, rollback (summary)

- **Functions:** Cloud Logging, filtered by function name. Error Reporting picks up thrown errors. Set an alert on `deleteAccount` errors > 0 in 1 hour.
- **Rules:** the Firestore usage dashboard; a spike in permission-denied after stage 1 means an old client is hitting a tightened path. Check against section 7's table.
- **Billing:** a budget alert at $5/month (alerts only, it doesn't cap spending), plus the 24-hour billing report after each stage.
- **Rollback:** see step 7. The data tools (steps 9–11) record a reversible manifest. Keep `ops-out/` files private and delete them when done.
