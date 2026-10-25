# Phase 7A — Baseline (recorded 2026-10-19, before any Phase 7A change)

**Repository:** `C:\Users\tahee\touchgrass`, branch `release-hardening-pass`, HEAD `67c5a38`, no stash.

**Working tree:**
- `git status --short` has **148 entries**, identical to the end of Phase 6:
  - modified tracked files, from 101 files changed in `git diff --stat`;
  - untracked files and folders, including all Phase 1–6 reports, `firestore-tests/`, `functions/src/ops/` and `tool/`.
- All of it is uncommitted Phase 0–6 work and is preserved.
- A full list is in the scratchpad (`p7/status_start.txt`). Backups of every file Phase 7A edits are in `p7/bak/`.

**Protected file:** `DOCUMENTATION.md` SHA-256 `baa43787aad0a31987f3c894db09c67df4cfe05650d56d813027cbb62a9f94bc`.

## Tools available

| Tool | Version / state |
|---|---|
| Flutter / Dart | 3.44.1 / 3.12.1 |
| Node (default) / npm | v26.3.0 / 11.16.0. Functions tests are run on **Node 22.23.3**, the deployed runtime, from a verified zip. |
| Firebase CLI | 15.19.1. **Authenticated** (cached login; not re-authenticated by me). |
| Java | System 17.0.12; JBR 25.0.2 (needed by the emulators) |
| Gradle | wrapper 9.1.0; Android build-tools 34–36 (apksigner, aapt2) |
| Emulators | Firestore v1.21.0 jar, Storage rules runtime v1.1.3 |
| gcloud | **not installed** |
| Xcode / CocoaPods | **not available** (Windows) |

## Identifiers (from repo configuration; no secrets)

| Item | Value | Source |
|---|---|---|
| Firebase project | `touchgrass-today` (only project) | `.firebaserc`, `firebase.json`, `firebase_options.dart` |
| Android applicationId / namespace | `com.touchgrass.app` | `android/app/build.gradle.kts` |
| iOS bundle ID (Runner) | `com.touchgrass.app` | `project.pbxproj` |
| Bundle and package registered for the Firebase apps | `com.example.touchgrass` | `google-services.json`, `firebase_options.dart` |
| Firebase Android app | `1:760620662222:android:24eb…9f` | `firebase.json` |
| Firebase iOS app | `1:760620662222:ios:0906…9f` | `firebase.json` |
| Build flavors | none | Gradle and Xcode have only debug/profile/release |
| Storage bucket | `touchgrass-today.firebasestorage.app` | `firebase_options.dart` |

## Read-only production checks performed

Each command was checked in `firebase help <cmd>` and is list/print only.

| Command | Result |
|---|---|
| `apps:list` | 4 apps: Android, iOS, 2 web |
| `apps:sdkconfig` (identifiers only; keys discarded) | Android package and iOS bundle are both **`com.example.touchgrass`** |
| `apps:android:sha:list` | **No SHA fingerprints** |
| `firestore:databases:list` | `(default)`, STANDARD, Native mode |
| `firestore:indexes` | **No composite indexes, no field overrides** |
| `functions:list` | **No functions deployed** |

## New facts established at baseline

1. **NEW (high):** `firestore.indexes.json` defines two composite indexes, but **neither is deployed**.
   - `firebase.json` does not reference the file, so no deploy would ever send them.
   - The app's completions query (`userId ==` plus `orderBy completedAt desc`) needs one. It runs in:
     - the home path stream;
     - journal repair;
     - `latestCompletedAt`, which is used when saving a completion for any account without `lastCompletionDate`.
   - The audit's "indexes exist" was based on the local file only.
2. **NEW (medium):** a single Maps key (hash `#97425825`) is used by web (`index.html`), iOS (hard-coded in `AppDelegate.swift`) and Android (`local.properties`).
   - A Google Cloud key can carry only one type of app restriction, so it can't be restricted correctly for all three platforms.
3. **Confirmed (X-5):** no Firebase app is registered for `com.touchgrass.app` on either platform.
4. **Confirmed:** no `ios/Podfile`, no `Runner.entitlements`, no `GoogleService-Info.plist`, no `GIDClientID` and no Google URL scheme.
5. **Live rules** can't be read through any plain CLI command. The CLI's own MCP server has a `get_security_rules` tool, marked `readOnlyHint`. Its code only sends GETs to the Firebase Rules API (`listReleases`, `getRuleset`), and its startup billing check is also a GET.
