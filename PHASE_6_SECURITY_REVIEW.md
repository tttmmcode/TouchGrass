# TouchGrass — Phase 6 security review

**Scope:** the local repository on branch `release-hardening-pass` (HEAD `67c5a38` plus Phases 0–6, uncommitted), as of 2026-10-19.

**Evidence levels:**
- **TEST:** automated test in the repo.
- **EMULATOR:** local Firebase emulators, demo project.
- **LIVE-READ:** read-only query of the production project.
- **STATIC:** code review.

Nothing here is evidence of what is deployed. The production rules and functions have not been changed by this work, and have not been re-read beyond the app registrations.

---

## 1. Account deletion (D-04)

| Property | Status | Evidence |
|---|---|---|
| Caller can only delete themselves (uid from the verified token, never from request data) | ✔ | STATIC (`index.ts`); TEST: unsafe uids refused before anything runs |
| Recent sign-in required (≤ 5 min, small clock-skew tolerance) | ✔ | TEST (boundaries) |
| **New:** other sessions revoked *before* any data is touched | ✔ | TEST (call order); EMULATOR (`tokensValidAfterTime` changes, data still intact after a later failure) |
| Order: revoke → Storage (photos, avatar) → Firestore (completions, usernames, feedback, leaderboard, user tree) → Auth user last | ✔ | TEST: exact order asserted |
| A failure at **any** step stops later steps and a retry finishes | ✔ | TEST: 9 injected-failure cases; EMULATOR: storage and Auth failures |
| Idempotent: Auth user already gone, user with no data, data left after Auth deletion | ✔ | TEST + EMULATOR |
| Bounded batches (≤ 400) and pagination | ✔ | TEST (900 docs → 3 batches); EMULATOR (450 completions) |
| Success only after the server confirms `{deleted: true}`; no message claims success on error | ✔ | TEST (Dart) |
| **New:** the device's analytics identity is cleared on sign-out and reset after deletion | ✔ | TEST (identity transitions; reset after confirm) |
| In-app copy matches what is deleted, and says Firebase keeps analytics and crash reports for its retention period | ✔ | TEST: copy tied to `accountDeletion.ts` |
| Deployed | ✖ | Not deployed. The privacy text promises deletion, so **deploy before release** (runbook §7, stage 3). |

**Residual risks:**
- *Low:* a second device can keep writing for up to an hour with its existing ID token, because rules can't check revocation. Revoking first shortens this to the life of that one token.
- Analytics events Google already holds remain until retention expires, or until you use the GA4 user-deletion API (runbook §8.7).

## 2. Profile-photo URL trust (N-6)

- **Before:** the rules accepted any string up to 2048 characters as `photoUrl`, and every leaderboard viewer's device loaded it. That let one user collect other users' IP addresses and user agents, or show arbitrary content.
- **Now (rules, EMULATOR, 35 new cases):** `isAllowedProfilePhoto` accepts only:
  - `null`;
  - the caller's own `user_avatars/{uid}.png` in **this app's bucket** (`touchgrass-today.firebasestorage.app`);
  - exactly the `picture` claim of the caller's verified ID token (Google sign-in).
  It applies to sign-up and to edits. Refused: other users' avatars, other buckets, completion photos, traversal, `http`, `javascript:`, empty, non-string and over-long values, and a valid photo combined with a protected field. Mutation check: the old permissive rule makes 20 of the 35 fail.
- **Client:** sign-up stores the token's `picture` claim, so it matches the rule by construction (TEST, 8 cases). When the claim is missing, the profile starts with initials instead of failing sign-up.
- The leaderboard renders other users' photos only from the app's bucket or `*.googleusercontent.com`, and falls back to initials on any error (Phase 5, TEST).
- **Legacy:** stored external URLs stay readable and mirrorable, so no migration is forced. Their owners can't switch to another external URL. A read-only inventory and a migration plan are in runbook §11.
- **Deployment notes:**
  - *Unverified:* that Google ID tokens carry `picture` in production. If they don't, Google users start without a photo, which degrades the experience but doesn't break sign-up.
  - The bucket name is written into `firestore.rules`; a staging project needs that line changed.

## 3. Firestore and Storage access control

The full suite, **310 emulator tests**, passes against the local rules.

| Feature | Path(s) | Client may | Protections verified |
|---|---|---|---|
| Sign-up | `users/{uid}`, `usernames/{name}` | create own | defaults only, server timestamps, owns the username, allowed photo |
| Profile edit | `users/{uid}` | update own | allow-listed fields; photo rule; no `uid`/`email`/`createdAt`/`entitlementTier` change |
| Complete a challenge | `completions/{uid}_{date}` + `users/{uid}` + `memories/{id}` | create, plus the reward in one batch | date within ±1 day, own photo path, XP equals the difficulty, streak/freeze/achievement transitions exact, one per date |
| Rerolls | `users/{uid}/challenges/{date}` | create/update own | cap 3, +1 only, no delete |
| Journal | `users/{uid}/memories/*` | create (mirrors own completion), caption edit, delete own | XP and photo must equal the completion |
| Journal repair | same | create only | can't overwrite; can't touch XP |
| Remove saved locations | `completions/*`, `memories/*` | delete location fields only | `removesOnly`: nothing set, nothing else changed, owner only |
| Leaderboard | `leaderboard_public/{uid}` | write own mirror equal to own profile; read when signed in | can't show values the profile rules wouldn't allow |
| Feedback | `feedback/{uid}_{date}_{n}` | create ≤ 5/day | no read/update/delete |
| Storage photos | `completion_photos/{uid}/{date}.jpg`, `user_avatars/{uid}.png` | write own; read own (avatars: any signed-in user) | content types, size caps, no SVG, no client delete |
| Server-only | `users/*/aiUsage`, `_ops/*`, `metadata_backup/*` (Storage) | nothing | default deny |

**Index check:** the "Remove saved locations" query is `where userId ==` ordered by document ID. Firestore's documentation says every index already ends with an implicit `__name__` ordering and equality queries use the automatic single-field indexes, so no composite index should be needed. The emulator can't confirm this. Check it once in production with a test account; a missing index fails visibly ("failed"), never silently.

## 4. Historical photo metadata (N-7)

- **New uploads:** stripped before upload. TEST: all 8 EXIF orientations come out upright with no GPS; GIF and TIFF are re-encoded without metadata; truncated and random input is refused.
- **Historical photos:**
  - A read-only inventory reads metadata headers only and reports counts, never coordinates.
  - Remediation is lossless and in place. It keeps the download token, content type and cache control, and keeps a minimal orientation-only EXIF for rotated photos.
  - It validates each replacement before writing (complete JPEG, no GPS/XMP, same orientation, byte-identical image data).
  - It writes only if the generation is unchanged, keeps a server-only backup and records a reversible manifest. Dry-run is the default.
  - TEST: 39 cases. EMULATOR: the saved download URL still works after rewriting.
- **Not done:** no production scan. Until the inventory runs, the number of affected photos is unknown.
- **Emulator limit:** the Storage emulator ignores `ifGenerationMatch`. A read-check is tested; the atomic precondition is real-Cloud-Storage only.

## 5. Cleanup-job deletion safety (D-16)

- **Eligibility:** all checks must pass. Name is `completion_photos/{safe uid}/{real date}.jpg`; date and object both ≥ 7 days old; generation known; no completion; no Journal entry; the profile exists.
- **Before deleting:** a Firestore re-check, then a generation read-check and `ifGenerationMatch`.
- **Defaults and limits:** dry-run is the default; delete needs exactly `delete` mode. Caps: 2000 inspected and 100 deleted per run. A Firestore **lease** prevents overlapping runs (EMULATOR: exactly one of four concurrent attempts wins).
- **Outcomes:** one code per object (operator file only; logs carry counts).
- **Not deployed or scheduled.** A test fails if `index.ts` exports it.

## 6. Android signing and build gates (X-6, X-5)

- **Signing:** the release build no longer falls back to the debug key.
  - Without a complete `key.properties` it stops early, listing what's missing. Verified on the repo, and on the scratchpad copy with a corrected `google-services.json`.
  - With a throwaway TEST-ONLY key, the release APK built and `apksigner` verified it: the signer equals the test key, differs from the debug key, and v2 signing is in use.
  - The APK has no `debuggable` flag, no cleartext or localhost entries, and no Crashlytics mapping upload. `package=com.touchgrass.app`, minSdk 24, targetSdk 36.
  - The test key and `key.properties` were deleted afterwards. No real signing identity was created.
- **Firebase config:** every Android build stops with an owner-actionable message when `google-services.json` has no app for `com.touchgrass.app` (the current state).
- **Ignored files:** `.gitignore` now also covers `*.p12`, `*.pem`, service-account JSON, `.env*` and `ops-out/`. Keystores and `key.properties` were already covered.

## 7. Firebase configuration

- **LIVE-READ (2026-10-19):** the project has Android `com.example.touchgrass` (no SHA fingerprints), iOS `com.example.touchgrass`, and two web apps. There is no app for `com.touchgrass.app`.
- **`tool/check_firebase_config.mjs`:** 19 consistency checks across Gradle, `google-services.json`, `firebase_options.dart`, the Xcode project, the iOS plist, entitlements and `firebase.json`. It currently fails 9, all owner-side (registration, plist, entitlements). Against a correctly registered copy, every Android check passes.
- Firebase client config (API keys, app IDs) is public by design and is not treated as a secret. Real protection comes from the rules and from key restrictions (X-4).

## 8. Secrets

- **Working tree** (tracked plus untracked, non-ignored): no private keys, service-account keys, Gemini-style keys, non-allow-listed `AIza` keys, keystores or signing passwords. Hits were placeholders and property lookups only.
- **Web bundle scan:** clean (see the final report).
- The revoked Gemini key was neither used nor searched for by value.
- **AI verification:** a new hard switch, `AI_VERIFICATION_ENABLED = false`, makes `verifyChallengeCompletion` refuse every call before auth, data or Gemini, even if deployed by mistake (TEST).

## 9. Dependency vulnerabilities

| Scope | Result |
|---|---|
| `functions/` (production deploy) | `npm audit`: 0 (firebase-admin 14.5.0, firebase-functions 7.4.0, Node 22) |
| `firestore-tests/` (dev-only emulator tooling) | **0, was 5 high.** `@grpc/grpc-js` is pinned to ≥ 1.14.3 (installed 1.14.6) through npm `overrides`, because even the newest `@firebase/firestore` pins `~1.9`. The full 310-test rules suite passes on 1.14.6. |
| Dart (OSV, Pub) | 0 known in 185 hosted packages. OSV's Pub coverage is limited. |

## 10. Older-app compatibility

| Change | Effect on already-installed builds |
|---|---|
| Photo rule | Sign-up and avatar upload keep working (old clients write the provider photo or the Storage URL). A crafted external URL is refused. |
| `removesOnly` branches | Additive; old clients never use them. |
| Account-deletion function | Old clients don't call it; nothing changes. |
| Analytics identity, gates, wording | Client-only; affects new builds only. |

## 11. Remaining release blockers

1. **X-5:** register `com.touchgrass.app` (Android and iOS) and download the config files.
2. **X-6:** create and back up the upload key.
3. **iOS** on a Mac: pods, entitlements (Sign in with Apple, Push), signing, a real-device test.
4. **Deploy (separate approvals):** rules, then `deleteAccount`, then the app. Export the live rules first (X-2).
5. **X-4:** restrict the Maps keys.
6. **X-8 / X-11:** hosted privacy policy, Data Safety form and privacy labels.
7. **N-7:** run the inventory, then remediate if needed.

## Deployment manifest

| # | Artifact | Depends on | Can deploy alone? | What may fail meanwhile |
|---|---|---|---|---|
| R | `firestore.rules`: N-6 photo rule, `removesOnly`, Phases 1–5 rules | — | Yes, **first**. Old clients stay compatible (§10). | Nothing legitimate. Crafted photo URLs are refused. |
| S | `storage.rules` (Phase 1+) | X-2 comparison | Yes, together with R | — |
| F1 | `functions:deleteAccount` (admin 14 / functions 7, Node 22) | Blaze, enabled APIs | Yes, after R | Before F1, in-app deletion reports "isn't available right now" (honest). |
| A | App builds (new client) | R (Remove saved locations needs it), F1 (Delete Account needs it), X-5, X-6 | No: needs R and F1 first | If shipped before R: Remove saved locations reports "failed" and changes nothing. If shipped before F1: Delete Account fails honestly. |
| F2 | `functions:orphanPhotoCleanupJob` (scheduled) | separate approval; two clean weekly dry-runs | Optional, last | — |
| Ops | photo-metadata remediation, profile-photo migration | authorization; inventory first | Independent operator runs | — |
| — | `verifyChallengeCompletion` | **never deploy** while AI is off; guarded off in code | — | — |
| — | `firestore.indexes.json` | unchanged this phase | — | — |
