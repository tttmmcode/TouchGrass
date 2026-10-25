# Phase 7E — Final Report: Incident Remediation & Release Readiness

**Date:** 2026-10-20

## 1. Status (7E vocabulary)

| Area | Status |
|---|---|
| Storage rules | **Contained at rules level**, verified LIVE (S1–S9 smoke test, 32/32) |
| Legacy challenge-photo links | **Not remediated.** LIVE: an existing token URL opens a photo without sign-in. |
| Historical metadata | **Not assessed / not remediated** |
| Account deletion | **Fixed locally.** Production is unchanged; the live app still can't delete accounts. |
| Release | **Not release ready** |

## 2. Stage 1: state and documents

- Branch `release-hardening-pass`, HEAD `67c5a38`, no stash.
- Git status (222 entries) identical to the end of 7D.
- `DOCUMENTATION.md` `baa43787…94bc`.
- Live state re-verified read-only at 05:01Z: Storage = interim (`630dc9a0…`), Firestore `eb6b6b1c…`, no functions.

**Discrepancies found:**
1. **`PHASE_7D_ACCOUNT_DELETION_REMEDIATION.md` §7 says the AI function "is not exported for deployment". It was exported from `functions/src/index.ts`.** Worse, a by-name `deleteAccount` deploy would still have demanded its secret (§5, D-2). Fixed in code; the 7D doc is preserved unedited and corrected here.
2. The 7A manifest's "deploy by name" guidance is insufficient for the same reason.
3. Phase 7D recorded only the **Android** Firebase app as `com.example.touchgrass`. The **iOS** app is too (read-only `apps:sdkconfig`).

## 3. Production operations

| | Operation | Scope / evidence |
|---|---|---|
| **Performed (authorized)** | S1–S9 live Storage smoke test, 05:26:05–05:26:16Z | 2 dedicated test accounts (self-deleted afterwards), synthetic objects (deleted), **one 1×1 test avatar left** (clients can't delete avatars). No Firestore writes; no real user data. |
| Read-only | Rules exports (05:01Z); `functions:list`; `apps:sdkconfig` (identifiers only); `apps:android:sha:list` | — |
| **Not performed** | Rotation dry-run or rotation; revocation experiment; historical inventory or remediation; backups; any deploy (rules, indexes, functions, hosting); app registrations; publication; cleanup jobs; billing, Auth, Maps or AI changes; commit or push | — |

## 4. Test results (this run; actual counts and exit codes)

| Category | Suite | Result |
|---|---|---|
| **LIVE** | S1–S9 smoke test (`PHASE_7E_PRODUCTION_SMOKE_TEST_RESULTS.md`) | **32/32** as expected; T1 token URL **HTTP 200** without sign-in |
| Rehearsal | The same script on emulators (interim rules) | 32/32 |
| Static | `dart format --set-exit-if-changed lib test` | Exit 0 (0 of 160 changed) |
| Static | `flutter analyze` | No issues, exit 0 |
| Static | Functions `tsc --noEmit`, `npm run lint` | OK / 0 problems |
| Unit | `flutter test` | **484/484**, exit 0 |
| Unit | Functions `npm test` (incl. rotation, metadata tool, deletion, **entry point**) | **208/208**, exit 0 |
| Unit | `node --test tool/test/*.test.mjs` | **30/30** |
| Emulator | Rules `firestore-tests npm test` (final/interim parity, matrix, config gate) | **569/569**, exit 0 |
| Emulator | Functions `npm run test:emulator` (deletion, rotation, metadata), run twice | **43/43**, exit 0 (both runs) |
| Build | Android gates `tool/test_android_gates.sh` (temporary copy) | **14/14** PASS, exit 0 (`--full` not run: needs a `com.touchgrass.app` config) |
| Build | Web release into the scratchpad (no `secrets.json`; `build/web` untouched) | Exit 0. Bundle scan: one `AIza…` key = the public Firebase web key (hash-matched); no Gemini or `generativelanguage`; no private-key material. |
| Deps | `npm audit` functions (production / all), firestore-tests | 0 / 0 / 0 |
| **Not run** | iOS build (no macOS); Android `--full` | Blocked (§6) |

## 5. Findings fixed locally

| # | Finding | Fix | Evidence |
|---|---|---|---|
| D-1 | The rotation dry-run didn't report photos without owner links or with stale links, or predicted writes | `photosWithoutReferences`, `photosWithStaleReferences`, `writes` | unit |
| D-2 | The revocation experiment needs a pause between "links moved" and "old token removed" | `--stop-before-remove` (`awaiting-removal`, resumable) | unit |
| D-3 | **`deploy --only functions:deleteAccount` would have prompted for and created the `GEMINI_API_KEY` secret** (or failed), and enabled Secret Manager. firebase-tools resolves every declared param, and enables APIs for every function, before applying `--only` (15.19.1 `prepare.js`). | The AI callable moved unchanged to `functions/src/aiVerification.ts`, not imported by `index.ts`; `entryPoint.test.ts` pins "exports only `deleteAccount`, declares no params"; README updated. AI stays disabled. | unit; `lib/index.js` contains 0 `defineSecret` |
| D-4 | Deletion coverage for data shapes and late failures | 0/1/3 completions × with/without photos; second-sweep failure keeps the Auth user and the retry finishes | emulator |

**Files changed in 7E** (backups in scratchpad `p7e/bak/`):
- `functions/src/index.ts`, `functions/src/aiVerification.ts` (new), `functions/src/entryPoint.test.ts` (new), `functions/src/rewards.test.ts` (path only), `functions/src/ops/photoTokenRotation.ts`, `functions/src/ops/opsCli.ts`, `functions/src/ops/ops7c.test.ts`, `functions/src/accountDeletion.emulator.test.ts`, `functions/package.json` (test list), `functions/README.md`;
- `REMEDIATION_CHECKLIST.md`, `KNOWN_BUGS.md`;
- 7 `PHASE_7E_*.md` files.

**Unchanged:** `lib/`, `test/`, rules files, `firebase.json`, `DOCUMENTATION.md`, `.vscode/settings.json`, and the Phase 7A–7D reports.

## 6. Outstanding blockers and risks

| # | Item | Needs |
|---|---|---|
| 1 | Legacy links valid (LIVE T1) | Owner ADC, then AC-2 dry-run → AC-3 experiment → AC-4 rotation |
| 2 | Historical GPS | M-1 inventory → M-3…M-6 (after rotation) |
| 3 | Live account deletion impossible; some users may be partially deleted | F-1 + coordinated I-1/R-1/S-2/H-1 + the two-account test |
| 4 | ≤1 h post-deletion upload window | Owner decision (rules cross-check or sweep) |
| 5 | Firebase Android **and iOS** apps registered as `com.example.touchgrass` | Authorized `apps:create` (`PHASE_7E_ANDROID_RELEASE_READINESS.md` §3) |
| 6 | Android release signing, Play App Signing | Owner (§4 there) |
| 7 | iOS not validated | A Mac (§5 there) |
| 8 | Disclosures depend on 1–3 | Publication only after the gates (`PHASE_7E_RELEASE_GATE_CHECKLIST.md` §6) |
| 9 | Leftover test avatar | Optional console deletion |

## 7. Git and documentation integrity

- Branch `release-hardening-pass`, HEAD `67c5a38`, 0 stashes; nothing committed or pushed.
- Every Git status entry from the start of 7E is still present; additions are only the files above.
- `DOCUMENTATION.md` `baa43787aad0a31987f3c894db09c67df4cfe05650d56d813027cbb62a9f94bc`, unchanged.
- `.vscode/settings.json` unchanged (`4c877983…`).

## 8. Next exact action requiring approval

After the owner sets up Application Default Credentials in their own terminal (`gcloud auth application-default login`), the **AC-2 read-only token-rotation dry-run** (`PHASE_7E_TOKEN_ROTATION_STATUS.md` §2):

```
node lib/ops/opsCli.js photo-token-rotate --project touchgrass-today --real-project --out ../ops-out/rotation/dry-1.json --max 1000
```

- **Reads:** private object names and metadata under `completion_photos/`, and the owners' link documents.
- **Writes:** nothing in production; a local 0600 file only.
