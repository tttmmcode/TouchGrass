# Phase 7D — Final Report: Production Photo Privacy, Remediation & Release Readiness

**Date:** 2026-10-20

**Overall status: PRODUCTION CONTAINMENT VERIFIED (rules level); partially remediated; NOT release-ready.**

## 1. Executive summary

- **Contained:** the live Storage vulnerability is closed at the rules level.
  - With your explicit authorization, I deployed **only** the interim Storage rules.
  - A read-only export shows the live ruleset byte-identical to the reviewed file.
  - Other users can no longer list user folders, enumerate uids, or open or get links to another user's challenge photos through Firebase.
  - Test-account smoke tests of live behaviour are still the owner's step.
- **Not yet remediated:**
  - **Harvested links:** links collected before 04:30Z on 2026-10-20 still work until the rotation runs (AC-2…AC-4).
  - **Historical GPS** is unassessed in production.
  - **Account deletion** is fixed locally, but the live app can't delete accounts until `deleteAccount` (F-1) and a new web build (H-1) ship.
- **Fixed locally in 7D:**
  1. **Token rotation made two-phase:** a saved link never points at a dead token, and no photo bytes are rewritten by default. The emulator's token merging is detected rather than reported as success.
  2. **Account deletion:** the root cause was confirmed from evidence, and a second Storage sweep catches uploads from another still-valid session. New tests cover concurrency, late uploads and dead links.
  3. **Misleading claims corrected**, with regression tests: photo privacy, profile-photo links, "deletes everything", and every AI claim in onboarding, the Terms, the labels and the store listing.
  4. **Release gate:** project and bucket consistency across the configuration.
- **Blocker:** this machine has no Application Default Credentials, so the production dry-run and inventory can't run here until the owner provides credentials.

## 2. Verified production state (READ-ONLY evidence unless marked)

| Item | Evidence | Value |
|---|---|---|
| Project | `projects:list`, `apps:sdkconfig`, `.firebaserc` | `touchgrass-today` (760620662222), current CLI project. The look-alike `gen-lang-client-0754598293` is not referenced. |
| Bucket | `apps:sdkconfig` web | `touchgrass-today.firebasestorage.app` |
| Storage rules **before** | Exports at 04:18Z and 04:29Z | `c5502223…29579d` (exposed). The rollback snapshot matches (`sha256sum -c` OK). |
| **Deployment (AUTHORIZED)** | `firebase deploy --only storage --config deploy/interim/firebase.interim-storage.json --project touchgrass-today` | Exit 0; "released rules storage.interim.rules to firebase.storage"; no other resource |
| Storage rules **after** | Export at 04:30Z + `cmp` | **Byte-identical** to `deploy/interim/storage.interim.rules` (`630dc9a0…dcff17`) |
| Firestore rules | Export | `eb6b6b1c…` (= HEAD), unchanged |
| Functions / indexes | `functions:list`, `firestore:indexes` | None / none (unchanged) |
| Android app registration | `apps:list`, `google-services.json` | Firebase app config is for `com.example.touchgrass`; the build uses `com.touchgrass.app` (B6 open) |

### Security checks: live, as governed by the deployed ruleset

These rest on the deployed ruleset (proven byte-identical) and its emulator behaviour. Behaviour on the live endpoint with test accounts is **not yet observed**.

| Can an authenticated non-owner… | Before | Now |
|---|---|---|
| list `completion_photos/` (enumerate uids) | Yes | **No** |
| list another user's folder | Yes | **No** |
| read another user's photo (SDK) | Yes | **No** |
| obtain a new download link for another user's photo | Yes | **No** |
| use a link obtained **before** 04:30Z | Yes | **Yes, until rotation** (rules don't govern token URLs) |
| list `user_avatars/` | No (no rule) | **No** (`get` only) |
| upload arbitrary type or size into their own folder | Yes | **No** (image types, < 10 MB, named files) |

## 3. Findings fixed locally

| # | Finding | Fix | Evidence |
|---|---|---|---|
| 7D-1 | The 7C rotation rewrote the object (killing the old token) **before** updating links: a broken link meanwhile, or longer on failure. It also rewrote bytes unnecessarily. | Two-phase: add the token → links → remove; metadata patch by default (`--remove-via rewrite` optional); per-object state (`added`/`done` + token tag) for resume | 23 unit tests incl. a no-dead-link invariant after every write; emulator: both URLs work mid-rotation; the old URL is refused after `rewrite` |
| 7D-2 | On the emulator, a metadata patch **merges** token lists | The tool verifies "exactly one token" and reports `verify-failed: old-token-still-present`, never `rotated` | unit + emulator |
| 7D-3 | Live account deletion: the client's first write (batch-delete `completions`) is refused by the create-only rules. Users **without** completions get a partial deletion. | The server-side `deleteAccount` (existing) is the fix; the client cascade can't work under safe rules | Live bundle + live rules (`PHASE_7D_ACCOUNT_DELETION_REMEDIATION.md` §1) |
| 7D-4 | `deleteAccount`: an upload from another still-valid session during deletion would outlive the account | Second Storage sweep before the Auth deletion | unit + emulator |
| 7D-5 | False or misleading copy (D1–D8, D12–D14) | Corrected; regression tests | Flutter tests |
| 7D-6 | Configuration could drift between project and bucket | Parity test checks `.firebaserc`, `firebase_options.dart` and `firestore.rules`; bans look-alike references | rules suite |

**Files changed in 7D (local; nothing committed; backups in scratchpad `p7d/bak/`):**
- **Functions:** `functions/src/ops/photoTokenRotation.ts`, `functions/src/ops/opsCli.ts`, `functions/src/ops/ops7c.test.ts`, `functions/src/ops/ops7c.emulator.test.ts`, `functions/src/accountDeletion.ts`, `functions/src/accountDeletion.test.ts`, `functions/src/accountDeletion.emulator.test.ts`.
- **App:** `lib/core/constants/privacy_copy.dart`, `lib/features/onboarding/screens/onboarding_screen.dart`, `lib/features/settings/screens/settings_screen.dart`, `lib/features/camera/screens/camera_screen.dart`, `lib/features/challenges/screens/challenge_detail_screen.dart`, `lib/models/adventure_memory_model.dart`.
- **Tests and release drafts:** `test/core/privacy_copy_test.dart`, `test/models/adventure_memory_model_test.dart`, `firestore-tests/test/storage_release_parity.test.mjs`, `STORE_LISTING.md`.
- **Docs:** `REMEDIATION_CHECKLIST.md`, `KNOWN_BUGS.md`, and the 7 `PHASE_7D_*.md` files (new).
- **Git-ignored:** read-only snapshots `ops-out/live-rules/touchgrass-today-20261020T041845Z`, `…T042940Z` and `…T043029Z`.
- **Unchanged:** `deploy/interim/*`, `storage.rules`, `firebase.json`, `firestore.rules`, `DOCUMENTATION.md`, and the Phase 7A–7C reports.

## 4. Test results (this run; exit codes recorded)

| Category | Suite | Result |
|---|---|---|
| Local static | `dart format --set-exit-if-changed lib test` | Exit 0 (0 of 160 files changed) |
| Local static | `flutter analyze` | No issues, exit 0 |
| Local static | functions `tsc --noEmit`, `npm run lint` | OK / 0 problems |
| Local unit | `flutter test` | **484/484**, exit 0 (5 new) |
| Local unit | functions `npm test` | **203/203**, exit 0 |
| Local unit | `node --test tool/test/*.test.mjs` | **30/30** |
| Emulator | rules suite `firestore-tests npm test` (before the deploy decision) | **568/568**, exit 0; 103 interim outcomes as expected |
| Emulator | rules suite, final (incl. the new config gate) | **569/569**, exit 0; 130 PARITY + MATRIX lines all match |
| Emulator | functions `npm run test:emulator` (Node 22.23.3) | **36/36**, exit 0 |
| Build | web release into the scratchpad (no `secrets.json`; `build/web` untouched) | Exit 0. Bundle scan: the only `AIza…` key is the public Firebase web config key (hash-matched to `firebase_options.dart`); no Gemini or `generativelanguage` references; no "our AI will verify". |
| Dependencies | `npm audit` functions (production / all), firestore-tests | 0 / 0 / 0 vulnerabilities |
| Read-only production | exports, `projects:list`, `apps:*`, `functions:list`, `firestore:indexes` | §2 |
| **Authorized production change** | S-1 deploy | Exit 0; verified by export |
| Production smoke tests | test accounts | **Not performed** (owner) |

**Not run:** Android/iOS builds (no native changes; signing and registration are open, §6).

## 5. Outstanding risks

| # | Risk | Status |
|---|---|---|
| R1 | Links harvested before S-1 still open photos | **Open:** AC-2 → AC-4 (needs authorization + owner ADC) |
| R2 | Historical photos may contain GPS | **Open:** M-1 → M-6 after the rotation |
| R3 | Live users can't delete accounts; some may hold partially deleted accounts | **Open:** F-1 + H-1 + the two-account test |
| R4 | ≤1 h post-deletion window for still-valid ID tokens | Owner decision |
| R5 | Profile-photo links are bearer links | By design; disclosed; C4 decision |
| R6 | Live access behaviour not yet smoke-tested | Owner, S1–S9 |
| R7 | Retention periods, notification duty, marketing claims | Owner / legal |
| R8 | Android signing and registration, iOS | Open (B6/B7) |

## 6. Production operations

**Performed (authorized):** only the S-1 Storage rules deploy above.

**Read-only:**
- rules exports at 04:18Z, 04:29Z and 04:30Z;
- `projects:list`, `apps:sdkconfig`, `apps:list`, `functions:list`, `firestore:indexes`, `login:list`.

**NOT performed:**
- final Storage rules, Firestore rules or indexes, Functions or Hosting deploys;
- token rotation (incl. its dry-run);
- historical inventory or remediation;
- backups;
- reads of any photo or user record;
- user-data changes;
- disclosure or store publication;
- cleanup jobs;
- billing, retention, Auth or Maps changes;
- AI enablement;
- commit or push.

## 7. Git and documentation integrity

- Branch `release-hardening-pass`, HEAD `67c5a38`, no stash; nothing committed.
- Every status entry from the start of 7D is still present (see the final check in the session).
- `DOCUMENTATION.md` SHA-256 `baa43787aad0a31987f3c894db09c67df4cfe05650d56d813027cbb62a9f94bc` (unchanged).

## 8. Readiness verdict

**Not release-ready.** Production containment is verified at the rules level. Closing the incident requires:
1. the rotation (AC-2…AC-4);
2. historical remediation (M-1…M-5);
3. F-1 + the coordinated release;
4. disclosures published only as their gates pass (`PHASE_7D_RELEASE_GATE_CHECKLIST.md`).

**Next action requiring explicit authorization:** the **AC-2 read-only token-rotation dry-run** (`PHASE_7D_TOKEN_ROTATION_RUNBOOK.md` §3), once the owner has provided Application Default Credentials. Before that, the owner's S1–S9 smoke tests are recommended.
