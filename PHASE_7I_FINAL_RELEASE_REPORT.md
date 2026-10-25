# Phase 7I — Final Release Report

**Date:** 2026-10-24/25. Branch `release-hardening-pass`.

**Verdict: NOT READY.** The candidate is built, tested and pushed, but **not deployed**.

**Why it isn't deployed:** under the Firestore rules that are live today, the candidate can't complete a challenge
(§9). Replacing `touchgrass-today.web.app`, which serves the same legacy app as `touchgrass.web.app` to real users,
would break its core flow. Fixing that needs the final Firestore rules, an approval-gated deploy that in turn breaks the
legacy app on `touchgrass.web.app`. Per the brief (§2.1), this needs your decision: see §13.

`touchgrass.web.app` was not touched.

## 1. Initial state and preservation

**At the start:**
- HEAD `67c5a38`, branch in sync with `origin/release-hardening-pass` (0 ahead / 0 behind), 0 stashes, nothing staged,
  216 status entries.
- `origin/main` had moved to `b493295` (two README-only commits, unrelated); not merged and not pushed to.

**Protected files:** `DOCUMENTATION.md` and `.vscode/settings.json` are untracked user files. Neither was edited or
committed.

| File | SHA-256 |
|---|---|
| `DOCUMENTATION.md` | `baa43787aad0a31987f3c894db09c67df4cfe05650d56d813027cbb62a9f94bc` |
| `.vscode/settings.json` | `4c877983…` |
| `deploy/interim/storage.interim.rules` (the live file) | `630dc9a0…`, unchanged |

**After the commit:** the working tree is clean except those two untracked files. Every starting entry is in the commit
(152 added, 106 modified, 4 deleted). No reset, clean, stash, rebase, amend or force-push.

## 2. Defects found and fixes made (7I)

| # | Finding | Severity | Status |
|---|---|---|---|
| I1 | **The candidate's completion batch is refused by the LIVE Firestore rules.** They don't allow `lastCompletionId` / `lastCompletionDate`. Feedback is refused too (no live rule), and so is "Remove saved locations" (live completions are immutable). The candidate depends on the final `firestore.rules` | **Critical deploy blocker** | Proven and pinned: `firestore-tests/test/candidate_on_live_rules.test.mjs` (10; live rules frozen as `test/fixtures/live-firestore-67c5a38.rules`, byte-identical to the live ruleset today). Not fixable in the client without weakening the rules. Needs a decision (§13) |
| I2 | **Both Hosting sites have always been deployed together.** Release history shows simultaneous deploys on 2026-08-13; `firebase deploy --only hosting` updates both | High (deploy safety) | The only safe command is `--only hosting:today` (§9); documented |
| I3 | Deleted-account marker expiry (2 h) reviewed | Review | Kept, with the reasoning below |

**Marker expiry (I3):**
- **Completed deletion:** safe. The Auth user is gone, and every ID token issued before the revocation (the first
  step) expires within 1 h, inside the window.
- **Failed deletion never retried:** the Auth account still exists, so after 2 h it works normally again. If the failure
  came after the profile was deleted, the next sign-in creates a fresh profile. The user was told the deletion failed
  and to retry; retries are idempotent and rewrite the marker.
- **Without expiry,** such an account would be locked forever.

Carried forward from 7H (fixed locally, all in the commit): B20–B24 (late creates after deletion, silent suite failures,
dev scripts using production, deletion UX, AC-1 CLI readiness), `body-parser` 2.4.0.

## 3. Final test results (final tree = commit `cdff4a3`)

| Check | Result |
|---|---|
| `dart format --set-exit-if-changed lib test` | 163 files, 0 changed |
| `flutter analyze` | No issues |
| `flutter test` | **503/503** |
| Functions `tsc --noEmit` / `npm run lint` | Clean / 0 problems |
| Functions unit (`npm test`, strict wrapper) | **238/238** |
| Functions emulator (`npm run test:emulator`) | **48/48** |
| Rules (`firestore-tests: npm test`) | **608/608** (598 + 10 live-rules gate tests) |
| Tool tests | **40/40** |
| Android gates | **13/13** |
| npm audit (functions prod/all, firestore-tests prod/all) | 0 / 0 / 0 / 0 |
| Pre-commit scan of all 262 files | Only the public Firebase client keys already in HEAD. The Gemini key from `secrets.json` (hash `0634ae0459b5`) is in none. No private keys, passwords, real tokens, uids or emails |
| Web release build from `cdff4a3` | §9 |

**Not tested:**
- live smoke tests (nothing deployed);
- a real browser session of the candidate (no browser automation here);
- Android release build (needs signing and the registration);
- iOS (needs a Mac).

## 4. Security and privacy

As in 7H, plus I1/I2. Still open in production:
- old tokenized photo links open photos without sign-in;
- historical GPS is unknown;
- the live account deletion is broken;
- the live web app still contains the Gemini endpoint and the old AI copy. Byte-identical on both sites, verified today
  (`main.dart.js` SHA-256 prefix `eebdffefb406cc5c`).

## 5. AC-1

**Not run, blocked.** The ADC file is still absent and you haven't confirmed readiness. Steps:
`PHASE_7H_AC1_RUNBOOK.md`.

## 6. Decisions and approval-gated operations

**Decisions** (definitions from `PHASE_7G_RELEASE_READINESS.md`):
- **D15:** "thousands of other explorers" (in `STORE_LISTING.md` only, not the app). Substantiate or remove.
- **D16:** retention periods (placeholders in the policy drafts).
- **D17:** whether to notify users that, until 2026-10-20, any signed-in user could read others' challenge photos.
- **D19:** Terms #3, "never share identifiable photos publicly without your consent". Nothing was shared
  intentionally, but download links were harvestable.
- **D20:** whether to disclose that the live web app could send photos to Google Gemini.
- **Marker TTL:** whether to configure a Firestore TTL policy on `deletedAccounts.expiresAt`.
- **Support mailbox:** whether `support@touchgrass.app` is monitored.
- **Dev project:** whether to set up a separate development project (debug builds send Analytics to production).
- **Candidate deployment:** §13.

**Approval-gated, not performed:**
- the final Firestore rules;
- the final Storage rules and the IAM grant;
- the `deleteAccount` deploy;
- AC-2 (revocation experiment), AC-3 (rotation), AC-4/5 (metadata);
- G-AV (the test avatar);
- the app registrations (AC-8);
- dev separation (AC-9).

## 7. Android / iOS

- **Android:** registration is `com.example.touchgrass` (the app is `com.touchgrass.app`); no `key.properties`. So
  there is no release build. Gates 13/13.
- **iOS:** no Mac, no `GoogleService-Info.plist`, no app privacy manifest, no signing. Not validated.

A web deployment would not be a store release.

## 8. Git

- **Commit:** `cdff4a3d2ef991eef0e1128b8f447c2d5537e0cf`, "Security remediation and release hardening (Phases 1-7I)".
- **Pushed:** to `origin/release-hardening-pass`, a fast-forward from `67c5a38`. Remote verified equal to local HEAD
  with `git ls-remote`.
- **Not touched:** `main`.
- This report and its supporting docs are committed separately (docs only; they don't change the build).

## 9. Candidate Hosting target and artifact

| Site ID | URL | `.firebaserc` target | Live content today |
|---|---|---|---|
| `touchgrass-today` | `https://touchgrass-today.web.app` | `today` | Legacy build (deployed 2026-08-13 14:21Z, version `d7ba95eda30c7f13`, 42 files) |
| `touchgrass` | `https://touchgrass.web.app` | `main` | The same legacy build (deployed 2026-08-13 14:21Z, version `0b863ff5c9f9b8bb`) |

- **Candidate-only command:** `firebase deploy --only hosting:today --project touchgrass-today`. It deploys only
  Hosting target `today`, so no Functions, rules or indexes.
- **Both targets serve `build/web`,** so the candidate must be copied there first. `build/web` currently holds an older
  local build.
- **Rollback:** `firebase hosting:clone touchgrass:live touchgrass-today:live` (re-serves the legacy release still on
  `touchgrass`).
- **Artifact:** see §9a.

### 9a. Candidate artifact (built from `cdff4a3`, kept outside the repo)

- **Build:** `flutter build web --release -o <scratchpad>/web-cdff4a3`, with no `secrets.json`. Exit 0.
- **Size:** 41 files, 44,624,832 bytes.
- **Manifest:** a per-file SHA-256 list; the list's own SHA-256 prefix is `46b1115c5879d637`.
- **Key files (SHA-256 prefix):**

  | File | Candidate | Live (both sites) |
  |---|---|---|
  | `main.dart.js` | `0fc5d7b6d2c2e4a6` (4,595,199 bytes) | `eebdffefb406cc5c` |
  | `flutter_bootstrap.js` | `d70ebbca9f62efad` | — |
  | `index.html` | `2d886022599c0320`, unchanged from live | `2d886022599c0320` |
  | `version.json` | `6c700ca862e85179` | — |

- **`tool/check_web_bundle_secrets.mjs`:** no secrets in 17 text files.
- **Keys:** exactly the 2 public keys, `943c870ac547` (Firebase web) and `974258259a37` (Maps JS).
- **0 text files contain:** `gemini`, `generativelanguage`, "AI verification", "premium feature", "Share Adventure",
  "Coming soon".
- **Present:** "Save to Journal", "Completed on the honor system", "Deleting your account".
- **No emulator or debug wiring:** 0 matches.

## 10. Live smoke tests

None: nothing was deployed.

## 11. `touchgrass.web.app`

Untouched: no deploy, clone, channel, redirect or target change.

## 12. Remaining risks

§4, §6 and §7.

## 13. Candidate deployment: your decision

**Option A — coordinated test cutover.**
- **You approve:**
  - the final Firestore rules;
  - the `deleteAccount` deploy;
  - the candidate on `touchgrass-today.web.app`.
- **Result:** you can test everything, account deletion included.
- **Cost:** while `touchgrass.web.app` stays legacy, its completions are refused (7A). Its users can't complete
  challenges until you approve the final-domain deploy.
- **Storage rules + IAM:** can follow separately.

**Option B — preview channel only.**
- **Command:** `firebase hosting:channel:deploy candidate --only today --expires 7d`.
- **Result:** a separate preview URL on the `touchgrass-today` site; neither live URL changes. You can test sign-in,
  navigation, layout, copy and Journal reading.
- **Cost:** completing a challenge, feedback, "Remove saved locations" and account deletion fail (known).
- **Auth:** Firebase normally adds the preview domain to Auth's authorized domains automatically. That's an Auth
  setting change, so it is part of what you'd approve.

**Option C — deploy to `touchgrass-today.web.app` as originally planned, without the rules.**
- **Cost:** anyone using that URL loses completions, feedback and location removal. Not recommended.

**Option D — a separate test Firebase project.**
- **Result:** full end-to-end testing with no production impact.
- **Cost:** needs project creation, Blaze for Functions, and app registration (AC-9).

## 14. Final-domain deployment

Not authorized; not performed.

## 15. Verdict

**NOT READY.** The candidate is built, tested and pushed (`cdff4a3`) but not deployed, pending §13. Mobile release is
blocked (§7).
