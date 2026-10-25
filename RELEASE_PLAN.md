# TouchGrass — release plan (web first)

**Prepared:** 2026-10-25.

This file covers the feature matrix, the defects and blockers, the cutover
and rollback plans, the approvals and costs, the retention proposal and the
mobile checklists. Nothing here has been executed in production.

**Evidence levels used below:** **U** unit/widget test · **R** rules test
(emulator) · **F** Functions emulator test · **B** real-browser journey
(Chrome, emulators) · **P** production-verified · **—** not verified.

## 1. Feature matrix (web)

| Feature | Expected behaviour | State | Evidence | Blocker for production |
|---|---|---|---|---|
| Email sign-up / sign-in | Account, username claim, profile with the typed name | Works; the name bug is fixed (Phase 8) | U, R, B | Final rules deploy |
| Google sign-in | Popup sign-in | Implemented; real "G" asset | U (repo), — | `touchgrass.web.app` may be missing from Auth authorized domains (X-3; unverified) |
| Password reset | Email link | Implemented | — | Not exercised in the emulators |
| Session restore, sign-out | Survives a reload; sign-out returns to sign-in | Sign-out and sign-in: works. Restore after a reload: unchanged production behaviour, **not browser-verified** (emulator builds deliberately don't keep the session, B32) | B (sign-out/in), — (restore) | Check on the smoke test (§4 step 5) |
| Route guards / direct URLs | Signed-out deep links go to sign-in | Works | B | — |
| Onboarding | 3 pages then home; no reminder prompt | Works | B | — |
| Daily challenge | Created on first visit; Day 1…N; reroll ≤ 3/day | Works | R, B | Final rules |
| Completion with photo | Upload (EXIF/GPS stripped), honor-system completion, Journal entry, XP, streak, leaderboard mirror in one batch | Works | U, R, B | **Final Firestore rules** (the live rules refuse the batch) |
| AI photo verification | Disabled; nothing claims verification | Correct | U, B | — |
| Journal / captions | Entry with note; caption editable | Works | R, B | Final rules |
| Feedback | Stored for the signed-in user (≤ 5/day) | Implemented | R, B | **Final rules** (no live rule) |
| Remove saved locations | Clears coordinates, place name and weather | Implemented | R, B | **Final rules** |
| Leaderboard | Top 30 of the league, server-ordered (Phase 8) | Implemented | U, R | **Composite index deploy** |
| Leaderboard opt-out | Removes the public entry | Implemented | R, B | — |
| Achievements / badges | Locked ones greyed with progress | Displays | B (visual) | — |
| Profile photo | Upload / replace (PNG, owner path) | Implemented | U, R | Final Storage rules + IAM |
| Weather | Shown only with a real reading (Phase 8) | Implemented | U | — |
| Map | Pins for Journal entries with location | Displays | B (visual) | Maps key restriction (B5) |
| Reminders / push | **Disabled**: no sender exists (Phase 8) | Honest | U | Needs a sender (Functions, Blaze) |
| Account deletion | Server-side, idempotent; marker first; progress; confirmed success | Works | U, F, R, B | **`deleteAccount` deploy** |
| Support contact | `toughpiprojects@gmail.com`, confirmed by the owner on 2026-10-25; shown in Help and in deletion errors | Implemented | U | Keep the mailbox monitored; use the same address in the store listings |
| Terms / Privacy | Readable from sign-in and Settings; wording aligned with behaviour | Prepared in the app | U | **Owner/legal approval** (D16, D17, D19, D20) |
| Wide screens | Phone-width column on desktop (Phase 8) | Implemented | U | — |

## 2. Defects fixed in Phase 8 (local; not deployed)

1. **Debug and dev runs used production.** All environments used
   `touchgrass-today`, and debug runs sent Analytics there. There is now an
   explicit, fail-closed environment selection, emulators by default in
   debug, and telemetry only in production.
2. **Email sign-up dropped the typed name.** Every account started as
   "Explorer".
3. **Reminder settings without a sender.** The app asked for notification
   permission, showed four reminder toggles and stored push tokens, but
   nothing sends reminders, and web can't receive them.
4. **A "Weather unavailable" placeholder** was shown without data.
5. **Wide screens:** grids stretched into tall, empty cards on desktop.
6. **Unverified support address.** `support@touchgrass.app` was presented as a
   working contact. It is replaced by the owner-confirmed
   `toughpiprojects@gmail.com`.
7. **Terms promise.** Terms #3 promised photos would "never" be shared
   publicly, and the Terms couldn't be read from the sign-in screen.
8. **Unbounded leaderboard read:** every view streamed the whole league.
9. **Logs held identifiers.** `deleteAccount` (and the dormant AI function)
   logged user ids and raw error messages.
10. **Unreadable trail.** Locked trail nodes were pale, and their day labels
    were unreadable over the dark landscape bands.
11. **Store listing:** an unsupported user-count claim (D15) and wrong league
    names.
12. **iOS:** declared an unused `fetch` background mode.
13. **"Remove saved locations" locked the app** (found in the browser run).
    The progress dialog never closed, because the wrong navigator was
    popped.
14. **Feedback "Send" was never enabled** on desktop web (found in the
    browser run).
15. **Settings switches had no accessible name** (found in the browser run).
    Screen readers announced "switch, on" without the setting's name.
16. **Emulator builds reached the real Auth service after a reload** (found
    in the browser run, B32). This is a development-safety defect. Emulator
    builds now fail closed and don't keep the session; production builds
    are unchanged.
17. **Challenge text said "Go outside and go outside and…"** for seeds
    whose action already goes out (B33).

## 3. Launch blockers

| Blocker | Why it matters | Who acts | Blocks |
|---|---|---|---|
| Old photo links open photos without sign-in | Privacy | Owner approves AC-1 → AC-2 → AC-3 | Web + mobile |
| Historical GPS unknown | Privacy | Owner approves AC-4/5 | Web + mobile |
| Live account deletion broken | Store policy, privacy law | Approve the `deleteAccount` deploy | Web + mobile |
| The live rules refuse the new client's core writes | Core feature | Approve the coordinated cutover (§4) | Web |
| Disclosure decisions D16, D17, D19, D20 | Legal | Owner/legal (`PRIVACY_INCIDENT_ASSESSMENT.md`) | Web + mobile |
| Firebase registrations `com.example.touchgrass` | Mobile builds | Owner (AC-8) | Mobile |
| Android signing, iOS build (Mac) | Store builds | Owner | Mobile |
| `touchgrass.web.app` in Auth authorized domains (X-3) | Google sign-in on that domain | Owner checks in the console | Web (final domain) |

## 4. Production cutover plan (not executed; each step needs its own approval)

**Why it must be coordinated:**
- The final Firestore rules refuse the legacy client's completion flow
  (`live_client_compat.test.mjs`).
- The live rules refuse the new client's completion, feedback and
  location-removal writes (`candidate_on_live_rules.test.mjs`).
- So both clients can't work at once. Plan a short maintenance window.

**Pre-flight (no production change):**
1. Check that the candidate artifact matches a reviewed commit, and that
   every suite above passes on it.
2. Run AC-1 (approved, waiting on ADC) and decide the disclosure questions.
3. Do a read-only check that billing is enabled (Blaze is required for
   Functions).

**Deploys, in order:**

| Step | Command | Effect on the legacy app |
|---|---|---|
| 1. Indexes (additive) | `firebase deploy --only firestore:indexes --project touchgrass-today` | None. Wait for READY (`firebase firestore:indexes`). |
| 2. Function | `firebase deploy --only functions:deleteAccount --project touchgrass-today` | None (the legacy client doesn't call it) |
| 3. Maintenance window: Firestore rules, then both sites immediately | `firebase deploy --only firestore:rules --project touchgrass-today`, then `firebase deploy --only hosting:today,hosting:main --project touchgrass-today` | Legacy tabs fail to complete challenges until they reload |
| 4. Storage rules + IAM grant (two separate approvals) | `firebase deploy --only storage --project touchgrass-today` (accept the IAM prompt only when approved) | Legacy uploads with timestamp names are refused, as intended |
| 5. Smoke test (needs its own approval) | One synthetic test account: sign up → complete → feedback → remove locations → delete account; check that the marker leaves no data | — |
| 6. Token rotation | AC-2 canary, then AC-3 staged | Irreversible by design |

**Step 3 note:** the cached Flutter service worker can keep an old build
alive in open tabs; the new build refreshes on the next load.

**Health checks after each step:**
- the Functions logs show no errors (they hold no ids now);
- the Firestore rules show no denial spike (Console → Rules monitoring);
- Hosting serves the expected `main.dart.js` hash.

## 5. Rollback

| Change | Rollback | Reversible? |
|---|---|---|
| Hosting (either site) | `firebase hosting:clone <site>:<previous version> <site>:live`, or Console → Release history → Roll back | Yes |
| Firestore / Storage rules | Redeploy the previous ruleset (saved in `ops-out/live-rules` / `ops-out/rollback`, and in Console history) | Yes. Data written meanwhile stays (extra fields are harmless to the legacy client) |
| `deleteAccount` | `firebase functions:delete deleteAccount --project touchgrass-today` | The function: yes. **Deleted accounts: no** |
| Indexes | Leave in place | Harmless |
| IAM grant | Remove the role binding | Yes |
| Token rotation | None: old links stop working | **No** (intended) |

## 6. Approvals needed (each separately)

- **Billing / cost:** Blaze on the dev project, so it gets Storage and
  Functions (or keep using the emulators).
- **Read-only production:** AC-1 (approved, waiting on your ADC
  confirmation); AC-4 metadata inventory; the Gemini-evidence count.
- **Deploys:** cutover steps 1–4, the IAM grant, the smoke test with a
  synthetic account.
- **Production data:** AC-2/3 token rotation; G-AV leftover test avatar.
- **Decisions:** a TTL policy on `deletedAccounts.expiresAt` (§8);
  publishing the Terms/Privacy text; any user notification; Maps key
  restrictions (B5); the Auth authorized domain (X-3).

## 7. Costs

- **Dev project:** free on Spark. Blaze would bill Storage, Functions and
  Cloud Build at small amounts.
- **Production (already on Blaze):**
  - `deleteAccount` invocations, plus the Cloud Build and Artifact Registry
    storage for its image (cents per month);
  - one extra Firestore read per client create (deleted-account check) and
    per upload (profile check);
  - leaderboard reads drop from "the whole league per view" to at most 30.
- **Only if enabled:** reminders (Functions + Cloud Scheduler) and
  AI verification (paid Gemini usage).

## 8. Retention proposal: deleted-account marker

| Field | Purpose | Personal data? | Access | Expiry |
|---|---|---|---|---|
| Document id = uid | Refuse creates from stale sessions of the deleted account | A pseudonymous id; Auth no longer knows it | Server only (rules deny all client access) | — |
| `markedAt` | When deletion began | No | Server only | — |
| `expiresAt` | markedAt + 2 h; the rules ignore the marker after it | No | Server only | Proposed Firestore TTL on this field: deleted ~2 h after deletion |

**Why 2 h:** ID tokens live at most 1 h after the revocation that starts the
deletion. **Recommendation:** enable the TTL policy, so markers don't
accumulate. **Owner decision**; not enforced.

## 9. Mobile checklists

**Android:**
1. Register `com.touchgrass.app` in Firebase (AC-8). Add SHA-1/SHA-256, then
   replace `android/app/google-services.json`.
2. Create the upload keystore and `android/key.properties`
   (`PHASE_7F_ANDROID_SIGNING_GUIDE.md`); never commit them.
3. `flutter build appbundle --release`, then `bash tool/test_android_gates.sh --full`.
4. Test on a device:
   - sign-in;
   - camera and gallery;
   - location;
   - deletion.

   `POST_NOTIFICATIONS` is declared but no longer requested while reminders
   are disabled.
5. Play Console: data safety form (`STORE_LISTING.md`), privacy policy URL,
   and the account-deletion URL or instructions.

**iOS** (needs macOS, Xcode and an Apple Developer account):
1. Register the bundle `com.touchgrass.app`, then add
   `GoogleService-Info.plist`.
2. Add an app privacy manifest (`PrivacyInfo.xcprivacy`) declaring the
   collected data and the required-reason APIs.
3. Signing, and the Sign in with Apple capability (Apple sign-in is offered).
   `UIBackgroundModes` now has only `remote-notification` (Phase 8 removed
   the unused `fetch`). Not validated on a device.
4. Archive in Xcode, then TestFlight. App Store privacy labels.
