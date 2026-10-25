# Phase 7A — Final Report: Pre-Deployment Verification & Controlled Release Preparation

**Date:** 2026-10-19 · **Branch:** `release-hardening-pass` · **HEAD:** `67c5a38`, unchanged

**Nothing was committed, pushed or deployed.**
- No production data, rules, indexes, functions, apps, keys, billing or store listings were changed.
- Every production contact was read-only (§4).
- AI verification is still off (`AI_VERIFICATION_ENABLED = false`).
- `DOCUMENTATION.md` SHA-256 is `baa43787aad0a31987f3c894db09c67df4cfe05650d56d813027cbb62a9f94bc` before and after.

## 1. Verdict

**Not ready for release. Ready for controlled, owner-authorized production steps.**

Phase 7A found that production is in a worse state than the reports assumed:
1. **The live Storage rules expose every user's completion photos to any signed-in user.**
2. **The live Firestore rules are the old committed rules**, so the audit's live findings still apply.
3. **No composite indexes are deployed**, and the app's completions query needs one.

All the local engineering for these is done and tested, including an interim fix that is safe to deploy right away. What remains are owner actions and separately authorized production steps.

## 2. Starting state (see `PHASE_7A_BASELINE.md`)

- Same branch and HEAD as Phase 6.
- 148 `git status` entries, all Phase 0–6 work, preserved.
- No stash.
- Tools:
  - Flutter 3.44.1;
  - Node 22.23.3 for Functions (from the verified zip);
  - Firebase CLI 15.19.1, **already logged in**;
  - JBR 25;
  - Android build-tools.
- Not available: gcloud and Xcode.

## 3. Phase 6 claims, checked

| Claim | Result |
|---|---|
| 460 Flutter tests | Confirmed. Now **465** (5 added). |
| 152 Functions unit / 23 emulator | Confirmed. Now **158 / 23**, on Node 22.23.3. |
| 310 rules tests | Confirmed. Now **347**. |
| Audits 0 | Confirmed (Functions all and prod-only; `firestore-tests`). |
| Web build and secret scan pass | Confirmed (17 files, no secrets). |
| Release signing fails closed; debug fallback removed | Confirmed by reading the code and by a new repeatable harness (13 gate cases + 10 build checks). |
| Config validator exists | Confirmed. Rewritten and tested (§5). |
| Profile-photo rules, deletion hardening, photo tools, iOS 14, AI hard stop | Confirmed in code. **Two defects found in the photo tool** (§5.4). |
| "Old clients stay compatible" with the new rules (`PHASE_6_SECURITY_REVIEW.md` §10, runbook stage 1) | **Wrong for the full ruleset.** The live web app's completion flow is denied by the local rules (emulator-proven, §5.2). The Phase 6 order "rules first" would have broken it. |
| Audit: "the completions and leaderboard composite indexes exist" | **Wrong for production.** That came from the local file only; none are deployed, and `firebase.json` never referenced the file. |
| Phase 6 runbook: `firebase deploy --only firestore:indexes` | Would not have deployed anything, because the indexes file wasn't referenced (fixed). |
| "Live Storage rules unknown" (X-2) | **Now known** (§4). |
| Blaze "owner-reported, not verified" (X-7) | **Verified: billing enabled.** |

## 4. Production checks performed (read-only only)

Each command's semantics were checked first in `firebase help` or in the firebase-tools source.
- `apps:list`, `apps:sdkconfig` (identifiers only; keys discarded), `apps:android:sha:list`;
- `firestore:databases:list`, `firestore:databases:get`, `firestore:indexes`, `firestore:backups:schedules:list`, `functions:list`;
- the CLI's MCP `get_security_rules` (`readOnlyHint`; GET `releases` and `rulesets` only) and `get_environment` (`readOnlyHint`; only the billing line was printed).

| Fact | Value |
|---|---|
| Live Firestore rules | **Byte-identical to `HEAD` `firestore.rules`** |
| Live Storage rules | `completion_photos/{userId}/{allPaths=**}`: **read for any signed-in user**; owner writes anything; no avatar rule; no catch-all deny. Matches **no** committed version. |
| Composite indexes | **None** |
| Functions | **None deployed** |
| Apps | Android and iOS only `com.example.touchgrass`; no SHA fingerprints |
| Billing | Enabled (Blaze) |
| Database | `(default)`, `nam5`, PITR off, no backups, delete protection off, version retention 1 h |

The snapshot is in `ops-out/live-rules/touchgrass-today-20261019T193135Z/` (git-ignored, never deployable), together with `comparison.md`.

## 5. Work implemented

### 5.1 Live rules export and comparison: `tool/export_live_rules.mjs` (new)
- Reads production only through the CLI's read-only MCP rules tool, and refuses the tool unless it is marked `readOnlyHint`.
- Never logs in, and requires the `.firebaserc` default project.
- Writes snapshots under `ops-out/` only.
- Produces a diff, a summary of `match` and function differences, risky-pattern detection (open grants, test-mode expiry, any-signed-in grants, missing catch-all) and an index comparison.
- **14 tests**, using a fake MCP server; they also prove the tool calls nothing but the rules tool.

### 5.2 Rules: new tests and an interim hotfix
- `deploy/interim/storage.interim.rules` (+ its config) closes the live photo exposure while accepting the live web app's `{timestamp}.jpg` uploads and the new app's `{date}.jpg`. **Not deployed.**
- New emulator suites, 37 tests:
  - `live_storage_exposure` (6): runs the exported live ruleset, proves the exposure, and proves both replacements close it;
  - `interim_storage` (14);
  - `live_client_compat` (7): the HEAD-era client's writes under the local rules. Profile, username, leaderboard and avatar writes work; completion upload, completion document and the separate reward update are **denied**;
  - `operator_and_queries` (10): `_ops` lease and `metadata_backup/` never client-accessible; catalogues read-only; the list queries the app runs are allowed only for the owner.
- `firestore.rules` and `storage.rules` are **unchanged** this phase.

### 5.3 Indexes
- `firebase.json` now references `firestore.indexes.json`.
- `test/core/firestore_index_parity_test.dart` (3 tests) pins the three query sites to the composite index.

### 5.4 Account deletion and the photo tools
- **Deletion now also removes the photo tool's backups** (`metadata_backup/completion_photos/{uid}/`). Unit order test and emulator footprint updated.
- **Defect 1 fixed: backups could be opened with the original photo's token URL.**
  - Backups were Storage copies, which inherit `firebaseStorageDownloadTokens`.
  - The emulator showed that overwriting the token wasn't enough there (it merges tokens), so backups are now **new objects with no token**.
  - Emulator-proven: the original token is refused.
- **Defect 2 fixed: backups were outside the user's prefix**, so account deletion missed them.
- Remediation **resumes** (`skipNames` / `--resume`), and an interrupted run retries cleanly. Both are tested.
- CLI:
  - real-project runs must write a private `--out` file;
  - stdout never carries names, uids or cursors (a Storage page token encodes an object path);
  - `--resume` and `--start-after` added;
  - the profile inventory now lists uids only for `external` / `malformed`.
- **The client's deletion message is now honest after a timeout or dropped connection:** "couldn't confirm", not "was not deleted" (2 tests).
- Emulator test seeding is batched; 420 parallel uploads made the Storage emulator drop connections.

### 5.5 Firebase config validator: `tool/check_firebase_config.mjs` (rewritten)
- About 35 local checks across Android, iOS, web, Dart and shared settings:
  - missing vs malformed files;
  - placeholders;
  - wrong environment (project, project number, bucket, `.firebaserc`, `firebase.json` app IDs);
  - Android OAuth fingerprint;
  - iOS plist, `GIDClientID` and URL scheme;
  - Podfile platform, entitlements, Maps keys;
  - the same Maps key used on several platforms (compared by hash).
- `--live` adds read-only registration checks: `apps:list` (namespace) and SHA fingerprints.
- Never prints a key. Output says plainly that local files don't prove registration.
- **16 tests.**

### 5.6 Android
- Debug builds warn when `MAPS_API_KEY` is missing; release builds already stop.
- `tool/test_android_gates.sh` (new) works on a throwaway copy with a test-only fixture config, a fake Maps key and a per-run test key, which is deleted afterwards.

### 5.7 iOS (static only; not built)
- `ios/Podfile` added, from Flutter 3.44.1's template with `platform :ios, '14.0'`.
- The Maps key is no longer hard-coded in `AppDelegate.swift`. It comes from the git-ignored `ios/Flutter/MapsApiKey.xcconfig` → `Info.plist` `GMSApiKey`.
- `Release.xcconfig` includes that file without the `?`, so in Xcode a missing file should stop Release and Profile builds early. This wasn't verified on Windows.
- An `.example` file is provided, and the real file is git-ignored.
- Icon checked: 1024 px, RGB, no alpha.

## 6. Files changed in Phase 7A

**Modified:**
- `firebase.json`
- `.gitignore`
- `android/app/build.gradle.kts`
- `ios/Flutter/Debug.xcconfig`
- `ios/Flutter/Release.xcconfig`
- `ios/Runner/Info.plist` (CRLF kept)
- `ios/Runner/AppDelegate.swift`
- `lib/services/account_deletion_service.dart`
- `test/repositories/commit_completion_test.dart`
- `functions/src/accountDeletion.ts`
- `functions/src/accountDeletion.test.ts`
- `functions/src/accountDeletion.emulator.test.ts`
- `functions/src/ops/photoMetadataJob.ts`
- `functions/src/ops/opsCli.ts`
- `functions/src/ops/profilePhotoInventory.ts`
- `functions/src/ops/ops.test.ts`
- `functions/src/ops/ops.emulator.test.ts`
- `firestore-tests/test/helpers.mjs`
- `tool/check_firebase_config.mjs`
- `KNOWN_BUGS.md`
- `REMEDIATION_CHECKLIST.md`

**New:**
- Reports:
  - `PHASE_7A_BASELINE.md`
  - `PHASE_7A_FINAL_REPORT.md`
  - `PHASE_7A_RELEASE_RUNBOOK.md`
  - `PHASE_7A_DEPLOYMENT_MANIFEST.md`
  - `PHASE_7A_PRIVACY_DISCLOSURE_DRAFT.md`
- Interim rules:
  - `deploy/interim/storage.interim.rules`
  - `deploy/interim/firebase.interim-storage.json`
- iOS:
  - `ios/Podfile`
  - `ios/Flutter/MapsApiKey.xcconfig.example`
- Tools:
  - `tool/export_live_rules.mjs`
  - `tool/test_android_gates.sh`
- Tool tests:
  - `tool/test/export_live_rules.test.mjs`
  - `tool/test/check_firebase_config.test.mjs`
  - `tool/test/fixtures/fake_mcp.mjs`
- Rules tests:
  - `firestore-tests/test/live_storage_exposure.test.mjs`
  - `firestore-tests/test/interim_storage.test.mjs`
  - `firestore-tests/test/live_client_compat.test.mjs`
  - `firestore-tests/test/operator_and_queries.test.mjs`
- Flutter test: `test/core/firestore_index_parity_test.dart`

**Not mine:** `.vscode/settings.json` appeared at 14:56, written by VS Code's Java extension (`java.configuration.updateBuildConfiguration`). It was left untouched.

**Git-ignored output:** `ops-out/live-rules/…` (the production snapshot).

Pre-change copies of every edited file are in the session scratchpad, `p7/bak/`.

## 7. Test results (this phase, actual exit codes)

| Suite | Command | Result |
|---|---|---|
| Dart format | `dart format --set-exit-if-changed lib test` | **0**: 157 files, 0 changed |
| Analyzer | `flutter analyze` | **0**: no issues |
| Flutter tests | `flutter test` | **0**: **465 passed** |
| Web release build | `flutter build web --release` (no `secrets.json`) | **0** |
| Bundle secret scan | `node tool/check_web_bundle_secrets.mjs` | **0**: no secrets (17 files) |
| Source secret scan | scratch scan of 331 tracked and untracked files | 0 real secrets (3 false positives: `key.properties` lookups and a `printf` placeholder); no Google key outside the public client-config files |
| Functions build / lint | `npm run build`, eslint (Node 22.23.3) | **0 / 0** |
| Functions unit | `npm test` | **158/158** |
| Functions emulator | `npm run test:emulator` | **23/23** (after fixing the backup-token defect and the flaky seeding) |
| Rules emulator | `cd firestore-tests && npm test` | **347/347** |
| Tool tests | `node --test "tool/test/*.test.mjs"` | **30/30** |
| Audits | `npm audit` (Functions all and prod; `firestore-tests`) | **0 / 0 / 0** |
| Android gates | `bash tool/test_android_gates.sh` | **13/13 PASS** |
| Android builds | `bash tool/test_android_gates.sh --full` | **10/10 PASS** (details below) |
| Config validator (repo) | `node tool/check_firebase_config.mjs --live` | Exit 1 as expected: 19 pass, 2 warn, 16 fail, **all owner-side** (X-5, iOS plist and entitlements, iOS Maps key file) |
| iOS build | — | **BLOCKED**: no Mac or Xcode |
| Android build of the repo itself | — | **BLOCKED by design** (X-5 gate) until the app is registered |

**Android gate cases (13):**
- a debug build needs no signing material;
- a debug build without a Maps key still builds, and warns;
- release APK and AAB without `key.properties` stop;
- a missing `storePassword` stops; a missing `keyPassword` stops;
- a bad keystore path stops;
- a missing Maps key stops a release;
- a complete config passes;
- the repo's `google-services.json` stops the build (X-5);
- a malformed config stops the build;
- the app code has no emulator endpoints.

**Android full-build checks (10):**
- a real debug APK builds without signing material;
- the test-key release APK builds;
- its signer is the test key, and not the debug key;
- `apksigner verify` passes;
- the package is `com.touchgrass.app`, version 1 / 1.0.0, not debuggable;
- no Crashlytics mapping upload ran;
- the password was never printed.

**Run note:** the full-build run's 12 gate failures were all exit 127, caused by a harness bug: the Gradle wrapper is git-ignored, so it wasn't in the copy. After the fix, the gate cases were re-run (13/13). The full-build checks come from the run before the fix; the build configuration didn't change in between.

## 8. Remaining critical and high risks

1. **CRITICAL, live: cross-user photo access (B12).** Fix ready: S-1. Also a privacy-policy mismatch (M-1); notification duty is a legal question for the owner.
2. **HIGH, live: old Firestore rules.** Username takeover, spoofable leaderboard, XP bounds of +4000 per write, arbitrary photo URLs. Fixed by the coordinated R-1 + S-2 + H-1 release.
3. **HIGH: no composite indexes (B13).** I-1 is ready.
4. **HIGH: X-5 / X-6.** No Firebase apps for `com.touchgrass.app`; no upload key.
5. **HIGH: `deleteAccount` not deployed**, while the app promises deletion (M-2).
6. **HIGH (iOS):** never built; entitlements, plist and signing missing; Sign in with Apple token revocation on deletion is missing (B14, owner to verify Apple's requirement).
7. **MEDIUM: one shared Maps key** across three platforms (X-4).
8. **MEDIUM:** no Firestore backups or PITR; delete protection off (owner decision, paid).

## 9. Owner actions, in priority order

1. ⚠️ Authorize and deploy **S-1**, the interim Storage rules (runbook §5.2). Then run the smoke test (§5.4).
2. ⚠️ Authorize and deploy **I-1**, the indexes (§5.3).
3. Register the apps, add fingerprints, run `flutterfire configure`, and re-run the validator with `--live` (§1).
4. Create and back up the upload key and `key.properties` (§2). Build and verify (§3).
5. Create per-platform Maps keys; then restrict `#97425825` to the web (§9).
6. ⚠️ Deploy **F-1** `deleteAccount` by name only (§6), then run the two-account test (§8).
7. ⚠️ Run the coordinated window **R-1 + S-2 + H-1** (§5.5).
8. Resolve the privacy draft's [OWNER] items; publish the policy and store forms (§10).
9. iOS on a Mac (§11), including the Apple token-revocation decision.
10. ⚠️ Authorize the read-only photo and profile inventories (§7).
11. Decide on Firestore PITR, backups and delete protection (paid).

## 10. Confirmations

| Item | Status |
|---|---|
| Production operations performed | **None.** Read-only commands only (§4). |
| Commits / pushes / branch changes | **None** |
| AI verification | Still disabled (`AI_VERIFICATION_ENABLED = false`; nothing deployed) |
| `DOCUMENTATION.md` | SHA-256 `baa43787…a9f94bc` before and after |
| Earlier phases' work | Preserved. 148 → 162 status entries: 13 new or modified Phase 7A paths, plus the IDE's `.vscode/settings.json`. Other edits are inside paths that were already listed. |
