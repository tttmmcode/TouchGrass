# Phase 7G — Development/production separation and platform registrations

**Status:** one Firebase project (`touchgrass-today`) serves development, testing and production. Nothing was created or changed. App registrations (AC-8) and environment separation (AC-9) need separate approvals.

## 1. What can reach production today (inspected 2026-10-21)

| Surface | Reaches production? | Evidence |
|---|---|---|
| `flutter run` / any app build | **Yes, always.** The app has no emulator mode, and the Android gate "app code has no emulator endpoints" forbids one, so release builds can't point at an emulator by mistake. | `lib/firebase_options.dart` is `touchgrass-today` only |
| `firebase …` CLI commands without `--project` | **Yes.** `.firebaserc` `default: touchgrass-today` | `.firebaserc` |
| Flutter unit and widget tests | No: they never initialise Firebase (fakes) | No `Firebase.initializeApp` in `test/` |
| Rules tests (`firestore-tests`) | No: `demo-touchgrass-rules` on the emulators, own `firebase.json` | `firestore-tests/package.json` |
| Functions tests | No: `demo-touchgrass-fn` on the emulators; the emulator suites refuse to start without emulator hosts | test headers |
| Operator CLI (`opsCli`) | Only with `--real-project` and the exact allowlist (`touchgrass-today` ↔ `touchgrass-today.firebasestorage.app`); writes also need `--execute --mode … --confirm-project` | Phase 7G guards and tests |
| Revocation experiment | Only `touchgrass-today` with `--mode test-object-mutation --confirm-project`; the rehearsal needs a `demo-` id | same |
| `tool/export_live_rules.mjs`, `check_firebase_config.mjs --live` | Yes, read-only | 7G audit |
| CI | None exists | `.github/` absent |

**Safeguards added in 7G:**
- the operator tools' exact allowlist;
- `demo-` ids on the emulators;
- refusal of mixed emulator environments and a conflicting `GCLOUD_PROJECT`;
- mutation modes.

**Deliberately not changed:** `.firebaserc`'s default alias. Removing it would make every `firebase` command require `--project`, which is safer, but it changes your daily workflow and the 7D consistency test. Recommended as step 1 below.

## 2. Separation plan (AC-9; each step needs approval; nothing done)

| Step | What | Production impact | Rollback |
|---|---|---|---|
| 1 | **Owner workflow:** drop `default` from `.firebaserc` and add aliases `prod` → `touchgrass-today` and `dev` → the new project; always pass `--project`. Update the 7D consistency test to expect aliases. | None (local file) | Restore the file |
| 2 | Create **`touchgrass-dev`** (new Firebase project, Spark plan unless Functions testing needs Blaze), owned by you | New project only; billing decision if Blaze | Delete the project |
| 3 | Register dev apps there (Android `com.touchgrass.app.dev` via an Android `dev` flavor with `applicationIdSuffix ".dev"`; iOS `com.touchgrass.app.dev`; a web app) | Dev project only | Remove the apps |
| 4 | `flutterfire configure --project touchgrass-dev --out lib/firebase_options_dev.dart`; select the options file by flavor (`--flavor dev` / `--dart-define=ENVIRONMENT=development`). Release builds keep `firebase_options.dart` (production). | None | Revert the code |
| 5 | Deploy rules and indexes to **dev** (`--project dev`), plus `deleteAccount` if testing deletion | Dev only | — |
| 6 | Auth providers in dev (Google sign-in needs dev OAuth clients and SHA fingerprints; Sign in with Apple needs the dev bundle id) | Dev only | — |
| 7 | Analytics and Crashlytics: separate dev streams, so production metrics stop counting developer use | None | — |
| 8 | Maps and API keys: separate restricted keys per project and app | None (new keys) | Delete the keys |
| 9 | Test data: synthetic only, in dev; never copy production user data | None | — |
| 10 | CI (if added): emulator suites only; any deploy job needs a manual approval step and project-scoped credentials kept in CI secrets | None | — |

**Risks:**
- **Don't migrate production data to dev.**
- The production project keeps its id, so no live user is affected.
- Cost: a Spark dev project is free; Blaze in dev costs only what you use (owner decision).

## 3. Firebase app registrations (AC-8; production configuration)

**Verified identifiers:**
- **Android:** `applicationId` and `namespace` = `com.touchgrass.app` (`android/app/build.gradle.kts`).
- **iOS:** Runner `PRODUCT_BUNDLE_IDENTIFIER` = **`com.touchgrass.app`** (`ios/Runner.xcodeproj/project.pbxproj`); tests: `com.touchgrass.app.RunnerTests`.
- **Registered in Firebase today:** Android `1:760620662222:android:24eb…` and iOS `1:760620662222:ios:0906…`, both **`com.example.touchgrass`**. `android/app/google-services.json` and `firebase_options.dart` (`iosBundleId`, iOS and macOS) match the old ids. `ios/Runner/GoogleService-Info.plist` is absent.

**Exact operations for approval:**

```
firebase apps:create ANDROID "TouchGrass Android" --package-name com.touchgrass.app --project touchgrass-today
firebase apps:create IOS "TouchGrass iOS" --bundle-id com.touchgrass.app --project touchgrass-today
```

- **Effect:** two new app registrations, each with its own auto-created, auto-restricted API key.
- **Unaffected:** Auth providers, Firestore, Storage, rules, billing, Maps, AI.
- The old `com.example.touchgrass` apps stay until no build uses them. Removing them is a separate decision.
- **SHA fingerprints** (Google sign-in on Android): debug, upload and Play app-signing certificates via `firebase apps:android:sha:create <newAppId> <sha>`. Each is a further configuration change, listed in AC-8.

**Afterwards:**
1. Owner: `firebase apps:sdkconfig ANDROID <id> > android/app/google-services.json` and `firebase apps:sdkconfig IOS <id> > ios/Runner/GoogleService-Info.plist`. These are public client config, but keep them out of chat.
2. `flutterfire configure --project touchgrass-today --platforms android,ios,web`. **Diff check:** web values unchanged; `iosBundleId` → `com.touchgrass.app`.
3. Rerun the Android gates (`--full`), `flutter analyze`/`test` and the parity test.
4. Restrict the new keys by package/SHA and bundle (Google Cloud Console; owner).

**OAuth:**
- Android Google sign-in needs the SHA fingerprints on the new app.
- iOS needs the `REVERSED_CLIENT_ID` URL scheme from the new plist in `Info.plist`.
- Sign in with Apple needs the bundle id enabled in the Apple developer account (owner).

## 4. Android signing and iOS

- **Android signing:** `PHASE_7F_ANDROID_SIGNING_GUIDE.md` (still current; nothing created). The full release build runs after AC-8 and your signing setup.
- **iOS:** the Mac/Xcode checklist in `PHASE_7F_FIREBASE_PLATFORM_CONFIGURATION.md` §4 is still current. Items needing a Mac: SDK/Xcode/CocoaPods, `pod install`, signing and provisioning, `flutter build ipa`, device tests, Organizer validation, TestFlight. Items needing an Apple developer account: team, capabilities (Push, Sign in with Apple), App Store Connect privacy labels. Owner decisions: privacy label answers, App Store metadata.
