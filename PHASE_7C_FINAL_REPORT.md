# Phase 7C — Final Report: Photo Privacy Remediation & Release Security Hardening

**Date:** 2026-10-20

**Scope:** local code, tests and plans, plus one read-only production check. **No production change was made.**

## 1. Executive summary

**Verdict: NOT RESOLVED in production.** It is locally remediated and release-gated.

**Production today:**
- Production still runs the exposed Storage rules (read-only export at 03:33Z on 2026-10-20, SHA-256 `c5502223…29579d`).
- Any signed-in user can list every user's ID and get permanent links to every challenge photo.
- The interim containment (S-1) is ready but **not deployed**. The Phase 7B authorization question is still unanswered.

**Fixed locally in 7C:**
1. **Final `storage.rules`** let any signed-in user list every profile photo, which enumerates uids. It now grants `get` only. A pre-fix vs post-fix regression run proved the leak and the fix.
2. **A release gate** now runs the same 64 security cases, the token-URL limitation and a static grant inventory against **both** rule files. It fails on any undocumented difference or any new or widened grant.
3. **New uploads could still carry location:** the "lossless" JPEG stripper copied everything after the image data. That includes appended MPF images (with their own GPS) and motion-photo video. The fix is in the app and in the operator tool; 5 Dart tests failed before it.
4. **Profile photos** were uploaded without any metadata stripping at the upload boundary. They are now sanitised to a metadata-free PNG.
5. **Token URLs in crash reports:** Flutter image errors contain the full photo URL, token included. Tokens are now redacted at every Crashlytics entry point.
6. **Historical-photo tool:**
   - a backup could outlive its photo if the photo was deleted, for example by account deletion, mid-run;
   - there was no lock against concurrent runs;
   - data appended after the image was invisible to it.
   All three are fixed.
7. **Revoking harvested links:** a new, tested operator tool (`photo-token-rotate`) rotates each completion photo's token and updates the owner's stored links. The emulator proves the old URL is refused afterwards. It is dry-run by default, resumable, has a `--uid` canary scope, and shares a lock with the metadata job.

**Still open:**
- **Harvested token URLs stay valid** until C2 rotation runs in production. That requires S-1 first.
- **Historical GPS** is unremediated, and the count is unknown.
- **Profile-photo links** are bearer links by design.
- **Account deletion doesn't work in the live app** (D-04).

## 2. Findings independently verified

| # | Finding | Evidence | New in 7C? |
|---|---|---|---|
| F1 | Repository baseline: branch `release-hardening-pass`, HEAD `67c5a38`, 0 stashes. The status matches the end of 7B plus the three 7B reports. `DOCUMENTATION.md` is `baa43787…94bc`. | `git`, `sha256sum` | — |
| F2 | **Live state:** Storage rules still `c5502223…` (exposed); Firestore rules `eb6b6b1c…` = HEAD. **S-1 not deployed.** | `tool/export_live_rules.mjs` (read-only; GET releases and rulesets), snapshot `ops-out/live-rules/touchgrass-today-20261020T033322Z/` | Re-verified |
| F3 | All 7A/7B reports and paths named in the brief exist | `ls` | — |
| F4 | **Final `storage.rules` allowed listing `user_avatars/`** (`allow read` includes `list`) | Emulator: pre-fix ALLOW (1 listed), post-fix DENY | Confirmed and fixed |
| F5 | The interim file is unchanged (`630dc9a0…`), so the pending S-1 authorization request remains valid | `sha256sum` | — |
| F6 | **Rules don't revoke token URLs:** an owner's URL opens without sign-in under FINAL and INTERIM; a wrong token is refused | Emulator P91 | Proven |
| F7 | **The JPEG stripper (app and operator tool) kept data after EOI** (MPF secondary images with GPS, motion-photo video, vendor trailers) and APPn between scans | 5 failing Dart tests before the fix; TS unit tests | **New** |
| F8 | **Profile-photo uploads weren't stripped at the upload boundary.** The Settings crop redraws the image (so metadata is lost in practice), but `uploadProfilePhoto` trusted its caller | Code review | **New** (hardening) |
| F9 | **Unhandled image-load errors on mobile would send the token URL to Crashlytics** (`FlutterError.onError → recordFlutterFatalError`; `NetworkImageLoadException` includes the URI). Every current widget handles its own errors, so this was latent. | Code review; tests with the real exception type | **New** (hardening) |
| F10 | **The historical tool could leave a backup** (original bytes with GPS) when the overwrite didn't happen, including when `deleteAccount` deleted the photo mid-run. This fell outside the deletion's backup purge. | Unit (fakes) + emulator race test | **New** |
| F11 | **No concurrency control** for `photo-metadata-remediate` (orphan cleanup had a lease; remediation didn't) | Code review | **New** |
| F12 | **The live web app's account deletion fails before it reaches Storage.** It deletes `completions` first, which live Firestore rules deny (`allow update, delete: if false`), and the `users` doc is also delete-denied. Its avatar delete would also be refused (only `object-not-found` is tolerated). Users of the live app therefore can't delete their photos. | Live public bundle (call order), live Firestore rules = HEAD | **New detail on D-04** |
| F13 | Correction to 7B: the interim owner-delete of completion photos is "needed by the live app's account deletion". That flow never reaches Storage (F12). The grant is harmless (owner-only), so the interim file was left unchanged. | F12 | Correction |
| F14 | Released versions could store GPS. Camera path: `compressJpeg` (`encodeJpg` writes the decoded EXIF back). Gallery path: uploaded unstripped. | `git show HEAD:…` | Re-verified (B11) |
| F15 | Every private-photo URL is stored only in owner-readable documents (`completions`, `users/{uid}/memories`). Avatar URLs are in `leaderboard_public` (readable by every signed-in user). No analytics event carries a URL. | Code + live rules | — |
| F16 | `STORE_LISTING.md` still advertises Gemini AI photo verification, which is disabled. That is a third-party-processing mismatch. | File review | Disclosure finding (§9) |

## 3. Files changed in 7C (local only; nothing committed)

Backups of every pre-existing file edited are in the scratchpad (`p7c/bak/`).

| File | Change |
|---|---|
| `storage.rules` | `user_avatars/{fileName}`: `allow read` → `allow get`; comment. SHA-256 now `e48a9d6e9e50e784d9c04a1550f47a2d0f1179b6ea7651ba2e58e4235b0be16d`. |
| `firestore-tests/test/storage_release_parity.test.mjs` | **New.** 64 behaviour cases × FINAL/INTERIM, documented differences, token-URL limitation, the new app's sequence, static grant inventory, config check (144 tests) |
| `lib/core/utils/image_metadata.dart` | JPEG: walks all segments, drops APPn between scans, **stops at EOI**. New `sanitizeProfilePhoto` (PNG chunk allow-list; anything else is re-encoded to PNG). |
| `lib/services/storage_service.dart` | `uploadProfilePhoto` sanitises first and checks the size after; unreadable images get a clear message |
| `lib/core/utils/secret_redaction.dart` | **New.** `redactDownloadTokens`, `redactErrorForReport`, `redactFlutterErrorDetails` |
| `lib/main.dart` | Crashlytics handlers record redacted errors |
| `lib/services/analytics_service.dart` | `CrashReporter.recordError` and `log` redact tokens |
| `test/core/image_metadata_trailer_test.dart`, `test/core/secret_redaction_test.dart` | **New** (9 + 5 tests) |
| `functions/src/ops/jpegMetadata.ts` | Same EOI / between-scans fix; `imageEnd`, `trailingData`, `afterScanMetadata`; validation compares SOS→EOI without APPn |
| `functions/src/ops/photoMetadataJob.ts` | `appended-data` category; `fullRead`; `uid` scope; backups deleted if the overwrite doesn't happen; `deleteBackup` (refuses non-backup paths) |
| `functions/src/ops/photoTokenRotation.ts` | **New.** Token rotation plus owner-link reconciliation; Admin adapters |
| `functions/src/ops/opsCli.ts` | `photo-token-rotate`; shared lease `_ops/photoRewrite_lease` for remediation and rotation; `--full-read`, `--uid`, `--run-id` validation; rotation resume reuses the run ID |
| `functions/src/ops/ops.test.ts` | Fake gains `deleteBackup` |
| `functions/src/ops/ops7c.test.ts`, `functions/src/ops/ops7c.emulator.test.ts` | **New** (38 unit, 8 emulator tests) |
| `functions/package.json` | Test scripts include the new files |
| `PHASE_7C_*.md` (5) | **New** deliverables |
| `REMEDIATION_CHECKLIST.md`, `KNOWN_BUGS.md` | Phase 7C entries (verified findings only) |
| `ops-out/live-rules/touchgrass-today-20261020T033322Z/` | New read-only snapshot (git-ignored). Earlier snapshots are untouched. |

**Not changed:**
- `deploy/interim/*` (SHA-256 unchanged);
- `firebase.json`, `firestore.rules`;
- `DOCUMENTATION.md`;
- Phase 7A and 7B reports;
- privacy copy;
- `STORE_LISTING.md`;
- `.vscode/settings.json`.

## 4. Security decisions and rationale

1. **Avatars get `get`, not `read`, in both files.** The leaderboard needs single-object reads; nothing needs listing.
2. **INTERIM and FINAL keep two documented, owner-only differences** (legacy name, owner delete), each with a removal condition: INTERIM is replaced by FINAL in the coordinated release. Changing INTERIM would have invalidated the pending S-1 approval for no security gain.
3. **Behaviour plus a static inventory, not text equality.** The files differ on purpose. The gate pins the exact grant set and the shared behaviour, so a future `allow read` or `{x=**}` grant fails the build.
4. **Stripping stops at EOI**, in the app and in the operator tool alike. Losing an appended depth map or motion clip is the intended privacy trade-off. The primary image is byte-identical.
5. **Token rotation rewrites the object rather than patching metadata.** A rewrite replaces all metadata, so every old token is gone, and that is testable on the emulator. The emulator merges token lists on a metadata patch, so revocation could not have been proven that way. Content is preserved and checked by MD5 before any link changes.
6. **Recommended strategy, C (staged):**
   - **C1:** S-1.
   - **C2:** rotation plus link updates, which works with today's live app.
   - **C3:** authenticated SDK reads by path.
   - **C4:** retire tokens, and decide on avatars.
   Option B (SDK reads) was designed but **not implemented**: it touches every photo screen and needs web CORS verification on a test account. A partial change would be unsafe.
7. **Rotation must follow S-1.** Under the live rules an attacker could simply fetch the new token.
8. **Privacy copy was not edited** (brief §6). Recommended corrections are in §9.

## 5. Test results (this run; local and emulator only)

| Suite | Result |
|---|---|
| Rules (Firestore + Storage), `firestore-tests` `npm test` | **568/568**, exit 0. 130 PARITY + 76 MATRIX lines, all matching. |
| Regression proof: P50 against the pre-fix `storage.rules` | Pre-fix ALLOW (leak) → fixed DENY |
| Functions unit (`npm test`) | **196/196**, exit 0. Lint: 0 problems. |
| Functions emulator (`npm run test:emulator`, Node 22.23.3) | **31/31**, exit 0 (8 new). Run twice; the final run came after the last code change (`--uid`). |
| Flutter (`flutter test`) | **479/479**, exit 0 (14 new) |
| `flutter analyze` / `dart format --set-exit-if-changed lib test` | No issues / 0 files changed |
| Web release compile into the scratchpad (no `secrets.json`; `build/web` untouched) | Exit 0. Bundle scan: the only `AIza…` key is the public Firebase web config key (hash-matched to `firebase_options.dart`); no Gemini references. |
| Dart trailer tests before the fix | **5 failed** (proving the defect), then passed after the fix |

**Not run:**
- Android/iOS builds (no native code changed);
- the `tool/` suite (no change there).

The full matrix is in `PHASE_7C_STORAGE_SECURITY_TEST_MATRIX.md`.

## 6. Remaining risks

| # | Risk | Severity | Mitigation / next step |
|---|---|---|---|
| R1 | **Live exposure continues.** Any signed-in user can enumerate uids and fetch every challenge photo's link. | **Critical** | S-1 (AC-1) |
| R2 | **Harvested token URLs stay valid after S-1.** Past harvesting is unknown. | **Critical** | C2 rotation (AC-2…AC-5) right after S-1 |
| R3 | Historical photos with GPS (count unknown); anyone holding a harvested link can read it | High | Inventory and remediation (M-1…M-6), after C2 |
| R4 | Profile-photo links are bearer links visible to every signed-in user | Medium | Disclose accurately; decide in C4 |
| R5 | Account deletion is unavailable in the live app (D-04/F12) | High (store policy, user trust) | F-1, then the coordinated release |
| R6 | Re-encoded uploads: quality is not measured perceptually; rules check only the declared type | Low | Server-side decode/re-encode, if ever needed |
| R7 | Soft delete / versioning may keep pre-rewrite generations (with GPS) recoverable by admins | Medium | Owner checks the bucket config; disclose the window |
| R8 | The atomic `ifGenerationMatch` is unverified locally (the emulator ignores it) | Low | Production canary on a test account |
| R9 | Option B web feasibility (bucket CORS) is unverified | Medium (for C3) | Test-account check before C3 |
| R10 | Notification duty for the past exposure | Legal | Owner / counsel |

## 7. Production operations NOT performed

None of the following were done:
- Storage rules deploy (S-1 or S-2);
- Firestore rules or indexes deploy;
- Functions or Hosting deploy;
- token rotation, revocation or regeneration;
- any read of, write to, move, copy or deletion of a photo object;
- metadata inventory or remediation;
- backups;
- cleanup jobs or schedules;
- user-data changes;
- billing, backup or PITR changes;
- Auth configuration;
- Maps keys;
- AI enablement;
- commit, push, stash, reset, rebase or amend.

**The only production contact** was the read-only export of rules metadata: `tool/export_live_rules.mjs` → `get_security_rules`, which GETs releases and rulesets only.

## 8. Readiness assessment

| Area | Ready? |
|---|---|
| S-1 deploy | **Ready.** Awaiting the exact Phase 7B authorization. |
| C2 token rotation | **Tool ready and tested locally.** Needs S-1 live, then AC-2 (dry-run) and AC-3 (test-account canary). |
| Historical metadata | **Tool ready and tested locally.** Needs M-1 (inventory). |
| Final rules for the coordinated release | **Ready and parity-gated.** Ships with R-1 + H-1 per the manifest. |
| New-upload metadata | **Fixed locally.** Ships with H-1. |
| Disclosures | **Not ready.** Several statements are false today (§9). |
| **Incident closure** | **No.** See the closing condition in `PHASE_7C_RELEASE_PRIVACY_CHECKLIST.md`. |

## 9. Privacy and disclosure review (review-ready; nothing published)

**Sources:**
- `lib/core/constants/privacy_copy.dart` (the in-app policy, Settings);
- `STORE_LISTING.md`;
- `PHASE_7A_PRIVACY_DISCLOSURE_DRAFT.md`.

| # | Current statement | Actual implementation | Mismatch / uncertainty | Recommended correction | Needs |
|---|---|---|---|---|---|
| G-1 | In-app: "Your challenge photos, which only you can see." | **Live:** any signed-in user can list and read them (F2). After S-1: owner-only through the app, **but** harvested links still work until C2. | **False today**; still inaccurate after S-1 alone | Publish only after S-1 + C2: "Your challenge photos are private to your account." Until then, remove the claim. | Ops (S-1, C2) + copy |
| G-2 | 7A draft: profile photo visible to "all signed-in users" | The avatar link sits in the leaderboard mirror; it opens for **anyone holding it** | Understated | "Your profile photo is shown to other TouchGrass users on the leaderboard, and can be seen by anyone they share its image link with." | Copy (or C4 change) |
| G-3 | Remove-locations dialog: "photos saved with earlier versions of the app may still contain location details inside the image file." | True for historical uploads. New uploads (7C) contain none, including appended data. | Accurate. Becomes outdated after historical remediation. | After M-5: "Location details have been removed from photos saved with earlier versions." | Ops + copy |
| G-4 | In-app: location is saved "only if 'Save location with adventures' is on" | True for Firestore fields. **Historical photo files** may embed GPS regardless of the setting. | Incomplete until remediation | Add: "Photos taken with earlier versions may contain location details inside the file until we finish removing them." | Copy (+ ops) |
| G-5 | "Settings → Delete Account permanently deletes your account and everything saved with it … photos" | `deleteAccount` is not deployed; the **live** web app's deletion fails at Firestore before Storage (F12) | **False today** | Publish only after F-1 is verified live (G4.1) | Ops + copy |
| G-6 | Retention: analytics and crash data "kept for the period set … in Firebase" | Metadata backups (14 days planned); soft-delete window unknown | Incomplete | Add backup and soft-delete windows once known | Owner facts + copy |
| G-7 | Download links | Not mentioned anywhere | Missing | "Photos are delivered through private links. If you share a photo's link, anyone with it can view that photo." (Accurate only while token URLs are used, i.e. until C3/C4.) | Copy |
| G-8 | Third parties: "stored in Google Firebase"; "Your photos are not sent to any AI service" | True in code (AI disabled; Firebase/Google Cloud only). **`STORE_LISTING.md`** says "let AI verify your adventure" and "Gemini Vision confirms…" | **The store listing contradicts the app** | Remove the AI-verification claims from the listing until AI is enabled and disclosed | Copy (store) |
| G-9 | Store listing: "Completion photos are stored in Firebase Storage under the user's UID" | True | — | Keep | — |

None of these were edited. `privacy_copy_test.dart` pins the current copy, so any change goes through review and that test.

## 10. Next action requiring explicit authorization

The **only** next step is the Phase 7B question, unchanged:

> Do you authorize me to deploy only the verified interim Firebase Storage rules file `deploy/interim/storage.interim.rules` to Firebase project `touchgrass-today`? No other production resources will be changed.

After S-1 is verified live, the next separate request is AC-2: a read-only rotation dry-run (`PHASE_7C_PHOTO_TOKEN_REMEDIATION_PLAN.md` §6).
