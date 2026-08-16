# TouchGrass QA Checklist

Every item starts at **Not tested**. An item is only marked **Passed** if it was actually
exercised this pass (an automated test ran, a compile/build genuinely succeeded, or code was
directly inspected and the claim is scoped to exactly that). Nothing here is marked Passed on the
strength of "the code looks right" alone — see KNOWN_BUGS.md's Unverified section and the final
hardening report for the same distinction applied narratively. Update this file honestly as real
testing (browser, physical device, deployed backend) actually happens — don't flip an item without
having done the thing it claims.

Legend: `[ ]` Not tested · `[x]` Passed · `[!]` Failed · `[B]` Blocked (external dependency)

## AUTH
- [ ] Email/password sign-in, sign-up, sign-out (real browser/device)
- [ ] Google sign-in (real browser/device)
- [B] Apple sign-in on web — intentionally disabled, needs Apple Service ID (KNOWN_BUGS.md B3)
- [ ] Apple sign-in on iOS (needs physical device/Xcode)
- [ ] Session persistence across app restart
- [ ] Account deletion + reauthentication flow
- [ ] GoRouter: logged-out access to protected route redirects to /login
- [ ] GoRouter: logged-in access to /login redirects to /home or /onboarding

## PROFILE
- [x] Authenticated email displays correctly — FIXED this pass (previously shown only in Settings, never on Profile itself); VERIFIED BY CODE INSPECTION (`profile_screen.dart` identity card now shows `user.email` when non-empty); real-device rendering UNVERIFIED
- [ ] Member Since duration renders correctly for a real account age
- [x] Profile photo upload (camera + gallery, web + mobile) — VERIFIED BY CODE INSPECTION this pass (`settings_screen.dart`'s `_changeProfilePhoto`: gallery/camera bottom-sheet picker, dedicated crop screen, `image_picker` compression, real Storage upload via `StorageService.uploadProfilePhoto` to owner-scoped `user_avatars/{uid}.png`, `_uploadingPhoto` loading state, `ErrorService`-routed failure handling); real-device capture/upload UNVERIFIED
- [x] Profile photo replace flow — VERIFIED BY CODE INSPECTION this pass; UI updates automatically via the reactive `currentUserProvider` stream, no manual refresh/restart needed

## HOME
- [ ] Today's challenge card renders with correct category color/gradient
- [ ] Trail error state (offline/failed load) shows friendly message + retry
- [ ] Mascot message rotation

## CHALLENGES
- [ ] Preferred category filtering affects daily assignment
- [ ] Empty preference set falls back to all categories
- [ ] Reroll flow

## CAMERA
- [ ] Mobile: capture, retake, flash, flip, focus (physical device)
- [ ] Web: getUserMedia permission grant/denial, gallery fallback
- [ ] Verifying-stage UI reflects real stages (analyzing/uploading/saving)
- [ ] Photo compression applies to both capture and gallery paths
- [x] Free-tier honor-system gating (`_canUseAi`/`honorSystemVerificationResult`) — VERIFIED BY AUTOMATED TEST (`test/providers/camera_providers_test.dart`)
- [ ] "AI verification — Coming soon!" badge actually renders correctly on the caption screen — NOT verified in a real browser/device
- [x] "AI is reviewing your adventure" only shown when Gemini is actually running (`CameraVerifying.usingAi`) — FIXED this pass (previously shown unconditionally, including for the honor-system/no-AI/manual-override paths); VERIFIED BY AUTOMATED TEST (2 new tests) + CODE INSPECTION of all 4 state-set call sites in `verify()`/`override()`; real-browser rendering UNVERIFIED
- [x] Challenge title on the pre-camera info card no longer risks unbounded growth — FIXED this pass (`maxLines: 2, overflow: ellipsis` added, matching the Today's Challenge card)
- [x] Reward screen's "View on Map" hidden (replaced by a primary "Continue") when the completion has no location — FIXED this pass (previously always shown, silently did nothing useful for location-less completions); VERIFIED BY CODE INSPECTION; real-device tap-through UNVERIFIED
- [x] A failed reflection submission preserves the typed caption on retry, and closing the caption screen with unsaved text asks for confirmation — FIXED this pass; VERIFIED BY AUTOMATED TEST (4 new tests on `CameraFailure.caption`/`CameraCaptionStep.initialCaption`) + CODE INSPECTION of the discard-confirmation dialog; real-device flow UNVERIFIED
- [x] Contextual explanation shown before the first camera-permission request, once ever — NEW this pass (`maybeShowPermissionPrimer`); VERIFIED BY AUTOMATED TEST (`test/widgets/permission_primer_test.dart`)

## LOCATION
- [ ] Permission grant/deny/permanently-denied flows
- [ ] GPS unavailable/timeout fallback
- [x] Contextual explanation shown before the first location-permission request, once ever — NEW this pass; VERIFIED BY AUTOMATED TEST (`test/widgets/permission_primer_test.dart`); real-device prompt-ordering UNVERIFIED

## WEATHER
- [x] Condition/outdoor-advice mapping (`WeatherModel.condition`/`outdoorAdvice`) — VERIFIED BY AUTOMATED TEST this pass (`test/models/weather_model_test.dart`, extended this pass), covering every WMO code band and the precipitation-overrides-temperature priority order
- [x] Snow-shower codes (83-86) no longer show contradictory "Rain showers" advice under a "Snow showers" title — FIXED this pass (genuine bug: `outdoorAdvice`'s `>=80` check pre-empted the snow check); VERIFIED BY AUTOMATED TEST (new regression test)
- [x] Chilly (0-10°C, no precipitation) now gets distinct "bring a light jacket" advice instead of the generic fallback — NEW this pass; VERIFIED BY AUTOMATED TEST
- [ ] Current weather + tap-for-tip rendering in a real browser/device — code-level mapping is now tested, UI rendering is not
- [ ] Denied-location fallback

## MASCOT
- [x] Message pool/rotation logic — VERIFIED BY CODE INSPECTION this pass; each companion type has a fully distinct message set across all 7 pools, no overlap
- [x] Top-centered on home screen — FIXED (was left-aligned), VERIFIED BY CODE INSPECTION; real-browser rendering not confirmed
- [x] Ungated/free — VERIFIED BY CODE INSPECTION this pass; no entitlement check exists anywhere in the companion code path (correct, per the requirement's own conditional wording)
- [x] Rendered above the progress bar (Header → Mascot → Progress → Challenge → Trail) — FIXED this pass (was Header-with-embedded-progress → Mascot); VERIFIED BY AUTOMATED TEST (regression suite) + CODE INSPECTION; real-browser visual confirmation UNVERIFIED
- [x] Tap-to-respond with anti-repeat message selection — FIXED this pass (previously no tap interaction at all); VERIFIED BY AUTOMATED TEST (`test/companions/companion_test.dart`, 6 tests on `nextCompanionMessage`); real-device tap/haptic/animation feel UNVERIFIED

## LEADERBOARD / LEAGUES
- [ ] Rankings tab renders from `leaderboard_public` (real data)
- [ ] Leagues tab renders correctly as a Leaderboard sub-tab
- [x] League chip row horizontally scrollable — VERIFIED BY CODE INSPECTION this pass (pre-existing)
- [x] Locked leagues show their own emoji, never a 🔒 substitute — FIXED this pass (previously replaced the emoji entirely); VERIFIED BY CODE INSPECTION; existing opacity/semantic-label locked-state signal unchanged
- [x] Each league has a distinct static background (botanical/peaks/sky motif families) — NEW this pass; VERIFIED BY CODE INSPECTION + `flutter analyze`; real-device contrast/readability against leaderboard row text UNVERIFIED — applies to the Rankings tab only, not the separate all-leagues Leagues-tab ladder view (structurally different layout, out of scope)
- [x] Locked leagues visually greyed out (not just a lock emoji at full opacity) — FIXED this pass
- [x] League chip touch target ≥44×44 guaranteed via `ConstrainedBox` — FIXED this pass (previously content-sized, could be narrower for short names)

## ACHIEVEMENTS
- [ ] Unlock flow end-to-end
- [ ] Grayscale treatment for unearned badges (real device rendering)

## JOURNAL
- [x] Entry creation with photo persists and reopens correctly — VERIFIED BY CODE INSPECTION this pass (`memory_repository.dart`: idempotent `createMemory` keyed on the completion ID, real-time `watchFirstPage` stream + paginated `fetchNextPage` history, real Storage `photoUrl`, owner-scoped Firestore subcollection); real-device restart/reopen behavior UNVERIFIED
- [ ] Caption edit
- [x] Discoverable from Home via a persistent "Your Adventure Journal" shortcut card, deep-linking into the Map screen's Journal tab — NEW this pass (previously only reachable via a secondary pill-tab inside Map, with no entry point from Home); VERIFIED BY CODE INSPECTION + `flutter analyze`; real-device tap-through UNVERIFIED
- [x] Journal entries render inside a bordered/shadowed card shell instead of a bare list row — NEW this pass (visual polish, matches achievement-card styling); VERIFIED BY CODE INSPECTION

## SETTINGS
- [ ] Theme selector (System/Light/Dark/Automatic)
- [ ] Category preference chips persist to Firestore
- [ ] Sign out clears local session (and now also clears fcmToken — see below)
- [x] "Export My Data" subtitle/icon now accurately describes a clipboard-copy, not a file download — FIXED this pass (previously said "Download a copy," but the action only ever copied a text summary to the clipboard); VERIFIED BY CODE INSPECTION

## THEME
- [ ] Automatic mode actually switches at real sunrise/sunset on a live device
- [x] `isDaytime`/`resolveEffectiveThemeMode` pure-function logic — VERIFIED BY AUTOMATED TEST (`test/core/sunrise_sunset_test.dart`, pre-existing)

## NOTIFICATIONS
- [ ] Mobile: foreground notification received
- [ ] Mobile: background/tap-to-navigate notification (physical device)
- [x] Mobile: FCM token capture on sign-in — VERIFIED BY STATIC INSPECTION (`notification_providers.dart`), not re-tested live this pass
- [x] fcmToken cleared on sign-out — VERIFIED BY STATIC INSPECTION + `flutter analyze`/`flutter test` regression pass this pass; not exercised against a real device
- [B] Web: background push — blocked on VAPID key (KNOWN_BUGS.md B4); client plumbing added this pass but genuinely untested against a real browser
- [x] Contextual explanation shown before the first notification-permission request, once ever, and moved from a context-less `main()` callback into `AppShell` (fires after sign-in, with a real `BuildContext`) — FIXED this pass; VERIFIED BY AUTOMATED TEST (`test/widgets/permission_primer_test.dart`) + CODE INSPECTION; real-device prompt-ordering UNVERIFIED
- [B] Actual push-sending capability (a server ever calling `admin.messaging()`) — genuinely absent from this repo; no Cloud Function anywhere sends a notification. This is new backend feature work (a scheduler or trigger function), not a client bug, and depends on the same Blaze-billing blocker as B1. Not attempted this pass — explicitly out of scope for a client-side polish pass.

## OFFLINE / ONLINE
- [ ] Airplane-mode mid-flow behavior
- [ ] Reconnect does not duplicate completions/journal entries
- [x] Web Firestore persistence enabled — VERIFIED BY CODE INSPECTION (prior pass), not re-tested live this pass

## ERROR STATES
- [x] Home screen routes errors through `ErrorService.friendlyMessage()` with retry — VERIFIED BY CODE INSPECTION this pass
- [x] Journal caption-save and challenge-reroll errors now route through `ErrorService` instead of hand-built SnackBars — FIXED this pass (styling/DRY consistency only — both already showed the same safe, friendly message before this change); VERIFIED BY CODE INSPECTION

## WEB
- [x] `flutter build web --release` succeeds without a Gemini or VAPID key defined — VERIFIED BY BUILD, re-confirmed this (8th) pass in 303.7s; grepped `main.dart.js` for `GEMINI_API_KEY`/`FCM_VAPID_KEY` — zero matches, only the expected public Firebase web config key present
- [x] Rebuilt with the dev Gemini key (`--dart-define-from-file=secrets.json`, 243.4s) and deployed to `touchgrass-today.web.app` via `firebase deploy --only hosting` — VERIFIED this (8th) pass (hosting only; no rules/functions deployed); active `firebase use` target confirmed as `touchgrass-today` before deploying
- [x] All this pass's changes (A16-A25: web branding, weather advice fix, profile email, View-on-Map fix, caption preservation + discard confirm, Data Export copy, permission primers, onboarding Reduce Motion, Reduce Motion OS inheritance, Journal shortcut + card polish) deployed to `touchgrass-today.web.app` — VERIFIED: deployment succeeded (`Deploy complete!`), and the served `main.dart.js` was confirmed via SHA-256 hash (`047c96a2e1bcfb0528f1355ca73be8243a30a943331e470672df0384b6942e8e`) to be byte-identical to the local build containing these changes; `manifest.json` fetched live and confirmed to show the corrected TouchGrass branding/forest-green theme color
- [ ] Full click-through in a real browser (Chrome/Edge/Safari) of the newly-deployed build — no browser-automation tooling available in this environment; the deployed bundle's *contents* are verified, its *rendered/interactive behavior* is not
- [ ] Responsive layout at 320/375/390/414/768/1024/1440/1920px (real viewport, not code inspection)

## ANDROID
- [x] `MainActivity.kt` namespace/package fixed to match `com.touchgrass.app` — VERIFIED BY CODE INSPECTION this pass; genuine, previously-undiscovered defect (see KNOWN_BUGS.md B9)
- [!] `flutter build apk --debug` — ATTEMPTED **five times** across this engagement (default 8GB Gradle heap → JVM OOM crash; temporary 2GB retry → JVM OOM crash again; a 4th-pass attempt → a Dart VM crash during native-assets kernel compilation of the `objective_c` package, a transitive dependency's build tooling; **5th and 6th-pass attempts → consistent, reproducible progress** — both runs got past the earlier environment-crash failure modes entirely and failed identically at `:app:processDebugGoogleServices` (125.6s then 495.0s — timing varies with system load, the failure point does not) on the already-documented B6 blocker: `No matching client found for package name 'com.touchgrass.app' in google-services.json`. Confirmed with correct exit-code capture the second time (exit 1) after realizing the first run's background-notification "exit 0" was a false signal caused by piping through `tail`. This is a genuine, reproducible external blocker, not an environment or code failure — but `compileDebugKotlin` still was never reached in this task graph, so the `MainActivity.kt` fix remains **unverified by an actual successful Kotlin compile**. Retry once `google-services.json` is replaced (B6) for a real signal.
- [B] `flutter build apk --release` — not attempted; would sign with the debug key today (no `key.properties`)
- [ ] Physical device install/run

## IOS
- [x] Xcode `PRODUCT_BUNDLE_IDENTIFIER` corrected to `com.touchgrass.app` (all 3 build configs, Runner + RunnerTests) — VERIFIED BY CODE INSPECTION this pass
- [B] `flutter build ios --release` — categorically impossible in this Windows environment (no Xcode/macOS)
- [B] `GoogleService-Info.plist` still does not exist in the repo at all — Firebase Console registration required before any iOS Firebase build is possible
- [ ] Physical device install/run

## ACCESSIBILITY
- [ ] VoiceOver (iOS) real announcement behavior
- [ ] TalkBack (Android) real announcement behavior
- [ ] Dynamic Type at 130%/150%/200%
- [x] `Semantics(...)` usage present across 13 files (28 occurrences) — VERIFIED BY CODE INSPECTION (prior pass), not re-audited for correctness this pass
- [x] Reduce Motion wired into ~8 animation-heavy widgets — VERIFIED BY CODE INSPECTION (prior pass)
- [x] `reducedMotionProvider` now also honors the OS-level "Reduce Motion" accessibility setting, not just TouchGrass's own in-app toggle — FIXED this pass, a single-point provider-level fix (`osReducedMotionProvider` in `settings_providers.dart`) that reaches all ~30 existing call sites without touching each individually; VERIFIED BY CODE INSPECTION + `flutter analyze`; the underlying pure `combinedReducedMotion` helper already has automated test coverage, the new provider wiring itself does not (touches `WidgetsBinding.platformDispatcher`)
- [x] Onboarding's page-swipe transition and indicator dots now respect Reduce Motion — FIXED this pass (previously always animated regardless of the setting, unlike the rest of the screen); VERIFIED BY CODE INSPECTION

## SECURITY
- [x] A1 Firestore reward-write bounds intact — VERIFIED BY CODE INSPECTION this pass (`firestore.rules`, unchanged)
- [x] `leaderboard_public` mirror prevents cross-user PII read via `/users/{uid}` — VERIFIED BY CODE INSPECTION this pass (rules restrict `/users/{uid}` to owner-only reads)
- [x] Repo-wide secret scan (Gemini key, service accounts) — VERIFIED BY CODE INSPECTION this pass; `secrets.json` confirmed gitignored and never committed (`git check-ignore`, `git log --all`)

## GEMINI
- [x] Client-side Gemini call sites identified and unchanged — VERIFIED BY CODE INSPECTION this pass
- [x] `functions/src/rewards.ts` pure logic (level/league/streak/weeklyXp/entitlement/response-parsing/request-validation/quota) — VERIFIED BY AUTOMATED TEST this pass (49/49, `npm test`)
- [B] `verifyChallengeCompletion` end-to-end against live Gemini/Firestore — blocked, not deployed (no Blaze billing)

## ENTITLEMENTS
- [x] `EntitlementTier` parsing/gating/quota logic — VERIFIED BY AUTOMATED TEST this pass (`test/models/entitlement_test.dart`, 8 tests)
- [x] **Now wired into the live camera flow** — `CameraNotifier.verify()` checks `canUseAiVerificationProvider` before ever reaching Gemini; free-tier honor-system fallback VERIFIED BY AUTOMATED TEST this pass (`test/providers/camera_providers_test.dart`)
- [ ] Real end-to-end confirmation that a free account sees "Coming soon!" and a manually-granted `premium`/`admin_test` account gets real Gemini verification — NOT tested in a real browser/device this pass

## FIRESTORE
- [x] Rules file reviewed end-to-end this pass — VERIFIED BY CODE INSPECTION; no automated rules-emulator test run (no Java 21 available in this environment)

## STORAGE
- [x] `completion_photos/` owner-scoped read+write, 10MB cap — VERIFIED BY CODE INSPECTION this pass (`storage.rules`)

## CLOUD FUNCTIONS
- [x] `npm run build` (TypeScript compile) — VERIFIED, this pass
- [x] `npm test` (49 unit tests, up from 32) — VERIFIED, this pass; covers all pure reward/entitlement/quota/request-validation logic
- [ ] `onCall` handler's own control flow (auth check, Firestore reads, transaction, idempotency branch) — NOT unit-testable in this environment (needs Firestore emulator, blocked on Java 21, or a risky untested DI refactor not attempted)
- [x] Client fail-closed wiring (`challenge_verification_service.dart`) reviewed — VERIFIED BY CODE INSPECTION this pass; production build cannot construct the insecure local path (throws `StateError`), remote path never falls back to local
- [B] Deployment and live invocation — blocked on Blaze billing + secret (external)

## NAVIGATION
- [x] GoRouter redirect logic reviewed for loop risk — VERIFIED BY CODE INSPECTION this pass; no loop found, one enforcement gap noted (onboarding not enforced outside `/login`) but not fixed this pass (out of scope)

## ACCOUNT DELETION
- [x] Web: Apple-linked account deletion shows friendly message, not a raw `PlatformException` — VERIFIED BY CODE INSPECTION this pass
- [ ] End-to-end deletion on a real account (all data actually removed)
