# TouchGrass — Pre-Deployment Audit Report

- **Date:** 2026-10-17
- **Branch / HEAD:** `release-hardening-pass` @ `67c5a38`. Working tree: only the untracked `DOCUMENTATION.md`, which predates this audit.
- **Scope:** I read the whole repository, ran the build and test baseline, and probed the security rules in a local emulator against a `demo-` project, which cannot reach production.
- **Changes made:** none to the repository. Every artifact from this audit is in the session scratchpad.
- **Evidence levels used below:**
  - **STATIC**: I traced it in the code.
  - **TEST**: an automated test in the repo covers it.
  - **EMULATOR**: I checked it in the local Firestore or Storage emulator during this audit.
  - **LIVE**: checked against the real deployed system. Nothing in this audit was checked live.
  - **UNVERIFIED**: there was no environment available to check it.

---

## 1. Executive summary

| Target | Readiness | Why |
|---|---|---|
| **Overall** | **NOT READY** | 8 P0 defects. Three of them break core flows: no XP or streak on a user's first day, account deletion always fails, and the Storage rules don't compile. The rest are confirmed security or privacy gaps. |
| **Web (touchgrass.web.app)** | **Internal testing only** | The release build compiles and 235/235 tests pass. However, the live bundle has the Gemini API key embedded in it, any user can set their own leaderboard XP to any value (confirmed in the emulator), and nobody can delete their account. The Google sign-in authorized-domain step for `touchgrass.web.app` is still listed as outstanding in KNOWN_BUGS B10. |
| **Android** | **NOT READY** | The Firebase config package (`com.example.touchgrass`) doesn't match the app's `applicationId` (`com.touchgrass.app`). Release builds silently fall back to debug signing. The app icons are Flutter's defaults. `flutter build apk --debug` fails on that package mismatch (§6). |
| **iOS** | **NOT READY**, could not test | There is no `GoogleService-Info.plist`. The Firebase `iosBundleId` doesn't match the Xcode bundle ID. The Google Sign-In URL scheme and the Sign in with Apple entitlement are both missing. This can't be built on Windows. |

**What's solid.**
- `flutter analyze` is clean.
- 235/235 Flutter tests and 49/49 Functions tests pass.
- The web release build compiles.
- The emulator confirmed that one user can't read another user's private profile, completions, or completion photos, and that a client can't change its own `entitlementTier` or AI-usage counters.
- Reduced-motion handling is wired across 16 files.
- Every network image has an error fallback.
- The companion never repeats the previous message (tested).

**What blocks a public release:** see §3. The items that break the user journey are D-01, D-04 and D-05.

---

## 2. Master feature checklist

Legend: `[x] PASS` · `[~] PARTIAL` · `[ ] FAIL` · `[?] UNVERIFIED` · `[-] N/A`. File references are relative to the repo root.

### A. Authentication & account management
| Status | Requirement | Evidence / notes |
|---|---|---|
| [?] | Email/password registration | The code path exists (`auth_service.dart:109`, `user_repository.dart:51`). Not tested live. On a new account the first completion awards 0 XP (D-01). |
| [?] | Sign-in / sign-out | `auth_service.dart:93,140`. Sign-out also skips Google on web. Not tested live. |
| [~] | Google sign-in config & branding | Web uses a popup (`auth_service.dart:32`). `touchgrass.web.app` still needs adding to Authorized domains (B10, an external action). The "G" logo is hand-painted, not the official asset (`social_sign_in_button.dart:196`; `assets/icons/google_logo.png` was never supplied). Android has the package mismatch (D-08). iOS has no URL scheme. |
| [?] | Password reset & auth errors | `login_screen.dart:558`. Errors are mapped in `auth_service.dart:242-263`. Not tested live. |
| [?] | Auth state survives restart | Uses the Firebase SDK's default persistence. Not tested. |
| [x] | Protected routes enforce auth | The router redirects signed-out users (`app_router.dart:267-289`). Server-side, the emulator showed cross-user reads are denied. |
| [~] | Profile initialized with the auth UID | `_resolveUser` (`user_repository.dart:590`). However, `lastActiveDate` is initialized to "now", which causes D-01, and the create rule doesn't limit initial values (D-02). |
| [~] | Profile settings show the auth email | `profile_screen.dart:361`. This reads the copy stored in Firestore at sign-up, which is never re-synced from Firebase Auth. |
| [~] | Member Since is accurate (timezone, missing data) | `.toLocal()` is applied and there are 10 tests. Gaps: (1) day counts come out one short across a DST spring-forward (`member_since.dart`, `difference().inDays`); (2) a missing `createdAt` falls back to "now" and shows "Today" (`user_model.dart:278`); (3) a client can overwrite its own `createdAt` (EMULATOR). |
| [ ] | Account deletion | **FAIL (EMULATOR).** The rules deny deleting a user's completions (step 2) and their `users/{uid}` doc (step 7), and Storage denies deleting their photos (D-04). |
| [~] | Understandable failure feedback | Errors are mapped, but `diagnosticFailureMessage` (`camera_providers.dart:73`) puts raw JS/Firebase error text in the UI. |
| [~] | No access to or changes of another user's data | Reads are isolated (EMULATOR). But **any user can overwrite another user's username claim** (EMULATOR, D-03). |

### B. Profile photos & camera
| Status | Requirement | Evidence / notes |
|---|---|---|
| [?] | Select a photo from the device | `settings_screen.dart:753-825`. Not tested live. |
| [?] | Replace an existing photo | Uploads overwrite `user_avatars/{uid}.png`. What the live Storage rules allow is unknown (D-05). |
| [?] | Native camera on mobile | `ImageSource.camera`. Not tested on a device. |
| [ ] | Camera permissions & denial states | The settings flow has no permission primer and no try/catch around `pickImage`, so a denial produces no feedback for the user (STATIC). |
| [?] | Unsupported browser or device degrades gracefully | Not tested. |
| [~] | Crop, size, compression | The crop is rendered as a 560 px PNG (`settings_screen.dart:2267`) and is not compressed further. That's acceptable but not optimized. |
| [~] | Upload progress, errors, retry | There's a spinner and an error toast, but no progress indicator and no retry button. |
| [?] | Photo persists across navigation and restart | Not tested live. |
| [?] | Photo refreshes everywhere in the app | The download URL changes on each upload and the leaderboard mirror is synced. Not tested live. |
| [ ] | Storage enforces ownership, size and content type | **FAIL.** `storage.rules` doesn't compile (EMULATOR, D-05). The `image/.*` pattern also accepts SVG (EMULATOR). |
| [~] | A failed upload leaves no misleading state | The upload and the Firestore update are two separate steps. If the second fails, a new file exists but the profile still shows the old URL. |

### C. Daily challenges
| Status | Requirement | Evidence / notes |
|---|---|---|
| [?] | A valid daily challenge is displayed | Generation falls back through 3 tiers to a synthetic challenge (`challenge_generation_service.dart`). Not tested live. |
| [~] | Rotates by local day and timezone | Doc IDs use the local date (`challenge_model.dart:352`). **The challenge goes stale after midnight while the app stays open (D-11).** |
| [~] | Deterministic selection | The seed is deterministic, but the text Gemini writes is not. Two devices generating at the same time overwrite each other (`set`, `merge:false`). |
| [~] | Doesn't change mid-session or on refresh | `todaysChallengeExists` returns false on any read error (`challenge_repository.dart:65-72`), which regenerates and overwrites today's doc. |
| [~] | New challenge appears on the correct day | Same issue as D-11. `dayNumber` also uses the UTC calendar day of `createdAt` (`assignment_providers.dart:265-270`) and is off by one across DST. |
| [~] | Categories and preferences respected | Seed selection is tested (5 tests). Gemini's returned category can still differ. |
| [?] | Titles readable on narrow screens | Overflow protection exists (A11). Not checked visually. |
| [~] | Descriptions and completion states accurate | **The success screen shows "+0 XP" while the Journal and detail screens show "+25 XP" for the same completion** (D-01, D-13). |
| [~] | Repeat submissions can't double-reward | The UI path is protected by deterministic completion IDs and same-day gating. Through the API directly, anyone can create completions with arbitrary challenge IDs and add XP (EMULATOR). |
| [~] | Safe fallback for empty or malformed data | A doc that fails to parse maps to `null` and shows the pending card. Because the doc still "exists", retrying never regenerates it, so the user is stuck (STATIC, plausible). |
| [~] | Consistent across sessions and devices | See the determinism and overwrite issues above. |

### D. Photo uploads, verification & XP
| Status | Requirement | Evidence / notes |
|---|---|---|
| [?] | Users can submit adventure photos | `camera_providers.dart:317-499`. The live Storage rules are unknown (D-05). |
| [~] | Realistic sizes and formats | Compressed client-side (`image_compression.dart`) with a 10 MB cap. Not tested live. |
| [~] | Upload errors, retries, network loss | Offline pre-check, timeouts and a retry path exist. Each retry uploads a new orphaned file (D-16). |
| [~] | UI distinguishes upload / verify / result states | The analyzing, uploading and saving stages exist, plus a failure state carrying the confidence score. |
| [x] | "AI is reviewing" appears only when AI is running | Gated on `usingAi` (`camera_screen.dart:1407`, `camera_providers.dart:360-369`). STATIC; the existing test only checks constructor defaults. |
| [ ] | AI runs on the intended backend, no insecure fallback | **FAIL.** The camera calls Gemini from the client using a key embedded in the bundle. The fail-closed `challengeVerificationServiceProvider` is never used anywhere (D-06, D-10). |
| [~] | Free / premium / admin entitlements enforced | Enforced client-side only. A client can't change its own tier (EMULATOR), but **granting a tier on the server breaks all of that user's client writes** (EMULATOR, D-07). |
| [ ] | AI quota enforced on a trusted backend | **FAIL.** The quota logic only exists in the undeployed Cloud Function. A premium client calls Gemini without limit. |
| [ ] | XP awarded per the intended rules (including honor-system) | **FAIL.** No XP is awarded on the sign-up day or on a day the user explicitly signs in (D-01). |
| [~] | No duplicate XP | The UI path is guarded. The rules allow +4000 XP per write with no limit on the number of writes (EMULATOR). |
| [~] | XP, level, streak, league and achievements stay consistent | The rules allow them to diverge. `buyStreakFreeze` leaves the stored `level` stale. |
| [ ] | Untrusted clients can't manipulate rewards | **FAIL (EMULATOR)**, see D-02. |
| [ ] | Failures say whether the photo was saved and whether XP was awarded | If the reward write fails, the app still shows a success screen claiming `completion.xpAwarded` (`camera_providers.dart:743-761`). |
| [~] | Results survive restarts and retries | The completion doc and the reward update are separate writes with no reconciliation between them. |
| [~] | Tests cover verification and reward branches | Only pure helpers are tested. `awardCompletionRewards`, `createCompletion` + reward, and `deleteAccount` have no tests, which is how D-01 got through. |

### E. Journal & adventure memories
| Status | Requirement | Evidence / notes |
|---|---|---|
| [~] | Completions create journal entries | Fire-and-forget with errors swallowed (`camera_providers.dart:679,829`). Nothing recreates a missing entry (D-13). |
| [x] | Photos linked to the right entry | `memoryId == completion.id`, sharing the same `photoUrl` (STATIC). |
| [?] | Entries persist across sessions | Not tested live. |
| [~] | Correct date, challenge and location | Location is saved even when "Store Location Data" is switched off (D-09). `xpEarned` shows the challenge's XP value, not what was actually awarded. |
| [x] | Entries belong to the right user | `users/{uid}/memories`, readable and writable by the owner only (STATIC rules). |
| [~] | Realtime updates & pagination | Merge logic is tested (5 tests). Not tested live. |
| [?] | Helpful empty state | Not checked visually. |
| [x] | Missing images don't crash | Every `CachedNetworkImage` has an `errorWidget` (6/6 files). |
| [x] | No duplicate memories | Same ID as the completion, plus an existence check. |
| [~] | Permissions | Owner-only, but the memory's `userId` and `photoUrl` fields aren't validated against the owner. |
| [~] | Edit and delete handle related data | Captions can be edited. Memories can only be deleted through account deletion, which fails. |

### F. Home & visual design
| Status | Requirement | Evidence / notes |
|---|---|---|
| [?] | Consistent in light and dark modes | Not checked visually. |
| [~] | Readable near-black / near-white text | I couldn't check this visually. In code, text colors are chosen per screen in 77 `isDark ?` branches. |
| [~] | Theme tokens used consistently | **73 raw `Color(0x…)` literals** across `lib/features`, and only **1** use of `colorScheme`. |
| [?] | Detailed background that stays readable | Not checked visually. |
| [?] | Companion above the progress bar | Claimed fixed (A12). Not checked visually. |
| [?] | Lily-pad trail size and node states | Not checked visually. |
| [?] | Challenge card hierarchy | Not checked visually. |
| [?] | Responsive layouts, no overflow | `responsive.dart` exists. No widget or golden tests at different widths. |
| [?] | Performance and repaints | Not measured. |
| [~] | Loading, error and empty states | Shared widgets exist (`loading_widgets.dart`, `error_retry_view.dart`, `empty_state.dart`). Not checked visually. |

### G. Companion
| Status | Requirement | Evidence / notes |
|---|---|---|
| [x] | Tapping triggers a response | `home_screen.dart:1847-1864`. |
| [x] | Variety on repeated taps; previous message avoided | `nextCompanionMessage`, 6 tests. |
| [~] | Messages match context | The only context used is `streak >= 3`. Time of day, today's challenge and completion state are ignored. |
| [x] | Distinct personality per companion | 4 companions with separate pools (`companion.dart`). The pools are small: 3–5 messages each. |
| [~] | Mood and animation match the message | Every tap plays `cheer`, whatever the message says. |
| [?] | Speech bubble readability and overflow | Not checked visually. |
| [x] | Haptics degrade gracefully | `HapticFeedback` is a no-op where unsupported; the call is `unawaited`. |
| [x] | Rapid taps handled | 400 ms cooldown; the timer is cancelled. |
| [~] | Accessible | Has a `Semantics` label and button role. Not tested with a screen reader. |

### H. Weather & tips
| Status | Requirement | Evidence / notes |
|---|---|---|
| [~] | Weather icon opens a useful view | It opens an `AlertDialog` with a single line of text (`home_screen.dart:1714`). |
| [x] | Comes from the intended source | Open-Meteo, no key needed (`weather_service.dart`). |
| [~] | Temperature units correct | The C→F conversion is correct and tested. **The UI is hard-coded to °F with no setting**, while challenge generation uses °C. |
| [x] | Condition codes map correctly | WMO codes are mapped and tested (18 tests). |
| [~] | Advice covers cold, heat, rain, storms, snow, wind, fog | Wind isn't covered (not even fetched). Freezing rain and freezing drizzle get ordinary rain advice. |
| [x] | Advice matches the data | Pure function with tests. |
| [x] | Advice isn't generic | 11 branches. |
| [x] | Conflicting conditions follow a tested priority | Order is storm > snow showers > showers > snow > rain > drizzle > fog > heat/cold. Tested. |
| [~] | Missing location, denied permission, API failure handled | Returns `null` and shows an "unavailable" message. **Location permission is requested before the primer is shown** (D-14). |
| [~] | Doesn't encourage unsafe activity | Storms say "Stay safe". Extreme heat or cold only says "stay hydrated" or "dress warmly". |
| [x] | Automated coverage of boundaries | `weather_model_test.dart`, 18 tests. |

### I. XP, levels, achievements, streaks
| Status | Requirement | Evidence / notes |
|---|---|---|
| [ ] | XP totals correct | Fails because of D-01. |
| [x] | Level formula | `floor(xp/100)+1`, tested in Dart, in the rules and in the Functions code. |
| [~] | Streaks follow local-day rules | `resolveStreakOutcome` is DST-safe and tested, but D-01 breaks its input. The Cloud Function uses UTC days (D-15). |
| [~] | Timezone changes and day boundaries | Local-date doc IDs. A change of device timezone shifts the day. |
| [~] | Longest streak and completion count | Correct logic, wrong input (D-01). |
| [~] | Achievements unlock only when earned | Correct logic, but a client can add any achievement ID directly (EMULATOR). |
| [x] | Unearned badges greyed out | `ColorFiltered` (`achievements_screen.dart:585`). Not checked visually. |
| [?] | Category colors for earned badges | Not checked visually. |
| [?] | Badges in light and dark | Not checked visually. |
| [x] | League assignment rules | `LeagueDef.idForXp`, mirrored in the rules and Functions, tested. |
| [ ] | Client writes can't bypass reward validation | FAIL (EMULATOR, D-02). |
| [~] | Edge cases and duplicates tested | The pure streak logic is tested. The repository path is not. |

### J. Leagues & leaderboard
| Status | Requirement | Evidence / notes |
|---|---|---|
| [x] | All leagues defined | 8 leagues (`league_definition.dart`). |
| [x] | Correct emoji per league | STATIC. |
| [~] | Locked leagues show their own greyed emoji | 0.4 opacity on the league's own content (`leaderboard_screen.dart:317`). Not checked visually. |
| [x] | Distinct static background per league | `league_background.dart`, a static painter. |
| [?] | Backgrounds keep contrast | Not checked visually. |
| [ ] | Leaderboard data correct | **Ranks by `weeklyXp` values left over from previous weeks** (reset happens only on a user's next completion), and **any user can set their own value** (EMULATOR) (D-02, D-12). |
| [?] | Reachable from the expected navigation | The Leaderboard tab exists. Not checked visually. |
| [?] | Locked and unlocked states understandable | Semantics include ", locked". Not checked visually. |
| [x] | No unnecessary private data | The mirror holds name, username, photo and stats only. No email. |
| [?] | Layout across widths | Not tested. |

### K. Navigation
| Status | Requirement | Evidence / notes |
|---|---|---|
| [x] | Main screens reachable | 5-tab `StatefulShellRoute`, plus camera, challenge detail, settings, streak and companion. |
| [?] | Back navigation | Not tested live. |
| [x] | Auth redirects | `app_router.dart:267`. |
| [?] | Journal / Profile / Leaderboard / Home coherent | The Journal is a tab inside Map plus a Home shortcut (A25). Not checked visually. |
| [~] | No dead controls | `AiFeatureLockedCard` and `challengeVerificationServiceProvider` are unused. No inert buttons found. |
| [~] | Deep links and refresh | Probably broken: on web the redirect runs before auth state loads, so a refresh on `/profile` lands on `/home` (STATIC, plausible). `/challenge/:id` relies on `state.extra`, which is lost on refresh. |
| [?] | Loading and error transitions | Not tested. |

### L. Notifications & realtime
| Status | Requirement | Evidence / notes |
|---|---|---|
| [ ] | Firebase config matches each platform | Android and iOS mismatches (D-08). |
| [~] | Push configured | Mobile subscribes to topics and syncs the token. Nothing server-side sends messages. |
| [ ] | Web VAPID key | Not configured (B4, external). |
| [~] | Permission requested at a sensible time | Notifications are primed in AppShell, but location is requested before its primer (D-14). |
| [?] | Foreground and background behavior | Not tested. |
| [~] | Tapping a notification navigates | The payload's `route` is passed to `context.go` without validation (`app_shell.dart:91`). Low risk because only the server sends payloads. |
| [x] | Realtime listeners, no polling | Firestore `snapshots()` streams. Weather polls every 30 min, which is intended. |
| [x] | Listeners disposed | `ref.onDispose` / `dispose` cancel them (STATIC). |
| [?] | Offline and reconnect consistency | Web persistence is enabled. Not tested. |
| [x] | Notification failures don't break the app | Errors swallowed and logged (`notification_service.dart`). |

### M. Firebase, backend & data integrity
| Status | Requirement | Evidence / notes |
|---|---|---|
| [~] | Firestore rules reviewed | Isolation is good. Integrity has gaps (D-02, D-03, D-07). |
| [ ] | Storage rules: ownership, size, type | Don't compile (D-05). |
| [x] | Default deny | Both rule files end in a catch-all deny. |
| [ ] | Client-writable fields constrained | `settings.*`, `createdAt`, `uid`, `achievements` and the whole leaderboard mirror are unconstrained (EMULATOR). |
| [~] | Entitlements, AI usage and rewards protected | Tier and usage counters are protected (EMULATOR). Rewards are not. |
| [x] | Functions authenticate callers and validate input | `index.ts:117-132`, 49 tests. |
| [x] | Ownership check resists UID-prefix collisions | `isOwnedStoragePath` checks the trailing slash, and it's tested. |
| [~] | Idempotent under retries | Completion IDs are deterministic. The function reads the existing completion outside its transaction, and the quota update isn't atomic. |
| [ ] | Rate limits and quotas effective | Rerolls are unlimited and each one calls Gemini from the client (D-06). |
| [x] | Errors don't leak internals (server) | `HttpsError` messages are generic. **The client UI does leak raw errors** (`diagnosticFailureMessage`). |
| [ ] | Production secrets managed properly | The Gemini key is in the live web bundle (D-06). The Functions code correctly uses `defineSecret`. |
| [ ] | App Check | Not integrated anywhere. |
| [x] | Indexes match queries | The completions and leaderboard composite indexes exist. The leaderboard query doesn't use its index (D-12). |
| [~] | No sensitive data in logs | `debugPrint` of errors only. The UI shows raw error text. |

### N. Accessibility
| Status | Requirement | Evidence / notes |
|---|---|---|
| [~] | Semantic labels | Present on many custom controls. Not audited exhaustively. |
| [?] | Keyboard navigation on web | Not tested. |
| [?] | Screen reader | Not tested on a real device. |
| [?] | WCAG 2.2 AA contrast | Not measured. |
| [~] | Text resizing | App and system scale are combined (`main.dart:165`). Not tested at 200%. |
| [~] | Touch targets | A 48 px minimum is used in several places. Not audited exhaustively. |
| [x] | Reduced motion | System and app settings are combined, used in 16 files, and tested. |
| [?] | Color isn't the only status signal | Not checked visually. Locked leagues have a text hint. |
| [~] | Forms show errors and manage focus | Validators exist on the login form. Focus handling not tested. |
| [?] | Loading and success announced | No `SemanticsService.announce` found. Not tested. |

### O. Performance & reliability
| Status | Requirement | Evidence / notes |
|---|---|---|
| [x] | No obvious synchronous blocking | JPEG compression runs in `compute()`. |
| [~] | Images sized and cached | Uses `cached_network_image`. Map markers decode full images. |
| [~] | Lazy lists and pagination | The Journal paginates. **The leaderboard reads the entire league on every snapshot** (D-12). |
| [?] | Painter repaints | Not measured. |
| [x] | No leaked subscriptions | Disposal is handled (STATIC). |
| [~] | Intermittent network | Offline pre-checks and web persistence exist. Not tested. |
| [~] | Slow-upload progress | Staged messages, no percentage. |
| [?] | Narrow / medium / wide widths | Not tested. |
| [?] | Startup | Not measured. |
| [~] | Error logging is private | Crashlytics is user-ID only. The UI shows raw errors. |

### P. SEO & web
| Status | Requirement | Evidence / notes |
|---|---|---|
| [~] | Production domain verified | `.firebaserc` has targets `main` → site `touchgrass` and `today` → site `touchgrass-today`, both in project `touchgrass-today`. Not checked live. |
| [~] | Title, description, favicon, social metadata | The title and description are set. **There are no Open Graph or Twitter tags, and the favicon and PWA icons are byte-for-byte Flutter's defaults.** |
| [?] | HTTPS | Firebase Hosting provides it by default. Not checked live. |
| [ ] | Robots and sitemap | Neither exists. |
| [ ] | Canonical URL with two domains | Both sites serve the same build with no canonical tag and no redirect. |
| [x] | Rewrites and SPA fallback | `** → /index.html` for both targets. |
| [~] | Refresh and deep links | See K. |
| [ ] | Public marketing content indexable | The site is a canvas-rendered Flutter app with no static landing content. |
| [x] | No private content in SEO metadata | Correct. |
| [ ] | Analytics consent | Firebase Analytics (GA4 `measurementId`) starts with no consent step. |
| (cache) | Stale-asset risk | `firebase.json` sets no `Cache-Control` headers for `index.html`, `flutter_bootstrap.js` or `flutter_service_worker.js`. |

### Q. Monetization & privacy
| Status | Requirement | Evidence / notes |
|---|---|---|
| [x] | Monetization integrations identified | None. There are no ad SDKs and no payment provider. The entitlement tiers exist, but nothing ever grants one. |
| [-] | No nonfunctional ads | There are no ads. |
| [-] | Ad policy compatibility | N/A. |
| [ ] | Privacy disclosures match collection | The in-app policy (`settings_screen.dart:983-986`) leaves out email, Analytics, Crashlytics, Performance, the FCM token, **photos sent to Google Gemini**, and **location sent to Open-Meteo and geocoding**. It also says location is only used on completion, but it's actually requested every time Home loads. |
| [ ] | Privacy policy and contact available | The in-app dialog only. `https://touchgrass.app/privacy` is not hosted. Whether `support@touchgrass.app` works is not verified. |
| [ ] | Third-party SDKs disclosed | See above. |
| [ ] | Consent evaluated | No consent flow exists. |
| [ ] | Deletion and retention match the policy | Account deletion fails (D-04). |
| [~] | No sensitive data sent to unnecessary third parties | Location goes to Open-Meteo even with "Store Location Data" turned off (D-09). |

### R. Store & platform release
| Status | Requirement | Evidence / notes |
|---|---|---|
| [ ] | Android app ID matches the Firebase registration | `com.touchgrass.app` vs `com.example.touchgrass`. |
| [ ] | iOS bundle ID matches the Firebase registration | `com.touchgrass.app` vs `com.example.touchgrass`, and there is no plist. |
| [ ] | Platform config files valid and in place | iOS config file missing. |
| [ ] | Release signing secure | Release silently falls back to the debug keystore (`build.gradle.kts:59-62`). |
| [~] | Debug-only behavior off in production | Crashlytics is gated by `kDebugMode`. `diagnosticFailureMessage` is marked "TEMPORARY" but ships. |
| [ ] | Production AI can't silently use an insecure fallback | The guard isn't wired up (D-10). |
| [ ] | Web release contains no privileged secrets | The Gemini key is in the deployed bundle (D-06). |
| [~] | Permissions and disclosures accurate | The manifest and plist strings are fine. The privacy disclosures are not. |
| [ ] | Store screenshots, icons, listing | Icons are Flutter's defaults. `assets/icon/` is empty. There are no screenshots. `STORE_LISTING.md` is a draft. |
| [ ] | Play Data Safety and Apple privacy labels | Not done (B8). |
| [~] | External configuration documented | KNOWN_BUGS, RELEASE_GUIDE and functions/README are thorough. Some claims are out of date (see §4). |
| [x] | Store blockers separated from code defects | See §4 and §9. |

---

## 3. Defects

Severity is based on user impact and exploitability. "EMULATOR" means I reproduced it against the repo's rules in the local emulator.

### D-01 — No XP or streak on the sign-up day, or on any day the user explicitly signs in · **Critical (journey-breaking)**
- **Root cause:** one field, `lastActiveDate`, is used for two things: the last sign-in time and the day of the last completion.
  - `UserModel.initial` sets it to "now" (`user_model.dart:132`).
  - `_resolveUser` sets it to the server time on every explicit sign-in (`user_repository.dart:596-601`).
  - `awardCompletionRewards` then sees `lastActive == today`, treats the day as already completed, and awards 0 XP, keeps the streak unchanged, and doesn't count the completion (`user_repository.dart:186-190`).
  - The Cloud Function copies the same logic (`functions/src/index.ts:263-268`).
- **Impact:** a brand-new user finishes their first challenge and gets **+0 XP, streak 0, completions 0, and no first-completion achievement**. Meanwhile the Journal and challenge detail screens say "+25 XP". A returning user who signs in explicitly loses that day's reward. This hits the most important retention moment in the app.
- **Repro:** register → complete today's challenge → the success screen counts up to 0 XP → Profile shows XP 0 and streak 0.
- **Fix:**
  - Add a dedicated `lastCompletionDate` field, written only by the reward path. Keep `lastActiveDate` as activity-only.
  - Migration for existing docs: if `lastCompletionDate` is missing, use the date of the user's most recent completion (one indexed query) or epoch if there are none.
  - Mirror the change in `rewards.ts`, `progression_model.dart:91` and the rules.
- **Acceptance:** a fresh account's first completion awards the challenge's XP with streak = 1. Signing in again the same day doesn't block that day's award. A second completion on the same day awards 0.
- **Regression risk:** medium. Touches streak logic and the rules' reward bounds. Needs repository tests with a fake Firestore.

### D-02 — Rewards and leaderboard can be forged directly through the client SDK · **High (integrity)** · EMULATOR
All of the following were **ALLOWED** by the current rules:
- A new account creating its own profile with xp = 5,000,000 and league = aurora.
- Three consecutive +4000 XP updates (the per-write cap doesn't limit the number of writes).
- `settings.streakFreezesOwned = 999`.
- Rewriting `createdAt`.
- Adding arbitrary achievement IDs.
- **Writing `leaderboard_public/{uid}` with xp and weeklyXp = 99,999,999** (that collection has no bounds at all).
- Creating a completion with a fabricated AI verdict for any challenge ID.
- Setting a challenge's `xpReward` to 100,000. The Cloud Function trusts this value once it's live.

**Fix:**
- Mirror rule: every mirror field must equal the corresponding field in `get(/users/$(uid))`.
- Create rule: initial stats must be zero/defaults and `createdAt == request.time`.
- Make `uid` and `createdAt` immutable.
- Bound `settings.streakFreezesOwned` to its legitimate transitions.
- Long term, only the server-authoritative cutover (P1-6) closes the "farm repeated writes" class completely.
- **Residual risk (stated plainly):** without a trusted backend, per-write bounds can only slow forgery down, not stop it.

### D-03 — Any user can take over another user's username · **High** · EMULATOR
`usernames/{name}` uses `allow write`, which also covers updates, and checks only the new owner. Mallory successfully overwrote `usernames/alice_name` with her own UID.
**Fix:** split the rule into `create` (doc must not already exist), `update: if false`, and `delete` (owner only).

### D-04 — Account deletion always fails · **High (store blocker: Apple 5.1.1(v), Google Play)** · EMULATOR
- **What happens:**
  - Deleting `completions/*` is denied, so a user with any completions fails at step 2.
  - Deleting `users/{uid}` is denied, so a user with no completions fails at step 7. By then their challenges, memories, leaderboard mirror and username have already been deleted, leaving the account half-deleted.
  - Storage deletes are denied, because `request.resource` is null on a delete and the rules read `request.resource.size`.
- **Fix:** see P0-2.

### D-05 — `storage.rules` doesn't compile · **High** · EMULATOR
- **Cause:** `match /user_avatars/{userId}.png` is invalid syntax, because a wildcard must be a whole path segment. Errors at lines 8 and 35.
- **Effect:** the file can't be deployed, so **whatever Storage rules are live today are unknown.** They could be wide open or locked down.
- **Fix:** `match /user_avatars/{fileName}` with `fileName == request.auth.uid + '.png'`; explicit `delete` rules; an allow-list of image types (jpeg, png, webp, heic).
- **External:** check the live rules in the Firebase Console before deploying anything.

### D-06 — Gemini API key is in the web bundle; generation isn't rate-limited · **High (cost/abuse)**
- `build/web/main.dart.js` (built 2026-08-13) contains the `secrets.json` key: `includes(key) == true`. KNOWN_BUGS B2 records deploying a build made with `--dart-define-from-file=secrets.json`.
- The key powers challenge generation for **all** users, not just entitled ones. Rerolls are unlimited, and each one makes up to 2 Gemini calls.
- **Fix:**
  - Rotate the key (external) and restrict it.
  - Stop passing the key to web builds.
  - Use seed-only generation (Tier 3) on the client until generation moves server-side.
  - Cap rerolls.

### D-07 — Granting a user `premium` or `admin_test` breaks all their profile writes · **High (latent)** · EMULATOR
- **Cause:** `isValidUserWrite()` checks `hasOnly()` against the whole resulting document, and `entitlementTier` isn't in the allowed list. So once a tier is set on the server, every client update for that user is denied: the FCM token, rewards and settings.
- **Fix:** add `entitlementTier` to the allowed keys, but require it to be unchanged using `diff().affectedKeys()`.

### D-08 — Mobile platform configuration · **High (store blocker)**
- **Android:** `google-services.json` lists package `com.example.touchgrass` but the app builds as `com.touchgrass.app` (build confirmed failing: see §6). Release builds sign with the debug key when `key.properties` is missing.
- **iOS:**
  - No `GoogleService-Info.plist`.
  - `firebase_options.dart` has `iosBundleId: com.example.touchgrass`.
  - No `CFBundleURLTypes` entry for Google Sign-In.
  - No Sign in with Apple entitlement.
- **Mostly external:** register the apps and download the config files. **Code:** make release signing fail closed.

### D-09 — The "Store Location Data" toggle is ignored, and the privacy text is inaccurate · **High (privacy)**
- `settings.locationEnabled` is written to the profile but never read (STATIC: it only appears in `settings_screen.dart:336,342`).
- Coordinates are still attached to completions and memories, and still sent to Open-Meteo and the geocoder.
- The in-app privacy text leaves out several data flows (see Q).

### D-10 — The production "fail-closed" guard isn't actually connected · **Medium**
- `CameraNotifier` uses `GeminiService` directly. `challengeVerificationServiceProvider` and `RemoteVerificationService` are never consumed.
- In a build with `ENVIRONMENT=production`, everyone is on the free tier, so every completion is approved on the honor system. "Submit Anyway" is always available.
- This matches the confirmed product decision (A5), but the documentation claims a production guarantee that the code doesn't provide.

### D-11 — Today's challenge goes stale after midnight while the app is open · **Medium**
- **Cause:** `todaysChallengeProvider` fixes `todayDocId()` when it first subscribes (`challenge_providers.dart:19-23`, `challenge_repository.dart:38-39`). The midnight tick rebuilds the path, but the provider keeps listening to yesterday's document.
- **Effect:** after midnight, "today" shows yesterday's challenge, and completing it writes against yesterday's ID.
- **Fix:** have the provider watch the calendar-date provider.

### D-12 — The weekly leaderboard uses stale weekly XP and reads the whole league · **Medium**
- `weeklyXp` only resets on the user's next completion, so last week's totals keep ranking.
- The query is equality-only, then sorts and takes the top N on the client (`leaderboard_providers.dart`), so the existing `(currentLeague, weeklyXp desc)` index goes unused.
- **Fix:** store a `weekKey`, filter on it, and use `orderBy(weeklyXp desc).limit(N)` (after D-02).

### D-13 — A Journal entry can be lost silently, and its XP figure can be wrong · **Medium**
Memory creation is fire-and-forget and its errors are swallowed, so nothing ever recreates a missing entry. `xpEarned` is the challenge's XP value, not what was actually awarded. Same family as the success-screen mismatch.

### D-14 — Location prompt fires before its primer · **Medium**
`weatherProvider` (Home) and `assignmentInitProvider` call `LocationService.getCurrentLocation()`, which calls `requestPermission()` immediately. That races the AppShell primer, so A22 ("primer before every native prompt") is only partly true.

### D-15 — Latent defects in the Cloud Function · **Medium (undeployed)**
- Streak days are computed in UTC, while the client uses local days.
- Trusts `challenge.xpReward`, which clients can write (D-02).
- Writes the leaderboard mirror **without checking `profilePublic`**, so users who opted out would reappear.
- The "already completed" response returns the wrong `newXp`, level and streak.
- The quota read and increment aren't atomic.
- The MIME type is hard-coded to `image/jpeg`.
- Expects a `storagePath`, but the client stores download URLs.
- No App Check.
- `npm audit`: 15 vulnerabilities (1 critical, 4 high), mostly transitive through `firebase-admin@12`. The fix is a major upgrade to v14.
- `npm run lint` fails because there's no ESLint config.

### D-16 — Orphaned Storage uploads · **Low/Medium**
The photo is uploaded before the completion is written. Every retry, and every "already completed" outcome, leaves an orphaned file behind.

### D-17 — Day counts are off by one across DST, and `dayNumber` uses the UTC date of `createdAt` · **Low**
- `difference().inDays` between two local midnights comes out one short after a spring-forward (`member_since.dart`, `assignment_providers.dart:270`, `user_providers.dart`).
- `assignment_providers.dart:269` takes the calendar day from `createdAt` while it's still in UTC.

### D-18 — Web: branding, SEO and cache headers · **Medium**
- The favicon and PWA icons are byte-for-byte Flutter's defaults (sizes 917, 5292, 8252, 5594, 20998 bytes; file dates 2025-03-11).
- No Open Graph tags, robots.txt, sitemap or canonical URL.
- No cache headers in `firebase.json`.
- A stale `TODO: Replace YOUR_MAPS_API_KEY` comment remains in `index.html`.
- `README.md` is still the Flutter template.

### D-19 — A fresh clone probably won't build · **Medium (plausible, not reproduced)**
- `pubspec.yaml` declares the asset folder `assets/icon/`. On disk it's empty, and git doesn't track empty folders.
- Flutter normally fails when a declared asset directory is missing.
- `flutter_launcher_icons` points at missing files.

### D-20 — Profile-photo permission denial isn't handled · **Low/Medium**
`ImagePicker().pickImage` isn't wrapped in try/catch and has no primer (`settings_screen.dart:794`).

### D-21 — Hygiene · **Low**
- **Unused dependencies:** `riverpod_annotation`, `riverpod_generator`, `mockito`, `lottie`, `path_provider`, `build_runner`.
- **Dead code:** `AiFeatureLockedCard`, `challengeVerificationServiceProvider` (until the cutover), `UserRepository.awardXp`.
- **Formatting:** 62 of 130 Dart files aren't formatted.
- **Other:**
  - The "temporary" `diagnosticFailureMessage` shows raw errors to users.
  - `analyticsBootstrapProvider` logs the retention event again on every profile-doc change.
  - Uploading an avatar increments `totalPhotosUploaded`.

### D-22 — Weather and companion polish · **Low**
- **Weather:** always °F, no wind or freezing-precipitation handling, weak warnings for extreme heat and cold, a one-line dialog.
- **Companion:** pools are small, the only context used is the streak, and the mood is always `cheer`.

---

## 4. External blockers
| # | Action | Owner | Prerequisite | How to verify |
|---|---|---|---|---|
| X-1 | **Rotate and restrict the Gemini key now.** It's in the live web bundle. | You (Google Cloud / AI Studio) | None | The old key returns 4xx. The new key has API and referrer restrictions. |
| X-2 | Check the **live Storage rules** in the Console. | You | None | Screenshot or export. Compare with the fixed `storage.rules`. |
| X-3 | Add `touchgrass.web.app` to Auth → Authorized domains. | You | None | Google sign-in works on that domain. |
| X-4 | Add `touchgrass.web.app/*` to the Maps key referrers. Also check the iOS Maps key restriction (`AppDelegate.swift:13`). | You | None | Map loads; the key is rejected on other origins. |
| X-5 | Register Android `com.touchgrass.app` and iOS `com.touchgrass.app` in Firebase, download the new config files, add SHA-1/SHA-256 fingerprints, and get the iOS `REVERSED_CLIENT_ID`. | You | Developer accounts | `flutter build apk` gets past `processDebugGoogleServices`. iOS builds on macOS. |
| X-6 | Create the release keystore and `key.properties`, and the iOS signing setup. | You | Developer accounts | A signed `appbundle` or archive. |
| X-7 | Enable Blaze billing and `firebase functions:secrets:set GEMINI_API_KEY` (only if you want the server-authoritative path or deletion via a Cloud Function). | You | Billing decision | `firebase functions:list`. |
| X-8 | Host the privacy policy and terms (e.g. on `touchgrass.web.app/privacy`). Confirm `support@touchgrass.app` works and `touchgrass.app` is owned. | You | Legal text | The URLs return 200. |
| X-9 | Generate the web push VAPID key (optional). | You | None | A token is issued on web. |
| X-10 | Final app icon artwork (1024², plus foreground layer). | You or a designer | None | `dart run flutter_launcher_icons` succeeds. |
| X-11 | Play Data Safety form, Apple privacy labels, store screenshots and listing. | You | Accurate disclosures (P0-8) | Consoles accept them. |

**Documentation that's out of date or wrong:**
- functions/README says "add `cloud_functions` to pubspec"; it's already there.
- KNOWN_BUGS A16 says branding was replaced, but the icons are still defaults.
- A22 says every native prompt is primed; location isn't (D-14).
- The 'FIRESTORE SECURITY' section says no field is more exploitable than B1 describes; the `leaderboard_public` mirror (completely unbounded) and the username takeover show that's not the case.

---

## 5. Security findings
| ID | Finding | Severity | Status | Existing mitigation |
|---|---|---|---|---|
| S-1 | Leaderboard mirror writable with any values | High | **Confirmed (EMULATOR)** | None |
| S-2 | Profile created with arbitrary stats; unlimited +4000 XP per write; arbitrary achievements; streak freezes; `createdAt` | High | **Confirmed (EMULATOR)** | Per-write bounds (A1) |
| S-3 | Username takeover | High | **Confirmed (EMULATOR)** | None |
| S-4 | Gemini key in the web bundle; unlimited Gemini-backed rerolls | High | **Confirmed** (local artifact + KNOWN_BUGS record) | None shown in the repo. Key restrictions unknown. |
| S-5 | Storage rules don't compile; live rules unknown | High | **Confirmed (compile)**; live state UNVERIFIED | Unknown |
| S-6 | Fabricated AI verdict or completion for any challenge ID | Medium | **Confirmed (EMULATOR)** | Honor system is the intended product behavior (A5) |
| S-7 | Client-writable `xpReward` trusted by the Cloud Function | Medium (latent) | Confirmed (EMULATOR + STATIC) | The function isn't deployed |
| S-8 | SVG accepted as an "image" upload | Low | Confirmed (EMULATOR) | Served from the Storage origin |
| S-9 | Raw error text shown in the UI | Low | STATIC | None |
| S-10 | Notification `route` not validated | Low | STATIC | Only the server sends payloads |
| S-11 | No App Check | Medium (abuse) | STATIC | None |
| S-12 | `firebase-admin` dependency chain: 1 critical, 4 high | Medium (functions undeployed) | Confirmed (`npm audit`) | Not deployed |
| S-13 | Flutter dependencies: 150 packages behind; `build_resolvers` and `build_runner_core` discontinued (dev only) | Info | `flutter pub outdated` | — |

**Verified safe (EMULATOR):**
- Reading another user's private profile or completions is denied.
- A client can't grant itself `entitlementTier` or write `aiUsage`.
- Reading another user's completion photos is denied (tested on a scratch copy with only the invalid avatar block removed).

**Secret scan:**
- The Gemini key is not in any tracked file or anywhere in git history.
- The tracked files contain 4 distinct `AIza…` keys: the Firebase client config keys (public identifiers) and the Maps keys in `index.html` and `AppDelegate.swift`, which are public by design but need restrictions (X-4).

---

## 6. Test & build results (run in this session)
| Command | Exit | Result | Time |
|---|---|---|---|
| `flutter --version` | 0 | Flutter 3.44.1 stable, Dart 3.12.1 | — |
| `flutter pub get --enforce-lockfile` | 0 | Resolved; lockfile unchanged | 44 s |
| `flutter analyze` | 0 | **No issues found** | 104 s |
| `flutter test --reporter expanded` | 0 | **235 passed, 0 failed, 0 skipped** | 88 s |
| `dart format --output=none --set-exit-if-changed lib test` | 1 | **62 of 130 files would be reformatted** (no files written) | 6 s |
| `flutter pub outdated` | 0 | 150 packages have newer versions outside the constraints; 2 dev packages discontinued | 18 s |
| `flutter build web --release --output <scratchpad>` | 0 | **Built.** Size 4.6 MB `main.dart.js`; no Gemini key, since no secrets were passed | 302 s |
| `flutter build apk --debug` | 1 | **FAILED:** `No matching client found for package name 'com.touchgrass.app' in android/app/google-services.json` (D-08 / X-5). Kotlin compilation was never reached. | 395 s |
| `npx tsc --noEmit -p functions` | 0 | Type-check clean | — |
| `npm test` (functions) | 0 | **49 passed, 0 failed** (11 suites) | 10 s |
| `npx eslint src --ext .ts` (functions) | 2 | **No ESLint config**, so `npm run lint` is broken | — |
| `npm audit --omit=dev` (functions) | 1 | 15 vulnerabilities: 1 critical, 4 high, 10 moderate | — |
| Emulator rules probe (`firebase emulators:exec`, project `demo-touchgrass-audit`, JBR 25) | 0 | 22 probes, results in §3 and §5. `storage.rules` failed to compile at lines 8 and 35. | — |
| Secret scan (`git grep`, `git log -S`) | 0 | See §5 | — |
| iOS build | — | **Not possible** (Windows, no Xcode) | — |

**Environment limits:**
- No physical devices and no browser automation, so no visual, accessibility, camera, push or live-site checks were done.
- System Java is 17, so the emulator ran on Android Studio's bundled JBR 25.
- No production access was used at any point.

**Test-suite gaps:**
- 27 of the 28 test files are pure-logic unit tests; 1 widget test file (`permission_primer_test.dart`).
- No integration tests, no rules tests, no repository tests against a fake Firestore.
- So none of the defects in §3 could have been caught by the current suite.

---

## 7. User-journey assessment
| Stage | Status | Notes |
|---|---|---|
| 1–2 Discover / understand | ⚠️ | Default Flutter icon and favicon, no social preview, nothing for search engines to index. Onboarding exists. |
| 3 Register / sign in | ⚠️ | Google sign-in fails on `touchgrass.web.app` until X-3 is done. Apple sign-in is hidden on web. |
| 4–7 Home, companion, progress, challenge | ✅ / ⚠️ | Works by code trace. The location prompt fires before its explanation (D-14). Stale challenge after midnight (D-11). |
| 8 Weather | ⚠️ | A one-line °F dialog. |
| 9–11 Photo, upload, verification | ⚠️ | Works on the honor system. Each retry leaves an orphaned upload. |
| **11–13 XP, Journal, progress** | ❌ | **The first-day reward is lost (D-01).** Success screen and Journal disagree. A Journal entry can go missing silently. |
| 14 Next day | ⚠️ | Correct after an app restart. Stale if the app stays open overnight. |
| 15 Profile and settings | ⚠️ | The location toggle does nothing (D-09). Photo-permission denial is silent. |
| 16 Error recovery | ⚠️ | Messages are friendly but sometimes include raw error text. |
| **17 Sign out / delete account** | ❌ | Sign-out works by code trace. **Deletion fails (D-04).** |

**Highest-leverage improvements for satisfaction and retention, in order:**
1. Fix the first-day reward (D-01).
2. Make the success screen and Journal always agree, and never lose a Journal entry (D-13).
3. Fix the stale challenge after midnight (D-11).
4. Make the leaderboard trustworthy and actually weekly (D-02, D-12).
5. Add a real icon and brand identity.

---

## 8. Implementation plan

Field order for each task:
1. Defect
2. Files
3. Approach
4. Dependencies
5. Security
6. Automated tests
7. Manual QA
8. Acceptance
9. Regression risk
10. Rollback
11. Complexity

### P0 — Critical

**P0-0 · Rules test harness (enables the rest of P0).**
1. No automated rules coverage.
2. New `firestore-tests/` package (`@firebase/rules-unit-testing`, dev-only Node), mirroring this audit's 22 probes plus deletion and mirror cases. One npm script.
3. Run with `firebase emulators:exec --project demo-…`.
4. Needs JDK 21+; the README will document using Android Studio's JBR.
5. No production access; demo project only.
6. Every P0 rules change gets an allow test and a deny test.
7. None.
8. `npm test` runs every case and they pass against the fixed rules.
9. None to the app.
10. Delete the folder.
11. Small.

**P0-1 · First-day / sign-in XP loss (D-01).**
1. D-01.
2. `user_model.dart`, `user_repository.dart`, `progression_model.dart`, `firestore.rules` (allow `lastCompletionDate`), `functions/src/rewards.ts` + `index.ts`, tests.
3. Add `lastCompletionDate`, written only by the reward path. Keep refreshing `lastActiveDate` on sign-in. Legacy fallback as described in D-01. Add `fake_cloud_firestore` as a dev dependency to test `awardCompletionRewards` (**new dev dependency — needs your approval**).
4. Needs P0-0.
5. No weakening. Only one new allowed field.
6. Repository tests: new user's first completion, same-day second completion, sign-in then complete, the yesterday → +1 streak path, and legacy docs without the field.
7. Register a new account on web, complete a challenge, check XP, streak and Journal.
8. As stated in D-01.
9. Medium, since the streak logic changes.
10. Revert the commit. Old docs still work because the code falls back to the old field.
11. Medium.

**P0-2 · Account deletion (D-04).**
1. D-04.
2. `user_repository.dart`, `storage_service.dart`, `firestore.rules`, `storage.rules`, tests.
3. Two options; Option B is recommended if you enable Blaze (X-7), otherwise A:
   - **Option A (no Blaze):**
     - Allow `delete` on `users/{uid}` for the owner.
     - Allow `delete` on `completions/{id}` where `resource.data.userId == auth.uid`. ⚠️ This loosens a rule: it lets users delete their own completions. That doesn't create a double-XP path once P0-1 lands, because the gate becomes `lastCompletionDate`, not completion existence.
     - Add explicit Storage `delete` rules.
     - Reorder the cascade so it can be retried: Storage → subcollections → mirror and username → completions → user doc → Auth. Re-authenticate first.
     - Treat "not found" as success.
   - **Option B (Blaze):** a `deleteAccount` callable using the Admin SDK, plus Auth deletion. The client keeps no delete permissions.
4. Needs P0-0 and P0-3. Option B also needs X-7.
5. A is a deliberate, narrow loosening that you'd need to approve explicitly. B keeps the rules strict.
6. Emulator tests: the owner can delete their own data; a non-owner cannot.
7. Delete an email account and a Google account on web. Check Firestore and Storage are empty afterwards.
8. Every user-owned document and file is removed, the Auth user is gone, and the username can be claimed again.
9. Medium.
10. Revert the rules and code.
11. Medium.

**P0-3 · Make `storage.rules` valid and correct (D-05, S-8).**
1. D-05, S-8.
2. `storage.rules`.
3. Use a filename wildcard plus equality check, explicit `delete` rules, and a content-type allow-list (jpeg, png, webp, heic, heif).
4. **X-2 first:** see what's live before replacing it.
5. Tightens the rules.
6. Storage emulator tests for owner, other users, size, type and delete.
7. Upload an avatar and a completion photo on web.
8. The rules compile, all tests pass, and uploads still work.
9. Medium: if the live rules are permissive today, tightening could expose client paths that depend on that.
10. Redeploy the previous rules, exported in X-2.
11. Small.

**P0-4 · Username takeover (D-03).**
1. D-03.
2. `firestore.rules`.
3. Separate `create` (`!exists`), `update: if false`, and owner-only `delete`.
4. Needs P0-0.
5. Tightens the rules.
6. Takeover denied; claim, change and release still allowed.
7. Change your username in Settings.
8. The takeover probe is DENIED.
9. Low. `_claimUsername` uses `tx.set`; re-setting your own claim becomes an update, so the transaction must skip the write when the claim already exists and is yours.
10. Revert the rules.
11. Small.

**P0-5 · Gemini key exposure and reroll cost (D-06).**
1. D-06.
2. `challenge_generation_service.dart`, `assignment_service.dart`, `todays_challenge_card.dart`, `app_constants.dart`, `DOCUMENTATION.md` / `RELEASE_GUIDE.md` build commands.
3. On web, and wherever no server path exists, use seed-only (Tier 3) generation. Cap rerolls (for example 3 a day) on the client and in the rules (`rerollCount` ≤ N). Stop using `--dart-define-from-file=secrets.json` for web release builds.
4. X-1 (rotation) is independent and should happen immediately.
5. Removes the secret from the client.
6. Unit tests for the reroll cap and the seed-only path.
7. Reroll on web and confirm the cap message.
8. The new build doesn't contain the key (scripted check), and rerolls are capped.
9. Low/medium: challenges become less varied until generation moves server-side.
10. Revert.
11. Small/medium.

**P0-6 · Reward and mirror integrity (D-02).**
1. D-02.
2. `firestore.rules`.
3. Each mirror field must equal its value in `get(users/uid)`; this needs `_syncPublicMirror` to run after the user write, which it already does. Create rule pins initial stats. `uid` and `createdAt` immutable. Bound `settings.streakFreezesOwned` to `{same, −1, +1 with XP cost, +1/+2 at milestones}`. Leave the +4000 cap and document the residual risk.
4. Needs P0-0 and P0-1.
5. Tightens the rules.
6. One emulator case for each ALLOWED probe in §3, now DENIED, plus the legitimate award, buy-freeze, photo and username paths still ALLOWED.
7. Complete a challenge, buy a freeze, toggle leaderboard visibility.
8. All forged writes denied, all legitimate flows pass.
9. **Medium/high**: the A1 history shows rules regressions here can break completion entirely. Test before deploying.
10. Redeploy the previous rules.
11. Medium.

**P0-7 · Entitlement grant breaks writes (D-07).**
1. D-07.
2. `firestore.rules`.
3. Allow the key but forbid changing it.
4. Needs P0-0.
5. Tightens and fixes.
6. Premium user can update the FCM token and receive rewards; self-grant still denied.
7. None.
8. Both premium probes ALLOWED, the self-grant probe DENIED.
9. Low.
10. Revert.
11. Small.

**P0-8 · Location toggle and accurate privacy disclosures (D-09).**
1. D-09.
2. `camera_providers.dart`, `weather_providers.dart`, `assignment_service.dart`, `settings_screen.dart` (privacy text), a new `web/privacy.html` (optional, linked in-app).
3. Read `settings.locationEnabled` before any location read. When it's off: no coordinates stored, no weather by GPS, a "Location off" chip. Rewrite the policy to list every data flow.
4. None.
5. Better privacy.
6. Unit test that the location helper respects the toggle.
7. Toggle off → complete → the memory has no coordinates.
8. No coordinates are written when the toggle is off, and the policy lists every SDK and data flow.
9. Low.
10. Revert.
11. Small/medium.

### P1 — High
| ID | Defect | Approach (summary) | Depends on | Tests | Acceptance | Risk / Rollback | Size |
|---|---|---|---|---|---|---|---|
| P1-1 | D-08 mobile config | Drop in the new `google-services.json` / `GoogleService-Info.plist`; run `flutterfire configure`; add the URL scheme and the Apple Sign-In entitlement | X-5 | Build smoke test | Debug and release builds succeed; Google and Apple sign-in work on devices | Low; revert the config files | M |
| P1-2 | Release signing falls back to debug | Make Gradle fail the release build when `key.properties` is missing (allow an explicit opt-in for local runs) | X-6 | — | A release build without a keystore fails with a clear message | Low | S |
| P1-3 | D-11 stale challenge after midnight | Make the calendar-date provider public and watch it in `todaysChallengeProvider` | — | Provider test with a fake clock | The stream switches doc at midnight | Low | S |
| P1-4 | D-13 / D-16 Journal reliability and orphans | Write the completion and memory in one batch; on Journal load, recreate memories for completions that lack one; set `xpEarned` from the actual reward; delete the uploaded file if the completion write fails | P0-1 | Repository tests | Every completion has a memory with matching XP | Medium; revert | M |
| P1-5 | Misleading success screen after a reward failure | Batch the completion and reward update atomically; on failure show "saved, rewards pending" and retry | P0-1, P0-6 | Notifier tests | The UI never claims XP that wasn't written | Medium | M |
| P1-6 | Server-authoritative verification and rewards (D-10, D-15) | Fix the function's latent bugs (local day via a client-sent UTC offset, checked server-side; server-side reward table; respect `profilePublic`; return values; transactional quota; MIME sniffing; storage path); add App Check; upgrade `firebase-admin` (**major version, needs approval**); ESLint config; move the caption before verification (**UX decision**); wire `challengeVerificationServiceProvider` into `CameraNotifier`; then tighten the rules | X-7, product decision | Functions unit tests + emulator integration tests | Production builds can't reach client-side Gemini; rewards only come from the server | High; staged rollout and rollback as in functions/README | L |
| P1-7 | D-12 leaderboard | Store `weekKey`; query `weekKey == current`, `orderBy(weeklyXp desc).limit(N)`; add the index | P0-6 | Emulator query test | Last week's XP isn't ranked; reads ≤ N per snapshot | Medium | M |
| P1-8 | D-14 primer bypass | Weather and assignment only *check* the permission; they never request it. Requests happen only from primer-gated paths | — | Unit test | No native prompt before its primer | Low | S |
| P1-9 | Privacy page, consent, analytics | Host the policy and terms; add an analytics consent toggle (default off in the EEA, or ask on first launch); call `setAnalyticsCollectionEnabled` | X-8 | Unit test | Policy URL live; analytics respects consent | Low | M |
| P1-10 | D-19 / D-18 branding and clean-clone build | Track the icon assets (once X-10 is done) or remove `assets/icon/` from pubspec; regenerate launcher and web icons | X-10 | Fresh-clone build in CI or scratch | A clean clone builds; no Flutter default icons | Low | S |

### P2 — Medium
| ID | Item | Approach | Size |
|---|---|---|---|
| P2-1 | Repository and integration test coverage | `fake_cloud_firestore` tests for `createCompletion`, `deleteAccount`, `buyStreakFreeze`, `updateUsername`; one `integration_test` happy path (needs approval to add the package) | M |
| P2-2 | D-17 DST and UTC day maths | Count days with a calendar-day helper (UTC-midnight construction) instead of `inDays`; call `toLocal()` before `dayNumber` | S |
| P2-3 | D-20 profile-photo permissions | Primer, try/catch, retry action | S |
| P2-4 | Remove the raw-error UI (`diagnosticFailureMessage`) | Keep the detail in Crashlytics/logs, show a friendly message | S |
| P2-5 | Hosting headers, SEO, canonical | `no-cache` for `index.html`, `flutter_bootstrap.js`, `flutter_service_worker.js`; OG and Twitter tags; `robots.txt`; canonical tag → `touchgrass.web.app`. **Redirecting `touchgrass-today.web.app` needs your approval.** | S |
| P2-6 | Web deep-link restore | The router waits for the first `authStateChanges` event before redirecting; keep a `from` query parameter | S/M |
| P2-7 | Recovering from a malformed challenge doc | On a parse failure, regenerate and overwrite | S |
| P2-8 | Functions hygiene | ESLint config, `npm audit` fix (major upgrade, needs approval) | S |
| P2-9 | `buyStreakFreeze` leaves `level` stale; avatar counted in `totalPhotosUploaded` | Write `level`; stop incrementing on avatar upload | S |

### P3 — Polish
| ID | Item | Size |
|---|---|---|
| P3-1 | Weather: °C/°F setting, wind (`wind_speed_10m`), freezing-precipitation and extreme heat/cold safety messages, a richer detail sheet, tests at boundaries | M |
| P3-2 | Companion: pools that use time of day, today's completion and streak; mood matched to the message; larger pools; tests | S/M |
| P3-3 | Theme tokens: move the 73 color literals into `AppColors`/`ColorScheme`, one screen at a time (no repo-wide churn) | M |
| P3-4 | Remove unused dependencies and dead code; format only the files touched (no repo-wide reformat unless approved) | S |
| P3-5 | Replace the template README; update KNOWN_BUGS and functions/README with corrected statuses | S |

### P4 — Optional
- App Check on Firestore and Storage (recommended once P1-6 is in progress).
- Web push VAPID key (X-9).
- A server-sent streak reminder via the stored FCM token.
- A payment provider for premium.
- Golden and visual regression tests.
- A static marketing landing page for SEO.
- Deduplicating the analytics retention event.

---

## 9. Release gate checklist
**Before ANY deployment (including web redeploys):**
- [ ] X-1: Gemini key rotated and restricted; new web build verified key-free.
- [ ] X-2: live Storage rules exported.
- [ ] P0-0 rules tests green.
- [ ] `flutter analyze` clean, `flutter test` green, functions `npm test` green.

**Before a public web release:**
- [ ] All of P0-1 to P0-8 done and verified.
- [ ] X-3 authorized domain; X-4 Maps referrer.
- [ ] P1-3, P1-4, P1-5, P1-8, P1-9, P1-10 (icons and favicon).
- [ ] P2-5 cache headers.
- [ ] Manual browser QA of the full journey on both domains (§7), in light and dark mode, at 360 / 768 / 1280 px.

**Before Android store submission:**
- [ ] Everything for web, plus X-5, X-6, P1-1, P1-2.
- [ ] Device QA for camera, location, push and deletion.
- [ ] Data Safety form (X-11).

**Before iOS store submission:**
- [ ] Everything for web, plus X-5 (plist, URL scheme), Apple entitlement, X-6.
- [ ] A macOS build and TestFlight QA.
- [ ] Privacy labels.
- [ ] Sign in with Apple works.

**Before declaring the app fully QA-verified:**
- [ ] Real VoiceOver and TalkBack passes.
- [ ] Text scaled to 200%.
- [ ] WCAG contrast measured.
- [ ] Offline and airplane-mode tests.
- [ ] Notification taps.
- [ ] P2-1 integration tests.

**Optional after launch:** P1-6 server authority (strongly recommended soon after launch), P3, P4.

---

## 10. Recommended implementation order
1. **Today, external:** X-1 (rotate the key) and X-2 (export the live Storage rules). Both are independent of the code.
2. **P0-0** rules harness. Every later rules change depends on it.
3. **P0-1** first-day XP. It changes the reward-path fields, which P0-6's rule bounds have to reference.
4. **P0-7, P0-4, P0-3**: small, independent rule fixes, all tested in the harness.
5. **P0-6** mirror and create integrity, after P0-1, because it needs the final set of reward fields.
6. **P0-2** account deletion, after P0-3 (Storage delete) and P0-6 (the final rules).
7. **P0-5, P0-8**: client-only changes, which can run in parallel with steps 4–6.
8. **P1-3, P1-8**, then **P1-4 / P1-5** (both touch `camera_providers.dart`, so do them one after the other).
9. **P1-7, P1-9, P1-10**, then P2.
10. **P1-6** server cutover last among the code work. It needs Blaze, a UX decision, and the corrected rules, and its rollback gets harder once the rules are tightened.

**Not safe to run in parallel:**
- All rules edits (P0-3/4/6/7, P0-2, P1-7) touch the same two files and share the test harness, so do them in sequence.
- P0-1, P1-4 and P1-5 all modify the reward and completion path in `user_repository.dart` and `camera_providers.dart`.
- **Deploying rules is a separate step that needs your approval**, because the A1 history shows how a rules regression can block completions for every user.
