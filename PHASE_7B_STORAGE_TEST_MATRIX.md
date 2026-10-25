# Phase 7B — Storage Containment Test Matrix

**Environment:** local Firebase Storage emulator (`firebase emulators:exec`, project `demo-touchgrass-rules`). This is **local evidence only**: it shows how each ruleset behaves, not what is deployed. Production evidence is in `PHASE_7B_STORAGE_CONTAINMENT_REPORT.md` §7.

**Rulesets:**
- **LIVE**: `firestore-tests/test/fixtures/live-storage-2026-10-19.rules`. Byte-identical to the ruleset exported read-only from `touchgrass-today` at 19:31Z and 23:54Z on 2026-10-19 (SHA-256 `c550222392960371d52680406c5b18657b20a530de5f7ce84f1d18c04729579d`).
- **INTERIM**: `deploy/interim/storage.interim.rules`, after the Phase 7B fix (SHA-256 `630dc9a02b1985b144a72ef847a9582adf2befc47a979d9ce55478b216dcff17`).

**Command:** `cd firestore-tests && npm test`, with `JAVA_HOME` set to JBR 25. **Exit 0: 424/424 tests passed.**
- That is the full suite: 347 earlier tests, plus 77 in `storage_containment_matrix.test.mjs` (38 cases × 2 rulesets + 1 sequence test).
- Each "Actual" value below comes from that run's `MATRIX|…` output lines.

## Matrix

| ID | Case | LIVE expected | LIVE actual | INTERIM expected | INTERIM actual | Result |
|---|---|---|---|---|---|---|
| T01 | Unauthenticated: read a challenge photo | DENY | DENY | DENY | DENY | PASS |
| T02 | Unauthenticated: list a user's photos | DENY | DENY | DENY | DENY | PASS |
| T03 | Non-owner: read another user's photo | **ALLOW** | ALLOW | DENY | DENY | PASS (exposure closed) |
| T04 | Non-owner: get a download URL (token) for another user's photo | **ALLOW** | ALLOW | DENY | DENY | PASS (closed) |
| T05 | Non-owner: read another user's photo metadata | **ALLOW** | ALLOW | DENY | DENY | PASS (closed) |
| T06 | Non-owner: list another user's photos | **ALLOW** | ALLOW | DENY | DENY | PASS (closed) |
| T07 | Signed-in: list the `completion_photos` root (every user's folder) | **ALLOW** | ALLOW | DENY | DENY | PASS (closed; **newly found in 7B**) |
| T08 | Signed-in: list the bucket root | DENY | DENY | DENY | DENY | PASS |
| T09 | Owner: read own photos (both name styles) | ALLOW | ALLOW | ALLOW | ALLOW | PASS |
| T10 | Owner: own download URL (live app, after upload) | ALLOW | ALLOW | ALLOW | ALLOW | PASS |
| T11 | Owner: list own folder (live app's account deletion) | ALLOW | ALLOW | ALLOW | ALLOW | PASS |
| T12 | Owner: upload `{timestamp}.jpg`, `image/jpeg` (live app) | ALLOW | ALLOW | ALLOW | ALLOW | PASS |
| T13 | Owner: upload `{yyyy-MM-dd}.jpg` (new app) | ALLOW | ALLOW | ALLOW | ALLOW | PASS |
| T14 | Owner: upload `text/html` | **ALLOW** | ALLOW | DENY | DENY | PASS (tightened) |
| T15 | Owner: upload SVG | **ALLOW** | ALLOW | DENY | DENY | PASS (tightened) |
| T16 | Owner: upload exactly 10 MB | **ALLOW** | ALLOW | DENY | DENY | PASS (tightened) |
| T17 | Owner: upload 10 MB − 1 byte | ALLOW | ALLOW | ALLOW | ALLOW | PASS |
| T18 | Owner: upload to a nested path | **ALLOW** | ALLOW | DENY | DENY | PASS (tightened) |
| T19 | Owner: upload an arbitrary name (`page.html` as `image/jpeg`) | **ALLOW** | ALLOW | DENY | DENY | PASS (tightened) |
| T20 | Non-owner: upload into another user's folder | DENY | DENY | DENY | DENY | PASS |
| T21 | Non-owner: overwrite another user's existing photo | DENY | DENY | DENY | DENY | PASS |
| T22 | Non-owner: delete another user's photo | DENY | DENY | DENY | DENY | PASS |
| T23 | Non-owner: change another user's photo metadata | DENY | DENY | DENY | DENY | PASS |
| T24 | Unauthenticated: upload into a user folder | DENY | DENY | DENY | DENY | PASS |
| T25 | Owner: delete own photo (live app's account deletion) | ALLOW | ALLOW | ALLOW | ALLOW | PASS |
| T26 | Owner: upload `user_avatars/{uid}.png`, `image/png` (live app) | DENY | DENY | **ALLOW** | ALLOW | PASS (avatar change restored) |
| T27 | Signed-in: read another user's avatar | DENY | DENY | ALLOW | ALLOW | PASS (by design: leaderboard) |
| T28 | Unauthenticated: read an avatar | DENY | DENY | DENY | DENY | PASS |
| T29 | Non-owner: overwrite another user's avatar | DENY | DENY | DENY | DENY | PASS |
| T30 | Owner: avatar of exactly 5 MB | DENY | DENY | DENY | DENY | PASS |
| T31 | Owner: avatar with a non-image type | DENY | DENY | DENY | DENY | PASS |
| T32 | Owner: delete own avatar | DENY | DENY | DENY | DENY | PASS (unchanged; the live app tolerates it) |
| T33 | Signed-in: list all avatars | DENY | DENY | DENY | DENY | PASS (**after the 7B fix**; the original interim ALLOWED it) |
| T38 | Owner: own avatar download URL (live app, after upload) | DENY | DENY | ALLOW | ALLOW | PASS |
| T34 | Owner: read own metadata backup | DENY | DENY | DENY | DENY | PASS |
| T35 | Signed-in: read an unrelated path | DENY | DENY | DENY | DENY | PASS |
| T36 | Signed-in: write an unrelated path | DENY | DENY | DENY | DENY | PASS |
| T37 | Owner: non-image bytes declared `image/jpeg` | ALLOW | ALLOW | ALLOW | ALLOW | PASS, but a **documented limitation**: rules see only the declared type |
| SEQ | INTERIM: the live app's full sequence (completion upload → URL → avatar upload → URL → list own → delete own) | — | — | works | works | PASS |

## Required coverage

| # | Requirement | Covered by |
|---|---|---|
| 1 | Unauthenticated users can't read challenge photos | T01, T02; `interim_storage` "unauthenticated reads" |
| 2 | Non-owners can't read another user's photos | T03, T04, T05 |
| 3 | Non-owners can't list another user's files | T06, T07 |
| 4 | Owners can access their own photos | T09, T10, T11 |
| 5 | Disallowed file types are refused | T14, T15, T19, T31 (and the T37 limitation) |
| 6 | Size limits | T16 / T17 (completions), T30 (avatars) |
| 7 | No overwriting another user's files | T21, T29 |
| 8 | No deleting another user's files | T22 |
| 9 | No uploading into another user's path | T20, T24 |
| 10 | Profile-photo behaviour | T26–T33, T38 |
| 11 | Overlapping rules can't grant access | T07, T08, T18, T33–T36, plus the analysis in the report §4 (no path is matched by two granting statements; the catch-all only denies) |
| 12 | Current web-app compatibility | T10–T13, T25, T26, T38, SEQ. The paths and types are taken from the live `main.dart.js`. |
| 13 | Completion and Journal flows | The Storage side is covered by SEQ and T10–T13. The Firestore side is untouched by this change (Firestore rules are not deployed). Journal images load through stored token URLs, which rules don't evaluate. |
| 14 | No unrelated path becomes public | T08, T33, T34, T35, T36 |

## Other suites run (same command, same run)

| Suite | Tests | Result |
|---|---|---|
| `interim_storage.test.mjs` (the 14 from Phase 7A) | 14 | PASS, against the corrected interim file |
| `live_storage_exposure.test.mjs` | 6 | PASS |
| All other rules suites (Firestore and final `storage.rules`) | 327 | PASS |

## What is not covered locally

- **The rules actually deployed.** Only a deploy followed by a read-only re-export can show that (report §7).
- **Token URLs.** Download-token URLs aren't evaluated by rules at all (report §5).
- **Byte-level content validation.** Not possible in rules (T37).
- **Final `storage.rules`.** It uses `allow read` on `user_avatars/{fileName}`, the same construct T33 caught. It isn't part of this deployment, but must be fixed before the coordinated release (follow-up).
