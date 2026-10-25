# Phase 7D — Production Security Runbook

**Labels:**
- **READ-ONLY**: changes nothing.
- **⚠️ PRODUCTION**: needs explicit authorization for exactly that operation.

Approval of one step never covers another.

## 1. Target verification (READ-ONLY; before every production step)

| Check | Command | Expected (verified 2026-10-20) |
|---|---|---|
| CLI account present (never log in from a session) | `firebase login:list` | One account |
| Project | `firebase projects:list` | `touchgrass-today`, "TouchGrass", **760620662222**. Don't confuse it with `gen-lang-client-0754598293`, which is also named "TouchGrass". |
| Web app config | `firebase apps:sdkconfig web 1:760620662222:web:ebb0cf64619e43dca53f9f --project touchgrass-today` | `projectId touchgrass-today`, `storageBucket touchgrass-today.firebasestorage.app` |
| Repository config | `.firebaserc` default; `lib/firebase_options.dart` | `touchgrass-today` / `touchgrass-today.firebasestorage.app`. The parity test enforces this and fails on any `gen-lang-client-` reference. |
| Live rules | `node tool/export_live_rules.mjs --project touchgrass-today`, then `sha256sum ops-out/live-rules/<new>/*.rules` | Storage `630dc9a0…dcff17` (interim, since 04:30Z on 2026-10-20); Firestore `eb6b6b1c…` (HEAD) |

## 2. Interim Storage rules (S-1): DONE in Phase 7D

| | |
|---|---|
| Authorization | Given by the user for exactly this file and project (Phase 7D) |
| Pre-checks at 04:29Z | Interim SHA `630dc9a0…`; config `{"storage":{"rules":"storage.interim.rules"}}` (SHA `bccfb989…`); live still `c5502223…`; local rules suite 568/568 (103 interim outcomes as expected) |
| Command | `firebase deploy --only storage --config deploy/interim/firebase.interim-storage.json --project touchgrass-today` |
| Result | Exit 0. "rules file storage.interim.rules compiled successfully", "released rules storage.interim.rules to firebase.storage", "Deploy complete!". No other resource was mentioned. |
| Read-only verification (04:30Z) | The new export's `storage.rules` is **byte-identical** to `deploy/interim/storage.interim.rules` (`cmp`, SHA `630dc9a0…`). Firestore rules unchanged (`eb6b6b1c…`). `functions:list`: none. `firestore:indexes`: none. The exporter no longer reports live risks. |

### 2.1 Smoke tests: owner, test accounts only (NOT yet performed)

I have no test credentials, and creating production accounts is a production change, so these are for the owner.

| # | Test | How | Expected |
|---|---|---|---|
| S1 | Cross-user read denied | Firebase console → Storage → Rules → **Rules Playground**: `get /b/touchgrass-today.firebasestorage.app/o/completion_photos/<testA>/x.jpg` as `<testB>` | Denied |
| S2 | Cross-user list denied | Playground: `list …/o/completion_photos/<testA>` as `<testB>` | Denied |
| S3 | Root listing (all uids) denied | Playground: `list …/o/completion_photos` as `<testB>` | Denied |
| S4 | Avatar folder listing denied | Playground: `list …/o/user_avatars` as `<testB>` | Denied |
| S5 | Owner read allowed | Playground: `get` as `<testA>` | Allowed |
| S6 | Bad upload refused | Playground: `create …/completion_photos/<testA>/x.html`, `text/html`, as `<testA>` | Denied |
| S7 | Live app: completion with photo | Test account A on `touchgrass-today.web.app` | Saves; photo shows in the Journal |
| S8 | Live app: avatar change | Settings → change photo | Works (it was denied before S-1) |
| S9 | Existing photos display | Journal, map | Load (stored links) |

Watch the console's Storage request errors for 48 h. A spike of denials on legitimate uploads means stop and report.

### 2.2 Rollback ⚠️ (separate authorization; restores the exposure)

- **Snapshot:** `ops-out/rollback/storage-live-2026-10-19/`, containing the exact previous live rules `c5502223…`. Re-verified 2026-10-20 (`sha256sum -c`: OK).
- **Command:** `firebase deploy --only storage --config ops-out/rollback/storage-live-2026-10-19/firebase.json --project touchgrass-today`
- **Consequence:** every signed-in user can enumerate uids and read every challenge photo again. Use it only if legitimate use is broken and no narrow forward fix exists.

## 3. Approval gates that follow (in order)

| Gate | Operation | Reads private data? | Writes? | Runbook |
|---|---|---|---|---|
| **AC-2** | Token-rotation **dry-run** | Yes: object names and metadata; Firestore link documents | No | `PHASE_7D_TOKEN_ROTATION_RUNBOOK.md` §3 |
| AC-3 | Rotation canary on a **test account** | That account | Yes (test account) | §4 there |
| AC-4 | Staged full rotation | Yes | Yes | §5 there |
| M-1 | Historical-photo inventory (headers, or `--full-read`) | Yes: photo bytes | No | `PHASE_7D_HISTORICAL_PHOTO_REMEDIATION_RUNBOOK.md` |
| M-2…M-6 | Metadata dry-run, canary, staged, backup purge | Yes | Yes (except M-2) | same |
| F-1 | Deploy `deleteAccount` only | — | Function | `PHASE_7D_ACCOUNT_DELETION_REMEDIATION.md` §7 |
| R-1+S-2+H-1 | Coordinated final rules and web build | — | Rules, Hosting | `PHASE_7D_RELEASE_GATE_CHECKLIST.md` |

**Blocker for AC-2, AC-4 and M-\*:** this machine has no Application Default Credentials. Owner setup is in the token runbook §3.1.

## 4. Stop conditions (any production step)

- The target check (§1) disagrees anywhere.
- The live rules differ from what the step expects (re-export first).
- A command mentions a resource outside its scope (Firestore, Functions or Hosting during a Storage step).
- A nonzero exit. Don't retry with different flags; re-export read-only and report.
- Any user report of lost photos or broken uploads.
