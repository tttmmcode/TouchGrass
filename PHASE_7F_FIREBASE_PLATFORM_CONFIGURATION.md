# Phase 7F — Firebase Android and iOS configuration

**Status: mismatched; the correction needs production registrations (approval G-1).**
- Nothing was registered or changed.
- The iOS release is **not validated**: there is no macOS here.

## 1. Current state (verified 2026-10-21)

| Item | Source | Value |
|---|---|---|
| Android `applicationId` and `namespace` | `android/app/build.gradle.kts` lines 101, 111 | `com.touchgrass.app` |
| iOS bundle ID (Runner) | `ios/Runner.xcodeproj/project.pbxproj` | `com.touchgrass.app` (tests: `com.touchgrass.app.RunnerTests`) |
| Firebase apps in `touchgrass-today` | `firebase apps:list` (read-only) | 4: Android `…:android:24eb…`, iOS `…:ios:0906…`, web `…:web:ebb0…`, web "windows" `…:web:6af5…` |
| Android app's package | `firebase apps:sdkconfig` (7E); `android/app/google-services.json` | **`com.example.touchgrass`** |
| iOS app's bundle | `firebase apps:sdkconfig` (7E); `lib/firebase_options.dart` `iosBundleId` (iOS **and** macOS) | **`com.example.touchgrass`** |
| `ios/Runner/GoogleService-Info.plist` | file | **absent** |
| Web config | `lib/firebase_options.dart` | `touchgrass-today`, bucket `touchgrass-today.firebasestorage.app` (parity test) |
| Version | `pubspec.yaml` | `1.0.0+1` |
| CI workflows | `.github/workflows` | none |
| Dev vs. production projects | — | **Only one Firebase project exists.** Tests use `demo-*` emulator projects only. The Android gate "app code has no emulator endpoints" passes. Development builds therefore talk to production. Separating them would need a second Firebase project: an owner decision, not a blocker. |

**Effect:**
- A release built today either fails the Android gate (correctly: `google-services.json` names the wrong package) or, if forced, initialises Firebase with an app registration for a different package. Google sign-in, App Check and FCM are per app registration.
- On iOS, the Google sign-in URL scheme and the plist would not match the bundle.

## 2. Plan (approval G-1: production project configuration)

**Exact operations** (Firebase project `touchgrass-today` only):

```
firebase apps:create ANDROID "TouchGrass Android" --package-name com.touchgrass.app --project touchgrass-today
firebase apps:create IOS "TouchGrass iOS" --bundle-id com.touchgrass.app --project touchgrass-today
```

| Question | Answer |
|---|---|
| Writes | Two new app registrations. Each also creates an auto-restricted API key (Firebase creates per-app keys). |
| Reads or exposes | Nothing private. |
| Unaffected | Auth providers, Firestore, Storage, rules, billing, Maps, AI. |
| Existing apps | **Keep** the `com.example.touchgrass` registrations until no installed build uses them. Deleting them is a separate decision. |
| OAuth and providers | Google sign-in on Android needs the **SHA-1 and SHA-256** of the debug key, the upload key and, after Play App Signing, Google's app-signing key on the new Android app (`firebase apps:android:sha:create <newAppId> <sha>`). Each SHA addition is a further project-configuration change: include them in G-1 or approve them separately. iOS Google sign-in uses the `REVERSED_CLIENT_ID` from the new plist as a URL scheme. Sign in with Apple needs the bundle ID in the Apple developer account (owner). |
| Cost | None |

**After registration (owner; files are public client config, but keep them out of chat and reports):**
1. `firebase apps:sdkconfig ANDROID <newAndroidAppId> --project touchgrass-today > android/app/google-services.json`
2. `firebase apps:sdkconfig IOS <newIosAppId> --project touchgrass-today > ios/Runner/GoogleService-Info.plist`
3. `flutterfire configure --project touchgrass-today --platforms android,ios,web`. This updates `lib/firebase_options.dart` (`appId`, `iosBundleId`) and the `flutter` block of `firebase.json`. **Check the diff:** web values must not change.
4. Rerun:
   - `bash tool/test_android_gates.sh --full`;
   - `flutter analyze`, `flutter test`;
   - the parity test (project and bucket consistency).
5. Restrict the new Android and iOS API keys by package/SHA and bundle ID in Google Cloud Console (B5). Owner, separately authorized.

## 3. Android validation after G-1 (not run: blocked by G-1 and signing)

- `flutter build appbundle --release` (with signing; see `PHASE_7F_ANDROID_SIGNING_GUIDE.md`).
- Confirm the package: `aapt2 dump badging` or `bundletool dump manifest` shows `package="com.touchgrass.app"`.
- Confirm the config: the packaged `google-services` values carry the new `mobilesdk_app_id`.
- Confirm debug settings are off in the release manifest: `debuggable` absent or false; no cleartext traffic; no emulator hosts.
- Permissions in the merged manifest match the disclosures (camera, location when in use, photos and notifications as used).
- Secret scan of the AAB (unzip, grep for `AIza`, private keys, `GEMINI`, `generativelanguage`): only the restricted Firebase Android key is expected.
- On a test device with test accounts: sign-in, a challenge photo upload, Journal, profile photo, and account deletion (after F-1).

## 4. iOS checklist (needs a Mac with Xcode; nothing below has been run)

1. Flutter SDK (same channel and version as this machine; check `flutter --version`), Xcode (current stable), CocoaPods (`sudo gem install cocoapods` or Homebrew).
2. After G-1:
   - put `ios/Runner/GoogleService-Info.plist` (bundle `com.touchgrass.app`) in place;
   - create `ios/Flutter/MapsApiKey.xcconfig` from the `.example`.
3. `cd ios && pod install`. Open `Runner.xcworkspace`.
4. Signing & Capabilities:
   - team, automatic signing, bundle `com.touchgrass.app`;
   - Push Notifications, Sign in with Apple, Background Modes (remote notifications);
   - the provisioning profile includes them.
5. `Info.plist`:
   - camera, photo library and location usage strings match the disclosures;
   - the `REVERSED_CLIENT_ID` URL scheme is added for Google sign-in.
6. `flutter build ipa --release`, then Xcode Organizer → Validate App.
7. On a device, with test accounts:
   - sign-in (Google, Apple, email);
   - camera and gallery upload (confirm the uploaded file has no GPS with `exiftool` on a downloaded copy);
   - Journal, profile photo;
   - account deletion (after F-1). Apple requires in-app deletion; the Sign in with Apple token isn't revoked (B14).
8. App Store Connect: privacy nutrition labels match `PHASE_7D_PRIVACY_DISCLOSURE_MATRIX.md` and the 7F status.

**Do not report iOS as passing until steps 6–7 have been run.**
