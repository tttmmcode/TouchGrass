# TouchGrass — Phase 8 final report (web first)

**Date:** 2026-10-25 · **Branch:** `release-hardening-pass` (Phase 8 is committed on top of `95a6081`, as authorized by the owner on 2026-10-25)

**Evidence levels:**
- **implemented:** the code exists;
- **unit-tested:** Flutter, Functions or tool tests;
- **emulator-tested:** rules or Functions run on the Firebase emulators;
- **browser-tested:** real Chrome against the emulators;
- **device-tested**, **config-verified**, **production-verified:** none of these were reached in Phase 8;
- **blocked:** waiting on an approval or on access.

## A. Status and verdict

**Verdict: not ready for production.** The web candidate works end to end
in a real browser against the emulators: 10/10 journeys, three runs in a row. But it
can't go live without a coordinated, approved cutover:
- the live rules refuse its core writes;
- `deleteAccount` isn't deployed;
- the disclosure and legal decisions are open;
- the photo-token rotation (AC-1 → AC-3) is still waiting for ADC.

Nothing was deployed or changed in production.

## B. Work done in Phase 8

**Environments** (`DEVELOPMENT_ENVIRONMENT.md`):
- An explicit, fail-closed choice of production, development or emulator.
  Before Phase 8, debug runs wrote to production.
- Telemetry is on in production only.
- Non-production builds show a DEV/EMULATOR banner.
- The new isolated dev project `touchgrass-dev-n7j3f` (free tier).
- A full local emulator stack, with the real `deleteAccount` function.

**Real-browser journeys** (`e2e/`): Chrome drives an emulator build through
sign-up, completion with a photo, reload, feedback, location removal,
leaderboard opt-out, sign-out/in, account deletion and reroll. Every
request to a real Google/Firebase backend is blocked and recorded.

**Defects fixed** (local, with regression tests; `KNOWN_BUGS.md` B25–B33;
`RELEASE_PLAN.md` §2):

| # | Defect | Found by | Test |
|---|---|---|---|
| B25 | "Remove saved locations" left an undismissable progress dialog: the wrong navigator was popped | Browser | `remove_saved_locations_test.dart` (fails on the old code) |
| B26 | Feedback "Send" never enabled on desktop web | Browser | `honest_features_test.dart` |
| B27 | Email sign-up dropped the typed name | Browser | `sign_up_display_name_test.dart` |
| B28 | Reminder permission prompt and settings with no sender: disabled honestly | Audit | `honest_features_test.dart` |
| B29 | Debug runs wrote to production and sent Analytics there | Audit | `firebase_environment_test.dart` |
| B30 | Smaller fixes: weather placeholder, stretched desktop cards, unreadable trail, unbounded leaderboard read, ids in Functions logs, unverified support address, Terms promise, unused iOS `fetch` mode | Audit | Several (see `KNOWN_BUGS.md`) |
| B31 | Settings switches had no accessible name ("switch, on") | Browser | `settings_toggle_tile_test.dart` (fails on the old code) |
| B32 | Emulator web builds sent Auth requests to the real Auth service after a reload; FlutterFire swallowed the failed emulator connection | Browser | `firebase_environment_test.dart` and journey 4 |
| B33 | Challenge text "Go outside and go outside and…" | Browser screenshots | `challenge_text_test.dart` (fails on the old code) |

**B32 in more detail.** This is a development-safety defect; production
builds are not affected.
- **What happened:** the test harness blocked the requests, so nothing
  left the machine.
- **The fix:**
  - emulator builds fail closed when Auth isn't on the emulator (the SDK is
    asked directly);
  - they never save the session on web, so a reload signs out by design;
  - any emulator-connection failure now stops startup, where it used to be
    swallowed.
- **Earlier evidence withdrawn:** the earlier "session survives a reload"
  pass was not valid evidence. Session restore across a reload is now
  listed as **not browser-verified** (`RELEASE_PLAN.md` §1).

**Visual direction** (checked in code and in the journey screenshots):
- deep-green lily pads, with a coloured 🔒 lock (no X) and no fog;
- exactly 3 stepping stones per trail connector, and "Day N" labels on a
  readable pill;
- a horizontal league row;
- unearned badges desaturated without blur;
- a blue-sky light theme;
- the weather chip only with a real reading;
- a phone-width column on desktop.

These are browser-tested visually only, not pixel-tested.

**Honesty and legal:**
- The unsupported "thousands of explorers" claim was removed.
- The league names were corrected.
- The Terms and Privacy text was aligned with what the app does. It is
  marked PROPOSED and is not published.
- The support address is the owner-confirmed `toughpiprojects@gmail.com`.
  It replaces the unconfirmed `support@touchgrass.app` and is named in one
  place (`SupportContact`).
- AI verification stays disabled, and nothing claims verification.

**Documents:**
- `RELEASE_PLAN.md`: feature matrix, blockers, cutover, rollback, approvals,
  costs, retention, mobile checklists.
- `PRIVACY_INCIDENT_ASSESSMENT.md` (kept local, not committed; see §I)
- `DEVELOPMENT_ENVIRONMENT.md`
- `e2e/README.md`
- `REMEDIATION_CHECKLIST.md`: P8-1…P8-16.

## C. Evidence (final run, this session)

| Suite | Result | Level |
|---|---|---|
| Flutter tests (full) | 538 / 538 pass | unit-tested |
| `flutter analyze` / `dart format` | No issues; 0 of 177 files changed | — |
| Firestore + Storage rules (`firestore-tests`) | 608 / 608 pass | emulator-tested |
| Functions unit / lint / tsc | 239 / 239 pass; 0 lint errors; tsc 0 | unit-tested |
| Functions on the emulators | 48 / 48 pass | emulator-tested |
| Tool tests | 45 / 45 pass | unit-tested |
| Browser journeys (Chrome, emulators) | 10 / 10 pass, three runs in a row (the last on the final build). No console errors, and no request to a real service during the main journey | browser-tested |
| Web release build (production default) + secret scan | Builds. Scan: no secrets in 17 text files (5 public keys allow-listed). No Gemini or AI endpoint in the bundle | local check |
| `npm audit --omit=dev` (functions, firestore-tests, e2e) | 0 vulnerabilities each | — |
| Protected files | `DOCUMENTATION.md`, `.vscode/settings.json` and `deploy/interim/storage.interim.rules` match their recorded SHA-256 | — |
| Android gates (Gradle dry-runs) | 14 / 14 pass. The older "no emulator endpoints in app code" check now asserts that they exist only in `main.dart`'s emulator branch, which release builds refuse. It still catches a planted call | local check |

**Notes on the journeys:**
- Two runs used a build that included every fix except B33. The third
  used the final build, with every Phase 8 fix.
- Each run resets the emulators and uses synthetic accounts, a synthetic
  photo and synthetic coordinates.
- **Not covered in the browser:**
  - Google sign-in and password reset;
  - profile-photo upload;
  - the map with real Maps tiles;
  - the dev project's own Hosting (no deploy; Storage needs Blaze).

## D. Launch blockers (owner action)

Full table in `RELEASE_PLAN.md` §3.
1. **Cutover:** the live Firestore rules refuse the new client's
   completion, feedback and location-removal writes, and the final rules
   break the legacy client. A coordinated cutover with a maintenance window
   is needed (`RELEASE_PLAN.md` §4). Each step needs its own approval.
2. **`deleteAccount`** isn't deployed, so live account deletion doesn't
   work.
3. **Old photo links** still open photos without sign-in. AC-1 (read-only
   inventory) is approved but waits for ADC, which is still absent. AC-2/3
   (rotation) need separate approval.
4. **Disclosure decisions** D16, D17, D19 and D20
   (`PRIVACY_INCIDENT_ASSESSMENT.md`), and approval of the Terms/Privacy
   text.
5. **Composite index** for the server-ordered leaderboard; deploy it before
   the new client.
6. **Unverified:** whether `touchgrass.web.app` is in Auth's authorized
   domains (X-3), and the Maps key restrictions (B5).

## E. Security and privacy

- **Secrets and personal data:** none appear in the code, docs or this
  report.
  - The Gemini key that was pasted earlier was not used or stored.
  - No build used `secrets.json`.
  - The dev web config has a public API key (allow-listed in the secret
    scanner like the production key). It needs restricting in Google Cloud
    like any web key.
- **Release bundle:** it also contains the dev project's public web config
  (project id and web API key), because every environment's options are
  compiled in. That's low risk: it's a public config, and the dev project
  holds synthetic data only. **Follow-up:** compile only the selected
  environment's options into release builds, and restrict the dev key.
- **Logs:** the Functions logs no longer contain user ids or raw errors
  (`logPrivacy.test.ts` pins this).
- **Photos:** EXIF/GPS is removed before upload. This was browser-verified:
  the stored object has no EXIF.
- **Account deletion:** server-side and idempotent. It leaves a
  timestamps-only marker; the proposed 2 h TTL is an owner decision.
  Emulator- and browser-tested; **not deployed**.
- **Development safety:** the emulator, dev and production paths are
  separate and fail closed. The harness blocks real backends. B32 above
  was a real gap, now fixed.
- **Open, owner-gated:** token rotation (AC-1 → AC-3), historical GPS
  (AC-4/5), Maps key restrictions, Auth domains.

## F. Development environment

**Dev project `touchgrass-dev-n7j3f`** ("TouchGrass DEV"):
- Spark plan, no billing, no Analytics.
- Firestore in `nam5`, and email/password Auth.
- Dev rules and indexes are deployed from `deploy/dev/` (generated from the
  production rules).
- Storage and Functions need Blaze, which needs your approval. Until then,
  photos and deletion are tested on the emulators.

**Emulators:** `demo-touchgrass-dev`, with ports and commands in
`DEVELOPMENT_ENVIRONMENT.md` §3. Emulator web builds sign out on reload by
design (B32).

## G. Production safety

**No production change in Phase 8:**
- no Hosting deploy to `touchgrass.web.app` or `touchgrass-today.web.app`;
- no rules, Functions or index deploys;
- no IAM, Auth, billing or app-registration changes;
- no production reads or writes;
- no token rotation, data repair or deletion test;
- AC-1 was not run (ADC is absent).

**The only cloud changes**, all on the new dev project and nowhere else:
- creating `touchgrass-dev-n7j3f`;
- enabling the Firestore and Identity Toolkit APIs;
- creating its Firestore database and web app;
- enabling email/password Auth;
- deploying the dev rules and indexes.

## H. Mobile

Not device-tested. The checklists are in `RELEASE_PLAN.md` §9.
- **Android:** registering `com.touchgrass.app` (AC-8), the upload
  keystore, the Play data-safety form, and the deletion URL.
- **iOS** (needs a Mac):
  - registering the bundle;
  - `GoogleService-Info.plist`;
  - the privacy manifest;
  - signing;
  - the Sign in with Apple capability.

  Phase 8 removed the unused `fetch` background mode; this isn't validated
  on a device.

The emulator and dev environment selection is web-first: `development` is
web-only so far.

## I. Git status

- **One Phase 8 commit** on `release-hardening-pass`, on top of `95a6081`,
  pushed to the matching GitHub branch (owner-authorized, 2026-10-25). The
  commit and push results are in the final message to the owner.
- **Deliberately not committed:** `PRIVACY_INCIDENT_ASSESSMENT.md`. The
  GitHub repository is public, and that document is written for the owner:
  it lays out the disclosure options and advises rotating the photo tokens
  before anything draws attention to the links. It stays local until the
  owner decides.
- **Git-ignored:** generated rules, the dev hosting folder, `e2e/node_modules`
  and the e2e artifacts.
- **Never committed:** the untracked user files `DOCUMENTATION.md` and
  `.vscode/settings.json` were not modified and stay out of any commit.

## J. Next actions and decisions needed

1. **`PRIVACY_INCIDENT_ASSESSMENT.md`:** keep it local or commit it to the
   public repo? Local is recommended until the tokens are rotated.
2. **Blaze on the dev project.** Billing needs your approval. It would
   enable dev Storage, Functions and a dev Hosting smoke test; otherwise
   keep using the emulators.
3. **AC-1:** tell me when ADC is ready. Only the approved read-only command
   will run.
4. **Cutover approvals**, each separately (`RELEASE_PLAN.md` §4/§6):
   - indexes;
   - `deleteAccount`;
   - the maintenance-window rules plus Hosting;
   - Storage rules plus the IAM grant;
   - the synthetic smoke test.
5. **Decisions:**
   - the Terms/Privacy text and disclosure (D16/D17/D19/D20);
   - the TTL on `deletedAccounts.expiresAt`;
   - the Maps key restrictions;
   - the Auth authorized domain.
