# Phase 7E — Android (and iOS) Release Readiness

**Status: NOT release-ready.** Two production configuration changes (Firebase app registrations) and owner-held signing material are needed. The local build gates are correct: they stop every release build until both exist (verified this run).

## 1. Verified facts (read-only, 2026-10-20)

| Item | Evidence | Value |
|---|---|---|
| Android `applicationId` / `namespace` | `android/app/build.gradle.kts` | `com.touchgrass.app` |
| iOS bundle ID | `ios/Runner.xcodeproj/project.pbxproj` | `com.touchgrass.app` (tests `.RunnerTests`) |
| Firebase Android app `1:760620662222:android:24eb…` | `firebase apps:sdkconfig ANDROID …` (package name only extracted) | **`com.example.touchgrass`** |
| Firebase iOS app `1:760620662222:ios:0906…` | `firebase apps:sdkconfig IOS …` (bundle ID only) | **`com.example.touchgrass`** |
| `android/app/google-services.json` | file | `com.example.touchgrass` |
| `android/key.properties` | file | **absent** (git-ignored, as it should be) |
| `.gitignore` | files | `key.properties`, `*.jks` and `*.keystore` ignored (root and `android/`) |
| SHA certificate fingerprints | `apps:android:sha:list` on the existing app | The command answered for the existing `com.example.touchgrass` app (contents not recorded). No Firebase app exists for `com.touchgrass.app` to hold fingerprints. |

## 2. Build gates (local, this run)

`bash tool/test_android_gates.sh` (a temporary copy; never touches `android/` or Firebase): **14/14 PASS, exit 0.**

| Gate | Result |
|---|---|
| App code has no emulator endpoints | PASS |
| Debug build needs no signing material | PASS |
| Debug build without `MAPS_API_KEY` still runs, and warns | PASS ×2 |
| Release / AAB without `key.properties` stops (**no debug-key fallback**) | PASS ×2 |
| Incomplete `key.properties` names the missing field (store/key password) | PASS ×2 |
| Keystore path that doesn't exist stops | PASS |
| Release without `MAPS_API_KEY` stops | PASS |
| Complete signing config passes the gate | PASS |
| **Debug build with the repo's current `google-services.json` stops (`com.example.touchgrass`)** | PASS |
| Malformed `google-services.json` stops | PASS |

**Not run:** `--full` (a real debug APK and a test-key-signed release build). It needs a valid `com.touchgrass.app` Firebase config to get past the gate. Run it after §3.

## 3. Firebase app registration: PRODUCTION change, needs authorization

The correct fix is new Firebase apps with the real IDs. Renaming the old apps isn't possible.

```
firebase apps:create ANDROID "TouchGrass Android" --package-name com.touchgrass.app --project touchgrass-today
firebase apps:create IOS "TouchGrass iOS" --bundle-id com.touchgrass.app --project touchgrass-today
```

**Then (owner):**
1. Add the **debug and upload/release SHA-1 and SHA-256** to the new Android app (`firebase apps:android:sha:create <appId> <sha>`). Google sign-in on Android needs them. After Play App Signing, also add **Play's app-signing key** SHA.
2. Download the configs: `firebase apps:sdkconfig ANDROID <newId> > android/app/google-services.json`; iOS → `ios/Runner/GoogleService-Info.plist`. These contain public client API keys: don't paste them into chat, and keep them out of reports.
3. Re-run `flutterfire configure --project touchgrass-today` so `lib/firebase_options.dart` and the `flutter` block of `firebase.json` point at the new app IDs. The web app is unchanged.
4. Restrict the **Maps** and **Firebase API keys** by package/bundle and SHA in Google Cloud. This is an owner action (B5); the Maps key is out of scope here.
5. Re-run `bash tool/test_android_gates.sh --full`.
6. **Leave the old `com.example.touchgrass` apps in place** until no build uses them. Removing them is a separate decision.

**Side effects:** only new app registrations. Auth, Firestore, Storage, rules and billing are unaffected. Push notifications (FCM) work per app, so the new app needs its own token flow, which is already in the code.

## 4. Release signing: owner only; never in the repository or chat

1. Create the upload key on your machine:
   ```
   keytool -genkeypair -v -keystore %USERPROFILE%\keys\touchgrass-upload.jks -keyalg RSA -keysize 2048 \
     -validity 10000 -alias upload
   ```
   Store it **outside** the repository, and back it up (a password manager plus an offline copy).
2. Create `android/key.properties` (git-ignored):
   ```
   storeFile=C:\\Users\\<you>\\keys\\touchgrass-upload.jks
   storePassword=<…>
   keyAlias=upload
   keyPassword=<…>
   ```
3. Add `MAPS_API_KEY=<restricted Android key>` to `android/local.properties` (git-ignored).
4. Enrol in **Play App Signing**: Google holds the app-signing key; you keep the upload key.
5. Run `flutter build appbundle --release`. The gate prints exactly what is missing.

Nothing about signing was created, requested or stored in this phase.

## 5. iOS: not validated

This machine has no macOS or Xcode, so iOS was not built and **is not validated**. On a Mac:
1. After §3, put `GoogleService-Info.plist` (bundle `com.touchgrass.app`) in `ios/Runner/`, and create `ios/Flutter/MapsApiKey.xcconfig` from the `.example`.
2. `cd ios && pod install`.
3. Open `Runner.xcworkspace`. Set the team and signing (automatic), and check that the bundle ID is `com.touchgrass.app`.
4. Capabilities to match the code: Push Notifications, Sign in with Apple, Background Modes (remote notifications), plus the camera, photo-library and location usage strings already in `Info.plist`.
5. `flutter build ipa --release`, then install on a device and test the S7–S9 equivalents and account deletion with test accounts.
6. Apple requires in-app account deletion: that needs F-1 deployed. Sign in with Apple tokens aren't revoked on deletion (B14).

## 6. Web build and deletion compatibility

- The web build calls `deleteAccount` in `us-central1`, matching the function.
- It must deploy in the coordinated window (`PHASE_7E_ACCOUNT_DELETION_RELEASE_PLAN.md` §5).
- Build with `flutter build web --release`, **never** with `--dart-define-from-file=secrets.json`.
- Bundle scan (this run): see the final report.

## 7. Secret handling (checked)

| Secret | Where | State |
|---|---|---|
| Android signing | `android/key.properties`, `*.jks` | Ignored, absent |
| Maps key (Android) | `android/local.properties` | Ignored. The gate refuses release builds without it. |
| Maps key (iOS) | `ios/Flutter/MapsApiKey.xcconfig` | Ignored (7A) |
| Gemini key | Never in the client. The server secret isn't created, and AI is no longer in the deploy entry point. | — |
| Firebase client config | `firebase_options.dart`, `google-services.json` | Public by design, but restrict it (§3.4) |
