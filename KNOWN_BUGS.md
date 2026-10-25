# TouchGrass — Known Bugs & Gaps

Compiled after 10 audit/hardening passes on the mobile app plus a dedicated Flutter Web
compatibility pass. Bugs found and fixed in those earlier passes aren't repeated here, since
they're resolved. Category A items stay listed with a **FIXED** status once closed (rather
than being deleted) so there's a record of what changed and why; Category B items remain
outstanding until their external blocker is cleared.

Each entry states the exact defect, the file/line it lives in, and who it actually affects.
Items in the "Unverified" section at the bottom are explicitly *not* confirmed bugs — they're
things nobody has been able to test yet (no physical device, no real browser session) and are
listed separately so they don't get treated as equivalent to a confirmed defect.

> **Remediation program (2026-10-17 onward):** the current status of every audit finding,
> with test evidence and blockers, is tracked in `REMEDIATION_CHECKLIST.md`. Phase 3 (local
> only — nothing deployed) changed the following; details and evidence are in its "Phase 3 —
> results" section:
> - **Location privacy (D-09):** the setting, now "Save location with adventures"
>   (`settings.locationEnabled`), actually works. When it's off, no location is saved with
>   completions or Journal entries, and none is sent to Open-Meteo (weather) or the place-name
>   geocoder. `firestore.rules` also refuse stored location data while it's off. Weather only
>   receives coordinates rounded to ~1 km. The in-app privacy policy now lists every data flow.
> - **Journal, photo and XP consistency (D-13):** the Journal entry is written in the same
>   atomic batch as the completion and its XP. Each completion's photo has one fixed path
>   (`completion_photos/{uid}/{yyyy-MM-dd}.jpg`, enforced by both rule files), so retries
>   replace it instead of orphaning files. Missing entries from older app versions are restored
>   once per session. The camera screen distinguishes "Photo not uploaded", "Not saved yet"
>   (retry), "Already completed" and "saved to your Journal".
> - **AI verification:** still off on every tier (owner decision); future design in
>   `AI_VERIFICATION_PLAN.md`.
> - **Cloud Functions runtime:** Node 22 (Node 20 is decommissioned by Google on 2026-10-30).
>
> Phase 4 (local only — nothing deployed) changed the following; details in "Phase 4 —
> results":
> - **Dependencies:** `functions/` npm audit went from 1 critical / 6 high / 10 moderate to
>   2 high / 7 moderate, using lockfile-only, semver-compatible updates. The remainder sits in
>   firebase-admin 12's node-forge and uuid, isn't reachable in this app, and needs the
>   firebase-admin 14 major upgrade (awaiting approval). 6 unused Dart packages were removed.
> - **Lint:** `npm run lint` now really runs ESLint (with type-aware promise checks).
> - **Formatting:** 76 Dart files formatted; the format check is clean.
> - **Privacy fix (new, N-2):** photos could carry **embedded GPS (EXIF/XMP)** into Storage
>   even with the location setting off. Every completion photo is now stripped before upload.
> - **Smaller fixes:** raw error text no longer shown (S-9); notification deep links are
>   allow-listed (S-10); weather no longer prompts before the location primer (D-14); DST-safe
>   day counts (D-17); profile-photo permission denial handled (D-20); retention analytics
>   logged once per session (D-21).
> - **Android build:** besides the external Firebase registration (X-5, still blocking), three
>   more blockers were found and fixed: geocoding 3 → 4 (compileSdk), R8 Play Core rules, and
>   the Crashlytics mapping upload, now opt-in so local builds never contact production.
>
> Phase 5 (2026-10-19, local only — nothing deployed) changed the following; details in
> "Phase 5 — results":
> - **Dependencies:** `firebase-admin` 12 → 14.5.0 with the required `firebase-functions`
>   6 → 7.4.0 (code moved to the modular Admin API). `functions/` npm audit: **0**. The
>   dev-only `firestore-tests/` chain still has 5 high (grpc-js 1.9, no upstream fix, client-only
>   use against the local emulator).
> - **Avatar uploads no longer count as photo uploads** (`totalPhotosUploaded` untouched;
>   adventure photos are counted by `totalCompletions`).
> - **"Remove saved locations"** in Settings → Privacy deletes the location, place name and
>   weather from past completions and Journal entries, and nothing else (enforced by
>   `firestore.rules`; needs a rules deploy). Photo files from earlier versions may still carry
>   GPS metadata (B11).
> - **Abandoned-photo cleanup** written and tested, dry-run by default, **not deployed or
>   scheduled** (needs approval).
> - **Leaderboard:** other users' photos only load from the app's own avatar storage or Google
>   profile photos (A27). The D-12 data-model redesign is a proposal awaiting decisions.
> - **Still blocked:** Firebase registration for `com.touchgrass.app` (B6/X-5), release signing
>   (B7/X-6), iOS (no Mac), and `deleteAccount` deployment (D-04).
>
> Phase 6 (2026-10-19, local only — nothing deployed); details in `PHASE_6_FINAL_REPORT.md`:
> - **Account deletion:** other sessions are signed out first; every failure point is tested
>   to stop and resume; analytics identity is cleared on sign-out and reset after deletion; the
>   in-app wording says exactly what is deleted and that Firebase keeps diagnostics for its
>   retention period. Still **not deployed**.
> - **Profile photos (A27):** `firestore.rules` now accept only no photo, the owner's own avatar
>   in this app's bucket, or the photo in the caller's verified Google ID token.
> - **Old photos' GPS (B11):** a dry-run-first inventory and lossless in-place remediation tool
>   exists (`functions/src/ops/`); nothing has been run against production.
> - **Android:** release builds no longer fall back to the debug key — they stop with the fix
>   (B7). Builds also stop with a clear message while Firebase has no `com.touchgrass.app` app (B6).
> - **iOS:** deployment target raised to 14.0 (Google Maps plugin requirement); permission texts
>   corrected. Entitlements, plist and signing still need a Mac (B6).
>
> Phase 7A (2026-10-19, local + READ-ONLY production checks — nothing deployed); details in
> `PHASE_7A_FINAL_REPORT.md`:
> - **NEW, critical (B12):** the LIVE Storage rules let any signed-in user read and list every
>   user's completion photos. Interim rules that close this without breaking the live web app
>   are ready (`deploy/interim/`), not deployed.
> - **NEW, high (B13):** production has no composite indexes; the completions query needs one.
>   `firebase.json` now deploys `firestore.indexes.json`; the deploy itself is pending.
> - **Live Firestore rules = committed HEAD rules**, so every audit finding on them is live until
>   the coordinated rules + web release (`PHASE_7A_DEPLOYMENT_MANIFEST.md`).
> - **Maps (B5):** one key serves web, iOS and Android, so it can't be restricted correctly; the
>   iOS key moved out of `AppDelegate.swift` into a git-ignored xcconfig.
> - Project billing (Blaze) verified enabled; no functions deployed yet.
>
> Phase 7C (2026-10-20, local + one READ-ONLY rules export — nothing deployed); details in
> `PHASE_7C_FINAL_REPORT.md`:
> - **Still live:** production Storage rules are unchanged (exposed); S-1 is not deployed.
> - **Fixed locally:** final `storage.rules` avatar listing (A30); data appended after a JPEG,
>   which can hold GPS, is no longer uploaded (A29); token URLs can't reach Crashlytics (A31).
> - **New tool:** download-token rotation for links harvested while the rules were open (B15).
>   Needs S-1 first, then separate authorizations.
> - **Live account deletion** fails at Firestore before touching photos (D-04 detail).
>
> Phase 7D (2026-10-20); details in `PHASE_7D_FINAL_REPORT.md`:
> - **Interim Storage rules DEPLOYED (authorized) and verified live** (B12 containment).
> - Harvested links are still valid until rotation (B15).
> - Rotation is now two-phase, so no saved link ever breaks.
> - Account-deletion root cause confirmed and server fix hardened (D-04).
> - Misleading privacy and AI copy corrected locally (A32).
>
> Phase 7E (2026-10-20); details in `PHASE_7E_FINAL_REPORT.md`:
> - **Live smoke test 32/32**, so containment at the rules level is verified in production.
> - Old token URLs still open photos without sign-in (B15).
> - `deleteAccount` deploy blocker removed (B16).
> - Firebase app registrations mismatch on Android **and** iOS (B6).
>
> Phase 7F (2026-10-21); details in `PHASE_7F_FINAL_REPORT.md`:
> - Live state re-verified read-only: still contained at the rules level; old links still valid (B15).
> - The rotation dry-run was not read-only (it wrote a lease document); fixed locally (B17).
> - Late uploads after account deletion: the final Storage rules now require the profile (B18).
> - Nothing was deployed, rotated or inventoried: no Google Cloud credentials on the operator machine.
>
> Phase 7G (2026-10-21); details in `PHASE_7G_FINAL_REPORT.md`:
> - The camera no longer advertises "AI verification — Coming soon!"; AI stays disabled (B19).
> - Operator dry-runs proven read-only and guarded by a central mutation mode and exact allowlists (B17 update).
> - A deleted account can no longer re-create its profile to upload again (B18 update).
> - Still nothing deployed, rotated or inventoried: no Google Cloud credentials on the operator machine.

---

## CATEGORY A — Claude Code can fix these directly (no external account/credential needed)

### A1. Users can inflate their own XP/level/streak/league by writing directly to Firestore — FIXED
**File:** `firestore.rules` (`isValidUserWrite()`, the reward-write-bounds helper functions above it, and the `/users/{userId}` `update` rule)
**The bug:** The rule only blocked XP from *decreasing* (`request.resource.data.xp >= resource.data.xp`). There was no upper bound, and `level`, `streak`, `currentLeague`, and `achievements` were all client-writable with no validation. Any signed-in user could call the Firestore SDK/REST API directly and set their own `xp` to any number.
**Who it affects:** Every user who cares about the leaderboard/league rankings being fair.
**What changed:** The `update` rule now bounds every reward field to what a single legitimate write from `UserRepository.awardCompletionRewards`/`buyStreakFreeze` could actually produce, traced against both methods' real write payloads:
- `xp` can shrink freely (spending XP, e.g. buying a streak freeze, is legitimate) but can only grow by at most 4000 per write — comfortably above the real max (one hard-challenge reward of 100 + the entire 16-achievement pool's XP, which sums to 3475) but far below "set it to anything."
- `level`/`currentLeague` are cross-checked against exact formulas (`levelForXp`, `leagueForXp`, mirroring `AppConstants.levelForXp` and `LeagueDef.idForXp`) whenever XP increases — the one path that reliably computes both correctly. Deliberately *not* enforced on decreases, because `buyStreakFreeze` decreases `xp` without recomputing `level` — requiring it there would have broken a legitimate feature.
- `weeklyXp` gets the same growth cap; `streak` is bounded to {unchanged, +1, reset-to-1} (the only three legitimate transitions `resolveStreakOutcome` can produce); `longestStreak`/`totalCompletions`/`rainyDayCount` can each only move by 0 or +1 per write; `achievements`/`frozenDates` can only grow (`hasAll` of the previous array), never be cleared.
- **Bonus find while implementing this:** the *existing, not-yet-deployed* `xp >= resource.data.xp` rule would have permanently broken `buyStreakFreeze` (a real, working feature that spends XP) the moment it was deployed, since spending is a legitimate decrease. Fixed as part of the same change — the new rule allows decreases and only bounds growth.
- This is a stopgap, not a full fix — see B1, the real fix (server-computed rewards) still needs a backend this project doesn't have.
**Status:** **Fixed in code, and now deployed (2026-08-12).** `flutter analyze` clean, `flutter test` 231/231. Traced by hand against both real write paths (`awardCompletionRewards`, `buyStreakFreeze`) since Java 21 wasn't available locally to run the rules emulator's automated check.

**Confirmed real-world impact, round 1 (deploy lag — real, but not the actual cause):** user reported "unable to bypass AI verification and submit the photo" via the "Submit Anyway" (`CameraNotifier.override()`) button. Traced the exact error text ("Verification Unavailable — An unexpected error occurred.") to `UnexpectedException.wrap()`, which only fires when `CompletionRepository.createCompletion()`'s Firestore transaction throws something other than the app's own typed exceptions. Deployed this already-written-but-undeployed ruleset via `firebase deploy --only firestore:rules`. **This did not fix the bug** — user retried and got the identical error, meaning deploy staleness was a real, separately-worth-fixing gap (now closed) but not the actual root cause here.

**Round 2 — the real bug, found and fixed:** `completions/{completionId}`'s `allow read` rule was `resource.data.userId == request.auth.uid`. `CompletionRepository.createCompletion()`'s transaction calls `tx.get(ref)` *before* writing, to check "does today's completion already exist" — the mechanism that makes duplicate completions impossible. For a first-time completion, the document doesn't exist yet, so `resource` is `null`; evaluating `resource.data.userId` on a null `resource` fails rule evaluation, which Firestore treats as a denial. So the exists-check read was rejected with `permission-denied` on **every completion attempt from any account**, override or not — present since the very first commit (`git show 4a1bb15:firestore.rules` has the identical rule), not something either hardening pass introduced. `guardAsync` (used by `createCompletion`, which calls `FirebaseFirestore.instance.runTransaction` directly rather than through `FirestoreService`'s nicer `permission-denied` → `DataException` mapping) wraps the raw `FirebaseException` as `UnexpectedException.wrap(e)`, which is exactly the generic "unexpected error" text the user saw.
**Fix:** `allow read: if isSignedIn() && (resource == null || resource.data.userId == request.auth.uid);` — allows the exists-check to run (a nonexistent document has no data to leak) while still restricting reads of *existing* completions to their owner.
**Verified empirically before deploying** (unlike round 1) — Java 21+ wasn't on `PATH`, but Android Studio's bundled JBR (25.0.2) was, so I ran the real Firestore Rules emulator against a scratch npm project using `@firebase/rules-unit-testing`, simulating the exact override-submission transaction end-to-end: the exists-check read on a nonexistent doc now succeeds, the full transactional write now succeeds, non-owners still cannot read another user's completion (isolation intact), and the user-doc reward update from A1's bounds rule still succeeds. Deployed via `firebase deploy --only firestore:rules`, compiled and released cleanly. **User retried — still the identical error, including in a fresh private/incognito window (ruling out stale-cache).** So round 2's rules fix, while real and independently correct, also wasn't the actual root cause of what this specific user is hitting.

**Round 3 — instrumented rather than guessed further.** Added `diagnosticFailureMessage()` (`camera_providers.dart`) so every `CameraFailure` built from an `AppException.message` appends the real cause when the message is the generic `UnexpectedException` text: a `[code]` suffix for a typed `FirebaseException`, or `[RuntimeType: text]` for anything else. Deployed. **First version of this helper only handled `FirebaseException` and produced no visible change in the user's retry — confirming the real cause on Flutter Web is NOT arriving as a typed `FirebaseException` at all.** Broadened the helper to fall back to `runtimeType` + truncated `toString()` for any other cause shape. Deployed, hash-verified.

**Round 4 — the actual root cause, now fixed.** User's next retry returned: `[JSObject: Error: Dart exception thrown from converted Future. Use the properties 'error' to fetch the boxed error and 'stack' to recover the stack trace...]`. That exact phrase is `dart:js_interop`'s own generic wrapper text for a Dart exception that failed to cross back out of a JS-interop-converted callback as a typed exception — and `CompletionRepository.createCompletion`'s `FirebaseFirestore.instance.runTransaction((tx) async {...})` is precisely that shape: an async Dart closure, passed through `cloud_firestore_web` (pinned at 4.4.12) to the underlying Firebase JS SDK's `runTransaction`. This is a known category of gap in `cloud_firestore_web`'s transaction support — nothing in this app's own rules, entitlement, or AI-verification logic was ever the cause; rounds 1–3 were each real, independently-correct fixes to things that turned out not to be it (and round 3's instrumentation is what finally proved it, rather than another guess).
**Fix:** rewrote `createCompletion` to skip `runTransaction` entirely. Firestore already atomically classifies a `.set()` against `allow create` when no document exists yet and `allow update` when one does — and `completions`' `allow update: if false` already denies the latter — so the "only one completion per day" guarantee needs no client-side read-then-write at all; a plain `.set()` gets the same atomicity for free, entirely server-side, without going anywhere near the buggy `runTransaction` code path. A `permission-denied` on this specific, self-owned, correctly-shaped write can now only mean "already exists," so it's translated straight to the same friendly "You've already completed today's challenge." message the transaction version used.
**Verified empirically before deploying** — re-ran the Firestore Rules emulator (Android Studio's JBR, 25.0.2) against the new plain-`.set()` pattern specifically: a fresh create succeeds, a second `.set()` on the same now-existing doc is denied with exactly `permission-denied`, and the original document's data is confirmed unchanged after the denied attempt (no silent partial overwrite). `flutter analyze` clean, `flutter test` 235/235. Deployed to both hosting targets, hash-verified. This is the first of the four rounds with both an emulator-verified mechanism *and* a plausible explanation for why the first three attempts each failed to change anything — still needs the user's live retry to close the loop, since no browser automation is available here.

### A2. No per-device push notification targeting on mobile — FIXED (mobile only)
**Files:** `lib/services/notification_service.dart` (`getToken()`, `onTokenRefresh`), `lib/providers/notification_providers.dart` (`fcmTokenSyncProvider`), `lib/main.dart` (wired into the app root), `firestore.rules` (`fcmToken` added to the client-writable field allow-list)
**The bug:** The app subscribed to two broadcast topics but never fetched or stored an individual device's FCM token — no way to target a notification at one specific user.
**What changed:** `NotificationService.getToken()` fetches the device's FCM token (returns `null` on web and never throws — web still needs a VAPID key first, see B4). A new `fcmTokenSyncProvider`, watched once from the app root alongside the existing `analyticsBootstrapProvider`, saves that token to the signed-in user's Firestore document on sign-in and keeps it current via `onTokenRefresh` for the rest of the session. Keyed off `authStateProvider` (uid), not the full user-document stream, so it only re-runs on actual sign-in/out — not on every unrelated Firestore field change.
**Status:** **Fixed in code, mobile only.** `flutter analyze` clean, `flutter test` 146/146. This closes the token-*capture* half of the gap; actually *sending* a targeted notification using the stored token still needs a way to call the FCM Admin API server-side (Cloud Function or manual), which circles back to B1's Blaze-plan blocker. Web token capture is separately blocked on the VAPID key in B4.

### A3. Signing out left a stale FCM token association on the user's document — FIXED
**Files:** `lib/providers/settings_providers.dart` (`SettingsNotifier.signOut`)
**The bug:** A2 (this doc, above) added FCM token *capture* on sign-in, but nothing ever cleared it on sign-out — a device that signed out remained targetable by per-user push notifications meant for whoever signs in next.
**What changed:** `signOut()` now clears `fcmToken` on the user's Firestore document (best-effort, while still authenticated — the write needs `isOwner`) before calling `AuthService.signOut()`.
**Status:** **Fixed in code.** `flutter analyze` clean, `flutter test` 193/193 (up from 185 — includes new tests from this pass, see below).

### A4. Google Sign-In official logo asset had no drop-in path — FIXED, then superseded
**Files:** `pubspec.yaml`, `assets/icons/`
**The bug:** `social_sign_in_button.dart` already referenced `assets/icons/google_logo.png` with a graceful fallback painter, but the `assets/icons/` directory didn't exist and wasn't declared in `pubspec.yaml`'s asset list — so dropping the real logo file in would still have required a config edit, contradicting the "insertable without code changes" goal.
**What changed:** Created `assets/icons/` (with a placeholder `README.txt` explaining what goes there) and added it to `pubspec.yaml`'s `flutter: assets:` list. Dropping in the real `google_logo.png` now requires zero further changes.
**Status:** **Superseded by a better fix, see below** — the PNG-drop-in pipeline this entry describes is no longer used by `_GoogleIcon`, though it's harmless to leave in place (`assets/icons/` stays declared for any future icon).

**Update — official Google logo now rendered directly, no PNG needed:** The user supplied Google's actual "Continue with Google" button markup (the official Identity Services SVG, 48×48 viewBox, 4 solid brand-color paths). Rather than saving that as a PNG asset (a lossy, DPI-dependent extra step), transcribed the 4 path's exact SVG command data (`M`/`c`/`l`/`C`/`s`/`H`/`v`/`h`/`z`) into Dart `Path` objects by hand — `social_sign_in_button.dart`'s new `_GoogleLogoPainter` — and made it the icon's only rendering path (the old `Image.asset`-with-`errorBuilder`-fallback mechanism and the hand-approximated `_GoogleGPainter` quadrant painter are both removed). This is Google's actual official mark, vector (scales perfectly at any size/DPI, nothing to 404), with zero new dependency and zero asset file. `flutter analyze` clean, `flutter test` 231/231 unaffected (no test covered the old painter either).

### A5. AI photo verification is now actually gated behind the paid entitlement tier — FIXED (product decision confirmed with user)
**Files:** `lib/providers/camera_providers.dart` (`_canUseAi`, `honorSystemVerificationResult`, `verify()`), `lib/features/camera/screens/camera_screen.dart` (caption-screen "Coming soon!" messaging)
**The gap:** The entitlement model, Cloud Function quota enforcement, and `AiFeatureLockedCard` widget all existed from earlier passes, but nothing in the live camera flow actually checked `canUseAiVerificationProvider` — every user, regardless of tier, reached the real Gemini call whenever a key was configured.
**What changed:** `CameraNotifier.verify()` now checks entitlement *before* ever reaching Gemini. Free-tier users (everyone today — nobody has been granted `premium`/`admin_test`) never call Gemini and never consume AI quota; instead they get the same honor-system auto-approve path already used for "no key configured" (XP is awarded normally — confirmed with the user this should not block the core app loop), with an accurate, distinct reason (`'aiLocked': true` in the stored `verificationResult`, never fabricating a `confidence`/`matches` verdict). The caption screen now shows an "AI verification — Coming soon!" badge for this case specifically, styled consistent with that screen's existing dark photo-overlay UI (not the mismatched light-card `AiFeatureLockedCard`, which remains unused — see its own doc comment).
**Important consequence — read before assuming AI verification "works" on the live site:** Since every current user is free-tier, this means the `touchgrass-today.web.app` deploy (which has the dev Gemini key embedded specifically so AI verification could be tested) will now show "Coming soon!" for every normal signup, not real Gemini verification. To actually exercise the real Gemini path for testing, manually grant a specific test account `premium` or `admin_test` via the Firestore Console (`entitlementTier` field on that user's document — already structurally un-client-writable, so this is the intended, documented way to test it, not a new blocker).
**Status:** **Fixed in code**, `flutter analyze` clean, new tests added (see below). **Not tested in a real browser** — I did not click through the live site to confirm the "Coming soon" badge renders correctly.

### A6. Mascot was left-aligned mid-page, not top-centered — FIXED
**File:** `lib/features/home/screens/home_screen.dart` (`_TrailCompanion`)
**The bug:** `Align(alignment: Alignment.centerLeft, ...)` — the mascot sat left-aligned below the header, not centered.
**What changed:** Changed to `Alignment.center`. Left its existing position in the scroll order unchanged (directly after the header, before the challenge card) — a fixed top-of-screen floating overlay would have been a much larger, riskier structural change than what was asked, and "centered near the top of the page content" is the more conservative, faithful reading of the request.
**Status:** **Fixed in code.** `flutter analyze` clean, `flutter test` regression clean (no existing test covered this widget's alignment).

### A7. Leaderboard locked leagues weren't visually greyed out, and had no guaranteed touch target — FIXED
**File:** `lib/features/leaderboard/screens/leaderboard_screen.dart` (`_LeagueChip`)
**The bug:** Locked leagues were rendered at full opacity, distinguished only by a 🔒 emoji replacing the league's own emoji — easy to miss. Separately, the chip's tappable area was sized purely by its content (padding + short text), with no `minWidth`/`minHeight` constraint, so a short league name could produce a touch target narrower than the 44×44 logical-pixel accessibility minimum.
**What changed:** Wrapped the chip's visual content in `Opacity(opacity: 0.4)` when locked (semantics/tap area unaffected — still tappable to preview). Added `ConstrainedBox(constraints: BoxConstraints(minWidth: 44, minHeight: 44))` around the chip.
**Status:** **Fixed in code.** `flutter analyze` clean, `flutter test` regression clean.

### A10. Mascot didn't respond to taps — FIXED (E1)
**Files:** `lib/features/home/screens/home_screen.dart` (`_TrailCompanion`), `lib/companions/companion.dart` (`nextCompanionMessage`), `lib/companions/companion_widget.dart` (`_CompanionViewState.didUpdateWidget`)
**The gap:** `_TrailCompanion` displayed one deterministic per-day message with no tap interaction at all.
**What changed:** `_TrailCompanion` is now a `ConsumerStatefulWidget`. Tapping it (debounced 400ms, haptic feedback) picks a new message from the companion's own existing message pool via the new pure `nextCompanionMessage()` helper — guaranteed not to immediately repeat the previous message unless the pool has no alternative — and briefly plays the existing `CompanionMood.cheer` animation before settling back to `encourage`. `CompanionView` gained a small `didUpdateWidget` addition so a changed `message` prop replays the speech-bubble reveal (previously only fired once, in `initState`, since no caller varied `message` over a widget's lifetime until now). No network call, no Firestore write, fully Reduce-Motion-compliant (mood animation freezes at rest-pose, message still changes).
**Status:** **Fixed in code.** `flutter analyze` clean. 6 new tests (`test/companions/companion_test.dart`) cover multi-message exclusion, single-message-pool fallback, previous-not-in-pool fallback, and the empty-pool defensive case.

### A11. Challenge titles had no overflow protection on several cards — FIXED (G1)
**Files:** `lib/features/home/widgets/todays_challenge_card.dart`, `lib/features/camera/screens/camera_screen.dart` (`_ChallengeInfoCard`), `lib/features/map/screens/map_screen.dart` (memory detail modal title)
**The gap:** The Today's Challenge card's title `Text` had no `maxLines`/`overflow`, unlike its own description directly beneath it; two other rendering sites (camera idle screen, map memory-detail modal) had the same gap. An unusually long generated title could grow a card unpredictably or, in the modal's `Row`+`Expanded` context, an extreme title could push other row content awkwardly.
**What changed:** Added `maxLines: 2, overflow: TextOverflow.ellipsis` at all three sites. The full title remains reachable via the challenge detail screen (`challenge_detail_screen.dart`, deliberately left unconstrained — it's the "full title" destination) and via screen readers regardless of visual truncation (Flutter's default `Text` semantics announce the complete string, not the rendered glyphs). Two other sites (`profile_screen.dart`'s recent-completions row, `map_screen.dart`'s memory list item) were checked and already had this protection.
**Status:** **Fixed in code.** `flutter analyze` clean, `flutter test` regression clean (layout-constraint change, no new test mechanism applicable).

### A12. Mascot rendered below the progress bar, not above it — FIXED (I1)
**File:** `lib/features/home/screens/home_screen.dart` (`_TrailHeader`, new `_TrailProgress`)
**The gap:** The XP/streak stats block lived inside `_TrailHeader`, which rendered *before* `_TrailCompanion` in the scroll order — inverted from the intended Header → Mascot → Progress → Challenge → Trail hierarchy.
**What changed:** Split the stats pills + XP bar out of `_TrailHeader` into a new `_TrailProgress` widget, inserted between the mascot's sliver and the Today's Challenge card's sliver. Same data dependency (`currentUserProvider`, already app-lifetime — confirmed via this engagement's earlier `.autoDispose` audit that a second watch site is safe, not a new listener), same visuals, same always-visible behavior, same staggered fade-in entrance pattern — a position move, not a redesign.
**Status:** **Fixed in code.** `flutter analyze` clean, `flutter test` regression clean.

### A13. Locked leagues replaced their own emoji with a generic 🔒 — FIXED (K1)
**File:** `lib/features/leaderboard/screens/leaderboard_screen.dart` (`_LeagueChip`)
**The gap:** A7's opacity fix (above) greyed out locked leagues but line 342 still substituted `🔒` for `league.emoji` when locked, losing the league's own identity.
**What changed:** Always render `league.emoji`. The locked state is now communicated entirely through the existing `Opacity(0.4)` wrapper (visual) and the existing semantic label's `', locked'` suffix (non-visual) — never a substituted icon.
**Status:** **Fixed in code.** One-line change. `flutter analyze` clean.

### A14. No unique visual identity per league — FIXED (J1)
**Files:** `lib/models/league_definition.dart` (new `LeagueBackgroundMotif` enum, `backgroundMotif`/`backgroundIntensity` fields), `lib/features/leaderboard/widgets/league_background.dart` (new), `lib/features/leaderboard/screens/leaderboard_screen.dart` (wired behind `_LeagueHeader`/board)
**The gap:** All 8 leagues used flat color-tinted UI only — no distinct atmospheric background.
**What changed:** Added a static, low-opacity (0.12–0.16) `CustomPainter`-based background per league, using 3 reusable parameterized painter families (not 8 bespoke implementations) — `botanical` (Seedling/Sprout/Wildflower: soft leaf/petal silhouettes + radial glow), `peaks` (Forest/Mountain/Summit: layered triangular silhouettes, denser/smaller at low intensity, sparser/taller at high intensity), `sky` (Sky Trail/Aurora: drifting cloud blobs vs. sweeping abstract aurora ribbons). Each league's own `color` and a new `backgroundIntensity` (0.0–1.0, art-direction only, unrelated to gameplay) differentiate leagues within a family. Rendered behind the Rankings tab's header/board only (the separate Leagues tab uses an all-leagues ladder list with a structurally different layout — out of scope for this pass, not retrofitted).
**Status:** **Fixed in code.** `flutter analyze` clean. No automated tests (pure `CustomPainter`, consistent with how the home screen's own landscape painter has zero test coverage). Real-device contrast/readability confirmation remains UNVERIFIED.

### A15. Verification screen claimed "AI is reviewing your adventure" even when no AI ran — FIXED (M1)
**Files:** `lib/providers/camera_providers.dart` (`CameraVerifying.usingAi`), `lib/features/camera/screens/camera_screen.dart` (`_VerifyingView`)
**The gap:** The subtitle was shown unconditionally regardless of verification path — misleading for the honor-system (free-tier-gated or no-key-configured) and manual-override paths, where Gemini never runs.
**What changed:** `CameraVerifying` gained a `usingAi` field (defaults `true`, matching the real-Gemini path; explicitly `false` for both honor-system branches and for `override()`'s manual-submission path — computed *before* the first state-set so the text is never shown even momentarily). `_VerifyingView` now only renders the subtitle when `usingAi && stage == VerifyingStage.analyzing`; the existing, already-accurate stage messages ("Checking your adventure…", "Saving your adventure…", "Finalizing your adventure…") carry the rest of the flow without needing a redundant/inaccurate subtitle.
**Status:** **Fixed in code.** `flutter analyze` clean. 2 new tests (`camera_providers_test.dart`) cover the field's default and explicit-false construction; reaching `verify()`'s actual honor-system branch under test would need a fully mocked `CameraNotifier` (Gemini/Storage/repositories) — not attempted, consistent with this codebase's existing avoidance of heavy Firebase mocking in favor of pure-function extraction.

### A16. Web app still wore Flutter's default scaffold branding — FIXED
**Files:** `web/manifest.json`, `web/index.html`
**The bug:** `manifest.json`'s `name`/`short_name`/`description` were the literal Flutter scaffold defaults ("touchgrass"/"A new Flutter project."), and `background_color`/`theme_color` were `#0175C2` — Flutter's own Dart-blue brand color, not TouchGrass's forest green. `index.html`'s meta description was the same unedited boilerplate. On any web/PWA install, the OS splash and browser theme-color chrome rendered Flutter blue against a forest-green native app.
**What changed:** Updated both files to real TouchGrass branding and `#2E7D32`/`#EAF7EC` (forest green / light background, matching `AppColors`).
**Status:** **Fixed in code.** Static config only — no test applicable; verified by re-running `flutter build web --release` and confirming the built `manifest.json` reflects the change.

### A17. Snow-shower weather advice contradicted its own condition label — FIXED
**File:** `lib/models/weather_model.dart` (`WeatherModel.outdoorAdvice`)
**The bug:** WMO codes 83-86 ("Snow showers" per `condition`) were caught by the `weatherCode >= 80` check before reaching the `>= 71` snow check, so a snow-shower day showed "Rain showers — grab a jacket" advice directly under a "Snow showers" dialog title.
**What changed:** Added an explicit `weatherCode >= 83 && weatherCode <= 86` branch before the rain-shower check. Also added a distinct "Chilly — bring a light jacket" tier for 0–10°C non-precipitating days, which previously fell through to the generic "Good enough to go outside!" with no acknowledgment of the cold.
**Status:** **Fixed in code.** `flutter analyze` clean. `test/models/weather_model_test.dart` extended with a regression test for the 83/86 boundary and the new chilly-range case; one pre-existing test's expected string was updated to match the new (more accurate) chilly copy.

### A18. Email address was never shown on the Profile screen — FIXED
**File:** `lib/features/profile/screens/profile_screen.dart`
**The gap:** Email was displayed in Settings → Account but nowhere on Profile, despite Profile being the screen meant to answer "who am I."
**What changed:** Added an email line under the display name in the identity hero card, styled as a muted subtitle, shown only when `user.email` is non-empty.
**Status:** **Fixed in code.** `flutter analyze` clean. No dedicated widget test added — `profile_screen.dart` has no existing widget-test harness to extend, and building one from scratch for a single conditional `Text` was judged disproportionate; verified by code inspection only.

### A19. "View on Map" did nothing useful for completions with no location — FIXED
**File:** `lib/features/camera/screens/camera_screen.dart` (reward screen's primary action)
**The gap:** The button was always shown and enabled regardless of whether the just-completed challenge actually captured a location. Tapping it for a location-less completion silently dropped the user on the map with nothing to focus on — no crash, but no explanation either.
**What changed:** When `hasLocation` is false, the primary action becomes "Continue" (same visual weight, routes home) instead of "View on Map"; the previously-separate outlined "Continue" button is only shown alongside "View on Map" when there is a location, avoiding a duplicate button.
**Status:** **Fixed in code.** `flutter analyze` clean. No dedicated widget test — same reasoning as A18 (`camera_screen.dart`'s reward view has no existing widget-test harness; this is a straightforward conditional-render change).

### A20. A failed reflection submission forced the user to retype their caption — FIXED
**Files:** `lib/providers/camera_providers.dart` (`CameraFailure.caption`, `CameraCaptionStep.initialCaption`, `retryVerification()`, `submitCaption()`), `lib/features/camera/screens/camera_screen.dart` (`_CaptionView`)
**The bug:** `CameraFailure` only ever carried photo `bytes`, never the caption text the user had typed. Retrying after a submission-time failure (`submitCaption()` throwing) re-ran verification from scratch and landed back on a caption screen with an empty text field. Separately, the caption screen's close button discarded any typed text immediately with no confirmation.
**What changed:** `CameraFailure` gained a nullable `caption` field, populated at all three of `submitCaption()`'s failure sites. `CameraCaptionStep` gained a nullable `initialCaption` field; `retryVerification()` now carries the failed attempt's caption forward via a `_pendingCaptionOnRetry` instance field, consumed once by the next successful `CameraCaptionStep` this run produces. `_CaptionView` pre-fills its controller from `initialCaption` in `initState`, and its close button now shows a "Discard your reflection?" confirmation dialog whenever there's non-empty typed text (skipped entirely for the common empty-field case).
**Status:** **Fixed in code.** `flutter analyze` clean. 4 new tests (`camera_providers_test.dart`) cover both fields' defaults and explicit values via direct construction — the full `retryVerification()`/`verify()` round trip isn't exercised under test (same `CameraNotifier`-mocking limitation noted throughout this file).

### A21. "Export My Data" promised a download it never performed — FIXED
**File:** `lib/features/settings/screens/settings_screen.dart`
**The gap:** The row's subtitle read "Download a copy of your TouchGrass data," but the action only copies a plain-text stats summary to the clipboard — no file, no photos, no full challenge history. The dialog itself was already accurate ("Copy to Clipboard," an explicit included-fields list); only the outer row's subtitle over-promised.
**What changed:** Subtitle corrected to "Copy a summary of your stats to your clipboard"; icon changed from a download glyph to a copy glyph to match. A real file-based export (with photos) is a materially larger feature, deliberately not built this pass — flagged as a possible future item, not silently expanded.
**Status:** **Fixed in code.** Copy-only change, no test applicable.

### A22. No contextual explanation before any native permission prompt — FIXED
**Files:** `lib/widgets/permission_primer.dart` (new), `lib/widgets/app_shell.dart`, `lib/features/camera/screens/camera_screen.dart`, `lib/main.dart`
**The gap:** Camera, location, and notification permissions were all requested directly via the native OS API with zero prior explanation of why TouchGrass wants each one. Notification permission was additionally requested from a bare `main()` post-frame callback with no `BuildContext` and before the user had even signed in.
**What changed:** New `maybeShowPermissionPrimer()` shows a short, permission-specific explanation (exact copy: location — "TouchGrass uses your location to show local weather and save where your adventures happen."; notifications — "Get reminders when a new daily adventure is ready."; camera — "Use your camera to capture today's adventure.") once per permission, ever (tracked via `SharedPreferences`), immediately before the corresponding native prompt. Notification priming + the actual `NotificationService().initialize()` call moved from `main()` into `AppShell.initState` (now has a real `BuildContext`, and only fires once the user has actually reached the main app). Location priming gates the first read of `currentLocationProvider` in `AppShell.build`. Camera priming is called unconditionally at the top of `_requestAndInit()` (no-ops after the first time, so it's safe on the resume-after-Settings retry path too). All three permissions' actual request/denial-handling logic is unchanged.
**Status:** **Fixed in code.** `flutter analyze` clean. 3 new widget tests (`test/widgets/permission_primer_test.dart`) cover: correct copy shown per permission, never shown a second time for the same permission, and permissions tracked independently of each other.

### A23. Onboarding's page transition and indicator dots ignored Reduce Motion — FIXED
**File:** `lib/features/onboarding/screens/onboarding_screen.dart`
**The gap:** The companion's idle-float animation already correctly gated on `reducedMotionProvider`, but the `PageController.nextPage` swipe animation and the page-indicator `AnimatedContainer` did not — both always animated regardless of the setting, inconsistent with the rest of this screen and the rest of the app.
**What changed:** Both now use `Duration.zero` when `reducedMotionProvider` is true. Also added one clause to page 3's subtitle mentioning the journal, which the onboarding copy previously never named at all despite it being one of the product's five core pillars.
**Status:** **Fixed in code.** `flutter analyze` clean. No new test — this mirrors the existing (untested) Reduce-Motion gating pattern already used elsewhere in the same file/widget.

### A24. Reduce Motion didn't inherit the OS-level accessibility setting outside the ambient MediaQuery — FIXED
**File:** `lib/providers/settings_providers.dart` (`osReducedMotionProvider`, `reducedMotionProvider`)
**The gap:** `main.dart` already correctly composed the OS-level "Reduce Motion" signal with TouchGrass's own in-app toggle into the ambient `MediaQuery.disableAnimations` (via `combinedReducedMotion`) — but that composition only reached widgets that read `MediaQuery.of(context)`. All ~30 call sites across the app that instead read `reducedMotionProvider` directly (nearly every `AnimationController` in the app) only ever saw the in-app toggle, silently ignoring a user's OS-level Reduce Motion setting unless they *also* separately found TouchGrass's own Settings screen.
**What changed:** `reducedMotionProvider` itself now combines both signals, via a new `osReducedMotionProvider` that bridges `WidgetsBinding.platformDispatcher`'s accessibility-features-changed callback into Riverpod (providers have no `BuildContext`/`MediaQuery` of their own). This is a single-point fix — none of the ~30 consuming call sites needed to change, since they all already read `reducedMotionProvider`.
**Status:** **Fixed in code.** `flutter analyze` clean. The underlying `combinedReducedMotion` pure function already has test coverage (`test/core/accessibility_prefs_test.dart`); the new provider-level wiring itself isn't separately unit-tested (touches `WidgetsBinding.platformDispatcher`, which is an integration concern, not a pure function).

### A25. Journal was undiscoverable — buried inside Map as a secondary tab — FIXED (partial, by design)
**Files:** `lib/features/home/screens/home_screen.dart` (`_JournalShortcut`), `lib/providers/map_providers.dart` (`pendingMapTabProvider`), `lib/features/map/screens/map_screen.dart` (`initState`), `lib/features/map/screens/map_screen.dart` (`_JournalTile` card-shell styling)
**The gap:** The adventure journal — one of the product's five named core pillars — was only reachable via a pill-tab switcher one screen inside Map, with no entry point from Home. Journal list entries were also plain, undecorated list rows, not visually "collectible."
**What changed (explicit product decision — see conversation):** Rather than promoting Journal to a 6th bottom-nav destination (a larger, harder-to-reverse IA change touching every screen that embeds the app shell), added a persistent "Your Adventure Journal" shortcut card to Home, between Today's Challenge and the trail. Tapping it sets a new `pendingMapTabProvider` and navigates to the Map screen, which now reads that provider in `initState` to open directly on its Journal tab (index 1) instead of the default Map tab — same consume-once-and-clear pattern as the existing `pendingMapFocusProvider`. Separately, `_JournalTile` now renders inside a bordered, shadowed card shell (matching the design language already used for achievement cards) instead of a bare padded row.
**Status:** **Fixed in code.** `flutter analyze` clean. No new test — both changes are structural/visual, consistent with this codebase's existing lack of coverage for pure layout/navigation-wiring changes of this kind.

### A27. Leaderboard loaded any URL as another user's profile photo — FIXED IN THE APP, RULES FIX PENDING (Phase 5, N-6)
**Files:** `firestore.rules` (`isValidNewProfile`, `isProfileEdit`: any string ≤ 2048 accepted as `photoUrl`), `lib/features/leaderboard/screens/leaderboard_screen.dart` (`_Avatar`)
**The bug:** A user could set their `photoUrl` to any address; every signed-in user viewing that league then fetched it, revealing their IP address and device to whoever runs that server, or seeing any image.
**Reproduction (emulator):** update `users/{uid}` with `photoUrl: 'https://x.test/a.png'` and sync the mirror — both writes are allowed.
**Status:** The app now loads other users' photos only from this app's Storage bucket (`user_avatars/`) or `*.googleusercontent.com`, otherwise it shows initials (`lib/core/utils/avatar_url.dart`, 16 tests). Older app versions are still exposed until the rules are tightened — proposal in `REMEDIATION_CHECKLIST.md` → Phase 5 → N-6 (needs a production check of the Google `picture` token claim first).

> **Update 2026-10-19 (Phase 6):** rules fix implemented and emulator-tested (35 cases; reverting to the old rule fails 20). `isAllowedProfilePhoto` accepts only `null`, the owner's own `user_avatars/{uid}.png` in `touchgrass-today.firebasestorage.app`, or exactly the `picture` claim of the caller's verified ID token; sign-up now stores that claim, so legitimate Google sign-up passes. Existing stored URLs stay readable (no forced migration; read-only inventory in `functions/src/ops/profilePhotoInventory.ts`). **Not deployed**: older app versions stay exposed until the rules are published (runbook §7 stage 1).

### A28. Account deletion said "not deleted" after a timeout, when it might have been — FIXED (Phase 7A)
**File:** `lib/services/account_deletion_service.dart`. On `unavailable` / `deadline-exceeded`
the app said "your account was not deleted", but the request may already have reached the
server and finished. It now says it couldn't confirm the result and that retrying is safe
(deletion is idempotent). Tested in `test/repositories/commit_completion_test.dart`.

### A29. Uploads could carry location data appended after the photo — FIXED LOCALLY (Phase 7C)
**Files:** `lib/core/utils/image_metadata.dart`, `functions/src/ops/jpegMetadata.ts`. The "lossless"
JPEG path removed header metadata but copied everything from the image data to the end of the file.
Phones append a second (MPF) image with its own EXIF/GPS, motion-photo video or vendor data after
the image's end marker, and APPn segments can sit between progressive scans. Stripping now walks every
segment and stops at the end marker. The primary image's compressed data stays byte-identical.
5 new Dart tests failed before the fix; TS unit and emulator tests cover the operator tool. Ships with
the next web build (H-1).

### A30. Final `storage.rules` let any signed-in user list every profile photo — FIXED LOCALLY (Phase 7C)
`match /user_avatars/{fileName} { allow read: … }`: `read` includes `list`, which enumerates every
uid that set a photo (the same defect Phase 7B fixed in the interim rules). Now `allow get`.
Emulator: the pre-fix file listed avatars, the fixed file denies. A release gate
(`firestore-tests/test/storage_release_parity.test.mjs`) runs the same cases against the final and
interim rules and pins the exact set of grants. Not deployed (S-2, coordinated release).

### A31. Photo download links could reach crash reports — FIXED LOCALLY (Phase 7C, hardening)
On mobile, `FlutterError.onError` sent unhandled errors to Crashlytics, and Flutter's image-load
errors contain the full URL, **token included**. Every current photo widget handles its own errors,
so this was latent. Tokens are now redacted in `main.dart`'s handlers and in `CrashReporter`
(`lib/core/utils/secret_redaction.dart`, 5 tests). Profile photos are also sanitised at the upload
boundary now (`sanitizeProfilePhoto`).

### A32. App and store copy promised privacy and AI behaviour that doesn't exist — FIXED LOCALLY (Phase 7D)
- "Challenge photos, which only you can see" (they are delivered by bearer links).
- "Delete Account deletes everything" (analytics, crash and log data are kept, and deletion isn't deployed).
- Onboarding: "our AI will verify your completion".
- Terms of Service: photos "may be used to improve AI verification".
- An "AI Verdict" label, and a Journal "AI Verified" badge as the default for entries with no recorded method.
- Camera and help text: "verify".
- `STORE_LISTING.md`: AI verification and "challenges powered by AI".

AI is disabled and challenges come from the seed library. All of it was corrected to describe what the code does
(`PHASE_7D_PRIVACY_DISCLOSURE_MATRIX.md`). Regression tests in `privacy_copy_test.dart` and
`adventure_memory_model_test.dart`. Nothing published.

### A26. "Start Challenge" could get permanently stuck unresponsive after an interrupted navigation — FIXED (hardening, not confirmed as the reported cause)
**File:** `lib/features/home/widgets/todays_challenge_card.dart` (`_StartButtonState`)
**The gap:** The tap handler set a `_navigating` guard to `true` before pushing the camera route, then reset it to `false` only on the line immediately after `await context.pushNamed('camera')`. If that navigation was ever interrupted (a route error, certain back/forward sequences on web) rather than resolving normally, the reset line would never run — leaving `_navigating` stuck `true` and the button silently unresponsive to every future tap, with no visible error.
**What changed:** Wrapped the `pushNamed` call in `try { ... } finally { ... }`, so the guard is reset unconditionally regardless of how the navigation attempt ends.
**Status:** **Fixed in code.** `flutter analyze` clean, `flutter test` 231/231. Reported in response to a live user bug report ("unable to click Start Challenge"); this closes the one plausible code-level way that specific symptom could happen, but wasn't reproduced in this environment (no browser access) so it isn't confirmed as *the* cause — see the paired Gemini-key finding below, which is confirmed and likely explains the second symptom reported alongside it.

---

## CATEGORY B — Needs action outside Claude Code's reach first

### B1. Gemini photo verification can be spoofed — no server-side re-check — CODE WRITTEN + UNIT TESTED, NOT DEPLOYED

> **Update 2026-10-17 (remediation Phases 1 and 3):** client-side Gemini verification was removed entirely (Phase 1), so there is no on-device AI verdict left to spoof; every completion is honor-system and says so. Server-side verification remains **deferred by owner decision** (Phase 3). Before it could be deployed, the gaps listed in `AI_VERIFICATION_PLAN.md` (Journal entry in the same transaction, fixed photo path, location setting, App Check) must be closed.
**Files:** `lib/services/gemini_service.dart:33-104` (still the live path); `functions/src/index.ts` + `functions/src/rewards.ts` (the real fix); `lib/services/challenge_verification_service.dart` (client-side abstraction, also not adopted yet)
**The bug:** Verification runs entirely on-device. A modified client can fabricate `VerificationResult(matches: true, confidence: 0.95, ...)` and skip the real Gemini call, then still call the ordinary reward-write path.
**What changed this pass:**
- Found and fixed a real logic gap in the Cloud Function: `weeklyXp` was never incremented or reset (only carried through unchanged), which would have silently broken the weekly leaderboard for anyone completing challenges through it. Ported the exact Monday-boundary reset logic from `awardCompletionRewards`.
- Extracted all pure reward/entitlement/validation/response-parsing logic into `functions/src/rewards.ts` (no Firebase imports) and added `functions/src/rewards.test.ts` — **49 tests** (up from 32; also extracted and tested `isOwnedStoragePath`, `parseVerifyRequestData`, and `isQuotaExhausted`, which used to be inline, untested logic in the handler), run via `npm test`, genuinely executed using Node's built-in test runner. No emulator or credentials needed. The `onCall` handler's own control flow (auth/Firestore reads/transactions) remains genuinely untestable here — it needs either the Firestore emulator (blocked, no Java 21) or a real dependency-injection refactor risky to make unverified; not attempted this pass.
- Built `lib/services/challenge_verification_service.dart`: a real `ChallengeVerificationService` interface with two implementations. **This pass added fail-closed/dev-only-flag semantics per an explicit security-hardening request:**
  - `LocalGeminiVerificationService`'s constructor now throws `StateError` (unconditionally, not via `assert` — asserts are stripped from `--release` builds, which is exactly the mode production ships in, so an assert would have silently done nothing in the case that matters) if `EnvironmentConfig.isProduction` is true. A production build (`--dart-define=ENVIRONMENT=production`) cannot instantiate the insecure local path at all.
  - `challengeVerificationServiceProvider` branches on that same flag: non-production (today's actual `ENVIRONMENT=staging` testing deploy) resolves to Local, unchanged; production resolves to `RemoteVerificationService`.
  - `RemoteVerificationService` is fail-closed by construction — every code path either returns a real server-verified acceptance or throws; there is no fallback to local/insecure verification anywhere in it. Broadened its error handling so a raw network failure (not just a `FirebaseFunctionsException`) still surfaces as a friendly error instead of an unhandled platform exception.
  - **No production build has ever been made from this repository** (only development and `ENVIRONMENT=staging`), so none of this is active in the currently-deployed `touchgrass-today.web.app` — confirmed deliberately: I asked before implementing this, since defaulting to Remote today would have broken challenge completion entirely on that live testing site with the Cloud Function still undeployed. Local stays the practical default until you deploy the function and start building with `ENVIRONMENT=production`.
  - **Still not wired into `CameraNotifier`** — its caption-entry step sits *between* verification and reward, which doesn't fit this function's atomic verify+reward contract without a real UX decision (caption before vs. after). Left for a dedicated follow-up rather than decided silently — see `functions/README.md`.
- Achievement unlocking still not ported (documented, bounded-risk gap — see `functions/README.md`).
**What is still not verified:** never deployed or run against live Firestore/Storage/Gemini — no Blaze billing on this project, no way to test that here.
**Why Claude Code can't close this alone:** Deploying requires your Blaze billing decision + your `firebase functions:secrets:set` action — both explicitly external.
**Status:** Code complete, unit-tested (49/49), fail-closed production semantics in place; deployment and client cutover remain, in that order.

### B2. Gemini API key is embedded in the client — mobile and web

> **Update 2026-10-17 (Phase 3):** the owner reports that the exposed key was **revoked** on 2026-10-17. This is owner-reported and not independently verified; a clean bundle scan is not proof of revocation. The deployed bundles still contain the old key string until they are redeployed.
>
> **Update 2026-10-17 (remediation Phase 1, see REMEDIATION_CHECKLIST.md):** the app no longer reads `GEMINI_API_KEY` at all. The client Gemini code and the `google_generative_ai` package are removed; challenges are template-only and AI verification is off for every tier. Even a build given `--dart-define-from-file=secrets.json` no longer embeds the key: a canary build proved this, and `tool/check_web_bundle_secrets.mjs` gates every web build. **Do not rebuild with `secrets.json` as described below.** The **already-deployed** bundles on both domains still contain the old key until they are redeployed, and the old key was confirmed **still active** on 2026-10-17. Rotation is external action X-1.
**File:** `lib/core/config/environment_config.dart:10-11`, compiled in via `--dart-define=GEMINI_API_KEY=...`
**The bug:** The key is a literal constant in the compiled output. On mobile, extraction requires decompiling the APK/IPA. On the web build, it requires nothing more than opening Chrome DevTools' Network tab or viewing the compiled JS source.
**Who it affects:** You (financially/quota-wise) if the key is scraped and reused elsewhere.
**Why Claude Code can't close this alone:** Same root fix as B1 — closes automatically once the client is cut over to the (now-written, not-yet-deployed) Cloud Function, since production builds would then never need `GEMINI_API_KEY` at all. Until then, apply **API key restrictions** in Google Cloud Console (HTTP referrer restriction for the web key, Android/iOS app restriction for the mobile key) as a stopgap.
**Status:** Not fixed — same B1 dependency chain (deploy → verify → decide the caption-step UX → cut over → stop passing the key to release builds).

**Finding + resolution (in response to a live "verification error" bug report):** Inspected `secrets.json`'s `GEMINI_API_KEY` (length/prefix only, never printed) and initially flagged it as suspicious — 53 characters starting with `AQ.A`, not the `AIzaSy...`/39-char shape I expected from the Generative Language API. That assumption turned out to be wrong: after the user supplied a replacement key in the same `AQ.A.../53-char` shape, a direct `GET https://generativelanguage.googleapis.com/v1beta/models?key=...` request returned **HTTP 200** with a real model list including `gemini-2.5-flash` (the exact model this app calls) — confirming this key format is valid and the key itself is live and authorized. Rebuilt (`flutter build web --release --dart-define-from-file=secrets.json`) and redeployed; new bundle hash-verified live (`01933533f62630b2feb2c0712f23c9bea901d2f9fdfaed4df44068bbdf5ca9da`). If real-Gemini verification failures for a `premium`/`admin_test` account continue after this, the key is no longer the suspected cause — worth re-checking Google Cloud Console quota/billing on that key instead.

### B3. Sign in with Apple doesn't work on the web build
**File:** `lib/services/auth_service.dart` (`signInWithApple()`, `reauthenticateWithApple()`), `lib/features/auth/screens/login_screen.dart` (`_showAppleButton`)
**The bug:** `sign_in_with_apple`'s web flow requires a registered Apple **Service ID** and redirect URI in your Apple Developer account, which doesn't exist yet. I already fixed the *crash* this caused (the button is now hidden on web, and a clear error is thrown instead of a raw platform exception if reached via account-deletion reauth) — but the underlying capability is still genuinely missing.
**Who it affects:** Any user who originally created their TouchGrass account via "Sign in with Apple" on iOS — they currently cannot sign in, or delete their account, from the web version at all.
**Why Claude Code can't close this alone:** Registering a Service ID + redirect URI requires your paid Apple Developer account and manual configuration at developer.apple.com. I can wire up the remaining `webAuthenticationOptions` code the moment you have those two values.
**Status:** Crash mitigated; underlying feature gap remains, external-blocked.

### B4. Background push notifications don't work on the web build at all — CLIENT PLUMBING READY, KEY STILL NEEDED
**File:** `web/firebase-messaging-sw.js`; `lib/services/notification_service.dart:17-25`; `lib/core/config/environment_config.dart` (`fcmVapidKey`)
**The bug:** Web push requires a VAPID key (Firebase Console → Project Settings → Cloud Messaging → Web Push Certificates) passed to `FirebaseMessaging.instance.getToken(vapidKey: ...)`. Neither exists yet. Foreground notifications (app tab open and focused) still work; anything else — closed tab, backgrounded tab — silently does nothing.
**What changed this pass:** `getToken()` now accepts a VAPID key sourced from `AppConstants.fcmVapidKey` (`String.fromEnvironment('FCM_VAPID_KEY', ...)`), passed only on web. With no key defined (today's state), behavior is byte-for-byte identical to before — still returns `null` on web without calling the SDK. Once you have a real key, `flutter build web --dart-define=FCM_VAPID_KEY=<key>` is the only remaining step — no further code changes.
**Who it affects:** Any web user who isn't actively looking at the tab when a challenge/streak reminder would fire.
**Why Claude Code can't close this alone:** Generating the VAPID key is a Firebase Console action only you can perform.
**Status:** Client-side plumbing complete; still blocked on you generating the key (this remains genuinely untested against a real browser either way).

### B5. Google Maps JavaScript API key's restriction status is unverified
**File:** `web/index.html` (key is hardcoded directly in the script tag, already live)
**The bug:** I can see the key is present and functional, but I cannot check from the repository whether it's HTTP-referrer-restricted in Google Cloud Console. If it isn't, anyone who copies it from view-source can use it from any site, against your quota.
**Who it affects:** You, financially, if unrestricted and scraped.
**Why Claude Code can't close this alone:** Purely a Google Cloud Console setting — I have no access to check or change it.
**Status:** Unverified — needs a 2-minute check on your end (Console → Credentials → this key → Application restrictions → HTTP referrers).

> **Update 2026-10-19 (Phase 7A):** compared by hash (never printed), the SAME key (`#97425825`)
> is used by `web/index.html`, was hard-coded in `ios/Runner/AppDelegate.swift`, and is the
> Android `MAPS_API_KEY` in `local.properties`. A key carries only one kind of application
> restriction, so it cannot be locked down for all three. The iOS key now comes from the
> git-ignored `ios/Flutter/MapsApiKey.xcconfig` via `Info.plist` (`GMSApiKey`); release builds
> stop without that file; `tool/check_firebase_config.mjs` flags a shared key. Owner steps:
> one restricted key per platform, then restrict `#97425825` to the web sites
> (`PHASE_7A_RELEASE_RUNBOOK.md` §9). Restriction status itself is still unverified.

### B6. iOS Firebase bundle ID mismatch, AND a separate Android Firebase-config mismatch — XCODE ID FIXED, FIREBASE CONFIG FILES STILL EXTERNAL
**Files:** `lib/firebase_options.dart:68,78` (`iosBundleId: 'com.example.touchgrass'`, unchanged — see below); `ios/Runner.xcodeproj/project.pbxproj` (`PRODUCT_BUNDLE_IDENTIFIER`, **now `com.touchgrass.app`, fixed this pass**); `android/app/google-services.json:12,37` (`com.example.touchgrass`, unchanged) vs. `android/app/build.gradle.kts:36` (`applicationId = "com.touchgrass.app"`)
**The bug (iOS):** The Firebase iOS app config was generated against the placeholder bundle ID `com.example.touchgrass`. There is also **no `ios/Runner/GoogleService-Info.plist` in the repository at all** — iOS has no Firebase config file checked in, not just a wrong one.
**What changed this pass:** Updated the Xcode project's `PRODUCT_BUNDLE_IDENTIFIER` (all 3 build configs, Runner + RunnerTests) from `com.example.touchgrass` to `com.touchgrass.app` — this is a plain local project-file edit, needs no external credentials, and RELEASE_GUIDE.md already establishes `com.touchgrass.app` as the unambiguous intended production identifier. **Deliberately did NOT touch `lib/firebase_options.dart`'s `iosBundleId`** — that field is tied to a specific Firebase-registered app (same `appId`/`apiKey` as today), and changing just the bundle-ID string without a real matching registration/plist would misrepresent a Firebase configuration that doesn't actually exist, which is exactly the kind of fabrication this project's standing rules forbid. Net effect: Xcode's bundle ID and Firebase's registered bundle ID are now *intentionally* out of sync until you complete the external step below — this is a necessary, temporary, and correctly-flagged state, not an oversight.
**The bug (Android):** `build.gradle.kts` already builds with `applicationId = "com.touchgrass.app"`, but `google-services.json` (the actual Firebase config bundled into the app) still declares `com.example.touchgrass`. This is a real, live mismatch today, not just a future-rename item — it can cause Firebase/Google Sign-In package-name validation failures on Android release builds right now.
**Who it affects:** Every iOS user (blocks sign-in entirely, and there's no config file to even attempt a build with Firebase iOS support). Potentially every Android release-build user too, depending on how strictly Google Sign-In validates the package name against `google-services.json`.
**Why Claude Code can't close this alone:** Both require registering apps with the correct ID in the Firebase Console and downloading new config files (`GoogleService-Info.plist` for iOS, `google-services.json` for Android) — genuine external account actions.
**Status:** iOS Xcode identifier fixed in code this pass. Both platforms still need their Firebase Console registration + config file download — external blocker, unchanged.

> **Update 2026-10-18 (remediation Phase 4, X-5):** confirmed read-only with `firebase apps:list`: the project has exactly one Android app (`com.example.touchgrass`) and one iOS app (bundle `com.example.touchgrass`). Nothing is registered for `com.touchgrass.app`, so **Android stays BLOCKED** until the owner registers it and supplies the real config files. Exact steps, including this machine's debug SHA fingerprints, are in `REMEDIATION_CHECKLIST.md` → Phase 4 → Android. A diagnostic build in a throwaway copy, with the package patched in the copy only, found and fixed three more blockers: geocoding_android compileSdk 33, missing R8 rules, and the Crashlytics mapping upload. Debug and release then built successfully. Release signing still falls back to the debug key (B7 / X-6).

> **Update 2026-10-19 (Phase 7A):** re-checked read-only — still only `com.example.touchgrass`
> on both platforms, no SHA fingerprints. `node tool/check_firebase_config.mjs --live` now checks
> local files AND live registration (read-only `apps:list` / `apps:android:sha:list`), never
> printing keys; 16 tests. Status unchanged: OWNER ACTION (runbook §1).

### B9. Android `MainActivity.kt` was compiled under the old package, orphaned from the app's actual namespace — FIXED, BUILD PROGRESS CONFIRMED (5th pass)
**Files:** `android/app/src/main/kotlin/com/touchgrass/app/MainActivity.kt` (new location); `android/app/build.gradle.kts:26,36` (`namespace`/`applicationId`, both already `com.touchgrass.app`)
**The bug (newly discovered second pass, not previously documented anywhere):** `build.gradle.kts` already set `namespace = "com.touchgrass.app"`, but the actual `MainActivity.kt` file still lived at `android/app/src/main/kotlin/com/example/touchgrass/MainActivity.kt` and declared `package com.example.touchgrass`. `AndroidManifest.xml`'s `android:name=".MainActivity"` is a relative reference resolved against the Gradle `namespace` at build time — meaning it would resolve to `com.touchgrass.app.MainActivity`, a class that didn't exist, while the real compiled class was `com.example.touchgrass.MainActivity`. This is a genuine defect independent of the already-known `google-services.json` mismatch (B6) — it's a pure Gradle/Kotlin namespace bug, not a Firebase config issue, and it very likely would have broken the Android build or app launch entirely, regardless of Firebase.
**What changed:** Moved the file to `android/app/src/main/kotlin/com/touchgrass/app/MainActivity.kt` and updated its `package` declaration to `com.touchgrass.app`, matching the Gradle namespace. Removed the old file and now-empty directories.
**Status:** **Fixed in code.** `flutter analyze` clean (Dart-only, doesn't cover Kotlin). Across this engagement, `flutter build apk --debug` has now been attempted **four** times: two genuine Gradle-daemon JVM OOM crashes (default 8GB heap, then a temporary 2GB retry — `gradle.properties` confirmed restored afterward with no residual diff), one Dart VM native-assets crash unrelated to TouchGrass's own source (`objective_c` package build hook), and this 5th-pass attempt, which for the first time got **past both of those environment failure modes entirely** — Gradle ran for 125.6s and reached the `:app:processDebugGoogleServices` task before failing. It failed there with `No matching client found for package name 'com.touchgrass.app' in android/app/google-services.json` — exactly the pre-existing, already-documented B6 external blocker (the config file still declares `com.example.touchgrass`), not a new defect. This is genuine forward progress: the build no longer crashes on this machine's resource constraints, and the only remaining failure is external and already tracked. It still does **not** constitute proof that `MainActivity.kt` itself compiles cleanly — `processDebugGoogleServices` runs before Kotlin compilation completes in this task graph, so `compileDebugKotlin` was never reached in this run. Retry after replacing `google-services.json` (B6) to get a real signal on the Kotlin compile step.

### B7. Android/iOS release signing not yet configured
**Files:** N/A (keystore/provisioning don't exist in-repo, correctly gitignored)
**The bug:** No release keystore, no `key.properties`, no iOS provisioning profile exist yet — both platforms are still on debug/unsigned config.
**Who it affects:** Blocks any store submission until done.
**Why Claude Code can't close this alone:** Signing credentials must be generated and held by you; I should never generate or hold these myself.
**Status:** Documented in `RELEASE_GUIDE.md` Part 2; not started.

> **Update 2026-10-19 (Phase 6):** the debug-key fallback is **removed**. A release build without a complete `android/key.properties` (and the Maps key) now stops immediately and lists what is missing. Verified: the repo and a corrected-config copy both stop; the copy built with a throwaway test key, and `apksigner` confirmed the signer is that key, not the debug key. The upload key itself must still be created and backed up by you (runbook §3).

> **Update 2026-10-19 (Phase 7A):** `bash tool/test_android_gates.sh [--full]` re-proves the
> gates on a throwaway copy (missing / incomplete `key.properties`, bad keystore path, missing
> Maps key, malformed or wrong-package `google-services.json`, debug needs no signing) and, with
> `--full`, builds a test-key release and verifies signer, package, non-debuggable and no
> Crashlytics upload. The upload key itself is still an OWNER ACTION (runbook §2).
>
> **Update 2026-10-19 (Phase 5):** re-checked — still no `android/key.properties` and no keystore, so `--release` builds are signed with the **debug** key (fallback in `android/app/build.gradle.kts`). Owner steps (create, store outside the repo, back up, Play App Signing, add the release SHA fingerprints to Firebase) are in `REMEDIATION_CHECKLIST.md` → Phase 5 → 9. No signing material was created.

### B11. Photos uploaded by earlier app versions may still contain GPS metadata — NEEDS A SERVER-SIDE JOB (Phase 5, N-7)
**Files:** Storage `completion_photos/{uid}/…` (objects uploaded before the Phase 4 N-2 fix, i.e. by every released version)
**The bug:** Those photo files may carry EXIF/XMP GPS coordinates. "Remove saved locations" clears the location fields in Firestore but cannot change the photo files: re-uploading from the app would give each file a new download token and break the completion's stored, immutable `photoUrl`.
**Who it affects:** Only the photo's owner can read these files (storage.rules), so it is a data-minimisation and deletion-completeness issue, not public exposure.
**Status:** Proposal: a one-off Admin SDK job that strips metadata from each object while keeping its download token. Needs a new Node image dependency, a deploy and your approval. The in-app confirmation says photos from earlier versions may still contain location details.

> **Update 2026-10-19 (Phase 6):** implemented as an operator tool, without a new dependency and without a deploy: `functions/src/ops/` (`jpegMetadata.ts`, `photoMetadataJob.ts`, `opsCli.ts`). The inventory reads only each photo's header and reports counts; remediation strips metadata losslessly in place (keeping a minimal orientation tag for rotated photos), keeps the download token, content type and cache control, validates the replacement, writes only if the photo is unchanged, and keeps a server-only backup and a manifest. Dry-run by default; a real project needs explicit flags. 39 unit and 4 emulator tests (the saved download URL still works after rewriting). **Not run against production**, so the number of affected photos is still unknown (runbook §9).

> **Update 2026-10-19 (Phase 7A):** two defects fixed before any production use. (1) Backups
> were Storage *copies*, which inherit the original's download token — and a token URL bypasses
> the rules — so a backup could be opened with the photo's own URL token. Backups are now new
> objects with no token (emulator-proven: the original token is refused). (2) Backups lived at
> `metadata_backup/{run}/…`, outside the user's prefix, so account deletion missed them; they
> now live at `metadata_backup/completion_photos/{uid}/{run}/…` and `deleteAccount` removes
> that prefix. Remediation can resume (`--resume`), the CLI keeps cursors and names off stdout,
> and real-project runs must write a private `--out` file. Still **not run against production**.

> **Update 2026-10-20 (Phase 7C):**
> - **"Only the photo's owner can read these files" is not true of production:** the live Storage
>   rules expose them (B12), and harvested links stay valid (B15). So this is an exposure issue, not
>   only data minimisation.
> - Released versions could store GPS. The camera path's `encodeJpg` wrote the decoded EXIF back; the
>   gallery path uploaded the picked bytes unstripped.
> - Tool fixes:
>   - data appended after the image is removed and validated (A29);
>   - `--full-read` inventory counts it;
>   - a backup is deleted again if its overwrite doesn't happen (e.g. `deleteAccount` ran mid-run),
>     so no copy outlives its photo;
>   - remediation and token rotation share a lease;
>   - `--uid` allows a test-account canary.
> - Plan: `PHASE_7C_HISTORICAL_METADATA_RUNBOOK.md`; run it **after** token rotation. Still **not run
>   against production**.

### B12. LIVE Storage rules expose every user's completion photos to any signed-in user — NEW (Phase 7A), FIX READY, NOT DEPLOYED
**Evidence:** the live ruleset was exported read-only on 2026-10-19
(`tool/export_live_rules.mjs`). It matches no committed `storage.rules`:
`match /completion_photos/{userId}/{allPaths=**} { allow read: if request.auth != null; allow write: if … uid == userId; }`.
`firestore-tests/test/live_storage_exposure.test.mjs` runs it on the emulator: a second user can
read and list another user's photos, any file type can be stored, and avatar uploads are denied
(no rule). User IDs are visible as `leaderboard_public` document IDs, and older photos may carry
GPS (B11).
**Fix:** `deploy/interim/storage.interim.rules` closes cross-user access while still accepting
the live web app's `{timestamp}.jpg` uploads (14 emulator tests); the final `storage.rules`
replaces it in the coordinated release.
**Status:** ⚠️ PRODUCTION action awaiting authorization — runbook §5.2 (S-1). Also see the
privacy draft's M-1.

> **Update 2026-10-19 (Phase 7B):**
> - The live rules were re-exported read-only and are unchanged.
> - The emulator matrix shows the exposure is **wider than reported**: any signed-in user can also list the
>   `completion_photos` root, which enumerates every user's folder.
> - The interim rules had a defect: `allow read` on avatars, which includes `list`. It is fixed to `allow get`.
>   All 38 cases × 2 rulesets pass.
> - Even after deployment, **token URLs obtained while the rules were open stay valid**. Rules can't revoke them;
>   token rotation is a separate change.
> - Status: **NOT DEPLOYED**, awaiting authorization (`PHASE_7B_STORAGE_CONTAINMENT_RUNBOOK.md`).

> **Update 2026-10-20 (Phase 7C):**
> - Still live: a read-only export at 03:33Z showed the same exposed rules (`c5502223…`), so S-1 is
>   not deployed.
> - The interim file is unchanged (`630dc9a0…`), so the Phase 7B authorization question still
>   applies.
> - Correction to 7B: the live web app's account deletion never reaches Storage. It fails at Firestore
>   first, so the interim owner-delete grant is harmless but unused.
> - The final rules' avatar listing is fixed (A30).

> **Update 2026-10-20 (Phase 7D): CONTAINED.**
> - The interim rules were deployed with explicit authorization (`--only storage`, interim config, exit 0).
> - A read-only export at 04:30Z shows the live ruleset byte-identical to `deploy/interim/storage.interim.rules`
>   (`630dc9a0…`), with Firestore rules, functions and indexes unchanged.
> - Test-account smoke tests are pending (owner).
> - Links obtained before this remain valid until rotation (B15).

### B13. Production has no composite Firestore indexes; the app's completions query needs one — NEW (Phase 7A), CONFIG FIXED, NOT DEPLOYED
**Evidence:** `firebase firestore:indexes` (read-only) lists none; `firestore.indexes.json`
defines two, but `firebase.json` never referenced it, so no deploy would have sent them. The
query `completions where userId == uid orderBy completedAt desc` (home path stream, Journal
repair, and the first-completion streak lookup in `commitCompletion`) needs the composite index;
emulators don't enforce indexes, so tests never caught it.
**Fix:** `firebase.json` now references the file; `test/core/firestore_index_parity_test.dart`
pins the query shapes to the index. **Status:** ⚠️ PRODUCTION — runbook §5.3 (I-1), safe and
independent.

### B14. Account deletion doesn't revoke Sign in with Apple tokens — NEW (Phase 7A), OWNER DECISION
**The gap:** `deleteAccount` deletes the Firebase user but doesn't call Apple's token
revocation. Apple's account-deletion guidance asks apps using Sign in with Apple to do so
(**owner to verify the current requirement**). A possible fix — calling
`FirebaseAuth.instance.revokeTokenWithAuthorizationCode` with the authorization code from the
re-authentication step — needs testing on a device, so it was not implemented blind.


### B15. Photo links collected while the Storage rules were open stay valid — TOOL READY, NEEDS AUTHORIZATION (Phase 7C)
**Exposure:** a Firebase Storage download URL (`…?alt=media&token=…`) opens the photo for anyone
holding it, signed in or not. Rules are not evaluated (emulator-proven, P91). Under the live rules any
signed-in user could list every uid and call `getDownloadURL` on every challenge photo. Deploying S-1
stops new collection but **revokes nothing**. Whether anyone collected links is unknown (audit logs
probably off).

**Fix (tool, local):** `functions/src/ops/photoTokenRotation.ts`, run as
`opsCli.js photo-token-rotate`. It rewrites each completion photo with the same bytes and one new
token, then updates the owner's `completions` and `users/{uid}/memories` links. It is dry-run by
default, offers a `--uid` canary, skips uploads from the last 10 minutes, resumes without issuing a
second token, never recreates a deleted photo, and never outputs tokens or URLs. Emulator: the old URL
is refused, and the links open identical bytes.

**Order matters:** run it only **after** S-1 is live, or the new tokens can be collected again.
Profile-photo links are public to signed-in users by design and are not rotated (decision C4).

**Status:** plan and authorization checkpoints in `PHASE_7C_PHOTO_TOKEN_REMEDIATION_PLAN.md`.
**Not run.**


> **Update 2026-10-20 (Phase 7D):** the precondition (S-1 live) is now met.
> - The tool is now two-phase: add the new token → move the owner's links → remove the old token. A saved link
>   never points at a dead token (unit invariant + emulator).
> - The default removal is a metadata patch, so no photo bytes are rewritten.
> - Whether removal revokes old URLs **in production** is decided by the test-account canary, not assumed: the
>   emulator merges token lists, and the tool reports that as `verify-failed`.
> - **Blocked on:** authorization (AC-2 dry-run) and owner-provided credentials (no ADC on this machine).

> **Update 2026-10-20 (Phase 7E):**
> - **Production evidence:** the live smoke test showed an owner's existing token URL returns HTTP 200 without
>   sign-in, while a random token returns 403.
> - The tool gained dry-run aggregates and `--stop-before-remove` for the revocation experiment.
> - Still not run: needs authorization and owner credentials (`PHASE_7E_TOKEN_ROTATION_STATUS.md`).

> **Update 2026-10-21 (Phase 7F):**
> - The dry-run was found to write the shared lease document; it is now truly read-only (B17).
> - A controlled revocation experiment is scripted (`functions/src/ops/revocationExperiment.ts`) and rehearsed on the
>   emulators; it reports `revoked` only on repeated production evidence.
> - Still not run: owner credentials (ADC) and approvals AC-2, AC-3a, AC-3b (`PHASE_7F_TOKEN_ROTATION_RESULTS.md`).

### B16. A by-name `deleteAccount` deploy would have demanded the Gemini secret — FIXED LOCALLY (Phase 7E)
`functions/src/index.ts` also defined the disabled AI callable with `defineSecret("GEMINI_API_KEY")`.
firebase-tools resolves every declared param (and enables APIs for every function) **before** applying `--only`. So
`firebase deploy --only functions:deleteAccount` would have prompted for and created that secret in Secret Manager
(or failed non-interactively), and enabled the Secret Manager API.

The AI callable now lives unchanged in `functions/src/aiVerification.ts`, which isn't imported by the entry point.
`entryPoint.test.ts` pins "exports only `deleteAccount`, declares no params". AI stays disabled.

### B8. Store listings, privacy policy, and Data Safety form not yet created

> **Update 2026-10-17 (Phase 3):** the **in-app** privacy policy (`lib/core/constants/privacy_copy.dart`) now lists every data flow, including Open-Meteo, the platform geocoder, Firebase Analytics, Crashlytics and Performance, and the location setting. `STORE_LISTING.md` no longer says location is "never shared with third parties" (inaccurate: approximate location goes to Open-Meteo while the setting is on). Its Data Safety row now flags the precise-vs-approximate and "shared" classification for the owner to decide (X-11). A hosted policy URL is still missing (X-8).
**Files:** N/A
**The bug:** No public privacy policy URL, no App Store/Play Store listing content, no Play Data Safety form submitted.
**Who it affects:** Blocks store submission.
**Why Claude Code can't close this alone:** These are account/business actions in App Store Connect and Play Console.
**Status:** Not started.

---

### B17. The token-rotation "dry-run" wrote to production Firestore — FIXED LOCALLY (Phase 7F)
`opsCli.ts` acquired the shared lease `_ops/photoRewrite_lease` (a Firestore transaction that creates or updates the
document, and another on release) before every `photo-token-rotate` and `photo-metadata-remediate` run, **dry-runs
included**; `orphan-photos` did the same with its own lease. An "authorized read-only dry-run" would therefore have
written to production. Never run in production.

Now `leaseFor(args)` returns a lease only with `--execute`. Unit tests cover every command; an emulator test runs the
real CLI dry-run and asserts no `_ops` document exists and no object's generation or metageneration changed.

> **Update 2026-10-21 (Phase 7G):** every dry-run is now proven read-only, both by fakes that trap any write
> method (with an `--execute` control) and by an emulator snapshot of all documents and objects across all six
> dry-run variants. Writes now need `--execute` plus an explicit `--mode test-object-mutation|production-mutation`.
> Production is an exact allowlist (`touchgrass-today` / `touchgrass-today.firebasestorage.app`), and output goes
> only to new files under `ops-out/` (`PHASE_7G_DRY_RUN_SAFETY_AUDIT.md`).

### B18. Uploads could land after account deletion (≤1 h) — FIXED LOCALLY IN THE FINAL RULES (Phase 7F)
A second signed-in device keeps a valid ID token for up to an hour after `deleteAccount` revokes refresh tokens.
Firestore writes from the app already fail once `users/{uid}` is gone (the completion batch updates it), but Storage
uploads didn't check anything but the uid. The final `storage.rules` now require the uploader's profile document
(`hasProfile()`, evaluated last). Not live: it ships with S-2, and the first deploy grants Storage's service agent
Firestore read access. Residual: a hand-written client re-creating its own profile within that hour
(`PHASE_7F_LATE_UPLOAD_MITIGATION.md` §5).

> **Update 2026-10-21 (Phase 7G):** the residual case is closed locally. `deleteAccount` writes a server-only marker,
> `deletedAccounts/{uid}` (timestamps only), before it deletes the profile, and `firestore.rules` refuse to create a
> profile for a marked uid. Covered by the rules tests and the parity race sequence. Ships with R-1 + S-2.

### B19. The camera advertised AI photo verification ("Coming soon", "premium feature") — FIXED LOCALLY (Phase 7G)
After a photo uploaded, free-tier users saw "AI verification — Coming soon!" (screen readers heard "AI verification is a
premium feature, coming soon"). Every completion stored "Honor-system approved — AI verification is a premium feature.",
which Challenge details displayed. The caption step's button said "Share Adventure" although nothing is shared.

Now:
- the caption step says "Photo added · Add a note, then save it to your Journal", and the button says "Save to Journal";
- completions store "Completed on the honor system with your photo.", and legacy wording is never displayed;
- the legacy Journal badge reads "✓ Verified";
- the unused "AI Verification — Coming Soon" card is deleted;
- `test/core/ai_copy_regression_test.dart` scans `lib/` so the copy can't return.

AI photo verification remains disabled.

### B20. A deleted account's stale session could still create Firestore documents (≤1 h) — FIXED LOCALLY (Phase 7H)
Phase 7G blocked only profile re-creation. A device still holding the deleted account's ID token could still create a
daily challenge, a completion, a Journal entry, feedback or a username claim, and nothing would ever delete it. Also,
`deleteAccount` wrote its `deletedAccounts/{uid}` marker only after deleting completions, usernames and feedback.

Now:
- the marker is written first (right after session revocation);
- every client create rule in `firestore.rules` checks `accountNotDeleted()`;
- the marker counts only until its `expiresAt` (2 h), so an abandoned failed deletion can't block an account forever.

Tests: `firestore-tests/test/deleted_account_writes.test.mjs` (17) and the reordered `accountDeletion.test.ts`.
Not deployed.

### B21. Test suites could fail silently under Node 22 — FIXED (Phase 7H)
Node 22's test runner exits 0 and reports `fail 0` when a `describe()` callback throws while the suite is being built.
Every test in that suite is skipped without a trace. Found when a new suite failed this way.

Every package script now runs tests through `tool/strict_node_test.mjs`, which fails on any TAP `not ok` line;
`tool/test/dev_safety.test.mjs` pins this. Earlier phases' logs were not affected for the suites present now: the
current runs show no other `not ok`.

### B22. `npm run serve` / `npm run shell` in functions/ used the production project — FIXED (Phase 7H)
Both scripts used `.firebaserc`'s default project (`touchgrass-today`). `serve` started only the Functions emulator, so
the Admin SDK reached the REAL Firestore, Storage and Auth: calling `deleteAccount` locally would have deleted
production data.

Both now pass `--project demo-touchgrass-dev`, and `serve` also starts the data emulators. Pinned by
`tool/test/dev_safety.test.mjs`.

### B23. Account deletion showed no progress and no confirmation — FIXED LOCALLY (Phase 7H)
After the password prompt, the Settings screen looked idle for up to 5 minutes. The user could leave it, or start a
second deletion. On success, the app silently returned to sign-in.

Now a blocking, screen-reader-announced overlay is shown, back navigation is disabled, a second start is ignored, and
"Your account and the data saved with it were deleted." appears only after the server confirms.

### B24. The AC-1 inventory would have lost its results — FIXED LOCALLY (Phase 7H)
`ops-out/rotation/` did not exist, and the CLI writes `--out` only after every read: the first real run would have read
everything and then failed. Also:
- any folder named `ops-out` anywhere was accepted;
- a run without Application Default Credentials started anyway;
- the read-only file stored object paths (with uids) it doesn't need.

Now:
- `--out` must be inside this repository's `ops-out/`;
- the folder is created before any read;
- a missing ADC file is refused before anything is contacted;
- the read-only rotation file keeps only aggregates and hashed per-photo outcomes;
- errors show the class and a short code only.

## FIRESTORE SECURITY — field-by-field audit (analysis only, no rules changed this pass)

Full re-read of `firestore.rules` this pass. This is the field-by-field breakdown the master
brief asked for, to justify *why* nothing was tightened yet: **rules tightening is explicitly
sequenced to happen only after the Cloud Function reward flow is deployed and proven** (see
`functions/README.md`'s "Cutting the client over" section) — doing it now, with the function
undeployed, would just break the only working reward path for every user, for no security
benefit (the function isn't there to take over yet).

| Field | Who legitimately writes it today | Bound today | Real risk today |
|---|---|---|---|
| `xp` | `awardCompletionRewards`, `buyStreakFreeze` (decrease only) | Grow ≤ +4000/write, shrink freely | A1 stopgap: bounds a single write, not cumulative writes over time — the documented reason a full fix needs server authority, not a tighter per-write bound |
| `weeklyXp` | `awardCompletionRewards` | Grow ≤ +4000/write | Same class of risk as `xp` |
| `level`, `currentLeague` | `awardCompletionRewards` | Cross-checked against `xp` via `levelForXp`/`leagueForXp` on increase only | Sound *given* `xp` is trustworthy — inherits `xp`'s own risk |
| `streak` | `awardCompletionRewards` | `{unchanged, +1, reset-to-1}` only | Tightly bounded already; hard to abuse even today |
| `longestStreak`, `totalCompletions`, `rainyDayCount` | `awardCompletionRewards` | `{unchanged, +1}` only | Tightly bounded already |
| `achievements`, `frozenDates` | `awardCompletionRewards` | `hasAll()` — can only grow, never shrink | Client can still *add* a fabricated achievement ID today (cosmetic badge forgery only — no XP attached to a client-added ID beyond what `awardCompletionRewards` itself would have granted; genuinely low severity, matches `functions/README.md`'s existing assessment) |
| `entitlementTier` | Nobody (client) | Absent from `isValidUserWrite()`'s allow-list entirely | None — structurally un-client-writable by omission, not by convention |
| `aiUsage/{periodKey}.*` | Nobody (client) | `allow write: if false` | None — Admin-SDK-only |
| `fcmToken`, `displayName`, `photoUrl`, `username`, `email`, `settings` | Various (profile/settings screens, A2/A3 this pass) | No reward-shaped bound needed — these aren't reward fields | None new |

**Conclusion:** no field is *more* exploitable today than `KNOWN_BUGS.md` B1 already documents; the
one soft spot found (repeated-write XP creep past the single-write A1 bound) is the same reason B1
exists, not a new discovery. No rules were changed as a result of this audit.

## STREAK FREEZE PURCHASE — security evaluation (Phase 7)

`UserRepository.buyStreakFreeze` (`lib/repositories/user_repository.dart:331-369`) writes `xp`
(decrease only), `currentLeague` (recomputed), and `settings.streakFreezesOwned` (+1) directly from
the client, bounded by the same A1 rules above. Evaluated whether this creates a *new* exploit:

- It does not decrease `xp` in a way that could be exploited to *increase* it — the write always
  subtracts a fixed cost (`AppConstants.streakFreezeCostXp`).
- It does not touch `level`, so it can't be used to game the `levelForXp`/`leagueForXp`
  cross-check that only fires on `xp` increases.
- The only way it interacts with the already-known A1 weakness (repeated writes creeping `xp` up
  over time) is that a *spend* here would look identical, at the rules level, to a legitimate
  purchase — but spending can only ever move `xp` down, so it cannot be the mechanism of an
  inflation attack.

**Conclusion: no new exploit.** Building a dedicated secure callable Cloud Function for this purchase
now — before the main verification cutover exists — would mean standing up, testing, and maintaining
a second undeployed/unverified server endpoint in parallel with the first, for a feature that isn't
currently more exploitable than the reward-write path it already shares rules with. Recommendation:
bundle streak-freeze purchase into the same eventual server-authority migration as
`awardCompletionRewards`, not as a separate earlier effort.

### B10. New Hosting site `touchgrass.web.app` needs manual Firebase Console + Google Cloud Console follow-up
**Files:** `.firebaserc` (new `targets` block), `firebase.json` (`hosting` converted to a 2-target array: `today` → `touchgrass-today`, `main` → `touchgrass`)
**What changed:** Introduced `touchgrass.web.app` as a second Hosting site on the *same* `touchgrass-today` project (not a new project, not a rename) — created via `firebase hosting:sites:create touchgrass`, deployed via `firebase deploy --only hosting:main`. `touchgrass-today.web.app` was never redeployed or modified; both sites currently serve byte-identical builds (confirmed via matching SHA-256 hashes across the local build and both live sites).
**What still needs your action:**
1. **Firebase Console → Authentication → Settings → Authorized domains** — add `touchgrass.web.app`. Firebase Auth checks the *origin* of the page initiating `signInWithPopup`/`signInWithRedirect` against this allowlist; without it, Google Sign-In will fail specifically when the app is loaded from the new domain. The Firebase CLI has no command for this (only `auth:export`/`auth:import` for user data) and `gcloud` isn't available in this environment, so this couldn't be automated — genuinely Console-only.
2. **Google Cloud Console → Credentials** — if the Maps API key (`web/index.html`, `AIzaSy...4nJRnvbdzQ`) has an HTTP-referrer restriction, add `https://touchgrass.web.app/*` alongside the existing `touchgrass-today.web.app` entry. I have no Console/API access to check whether a restriction currently exists.
**Status:** Hosting-side migration code-complete and verified; both Console actions above are unautomatable from this environment and remain outstanding.

**Confirmed hit (2026-08-12):** user reported "Authentication Provider Error" signing in with Google specifically on `touchgrass.web.app` — this is exactly action #1 above, un-actioned. Firebase throws `auth/unauthorized-domain`, which `AuthService._mapFirebaseException` previously had no explicit case for, so it fell through to the generic `AuthException.providerError()` message ("Authentication provider error."), giving no hint at the real cause. Fixed the diagnosability gap in code — `lib/core/errors/app_exception.dart` gained `AuthException.unauthorizedDomain()` and `AuthException.providerDisabled()`, and `lib/services/auth_service.dart`'s `_mapFirebaseException` switch now maps Firebase's `unauthorized-domain` → the new clear message and `operation-not-allowed` → the provider-disabled message, instead of both silently collapsing into the generic fallback. Verified: `flutter analyze` clean, `flutter test` 231/231, rebuilt and redeployed to both `hosting:main` and `hosting:today` (new SHA-256 `9b6fa16a...c59ba96` matches on both live domains). **This code change does not itself fix sign-in** — the actual fix is still action #1 above (add `touchgrass.web.app` to Authorized domains in Console); until that's done, users on the new domain will keep hitting Google Sign-In failures, just with a clearer message now.

---

## UNVERIFIED — not confirmed bugs, listed separately on purpose

I have no physical device and no real browser session in this environment, so none of these
have actually been tested — they're open questions, not defects. Don't treat this list as
equivalent to Category A/B above.

- VoiceOver (iOS) / TalkBack (Android) real announcement behavior
- Real Dynamic Type rendering at 130%/150%/200% system font scale
- Physical touch-target feel on real hardware
- Camera capture (shutter, flash, flip, focus) on real hardware
- Google Maps rendering/marker clustering on-device and in-browser
- Network-loss/airplane-mode behavior mid-flow
- Push notification tap-to-navigate, once B4 is resolved
- Whether `permission_handler_html`'s web implementation genuinely supports camera/location permission types, or degrades silently for them (my Phase 1 web-audit claim that it had *no* web implementation was wrong — it exists — but I couldn't confirm from docs alone what it actually does for these specific permission types; the code fix that bypasses it on web is safe regardless, see the web-audit conversation for detail)
- Whether the existing streak-warning topic notification is intended as a broadcast-to-everyone reminder (fine as-is) or was meant to be personalized per user (A2 now captures the per-device token needed for this; actually sending a targeted message still needs server-side FCM Admin access — see A2/B1)
- Real rendering/feel of the new permission-primer dialogs (A22), the Home journal shortcut card and its navigation into Map's Journal tab (A25), and the new league-background/journal-card visual polish — all confirmed by code inspection and automated test where applicable, none confirmed in a real browser or on a real device this pass

---

*Last updated: this conversation (eighth pass, same session) — implemented an end-to-end user-journey
audit's approved plan (Parts 1-30 of a 31-part audit prompt covering first impression through
long-term retention). Nine new Category A fixes this pass: A16 (web app still wore Flutter's default
branding — manifest.json/index.html), A17 (snow-shower weather advice contradicted its own condition
label — genuine logic bug), A18 (email never shown on Profile), A19 ("View on Map" did nothing useful
for location-less completions), A20 (a failed caption submission forced a full retype, plus no
discard confirmation), A21 ("Export My Data" promised a download it never performed), A22 (no
contextual explanation before any of the three native permission prompts), A23 (onboarding's page
transition/indicator dots ignored Reduce Motion), A24 (Reduce Motion didn't inherit the OS-level
accessibility signal outside the ambient MediaQuery — fixed at a single provider-level point reaching
all ~30 existing call sites), A25 (Journal was undiscoverable from Home — added a shortcut card,
explicitly *not* a bottom-nav restructure, per a direct product decision). Also two minor
error-surface-consistency cleanups (`map_screen.dart`'s caption-save SnackBar and
`todays_challenge_card.dart`'s reroll handler now route through `ErrorService` instead of duplicating
its styling/fallback-message logic by hand). The audit itself found the large majority of the app —
onboarding, auth error handling, the camera capture UI, submission double-submit guarding, the reward
screen, offline handling, and the `ErrorService` layer — already matching or exceeding the target
experience described in the prompt; those findings are not repeated as bugs here. Full regression:
`flutter analyze` 0 issues, `flutter test` 231/231 (222 prior + 9 new: 2 weather boundary tests + 1
modified, 4 caption-preservation tests, 3 permission-primer widget tests), `npm test` 49/49 (Cloud
Functions untouched this pass), `npm run build` PASS, `flutter build web --release` PASS. `dart
format` run only on the files actually touched this pass (17 files, 8 needed reformatting), never
repo-wide. Deployment and post-deployment hash verification recorded below once complete. Explicitly
deferred, by design, not oversight: promoting Journal to its own bottom-nav tab (a materially larger,
harder-to-reverse IA change — the shortcut-card approach was chosen instead after asking), and actual
server-side push-notification sending (no Cloud Function anywhere calls `admin.messaging()` — this is
new backend feature work gated on the same Blaze-billing blocker as B1, not a client bug).*

*Previously (seventh pass, same session) — implemented all 6 confirmed UX gaps
from the prior pass's implementation plan: A10 (mascot tap-to-respond, E1), A11 (challenge title
overflow safety, G1), A12 (mascot/progress reorder, I1), A13 (league lock emoji fix, K1), A14 (league
backgrounds, J1), A15 (accurate verification copy, M1) — see each entry above for detail. Before
implementing, re-confirmed (not re-implemented) two items the plan had flagged as needing final
verification: profile photo upload (`settings_screen.dart`'s `_changeProfilePhoto` — gallery, native
camera, crop screen, compression, `_uploadingPhoto` loading state, `ErrorService` error handling, and
automatic UI refresh via the reactive `currentUserProvider` stream, all genuinely present) and journal
photo persistence (`memory_repository.dart` — idempotent `createMemory` via completion-ID document
keys, real-time first-page stream + paginated history, real Storage URLs, owner-scoped) — both
confirmed already fully correct, zero code changes made to either. Full regression: `flutter analyze`
0 issues, `flutter test` 222/222 (214 prior + 6 new `nextCompanionMessage` tests + 2 new
`CameraVerifying.usingAi` tests), `npm test` 49/49, `npm run build` PASS, `flutter build web --release`
PASS (195.7s), secret scan clean (only the known public Firebase Web API key present). Deployed to
`touchgrass-today.web.app` via `firebase deploy --only hosting`; verified via SHA-256 hash match that
the served `main.dart.js` is byte-identical to this pass's local build (not a stale prior deploy). No
browser-automation tooling is available in this environment, so the actual rendered/interactive
behavior of any of this pass's changes on the live site remains UNVERIFIED — only their presence in
the deployed bundle is confirmed, not their visual correctness.*

*Previously (sixth pass, same session) — independently re-traced code paths for
all 21 requirements per this pass's explicit "do not trust previous reports" instruction. Found one
genuine, if minor, gap: `WeatherModel.condition`/`outdoorAdvice` (the tap-the-weather-icon tip feature)
had zero test coverage despite being pure, boundary-heavy logic — added
`test/models/weather_model_test.dart` (16 tests covering every WMO code band, the temperature-only
branches, and the precipitation-overrides-temperature priority order), confirmed passing. Verified
`member_since.dart` already has strong boundary coverage (11 tests: singular/plural, month/year
anniversary boundaries, future-timestamp clock-skew safety) — no gap there. Re-ran the entire matrix
from a clean invocation: `flutter analyze` 0 issues (303.4s), `flutter test` 214/214 (198 prior +
16 new), `npm run build`/`npm test` 49/49, `flutter build web --release` PASS (226s). Secret-scanned
the web output for the `AIzaSy...` key pattern directly (not just an env-var-name grep) and confirmed
the one match present is the public Firebase Web API key (also present in `firebase_options.dart`
and `firebase-messaging-sw.js`, by design not a secret) — the separate Google Maps key
(`web/index.html`, B5) does not appear in the compiled JS at all, and `GEMINI_API_KEY`/
`FCM_VAPID_KEY` have zero matches. Re-ran `flutter build apk --debug` a second time this session with
corrected exit-code capture (the prior run's "exit 0" in a background-task notification was an
artifact of piping through `tail`, which swallows the real exit code — the actual result was always a
failure): reproduced the exact same clean failure at `:app:processDebugGoogleServices` on the B6
blocker, confirming the finding is stable and not a fluke. Grepped `lib/` and `functions/src/` for
TODO/FIXME/HACK — none found. No new bugs found in application logic; no regressions.*

*Previously (fifth pass, same session) — re-verified the full baseline
(`flutter pub get`, `flutter analyze` 0 issues, `flutter test` 198/198, `npm run build`, `npm test`
49/49) from scratch, tracing current code rather than trusting the fourth pass's report, per this
pass's explicit instruction. No regressions found; no new bugs found. Re-ran `flutter build web
--release` (266s this time, much faster than the fourth pass's 78-minute run — that run's slowness
is now confirmed as transient system load, not a persistent issue) and re-confirmed the output is
free of `GEMINI_API_KEY`/`FCM_VAPID_KEY`. Re-attempted `flutter build apk --debug` — see the updated
B9 entry above: this is the most informative Android build attempt yet, having finally gotten past
the environment-resource-crash failure mode entirely and reached a real, already-documented external
blocker (B6's `google-services.json` mismatch) instead. Spot-checked (via direct code read, not
re-summarized from memory) Member Since, sunrise/sunset theme logic, preferred-categories wiring,
journal photo model, category-color gradients, and Firestore/Storage/Cloud-Function security fields
— all confirmed intact and matching this document's existing claims.*

*Previously (fourth pass, same session) — re-verified the full baseline
(`flutter pub get`, `flutter analyze`, `flutter test`, `npm test`, `npm run build`), all clean, no
regressions from the prior pass. Ran `dart format --set-exit-if-changed .` and found 105 files with
formatting drift — deliberately only reformatted the 7 that are actually this session's own files
(`ai_feature_locked_card.dart` + 6 test files); the other ~98 are pre-existing drift from before
this engagement and were left alone rather than bundling an unrelated repo-wide reformat into this
diff. A quick provider-lifecycle spot-check (`.autoDispose` usage across `lib/providers/`) found no
issue — the app-lifetime `StreamProvider`s that lack `.autoDispose` (auth state, current user,
today's challenge, connectivity, foreground messages) are intentionally long-lived, not a leak.
No new bugs found this pass.*

*Previously (third hardening pass, same session) — A5/A6/A7 newly fixed: AI
verification is now actually gated behind the paid entitlement tier in the live camera flow (read
A5's "important consequence" note — this changes what the deployed testing site actually does for
every current free-tier user); mascot re-centered; leaderboard locked-league greyout + touch
target. `flutter test` now 198/198 (was 195). No rules/functions/hosting were (re-)deployed this
pass — the live site still reflects the previous pass's deploy, not these newest UI/gating changes,
until you redeploy.*

*Previously (second hardening pass, same session) — deployed the prior pass's
fixes to `touchgrass-today.web.app` (hosting only; no rules/functions deployed). New this pass: B9
(Android `MainActivity.kt` package/namespace bug — a genuine, previously-undiscovered defect, fixed
but unverified due to an environment memory constraint, see B9); iOS Xcode `PRODUCT_BUNDLE_IDENTIFIER`
corrected to `com.touchgrass.app` (B6, code-level only — Firebase config files still external);
Cloud Function tests expanded 32→49 (added `isOwnedStoragePath`/`parseVerifyRequestData`/
`isQuotaExhausted` extraction+coverage); `challenge_verification_service.dart` gained fail-closed
production semantics and a hard dev-only guard on the local path (B1) — confirmed with the user
before implementing, since defaulting to remote today would have broken the live testing site; a
field-by-field Firestore rules audit and a `buyStreakFreeze` security evaluation were completed
(both concluded: no new exploit, no rules changes needed yet). A1/A2/A3/A4 unchanged and still
intact. No rules were deployed and no external accounts were touched this pass either.*
