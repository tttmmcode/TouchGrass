# TouchGrass — Phase 6 final report (2026-10-19)

## Executive summary

**Decision: not ready to release.** The engineering work that can be done locally is complete, and the app is **ready for controlled release preparation**. What remains needs owner credentials, a Mac, or deployment approvals:
- Firebase app registration;
- the upload key;
- iOS signing and entitlements;
- three production deploys: rules, then `deleteAccount`, then the apps.

This phase:
- **Account deletion:** made it more robust and its wording exact.
- **Profile photos:** closed the arbitrary-URL hole at the rules level.
- **Old photos:** built a safe, tested way to find and remove GPS from historical photos.
- **Cleanup job:** hardened it.
- **Android:** release builds can no longer be silently debug-signed, and builds fail clearly on missing Firebase config.
- **iOS:** fixed a blocker (deployment target).
- **Dependencies:** cleared the last dependency advisories.

Everything passes:
- 460 Flutter tests;
- 152 Functions unit tests, 23 emulator tests and 310 rules tests, all on Node 22.23.3;
- analyze, format, the web build and every audit.

No production change, commit or push happened.

## Initial repository state (verified)

- **Branch and HEAD:** `release-hardening-pass` at `67c5a38`.
- **Working tree:** 137 uncommitted entries from Phases 0–5, identical to the end of Phase 5. All were preserved, and backups of every file this phase edited are in the scratchpad (`p6/bak/`).
- **`DOCUMENTATION.md`:** SHA-256 `baa43787aad0a31987f3c894db09c67df4cfe05650d56d813027cbb62a9f94bc`, unchanged at the end.
- **Phase 5 numbers:** confirmed (431 / 94 / 275 / 12, audit 0).
- **Firebase CLI:** working again for read-only calls. Live state: Android and iOS registered only as `com.example.touchgrass`, and no SHA fingerprints.

## Issues, root causes and fixes

| ID | Root cause | Fix (local) |
|---|---|---|
| D-04 | Deletion wasn't deployed; another signed-in device could keep refreshing during deletion | Refresh tokens revoked **before** any data; order fixed (revoke → Storage → Firestore → Auth); 17 new unit tests (failure at every step stops later steps, and a retry finishes); 3 new emulator tests (revocation, empty account, Auth already gone) |
| P6-A2 | Analytics and Crashlytics user IDs survived sign-out and deletion | Identity cleared on sign-out; analytics data reset after a confirmed deletion |
| P6-A3 | Privacy text claimed "delete … its data" without exceptions | Exact deletion scope, plus "usage analytics and crash reports already sent to Firebase are kept for the period set for this app in Firebase"; test ties the wording to `accountDeletion.ts` |
| N-6 | Rules accepted any profile photo URL, which every leaderboard viewer's device loaded | `isAllowedProfilePhoto`: null, the own avatar in the app bucket, or the token's `picture` claim. Sign-up stores the token claim, so it can't fail the rule. 35 emulator cases; reverting to the old rule fails 20 of them |
| N-6b | Legacy external URLs may already be stored | Read-only inventory tool and migration plan; no data changed |
| N-7 | Photos from released versions may carry GPS | Lossless in-place stripper (keeps the download token; orientation-only EXIF for rotated photos), header-only inventory, validated replacement, generation-guarded write, backup and manifest, dry-run by default, guarded CLI |
| C-1 | Upload stripping coverage gaps | Tests for all 8 orientations, GIF, TIFF, truncated and random input |
| D-16 | Cleanup gave no per-object reasons and had no overlap guard | Outcome codes, a Firestore lease, a CLI dry-run, and a synthetic-volume test (322 objects → exactly 6 eligible) |
| X-6 | Release fell back to the **debug key** | Fallback removed; release stops early when `key.properties` or the Maps key is missing |
| X-5 | No Firebase app for `com.touchgrass.app` | Gradle gate with an actionable message; `tool/check_firebase_config.mjs` (19 checks) |
| iOS-1 | `google_maps_flutter_ios` 2.18.3 needs iOS 14; the Runner targeted 13.0 | Deployment target raised to 14.0 |
| iOS-3 | Permission texts mentioned "verification"; an unused add-to-library purpose was declared | Accurate texts; unused key removed |
| AI-1 | A mis-deploy could run AI verification | `AI_VERIFICATION_ENABLED = false`, checked before auth, data or Gemini |
| DEP-1 | `firestore-tests` grpc-js 1.9 (5 high, dev-only) | npm `overrides` to 1.14.6; the full rules suite passes |
| A11Y-1 | Weather label untested | Extracted and tested |

**Bug caught by the new tests:** the photo stripper's verification treated the orientation-only EXIF it writes as removable metadata. That would have made every rotated photo fail verification and be re-processed on every run. Fixed: an orientation-only EXIF block is now recognised as clean.

**Leaderboard (D-12), recommendation:** no defect is fixable without a schema change, so nothing was changed. The smallest safe path is Option A (rules-only, no Functions cost), in two releases:
1. **Release N:** clients also write `weekIndex` (Monday 00:00 UTC weeks). The rules *accept* it but don't require it, so older clients keep working. Freeze purchases must also update an existing mirror.
2. **Release N+1, once most users have updated:** query `where currentLeague == L and weekIndex == current orderBy weeklyXp desc limit 30`, add the composite index, and add an `allow list` limit.

Name moderation and showing your own rank outside the top 30 are product decisions. Option B (a server trigger) is the long-term authoritative model once Functions are in use anyway.

## Files changed in Phase 6

**Functions**
- `functions/src/accountDeletion.ts`, `accountDeletion.test.ts`, `accountDeletion.emulator.test.ts`
- `functions/src/index.ts` (AI guard), `rewards.ts`, `rewards.test.ts`
- `functions/src/orphanPhotoCleanup.ts`, `orphanPhotoCleanup.test.ts`, `orphanPhotoCleanupJob.ts` (outcome codes, lease)
- **new** `functions/src/ops/`: `jpegMetadata.ts`, `photoMetadataJob.ts`, `profilePhotoInventory.ts`, `lease.ts`, `opsCli.ts`, `testJpeg.ts`, `ops.test.ts`, `ops.emulator.test.ts`
- `functions/package.json` (test scripts only)

**Rules and rules tests**
- `firestore.rules` (photo rule)
- `firestore-tests/test/profile_photo.test.mjs` (**new**), `users.test.mjs`, `helpers.mjs`
- `firestore-tests/package.json`, `package-lock.json` (grpc-js override), `README.md`

**App**
- `lib/repositories/user_repository.dart`, `lib/services/analytics_service.dart`, `lib/providers/user_providers.dart`
- `lib/core/constants/privacy_copy.dart`, `lib/features/settings/screens/settings_screen.dart`, `lib/features/home/screens/home_screen.dart`

**App tests** (all **new** except one)
- `test/providers/analytics_identity_test.dart`
- `test/repositories/sign_in_photo_test.dart`
- `test/core/image_metadata_formats_test.dart`
- `test/features/home/weather_chip_label_test.dart`
- `test/core/privacy_copy_test.dart` (existing, extended)

**Platforms**
- `android/app/build.gradle.kts` (gates; no debug fallback)
- `ios/Runner.xcodeproj/project.pbxproj` (iOS 14.0), `ios/Runner/Info.plist` (permission texts; CRLF kept)

**Tools and repo hygiene**
- **new** `tool/check_firebase_config.mjs`
- `.gitignore` (`ops-out/`, `*.p12`, `*.pem`, service-account JSON, `.env*`)

**Docs**
- **new** `PHASE_6_FINAL_REPORT.md`, `PHASE_6_RELEASE_RUNBOOK.md`, `PHASE_6_SECURITY_REVIEW.md`
- `REMEDIATION_CHECKLIST.md` (Phase 6 section, X-5 and X-6 rows), `KNOWN_BUGS.md` (Phase 6 note, A27, B7, B11)

**Touched by tools, content unchanged**
- `pubspec.lock`: rewritten by `flutter pub get`; byte-identical.
- `android/local.properties`: rewritten by Flutter; gitignored.

## Tests run (this phase, final run)

| Check | Command | Exit | Result |
|---|---|---|---|
| Format | `dart format --output=none --set-exit-if-changed lib test` | 0 | clean |
| Analyze | `flutter analyze` | 0 | No issues |
| Flutter tests | `flutter test` | 0 | **460 passed** |
| Web build | `flutter build web --release` | 0 | built |
| Web secret scan | `node tool/check_web_bundle_secrets.mjs` | 0 | clean (17 files); 0 Gemini or Generative Language references |
| Functions type check, lint (Node **v22.23.3**, checked) | `npx tsc --noEmit`, `npm run lint` | 0 / 0 | clean |
| Functions unit | `npm test` | 0 | **152/152** (rewards 51, deletion 27, cleanup 35, ops 39) |
| Functions emulator | `npm run test:emulator` | 0 | **23/23** (deletion 9, cleanup 6, ops 8) |
| Rules emulator | `cd firestore-tests && npm test` | 0 | **310/310** |
| Rule mutation checks | old photo rule / `removesOnly` → permissive | 1 (expected) | 20 of 35 and 14 of 25 fail; restored |
| Audits | `npm audit` (functions, `--omit=dev`, firestore-tests) | 0 / 0 / 0 | 0 vulnerabilities each |
| Dart advisories | OSV querybatch, 185 hosted packages | — | 0 known (limited coverage) |
| Source secret scan | tracked + untracked, non-ignored, 311 files | — | 0 real; 6 placeholder or property hits |
| Config check | `node tool/check_firebase_config.mjs` | 1 (expected) | 10 pass, 9 fail, all owner-side; on a correctly registered copy every Android check passes |
| Operator CLI | rehearsal in the emulators; refusal outside them | 0 / 2 | counts only on stdout; refuses a real project without flags |
| Android debug (repo) | `flutter build apk --debug` | 1 (expected) | **stopped by the X-5 gate**, with the fix in the message |
| Android release (repo) | `flutter build apk --release` | 1 (expected) | stopped: X-5, plus missing `key.properties` |
| Android release (copy with a corrected config, no key) | same | 1 (expected) | stopped: missing `key.properties` only |
| Android release (copy, TEST-ONLY key) | same | 0 | built; `apksigner`: verifies (v2), signer = test key ≠ debug key; `com.touchgrass.app`, minSdk 24, targetSdk 36, not debuggable, no Crashlytics upload |
| iOS | — | — | **not built** (Windows); static checks only |

**Process notes:**
- One intermediate Node run silently used v26 because Windows temp cleanup had deleted the extracted Node 22 again. It was discarded. I re-verified the zip's checksum and re-ran with the version asserted first.
- The test key and its `key.properties` existed only in the scratchpad and were deleted after use.

## Security and privacy improvements
Detailed in `PHASE_6_SECURITY_REVIEW.md`:
- Deletion now revokes other sessions first and resets the device's analytics.
- Photo URL trust is enforced server-side, so old clients are covered once the rules are deployed.
- There is a reversible path to remove GPS from historical photos.
- Cleanup has an overlap guard and per-object reasons.
- Debug signing can't leak into a release.
- AI verification is hard-off.
- No dependency advisories remain anywhere, test tooling included.

## Remaining risks
- **High (release blockers):** X-5, X-6, and the iOS entitlements and signing. `deleteAccount` isn't deployed while the app promises deletion.
- **Medium:**
  - Old installed versions remain exposed to N-6 until the rules are deployed.
  - The historical-photo GPS volume is unknown until the inventory runs.
  - Google `picture` claims are unverified in production; if absent, users simply start without a photo.
- **Low:**
  - A second device's existing ID token can write for up to an hour after deletion.
  - The location-removal index needs one production confirmation.
  - The Storage emulator can't prove `ifGenerationMatch`.
  - HEIC from some devices would be refused with a message (device test).

## Blocked items and owner actions (in priority order)

1. **Register the apps:** `com.touchgrass.app` for Android (with SHA fingerprints) and iOS, then run `flutterfire configure` (runbook §1).
2. **Upload key:** create it and back it up; fill in `key.properties` and the Maps key (§3). Then build and verify (§4).
3. **Rules:** export the live rules and compare them with the local ones (§6).
4. **Approve stage 1**, the rules deploy, then stage 3, `deleteAccount` by name; run the controlled deletion test (§7, §8).
5. **iOS on a Mac:** pods, the Sign in with Apple and Push capabilities, the APNs key, signing, archive, a device test (§5).
6. **Maps keys:** restrict them (X-4). Publish the hosted privacy policy and the Data Safety form (X-8, X-11), matching the new deletion wording.
7. **Authorize the operator inventories:** photo metadata and profile photos (§9, §11), then decide on remediation.
8. **Later:** cleanup-job enablement, and the leaderboard decisions.

## Local completion vs. production verification
Everything above is **implemented and tested locally**. **Nothing is verified in production** except the read-only app registration. **Nothing is deployed.** No release artifact was signed with a real key or uploaded.

## Confirmations
- No commits, pushes or branch changes.
- No deploys. No production data, rules, indexes, apps, services or billing changed.
- No production scan or deletion was run.
- AI photo verification is still disabled, and now also hard-disabled in the server code. No Gemini key was used or added.
- `DOCUMENTATION.md` SHA-256 is unchanged: `baa43787aad0a31987f3c894db09c67df4cfe05650d56d813027cbb62a9f94bc`.
