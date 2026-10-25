# Phase 7G — Final Report

**Date:** 2026-10-21. Branch `release-hardening-pass`, HEAD `67c5a38`.

## 1. Overall status

**Contained at rules level; partially remediated (locally). The incident is NOT closed and TouchGrass is NOT release-ready.**

All remaining mandatory steps need production credentials (none on this machine), explicit production approvals, a Mac, or owner decisions. See `PHASE_7G_RELEASE_READINESS.md` for the dependency graph and approval queue.

## 2. AI-verification UI copy (user-approved removal)

| Removed (exact) | Replaced with |
|---|---|
| Camera caption-step banner **"AI verification — Coming soon!"** | **"Photo added · Add a note, then save it to your Journal"** |
| Its screen-reader label **"AI verification is a premium feature, coming soon. Your adventure was accepted."** | The same new text |
| Button **"Share Adventure"** (it saves privately) | **"Save to Journal"** |
| Stored and displayed completion reason **"Honor-system approved — AI verification is a premium feature."** / **"Auto-approved — AI verification not configured."** under "Verification" | **"Completed on the honor system with your photo."** under "Completion". Legacy completions show the new line too. |
| Journal badge **"🤖 AI Verified"** (legacy entries) | **"✓ Verified"** |
| Unused widget `AiFeatureLockedCard` ("AI Verification — Coming Soon") | Deleted |

**Tests added:**
- `test/core/ai_copy_regression_test.dart` (9): a scan of every string literal in `lib/`, a scanner self-check, the caption copy, Challenge-details mapping for new, legacy and AI-checked results, the Firestore payload;
- updated `camera_providers_test.dart` and `adventure_memory_model_test.dart`.

**AI stays disabled:** client, deploy manifest and web bundle (§17). Details: `PHASE_7G_AI_COPY_AUDIT.md`.

## 3. Dry-run safety audit

**Every operator dry-run is proven read-only locally:**
- mutation-trapping fakes for all commands through the real dispatch, plus an `--execute` control that the trap catches (15 tests);
- an emulator snapshot of every Firestore document's update time and every object's generation and metageneration across all six dry-run variants.

**New guards:**
- a central `--mode read-only|test-object-mutation|production-mutation`;
- an exact allowlist (`touchgrass-today` ↔ `touchgrass-today.firebasestorage.app`);
- `demo-` ids on the emulators;
- refusal of mixed emulator environments and a conflicting `GCLOUD_PROJECT`;
- `--out` only to new files under `ops-out/`;
- no echo of file contents in errors;
- field masks for the profile inventory and orphan checks.

Details: `PHASE_7G_DRY_RUN_SAFETY_AUDIT.md`.

## 4. Production access and credentials

- **Google Cloud CLI:** not installed (PATH and the standard install locations were checked).
- **ADC:** absent (`%APPDATA%\gcloud\application_default_credentials.json` doesn't exist). `GOOGLE_APPLICATION_CREDENTIALS` is not set.
- No production command was run in 7G, not even read-only.

## 5. Inventory (AC-1)

**Not run** (no credentials). The command, scope and the aggregates to share back are in `PHASE_7G_TOKEN_ROTATION_RUNBOOK.md`.

## 6. Token invalidation (AC-2)

**Unproven in production.** The harness is rehearsed on the emulators every run:
- rewrite removal → `revoked`;
- the emulator's merging metadata patch → `not-revoked`. No false success.

Production setup and cleanup now require `--mode test-object-mutation`.

## 7. Challenge-link rotation (AC-3)

**Legacy links not remediated.** The staged plan (25 → 250 → the rest) and stop rules are in the runbook.

## 8. Historical GPS and metadata

**Not assessed; not remediated.**
- Every upload path is re-verified to strip first.
- Fixtures added: EXIF thumbnail, PNG data after `IEND`, rotated avatar, HEIC refused, large rotated photo.
- AC-4/AC-5 commands: `PHASE_7G_HISTORICAL_METADATA_RUNBOOK.md`.

## 9. Account deletion

**Fixed locally; not verified in production.**
- **New in 7G:** a `deletedAccounts/{uid}` marker (timestamps only) is written before the profile is deleted.
- **Deploy scope re-verified after the change:** one endpoint, no params, no required APIs.
- **Partial-deletion recovery** is designed. The contact policy is an owner/legal decision.

Details: `PHASE_7G_ACCOUNT_DELETION_VALIDATION.md`.

## 10. Late-upload protection

**Fixed locally:**
- final Storage rules require the profile;
- **new:** final Firestore rules refuse profile re-creation for a marked uid, which closes the 7F residual case.

The full race is tested: upload OK → deletion → upload DENY → re-creation DENY → upload DENY, with other users unaffected.

## 11. Storage rules and the required permission

- **Not deployed.** The live rules are still the interim rules.
- **Exact permission:** `roles/firebaserules.firestoreServiceAgent` for `service-760620662222@gcp-sa-firebasestorage.iam.gserviceaccount.com`, at project level.
- **Deploy behaviour:** `--force` auto-grants it; `--non-interactive` skips it, so uploads fail closed.

Two separate approvals: AC-7a (deploy) and AC-7b (grant). Details: `PHASE_7G_STORAGE_RULES_DEPLOYMENT.md`.

## 12. Firebase app registrations

**Mismatch open.**
- Android `applicationId` and iOS bundle are both `com.touchgrass.app` (the iOS id was verified in `project.pbxproj`).
- The registered apps are `com.example.touchgrass`.
- The iOS plist is missing.

Commands for AC-8: `PHASE_7G_FIREBASE_ENVIRONMENT_PLAN.md` §3.

## 13. Android signing and build

- **Signing:** not configured (owner; `PHASE_7F_ANDROID_SIGNING_GUIDE.md`).
- **Gates:** 13/13.
- **Full release build:** not run (it needs AC-8 and signing).

## 14. iOS

**Explicitly blocked:** no macOS or Xcode. The checklist is unchanged and current: `PHASE_7F_FIREBASE_PLATFORM_CONFIGURATION.md` §4.

## 15. Development/production separation

**One project; plan prepared (AC-9).** Operator-tool safeguards are in place. `.firebaserc` still defaults to production; removing that default is recommended as an owner workflow change.

## 16. Privacy and store disclosures

**Corrected locally:**
- the AI copy;
- the deletion-exceptions sentence, which now discloses the deleted-account record, with a test.

**Open:**
- D1 and D11 (after remediation);
- D3/D14 (after deployment);
- D15–D17 and D19 (owner/legal);
- **new D20:** the live app can send photos to Gemini; past processing may need disclosure (owner/legal).

Nothing published. Table: `PHASE_7G_RELEASE_READINESS.md` §3.

## 17. Tests run in this phase (actual results)

| Suite | Command | Result |
|---|---|---|
| Dart format | `dart format --output=none --set-exit-if-changed lib test` | 161 files, 0 changed, exit 0 |
| Flutter analyze | `flutter analyze` | No issues, exit 0 |
| Flutter tests | `flutter test` | **499/499**, exit 0 |
| Functions type check / lint | `npx tsc --noEmit -p .` / `npm run lint` | Clean / 0 problems |
| Functions unit | `npm test` | **232/232**, exit 0 |
| Functions emulator | `npm run test:emulator` | **48/48**, exit 0 |
| Rules (Firestore + Storage, final/interim parity) | `firestore-tests: npm test` | **581/581**, exit 0 |
| Tool tests | `node --test tool/test/*.test.mjs` | 30/30 |
| Android gates | `bash tool/test_android_gates.sh` | 13/13, exit 0 |
| Deploy manifest | local `firebase-functions` discovery | 1 endpoint (`deleteAccount`), no params, `requiredAPIs: []` |
| Web release + bundle scan | `flutter build web --release -o <scratchpad>` (no `secrets.json`; `build/web` untouched) + `tool/check_web_bundle_secrets.mjs` + greps | see §17a |
| npm audit | functions production / all; firestore-tests | 0 / 0 / 0 |

### 17a. Web release bundle (final code)

- **Build:** exit 0.
- **`check_web_bundle_secrets.mjs`:** "No secrets found in 17 text files", exit 0.
- **0 matches for:**
  - `gemini`, `generativelanguage`, `AQ.`-style keys and private-key markers;
  - the removed copy ("AI verification — Coming soon", "AI verification is a premium", "premium feature", "Share Adventure").
- **Present:** "Save to Journal", "Completed on the honor system", "record that the account was".
- **Keys:** exactly 2 public keys, the same hashes as 7F (`943c870ac547` Firebase web key, `974258259a37` Maps JS key in `index.html`; restrict the latter by referrer, B5).

**Runs not counted above:** one Functions emulator run had a failure that was fixed:
- the new all-commands snapshot test hit `ECONNRESET` on its final listing read (an idle socket);
- the read now retries on connection errors; the assertion is unchanged.

The rerun is the 48/48 above.

**Not run:** any production check; Android `--full` and release build; iOS.

## 18. Production operations

- **Performed:** none.
- **Not performed:** everything in the approval queue (AC-1…AC-10), G-AV (the leftover avatar), PD-1, and any change to Auth, billing, Maps or AI.

## 19. Remaining risks and release blockers

1. Old challenge-photo links still open photos without sign-in.
2. Historical GPS is unknown.
3. Live account deletion is broken; some users may be partially deleted.
4. App registrations are wrong; no signing; no Android release or iOS build.
5. The live web app still shows the old AI copy and can send photos to Gemini until H-1.
6. Dev and prod share one project.
7. Disclosure decisions D15–D17, D19, D20.
8. Deleted-account marker retention (TTL) is an owner decision.
9. One leftover test avatar.

## 20. Next exact operation requiring approval

**Precondition (owner, own terminal):**
- install the Google Cloud CLI;
- run `gcloud auth application-default login`;
- run `cd functions && npm ci && npm run build && npm test`.

**Then AC-1:**

```
node lib/ops/opsCli.js photo-token-rotate --project touchgrass-today --real-project --out ../ops-out/rotation/dry-1.json --max 1000
```

| | |
|---|---|
| Reads | Object names and metadata under `completion_photos/`; the `photoUrl` field of each reached owner's completions and Journal entries |
| Photo bytes | None |
| Writes | **Nothing in production**; one new owner-only file under git-ignored `ops-out/` |
| Cost | Under $0.01 |
| Verify | The summary shows `"operationMode": "read-only"` and bucket `touchgrass-today.firebasestorage.app` |
| Share back | Aggregates only |

Approving AC-1 does not authorize any token creation, revocation or rotation.

## 21. Git and protected files

- Branch `release-hardening-pass`, HEAD `67c5a38`, 0 stashes; no commit, push, reset, clean, stash, rebase or amend.
- **Every Git status entry from the start of 7G is still present** (compared at the end).
- **Deleted:** `lib/widgets/ai_feature_locked_card.dart`, an unused widget containing only the obsolete copy. It shows as a deletion; a backup is in the scratchpad (`p7g/bak/`).
- `DOCUMENTATION.md` SHA-256 `baa43787aad0a31987f3c894db09c67df4cfe05650d56d813027cbb62a9f94bc`: unchanged.
- `.vscode/settings.json` `4c877983…`: unchanged.
- `deploy/interim/storage.interim.rules` (the live file) `630dc9a0…`: unchanged.
