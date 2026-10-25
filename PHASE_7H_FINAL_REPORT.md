# Phase 7H — Final Report

**Date:** 2026-10-24. Branch `release-hardening-pass`, HEAD `67c5a38`.

**Release verdict: NOT READY.** Critical blockers remain, all needing production approvals, the owner's own actions, a
Mac, or owner/legal decisions:
- old photo links still open photos without sign-in;
- historical GPS is unknown;
- the live account deletion is broken;
- the Firebase app registrations are wrong;
- there is no signing, no Android release build and no iOS build;
- the privacy decisions are open.

## 1. Initial state and preserved work

**At the start:** branch `release-hardening-pass`, HEAD `67c5a38`, 0 stashes, nothing staged, and 214 status entries
(all prior uncommitted work; the list is saved in the scratchpad).

**Protected files at start and end:**

| File | SHA-256 | Changed? |
|---|---|---|
| `DOCUMENTATION.md` | `baa43787aad0a31987f3c894db09c67df4cfe05650d56d813027cbb62a9f94bc` | No |
| `.vscode/settings.json` | `4c877983…` | No |
| `deploy/interim/storage.interim.rules` (the live file) | `630dc9a0…` | No |

**At the end:**
- No baseline status entry was removed.
- The only new top-level entries are `PHASE_7H_AC1_RUNBOOK.md` and this report. Every other new file sits inside
  directories that were already untracked: `tool/`, `firestore-tests/`, `lib/features/settings/widgets/`,
  `test/features/settings/`.
- No commit, push, stash, reset, rebase, clean or amend.

## 2. Defects found (severity · component · production risk · locally fixable)

| # | Defect | Severity | Fixed locally? |
|---|---|---|---|
| H1 | **AC-1 would have lost its results.** `ops-out/rotation/` didn't exist, and `--out` is written only after every read. Also: any folder named `ops-out` anywhere was accepted; no credential preflight; the read-only file stored object paths (with uids) it doesn't need | High (AC-1 readiness, data minimization) | Yes |
| H2 | **Stale sessions could still create data after deletion.** A deleted account's session (≤1 h) could create daily challenges, completions, Journal entries, feedback or username claims, and nothing would delete them. The marker was written only after completions, usernames and feedback were deleted | High (privacy: data surviving deletion) | Yes (rules + Function; not deployed) |
| H3 | **Node 22 hides some suite failures.** Its test runner exits 0 and reports `fail 0` when a `describe()` throws, so a whole suite can silently not run. Reproduced | High (test evidence integrity) | Yes |
| H4 | **Local dev scripts used production.** `functions` `npm run serve` / `npm run shell` used the production project; `serve` ran the Functions emulator against the REAL Firestore, Storage and Auth (a local `deleteAccount` would delete real data) | High (dev → prod) | Yes |
| H5 | **Account deletion UX:** no progress for up to 5 min, a second start possible, no success confirmation | Medium (UX, deletion clarity) | Yes |
| H6 | `body-parser` 2.3.0 (firebase-functions → express): advisory GHSA-27r3-jxmh-p828, DoS. New since 7G | High per npm; a deployed-runtime concern | Yes (lockfile only → 2.4.0) |
| H7 | Debug builds send Analytics/Performance data to production; the app always uses the production Firebase project (no emulator or dev mode) | Medium | No: needs a dev project (AC-9). On Android a second set of options conflicts with the native default app |
| H8 | No app-level iOS privacy manifest (`PrivacyInfo.xcprivacy`) | Medium (App Store) | No: needs Xcode to add to the project |
| H9 | Emulator snapshot test flaky on dropped idle sockets (reproduced once) | Low (test infra) | Yes (backoff; assertion unchanged) |

Carried over from 7G, unchanged, not locally fixable: old token links, historical GPS, live deletion, registrations,
signing, iOS, dev/prod separation, disclosures, the leftover test avatar.

**Considered, not changed:**
- **Exact content type per photo path.** The client always sends `image/jpeg` / `image/png`, but the rules also allow
  webp/heic/heif. Narrowing it would protect only against a modified client storing its own photo, and would add a
  parity difference against the live interim rules. Low value; it's recorded here for the owner.

## 3. Fixes (files)

**H1, AC-1 readiness** (`functions/src/ops/opsCli.ts`):
- `OPS_OUT_DIR`, `insideOpsOut()`: `--out` must be inside this repository's `ops-out/`.
- `credentialsRefusal()`: a missing ADC file (or a missing `GOOGLE_APPLICATION_CREDENTIALS` target) is refused before
  any client is created. The file is never read.
- The `--out` folder is created (0700) before any read.
- `forOutFile()`: the read-only rotation file keeps aggregates plus per-photo outcomes keyed by a 16-hex SHA-256 tag.
  It holds no names, uids or generations (an allowlist of entry fields).
- `safeErrorLabel()`: errors show the class plus a short code (e.g. `403`, `PERMISSION_DENIED`), never the message.

**H2, late creates after deletion:**
- `firestore.rules`: `accountNotDeleted()`, applied to every client create (`users`, `usernames`, `challenges`,
  `memories`, `completions`, `feedback`). The marker counts only until its `expiresAt` (2 h), so an abandoned failed
  deletion can't block an account forever even without a TTL policy.
- `functions/src/accountDeletion.ts`: the marker is written first, right after session revocation.

**H3, strict test runs:**
- `tool/strict_node_test.mjs`: fails on any TAP `not ok`; clears an inherited `NODE_TEST_CONTEXT`.
- Used by `functions` `test` / `test:emulator` and by `firestore-tests` `test` / `test:only`.

**H4, dev scripts:** in `functions/package.json`, `serve` and `shell` now use `--project demo-touchgrass-dev`, and
`serve` adds the firestore, storage and auth emulators.

**H5, deletion UX:**
- `lib/features/settings/widgets/account_deletion_progress.dart` (new);
- `settings_screen.dart`: overlay, `PopScope`, double-start guard, and a success message shown only in the server's `ok`
  branch;
- `privacy_copy.dart`: the new strings.

**H6:** `functions/package-lock.json` only (`body-parser` 2.4.0); `package.json` unchanged (same hash).

**H9:** `ops7c.emulator.test.ts`: retry with backoff on dropped connections.

**Docs:**
- this report;
- `PHASE_7H_AC1_RUNBOOK.md`;
- `REMEDIATION_CHECKLIST.md` (Phase 7H, P7H-1…8);
- `KNOWN_BUGS.md` (B20–B24);
- `functions/README.md`.

## 4. Tests run (actual results, this phase)

| Check | Command | Result |
|---|---|---|
| Dart format | `dart format --output=none --set-exit-if-changed lib test` | 163 files, 0 changed |
| Flutter analyze | `flutter analyze` | No issues |
| Flutter tests | `flutter test` | **503/503** (+4: deletion progress) |
| Functions type check / lint | `npx tsc --noEmit -p .` / `npm run lint` | Clean / 0 problems |
| Functions unit | `npm test` (strict) | **238/238** (+6: AC-1 readiness); rerun after the lockfile fix: 238/238 |
| Functions emulator | `npm run test:emulator` (strict) | **48/48** (rerun after the reorder and the lockfile fix) |
| Rules (Firestore + Storage) | `firestore-tests: npm test` (strict) | **598/598** (+17: creates after deletion) |
| Tool tests | `node tool/strict_node_test.mjs "tool/test/*.test.mjs"` | **40/40** (+10: strict wrapper, dev safety) |
| Android gates | `bash tool/test_android_gates.sh` | 13/13 |
| Deploy manifest | local `firebase-functions` discovery | 1 endpoint: `deleteAccount` (gcfv2, us-central1, callable, 300 s); no params; `requiredAPIs: []` |
| Web release + scan | see §4a | see §4a |
| npm audit | functions production / all; firestore-tests | see §4a |

**Runs not counted above:**
- **Rules, first run:** reported 581/581 with exit 0 although my new suite had failed while being built. That is how
  H3 was found. After the wrapper: 598/598.
- **Functions emulator:** one run failed on "socket hang up" in the snapshot read (H9). The rerun is above.
- **Tool tests, first run of the new wrapper test:** 2 failures from an inherited `NODE_TEST_CONTEXT`. Fixed in the
  wrapper.
- **Functions audit at the start of the final pass:** 1 high (H6), fixed.

**Earlier evidence:** apart from my new suite, no other `not ok` appears in any current log. So the 7G counts were not
hiding a broken suite, as of today's code.

### 4a. Web release bundle and dependency audit (final code)

- **Build:** `flutter build web --release -o <scratchpad>`, with no `secrets.json`; `build/web` was not touched.
  Exit 0.
- **`tool/check_web_bundle_secrets.mjs`:** "No secrets found in 17 text files", exit 0.
- **Keys:** exactly 2 distinct `AIza…` keys, with the same hashes as 7F/7G: `943c870ac547` (Firebase web) and
  `974258259a37` (Maps JS).
- **0 files contain:**
  - `generativelanguage`;
  - private-key markers;
  - "AI verification — Coming soon", "AI verification is a premium", "premium feature", "Share Adventure".
- **"gemini" (case-insensitive):** 0 text files. It matches 5 CanvasKit `.wasm` binaries, but only inside the byte run
  "langua**ge mini**sters", part of the built-in Brotli compression dictionary in Flutter's Skia engine.
  `canvaskit.wasm` is byte-identical (SHA-256 prefix `6bdfaa51c76845c0`) to the stock Flutter 3.44.1 SDK copy. Not an
  AI reference; 7G's grep covered text files only.
- **Present:** "Save to Journal", "Completed on the honor system", "record that the account was", "Deleting your
  account", "Your account and the data saved with it were deleted".
- **npm audit** (after the H6 lockfile fix): functions production 0, functions all 0, firestore-tests production 0,
  firestore-tests all 0.

**What the live web app does is not verified here.** 7G found the Gemini endpoint and inline image payloads in the
deployed bundle. This local build contains no Gemini client code; that changes only when the new build is deployed
(an approval).

## 5. Regressions or unresolved failures

None remaining.

## 6. AC-1 status: **NOT RUN (blocked)**

- **Installed:** the Google Cloud CLI (SDK 590.0.0). The active account equals the Firebase CLI account (by hash), and
  the configured project is `touchgrass-today`.
- **Missing:** Application Default Credentials. `%APPDATA%\gcloud\application_default_credentials.json` doesn't exist
  and `GOOGLE_APPLICATION_CREDENTIALS` is unset.
- **Readiness:** not confirmed by the owner.
- **Next:** the owner steps and the exact command are in `PHASE_7H_AC1_RUNBOOK.md`. Before any real run, the
  command's read-only guarantee, allowlist, output location and credential preflight were re-verified in code and
  tests (§3, §4).

## 7. Inventory findings

None (not run).

## 8. Production operations deliberately not performed

AC-1 is authorized but blocked. Not performed: AC-2…AC-10, G-AV, PD-1, and every other operation:
- any rules, Functions or Hosting deploy;
- the Storage→Firestore IAM grant;
- any token or link change;
- any metadata inventory or rewrite;
- app registration;
- any Auth, billing, Maps or AI change;
- user-record repair or cleanup;
- deleting the test avatar;
- dev-project migration;
- any publication.

No production command was run in 7H. The only cloud-related commands were local gcloud configuration reads
(`--version`, `config get-value project`, `auth list` hashed).

## 9. Decisions still required (owner/legal)

- **D20:** whether to disclose that the live web app could send photos to Google Gemini. Whether photos were actually
  sent hasn't been verified, and the live app is unchanged until a new web build is deployed.
- **D15–D17, D19:**
  - the user-count claim;
  - retention periods;
  - whether to notify users about the past photo-link exposure;
  - the Terms wording on photo sharing.
- **Deleted-account marker:**
  - retention: whether to configure a Firestore TTL policy on `deletedAccounts.expiresAt`. Without it, markers persist
    (the rules ignore them after 2 h);
  - whether the policy text "a record that the account was deleted (its internal ID and the time)" is the wording you
    want.
- **Support contact:** confirm `support@touchgrass.app` is a monitored mailbox (shown in deletion errors and Help).
- **Partially deleted accounts:** the recovery/contact policy for accounts the old web app partly deleted.
- **Dev/prod separation (AC-9):** a separate dev project. Also, whether debug builds should stop sending Analytics and
  Performance data to production.

## 10. Android blockers

- The Firebase app is registered as `com.example.touchgrass`; the app is `com.touchgrass.app` (AC-8, owner).
- No `android/key.properties` or keystore (owner; `PHASE_7F_ANDROID_SIGNING_GUIDE.md`). No signing files are tracked.
- So there is no signed release build yet, and no device test.

## 11. iOS blockers

- No macOS/Xcode here.
- `GoogleService-Info.plist` is missing (registration AC-8).
- No app-level `PrivacyInfo.xcprivacy` (H8).
- Signing.
- **Not validated in any way.**

## 12. Web blockers

- The live web app is the old build: old AI copy, possible Gemini processing, the broken deletion flow.
- The final rules must ship together with the new web build and the `deleteAccount` deploy (AC-5…AC-7). The final
  Storage rules need the IAM grant (AC-7b).
- The Maps JS key needs a referrer restriction (B5).

## 13. Prioritized next steps

1. **Owner:** `gcloud auth application-default login`, then tell me you're ready (AC-1 runbook §1).
2. **Me, under the AC-1 approval:** pre-run checks (runbook §2), then the inventory. Aggregates only, reported back.
3. **Owner approval:** AC-2, the revocation experiment on the test account. Its result decides the rotation method.
4. **Owner approvals:** deploy `deleteAccount` + the final Firestore rules + the new web build together; then the final
   Storage rules with the IAM grant (separate approvals).
5. **Owner approvals:** staged rotation (AC-3); metadata inventory/remediation (AC-4/5); the test avatar (G-AV).
6. **Owner:** register `com.touchgrass.app` (Android/iOS), signing, and a Mac for the iOS build and privacy manifest.
7. **Owner/legal:** the decisions in §9; store listings and policies.

## 14. Verdict

**NOT READY.** Nothing here makes it eligible for limited external testing yet: the live app still has the photo-link
exposure and broken deletion, and no mobile build can be produced.
