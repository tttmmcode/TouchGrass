# Phase 7F — Final Report

**Date:** 2026-10-21. Branch `release-hardening-pass`, HEAD `67c5a38`.

## 1. Overall status

**Contained, partially remediated (locally). The incident is NOT closed and TouchGrass is NOT release-ready.**

- The production blocker for every Phase B–D operation is the same: this machine has no Google Cloud credentials for the operator tools. `gcloud` isn't installed and no Application Default Credentials exist; that was an existence check only.
- So no inventory, experiment, rotation or remediation could run, and none was attempted.

## 2. Live Storage-rules verification (read-only, 2026-10-21)

- **Storage:** `630dc9a0…dcff17`, released **2026-10-20T04:30:20Z**. **Byte-identical** to `deploy/interim/storage.interim.rules`. No release since.
- **Firestore:** `eb6b6b1c…d0edc2` (= HEAD), released 2026-08-13.
- **Functions:** none.
- **Apps:** unchanged (four registrations).

Method: firebase-tools' own GET-only Rules API helpers under the account the CLI is already signed into, plus `firebase functions:list` and `firebase apps:list`. Details: `PHASE_7F_PRODUCTION_SECURITY_STATUS.md`.

## 3. Production smoke test

**Not re-run in 7F** (it would be a new production operation). The 7E live run (**32/32**, 2026-10-20 05:26Z) tested the rules that are still live byte for byte. Its T1 finding stands: an existing token URL opens without sign-in.

## 4. Read-only inventory (AC-2)

**Not run: no ADC.** The audit found and fixed, locally, **a dry-run that wasn't read-only**:
- the CLI wrote the `_ops/photoRewrite_lease` lease document even without `--execute`;
- the same was true of the `orphan-photos` and remediation dry-runs.

**Also fixed:**
- reference queries now read only `photoUrl`;
- foreign buckets and the look-alike project are refused;
- a capped dry-run can resume;
- link anomalies are reported.

Details: `PHASE_7F_TOKEN_ROTATION_RESULTS.md` §1.

## 5. Token-invalidation experiment (AC-3)

**Not run.** A scripted, cleanup-complete experiment harness now exists (`functions/src/ops/revocationExperiment.ts`). It uses the real rotation CLI for the token steps and was rehearsed end to end on the emulators:
- rewrite removal → verdict **revoked**;
- metadata removal, which the emulator merges → tool `verify-failed`, harness **not-revoked**. No false success.

**Production behaviour remains unproven.**

## 6. Challenge-link rotation

**Legacy links not remediated.** No production link was rotated. The staged plan (25 → 250 → the rest, with stop conditions) is in `PHASE_7F_TOKEN_ROTATION_RESULTS.md` §3.

## 7. Historical GPS

**Historical metadata not assessed and not remediated.**
- **New uploads:** a single upload boundary strips metadata on every path (audited in 7F).
- **Avatars at HEAD:** re-encoded from pixels, so no metadata. Older builds weren't checked.
- **Inventory scope and commands:** `PHASE_7F_HISTORICAL_METADATA_REMEDIATION.md`.

## 8. Account deletion

**Account deletion fixed locally; not verified in production** (no function deployed).
- **Deploy graph proven locally:** the manifest discovery firebase-tools uses lists **exactly `deleteAccount`**, with no params or secrets and no required APIs.
- **Semantics:** every brief item is mapped to tests.
- **Partial deletions:** the signature and recovery plan are designed.

Details: `PHASE_7F_ACCOUNT_DELETION_VALIDATION.md`.

## 9. Late-upload mitigation

**Decision: Option A.** Uploads require `users/{uid}`, implemented in the **final** `storage.rules` (`hasProfile()`, evaluated last) and tested.
- **Option B rejected:** a scheduled sweep is more infrastructure and cost, and risks false positives.
- **Not live:** it ships with S-2, and the first deploy grants Storage's service agent Firestore read access.
- **Residual case documented:** `PHASE_7F_LATE_UPLOAD_MITIGATION.md`.

## 10. Android and iOS Firebase configuration

**Mismatch open.** Both registrations are `com.example.touchgrass`; the app is `com.touchgrass.app`, and `GoogleService-Info.plist` is absent. Exact `apps:create` commands for approval G-1: `PHASE_7F_FIREBASE_PLATFORM_CONFIGURATION.md`.

## 11. Android signing and build

- **Signing:** not configured (owner steps in `PHASE_7F_ANDROID_SIGNING_GUIDE.md`; nothing generated or requested).
- **Build gates:** **13/13 PASS**. Correction: 7E reported "14/14", but its own log says 13 passed. The gate list is unchanged; the 7E figure was a miscount.
- **Release build:** not possible until G-1 and signing.

## 12. iOS

**Not built and not validated:** no macOS or Xcode here. Mac checklist: `PHASE_7F_FIREBASE_PLATFORM_CONFIGURATION.md` §4.

## 13. Test results from this run (actual counts and exit codes)

| Suite | Command | Result |
|---|---|---|
| Dart format | `dart format --output=none --set-exit-if-changed lib test` | 0 of 160 changed, exit 0 |
| Flutter analyze | `flutter analyze` | No issues, exit 0 |
| Flutter tests | `flutter test` | **484/484**, exit 0 |
| Functions type check | `npx tsc --noEmit -p .` | Clean |
| Functions lint | `npm run lint` | 0 problems |
| Functions unit | `npm test` | **216/216**, exit 0 (208 + 8 new) |
| Functions emulator | `npm run test:emulator` | **46/46**, exit 0 (43 + 3 new: CLI dry-run writes nothing; experiment rehearsal ×2) |
| Rules emulator | `firestore-tests: npm test` | **576/576**, exit 0 (569 + 7 new: P71–P73 × 2 rulesets, `hasProfile` static guard) |
| Tool tests | `node --test tool/test/*.test.mjs` | **30/30** |
| Android gates | `bash tool/test_android_gates.sh` | **13/13 PASS**, exit 0 |
| Web release | `flutter build web --release -o <scratchpad>` (no `secrets.json`; `build/web` untouched) | exit 0 |
| Web bundle scan | `node tool/check_web_bundle_secrets.mjs <build>` + greps | No secrets, exit 0. 0 hits for `gemini`, `generativelanguage`, `AQ.` keys and private keys. 2 public keys, the same as 7E: the Firebase web key and the Maps JS key in `index.html` (restrict by referrer, B5). |
| Deploy manifest | local `firebase-functions` discovery | 1 endpoint (`deleteAccount`), no params, `requiredAPIs: []` |
| npm audit | functions production / all; firestore-tests | 0 / 0 / 0 |

**Run but not counted above:**
- an earlier Functions emulator run (44/44, before the harness);
- two failing runs, both fixed:
  - **rules P73:** my new case used a name the interim rules legitimately allow, so it now uses `.jpeg`;
  - **rehearsal:** the probe's signed-in read hit the emulator's deny-all placeholder rules, so the test now loads the live interim rules.

**Not run:** iOS build (no Mac); Android `--full` and release build (blocked by G-1 and signing); any production test.

## 14. Production operations performed

Read-only only:
- Rules API releases list and two ruleset reads;
- `firebase functions:list`;
- `firebase apps:list`.

## 15. Production operations not performed

- **Photos and links:** AC-2 dry-run; AC-3a/b experiment; AC-4 rotation; M-1 inventory; M-3…M-6 remediation; any backup.
- **Deploys:** F-1 Functions; H-1 Hosting; R-1 or S-2 rules; I-1 indexes.
- **Configuration:** G-1 app registrations or SHA fingerprints.
- **Data and cleanup:** deleting the leftover test avatar (G-AV); the partial-deletion audit; any cleanup job; any user-record change.
- **Publication:** policy, Terms or store listing.
- **Accounts and services:** Auth, billing, Maps or AI changes.
- **Git:** no commit or push.

## 16. Outstanding risks and release blockers

1. Old challenge-photo links still open photos without sign-in.
2. Historical GPS is unknown.
3. Live account deletion is broken, and some users may be partially deleted.
4. Firebase app registrations are mismatched.
5. No Android signing; no Android or iOS release build.
6. Disclosures D1, D3/D14 and D11 depend on 1–3. D15–D19 need owner or legal decisions, including the new D18: the "AI verification — Coming soon!" camera copy.
7. One Firebase project serves both development and production.
8. One leftover 1×1 test avatar.

Full gate list: `PHASE_7F_RELEASE_READINESS.md`.

## 17. Next exact operation requiring approval

**Precondition (owner, in your own terminal):** `gcloud auth application-default login`.

**Then AC-2, the read-only rotation dry-run.** From `functions/`, after `npm ci && npm run build`:

```
node lib/ops/opsCli.js photo-token-rotate --project touchgrass-today --real-project --out ../ops-out/rotation/dry-1.json --max 1000
```

| | |
|---|---|
| Reads | Object names and metadata under `completion_photos/` (token lists held in memory only); the `photoUrl` field of each reached owner's `completions` and `users/{uid}/memories` |
| Photo bytes | None |
| Writes | **Nothing in production** (no lease since 7F); one 0600 local file under git-ignored `ops-out/` |
| Cost | Under $0.01 for ≤1000 photos |
| Verification | The summary shows the project and bucket, counts, `limitReached` and `referenceAnomalies` |

## 18. Git status and preservation

- Branch `release-hardening-pass`, HEAD `67c5a38`, 0 stashes; nothing committed, pushed, reset, cleaned, stashed or amended.
- Every Git status entry from the start of 7F is still present.
- **New untracked:** 9 `PHASE_7F_*.md` files (8 before this report) and `functions/src/ops/revocationExperiment.ts`.
- **Modified** (all already modified or untracked before 7F; backups in scratchpad `p7f/bak/`):
  - `storage.rules`;
  - `firestore-tests/test/{storage_release_parity,storage,helpers}` `.test.mjs`/`.mjs`;
  - `functions/src/ops/{photoTokenRotation,opsCli,ops7c.test,ops7c.emulator.test,testJpeg}.ts`;
  - `functions/README.md`, `KNOWN_BUGS.md`, `REMEDIATION_CHECKLIST.md`.
- **Unchanged:** `deploy/interim/storage.interim.rules` (`630dc9a0…`, the live file), `firestore.rules`, `lib/`, `test/`, the Phase 7A–7E reports, `.vscode/settings.json` (`4c877983…`).

## 19. `DOCUMENTATION.md`

SHA-256 `baa43787aad0a31987f3c894db09c67df4cfe05650d56d813027cbb62a9f94bc`, **unchanged**: identical at the start and end of 7F.
