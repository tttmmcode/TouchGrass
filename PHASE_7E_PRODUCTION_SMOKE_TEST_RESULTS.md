# Phase 7E — Production Storage Smoke Test Results (S1–S9)

**Status: CONTAINED AT RULES LEVEL — verified on the live endpoint.** 32/32 checks behaved as expected.

**Separately confirmed in production:** previously issued token URLs still work without sign-in. That is an outstanding risk the rules can't address.

## Run

| | |
|---|---|
| Authorization | Explicit, for exactly this scope (Phase 7E): 2 new test accounts, synthetic test objects in the test account's own paths, cleanup, no Firestore writes |
| Target | `touchgrass-today`, bucket `touchgrass-today.firebasestorage.app`, through the public web config in `lib/firebase_options.dart` (the same path the web app uses). The script refuses any other target. |
| Live rules at run time | `630dc9a0…dcff17` (interim). A read-only export at 05:01Z was byte-identical to `deploy/interim/storage.interim.rules`. |
| When | 2026-10-20 **05:26:05Z – 05:26:16Z**, run tag `b6827f34` |
| Accounts | 2 new dedicated test accounts (`tg-smoke-a/b-<run>@example.com`). Random passwords were held in memory only and never printed or stored. Called **A** (owner) and **B** (other user); uids are not recorded. |
| Test data | 1×1 synthetic JPEG/PNG; zero-filled buffers for the size checks. No real photo was read or displayed. |
| Tool | `p7e/live_smoke.cjs` (scratchpad; Firebase JS SDK 11.10.0) |
| Rehearsal | The same script against local emulators loaded with the interim rules: 32/32, cleanup complete |
| Cleanup | A deleted its test photos (0 left). Both test Auth users deleted. **Leftover:** `user_avatars/<A>.png`, a 1×1 PNG that clients can't delete under the interim rules. The owner can delete it in the console, or leave it (no personal data). |
| Evidence type | SDK call outcome (ALLOW, or DENY with `storage/unauthorized`); HTTP status for the token check. No tokens, URLs, uids or bytes were recorded. |

## Results

Every check passed.

| ID | Preconditions | Operation | Expected | Actual | Error (sanitized) |
|---|---|---|---|---|---|
| S7a | A signed in | Upload `completion_photos/A/{timestamp}.jpg`, `image/jpeg` (live web app shape) | ALLOW | ALLOW | — |
| S7b | A | Upload `completion_photos/A/{yyyy-MM-dd}.jpg` (new app shape) | ALLOW | ALLOW | — |
| S5a | A owns the photo | `getBytes` own photo | ALLOW | ALLOW | — |
| S5b | A | Own download URL + metadata (URL kept in memory only) | ALLOW | ALLOW | — |
| S5c | A | List own folder | ALLOW | ALLOW | — |
| S4a | Not signed in | Read A's photo | DENY | DENY | storage/unauthorized |
| S4b | Not signed in | List A's folder | DENY | DENY | storage/unauthorized |
| S4c | Not signed in | Upload into A's folder | DENY | DENY | storage/unauthorized |
| S3 | B signed in | List `completion_photos/` (uid enumeration) | DENY | DENY | storage/unauthorized |
| S2 | B | List A's folder | DENY | DENY | storage/unauthorized |
| S1a | B | `getBytes` A's photo | DENY | DENY | storage/unauthorized |
| S1b | B | `getDownloadURL` A's photo | DENY | DENY | storage/unauthorized |
| S1c | B | `getMetadata` A's photo | DENY | DENY | storage/unauthorized |
| X1 | B | Upload into A's folder | DENY | DENY | storage/unauthorized |
| X2 | B | Overwrite A's photo | DENY | DENY | storage/unauthorized |
| X3 | B | Change A's photo metadata | DENY | DENY | storage/unauthorized |
| X4 | B | Delete A's photo | DENY | DENY | storage/unauthorized |
| X5 | B | List the bucket root | DENY | DENY | storage/unauthorized |
| S6a | A | Upload `text/html` | DENY | DENY | storage/unauthorized |
| S6b | A | Upload `image/svg+xml` | DENY | DENY | storage/unauthorized |
| S6c | A | Upload exactly 10 MB | DENY | DENY | storage/unauthorized |
| S6d | A | Upload `page.html` (arbitrary name) | DENY | DENY | storage/unauthorized |
| S6e | A | Upload to a nested path | DENY | DENY | storage/unauthorized |
| S8a | A | Upload `user_avatars/A.png`, `image/png` (live web app shape) | ALLOW | ALLOW | — |
| S8b | B | GET A's single avatar (leaderboard) | ALLOW | ALLOW | — |
| S8c | Not signed in | Read A's avatar | DENY | DENY | storage/unauthorized |
| S8d | B | List `user_avatars/` (enumeration) | DENY | DENY | storage/unauthorized |
| S8e | B | Overwrite A's avatar | DENY | DENY | storage/unauthorized |
| S8f | A | Avatar with `text/html` | DENY | DENY | storage/unauthorized |
| S8g | A | Avatar of exactly 5 MB | DENY | DENY | storage/unauthorized |
| X6 | A | List own `metadata_backup/…` (server-only) | DENY | DENY | storage/unauthorized |
| S9 | A | Delete own test photos (cleanup; live app's deletion shape) | ALLOW | ALLOW | — |

## Token URLs: not governed by rules (outstanding risk, measured)

| ID | Operation | Result |
|---|---|---|
| T1 | Fetch A's own download URL **without signing in** | **HTTP 200**: a bearer link works for anyone who holds it |
| T1b | The same URL with a random token | HTTP 403 |

So rules containment stops **new** links from being obtained by other users (S1b), but every link issued earlier, including those harvested under the old rules, still works. That stays open until the token rotation is proven (`PHASE_7E_TOKEN_ROTATION_STATUS.md`).

## Not covered by this run (owner, in a browser)

The UI paths of the live web app are not exercised end to end:
- sign up;
- complete a challenge with a photo;
- see it in the Journal;
- change the avatar.

The Storage calls those screens make were reproduced exactly (S7a, S5b, S8a). Firestore writes were deliberately excluded: the live rules make completions undeletable, so test data would stay behind.
