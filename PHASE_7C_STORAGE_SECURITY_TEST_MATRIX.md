# Phase 7C — Storage Security Test Matrix

**Environment: local only.** These results come from the Firebase emulators (`demo-` projects) and unit tests. They show how each ruleset and tool behaves. **They are not evidence of what is deployed**: production still runs the old exposed rules (read-only export at 03:33Z on 2026-10-20, SHA-256 `c5502223…29579d`).

**Rulesets tested:**

| Name | File | SHA-256 | Deployed by |
|---|---|---|---|
| FINAL | `storage.rules` (after the Phase 7C fix) | see report §3 | `firebase.json` (coordinated release, S-2) |
| INTERIM | `deploy/interim/storage.interim.rules` (unchanged since 7B) | `630dc9a02b1985b144a72ef847a9582adf2befc47a979d9ce55478b216dcff17` | `deploy/interim/firebase.interim-storage.json` (S-1) |
| LIVE (reference only) | `firestore-tests/test/fixtures/live-storage-2026-10-19.rules` | `c550222392960371d52680406c5b18657b20a530de5f7ce84f1d18c04729579d` | what production runs today |

## 1. Suites and results (actual exit codes from this run)

| Suite | Command | Result |
|---|---|---|
| All rules suites (Firestore + Storage) | `cd firestore-tests && npm test` (JBR 25) | **Exit 0: 568/568.** 424 earlier + 144 new in `storage_release_parity.test.mjs`. All 130 `PARITY` and 76 `MATRIX` lines match their expected outcomes. |
| Regression proof | The P50 case against the **pre-fix** `storage.rules` backup | Pre-fix: **ALLOW** (1 avatar listed). Fixed: **DENY** (`storage/unauthorized`). |
| Functions unit | `cd functions && npm test` | **Exit 0: 196/196** (38 new in `ops7c.test.ts`). Lint 0. |
| Functions emulator | `cd functions && npm run test:emulator` (Node 22.23.3) | **Exit 0: 31/31** (8 new in `ops7c.emulator.test.ts`). Rerun after the last code change: 31/31. |
| Flutter | `flutter test`, `flutter analyze`, `dart format` | **479/479**; analyze: no issues; format: 0 files changed |
| Dart metadata (focused) | `flutter test test/core/image_metadata*_test.dart test/core/secret_redaction_test.dart` | 29 + 5 pass. The 5 new JPEG trailer and between-scans tests **failed before the fix**, against the code in the working tree at the start of 7C. |

## 2. Behaviour matrix: FINAL vs INTERIM (emulator)

Each case was run against both rulesets in one `npm test` run. The "actual" columns come from the `PARITY|…` lines that run printed.

A case's expectation is the same for both rulesets unless it is listed as a **documented difference**. The test refuses any other difference.

| ID | Case | FINAL expected | FINAL actual | INTERIM expected | INTERIM actual | Result |
|---|---|---|---|---|---|---|
| P01 | unauthenticated: read a challenge photo | DENY | DENY | DENY | DENY | PASS |
| P02 | unauthenticated: list a user's photos | DENY | DENY | DENY | DENY | PASS |
| P03 | non-owner: read another user's photo | DENY | DENY | DENY | DENY | PASS |
| P04 | non-owner: read a legacy-named photo | DENY | DENY | DENY | DENY | PASS |
| P05 | non-owner: get a download URL (token) for another user's photo | DENY | DENY | DENY | DENY | PASS |
| P06 | non-owner: read another user's photo metadata | DENY | DENY | DENY | DENY | PASS |
| P07 | non-owner: list another user's photos | DENY | DENY | DENY | DENY | PASS |
| P08 | signed-in: list the completion_photos root (all uids) | DENY | DENY | DENY | DENY | PASS |
| P09 | signed-in: list the bucket root | DENY | DENY | DENY | DENY | PASS |
| P10 | owner: read own photos (date and legacy names) | ALLOW | ALLOW | ALLOW | ALLOW | PASS |
| P11 | owner: own download URL and metadata | ALLOW | ALLOW | ALLOW | ALLOW | PASS |
| P12 | owner: list own folder | ALLOW | ALLOW | ALLOW | ALLOW | PASS |
| P13 | owner (alice): list a look-alike uid folder (alice2) | DENY | DENY | DENY | DENY | PASS |
| P20 | owner: upload {yyyy-MM-dd}.jpg image/jpeg | ALLOW | ALLOW | ALLOW | ALLOW | PASS |
| P21 | owner: upload 10 MB − 1 byte (limit is < 10 MB) | ALLOW | ALLOW | ALLOW | ALLOW | PASS |
| P22 | owner: upload exactly 10 MB | DENY | DENY | DENY | DENY | PASS |
| P23 | owner: upload 10 MB + 1 byte | DENY | DENY | DENY | DENY | PASS |
| P24 | owner: upload image/png, image/webp, image/heic, image/heif | ALLOW | ALLOW | ALLOW | ALLOW | PASS |
| P25 | owner: upload image/svg+xml | DENY | DENY | DENY | DENY | PASS |
| P26 | owner: upload image/gif | DENY | DENY | DENY | DENY | PASS |
| P27 | owner: upload text/html | DENY | DENY | DENY | DENY | PASS |
| P28 | owner: upload application/octet-stream | DENY | DENY | DENY | DENY | PASS |
| P29 | owner: name 2026-10-19.jpeg | DENY | DENY | DENY | DENY | PASS |
| P30 | owner: name 2026-10-19.JPG | DENY | DENY | DENY | DENY | PASS |
| P31 | owner: name 2026-10-19.jpg.html | DENY | DENY | DENY | DENY | PASS |
| P32 | owner: name x2026-10-19.jpg (prefix) | DENY | DENY | DENY | DENY | PASS |
| P33 | owner: name 123456789.jpg (9 digits) | DENY | DENY | DENY | DENY | PASS |
| P34 | owner: name of 17 digits | DENY | DENY | DENY | DENY | PASS |
| P35 | owner: nested path in own folder | DENY | DENY | DENY | DENY | PASS |
| P36 | owner: upload directly at completion_photos/{uid} (no file name) | DENY | DENY | DENY | DENY | PASS |
| P37 | owner: legacy {timestamp}.jpg upload (13 digits) | DENY | DENY | ALLOW | ALLOW | PASS (documented difference) |
| P38 | non-owner: upload into another user's folder | DENY | DENY | DENY | DENY | PASS |
| P39 | non-owner: overwrite another user's photo | DENY | DENY | DENY | DENY | PASS |
| P40 | non-owner: change another user's photo metadata | DENY | DENY | DENY | DENY | PASS |
| P41 | non-owner: delete another user's photo | DENY | DENY | DENY | DENY | PASS |
| P42 | unauthenticated: upload into a user folder | DENY | DENY | DENY | DENY | PASS |
| P43 | owner: delete own photo | DENY | DENY | ALLOW | ALLOW | PASS (documented difference) |
| P50 | signed-in: list all avatars (user_avatars/) | DENY | DENY | DENY | DENY | PASS |
| P51 | signed-in: list "another user's avatar directory" (user_avatars/alice) | DENY | DENY | DENY | DENY | PASS |
| P52 | owner: list own avatar prefix | DENY | DENY | DENY | DENY | PASS |
| P53 | signed-in: GET one avatar (leaderboard) | ALLOW | ALLOW | ALLOW | ALLOW | PASS |
| P54 | signed-in: avatar download URL + metadata (single object) | ALLOW | ALLOW | ALLOW | ALLOW | PASS |
| P55 | unauthenticated: read an avatar | DENY | DENY | DENY | DENY | PASS |
| P56 | owner: upload own {uid}.png image/png | ALLOW | ALLOW | ALLOW | ALLOW | PASS |
| P57 | owner: avatar 5 MB − 1 byte | ALLOW | ALLOW | ALLOW | ALLOW | PASS |
| P58 | owner: avatar exactly 5 MB | DENY | DENY | DENY | DENY | PASS |
| P59 | owner: avatar 5 MB + 1 byte | DENY | DENY | DENY | DENY | PASS |
| P60 | owner: avatar declared image/svg+xml | DENY | DENY | DENY | DENY | PASS |
| P61 | owner: avatar declared text/html | DENY | DENY | DENY | DENY | PASS |
| P62 | owner: avatar named {uid}.jpg | DENY | DENY | DENY | DENY | PASS |
| P63 | owner: avatar nested under own uid | DENY | DENY | DENY | DENY | PASS |
| P64 | owner: avatar named {uid}.png.html | DENY | DENY | DENY | DENY | PASS |
| P65 | non-owner: upload into another user's avatar path | DENY | DENY | DENY | DENY | PASS |
| P66 | non-owner: create an avatar for a uid that has none | DENY | DENY | DENY | DENY | PASS |
| P67 | non-owner: change another user's avatar metadata | DENY | DENY | DENY | DENY | PASS |
| P68 | non-owner: delete another user's avatar | DENY | DENY | DENY | DENY | PASS |
| P69 | owner: delete own avatar | DENY | DENY | DENY | DENY | PASS |
| P70 | unauthenticated: upload an avatar | DENY | DENY | DENY | DENY | PASS |
| P80 | owner: read own metadata backup (server-only) | DENY | DENY | DENY | DENY | PASS |
| P81 | owner: list own metadata backups | DENY | DENY | DENY | DENY | PASS |
| P82 | signed-in: list metadata_backup root | DENY | DENY | DENY | DENY | PASS |
| P83 | signed-in: write an unrelated path | DENY | DENY | DENY | DENY | PASS |
| P84 | signed-in: write a metadata backup | DENY | DENY | DENY | DENY | PASS |
| P90 | owner: non-image bytes declared image/jpeg (limitation) | ALLOW | ALLOW | ALLOW | ALLOW | PASS |
| P91 | token URL opens without auth (limitation) | ALLOW | ALLOW | ALLOW | ALLOW | PASS |

**Documented differences** (the only ones the test allows):
- **P37** (legacy `{timestamp}.jpg` upload): INTERIM allows it because the **live** web app names new photos that way. FINAL requires `{yyyy-MM-dd}.jpg`.
- **P43** (owner deletes own photo): INTERIM keeps the live rules' owner delete. FINAL leaves deletion to the server-side `deleteAccount`.

Both differences are owner-only and disappear when FINAL replaces INTERIM. Phase 7C also found that the live web app's account deletion fails at Firestore (D-04) before it reaches Storage, so P43's ALLOW is not used by any working flow today.

## 3. Static grant inventory (both files)

| Check | FINAL | INTERIM |
|---|---|---|
| Grants exactly the reviewed (path, operation) set. Any new or widened grant fails. | PASS | PASS |
| No `read`/`list` grant except a user's own completion folder (owner-only condition) | PASS | PASS |
| A recursive wildcard `{x=**}` never grants anything | PASS | PASS |
| Every completion-photo grant is owner-only; every write needs sign-in | PASS | PASS |
| Every create/update checks `isAllowedImage()` and a size limit; no SVG/GIF/`image/*` | PASS | PASS |
| `firebase.json` deploys `storage.rules`; the interim config deploys only `storage.interim.rules` | PASS | PASS |

The parser itself is tested on nested blocks, braces inside strings, and multi-line conditions.

## 4. Brief requirements (1–40) → evidence

Status values:
- **PASS**: automated test passed this run.
- **PASS (review)**: code review only; no automated test.
- **N/A**: does not apply to the current design.
- **BLOCKED**: needs a deployment or an owner action.

| # | Requirement | Evidence | Rules file / environment | Status |
|---|---|---|---|---|
| 1 | Unauthenticated reads denied | P01, P02 | FINAL + INTERIM, emulator | PASS |
| 2 | Non-owner reads denied | P03–P06 | both, emulator | PASS |
| 3 | Non-owner listing denied | P07, P08 (root: every uid), P13 (look-alike uid) | both, emulator | PASS |
| 4 | Owner access works | P10–P12 | both, emulator | PASS |
| 5 | Unapproved types denied | P25–P28; P90 records the declared-type limitation | both, emulator | PASS |
| 6 | Oversized uploads denied | P21 (10 MB − 1: allowed), P22 (= 10 MB), P23 (10 MB + 1) | both, emulator | PASS |
| 7 | Invalid filenames denied | P29–P36; P37 is the documented difference | both, emulator | PASS |
| 8 | Uploads into another user's path denied | P38, P42 | both, emulator | PASS |
| 9 | Cross-user overwrites denied | P39, P40 (metadata) | both, emulator | PASS |
| 10 | Cross-user deletes denied | P41 | both, emulator | PASS |
| 11 | Legitimate owner deletes work | INTERIM: P43 ALLOW. FINAL: by design through `deleteAccount` (functions emulator: full cleanup, uid look-alike untouched) | both, emulator | PASS (design differs per stage) |
| 12 | Overlapping wildcards don't bypass | P08, P09, P36, P80–P84, plus the static checks in §3 | both | PASS |
| 13 | Can't list all profile photos | P50 (FINAL was **ALLOW before the 7C fix**) | both, emulator | PASS |
| 14 | Can't list another user's "profile-photo directory" | P51, P52 (avatars are flat: `user_avatars/{uid}.png`) | both, emulator | PASS |
| 15 | Single-photo retrieval behaves as intended | P53, P54 (signed-in GET, URL, metadata) | both, emulator | PASS |
| 16 | No upload into another user's avatar path | P65, P66 | both, emulator | PASS |
| 17 | No overwrite or delete of another user's photo | P65, P67, P68 | both, emulator | PASS |
| 18 | Unauthorized profile-photo operations denied | P55, P58–P64, P69, P70 | both, emulator | PASS |
| 19 | Visibility documented and tested | P53–P55, P91; plan §1.2 | both | PASS |
| 20 | No unrelated rule grants listing | §3 "no read/list grant except own folder" | both, static | PASS |
| 21 | Challenge upload + completion flow | FINAL sequence test; INTERIM SEQ (7B); Flutter completion tests | emulator + unit | PASS |
| 22 | Journal loads own photos | Journal images load through the stored token URL, which the rules don't evaluate; P11 (owner URL). No end-to-end Journal test against Storage. | — | PASS (review) |
| 23 | Profile-photo updates work | P56, P57, FINAL sequence; `sanitizeProfilePhoto` tests | emulator + unit | PASS |
| 24 | Account deletion cleans up own photos | Functions emulator: `deleteAccount` removes photos, metadata backups and the avatar; a uid-prefix look-alike is untouched. **Live:** `deleteAccount` isn't deployed, and the live web app's deletion fails at Firestore (D-04). | emulator | PASS (emulator) / **BLOCKED** (live) |
| 25 | Missing or deleted objects give safe errors | Every render path has an error fallback: `errorWidget` (×4 private photos, avatars), `errorBuilder` (camera), `onError` (map marker) | review | PASS (review) |
| 26 | Expired authentication → re-authentication | Token URLs don't use the session. This applies to Option B (SDK access), which is not implemented. | — | N/A (current design) |
| 27 | Stale token URLs fail or are handled | Emulator: the old URL is **refused** after rotation; new links open identical bytes. P91: rules do **not** revoke tokens. App falls back to the error widget. | emulator | PASS (emulator) |
| 28 | Web and mobile consistent | Same Dart upload, strip and render code on both. The **live** web app is an older build (report §2). | review | PASS (review) |
| 29 | GPS EXIF removed | `image_metadata_test`, `image_metadata_formats_test`, `image_metadata_trailer_test` (appended MPF image with GPS) | unit | PASS |
| 30 | XMP removed | XMP APP1 test; PNG `iTXt` XMP in avatars | unit | PASS |
| 31 | Orientation correct | Orientations 1–8; rotated + trailer | unit | PASS |
| 32 | Unsupported or corrupt files fail safely | Random or empty bytes, truncated header, no EOI, unreadable avatar | unit | PASS |
| 33 | Acceptable visual quality | Lossless path: scan data byte-identical (asserted). Re-encode path: JPEG quality `AppConstants.imageQualityPercent`; **no perceptual test** | unit | PASS (lossless) / not measured (re-encode) |
| 34 | No metadata through alternate paths | Camera `compressJpeg`; gallery → `stripImageMetadata`; avatar → `sanitizeProfilePhoto` (new); data after EOI (new) | unit | PASS |
| 35 | Dry-run never modifies | Metadata remediation, token rotation (fakes + emulator: generations unchanged) | unit + emulator | PASS |
| 36 | Backups never reuse download tokens | 7A emulator (original token refused on backup); unit | emulator | PASS |
| 37 | No cross-ownership deletion or cleanup | `deleteAccount` look-alike uid; rotation leaves a link to another user's photo inside Alice's data alone; `--uid` scope (`ali` ≠ `alice/`) | unit + emulator | PASS |
| 38 | Resume and retry are safe | Remediation resume; rotation resume (no second token; links finished) | unit + emulator | PASS |
| 39 | Concurrent jobs can't corrupt | Shared lease (emulator); generation-checked writes; account deletion mid-run: no resurrection, no orphan backup. The emulator **ignores** `ifGenerationMatch`, so only the read-check runs here. | unit + emulator | PASS (atomic precondition is production-only) |
| 40 | No URLs, tokens or locations in logs | CLI summary; rotation report has no token or URL; Crashlytics redaction (5 tests) | unit | PASS |

## 5. Not covered locally (needs production, with separate authorization)

- **What is actually deployed.** Only a deploy followed by a read-only re-export can show it.
- **Token revocation in real Cloud Storage.** The emulator shows that the rewrite approach revokes the old token. Production needs the canary in `PHASE_7C_PHOTO_TOKEN_REMEDIATION_PLAN.md` §6 on a **test account** first.
- **`ifGenerationMatch` atomicity.** It is enforced only by real Cloud Storage.
- **How many historical photos carry GPS or appended data.** Needs the inventory (`PHASE_7C_HISTORICAL_METADATA_RUNBOOK.md`).
- **Byte-level content validation.** Rules see only the declared type (P90).
