# TouchGrass — Remediation Checklist

This checklist tracks every finding in `TOUCHGRASS_AUDIT_REPORT.md` (audit of 2026-10-17, HEAD `67c5a38`), from the fix through its regression test, verification result, and any remaining blocker. I update it at the end of every remediation phase.

**Status values**
- **OPEN**: not started.
- **IN PROGRESS**
- **PASS**: the fix is implemented and its acceptance criteria are shown by tests or builds.
- **FAIL**: attempted, but the acceptance criteria are not met.
- **BLOCKED**: waiting on an external action or an approval.
- **NOT VERIFIED**: implemented, but the evidence isn't sufficient yet.

**Evidence levels**
- **STATIC**: a code trace.
- **TEST**: an automated test in the repo.
- **EMULATOR**: the local Firebase emulator, on a `demo-` project.
- **LIVE-READ**: a read-only HTTP request to the public site.
- **CONSOLE**: needs access to the Firebase or Google Cloud console, which this environment doesn't have.

Emulator evidence never proves what is deployed in production.

---

## Phase 0 — Baseline (2026-10-17)

### Repository state
| Item | Value |
|---|---|
| Branch | `release-hardening-pass`, tracking `origin/release-hardening-pass`, nothing ahead or behind |
| HEAD | `67c5a38` (tree `3a935cb0…`), the same commit the audit covered |
| Working tree | Only `?? DOCUMENTATION.md`, which is your file and is preserved. Phase 0 adds `TOUCHGRASS_AUDIT_REPORT.md` and this checklist, both documentation only. |
| Uncommitted app changes | None |

### Toolchain
| Tool | Version | Note |
|---|---|---|
| Flutter / Dart | 3.44.1 stable / 3.12.1 | — |
| Node / npm | 26.3.0 / 11.16.0 | `functions/package.json` pins `engines.node = 20`. Local Functions tests run on Node 26, so the deploy runtime is not reproduced locally. |
| Firebase CLI | 15.19.1 | Needs Java 21 or newer for emulators. |
| Java | System 17.0.12; Android Studio JBR 25.0.2 at `C:\Program Files\Android\Android Studio1\jbr` | Emulators only run with `JAVA_HOME` pointing at the JBR. |
| Xcode | Not available (Windows) | iOS builds cannot be done here. |

### Firebase configuration in the repo (STATIC; not checked in the console)
| Item | Value |
|---|---|
| Default project | `touchgrass-today` (`.firebaserc`) |
| Hosting targets | `main` → site `touchgrass` (`touchgrass.web.app`); `today` → site `touchgrass-today`. Both deploy from `build/web`. |
| Functions | One codebase, `functions/`, never deployed (per functions/README; CONSOLE to confirm) |
| Rules files | `firestore.rules` (compiles); `storage.rules` (**doesn't compile**, see D-05) |
| Android Firebase app | package `com.example.touchgrass`, but the Gradle `applicationId` is `com.touchgrass.app` |
| iOS Firebase app | `iosBundleId: com.example.touchgrass`, but Xcode uses `com.touchgrass.app`. No `GoogleService-Info.plist`. |

### Test and build commands
| Purpose | Command |
|---|---|
| Dependencies | `flutter pub get --enforce-lockfile` |
| Static analysis | `flutter analyze` |
| Flutter tests | `flutter test` |
| Format check (no writes) | `dart format --output=none --set-exit-if-changed lib test` |
| Functions typecheck | `npx --prefix functions tsc --noEmit -p functions` |
| Functions tests | `npm --prefix functions test` (also builds into the gitignored `functions/lib/`) |
| Functions lint | `npm --prefix functions run lint` |
| Functions dependency audit | `npm --prefix functions audit --omit=dev` |
| Web release build | `flutter build web --release` (run **without** `--dart-define-from-file=secrets.json`) |
| Android debug build | `flutter build apk --debug` |
| Rules probes | Not in the repo yet. The audit probe script is in the session scratchpad (`rulestest/audit.test.mjs`) and moves into the repo in Phase 1 (task P0-0). |

### Baseline results (re-run in Phase 0)
| Check | Exit | Result | Time | Same as audit run? |
|---|---|---|---|---|
| pub get | 0 | Resolved from the lockfile; lockfile unchanged | 9 s | Yes |
| flutter analyze | 0 | No issues found | 185 s | Yes |
| flutter test | 0 | **235 passed**, 0 failed, 0 skipped | 48 s | Yes |
| dart format check | 1 | 62 of 130 files would be reformatted (check only, nothing written) | 6 s | Yes |
| functions tsc | 0 | Clean | 14 s | Yes |
| functions test | 0 | **49 passed**, 0 failed | 19 s | Yes |
| functions lint | 2 | **Broken**: "ESLint couldn't find a configuration file" | 14 s | Yes |
| functions npm audit | 1 | 15 vulnerabilities (1 critical, 4 high, 10 moderate) | 8 s | Yes |
| web release build | 0 | Built, 4,565,401-byte `main.dart.js`. **No Gemini key and no `AQ.`-shaped strings in the bundle** (built without `secrets.json`). | 269 s | Yes |
| android debug build | 1 | **Fails** at `:app:processDebugGoogleServices`: no client for `com.touchgrass.app` in `google-services.json` | 157 s | Yes |
| Rules emulator probe | (audit run) | 22 probes. The results are listed per finding below. I didn't re-run it because the rules files are byte-identical to the audited commit. Phase 1 re-runs it as an in-repo test suite. | — | n/a |

---

## Evidence classification

### Independently verified facts
| # | Fact | Evidence |
|---|---|---|
| V-1 | **Both live sites currently serve the Gemini API key from `secrets.json`** inside `main.dart.js`. The two sites serve an identical bundle (sha256 prefix `eebdffefb406cc5c`, 4,571,189 bytes). | LIVE-READ: `curl` of `https://touchgrass.web.app/main.dart.js` and `https://touchgrass-today.web.app/main.dart.js`, compared locally against `secrets.json`. The key was never printed or sent anywhere. |
| V-2 | The Gemini key is **not** in any tracked file or anywhere in git history. | `git grep -F`, `git log --all -S` |
| V-3 | `storage.rules` fails to compile (line 8, the `{userId}.png` segment; line 35). | EMULATOR rules load |
| V-4 | Leaderboard mirror forgery, profile create with arbitrary XP, repeated +4000 XP writes, `streakFreezesOwned = 999`, `createdAt` rewrite, arbitrary achievements, fabricated completions, client-writable `xpReward`, username takeover: all **allowed** by the current rules. | EMULATOR (audit run) |
| V-5 | A user's own completion delete, own `users/{uid}` delete, and own completion-photo delete are all **denied** (account deletion can't succeed). | EMULATOR |
| V-6 | Server-set `entitlementTier` makes every client update to that user's profile get **denied**. | EMULATOR |
| V-7 | Cross-user reads of profiles, completions and completion photos are denied. Self-granting a tier or writing `aiUsage` is denied. | EMULATOR |
| V-8 | `flutter build apk --debug` fails with `No matching client found for package name 'com.touchgrass.app'`. | Build (audit run plus Phase 0 re-run) |
| V-9 | Live hosting: `index.html`, `flutter_bootstrap.js` and `flutter_service_worker.js` are all served with `Cache-Control: max-age=3600`. `/robots.txt` returns the SPA `index.html`, so there's no real robots file. There are no Open Graph, Twitter or canonical tags. The favicon is 917 bytes, matching Flutter's default. HSTS is on. | LIVE-READ |
| V-10 | D-01 (no XP on day one / on an explicit-sign-in day), D-09 (location toggle never read), D-11 (stale challenge after midnight), D-14 (location prompt shown before its primer) | STATIC only. Phase 2 and 3 add tests that reproduce these before fixing them. |

### Assumptions, not yet verified
| # | Assumption | How to verify |
|---|---|---|
| A-1 | Cloud Functions have never been deployed. | **Verified 2026-10-17:** `firebase functions:list --project touchgrass-today` returned "No functions found". |
| A-2 | The project is on the Spark (free) plan. | **Still unverified.** The CLI has no read-only billing query. Check Console → Usage and billing. Phase 1 followed the no-Blaze path. |
| A-3 | Production Firestore rules match the repo's `firestore.rules` (KNOWN_BUGS says they were deployed on 2026-08-12). | CONSOLE: Firestore → Rules → history |
| A-4 | What the live Storage rules are. Unknown, because the repo file can't be deployed. | CONSOLE: Storage → Rules (**X-2**) |
| A-5 | Whether the exposed Gemini key, the Maps keys and the Firebase API keys have API or referrer restrictions. | Google Cloud console → Credentials |
| A-6 | Whether `touchgrass.web.app` is in Auth's Authorized domains. | CONSOLE: Authentication → Settings |
| A-7 | Whether any user document already has an `entitlementTier` set (which would trigger D-07 today). | CONSOLE: Firestore query |
| A-8 | Whether any older user documents are missing fields the rules require (`weeklyXp`, `rainyDayCount`, `frozenDates`, `achievements`). If so, every update to that document is denied. | CONSOLE: data sample |
| A-9 | A fresh clone fails to build because `assets/icon/` is empty and untracked (D-19). | A clean-clone build in the scratchpad (planned for Phase 5) |

---

## Finding → remediation map

Phase numbers follow your remediation brief. Findings the brief doesn't assign are marked **UNSCHEDULED** so they don't get lost.

### Phase 1 — P0 security and data integrity
| ID | Sev | Finding | Planned fix | Regression test (allowed + denied) | Verification | Blocker / approval | Status |
|---|---|---|---|---|---|---|---|
| P0-0 | — | No automated rules tests | `firestore-tests/`: 4 suites, 178 tests | Self | 178/178 pass on the new rules. On the old rules the same suite reproduced the vulnerabilities: 78 failures, plus 26 cancelled because Storage didn't compile. | Approved | **PASS** (EMULATOR) |
| D-02 / S-1, S-2, S-6 | High | Rewards, leaderboard and initial XP can be forged | Rules: mirror fields must equal `get(users/uid)`; profile create pinned to defaults; `uid` and `createdAt` immutable; `streakFreezesOwned` only moves through legitimate transitions; each XP increase tied by `getAfter()` to one new completion in the same batch (the client switches to a batched write). Full server authority needs Cloud Functions (Blaze). | Every forged probe from V-4 must be denied. Legitimate award, freeze purchase, photo upload, username change and leaderboard toggle must be allowed. | 87 cases pass: profile create 12, profile edits 27, freeze purchase 4, reward batch 30, leaderboard 14. Together they cover every forged write in V-4 and every legitimate write type. | Blaze UNVERIFIED, so the rules-only design was implemented. See the Phase 1 residual-risk notes. | **PASS** (EMULATOR); not deployed |
| D-03 / S-3 | High | Username takeover | Split into `create` (only if the doc doesn't exist), `update: if false`, and owner-only `delete`. The client transaction stops re-setting a claim it already owns. | Takeover denied. A simultaneous claim by two users: exactly one succeeds. Claim, change and release by the owner allowed. | 9/9 pass | — | **PASS** (EMULATOR); not deployed |
| D-05 / S-5, S-8 | High | `storage.rules` doesn't compile; SVG allowed | Valid filename-wildcard match; explicit owner-only `delete`; content-type allow-list (jpeg, png, webp, heic, heif); size caps kept | Compiles. Owner write and read allowed. Another user's write and read denied. Oversize upload and SVG denied. Client delete stays denied, pending Phase 2. | 26/26 pass (avatars 11, completion photos 14, catch-all 1) | **X-2 still needed before any deploy** | **PASS** (EMULATOR); not deployed |
| D-06 / S-4 | High | Gemini key in client bundles; unlimited Gemini-backed rerolls | Stop passing the key to client builds. Without a server path, clients use seed-only challenge generation and no client-side AI. Cap rerolls in the rules (`rerollCount` ≤ N, increment by 1 only). A build check script fails if a key pattern appears in `build/`. | Canary build with a fake key: key absent, scan exit 0. Real `secrets.json` scan: exit 0. Rules: 4th reroll, skip, reset, delete and concurrent duplicate all denied (11 cases). Dart: 13 cap and template tests. | Decision received (templates only, AI off, N = 3) | **X-1 still OPEN: the old key was confirmed ACTIVE on 2026-10-17, and the live sites still serve it.** | **PASS** for code and new builds; live exposure remains until X-1 is done and the site is redeployed |
| — | — | Wider review: privilege escalation, ownership bypass, public access | Memories must mirror the owner's own completion. Completions are restricted to known fields, an honor-system verdict, an own-folder photo URL, a server timestamp, and a date key within ±1 day. Challenge docs have bounded `xpReward`. Default deny kept. | Memories 8, completions 13, challenge creation 13 | Pass | Notification route (S-10) moved to Phase 3 | **PASS** (EMULATOR) |

### Phase 2 — Rewards, profiles and account deletion
| ID | Sev | Finding | Planned fix | Regression test | Verification | Blocker / approval | Status |
|---|---|---|---|---|---|---|---|
| D-01 | Critical | No XP or streak on the sign-up day, or on any day the user explicitly signs in | New `lastCompletionDate` (server timestamp) and `lastCompletionId` on the user. Rewards are decided from the completion date only; sign-in touches only `lastActiveDate`. Legacy accounts fall back to their latest completion (read-only, no migration). The completion records the XP actually granted. The rules require a reward batch to stamp `lastCompletionDate == request.time` and make the XP added equal the completion's `xpAwarded`. The Cloud Function `verifyChallengeCompletion` was changed to match. | Dart: `reward_plan_test.dart` (sign-up day, sign-in then complete, yesterday → +1, 23:59 → 00:01, 00:01 → 23:59, gaps, freezes, weekly reset); `commit_completion_test.dart` on `fake_cloud_firestore` (first-day XP, legacy fallback, no-completion legacy, retry refused, same-day completion stores 0 XP, missing profile writes nothing). Emulator: new user's first reward, batch without `lastCompletionDate` denied, XP/`xpAwarded` mismatch denied both ways, two concurrent same-day submissions → exactly one wins. | All pass (see Phase 2 results) | `fake_cloud_firestore` added (dev only, approved in Phase 2 scope). DST has no dedicated test (the test machine's time zone can't be switched in-process); calendar math uses `DateTime(y, m, d)`, so it is DST-safe by construction. | **PASS** (TEST + EMULATOR); not deployed |
| D-13 / P1-5 | Medium | Success screen, Journal and detail screen disagree on XP; Journal entries can be lost; success shown after a failed reward write | Batched completion + memory + reward write; the UI shows the committed result; "saved, rewards pending" state | Notifier and repository tests | **Partly done in Phase 2:** completion + reward are one batch (Phase 1); the success screen and the memory both use the XP the batch actually committed, and the rules require memory `xpEarned == completion.xpAwarded`. **Still open:** the Journal memory is written after the batch, best-effort, so it can be missing if that write fails. | — | **PASS** (TEST + EMULATOR), Phase 3; not deployed. See "Phase 3 — results". |
| D-04 | High | Account deletion always fails | `deleteAccount` callable (Admin SDK, `us-central1`, 300 s): requires a sign-in within the last 5 minutes; deletes photos, avatar, completions, username claims, feedback, leaderboard entry, then the user doc with all subcollections (challenges, memories, aiUsage), and the Auth user **last**. Idempotent; any failure returns an error. The client re-authenticates, calls it, and signs out only on `{deleted: true}`. The old client-side partial cascade was removed. **Rules not loosened** (client deletes stay denied). | Functions unit: request checks (unauthenticated, stale sign-in, unsafe uid, clock skew), step ordering, failure propagation. Functions emulator (real Firestore/Storage/Auth emulators): full cleanup; other users untouched (incl. a uid-prefix look-alike); repeat request; >1 batch of completions; failure mid-way then retry; failure at the Auth step then retry. Dart: reauth → server delete → sign out ordering; failed reauth deletes nothing; server failure keeps the user signed in; wrong uid refused; no error message claims success. | All pass (see Phase 2 results) | **Deploy BLOCKED:** needs Blaze confirmed (X-7) and your approval to deploy. Until deployed, the app's Delete Account shows an honest "couldn't finish deleting" error. | **PASS** (TEST + EMULATOR). Approach **conditionally approved** by the owner (2026-10-17). **Production deployment NOT authorized**; see the D-04 deployment checklist below. |
| D-07 / A-7 | High | Granting a tier breaks profile writes | Done in Phase 1, because the users rule had to be rewritten anyway: server-owned fields (`uid`, `email`, `createdAt`, `entitlementTier`) may exist on a profile but no client can change them | Premium user's FCM token and reward updates allowed; self-grant, tier change and tier removal denied | 6/6 pass | Live state A-7 unverified | **PASS** (EMULATOR); not deployed |
| N-1 | Medium | "Send feedback" has never worked (default deny) | Create-only `feedback/{uid}_{yyyy-MM-dd}_{1..5}`: own uid, exactly `type`/`message`/`userId`/`createdAt`/`appVersion`, type `feedback` or `bug`, message 1–1000 chars, server timestamp, date within ±1 day (UTC). Each ID can be created once, so the cap is 5 per user per day with no counter. No client read, update, delete or list. | Emulator: 28 cases (valid shapes, both length boundaries, 9 invalid payloads, missing field, unauthenticated, other user's ID space, 5 bad IDs, cap of 5, slot reuse, concurrent same slot → exactly one, no read/list/edit/delete). Dart: payload shape, trimming, signed-out, length boundaries, slot claiming and cap. Parity test ties cap, length and types to the Dart constants. | All pass | Approved in Phase 2 scope. The cap of 5/day is my choice — say if you want a different number. | **PASS** (TEST + EMULATOR); not deployed. **5/day approved by the owner** (2026-10-17); enforced in `firestore.rules`, not only in the UI. |

### Phase 3 — Privacy and AI verification
| ID | Sev | Finding | Planned fix | Regression test | Verification | Blocker / approval | Status |
|---|---|---|---|---|---|---|---|
| D-09 | High | "Store Location Data" toggle ignored; privacy text inaccurate | One gate on location that every read goes through (camera, memory, weather, challenge generation); rewritten disclosures | Unit tests for each path when the toggle is off | — | **Approval: material privacy-behavior change.** Weather and the weather-tailored challenge text stop working when location is off. | **PASS** (TEST + EMULATOR), Phase 3; not deployed. See "Phase 3 — results". |
| D-10 | Medium | The production "fail-closed" guard isn't connected | Route `CameraNotifier` through `challengeVerificationServiceProvider` | Provider and notifier tests | — | Needs D-15 and Blaze for the remote path; caption step before or after verification (**product decision**) | **DEFERRED** by owner decision (2026-10-17): AI verification stays off. Phase 3 removed the AI-only wording from the failure screen ("Submit Anyway" now appears only after a real AI verdict). |
| D-15 / S-7, S-11 | Medium | Latent bugs in the Cloud Function; no App Check | Local-day handling, server-side reward table, respect `profilePublic`, transactional quota, MIME sniffing, App Check | Functions unit and emulator tests | — | Blaze, plus App Check registration (CONSOLE) | **DEFERRED** with AI verification; design in `AI_VERIFICATION_PLAN.md`. Runtime part done: Node 22 (see RT-1). |
| D-14 | Medium | Location prompt shown before its primer | Weather and challenge assignment check the permission but never request it | Unit test | — | — | **PASS** (TEST), Phase 4: weather waits for the location primer. |
| RT-1 | High (deploy blocker) | Functions pinned to Node 20, which Google decommissions on 2026-10-30 | `engines.node` "20" → "22" (package.json and the lockfile's root entry); no SDK change | tsc, unit and emulator tests run **on Node 22.23.3** | tsc clean; 62/62 unit; 6/6 emulator | Approved by owner 2026-10-17 | **PASS** (TEST, Node 22); not deployed |

### Phase 4 — Dependencies and code quality
| ID | Sev | Finding | Planned fix | Regression test | Verification | Blocker / approval | Status |
|---|---|---|---|---|---|---|---|
| D-15 (lint) | Low | `npm run lint` broken (no ESLint config) | Add a flat ESLint config matching the current code style | `npm run lint` exits 0 | — | — | **PASS** (Phase 4): `functions/.eslintrc.js`; `npm run lint` exits 0 and catches violations (positive control). See Phase 4 results. |
| S-12 | Medium | `npm audit`: 1 critical, 4 high | Triage each advisory (exploitability, fix, breaking risk) | Audit re-run | — | **Approval: `firebase-admin` 12 → 14, a major upgrade, done as its own change set** | **FIXED LOCALLY — TESTED** (Phase 5): `firebase-admin` 14.5.0 + the required `firebase-functions` 7.4.0, code moved to the modular Admin API; `npm audit` 9 → **0**; tsc, lint, 94/94 unit, 12/12 emulator on Node 22. Not deployed. See Phase 5 → 1. |
| D-21 | Low | 62 unformatted Dart files; unused dependencies and dead code | Format in a separate commit; remove unused items only with approval | analyze and test | — | — | **PASS** (Phase 4): 76 files formatted (separate patch); 6 unused packages removed; once-per-session analytics. Dead code kept on purpose (AI cutover). |
| P2-1 | Medium | No repository, integration or rules coverage | Repository tests plus one integration happy path | — | — | Approval for any new dev dependencies | **PASS**: repository, provider-flow and emulator rules coverage added in Phases 1–4. |

### Phase 5 — Platform and release readiness
| ID | Sev | Finding | Planned fix | Regression test | Verification | Blocker / approval | Status |
|---|---|---|---|---|---|---|---|
| D-08 (Android) | High | Firebase package mismatch; release builds silently debug-signed | Drop in the new `google-services.json`; release build fails without `key.properties` | Debug and release builds | V-8 (currently failing) | **X-5, X-6** | **BLOCKED (X-5)** for the real build; re-confirmed 2026-10-19 (`processDebugGoogleServices` / `processReleaseGoogleServices`). Phase 4 fixed every other build failure found. Release signing still falls back to debug (X-6). |
| D-08 (iOS) | High | No plist; bundle ID mismatch; no Google URL scheme; no Apple Sign-In entitlement | Add the config files and entitlements | Build on macOS | Not possible here | **X-5, X-6, a macOS machine** | BLOCKED (external) |
| D-18, D-19 | Medium | Default icons and favicon; no SEO or cache headers; possible clean-clone build failure | Icons, headers, robots/OG/canonical tags, asset declaration | Clean-clone build; LIVE-READ after deploy | V-9 | **X-10 icon artwork; approval for a domain redirect** | OPEN |
| Store | — | Signing, privacy labels, Data Safety form, screenshots, deletion | Store submission checklist | — | — | X-8, X-11 | OPEN |
| P2-9 | Low | Avatar uploads incremented `totalPhotosUploaded` | Avatar writes `photoUrl` only; field kept for compatibility | `avatar_upload_test.dart` (7) + 1 emulator case | Pass | — | **FIXED LOCALLY — TESTED** (Phase 5) |
| D-09b | Medium | Saved locations stay after the setting is turned off | "Remove saved locations" (Settings → Privacy) + narrow `removesOnly` rules branches on `completions` and `memories` | Emulator 25; repository 11; widget 8 | Pass | **Rules deploy** needed | **FIXED LOCALLY — TESTED**; OPEN — PRODUCTION VERIFICATION REQUIRED |
| N-6 | Medium | Any URL accepted as a profile photo and loaded by every leaderboard viewer | Client: load only own-bucket avatars or Google photos. Rules: proposal | `avatar_url_test.dart` (16) | Pass | Rules fix needs a production check of the `picture` claim | Client **FIXED LOCALLY — TESTED**; rules **DESIGN COMPLETE — IMPLEMENTATION DEFERRED** |
| N-7 | Medium | Photo files from released versions may carry EXIF GPS | Admin job that strips metadata and keeps download tokens | — | — | New dependency + deploy + approval | **DEFERRED — OWNER APPROVAL REQUIRED** |

### Unscheduled (in the audit, not in any phase of the brief)
| ID | Sev | Finding | Suggested phase |
|---|---|---|---|
| D-11 | Medium | Today's challenge goes stale after midnight while the app is open | **Done in Phase 2, with an automated test since 2026-10-17:** `test/providers/calendar_date_provider_test.dart`, 9 tests, all pass; the D-11 test fails against the old behavior. **PASS** (TEST). |
| D-12 | Medium | Leaderboard ranks stale weekly XP and reads whole leagues | **DESIGN COMPLETE — IMPLEMENTATION DEFERRED** (schema + rules; owner decisions listed): see Phase 5 → 6. |
| D-16 | Low/Med | Orphaned Storage uploads | **IMPLEMENTED LOCALLY — TESTED** (Phase 5): conservative, dry-run-by-default cleanup; **not exported, deployed or scheduled**. Enabling: **DEFERRED — OWNER APPROVAL REQUIRED** (Cloud Scheduler job). See Phase 5 → 4. |
| D-17 | Low | DST / UTC day-count off by one | **PASS** (TEST), Phase 4: `calendarDaysBetween`; local-day `createdAt`. |
| D-20 | Low/Med | Profile-photo permission denial not handled | **PASS** (TEST), Phase 4: camera primer + friendly denial message. |
| D-21 (UI) | Low | Raw error text shown in the UI | **PASS** (TEST), Phase 4 (with S-9). |
| D-22 | Low | Weather and companion polish | Phase 5: 2 small fixes (screen-reader unit, honest error text); the rest **DEFERRED — OWNER APPROVAL REQUIRED** (product). See Phase 5 → 7. |
| S-9, S-10 | Low | Raw errors in the UI; notification route not validated | **PASS** (TEST), Phase 4. |

---

## Phase 1 — results (2026-10-17)

### Verification commands (exit codes from this run)
| Command | Exit | Result |
|---|---|---|
| `npm --prefix firestore-tests test` (JBR 25, emulators) | 0 | **178 passed**, 0 failed, 0 skipped, 0 todo (15 suites) |
| Same suite against the **old** rules (before the fix) | 1 | 74 passed, 78 failed, 26 cancelled. The cancelled tests are all Storage tests: the old `storage.rules` doesn't compile. This shows the suite does detect the vulnerabilities. |
| `flutter analyze` | 0 | No issues |
| `flutter test` | 0 | **267 passed**, 0 failed, 0 skipped. Baseline was 235. **Removed:** 9 tests, listed below. **Added:** 41 tests. |
| `npx --prefix functions tsc --noEmit` | 0 | Clean (Functions code unchanged) |
| `npm --prefix functions test` | 0 | 49 passed |
| `flutter build web --release --dart-define-from-file=<canary>` | 0 | Built, 4,529,156 bytes. The canary string is absent and there are 0 `generativelanguage` references. |
| `node tool/check_web_bundle_secrets.mjs <build> <canary key only>` | 0 | Clean |
| `node tool/check_web_bundle_secrets.mjs <build> secrets.json` | 0 | Clean (the real old key is absent) |
| Scanner positive control: old `build/web` | 1 | Correctly flags the embedded key |
| First canary scan (`canary.json` with `ENVIRONMENT=production`) | 1 | **A false positive from my test design.** `ENVIRONMENT` isn't a secret and is legitimately compiled in. Re-run with a key-only canary: exit 0. |
| `flutter build apk --debug` | not re-run | Still blocked before any Dart or Kotlin compilation by D-08 (`google-services.json` package mismatch, external action X-5). Nothing in Phase 1 can change that result. |

### Tests removed (deliberate; the code they tested was deleted)
- `test/services/gemini_service_test.dart` (7 tests). These covered client-side Gemini response parsing; that client code was deleted. The server-side equivalent, `parseGeminiResponse`, is still covered by `functions/src/rewards.test.ts` (7 tests).
- `test/services/challenge_verification_service_test.dart` (2 tests). These covered the guard on the deleted local Gemini verifier.
- **Changed:** `CameraVerifying.usingAi` now defaults to `false`, as a fail-safe. Its two tests were updated to assert the new default.

### Product and security behavior: before → after
| Area | Before | After |
|---|---|---|
| Gemini key | Compiled into client bundles whenever passed at build time. Live on both sites. | The app doesn't read it at all. The `google_generative_ai` package is removed. Builds are scanned. |
| Challenge text | Gemini-written, with a template fallback | **Template-only** (deterministic seed library). No location or weather lookup when a challenge is assigned. |
| AI photo verification | Premium and admin accounts called Gemini from the client | **Off for every tier.** Every submission uses the honor system and says so on the record. The "Submit Photo" button no longer says "Verify with AI". |
| Rerolls | Unlimited | **3 per user per local day.** The counter resets when the next day's challenge document is created. Enforced by the rules (strictly +1 per write, no delete) and in the UI ("N/3", disabled at 0). |
| Completion + reward | Two separate writes, so a completion could exist without its reward | **One atomic batch.** On failure nothing is saved, and the user is told so. The reward math itself is unchanged (D-01 is still open, for Phase 2). |
| Reward, leaderboard and profile forgery | Allowed (V-4) | Denied (EMULATOR). |
| Username claims | Could be taken over | Create-only. The race is decided server-side. |
| New account | Client could set any values | Defaults are enforced. `createdAt` and `lastActiveDate` use server time. |
| Streak-freeze purchase | Didn't write `level` | Writes `level`; the rules require exactly 200 XP for exactly one freeze. |
| Storage | Rules didn't compile; SVG allowed | Rules compile. Raster images only. Owner-scoped. |

### Residual risks (stated plainly)
- **Honor system.** Without a server verifier, anyone can "complete" a challenge without going outside. That's the product decision (A5). The rules now cap rewards at the legitimate rate:
  - one completion per date key, and only for yesterday, today or tomorrow by the server's UTC date;
  - at most 100 XP per completion;
  - achievement bonuses only for achievements genuinely earned.

  Around a date change, a client can redeem up to 3 date keys within a ~48-hour window, each still capped at 100 XP.
- **No server authority yet.** Real authority needs Cloud Functions on Blaze (Phase 3 decision).
- **Nothing is deployed.** These rules exist only in the repo and the emulator. Production still runs the **old** Firestore rules, assuming A-3 holds, and **unknown** Storage rules (A-4).
- **The live site is still exposed.** It still serves the old Gemini key, which is still active, until X-1 and a redeploy.
- **Rules-deploy compatibility.** Once these rules are deployed, any client still running a **pre-Phase-1 build** will have completions, rerolls and username changes denied. That's because old builds write the completion and reward separately, and re-set username claims. Web clients update on reload; mobile has no store build yet. Deploy the rules and the web build together.
- **Leaderboard sync failure.** If the leaderboard sync after a completion fails, the completion is still committed but the leaderboard entry stays stale until the next sync. Failures are logged to Crashlytics.

### New finding while mapping client writes
| ID | Sev | Finding | Status |
|---|---|---|---|
| N-1 | Medium | "Send feedback" (`settings_screen.dart:1322`, collection `feedback`) is denied by the default-deny rule, so it has never worked. Fixing it means *adding* a client write permission (create-only, owner-tagged, size-bounded). | Approved and done in Phase 2 — see the Phase 2 table |

### Rollback (Phase 1)
- **Code:** revert the Phase 1 commit. It isn't committed yet; nothing is pushed or deployed.
- **Rules:** nothing has been deployed, so there's nothing to roll back in production. Before a future deploy, export the current live rules (X-2), so you can redeploy them if needed.
- **Lockfile:** the revert restores `google_generative_ai`.

## Phase 2 — results (2026-10-17)

All results below are from the repo, local unit tests and the **local emulators** (`demo-` projects). None of it shows what production is running: nothing was deployed, and no production Firebase resource was read or changed.

### Verification commands (exit codes from this run)
| Command | Exit | Result |
|---|---|---|
| `npm --prefix firestore-tests test` (JBR 25, Firestore + Storage emulators) | 0 | **212 passed**, 0 failed (Phase 1: 178; +34 net, including 28 feedback cases and the D-01 reward/completion cases) |
| `npx --prefix functions tsc --noEmit` | 0 | Clean |
| `npm --prefix functions test` | 0 | **62 passed** (Phase 1: 49; +13 `accountDeletion` unit tests) |
| `npm --prefix functions run test:emulator` (Firestore + Storage + Auth emulators) | 0 | **6 passed** (new: full cleanup, isolation, idempotency, pagination, partial failure + retry, Auth-step failure + retry) |
| `npm --prefix functions run lint` | 2 | **Not run: no ESLint config exists** (same as baseline; Phase 4 item). Not a pass. |
| `flutter analyze` | 0 | No issues |
| `flutter test` | 0 | **304 passed**, 0 failed, 0 skipped (Phase 1: 267; +37) |
| `flutter build web --release` (output to the scratchpad, not `build/`) | 0 | Built |
| `node tool/check_web_bundle_secrets.mjs <that build> secrets.json` | 0 | Clean: the old key is absent; 0 `generativelanguage` references |
| `flutter build apk --debug` | 1 | **Still blocked** at `:app:processDebugGoogleServices`: "No matching client found for package name 'com.touchgrass.app'" (D-08, external X-5). Fails before any Dart or Kotlin compilation, so **Android is not verified**. |
| iOS | — | Not built; no claim about iOS readiness. |

### Behavior: before → after
| Area | Before | After |
|---|---|---|
| First completion (sign-up day, or any day after an explicit sign-in) | 0 XP, no streak (D-01) | Full XP and streak 1 (or +1). Only `lastCompletionDate` decides "already completed today". |
| Journal / success screen XP | Could show XP that was never granted | Show the XP the batch committed. A second completion on the same day records 0 XP. |
| Duplicate completions | Prevented only by the client | One completion per date key (create-only, emulator-tested, including two concurrent submissions); retries get "You've already completed today's challenge" and change nothing. |
| Today's challenge after midnight | Stayed on yesterday's (D-11) | Switches at local midnight |
| Delete Account | Always failed, sometimes after deleting part of the data | Calls the server function; never reports success unless the server confirms `{deleted: true}`. **Until the function is deployed, users see a clear "couldn't finish deleting" error.** |
| Send Feedback | Always denied | Works, within the narrow rule (5/day, 1000 chars, write-only) |
| Reward amounts | — | **Unchanged** (25/50/100 XP, same achievement bonuses, freezes, weekly reset) |

### D-04 — what deploying `deleteAccount` needs and costs (estimate, not a quote)
Source: firebase.google.com/pricing, read on 2026-10-17. Prices and free tiers can change.

| Service | Why it's needed | No-cost allowance (Blaze) | Expected use |
|---|---|---|---|
| **Blaze plan** (pay-as-you-go billing account) | Required for any Cloud Functions deploy | — | **Not confirmed by me** (X-7) |
| Cloud Functions (2nd gen, runs on Cloud Run) | Runs `deleteAccount` | 2M invocations, 400K GB-s, 200K CPU-s per month | 1 invocation of a few seconds per deletion |
| Firestore deletes | Removes the user's documents | 20K deletes/day | ~1 delete per document; a year-long daily user is roughly 1,000 |
| Cloud Storage operations | Removes photos | Within the Storage free operations | 1 list + 1 delete per photo |
| Cloud Build | Builds the function on deploy | 120 build-min/day | A few minutes per deploy |
| Artifact Registry | Stores the function's container image | 0.5 GB | Can grow with each deploy; set the cleanup policy the CLI offers |
| Secret Manager | **Not** needed for `deleteAccount` | — | Deploy it by name (`firebase deploy --only functions:deleteAccount`), so the Gemini secret is not required |

**Estimate: about $0/month at current scale**, inside the free allowances. **Recommend a budget alert** (e.g. $5) on the billing account before the first deploy.

### Migration
- **No data migration.** Existing accounts have no `lastCompletionDate`; the app and the Cloud Function then use the user's latest completion (read-only query). The first new completion writes the field. Nothing is rewritten or deleted.
- **Deploy order (when approved):** rules and the new web build together, as in Phase 1. Once the Phase 2 rules are live, a reward write without `lastCompletionDate` is denied, so a **pre-Phase-2 client cannot complete challenges** until it reloads. `deleteAccount` can be deployed before or after; until it is, deletion fails honestly.
- `verifyChallengeCompletion` isn't deployed (the CLI reported "No functions found"), so changing it affects nothing live.

### Residual risks (stated plainly)
- **D-04 isn't live.** Store policies require working account deletion; this stays a release blocker until `deleteAccount` is deployed and tested against the real project.
- **Token after deletion.** A deleted user's ID token stays valid for up to ~1 hour, so a client could still write a few documents in that window (the rules only check the token). Low impact: those writes are capped by the same rules, and they're orphaned. Fix later with token revocation checks, if wanted.
- **Time zones.** The client decides "same day" in local time; the rules check date keys against the server's UTC date ±1 day. A user who changes time zones can gain at most one extra day's completion around the change, still capped per date key and at 100 XP.
- **D-11 timer** has no automated test (analyzer clean; needs a manual check across midnight).
- **D-13 partial:** the Journal memory is still written after the batch, best-effort; if that write fails, the completion and XP are saved but the Journal entry is missing.
- **Feedback abuse:** 5 messages × 1000 chars per user per day, but new accounts are free to create. Acceptable for now; App Check would tighten it (Phase 5).

### Rollback (Phase 2)
- **Code:** nothing is committed, pushed or deployed. Reverting the working-tree changes to the Phase 2 files restores Phase 1.
- **Data:** the new fields (`lastCompletionDate`, `lastCompletionId`) are additive. Older code ignores them; no cleanup is needed.
- **Rules:** if the Phase 2 rules are ever deployed and must be rolled back, redeploy the previous rules **together with** a matching client build (an older client and the newer rules don't mix; see Migration).
- **`deleteAccount`:** if deployed and it misbehaves, `firebase functions:delete deleteAccount` removes it; the client then falls back to the honest error.

## Phase 2 — owner decisions and follow-ups (2026-10-17)

Phase 2 was **accepted** by the owner on the basis of the local test and emulator evidence above. Phase 3 has **not** started.

### Decisions
| # | Item | Decision | Effect on this checklist |
|---|---|---|---|
| 1 | X-1 | The owner revokes/deletes the exposed Gemini key in the provider console. A clean bundle scan is not proof of revocation. | X-1 stays **BLOCKED** until the owner confirms. |
| 2 | X-7 | No Blaze upgrade and no paid service without explicit approval. Document the plan, requirements and costs before asking to deploy. | Plan recorded as UNVERIFIED; costs are in the D-04 table above. |
| 3 | D-04 | Server-side deletion approach **conditionally approved**. **Production deployment not authorized.** First: verify Blaze, review billing, prepare a deployment checklist, define safe testing with a controlled test account. | Deployment checklist and test plan below (drafts, nothing executed). |
| 4 | N-1 | 5 feedback messages per user per day **approved**. Must be enforced outside client-only UI logic, with boundary tests. | Already so: enforced by `firestore.rules` (create-once slot IDs 1–5). Emulator boundary tests: slot 5 allowed, slot 6 denied, slot 0 denied, exactly 5 then a 6th denied, slot reuse denied, concurrent same slot → exactly one, ±10-day dates denied. |
| 5 | D-13 | Add the Journal/completion consistency gap to the next phase: retry-safe, idempotent Journal sync; no duplicate XP; never lose the authoritative completion. | Scheduled; acceptance criteria below. |
| 6 | D-11 | Add an automated midnight/day-boundary regression test and report the result. | Done; results below. |

### D-11 — automated day-boundary test (added 2026-10-17)
- **Change:** `CalendarDateNotifier` now reads the time from an injectable `wallClockProvider` (defaults to `DateTime.now`), so a test can drive the midnight timer. Behavior in the app is unchanged.
- **Test:** `test/providers/calendar_date_provider_test.dart` uses fake async time with an injected wall clock:
  - starts on today's date, with the time stripped;
  - is unchanged one second before midnight;
  - rolls over exactly at midnight, then again the next midnight;
  - rolls over across a month end, a year end and a leap day;
  - a timer that fires early keeps the date and re-arms;
  - a timer that fires late (device asleep) lands on the real date;
  - **`todaysChallengeProvider` switches its subscription from 2026-03-10's document to 2026-03-11's at midnight.**
- **Result:** 9/9 pass. `flutter analyze` on both files: no issues.
- **Mutation check:** I temporarily restored the old behavior (date fixed when the provider is created). The D-11 test then **failed** (expected `2026-03-11`, got `2026-03-10`). I restored the fix; the file is byte-identical to before.
- **Not covered:** DST transitions. The test process's time zone can't be changed; the code uses calendar-field arithmetic, which is DST-safe by construction.
- **Full suite after this change:** `flutter test` exit 0, **313 passed** (304 + 9), 0 failed; `flutter analyze` exit 0, no issues.

### D-13 — scope for the next phase (acceptance criteria)
- The completion + reward batch stays the single source of truth; a Journal failure never undoes or blocks it.
- The memory uses the completion's ID, and creating it is create-only and idempotent: a retry either creates the missing memory or does nothing.
- A missing memory is repaired automatically (e.g. on app start or when the Journal opens) from the stored completion.
- Repair never changes XP, streak or any reward field, and never creates a second completion.
- Tests: memory write fails then repair succeeds; repeated repair is a no-op; repair after a same-day 0-XP completion shows 0 XP; emulator rules allow the repair and deny any XP mismatch.

### D-04 — deployment checklist (DRAFT; nothing here has been executed)
**Prerequisites (owner):**
1. Read the current plan in Firebase Console → Project settings → **Usage and billing**, and record it here (Spark or Blaze).
2. If it's Spark: decide on Blaze **as a separate, explicit approval**. If it's Blaze: review the linked billing account.
3. Create a **budget alert** on the billing account (suggested: $5/month; email at 50%, 90%, 100%). A budget alert notifies; it does not cap spending.
4. Export the live Firestore and Storage rules (X-2), so there's a rollback point.
5. *(Done: RT-1 moved to Node 22 in Phase 3, and Phase 5 upgraded to `firebase-admin` 14.5.0 / `firebase-functions` 7.4.0 — the deploy will use these. The text below is the original Phase 2 note.)* **Approve a Functions runtime change.** `functions/package.json` pins `"node": "20"`. Google lists Node.js 20 as deprecated since 2026-04-30 and **decommissioned 2026-10-30**; after that date new deploys on Node 20 aren't possible. Node 22 is supported until 2027-10-31, Node 24 until 2028-10-31. The installed `firebase-functions` 6.6.0 and `firebase-admin` 12.7.0 support Node 22, so this is a one-line `engines` change **with no SDK upgrade**, followed by a re-run of the Functions tests. Source: docs.cloud.google.com/functions/docs/runtime-support, read 2026-10-17.
6. Give explicit written approval to deploy, naming the command below.

**Deploy (only after approval):**
- `firebase deploy --only functions:deleteAccount --project touchgrass-today`. Deploy by name: this avoids deploying `verifyChallengeCompletion` and needing its Gemini secret.
- Accept the CLI's Artifact Registry cleanup-policy prompt, so stored container images don't accumulate cost.
- This deploys the function only. It does **not** deploy rules or the web app, and doesn't depend on them (the function uses the Admin SDK).

**Post-deploy checks:**
- `firebase functions:list --project touchgrass-today` shows `deleteAccount(us-central1)`.
- Run the safe test below; read the function logs; check billing after 24 hours.
- Rollback: `firebase functions:delete deleteAccount --project touchgrass-today`.

### D-04 — safe production test with a controlled test account (DRAFT)
- **Accounts:** two owner-controlled test accounts (e.g. email aliases), never a real user's. Account B is a bystander.
- **Client:** the deployed web app is the **old** build. Its Delete Account doesn't call the function, so an end-to-end test needs the new client build. That build writes fields the old production rules may not expect, so test it only after the Phase 1/2 rules are deployed, or with a separate approval to run a local build against production.
- **Seed A:** complete one challenge with a photo, set an avatar, claim a username, send one feedback message, appear on the leaderboard. Record the expected paths: `users/{uid}` and its subcollections; `completions/{uid}_*`; `usernames/*`; `feedback/{uid}_*`; `leaderboard_public/{uid}`; `completion_photos/{uid}/`; `user_avatars/{uid}.png`; the Auth user.
- **Negative first:**
  - Delete with a session older than 5 minutes → refused (asks you to sign in again), and nothing is deleted.
  - Cancel the re-authentication → nothing is deleted.
- **Positive:** re-authenticate, then delete → the app reports success only after `{deleted: true}`. Verify in the Console that every recorded path is gone and the Auth user no longer exists.
- **Bystander:** account B's data is unchanged.
- **Evidence:** screenshots or Console exports, plus the function log entries, attached to this checklist. Only then can D-04 move from EMULATOR to LIVE.

## Phase 3 — results (2026-10-17)

Approved scope: D-09, D-13, AI verification kept deferred, Node 22. Everything below comes from the repo, unit tests and the **local emulators**. Nothing was deployed, committed or pushed, and no production resource was read or changed.

### Owner decisions and confirmations recorded
| Item | Decision / confirmation | Evidence level |
|---|---|---|
| Location | Necessary for the location-dependent features; the setting must govern optional storage and sharing | Owner decision |
| Gemini key (X-1) | Revoked | **Owner-reported**, not verified |
| Firebase plan (X-7) | Blaze | **Owner-reported**, not verified |
| Journal | Photos of completed challenges must be saved to the Journal | Owner decision |
| AI verification | Stays off; honor system; no Gemini credentials in clients | Owner decision |
| D-13 | Included in Phase 3 | Owner decision |
| Node 22 | Approved, no Firebase SDK major upgrade | Owner decision |

### D-09 — location data flows (complete inventory)
"Setting" = **Save location with adventures** (`settings.locationEnabled`; on by default, as before; no migration).

| # | Flow | When | Data | Destination | Purpose | Retention | Class | With the setting OFF |
|---|---|---|---|---|---|---|---|---|
| L1 | Map: your position | The map is open | Device position | On-device map layer (`myLocationEnabled`) and map centering. The map tiles for the area you view come from Google Maps, as with any map. | Show where you are | Not stored by TouchGrass | **Essential, user-requested** | Still works (on-device only) |
| L2 | Home weather | Home open; every 30 min | Coordinates **rounded to 2 dp (~1 km)** | Open-Meteo (`api.open-meteo.com`) | Weather chip; Automatic theme's sunrise and sunset | Not stored by TouchGrass; Open-Meteo per its own policy | Optional | **No location read, nothing sent**; chip shows "Location off" with an explanation; theme follows the device |
| L3 | Completion location | Submitting a photo | Coordinates (medium accuracy) | Firestore `completions/{id}.location` | Map pin, Journal | Until account deletion (completions are immutable) | Optional | Not read, not stored; **rules deny** a completion with a location |
| L4 | Journal coordinates | Same batch as L3 | latitude, longitude | Firestore `users/{uid}/memories/{id}` | Map pin | Until account deletion | Optional | Not stored; **rules deny** |
| L5 | Place name | While writing the caption | Coordinates | Platform geocoder (Apple / Google); `locationName` stored in L4 | Journal label | Until account deletion | Optional | Not sent, not stored; **rules deny** |
| L6 | Journal weather | While writing the caption | Coordinates rounded to ~1 km | Open-Meteo; condition and emoji stored in L4 | Journal label | Until account deletion | Optional | Not sent, not stored; **rules deny** |
| L7 | Challenge assignment | — | None (Phase 1 removed location and weather from assignment) | — | — | — | — | — |
| L8 | Leaderboard, feedback, notifications, Functions | — | No location sent by app code. Firebase Analytics may derive coarse location from the IP address (standard SDK behavior; disclosed as app diagnostics). | — | — | — | — | — |

**Consent behavior:**
- The OS permission prompt, preceded by the primer, gates any location read.
- The setting gates all optional storage and sharing (L2–L6):
  - **in the app:** the `optionalLocationAllowedProvider` gate fails closed until the profile has loaded;
  - **in `firestore.rules`:** `optionalLocationAllowed()` and `locationDerivedKeys()` refuse stored location data while the setting is off.
- The setting is re-checked just before saving, so switching it off mid-flow takes effect.
- Turning it off asks for confirmation and lists exactly what becomes unavailable. The app never changes the setting itself.
- Denied permission or no fix: completions save without location; weather shows "unavailable"; the map shows its existing "enable location" prompts.

**Labels and disclosures now matching this behavior:**
- the settings toggle and subtitle;
- the off-confirmation;
- the Home "Location off" dialog;
- the in-app privacy policy (`PrivacyCopy`);
- the permission primer;
- the iOS `NSLocationWhenInUseUsageDescription`;
- `STORE_LISTING.md` (the Data Safety classification is flagged for the owner).

### D-13 — design (no destructive migration)
1. **Fixed photo path** `completion_photos/{uid}/{yyyy-MM-dd}.jpg`, so a retried upload replaces the same file. `storage.rules` only accept that name for new writes; older photos stay readable. `firestore.rules` only accept a completion whose `photoUrl` is exactly that file.
2. **Before uploading,** the app checks the authoritative completion document. If the completion already exists, it shows "Already completed", and nothing is uploaded or overwritten.
3. **One atomic batch:** completion + reward + **Journal entry**. The entry is built from the completion as stored, with the same ID, photo, caption and **XP actually granted**. Rules: the memory's `get` → `getAfter`, and it stays create-only. Either everything is saved, or nothing is.
4. **Repair:** the Journal and map run `journalSyncProvider` once per session. It recreates missing entries for the 30 most recent completions (for example, those saved by older versions, whose separately written entry could fail).
   - Create-only and idempotent.
   - Never touches XP, streaks or completions.
   - On failure, a banner says the adventures and XP are safe and offers Retry.
5. **UI states:**
   - "Uploading your photo…" → "Saving to your Journal…" → success with **"Photo saved to your Journal"** (shown only when the batch included the entry).
   - Failures: **Photo not uploaded** (retry), **Not saved yet** (retry; the caption is kept), **Already completed** (final; "Back to Home").
   - "Submit Anyway" appears only after a real AI verdict.
6. **Offline:** the app won't start an upload or a save while offline, and says nothing was saved. Retrying after reconnecting is safe.
7. **Ownership and deletion:** photos stay owner-only under `completion_photos/{uid}/`, which account deletion removes by prefix. Journal entries live under `users/{uid}`, which deletion removes recursively.

### Verification commands (exit codes from this run)
| Command | Exit | Result |
|---|---|---|
| `npm --prefix firestore-tests test` (Firestore + Storage emulators, JBR 25) | 0 | **249 passed**, 0 failed, 0 cancelled (Phase 2: 212; +37 = 26 new Journal/location cases, +9 Storage, +2 completion-photo cases) |
| `npx --prefix functions tsc --noEmit -p functions` (Node 26) | 0 | Clean |
| `npm --prefix functions test` (Node 26) | 0 | **62 passed** |
| `npm --prefix functions run test:emulator` (Node 26) | 0 | **6 passed** |
| Same three on **Node v22.23.3** (official zip, SHA-256 verified) | 0 | tsc clean; **62 passed**; **6 passed** |
| `npm --prefix functions run lint` | 2 | **Not run: no ESLint config** (Phase 4 item). Not a pass. |
| `flutter analyze` | 0 | No issues |
| `flutter test` | 0 | **370 passed**, 0 failed (Phase 2 end: 313; +57) |
| `flutter build web --release` (to the scratchpad) | 0 | Built |
| `node tool/check_web_bundle_secrets.mjs <build> secrets.json` | 0 | Clean |
| Search the web build for `generativelanguage` / `gemini` | — | **0 matches** in the bundle. In `lib/` and `pubspec.yaml`: no package, endpoint or key, only comments that mention Gemini. |
| `flutter build apk --debug` | 1 | **Still blocked** at `processDebugGoogleServices` ("No matching client found for package name com.touchgrass.app"; X-5). **Android not verified.** |
| iOS | — | Not built; no readiness claim |

### New and changed tests
| Suite | File | What it proves |
|---|---|---|
| Emulator | `firestore-tests/test/journal_location.test.mjs` (new, 26 cases) | **D-13:** full batch allowed; an XP-mismatched, wrong-photo or AI-claiming entry denies the **whole** batch with nothing saved; concurrent batches → exactly one; retry after success denied; repair allowed once; duplicate or concurrent repair → exactly one; repair can't change XP; another user can't write or read the Journal; can't adopt another user's completion. **D-09:** with the setting on or unset, location allowed; with it off, a completion with a location is denied, and an entry with coordinates, a place name or weather is denied (each); without location, allowed; full batch with location denied with nothing saved; other users unaffected. |
| Emulator | `storage.test.mjs` (changed) | Date-named upload allowed; **retry overwrite allowed**; 6 non-date names denied; legacy photo still readable; 10 MB boundary both sides |
| Emulator | `challenges.test.mjs` (changed) | A completion whose photo isn't `{uid}/{date}.jpg`, or is another day's, is denied |
| Dart | `test/providers/camera_flow_test.dart` (new, 10) | End-to-end notifier on `fake_cloud_firestore`: success writes completion + Journal + XP with the same photo; location on → saved, with weather getting coarse coordinates only; **location off → no location read, no weather or geocoder call, nothing stored**; switched off mid-flow → nothing stored; **upload failure → retry**; **save failure → retry keeps the caption, one completion, one entry, one photo object**; **duplicate retry after success → refused with no upload**; double-tap → one save; **offline → retry after reconnecting** |
| Dart | `test/repositories/journal_repair_test.dart` (new, 8) | Repair mirrors completions (photo, caption, granted XP including 0, day); idempotent; never touches existing entries, completions or XP; location only when allowed; only own completions; scan limit |
| Dart | `test/providers/location_privacy_test.dart` (new, 6) | Gate fails closed while loading; on and off; **weather off → 0 location reads, 0 requests**; on → coarse coordinates only |
| Dart | `test/core/privacy_copy_test.dart` (new) | The policy lists every flow (Open-Meteo, ~1 km, geocoder, Analytics, Crashlytics, Performance, token, leaderboard, feedback, no AI, deletion); the off-explanation names every limitation; screens use the shared wording; camera failure headlines, Retry availability, and "saved" shown only after commit |
| Dart | `commit_completion_test.dart` (+5) | Entry in the same batch with the photo and granted XP; 0-XP entry on the same day; retry → no second entry or extra XP; a failed save writes neither; a non-mirroring entry is refused before writing |
| Dart | `security_rules_parity_test.dart` (+2) | Location-derived keys and the photo-path pattern match between the app, `firestore.rules` and `storage.rules` |

**Mutation check (rules):** I temporarily removed the location gate, reverted the memory rule to `get()`, and loosened the photo name in both rule files. **16 of the new tests failed** (photo naming in both files, the full-batch Journal tests, and every location-off denial). Both rule files were then restored byte-identical (`cmp`).

### Node 22 (RT-1)
- **Change:** `functions/package.json` `engines.node` and the lockfile's root `engines` changed from "20" to "22". No dependency changes; `firebase-functions` 6.6.0 declares `>=14.10.0` and `firebase-admin` 12.7.0 declares `>=14`.
- **How it was tested:** this machine has Node 26. I downloaded the official **Node v22.23.3** Windows zip from nodejs.org into the scratchpad, **verified its SHA-256** against the published `SHASUMS256.txt`, and ran the Functions checks with it (nothing was installed system-wide).
- **Results:** tsc clean, 62/62 unit tests and 6/6 emulator tests (account deletion against the Firestore, Storage and Auth emulators). npm reported no engine warnings.
- **Not verified here:** an actual Cloud Functions deploy and build on Google's Node 22 runtime. That happens only at deploy time.

### AI verification — deferred
- **Status:** not implemented and not enabled. The future design is in `AI_VERIFICATION_PLAN.md`: architecture, App Check, authorization, quotas, abuse protection, privacy, and a billing estimate of about $0.003 per verification at gemini-2.5-flash paid-tier rates read 2026-10-17.
- **Client check:** the Phase 3 web build contains no `generativelanguage` or `gemini` strings, and the secret scan is clean. `lib/` and `pubspec.yaml` contain no Gemini package, endpoint or key, only comments.

### Migration and deploy order (when deployment is approved)
- **No data migration.** Existing completions, entries and photos are untouched. Missing Journal entries for recent completions are recreated by the app; nothing is rewritten or deleted.
- **Deploy `firestore.rules`, `storage.rules` and the new web build together.** Older app versions upload `{timestamp}.jpg` photos and write the Journal entry separately. Under the new rules their uploads and completions are denied, so they can't complete challenges until they reload. Same constraint as Phases 1 and 2.
- The new rules add one `get()` of the user's document to completion and Journal-entry creates, a billed read per such write. Negligible at current scale.

### Residual risks
- **Locations saved earlier stay saved** when the setting is turned off; only future collection stops. There is no "remove saved locations" tool; account deletion removes everything. Owner decision if a removal tool is wanted.
- **Legacy data:** pre-Phase-2 completions may record a `xpAwarded` that was never granted (the old D-01 bug). Repaired Journal entries mirror the stored value, because the rules require it. Legacy completions verified by AI are repaired as `auto_approved` for the same reason.
- **Abandoned attempts:** a user who uploads and never saves leaves at most one photo per date (D-16).
- **Mid-save connection loss on mobile:** Firestore may queue the batch and apply it atomically once back online. The screen stays on "Saving…" until then; there's no timeout UI.
- **D-14** (permission prompt before its primer) remains open.
- **Disclosures:** the in-app policy says Delete Account removes data, which is only true once `deleteAccount` is deployed (D-04). The hosted policy (X-8) and the Data Safety answers (X-11) are still owner actions.
- **Android:** still not built past the config step (X-5). iOS not built.

### Rollback (Phase 3)
- **Code:** nothing is committed. Reverting the Phase 3 working-tree changes restores Phase 2.
- **Data:** Phase 3 writes no new fields. Journal entries created by the batch or the repair are ordinary entries that older code reads normally. Photos at date paths are ordinary files.
- **Rules (if ever deployed):** roll back `firestore.rules` and `storage.rules` **together with** the matching client build.
- **Node 22:** set `engines.node` back to "20" (only useful before 2026-10-30).

## Phase 4 — results (2026-10-17 → 2026-10-18)

Scope: dependency security, Functions lint, Dart formatting, Android configuration (X-5), and the remaining audit findings. Everything below is local or emulator evidence. Nothing was deployed, committed or pushed; no production resource was changed; AI verification stays off.

### 1. Dependency security

**`functions/` — `npm audit` before:** 17 vulnerabilities (1 critical, 6 high, 10 moderate).
**Fix:** `npm audit fix` without `--force`. It changed **only `package-lock.json`**: semver-compatible transitive updates, no `package.json` edits, no Firebase SDK version change.
**After:** 9 vulnerabilities (2 high, 7 moderate).

| Package (installed → fixed) | Sev | Direct? | Path | Exploitability here | Status |
|---|---|---|---|---|---|
| proxy-addr 2.0.7 → 2.0.8 | **Critical** (GHSA-jqcg-44mw-7w3h) | transitive | firebase-functions → express | IP spoofing only when Express `trust proxy` uses subnet lists; the app never configures it. Low. | **Fixed** |
| @fastify/busboy 3.2.0 → 3.2.3 | High ×3 | transitive | firebase-admin (multipart parsing of Google API responses) | Needs attacker-controlled multipart responses from Google APIs. Low. | **Fixed** |
| @grpc/grpc-js 1.14.4 → 1.14.6 | High ×2 | transitive | firebase-admin → @google-cloud/firestore → google-gax | Advisories concern gRPC **server** features (`getAuthContext`, server error messages); the app is a client. Low. | **Fixed** |
| brace-expansion 1.1.18 / 5.0.9 → 1.1.21 / 5.0.12 | High | transitive, **dev only** | eslint / typescript-eslint → minimatch | Lint tooling only, never deployed. | **Fixed** |
| js-yaml 4.3.1 → 4.3.2 | High | transitive, **dev only** | eslint → @eslint/eslintrc | Lint tooling only. | **Fixed** |
| qs 6.15.3 → 6.16.1; body-parser 1.20.8; express 4.22.3 | Moderate | transitive | firebase-functions → express | Callable functions don't parse query strings with qs. Low. | **Fixed** |
| **node-forge 1.4.0** | **High** (GHSA-86w9-cpqp-85rv) | transitive | firebase-admin 12.7.0 | The flaw is in RSA PKCS#1 v1.5 **signature verification**. firebase-admin 12 uses node-forge only in `app/credential-internal.js` to **parse a service-account private key** (`privateKeyFromPem`), and never verifies signatures with it. **Not reachable.** No fixed node-forge release exists (1.4.0 is the latest). | **Remains** — fix = firebase-admin 14 (major, **needs approval**) |
| firebase-admin 12.7.0 | High (via node-forge) | **direct** | — | As above | Same |
| **uuid** < 11.1.1 (google-gax, gaxios, teeny-request, retry-request, @google-cloud/firestore, @google-cloud/storage) | Moderate ×7 | transitive | firebase-admin's Google Cloud clients | Missing bounds check only when `v3`/`v5`/`v6` are called with a `buf` argument. These SDKs only call `v4` (checked in `node_modules`). **Not reachable.** | **Remains** — fix = firebase-admin 14 (major) |

**`firestore-tests/` (dev-only emulator harness):** 5 high, all one chain: `@grpc/grpc-js` 1.9.16 via `firebase` 11 → `@firebase/firestore`.
- **No fix exists:** the latest `firebase` (13.0.0) still pins `@grpc/grpc-js ~1.9.0`. npm's only offer is a *downgrade* to firebase 9.14 (breaking).
- **Not exploitable:** it only talks to the local emulator, and both advisories concern gRPC server features.
- **No change.**

**Dart:**
- `dart pub` has no audit command, so I queried the OSV database (`api.osv.dev/v1/querybatch`) for **all 222 hosted packages** in `pubspec.lock`: **0 known vulnerabilities**. OSV's coverage of the Pub ecosystem is narrower than npm's, so this is "no known advisories", not a guarantee.
- Separately, **6 unused packages were removed** (D-21), which also shrinks the attack surface: `lottie`, `path_provider`, `riverpod_annotation`, `riverpod_generator`, `build_runner`, `mockito`. **37 transitive packages** left the lockfile. **No remaining package changed version** (checked by diffing the lockfiles). `path_provider` stays as a transitive dependency of other plugins.

**Node 22 after the dependency changes:** tsc clean, lint clean, 62/62 unit, 6/6 emulator on Node v22.23.3 (version checked in the log); audit unchanged at 9.

### 2. Functions lint (D-15)
- **Config:** `functions/.eslintrc.js` (classic config for the installed ESLint 8 and typescript-eslint 8; no tooling upgrade):
  - `eslint:recommended` + `plugin:@typescript-eslint/recommended`;
  - **type-aware** `no-floating-promises` and `no-misused-promises` (a promise that isn't awaited can be cut off when a Cloud Function returns);
  - `eqeqeq`.
- **Only exemption:** `node:test`'s `describe`/`test`/`it`, via `allowForKnownSafeCalls`. These return promises the test runner tracks itself; they caused all 83 initial reports, all in test files. No rule is disabled globally, and the production sources had **0 violations**.
- **Positive control:** a throwaway file with a floating promise and `==` produced exactly those 2 errors, and was then deleted.
- **Note:** ESLint 8 is end-of-life upstream. Moving to ESLint 9 (flat config) is a separate dev-tooling upgrade.

### 3. Dart formatting (D-21)
- **Scope:** `dart format lib test` reformatted **76 files**; `dart format --output=none --set-exit-if-changed lib test` now exits **0**.
- **Isolated diff:** the formatting-only change is saved as a separate patch, taken against a pre-format snapshot (scratchpad `p4_format.patch`, 76 files, 7,436 lines), so it can be reviewed apart from behavior changes.
- **Line endings:** unchanged in all 76 files.
- **Safety:** formatting is semantics-preserving. `flutter analyze` and the full test suite were run afterwards (results below).

### 4. Android (X-5 and build reliability)
**What exists:**
- `android/app/build.gradle.kts`: namespace and `applicationId` = `com.touchgrass.app`.
- `android/app/google-services.json`: one client, package **`com.example.touchgrass`**, app `1:760620662222:android:24eb…`.
- `firebase apps:list --project touchgrass-today` (read-only) lists **one Android app (that one)** and one iOS app.
- `lib/firebase_options.dart` points Android at it and iOS at bundle **`com.example.touchgrass`**.
- There is **no Firebase app registered for `com.touchgrass.app`**, on Android or iOS.
- No `GoogleService-Info.plist`.
- No `android/key.properties`, so release builds fall back to the debug key (X-6).

**Decision:** I did not change the application ID, and did not invent, edit or download any configuration. Registering a new app changes production Firebase, so it's an owner action. **Android = BLOCKED (X-5).**

**Exact owner steps (X-5):**
1. Firebase Console → project **touchgrass-today** → Project settings → *Add app* → **Android**, package name **`com.touchgrass.app`**.
2. Add SHA certificate fingerprints:
   - **Debug** (this machine's `~/.android/debug.keystore`; public fingerprints, not secrets):
     - SHA-1 `BF:3E:34:C3:20:E8:42:DC:A6:F2:C4:82:E1:61:26:0F:27:A4:10:FC`
     - SHA-256 `33:F8:D7:B3:AC:33:BA:A9:D8:53:07:08:C3:E7:5F:C7:29:E1:F1:2A:CA:99:45:BD:DD:53:DE:53:D8:6F:0B:BC`
   - **Release / Play App Signing:** add after X-6.
3. Download the new `google-services.json` and replace `android/app/google-services.json`.
4. Do the same for **iOS**, bundle ID `com.touchgrass.app`: download `GoogleService-Info.plist` into `ios/Runner/` and note its `REVERSED_CLIENT_ID` for the Google Sign-In URL scheme.
5. Run `flutterfire configure --project=touchgrass-today --platforms=android,ios,web` to regenerate `lib/firebase_options.dart` (it still points at the `com.example` registrations).
6. Tell me. I'll then run the real debug and release builds.

**Diagnostic build (not a PASS):** to find what *else* breaks, I built a **throwaway copy** of the project in the scratchpad, with the package name patched in that copy only. The repo's config file was never touched (`git diff` empty). The copy found **three more build blockers**, now fixed in the repo:

| # | Failure (diagnostic copy) | Cause | Fix in repo |
|---|---|---|---|
| N-4 | `:geocoding_android:checkDebugAarMetadata`: 15 AAR-metadata errors | `geocoding` 3.0.0 → `geocoding_android` 3.3.1 compiles against SDK 33; its AndroidX dependencies need ≥34 | `geocoding: ^4.0.0` (→ geocoding_android 4.0.1, compileSdk 35). 4.0's "breaking" changes are build requirements only (Flutter 3.29+, iOS 12+; we have 3.44 and iOS 13). `placemarkFromCoordinates` is unchanged. Only 2 lock entries changed. |
| N-5 | `:app:minifyReleaseWithR8`: missing Play Core classes | The Flutter embedding references Play Store deferred-component classes; the app uses neither | 11 exact `-dontwarn` rules (as generated by AGP) in `proguard-rules.pro` |
| N-3 | `:app:uploadCrashlyticsMappingFileRelease` | **Every release build uploads the R8 mapping file to the production Crashlytics project.** It failed here before connecting ("Host name may not be empty"), so nothing was uploaded. | Upload is now **opt-in**: `-P uploadCrashlyticsMapping=true` for a store build. Local builds never contact production. |

**Diagnostic results after the fixes:** debug **built**; release (`./gradlew assembleRelease`) **BUILD SUCCESSFUL**, R8 passes, and **no Crashlytics upload task runs**. Signed with the **debug key** (no keystore, X-6). Still a diagnostic, not a pass.
**Repo build (real config):** `flutter build apk --debug` and `--release` both exit 1 at `process*GoogleServices` (no client for `com.touchgrass.app`). **Android = BLOCKED (X-5).**
**iOS:** not built (no macOS/Xcode here); no readiness claim.

### 5. Remaining audit findings

| ID | Sev / release impact | Evidence and files | Smallest safe fix | Tests / acceptance | Status |
|---|---|---|---|---|---|
| **N-2 (new)** | **High (privacy)**: breaks the approved D-09 decision | `compressJpeg` kept EXIF despite its comment. **Verified:** a JPEG with GPS still had GPS after `compressJpeg`. Gallery photos (`image_picker`) can also carry the camera's GPS. Stored in Storage even with the setting off. | `stripImageMetadata` (`lib/core/utils/image_metadata.dart`) runs on every completion upload in `StorageService`, off the UI isolate: EXIF/XMP/comments dropped losslessly; rotated photos are upright-baked first; ICC kept; non-JPEG re-encoded; unreadable files refused with a friendly message. `compressJpeg` also clears EXIF. Avatars are re-rendered from pixels by the crop screen (no metadata). | `image_metadata_test.dart` (8): GPS and camera make removed; **scan data byte-identical** (lossless); rotation baked (64×48 → 48×64); XMP GPS removed, ICC kept; comments removed; PNG → clean JPEG; garbage refused; `compressJpeg` no longer keeps GPS. | **PASS** (TEST) |
| D-14 | Medium | `weatherProvider` read location (which can show the OS prompt) before AppShell's primer | `locationPrimerDoneProvider`, set by AppShell after the primer; weather waits for it | `location_privacy_test.dart` (+2): 0 location reads before the primer; loads after | **PASS** (TEST) |
| D-17 | Low | `inDays` between local midnights is 23 h after spring-forward; `dayNumber` used the UTC `createdAt` | `calendarDaysBetween` (UTC-normalized calendar fields); `createdAt.toLocal()` in assignment and retention; Member Since; companion day-of-year | `phase4_fixes_test.dart`: every day of 2026 counts as exactly 1 (DST included); **on this machine (US Central, DST) the old method gives 0 across 8 March**; Member Since across spring-forward. Note: `dayNumber` can shift by one for some users around DST or UTC-offset days; it only picks the template seed. | **PASS** (TEST) |
| D-20 | Low/Med | `ImagePicker().pickImage` in Settings unguarded; no camera primer | Camera primer before "Take a Photo"; try/catch with `profilePhotoPickErrorMessage` (explains how to allow access; never raw text) | 2 tests | **PASS** (TEST) |
| S-9 / D-21 (UI) | Low (info leak) | `diagnosticFailureMessage` appended raw cause text (JS errors, URLs, IDs) to user messages; it was a temporary aid for a bug fixed long ago | Friendly text plus only a short Firebase error code (`[permission-denied]`, matching `^[a-z][a-z0-9-]{0,40}$`); full cause → Crashlytics. `CrashReporter.recordError` no longer throws when Firebase isn't initialized. | `camera_providers_test.dart`: code kept; URL/uid not shown; odd codes not shown; typed messages unchanged | **PASS** (TEST) |
| S-10 | Low | `context.go(message.data['route'])` with no check | `safeNotificationRoute`: allow-list of in-app routes + `/challenge/<id>` (`[A-Za-z0-9_-]{1,64}`); anything else → Home | 2 tests: all real routes pass; 16 hostile or odd values (external URLs, `//host`, `javascript:`, `/login`, traversal, query strings, wrong types) → Home | **PASS** (TEST) |
| D-21 | Low | Retention milestones and streak-abandoned re-logged on every profile-document change | `claimSessionEvent`: once per session per user and milestone | 1 test | **PASS** (TEST) |
| D-21 | Low | Unused dependencies | Removed (see §1) | analyze, full suite | **PASS** |
| D-21 | Low | Dead code: `AiFeatureLockedCard`, `challengeVerificationServiceProvider` | **Kept on purpose:** they're the entry points for the deferred server-side AI verification | — | Deferred with AI |
| D-21 | Low | Avatar upload increments `totalPhotosUploaded` | Changes a stat definition and a rules-tested write shape | — | **Proposal** (product) |
| D-12 | Medium | `weeklyXp` only resets on the next completion; the client sorts whole leagues | Mirror a `weekKey` (or `weeklyXpResetDate`) in `leaderboard_public`; query `where(weekKey == current).orderBy(weeklyXp desc).limit(N)` with the existing index; rules must validate the new mirror field | Emulator mirror tests; provider test for the week boundary | **Proposal: needs approval** (rules + data shape) |
| D-16 | Low/Med | At most one photo per abandoned date remains | A scheduled function (daily) deletes `completion_photos/{uid}/{date}.jpg` older than 2 days that have no completion. Est. ≈$0 (Blaze free tier: 1 invocation/day + a few Storage list/delete ops). | Functions emulator test: orphan deleted, photo with a completion kept | **Proposal: needs approval** (deploy, billing) |
| D-22 | Low | Weather always °F; limited companion context | Unit preference; more weather states; companion moods | — | **Deferred** (product) |

### 6. Historical location data after the setting is turned off — assessment (nothing implemented)
**What is stored today:**
- `completions/{id}.location`: precise coordinates. Rules: completions are **immutable**.
- `users/{uid}/memories/{id}`: `latitude`, `longitude`, `locationName`, `weatherCondition`, `weatherEmoji`. Rules: **only the caption** can be updated.
- Before N-2, photos could also embed GPS in their EXIF. Those already-uploaded files are unchanged.

**Implications:**
- Turning the setting off stops *future* collection only. Earlier coordinates stay until account deletion, and this is disclosed in the off-explanation.
- Under data-minimization principles, and store policies that expect users to control their data, retaining precise location after the user withdraws the optional purpose is defensible only if disclosed and deletable. Today the only deletion route is deleting the whole account, which is itself not yet deployed (D-04).

**Options (each needs approval, since it is destructive and changes the rules or server):**
- **A: "Remove saved locations" action** in Settings (offered when turning the setting off; confirmed; irreversible; shows how many entries).
  - A narrow rules change lets the owner **delete only** the location-derived fields on their own completions and Journal entries: field removal only, no other change, rule-tested.
  - Map pins and place names for those entries disappear; XP, photos and captions are untouched.
  - No server cost.
- **B: The same, via a server callable** (Admin SDK). Rules stay unchanged; needs a Functions deploy (≈$0).
- **C: Also re-strip existing photos** (download, strip, re-upload). This rewrites user files and changes download tokens, so stored `photoUrl`s would need updating. Higher risk; server-side only. Recommend only if old photos are confirmed to contain GPS.
- **D: Keep as is,** disclosed, with deletion via account deletion only.

**Recommendation:** A, with explicit confirmation, plus updating the privacy text to describe it. Not implemented, pending your decision.

### Verification (exit codes from this run)
| Command | Exit | Result |
|---|---|---|
| `npm --prefix functions audit` | 1 | **9** (2 high, 7 moderate); before Phase 4: 17 (1 critical, 6 high, 10 moderate). All remaining are not reachable; the fix needs firebase-admin 14. |
| `npm --prefix firestore-tests audit` | 1 | 5 high (one dev-only grpc-js chain; no upstream fix) |
| OSV query, 222 hosted Dart packages | — | 0 known vulnerabilities |
| `npm --prefix functions run lint` | 0 | ESLint runs; 0 problems (positive control produced 2 expected errors) |
| `npx --prefix functions tsc --noEmit -p functions` | 0 | Clean |
| `npm --prefix functions test` | 0 | **62 passed** |
| `npm --prefix functions run test:emulator` | 0 | **6 passed** |
| Same, plus lint and audit, on **Node v22.23.3** (official zip, SHA-256 re-verified; `node --version` checked in the log) | 0 | tsc clean; lint clean; 62 passed; 6 passed; audit 9 (2 high, 7 moderate). An earlier attempt silently ran on Node 26 (PATH not applied) and is **not counted**. |
| `npm --prefix firestore-tests test` (emulators) | 0 | **249 passed**, 0 failed (rules unchanged in Phase 4) |
| `dart format --output=none --set-exit-if-changed lib test` | 0 | 145 files, 0 changed |
| `flutter analyze` | 0 | No issues |
| `flutter test` | 0 | **389 passed**, 0 failed (Phase 3: 370; +19) |
| `flutter build web --release` (scratchpad) | 0 | Built |
| `node tool/check_web_bundle_secrets.mjs <build> secrets.json` | 0 | Clean |
| Search the web bundle for `generativelanguage` / `gemini` | 0 | 0 matches |
| `flutter build apk --debug` (repo, real config) | 1 | **BLOCKED (X-5):** `processDebugGoogleServices`: no client for `com.touchgrass.app` |
| `flutter build apk --release` (repo, real config) | 1 | **BLOCKED (X-5):** `processReleaseGoogleServices`, same cause |
| Diagnostic copy (patched package, scratchpad only): `flutter build apk --debug` | 0 | Built (after the N-4 fix) |
| Diagnostic copy: `./gradlew assembleRelease --console=plain` | 0 | BUILD SUCCESSFUL; R8 and geocoding resources pass; **no Crashlytics upload task runs** |
| iOS | — | Not built (no macOS) |

### Changed files (Phase 4)
| File | Why |
|---|---|
| `functions/package-lock.json` | `npm audit fix` (lockfile-only, 13 transitive updates) |
| `functions/.eslintrc.js` (new) | Working ESLint config (D-15) |
| `pubspec.yaml`, `pubspec.lock` | Removed 6 unused packages (D-21); `geocoding` ^3 → ^4 (N-4) |
| `android/app/build.gradle.kts` | Crashlytics mapping upload opt-in (N-3) |
| `android/app/proguard-rules.pro` | R8 `-dontwarn` for unused Play Core classes (N-5) |
| `lib/core/utils/image_metadata.dart` (new) | Strip EXIF/XMP GPS before upload (N-2) |
| `lib/core/utils/image_compression.dart` | Clear EXIF; fix the misleading comment (N-2) |
| `lib/services/storage_service.dart` | Strip metadata on every completion upload (N-2) |
| `lib/services/analytics_service.dart` | `CrashReporter.recordError` never throws |
| `lib/providers/camera_providers.dart` | No raw error text in the UI (S-9) |
| `lib/core/constants/route_names.dart`, `lib/widgets/app_shell.dart` | Notification route allow-list (S-10); primer-done flag (D-14) |
| `lib/providers/location_privacy_providers.dart`, `lib/providers/weather_providers.dart` | Weather waits for the location primer (D-14) |
| `lib/core/utils/calendar_days.dart` (new); `member_since.dart`, `assignment_providers.dart`, `user_providers.dart`, `home_screen.dart` | DST-safe day counts, local `createdAt` (D-17); once-per-session analytics (D-21) |
| `lib/features/settings/screens/settings_screen.dart` | Camera primer and handled picker errors (D-20) |
| `test/core/phase4_fixes_test.dart`, `test/core/image_metadata_test.dart` (new); `test/providers/location_privacy_test.dart`, `test/providers/camera_providers_test.dart` | Regression tests (+19) |
| 76 Dart files under `lib/` and `test/` | **Formatting only** (`dart format`); separate patch `p4_format.patch` |
| `REMEDIATION_CHECKLIST.md`, `KNOWN_BUGS.md` | Evidence, blockers, owner actions |

### Rollback (Phase 4)
- **Code:** nothing is committed. Revert the Phase 4 working-tree changes; backups of the pre-Phase-4 `functions/package-lock.json`, `pubspec.yaml`, `pubspec.lock`, `build.gradle.kts` and `proguard-rules.pro` are in the scratchpad (`*.p4bak`).
- **Formatting:** reverse-apply `p4_format.patch`, or simply don't commit it separately.
- **Dependencies:** restore the lockfiles from the backups, then run `npm ci` and `flutter pub get`.
- **Data:** none. Phase 4 writes no data and changes no rules.

## Phase 5 — results (2026-10-19)

Everything below is **local only**. Nothing was committed, pushed or deployed; no production data, rules, services or billing were changed; AI verification stays off. The only network calls were read-only (npm registry metadata, GitHub release notes, the OSV database). The one production-facing attempt, a read-only `firebase apps:list`, **failed** because the CLI credentials have expired. I did not re-authenticate, so X-5 was not re-checked live in this phase. `DOCUMENTATION.md` is untouched (SHA-256 identical before and after).

**Starting state (verified, not assumed):**
- Branch `release-hardening-pass`, HEAD `67c5a38`.
- 125 entries in `git status --short` before any Phase 5 edit, all from Phases 0–4 and all preserved.
- The Phase 4 report matched the code, with one correction. Its "OSV query, 222 hosted Dart packages" was the count **before** the 37 package removals: the current `pubspec.lock` has **185** hosted packages, and the Phase 5 query covers all 185.
- The extracted Node 22 folder had again been partly removed by Windows temp cleanup. I re-extracted it from the checksum-verified zip. Every Node 22 result below logged `v22.23.3`.

### Statuses used in this section
FIXED LOCALLY — TESTED · IMPLEMENTED LOCALLY — BLOCKED ON CONFIGURATION · DESIGN COMPLETE — IMPLEMENTATION DEFERRED · DEFERRED — OWNER APPROVAL REQUIRED · OPEN — PRODUCTION VERIFICATION REQUIRED · BLOCKED — ENVIRONMENT LIMITATION

### Summary
| ID | Item | Status |
|---|---|---|
| S-12 | firebase-admin 12 → 14 (with the required firebase-functions 6 → 7) | **FIXED LOCALLY — TESTED.** `npm audit`: 9 → **0**. Not deployed. |
| P2-9 | Avatar uploads counted as photo uploads | **FIXED LOCALLY — TESTED** |
| D-09b | Remove saved locations (historical data) | **FIXED LOCALLY — TESTED** (EMULATOR + TEST). Needs a **rules deploy**: OPEN — PRODUCTION VERIFICATION REQUIRED. Photo-file metadata from older app versions is **not** covered (N-7). |
| D-16 | Abandoned-photo cleanup | **IMPLEMENTED LOCALLY — TESTED**, not exported, deployed or scheduled. Enabling it: DEFERRED — OWNER APPROVAL REQUIRED. |
| N-6 (new) | Any URL accepted as a profile photo and loaded by every leaderboard viewer | Client mitigation **FIXED LOCALLY — TESTED**. Rules fix: DESIGN COMPLETE — IMPLEMENTATION DEFERRED. |
| D-12 | Leaderboard data model | **DESIGN COMPLETE — IMPLEMENTATION DEFERRED** (schema + rules change; owner decisions below) |
| D-22 | Weather and companion polish | Two small fixes **FIXED LOCALLY** (accessibility label, honest error text); the rest **DEFERRED — OWNER APPROVAL REQUIRED** (product) |
| D-04 | Account deletion | **OPEN — PRODUCTION VERIFICATION REQUIRED.** Re-reviewed; passes on admin 14 in the emulator; not deployed. |
| X-5 | Firebase registration for `com.touchgrass.app` | **IMPLEMENTED LOCALLY — BLOCKED ON CONFIGURATION** (unchanged) |
| X-6 | Release signing | **BLOCKED ON CONFIGURATION**: no `key.properties` or keystore; release falls back to the debug key |
| iOS | Build and signing | **BLOCKED — ENVIRONMENT LIMITATION** (Windows; no macOS or Xcode) |

### 1. S-12 — firebase-admin 12 → 14 (compatibility review, then upgrade)

**Advisories before** (`npm audit` in `functions/`, exit 1: 2 high, 7 moderate; all transitive through firebase-admin 12.7.0):

| Advisory | Package (path) | Affected | Reachable here? |
|---|---|---|---|
| GHSA-86w9-cpqp-85rv (high): RSA PKCS#1 v1.5 signature verification accepts extra nested DigestAlgorithm elements | node-forge 1.4.0 (firebase-admin → node-forge) | all versions (no fixed node-forge) | Not found reachable. The Admin SDK used node-forge for credential/key parsing, not for verifying signatures this app relies on. firebase-admin 14 drops node-forge altogether. |
| GHSA-w5hq-g745-h8pq (moderate): missing buffer bounds check in v3/v5/v6 when `buf` is provided | uuid 9.0.1 / 10.0.0, via gaxios, google-gax, teeny-request, retry-request, @google-cloud/firestore, @google-cloud/storage | < 11.1.1 | Only reachable through internal v4 calls in the Google client libraries; the app never calls uuid. |

**Compatibility findings:**
- **Peer dependency:** `firebase-functions` 6.6.0 accepts `firebase-admin` `^11.10 || ^12 || ^13` only. Admin 14 is supported from **firebase-functions 7.3.0**, so the upgrade requires firebase-functions 6 → 7. This is a *required* companion upgrade, not an unrelated one.
- **firebase-functions 7.0.0 breaking changes:**
  - Node 16 dropped;
  - `functions.config()` removed;
  - TypeScript 5 / ES2022;
  - the v1 `Event` type renamed;
  - emulator 500s from async `onRequest`.
  None of these applies: the code uses only v2 `onCall`, `params`, `logger` and (new) `onSchedule`, as checked by grep and tsc.
- **firebase-admin 14.0.0 breaking changes:**
  - Node 18/20 dropped (engines `>=22`, which matches our Node 22);
  - Instance ID removed;
  - legacy FCM types removed;
  - **the legacy namespaced API removed** (PR #3164): `admin.firestore()`, `admin.storage()`, `admin.auth()` and `admin.firestore.FieldValue` are gone.
- **Admin 14 dependency changes:** `@google-cloud/firestore` and `@google-cloud/storage` become *optional* dependencies (installed by default; `npm ci` installs them).
- **Code impact:** `index.ts` and `accountDeletion.emulator.test.ts` used the namespaced API (tsc against 14: 20 errors). Both now use modular imports (`firebase-admin/app`, `/firestore`, `/storage`, `/auth`), which also work on admin 12 (available since v10). The migration was verified on 12 first, then on 14.
- **Method:** trial upgrade in an isolated scratchpad copy first, then applied to the repo with `npm install firebase-admin@^14.5.0 firebase-functions@^7.4.0` (lockfile from that install, then `npm ci`). No `--force`, and no other dependency changed on purpose.
- **Lockfile delta:** 42 packages removed (node-forge, the old uuid copies and others), 42 added, 60 changed.
  - Notable: `express` 4 → 5 inside firebase-functions. The app has no `onRequest` handlers, so it isn't used directly.
  - Google client libraries: `@google-cloud/firestore` 7.11.6 → 9.3.1, `@google-cloud/storage` 7.22.0 → 8.4.0, `google-auth-library` 9 → 11.

**Results on Node 22.23.3 (repo):**
- `npm audit`: **0 vulnerabilities** (exit 0); `--omit=dev` also 0.
- tsc: clean.
- Lint: clean.
- Unit tests: **94/94** (62 earlier + 32 new).
- Emulator tests: **12/12**, including the 6 account-deletion tests, which now run on admin 14.

**Untested by automation:** `verifyChallengeCompletion` (AI, disabled, not deployed). tsc confirms its Admin API calls are type-correct on 14; there is no runtime test, because it needs Gemini.

**Deploy note:** the next `firebase deploy --only functions:…` will build with the new SDKs. That deploy still needs its own approval (D-04).

### 2. P2-9 — avatar uploads counted as adventure photos
- **Root cause (verified):**
  - `UserRepository.uploadProfilePhoto` incremented `totalPhotosUploaded`.
  - No completion upload ever incremented it.
  - Nothing reads it: it is not displayed, not used by achievements (`computeNewlyEarned` has no photo input), progression or analytics. So the field only ever counted avatar changes.
- **Fix:** an avatar upload now writes `photoUrl` only. Adventure photos are already counted authoritatively by `totalCompletions`: one photo per completion, rules-validated.
- **Kept for backward compatibility:**
  - The `totalPhotosUploaded` field is kept (no rename, no migration).
  - The rules still accept the old `+1` write, so older app versions keep working.
  - The new shape (`photoUrl` only) has its own rules test.
- **Tests:**
  - `test/repositories/avatar_upload_test.dart` (7): successful, failed and retried uploads, missing field, unrelated profile edit, completion + same-day repeat, and achievements/progression independence. A mutation check (re-adding the increment) makes it fail.
  - Emulator: +1 case in `users.test.mjs`.
- XP, streak, completions and the leaderboard values are unchanged by an avatar upload (asserted).

### 3. D-09b — "Remove saved locations" (historical location data)

**Inventory of persisted location data:**

| Data | Where | Necessary for the app? | Removed by the action? |
|---|---|---|---|
| `location` (GeoPoint) | `completions/{uid}_{date}` | No (optional) | **Yes** |
| `latitude`, `longitude`, `locationName`, `weatherCondition`, `weatherEmoji` | `users/{uid}/memories/{id}` | No (optional; map pins only) | **Yes** |
| GPS in EXIF/XMP inside photo files uploaded by app versions **before the N-2 fix** (every version released so far) | `completion_photos/{uid}/…` (Storage) | No | **No** (see N-7 below) |
| Avatars | `user_avatars/{uid}.png` | — | Nothing to remove: the crop step re-renders pixels to PNG (`RenderRepaintBoundary.toImage`), so no metadata (STATIC) |
| `settings.locationEnabled` | `users/{uid}` | Preference, not location | n/a |
| Device cache | Firestore offline persistence | — | Updated by the same writes |
| `leaderboard_public`, `usernames`, `feedback`, analytics events, logs | — | — | None hold coordinates (grep for location in log/analytics calls: 0 hits) |

**Mechanism: the narrowest one that works without a deployed backend.**
- Two new rules branches, both built on a `removesOnly(keys)` helper. It allows an update only if it:
  - changes at least one field;
  - changes nothing outside `keys`;
  - leaves none of `keys` behind.
  So a value can never be set, changed or added this way.
- **`completions`:** `allow update` if the caller owns the doc and the update only removes `location`. Delete stays denied. Using an update to re-award XP is denied: the reward rule needs a *new* completion.
- **`memories`:** the caption edit is unchanged; the second branch allows only removing all location-derived keys.
- A callable function was considered and rejected for now. It would need a Functions deploy (not yet approved, even for D-04) and adds cost. The rules route needs only a rules deploy.

**Client (`LocationHistoryRepository`):**
- Scoped to the signed-in user (`where userId ==`; own subcollection).
- Paginated: pages of 200 ordered by document ID, so it needs no new composite index. Note that `fake_cloud_firestore` mis-paginates when `limit` is chained before `startAfterDocument`; the code orders the calls so both behave.
- One batch per page (≤ 200 writes), and only documents that still have a location are written.
- Completions are cleared before Journal entries.
- Repeats until a full pass finds nothing (≤ 3 passes), reading from the **server**, never the cache. It reports `complete` only then; otherwise `offline`, `failed` or `incomplete`, with exact counts of what was removed.
- Logs counts only. It never throws.

**UI (Settings → Privacy → "Remove saved locations"):**
- The confirmation says:
  - what is removed, and that it's permanent;
  - that entries, photos, captions, XP, streak and progress stay;
  - that map pins disappear;
  - when the setting is still on, that new adventures keep saving location;
  - that photo files from earlier versions may still contain location;
  - that a connection is needed;
  - that a stop partway is safe to retry.
- While running, a non-dismissible progress dialog prevents double runs.
- On success, a snackbar.
- On failure, a dialog that says some locations **may** remain, with **Try again** and **Close**.
- The Journal/map cache is refreshed after any run that removed something.
- The explanation shown when turning the setting off now points to the action. The policy text is unchanged.

**Future collection:** re-verified, unchanged. The camera capture, geocoding and weather enrichment, Journal repair and weather widget paths all go through `optionalLocationAllowedProvider` (STATIC + existing tests). Journal repair copies from completions, so after removal it cannot copy a location back (test).

**Tests:**
- Emulator `location_removal.test.mjs` (25): owner allowed; other user and unauthenticated denied; set, change and add denied; partial removal denied; riders (XP, photo, caption, dates, owner) denied; delete still denied; re-award via removal denied; profile unchanged.
- Mutation check: replacing `removesOnly` with "any change" makes 14 of the 25 fail.
- `location_history_repository_test.dart` (11): fields removed with others kept (unexpected fields too); XP and profile untouched; no records deleted; other users untouched; documents without location; empty account; multi-page; partial failure then retry; offline; repeat after success; reappearing locations reported as incomplete; repair after removal.
- `remove_saved_locations_test.dart` (8 widget tests): copy, cancel, progress and non-dismissible, success, nothing to remove, offline/failed/incomplete with retry, close.
- `privacy_copy_test.dart`: +3 assertions.

**N-7 (new, privacy, Medium): GPS inside older photo files.**
- Photos uploaded before the N-2 fix may still carry EXIF GPS.
- The client can't rewrite them safely: overwriting an object gives it a new download token, and the immutable `completions.photoUrl` would then break.
- **Proposal:** a one-off Admin SDK job that rewrites each `completion_photos/` object with its metadata stripped, **keeping `firebaseStorageDownloadTokens`** so stored URLs keep working.
- It needs a Node image library (new dependency), a deploy and owner approval. Until then, the UI and this checklist say so plainly.

### 4. D-16 — abandoned completion-photo cleanup
**Files:**
- `functions/src/orphanPhotoCleanup.ts`: logic plus Admin adapters.
- `functions/src/orphanPhotoCleanupJob.ts`: scheduled wrapper, **not exported from `index.ts`**. A unit test fails if `index.ts` mentions it.

**Orphan definition.** All of these must hold; anything uncertain is skipped, never deleted:
1. The name is exactly `completion_photos/{safe uid}/{real yyyy-MM-dd}.jpg`. Legacy `{timestamp}.jpg`, avatars, nested paths and impossible dates are skipped.
2. The date is ≥ 7 days before today (UTC). The rules only accept a completion within ±1 day of **server** time, offline-queued commits included, so after 2 days the completion can never be created. Seven days leaves margin for time zones, clock skew and slow retries.
3. The object's `timeCreated` **and** `updated` are ≥ 7 days old, and its generation is known. A recent re-upload is therefore never touched.
4. There is no `completions/{uid}_{date}` and no Journal entry `users/{uid}/memories/{uid}_{date}`, and the user profile exists. Deleted-account leftovers are left to account deletion.

**Run behavior:**
- A lookup error skips the page.
- A listing error aborts the run with nothing deleted.
- **Dry-run is the default.** Anything other than `mode: "delete"` deletes nothing.
- In delete mode, each candidate is re-checked in Firestore right before deletion. The adapter then re-reads the object's generation and deletes with `ifGenerationMatch`.
- Limits: ≤ 2000 objects inspected and ≤ 100 deleted per run, with page size clamped to 1000. A cursor is returned so the next run continues.
- Report: counts of inspected, retained, eligible, deleted and failed objects, plus skip reasons. No uids, file names or content are logged.

**Wrapper (if ever enabled):**
- `onSchedule("every day 04:00", UTC)`, `maxInstances: 1`, `concurrency: 1`, so runs never overlap; `retryCount: 0`.
- Mode comes from parameter `ORPHAN_PHOTO_CLEANUP_MODE` (default `dry-run`).
- The cursor is kept in server-only `_ops/orphanPhotoCleanup`; the catch-all rule denies clients.
- No HTTP or callable endpoint, so no app user can trigger it.

**Tests:**
- Unit (32, fakes): every one of the 16 required cases, plus impossible dates, unsafe uid, a Journal-entry-only photo, a deleted account, mode spoofing, a re-check lookup failure, and a guard that the job isn't exported.
- Emulator (6, real Storage + Firestore): dry-run finds exactly the orphan and deletes nothing; delete mode removes only the orphan and keeps the completion photo, Journal-only photo, legacy photo, deleted-account photo and avatar; real clock means nothing eligible; repeated run; pagination over the real listing; replaced object refused.
- **Emulator limitation (verified):** the Storage emulator changes the generation on overwrite but **ignores `ifGenerationMatch` on delete** (a probe deleted a stale generation). The adapter therefore re-reads the generation first, which the emulator test covers. The atomic precondition itself is only enforced by real Cloud Storage and is unverified here.

**Cost and scheduling** (estimate from Google's published pricing as I understand it, not a quote; check the current pricing pages before enabling):
- **Infrastructure:** 2nd-generation Cloud Function (Cloud Run) plus **one Cloud Scheduler job**. Scheduler includes 3 free jobs per billing account, then about $0.10 per job per month. Deploying also uses Cloud Build and Artifact Registry (set the cleanup policy).
- **Per run:**
  - 1 Storage list call per 1000 objects (Class A operation); deletes are not billed as operations.
  - Firestore: 3 reads per candidate (candidates are only old-dated, metadata-complete photos), plus 3 re-check reads per eligible photo, plus 1 state read and 1 write. Worst case at the default limit is about 6,000 reads per run.
- **Frequency:** daily is enough. Orphans are rare (at most one per abandoned date) and harmless while they wait, so weekly would also do.
- **Expected total:** within the free tiers at today's scale; at most cents per month as usage grows. **Not zero:** Scheduler beyond the free jobs, Artifact Registry storage, and reads beyond 50k per day are billable.
- **Disable or roll back:**
  - Pause the Scheduler job.
  - Or set the mode back to `dry-run`.
  - Or remove the export and run `firebase functions:delete orphanPhotoCleanupJob`.
  Deleted orphans are not recoverable, which is why dry-run comes first.

**To enable (owner approval required):**
1. Add `export {orphanPhotoCleanupJob} from "./orphanPhotoCleanupJob";` to `index.ts`.
2. Deploy by name.
3. Read a week of dry-run reports.
4. Only then set `ORPHAN_PHOTO_CLEANUP_MODE=delete`.

### 5. N-6 (new) — arbitrary profile photo URLs on the leaderboard
- **Evidence:** the rules accept any string ≤ 2048 characters as `photoUrl`; the existing emulator test even uses `https://x.test/a.png`. The mirror copies it, and `leaderboard_screen.dart` loads every listed user's `photoUrl` with `CachedNetworkImage`.
- **Impact:** a user could make every leaderboard viewer's device fetch from a server they control, which reveals viewers' IP addresses and user agents, or show any image.
- **Severity:** Medium (privacy). Exploitable today against the deployed web app's leaderboard.
- **Client mitigation (done):** `isTrustedAvatarUrl` loads other users' photos only from:
  - this app's own Storage bucket under `user_avatars/` (bucket pinned to the configured `storageBucket`, so another Firebase project's bucket is refused);
  - `*.googleusercontent.com` (Google sign-in photos).
  Anything else shows initials. Tests: 16, including look-alike hosts, other buckets, other namespaces, `..` traversal, credentials in the URL, non-default ports, `http`, `javascript:` and `data:`. Only the new app build is protected.
- **Server fix (proposal, not implemented):** in `isValidNewProfile` and `isProfileEdit`, allow only:
  - `null`;
  - the own-avatar Storage URL (`…/o/user_avatars%2F{uid}.png…`);
  - `request.auth.token.picture` (the provider photo).
  This needs production evidence that Google ID tokens carry `picture` equal to the Auth user's `photoURL` (test with a test account). If that assumption is wrong, Google sign-up would break, so it must not be shipped untested.

### 6. D-12 — leaderboard security and data model (proposal; nothing implemented)

**Current model (verified):**
- **What's stored:** `leaderboard_public/{uid}` holds `displayName`, `username`, `photoUrl`, `xp`, `weeklyXp`, `streak`, `currentLeague`.
- **Who writes it:** the client. The rules require every field to equal the caller's own profile (`get(users/uid)`), and profile progress fields only move through rules-validated transitions (a completion reward tied to a new completion, or a freeze purchase).
- **Who reads it:** any signed-in user. Opting out deletes the doc.
- **Query:** `where currentLeague ==`, streaming the **whole league**. The client sorts by `weeklyXp` and takes the top 30. The index `(currentLeague, weeklyXp desc)` exists but is unused.

**Weaknesses:**
1. **Stale weeks:** `weeklyXp` resets only on the user's next completion, so last week's totals keep ranking.
2. **Cost:** every viewer reads every league member on every change.
3. **Mirror can lag the profile:** a modified client can skip the mirror update after a freeze purchase (XP −200) and keep showing a higher XP. The rules only check equality when the mirror is written.
4. **Honor system:** with AI off, completions are self-attested. XP gain is capped at the rules' daily maximum but not verified. Multiple accounts can't be prevented.
5. **Unmoderated profile data:** any `displayName` (≤ 100 characters); N-6 for photos.
6. **Ties:** the order is undefined.
7. **Scraping:** any signed-in user can list every league with no size limit.

**Authoritative source of scores:**
- The profile's XP, `weeklyXp` and `streak` are already rules-validated transitions.
- **Recommended long-term (Option B):** the server owns the leaderboard. An `onDocumentWritten(users/{uid})` trigger (or the future server reward function) writes the mirror; clients can only read it, and opt-out is handled by the trigger. This removes weaknesses 1–3 and lets the server compute the week.
- **Rules-only alternative (Option A, no Functions cost):**
  - Add `weekIndex = floor((days since epoch + 3) / 7)` (Monday 00:00 UTC weeks, the same boundary as `weeklyXpResetDate`) to the profile and the mirror.
  - The reward rule requires the right `weekIndex` for `request.time`.
  - A freeze purchase must update an existing mirror in the same batch (`getAfter`), which closes weakness 3.

**Query and index:**
- `where currentLeague == L, where weekIndex == current, orderBy weeklyXp desc, orderBy weeklyXpUpdatedAt asc, limit 30`.
- Composite index `(currentLeague asc, weekIndex asc, weeklyXp desc, weeklyXpUpdatedAt asc)`.
- The viewer's own rank outside the top 30 comes from a `count()` aggregation (`weeklyXp >` mine).
- Rules: `allow list: if isSignedIn() && request.query.limit <= 50` (fixes 7).

**Ties, deletion and exposed fields:**
- **Ties:** higher weekly XP first; then whoever reached it first (`weeklyXpUpdatedAt`); then uid.
- **Deleted accounts:** `deleteAccount` already deletes the mirror. **Suspended accounts:** no suspension mechanism exists. Option B can exclude a `suspended` flag set by an admin; Option A cannot hide a user without an admin write.
- **Exposed data:** only display name, username, photo (N-6 filter), XP, weekly XP, streak and league. No email or settings; that stays as today.

**Migration and compatibility:**
- **Migration:** none required. Mirrors without `weekIndex` simply don't appear until their owner completes a challenge that week. That is correct behavior, since their weekly XP is stale anyway.
- **Option A and older app versions:** older clients don't write `weekIndex`. If the rules *require* it, older clients' reward batches fail. So either make it optional (older clients' users vanish from the board until they update) or ship a forced update first.
- **Option B:** older clients' mirror writes are denied once the mirror is server-owned. Their reward batches must not include the mirror write, so check `UserRepository` ordering before deploying.

**Emulator tests required:**
- `weekIndex` correct, wrong or missing;
- freeze purchase without the mirror update denied;
- list limit > 50 denied;
- mirror write by the client denied (Option B);
- ordering and ties via the composite query (emulator, no index enforcement; needs a production check);
- deleted user's mirror gone.

**Abuse scenarios:** sybil accounts (residual: honor system); forged XP (blocked by existing rules); stale-high mirror (fixed by A or B); scraping (list limit); tracking photos (N-6); offensive names (needs a moderation decision).

**Rollback:** redeploy the previous rules and indexes, and redeploy the previous client. The added fields are inert.

**Owner decisions needed:**
- (a) Option A (rules-only, no cost) or B (Functions trigger, server-authoritative).
- (b) Week boundary: UTC Monday (current) or local.
- (c) What to do about older app versions.
- (d) Name moderation.
- (e) Whether to show the viewer's rank outside the top 30.

### 7. D-22 — weather and companion review
**Verified behavior:**
- Weather is fetched only with the setting on and after the primer.
- Coordinates are coarsened to about 1 km.
- Any error becomes `null`; no raw error or URL is shown.
- A failed refresh hides the chip rather than showing stale data, and a 30-minute refresh shows at most 30-minute-old data.
- One request per tick; no analytics events.
- Companion content is static text with no links or navigation, and its animation respects Reduce Motion.

**Small fixes made:**
- The weather chip's screen-reader label now says "degrees Fahrenheit".
- The "unavailable" dialog no longer blames location permission when the cause may be the connection.

**Proposals (product, ranked by user impact/effort; none implemented):**
1. °C/°F preference (low effort; locale default).
2. A "Loading weather…" semantics state instead of "unavailable" during the first fetch (low).
3. Wind, freezing-rain and extreme-heat/cold advice (medium).
4. Larger companion line pools and moods beyond `cheer`, tied to more context (medium; content work).

No new services or AI.

### 8. D-04 — account deletion readiness (re-review; not deployed)
**Verified:**
- The uid comes from the token only, and a sign-in within 5 minutes is required.
- Storage is deleted first, then Firestore, then the Auth user.
- Prefix `completion_photos/{uid}/` (the trailing slash protects `alice2`) and the avatar.
- `completions`, `usernames` and `feedback` by owner field, in batches of 400.
- `leaderboard_public/{uid}`.
- `recursiveDelete(users/{uid})`, which covers challenges, memories (with their location fields) and aiUsage.
- Idempotent, so retry is safe; success is reported only after Auth deletion.
- Every collection in `firestore.rules` and every Storage path is covered. The new `_ops/orphanPhotoCleanup` holds no user data.

**Remaining gaps:**
1. **Second device:** a still-signed-in second device keeps a valid ID token for up to about an hour and could write new documents after deletion. That is low risk; a follow-up admin sweep could remove such orphans.
2. **Google-side data:** Analytics, Crashlytics and Performance data are not deleted by the function. Set Analytics data retention, and consider the Analytics User Deletion API.
3. **Logging:** the success log records the uid (a pseudonymous ID), which is acceptable for an audit trail.
4. **Policy text:** the privacy policy and the app say "delete your account and its data from Settings → Delete Account". That is only true once `deleteAccount` is deployed, so **deploy it before releasing a build that shows that text.**

**Deployment readiness (owner):**
- The existing D-04 checklist and safe-test plan stand.
- Phase 5 additions:
  - Deploy with the new SDKs (admin 14.5.0, functions 7.4.0, Node 22).
  - Confirm the Cloud Functions, Cloud Build, Artifact Registry and Cloud Run APIs are enabled.
  - Export the live Firestore and Storage rules first (X-2).
  - Deploy `functions:deleteAccount` **by name only**: never a bare `functions`, which today exports `verifyChallengeCompletion` too.

### 9. Release blockers (X-5, X-6, iOS, Crashlytics)
- **X-5:** still blocked. Repo evidence is unchanged:
  - `android/app/google-services.json` is for `com.example.touchgrass`, while `applicationId` and namespace are `com.touchgrass.app`;
  - there is no `ios/Runner/GoogleService-Info.plist`;
  - `firebase_options.dart` iOS bundle ID is `com.example.touchgrass`, while the Xcode `PRODUCT_BUNDLE_IDENTIFIER` is `com.touchgrass.app`;
  - `firebase.json` still points at the old Android app ID.
  The live registration could not be re-read (expired CLI credentials). Owner steps are in Phase 4 → Android. No identifier was changed and no config was invented.
- **X-6:** `android/key.properties` and any keystore are absent, so `release` falls back to the **debug** key (`build.gradle.kts`). No signing material was created.
  - **Owner steps:**
    1. Create an upload key: `keytool -genkeypair -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`.
    2. Store it **outside the repo**.
    3. Write `android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`); it is gitignored, but confirm with `git check-ignore -v android/key.properties`.
    4. Enrol in Play App Signing.
    5. Back up the keystore and passwords in a password manager **and** an offline copy; losing the upload key needs a Play support reset.
    6. Add the release SHA-1/SHA-256 to Firebase (X-5).
  - **Recommended:** make release builds fail when `key.properties` is missing instead of falling back to debug. That's a one-line Gradle change, left for your approval because it breaks local `--release` diagnostics.
- **iOS:** this machine is Windows (no Xcode). Owner steps on a Mac:
  1. After X-5, add `GoogleService-Info.plist`.
  2. Run `flutterfire configure`.
  3. Add the `REVERSED_CLIENT_ID` URL scheme and the Sign in with Apple capability.
  4. Run `flutter build ios --release`.
  5. Archive in Xcode with the distribution certificate and provisioning profile.
- **Crashlytics:** `mappingFileUploadEnabled` is true only with `-P uploadCrashlyticsMapping=true` (verified in `build.gradle.kts`). No upload was attempted.

### 10. Security and dependency audit closure
| Scope | Before Phase 5 | After | Notes |
|---|---|---|---|
| `functions/` npm audit | 9 (2 high, 7 moderate) | **0** | firebase-admin 14.5.0 / firebase-functions 7.4.0 |
| `firestore-tests/` npm audit (dev-only) | 5 high | 5 high | See below. |
| Dart (OSV querybatch, Pub) | — | 0 known in **185** hosted packages | OSV's Pub coverage is limited: "no known advisories", not "no vulnerabilities". `pubspec.yaml` and `pubspec.lock` unchanged in Phase 5. |
| Secret scan, working tree (tracked + untracked, non-ignored: 295 text files) | — | 0 real findings | 4 pattern hits were placeholders (`RELEASE_GUIDE.md`) and property lookups (`build.gradle.kts`). No keystore files. Scanner prints locations, never values. |
| Secret scan, web bundle (`tool/check_web_bundle_secrets.mjs`) | — | **Clean** (exit 0): 17 text files, 1 `secrets.json` value checked, 4 public keys allow-listed; 0 Gemini-style keys or Generative Language endpoint references in `build/web` | |

**`firestore-tests/` findings:**
- All 5 come from one chain: `@grpc/grpc-js` 1.9.16, pulled in by `firebase` 11.10.0 → `@firebase/firestore` 4.8.0.
- Advisories:
  - GHSA-m9gg-hp2v-232j (high): "getAuthContext can return unauthorized certificates as though they were authorized";
  - GHSA-f596-whhp-79r4 (low): "server transmits some error messages … to the client".
  Both are fixed in grpc-js 1.13.6.
- **No upstream fix:** even the newest `@firebase/firestore` (4.18.0 / firebase 13) pins `@grpc/grpc-js ~1.9.0`.
- **Exposure:** both advisories concern a gRPC *server*. These tests use grpc-js only as a *client* of the local emulator on `127.0.0.1`. The package is not in the app or the Functions deploy.
- **Follow-up:** re-check when the firebase JS SDK moves past grpc-js 1.9. The emulator tests are kept, not weakened.

### Verification (exit codes from this run)
| Check | Command | Exit | Result |
|---|---|---|---|
| Format | `dart format --output=none --set-exit-if-changed lib test` | 0 | 152 files, 0 changed |
| Analyze | `flutter analyze` | 0 | No issues |
| Flutter tests | `flutter test` | 0 | **431 passed** (Phase 4: 389; +42 new) |
| Web build | `flutter build web --release` | 0 | Built |
| Web bundle secrets | `node tool/check_web_bundle_secrets.mjs` | 0 | Clean |
| Functions type check (Node 22.23.3) | `npx tsc --noEmit` | 0 | Clean |
| Functions lint | `npm run lint` | 0 | Clean |
| Functions unit | `npm test` | 0 | **94/94** |
| Functions emulator (Firestore, Storage, Auth) | `npm run test:emulator` | 0 | **12/12** (account deletion 6 on admin 14; cleanup 6) |
| Functions audit | `npm audit` | 0 | 0 vulnerabilities |
| Rules (emulator, Node 22, JBR 25) | `cd firestore-tests && npm test` | 0 | **275/275** (Phase 4: 249; +1 avatar, +25 removal) |
| Rules mutation check | `removesOnly` → "any change" | 1 (expected) | 14 of 25 removal tests fail; rules restored |
| firestore-tests audit | `npm audit` | 1 | 5 high (grpc-js 1.9 chain; dev-only; no upstream fix) |
| Dart advisories | OSV `querybatch`, 185 hosted packages | — | 0 known |
| Source secret scan | scratchpad scanner over `git ls-files -co --exclude-standard` | 1 → reviewed | 4 hits, all placeholders or property lookups; 0 real secrets |
| Android debug | `flutter build apk --debug` | 1 | **BLOCKED (X-5)**: `processDebugGoogleServices`, no client for `com.touchgrass.app` |
| Android release | `flutter build apk --release` | 1 | **BLOCKED (X-5)**: `processReleaseGoogleServices`. Phase 4's diagnostic-copy builds were not repeated: Phase 5 changed no Android configuration |
| Release signing | inspection | — | No `key.properties`/keystore; would be debug-signed (X-6) |
| Crashlytics mapping upload | inspection of `build.gradle.kts` | — | Opt-in only (`-P uploadCrashlyticsMapping=true`); nothing uploaded |
| iOS | — | — | Not built: Windows host, no Xcode (environment limitation) |
| Live Firebase app list | `firebase apps:list` (read-only) | 1 | Credentials expired; not re-authenticated; not re-verified |

### Changed files (Phase 5)
| File | Why |
|---|---|
| `functions/package.json`, `functions/package-lock.json` | firebase-admin ^14.5.0 and firebase-functions ^7.4.0; new test files added to `test` and `test:emulator`; emulator files run one at a time (`--test-concurrency=1`) because both clear the emulators |
| `functions/src/index.ts` | Modular Admin imports (required by admin 14) |
| `functions/src/accountDeletion.emulator.test.ts` | Same import migration |
| `functions/src/orphanPhotoCleanup.ts` (new) | D-16 cleanup logic and Admin adapters |
| `functions/src/orphanPhotoCleanupJob.ts` (new) | Scheduled wrapper; **not exported** |
| `functions/src/orphanPhotoCleanup.test.ts` (new) | 32 unit tests, including the not-exported guard |
| `functions/src/orphanPhotoCleanup.emulator.test.ts` (new) | 6 emulator tests |
| `firestore.rules` | `removesOnly()` helper; owner may delete only `location` from a completion and only the location fields from a Journal entry; caption rule moved into `isCaptionEdit()` unchanged |
| `firestore-tests/test/location_removal.test.mjs` (new) | 25 emulator cases |
| `firestore-tests/test/users.test.mjs` | New "photo only" avatar case; old case relabelled for older app versions |
| `lib/repositories/user_repository.dart` | Avatar upload no longer increments `totalPhotosUploaded` |
| `lib/repositories/location_history_repository.dart` (new) | Bounded, verified, retry-safe removal of saved locations |
| `lib/providers/location_privacy_providers.dart` | `locationHistoryRepositoryProvider` |
| `lib/features/settings/widgets/remove_saved_locations.dart` (new) | Confirm, progress, success and failure/retry flow |
| `lib/features/settings/screens/settings_screen.dart` | "Remove saved locations" tile; refreshes the Journal/map cache |
| `lib/core/constants/privacy_copy.dart` | Wording for the new action; the setting-off explanation points to it |
| `lib/core/utils/avatar_url.dart` (new) | N-6 avatar URL filter |
| `lib/features/leaderboard/screens/leaderboard_screen.dart` | Uses the filter for other users' photos |
| `lib/features/home/screens/home_screen.dart` | D-22: "degrees Fahrenheit" label; honest weather-unavailable text |
| `test/repositories/avatar_upload_test.dart` (new) | 7 tests |
| `test/repositories/location_history_repository_test.dart` (new) | 11 tests |
| `test/features/settings/remove_saved_locations_test.dart` (new) | 8 widget tests |
| `test/core/avatar_url_test.dart` (new) | 16 tests |
| `test/core/privacy_copy_test.dart` | Wiring and wording assertions for the new action |
| `REMEDIATION_CHECKLIST.md`, `KNOWN_BUGS.md` | This section; status updates |

### Migration
- **Data:** none.
- **Production rules:** one change is required for "Remove saved locations": the narrow `update` branches on `completions` and `memories`. Until it is deployed, the action reports "failed" (permission denied) and changes nothing. Old clients are unaffected.
- **Functions:** SDK majors changed. The next Functions deploy (still unapproved) uses them.

### Rollback (Phase 5)
- **Code:** nothing is committed, so reverting the Phase 5 files restores Phase 4.
- **Backups** are in the scratchpad (`p5/bak/`): `index.ts`, `accountDeletion.emulator.test.ts`, `functions/package.json`, `functions/package-lock.json` and `firestore.rules` as they were before Phase 5.
- **SDK rollback:**
  1. Restore the `functions/` package.json and lockfile.
  2. Run `npm ci`.
  3. Keep the modular imports: they work on admin 12 as well.
- **After a future deploy:**
  - Rules: redeploy the previous `firestore.rules`.
  - Functions: redeploy the previous build, or delete by name.

## Phase 6 — results (2026-10-19)

Local work only. Nothing was committed, pushed or deployed. No production data, rules, apps, services or billing were changed, and AI verification stays off. The only production contact was **read-only**: `firebase apps:list`, `apps:sdkconfig` (package and bundle IDs only) and `apps:android:sha:list`. `DOCUMENTATION.md` is unchanged (SHA-256 `baa43787…a9f94bc`, before and after).

**Starting state:**
- Branch `release-hardening-pass`, HEAD `67c5a38`.
- 137 `git status` entries, identical to the end of Phase 5; all preserved.
- The Phase 5 report's numbers matched the code.

Full narrative: `PHASE_6_FINAL_REPORT.md`. Security detail and the deployment manifest: `PHASE_6_SECURITY_REVIEW.md`. Owner steps: `PHASE_6_RELEASE_RUNBOOK.md`.

**Status columns:**
- **Impl:** implemented locally.
- **Unit:** unit-tested.
- **Emu:** emulator-tested.
- **Int:** integration-tested (a real build or a multi-component flow).
- **Prod-cfg:** verified against production configuration.
- **Deployed:** deployed and verified.

✔ = done, ✖ = not done, — = not applicable.

| ID | Sev | Issue / root cause | Fix | Impl | Unit | Emu | Int | Prod-cfg | Deployed | Prod access needed | Owner / next action | Blocks release |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| D-04 | High | Promised deletion not deployed. Also, another signed-in device could keep refreshing its session during deletion. | Refresh tokens revoked **first**; strict step order; failure-at-every-step tests | ✔ | ✔ 27 | ✔ 9 | ✖ | ✖ | ✖ | Yes (deploy) | Owner: approve stage 3, then run the controlled test (runbook §8) | **Yes** |
| P6-A2 | Medium | Analytics and Crashlytics kept the uid after sign-out or deletion | Identity cleared on sign-out; `resetAnalyticsData` after a confirmed deletion | ✔ | ✔ 4 | — | ✖ | — | ✖ | No | Ships with the app; GA4 user deletion is an owner option (§8.7) | No |
| P6-A3 | Medium | Privacy wording promised deletion of "its data" without saying Firebase keeps diagnostics | Exact deletion scope plus a diagnostics-retention sentence; tied by test to `accountDeletion.ts` | ✔ | ✔ 2 | — | — | — | ✖ | No | Hosted policy (X-8) should say the same | No |
| N-6 | Medium | Any URL accepted as a profile photo (leaderboard viewers' IPs exposed) | Rules `isAllowedProfilePhoto` (null / own avatar in the app bucket / token `picture`); sign-up uses the token claim | ✔ | ✔ 8 | ✔ 35 | ✖ | ✖ | ✖ | Yes (rules deploy; check `picture` claim) | Owner: stage 1, then sign up a Google test user | **Yes** (for old clients) |
| N-6b | Low | Legacy stored external photo URLs | Read-only inventory + migration plan | ✔ | ✔ | ✔ | — | ✖ | ✖ | Yes (read) | Owner: run the inventory (§11); approve the migration if any are found | No |
| N-7 | Medium | Released versions' photos may carry EXIF/XMP GPS | Lossless in-place strip keeping the token; header-only inventory; dry-run default; backup + manifest; guarded CLI | ✔ | ✔ 39 | ✔ 4 | ✔ CLI rehearsal | ✖ | ✖ | Yes (reads private photos) | Owner: authorize the inventory (§9) | No (privacy debt) |
| C-1 | Low | New-upload stripping coverage | 8 orientations, GIF, TIFF, truncated, random | ✔ | ✔ 12 | — | — | — | — | No | Device test: HEIC from iOS gallery is refused with a message if not converted | No |
| D-16 | Low/Med | Cleanup lacked per-object outcomes and an overlap guard | Outcome codes; Firestore lease; CLI dry-run; synthetic-volume test | ✔ | ✔ 35 | ✔ 7 | — | ✖ | ✖ | Yes | Owner: two weekly dry-runs, then a decision on enabling | No |
| X-6 | High | Release fell back to the **debug key** | Release fails early without a complete `key.properties` and Maps key; no fallback | ✔ | — | — | ✔ (test-key build verified by apksigner) | — | — | No | Owner: create and back up the upload key (§3) | **Yes** |
| X-5 | High | No Firebase app for `com.touchgrass.app` | Gradle gate with an actionable message; `tool/check_firebase_config.mjs` | ✔ | — | — | ✔ (debug/release stop with the message) | ✔ LIVE-READ: still unregistered | — | Yes (register apps) | Owner: §1 | **Yes** |
| iOS-1 | High | `google_maps_flutter_ios` 2.18.3 needs iOS 14; Runner targeted 13.0 (pod install would fail) | Deployment target 14.0 | ✔ | — | — | ✖ (no Mac) | — | — | No | Owner: `pod install` on a Mac | **Yes** (iOS) |
| iOS-2 | Medium | No entitlements (Sign in with Apple, Push); no Google URL scheme; no plist | Documented; checker flags them | — | — | — | ✖ | ✖ | — | Apple account | Owner: §5 | **Yes** (iOS) |
| iOS-3 | Low | Permission texts said "challenge verification" (AI is off); an add-to-library purpose was declared but unused | Accurate camera/photos texts; unused key removed | ✔ | ✔ (existing plist test) | — | ✖ | — | — | No | — | No |
| AI-1 | Medium | A mis-deploy of `verifyChallengeCompletion` could run AI | `AI_VERIFICATION_ENABLED = false` checked before auth, data or Gemini | ✔ | ✔ 2 | — | — | — | — | No | Deploy functions by name only | No |
| DEP-1 | High (dev-only) | `firestore-tests` grpc-js 1.9 (5 high) | npm `overrides` → 1.14.6; 310/310 rules tests pass | ✔ | — | ✔ | — | — | — | No | Remove the override once the SDK range is fixed | No |
| IDX-1 | Low | Location-removal query index | Docs: covered by automatic indexes (implicit `__name__`); not provable in the emulator | — | — | — | — | ✖ | ✖ | Yes | Owner: one production run with a test account | No |
| D-12 | Medium | Leaderboard model | No safe fix without a schema change; recommendation in the final report | — | — | — | — | — | — | — | Owner decisions (Phase 5 §6) | No |
| A11Y-1 | Low | Weather chip label | Extracted and tested | ✔ | ✔ 3 | — | — | — | — | No | — | No |

**Test totals (this run; exit codes in `PHASE_6_FINAL_REPORT.md`):**
- Flutter: **460** passed (Phase 5: 431; +29 new), analyze clean, format clean.
- Functions: 152 unit, 23 emulator.
- Rules: 310 emulator.
- Audits: Functions 0; `firestore-tests` 0.
- Web build and bundle scan: built, clean.
- Android:
  - repo debug and release: **stopped by the X-5 gate**, as intended;
  - scratchpad copy with a corrected config: release without a key **stopped by the signing gate**;
  - copy with a TEST key: **built**, and the signature was verified.
- iOS: not built (Windows).

**Rollback:** the pre-Phase-6 copies of every edited file are in the scratchpad (`p6/bak/`). Nothing is committed, so reverting the Phase 6 files restores Phase 5. To undo the dependency changes, restore the `firestore-tests` package files, then run `npm ci`.

## Phase 7A — results (2026-10-19)

Local work plus **read-only** production checks. Nothing was committed, pushed or deployed, no production data, rules, apps, keys or billing changed, and AI verification stays off. `DOCUMENTATION.md` is unchanged (SHA-256 `baa43787…a9f94bc`, before and after). Full narrative: `PHASE_7A_FINAL_REPORT.md`; owner steps: `PHASE_7A_RELEASE_RUNBOOK.md`; production changes: `PHASE_7A_DEPLOYMENT_MANIFEST.md`; privacy: `PHASE_7A_PRIVACY_DISCLOSURE_DRAFT.md`; starting state: `PHASE_7A_BASELINE.md`.

**Read-only production facts:**
- live Firestore rules = HEAD `firestore.rules`;
- live Storage rules let any signed-in user read and list all completion photos;
- no composite indexes and no functions are deployed;
- billing is enabled;
- apps are still registered only as `com.example.touchgrass`.

Status columns as in Phase 6: **Impl**, **Unit**, **Emu**, **Int**, **Prod-cfg** (verified against production config), **Deployed**.

| ID | Sev | Issue | Fix / work | Impl | Unit | Emu | Int | Prod-cfg | Deployed | Owner / next action | Blocks release |
|---|---|---|---|---|---|---|---|---|---|---|---|
| P7-1 (B12) | **Critical** | LIVE Storage rules: cross-user read/list of completion photos; any file type; no avatar rule | Interim `deploy/interim/storage.interim.rules`, compatible with the live and new apps | ✔ | — | ✔ 14 + 6 | — | ✔ LIVE-READ | ✖ | ⚠️ Authorize S-1 (runbook §5.2) | **Yes** |
| P7-2 (B13) | High | No composite indexes in production; `firebase.json` never deployed the file | `firebase.json` references `firestore.indexes.json`; Dart parity test | ✔ | ✔ 3 | — | — | ✔ LIVE-READ | ✖ | ⚠️ Authorize I-1 (§5.3) | **Yes** |
| P7-3 | High | Phase 6 claimed old clients stay compatible; the live web app's completion flow is denied by the local rules | Proven by `live_client_compat` (7); coordinated window R-1 + S-2 + H-1 | ✔ | — | ✔ 7 | — | ✔ (live = HEAD) | ✖ | ⚠️ Coordinated window (§5.5) | **Yes** |
| P7-4 | — | No safe way to see live rules | `tool/export_live_rules.mjs` (read-only MCP tool; snapshot in `ops-out/`) | ✔ | ✔ 14 | — | ✔ ran on prod | ✔ | — | Re-run before every rules deploy | No |
| P7-5 (B11) | Medium | Photo-tool backups inherited the download token and lived outside the user's prefix | Backups are new objects with no token, at `metadata_backup/completion_photos/{uid}/{run}/`; deletion removes them; resume; private `--out`; no cursors on stdout | ✔ | ✔ +6 | ✔ | — | — | ✖ | — | No |
| P7-6 | Low | Deletion said "not deleted" after a timeout | "Couldn't confirm… retrying is safe" | ✔ | ✔ 2 | — | — | — | ✖ | — | No |
| P7-7 (X-5) | High | Config validator incomplete; local ≠ registered | Rewritten: about 35 local checks plus read-only `--live` | ✔ | ✔ 16 | — | ✔ ran | ✔ LIVE-READ: unregistered | — | Owner §1 | **Yes** |
| P7-8 (X-6) | High | Signing gates had no repeatable test | `tool/test_android_gates.sh` | ✔ | — | — | ✔ 13 gate + 10 build | — | — | Owner §2 | **Yes** |
| P7-9 (X-4) | Medium | One Maps key on web, iOS and Android; iOS key hard-coded | iOS key via a git-ignored xcconfig (release requires it); validator flags shared keys; debug-build warning | ✔ | ✔ | — | ✖ (no Mac) | — | — | Owner §9 | No |
| P7-10 | High (iOS) | No Podfile (iOS 14 needed) | `ios/Podfile` from Flutter's template, `platform :ios, '14.0'` | ✔ | — | — | ✖ | — | — | `pod install` on a Mac | **Yes** (iOS) |
| P7-11 (B14) | High (iOS) | Deletion doesn't revoke Sign in with Apple tokens | Documented; not implemented blind | — | — | — | — | — | — | Owner verifies the Apple requirement | iOS |
| P7-12 | Medium | Privacy text says only you can see your photos (false live); deletion promised but not deployed | Disclosure draft with an inventory and mismatches M-1…M-6 | ✔ | — | — | — | — | — | Owner §10 | Store |
| P7-13 | Medium | Rules tests missed operator data, catalogues and queries | `operator_and_queries` (10) | ✔ | — | ✔ 10 | — | — | — | — | No |

**Test totals (this run):**
- Flutter: 465 passed; format and analyze clean; web build and bundle scan clean.
- Functions (Node 22.23.3): 158 unit; 23 emulator; lint 0; audits 0.
- Rules: 347.
- Tools: 30.
- Android: 13 gate cases and 10 build checks.
- iOS: not built.

**Rollback:** the pre-Phase-7A copies of every edited file are in the scratchpad (`p7/bak/`). Nothing is committed. The new files can simply be deleted. `firebase.json`'s `indexes` line only matters for a deploy.

## Phase 7B — Storage containment (2026-10-19)

**Status: NOT DEPLOYED. Awaiting explicit authorization.** Reports:
- `PHASE_7B_STORAGE_CONTAINMENT_REPORT.md`
- `PHASE_7B_STORAGE_CONTAINMENT_RUNBOOK.md`
- `PHASE_7B_STORAGE_TEST_MATRIX.md`

| ID | Finding / work | Evidence | State |
|---|---|---|---|
| P7B-1 | Live Storage rules re-verified unchanged (two read-only exports, SHA-256 `c5502223…29579d`). Target confirmed as `touchgrass-today` (760620662222), bucket `touchgrass-today.firebasestorage.app`. Look-alike project `gen-lang-client-0754598293` ("TouchGrass") ruled out. | projects:list, sdkconfig, live web bundle | Verified (read-only) |
| P7B-2 | **NEW:** the live rules also let any signed-in user list the `completion_photos` root, which enumerates every uid | Emulator matrix T07, using the exact live ruleset | Containment ready, not deployed |
| P7B-3 | **Interim rules defect fixed:** avatars used `allow read`, which includes `list`, so all avatars could be enumerated. Now `allow get`. | Matrix T33 | Local fix; 424/424 tests |
| P7B-4 | Live web app compatibility, from the public `main.dart.js` paths and types | Matrix T10–T13, T25, T26, T38, SEQ | Verified locally |
| P7B-5 | Token URLs bypass rules; URLs harvested while open stay valid after the deploy | Analysis, report §5 | **Open:** token rotation needs separate authorization |
| P7B-6 | Final `storage.rules` has the same avatar `allow read` construct | Code review | Open (before the coordinated release) |
| P7B-7 | Rollback artifact: exact live rules plus config | `ops-out/rollback/storage-live-2026-10-19/SHA256SUMS` | Ready |

## Phase 7C — Photo privacy remediation & release hardening (2026-10-20)

**Status: local fixes and tools tested. NOTHING deployed or run against production.** Production still
runs the exposed Storage rules (read-only export at 03:33Z on 2026-10-20, SHA-256 `c5502223…29579d`), so
S-1 is still pending. Reports:
- `PHASE_7C_FINAL_REPORT.md`
- `PHASE_7C_PHOTO_TOKEN_REMEDIATION_PLAN.md`
- `PHASE_7C_HISTORICAL_METADATA_RUNBOOK.md`
- `PHASE_7C_STORAGE_SECURITY_TEST_MATRIX.md`
- `PHASE_7C_RELEASE_PRIVACY_CHECKLIST.md`

| ID | Finding / work | Evidence | State |
|---|---|---|---|
| P7C-1 | Final `storage.rules`: avatars `allow read` (includes `list`) → `allow get`. This closes P7B-6. | Emulator: pre-fix listed avatars, post-fix denied; parity P50–P52 | **Fixed locally**; ships with S-2 |
| P7C-2 | Release gate: 64 cases × FINAL/INTERIM, documented differences only (P37, P43), static grant inventory, config check | `firestore-tests/test/storage_release_parity.test.mjs` (144 tests) | Done; rules suite 568/568 |
| P7C-3 | **New uploads could carry location in data appended after the JPEG** (MPF image with GPS, motion-photo video) or APPn between scans. The stripper now stops at EOI (app and operator tool). | 5 Dart tests failed before the fix; TS unit and emulator tests | **Fixed locally** |
| P7C-4 | Profile photos are now sanitised at the upload boundary (metadata-free PNG) | `sanitizeProfilePhoto` (3 tests) | Fixed locally |
| P7C-5 | Download tokens are redacted from Crashlytics reports and logs (image errors include the full URL) | `secret_redaction.dart` (5 tests) | Fixed locally |
| P7C-6 | Historical metadata tool: a backup is deleted if its overwrite doesn't happen (e.g. `deleteAccount` mid-run); shared lease with token rotation; `--full-read` finds appended data; `--uid` scope | Unit + emulator | Fixed locally; **not run in production** |
| P7C-7 | **Token rotation tool** `photo-token-rotate`: a new single token per completion photo plus the owner's links; dry-run default; resumable without a second token; skips uploads from the last 10 minutes; never recreates a deleted photo | Emulator: **old URL refused**, links open identical bytes | **Ready; needs S-1 live, then AC-2/AC-3/AC-4** |
| P7C-8 | Live web app's account deletion fails at Firestore (completion and user deletes denied) **before any Storage deletion** | Live bundle call order + live Firestore rules | Open (D-04 / F-1) |
| P7C-9 | Disclosure review: "photos only you can see" and the deletion claims are false today; the avatar link is a bearer link; the store listing still advertises AI verification | Final report §9 | Review-ready; nothing published |

## Phase 7D — Production containment & release readiness (2026-10-20)

**Production change made (authorized): the interim Storage rules (S-1) only.** Everything else is local or
read-only. Reports:
- `PHASE_7D_FINAL_REPORT.md`
- `PHASE_7D_PRODUCTION_SECURITY_RUNBOOK.md`
- `PHASE_7D_TOKEN_ROTATION_RUNBOOK.md`
- `PHASE_7D_HISTORICAL_PHOTO_REMEDIATION_RUNBOOK.md`
- `PHASE_7D_ACCOUNT_DELETION_REMEDIATION.md`
- `PHASE_7D_PRIVACY_DISCLOSURE_MATRIX.md`
- `PHASE_7D_RELEASE_GATE_CHECKLIST.md`

| ID | Finding / work | Evidence | State |
|---|---|---|---|
| P7D-1 | **S-1 deployed** with `firebase deploy --only storage --config deploy/interim/firebase.interim-storage.json --project touchgrass-today` (exit 0, Storage only) | Read-only export at 04:30Z: live `storage.rules` byte-identical to the interim file (`630dc9a0…`); Firestore unchanged (`eb6b6b1c…`); no functions or indexes | **LIVE, verified.** Test-account smoke tests pending (owner). |
| P7D-2 | Token rotation made **two-phase**: add the new token → update links → remove the old one. A saved link never points at a dead token. Default removal by metadata patch (no bytes rewritten); `--remove-via rewrite` alternative. | Unit invariant after every write; emulator: the old URL and the new link both work mid-rotation; the emulator's token merging is reported as `verify-failed` | Local. Production canary decides the mode (AC-3). |
| P7D-3 | Account deletion root cause: the live client cascade's first write (batch-delete `completions`) is refused by the create-only rules. Users without completions get a **partial** deletion (Journal, username, leaderboard gone; profile, photos, Auth kept). | Live bundle call order + live rules | Fix = server `deleteAccount` (local); F-1 + H-1 pending |
| P7D-4 | `deleteAccount` second Storage sweep (uploads by another still-valid session during deletion) | Unit + emulator (concurrent requests, late upload, links dead after deletion) | Local |
| P7D-5 | Misleading copy corrected: photo visibility, profile-photo links, "everything" deleted, AI claims (onboarding, Terms, "AI Verdict", permission and help text), the Journal "AI Verified" default, store listing | `privacy_copy_test.dart` regression group; disclosure matrix | Local; nothing published |
| P7D-6 | Release gate: `.firebaserc`, `firebase_options.dart` and `firestore.rules` must agree on project and bucket; no look-alike project | Parity test | Local |
| P7D-7 | **Blocker:** no Application Default Credentials on the operator machine, so the production dry-run and inventory can't run from this session | `gcloud` absent; no ADC file | Owner |

## Phase 7E — Incident remediation & release readiness (2026-10-20)

**Production operation performed (authorized):** the S1–S9 live Storage smoke test, run with 2 dedicated test accounts
and synthetic objects. The test accounts were self-deleted; one 1×1 test avatar is left over. Nothing else changed in
production. Reports:
- `PHASE_7E_FINAL_REPORT.md`
- `PHASE_7E_PRODUCTION_SMOKE_TEST_RESULTS.md`
- `PHASE_7E_TOKEN_ROTATION_STATUS.md`
- `PHASE_7E_HISTORICAL_METADATA_STATUS.md`
- `PHASE_7E_ACCOUNT_DELETION_RELEASE_PLAN.md`
- `PHASE_7E_ANDROID_RELEASE_READINESS.md`
- `PHASE_7E_RELEASE_GATE_CHECKLIST.md`

| ID | Finding / work | Evidence | State |
|---|---|---|---|
| P7E-1 | Live Storage containment verified end to end | Live smoke 32/32 (05:26Z) | **Contained at rules level** |
| P7E-2 | An existing token URL opens a photo **without sign-in** in production | Live T1: HTTP 200 (random token 403) | Open: legacy links not remediated |
| P7E-3 | Rotation tool: dry-run aggregates (no references, stale links, predicted writes) and `--stop-before-remove` for the revocation experiment | Unit tests | Local |
| P7E-4 | **Deploy blocker:** `defineSecret("GEMINI_API_KEY")` in `index.ts` meant `deploy --only functions:deleteAccount` would prompt for and create the secret (firebase-tools resolves every param before `--only`). AI callable moved to `aiVerification.ts`, not exported; entry-point test added. | firebase-tools 15.19.1 source; `entryPoint.test.ts` | **Fixed locally** |
| P7E-5 | Deletion tests: 0/1/3 completions × with/without photos; second-sweep failure + retry | Emulator 43/43 | Fixed locally; F-1 pending |
| P7E-6 | Firebase **Android and iOS** apps are both registered as `com.example.touchgrass`; the app ID is `com.touchgrass.app` | `apps:sdkconfig` (identifiers only) | Production registration pending authorization |
| P7E-7 | Android gates | `tool/test_android_gates.sh` 14/14 | Local |
| P7E-8 | Production dry-run and inventory still blocked: no ADC on the operator machine | — | Owner |

## Phase 7F — Incident remediation, production safety & release readiness (2026-10-21)

**Production operations:** read-only only (rules releases and rulesets, `functions:list`, `apps:list`).
Nothing was written, deployed, registered, rotated, inventoried or published. The incident remains open.
Reports:
- `PHASE_7F_FINAL_REPORT.md`
- `PHASE_7F_PRODUCTION_SECURITY_STATUS.md`
- `PHASE_7F_TOKEN_ROTATION_RESULTS.md`
- `PHASE_7F_HISTORICAL_METADATA_REMEDIATION.md`
- `PHASE_7F_ACCOUNT_DELETION_VALIDATION.md`
- `PHASE_7F_LATE_UPLOAD_MITIGATION.md`
- `PHASE_7F_FIREBASE_PLATFORM_CONFIGURATION.md`
- `PHASE_7F_ANDROID_SIGNING_GUIDE.md`
- `PHASE_7F_RELEASE_READINESS.md`

| ID | Finding / work | Evidence | State |
|---|---|---|---|
| P7F-1 | Live state re-verified: Storage = interim (byte-identical, released 04:30:20Z on 2026-10-20), Firestore = HEAD (released 2026-08-13), no functions, apps unchanged | Read-only Rules API + CLI | **Contained at rules level** |
| P7F-2 | **The rotation "dry-run" wrote to production Firestore:** it took the `_ops/photoRewrite_lease` lease (so did the `orphan-photos` and remediation dry-runs) | Source review; emulator test runs the real CLI and asserts no `_ops` doc | **Fixed locally** (`leaseFor`) |
| P7F-3 | Rotation reference queries read whole documents (completion locations entered the tool's memory) | Source review | **Fixed locally** (`select("photoUrl")`) |
| P7F-4 | Real-project runs could name a foreign bucket or the look-alike project; a capped dry-run couldn't resume; link anomalies weren't reported | Unit tests | **Fixed locally** |
| P7F-5 | Revocation experiment harness (`revocationExperiment.ts`): setup, probes, verdict, cleanup; drives the real rotation CLI | Emulator rehearsal: rewrite → `revoked`; metadata (emulator merges) → `not-revoked` | Ready; **needs ADC + AC-3a/AC-3b** |
| P7F-6 | Late-upload window: final `storage.rules` require `users/{uid}` (`hasProfile()`, cross-service, evaluated last) | Rules suite: P71/P72 FINAL DENY; static guard | **Fixed locally**; ships with S-2 (IAM grant on first deploy) |
| P7F-7 | `deleteAccount` deploy graph: local manifest discovery shows exactly one endpoint, no params, no required APIs | `/__/functions.yaml` | Ready for F-1 |
| P7F-8 | Partial deletions by the live client: signature (profile without its username claim) and recovery plan | Design | Owner/legal decision; audit needs authorization |
| P7F-9 | Historical avatars: the live code re-encodes avatars from pixels (no metadata); older builds unverified | Source at HEAD | Low risk; optional scan |
| P7F-10 | Production inventory, experiment and rotation still blocked: no `gcloud`/ADC on the operator machine | Existence check only | **Owner** |

## Phase 7G — Final security remediation, privacy & release readiness (2026-10-21)

**Production operations:** none (not even read-only). This machine has no Google Cloud CLI or ADC, so every
production step is prepared and waiting. The incident remains open. Reports:
- `PHASE_7G_FINAL_REPORT.md`
- `PHASE_7G_AI_COPY_AUDIT.md`
- `PHASE_7G_DRY_RUN_SAFETY_AUDIT.md`
- `PHASE_7G_TOKEN_ROTATION_RUNBOOK.md`
- `PHASE_7G_HISTORICAL_METADATA_RUNBOOK.md`
- `PHASE_7G_ACCOUNT_DELETION_VALIDATION.md`
- `PHASE_7G_STORAGE_RULES_DEPLOYMENT.md`
- `PHASE_7G_FIREBASE_ENVIRONMENT_PLAN.md`
- `PHASE_7G_RELEASE_READINESS.md`

| ID | Finding / work | Evidence | State |
|---|---|---|---|
| P7G-1 | Camera caption step advertised "AI verification — Coming soon!" (and a "premium feature" screen-reader label); completions stored "AI verification is a premium feature" and Challenge details showed it; the "Share Adventure" button saved privately | Source | **Fixed locally**: truthful copy, "Save to Journal", legacy reasons never shown; unused "Coming Soon" card deleted; regression scan of `lib/` |
| P7G-2 | Operator tools had no central mutation mode; the bucket check accepted `appspot`; mixed emulator environments and a conflicting `GCLOUD_PROJECT` weren't refused | Source | **Fixed locally**: `--mode`, exact allowlist, `demo-` emulators, fail closed |
| P7G-3 | `--out` could land anywhere (incl. `functions/`, which a deploy uploads) and overwrote files; malformed resume files could be echoed by the JSON parser | Source | **Fixed locally**: `ops-out/` only, never overwrite, fixed error text |
| P7G-4 | `profile-photo-inventory` read whole profiles (email, settings); `orphan-photos` read whole documents | Source | **Fixed locally**: field masks |
| P7G-5 | Dry-runs proven read-only: mutation-trapping fakes for every command (+ an `--execute` control) and an emulator snapshot of all Firestore docs and Storage objects across all six dry-run variants | `readOnlyGuarantee.test.ts` 15/15; emulator | Local proof; production unverified |
| P7G-6 | A deleted account's still-valid session could re-create its profile and then upload again (the residual 7F case) | Rules analysis | **Fixed locally**: `deleteAccount` writes `deletedAccounts/{uid}` before deleting the profile; `firestore.rules` refuse profile creation for marked uids |
| P7G-7 | Storage→Firestore permission for the final Storage rules identified exactly: `roles/firebaserules.firestoreServiceAgent` for the Storage service agent, project-level; `--force` auto-grants and `--non-interactive` skips it | firebase-tools 15.19.1 `rulesDeploy.js` | Needs AC-7a + AC-7b |
| P7G-8 | Upload metadata fixtures extended: EXIF thumbnail, PNG data after IEND, rotated avatar, HEIC refused, large rotated photo | `image_metadata_phase7g_test.dart` 5/5 | Local |
| P7G-9 | One Firebase project for dev and prod; `.firebaserc` defaults to production | Inspection | Plan only (AC-9) |

## Phase 7H — Security remediation, release readiness & finalization (2026-10-24)
Report: `PHASE_7H_FINAL_REPORT.md`; AC-1 steps: `PHASE_7H_AC1_RUNBOOK.md`.

**Production:** nothing performed. AC-1 is authorized but not run: the Google Cloud CLI is now installed and signed in
(same account as the Firebase CLI), but Application Default Credentials are absent and the owner hasn't confirmed
readiness.

| # | Finding | Evidence | Status |
|---|---|---|---|
| P7H-1 | AC-1 run would lose its results (output folder missing; written only after all reads); any folder named `ops-out` accepted; no credential preflight; the read-only file held object paths/uids | Code review | **Fixed locally** (B24); `readOnlyGuarantee.test.ts` +6; emulator CLI test |
| P7H-2 | Stale session of a deleted account could create challenges, completions, Journal entries, feedback, username claims; marker written after some deletions | Rules analysis | **Fixed locally** (B20); rules tests +17; not deployed |
| P7H-3 | Node 22 test runner hides suites whose `describe()` throws | Reproduced | **Fixed** (B21): `tool/strict_node_test.mjs` in every script |
| P7H-4 | functions `serve`/`shell` used production; a local `deleteAccount` would delete real data | `package.json` | **Fixed** (B22) |
| P7H-5 | Account deletion: no progress, possible double start, no confirmation | Code review | **Fixed locally** (B23); 4 Flutter tests |
| P7H-6 | `body-parser` 2.3.0 (via firebase-functions → express) high-severity DoS advisory GHSA-27r3-jxmh-p828 | `npm audit` | **Fixed**: lockfile-only update to 2.4.0; audit 0 |
| P7H-7 | Debug builds send Analytics/Performance data to production; app always uses production Firebase | Code review | Open — part of AC-9 (needs a dev project) |
| P7H-8 | No app-level iOS privacy manifest (`PrivacyInfo.xcprivacy`) | Inspection | Open — needs Xcode/Mac |

## External actions (only you can do these)
| # | Action | Status |
|---|---|---|
| **X-1** | **Revoke/delete the exposed Gemini key** in the provider console. It was confirmed live in the public bundles (V-1). | **OWNER-REPORTED DONE (2026-10-17), not independently verified.** A clean bundle scan isn't proof of revocation. The deployed bundles still contain the old key string until they're redeployed, which is harmless only if the key really is revoked. |
| X-2 | Export the live Storage rules | **DONE read-only (Phase 7A):** exported with `tool/export_live_rules.mjs`. Cross-user read is open (B12); the interim fix is ready (S-1, awaiting authorization). |
| X-3 | Add `touchgrass.web.app` to Auth Authorized domains | OPEN (A-6) |
| X-4 | Maps key restrictions | OPEN. Phase 7A: one key (`#97425825`) serves web, iOS and Android, so it can't be restricted correctly. Create per-platform keys (runbook §9). |
| X-5 | Register the Android and iOS apps as `com.touchgrass.app`; download the config files; add SHA fingerprints; then run `flutterfire configure` | **OPEN, blocks Android and iOS.** LIVE-READ 2026-10-19 (Phase 6): Android `com.example.touchgrass` (no SHA fingerprints) and iOS `com.example.touchgrass` only. Builds now stop with an actionable message; `node tool/check_firebase_config.mjs` lists what's missing. Steps: `PHASE_6_RELEASE_RUNBOOK.md` §1. |
| X-6 | Release keystore (`android/key.properties`) and iOS signing | OPEN. Phase 6: release builds **refuse** to build without a complete `key.properties` (no debug fallback; verified). Owner steps and backup: runbook §3; iOS: §5. |
| X-7 | Confirm the Firebase plan; Blaze decision | **VERIFIED read-only (Phase 7A): billing enabled.** No paid services were enabled by Claude. Each deploy still needs explicit approval. |
| X-8 | Host the privacy policy and terms; confirm the support mailbox | OPEN |
| X-9 | Web push VAPID key (optional) | OPEN |
| X-10 | App icon artwork | OPEN |
| X-11 | Data Safety form, privacy labels, store listing | OPEN |
