# Phase 7A — Production Deployment Manifest

**Project:** `touchgrass-today` (the only project; `.firebaserc` default).

**Status: NOTHING HERE HAS BEEN DEPLOYED.** Each change is a separate ⚠️ PRODUCTION action that needs the owner's explicit authorization. Exact commands and checks are in `PHASE_7A_RELEASE_RUNBOOK.md`; the step numbers below refer to that runbook.

## What production looks like today

All checks were read-only, on 2026-10-19:
- `tool/export_live_rules.mjs` (CLI MCP `get_security_rules`, GET only);
- `firebase firestore:indexes`, `functions:list`, `apps:list`, `apps:android:sha:list`, `firestore:databases:get`, `firestore:backups:schedules:list`;
- the MCP `get_environment` billing line.

| Area | Live state | Local (repo) state |
|---|---|---|
| Firestore rules | **Byte-identical to the committed `HEAD` (`67c5a38`) `firestore.rules`.** Every audit finding on that file is live: username takeover, spoofable leaderboard, XP bounds of +4000 per write, any photo URL. | Phases 1–6 rules, 347 emulator tests |
| Storage rules | **Matches no committed version.** Any signed-in user can read **and list** every user's completion photos; owners can store any file type or size; there is **no `user_avatars` rule** (avatar uploads are denied); there is no catch-all deny. | `storage.rules` (never deployed) |
| Composite indexes | **None** | 2 in `firestore.indexes.json`. It was **not referenced by `firebase.json`** until Phase 7A. |
| Cloud Functions | **None deployed** | `deleteAccount`; `verifyChallengeCompletion` (AI, hard-disabled, must not be deployed) |
| Billing | **Enabled (Blaze)** | — |
| Database | `(default)`, `nam5`, no PITR, no backup schedules, delete protection off | — |
| Apps | Android and iOS registered only as `com.example.touchgrass`; no SHA fingerprints | App IDs `com.touchgrass.app` |
| Web hosting | Sites `touchgrass` and `touchgrass-today` serve an older build (HEAD-era code; the old Gemini key, X-1) | Current code builds clean |

## Compatibility facts that decide the order

These were proven on the emulator in `firestore-tests/test/live_client_compat.test.mjs` and `live_storage_exposure.test.mjs`.

1. **The local rules break the live web app's completion flow.** The live app:
   - uploads `completion_photos/{uid}/{timestamp}.jpg`, which the local Storage rules deny;
   - creates completions that point at that file, which the local Firestore rules deny;
   - writes the reward update separately without `lastCompletionId`, which is denied.

   Its profile edits, username claims, leaderboard mirror and avatar uploads still work.

   **So R-1 and S-2 must ship in the same window as a new web build (H-1).**
2. **The new app needs the new rules.** Under the live rules, its batch write (`lastCompletionId`, `lastCompletionDate`, Journal entry) is refused by the old `isValidUserWrite` allow-list. So H-1 can't ship before R-1 either.
3. **The interim Storage rules (S-1) work for both the live web app and the new app.** They close the photo exposure on their own, without waiting for the coordinated window.
4. **Indexes (I-1) are additive.** The app's completions query needs one, and production has none. Deploying them changes no access, and the live and new apps both benefit.
5. **`deleteAccount` (F-1)** runs with the Admin SDK, so rules don't affect it. The new app needs it, because Settings → Delete account calls it. The live web app doesn't call it.

## Changes, in the recommended order

### S-1 ⚠️ Interim Storage rules — URGENT, independent

| | |
|---|---|
| Files | `deploy/interim/storage.interim.rules`, `deploy/interim/firebase.interim-storage.json` |
| Command | `firebase deploy --only storage --config deploy/interim/firebase.interim-storage.json --project touchgrass-today` |
| Expected behaviour | Completion photos become owner-only for read and list. Owner writes are image files named `{date}.jpg` or `{timestamp}.jpg`, under 10 MB, and the owner may delete. Avatars become uploadable (owner only, PNG name, under 5 MB, images). Everything else, including `metadata_backup/`, is denied. |
| Breaks | Nothing legitimate: 14 interim tests, plus 6 live-exposure and 7 live-compat tests. A non-image or oddly named upload is now refused. |
| Pre-checks | Runbook §5.1 (re-export: live Storage still equals the 2026-10-19 snapshot). |
| Smoke test | §5.4: own photo loads; another account's photo URL path is refused; avatar change works. |
| Rollback | Firebase console → Storage → Rules → history → previous version. This re-opens the exposure, so only do it if legitimate uploads fail. |

### I-1 ⚠️ Firestore composite indexes — independent, before any release

| | |
|---|---|
| Files | `firestore.indexes.json`, now referenced by `firebase.json` |
| Command | `firebase deploy --only firestore:indexes --project touchgrass-today` |
| Expected | Two indexes are created: `completions (userId ASC, completedAt DESC)` and `leaderboard_public (currentLeague ASC, weeklyXp DESC)`. Each takes minutes to build. |
| Effect | The home path stream, Journal repair and first-completion streak lookup stop failing with `FAILED_PRECONDITION`. No access change. |
| Pre-check | `firebase firestore:indexes` still lists none, so the CLI won't offer to delete anything. |
| Smoke test | Firebase console → Firestore → Indexes shows both as **Enabled**. |
| Rollback | Not needed (additive). To remove one, delete it in the console. |

### R-1 + S-2 + H-1 ⚠️ Coordinated release window (rules + web build)

| | R-1 Firestore rules | S-2 Storage rules | H-1 Web hosting |
|---|---|---|---|
| File | `firestore.rules` | `storage.rules` | `build/web` from `flutter build web --release` (never with `secrets.json`) |
| Command | `firebase deploy --only firestore:rules,storage --project touchgrass-today` | (same command) | `firebase deploy --only hosting --project touchgrass-today` (both targets) |
| Expected | Phases 1–6 rules: server-checked rewards, create-only completions, the N-6 photo rule, `removesOnly`, feedback, username and leaderboard integrity | Final rules: date-named photos only; no client delete | The current app |
| Tests | 347 emulator tests | (same) | 465 Flutter tests; web build and secret scan |

**Order inside the window:**
1. I-1 already **Enabled**.
2. Build the web app and secret-scan it.
3. Deploy R-1 + S-2.
4. **Immediately** deploy H-1.

Open tabs of the old web app fail to save completions until they reload. Tell users, or accept that a reload fixes it.

| | |
|---|---|
| Prerequisites | S-1 and I-1 done. If F-1 isn't deployed, Settings → Delete account says "isn't available right now" and nothing is deleted. Re-export and diff the live rules (runbook §5.1) right before. |
| Smoke test | §5.5: new account; first completion with photo; Journal; leaderboard; avatar change; remove saved locations; feedback. |
| Rollback | Re-deploy the previous hosting release (Hosting → release history → Roll back) **and** restore the previous rules in the console's rules history, **together**. The old web app needs the old rules. |

### F-1 ⚠️ `deleteAccount` Cloud Function

| | |
|---|---|
| Source | `functions/` (codebase `default`), Node 22, `firebase-functions` 7.4.0, `firebase-admin` 14.5.0. Function `deleteAccount`, `onCall`, region `us-central1`, timeout 300 s. No secrets. |
| Command | `firebase deploy --only functions:deleteAccount --project touchgrass-today` |
| **Never** | A bare `--only functions` or a plain `firebase deploy`. That would also try to deploy `verifyChallengeCompletion`, which needs the `GEMINI_API_KEY` secret and must stay undeployed (AI off, X-1). |
| Infrastructure | Blaze (verified). The first deploy enables the Cloud Functions, Cloud Build, Artifact Registry and Cloud Run APIs, and may ask for an Artifact Registry cleanup policy (owner's choice; a small storage cost). |
| Runtime identity | Default compute service account. It needs Firebase Authentication admin (revoke and delete users), Firestore read/write and Storage object admin, which the default Editor grant covers. If an organization policy removed that grant, add `roles/firebaseauth.admin`, `roles/datastore.user` and `roles/storage.objectAdmin`. |
| Behaviour | The caller is taken only from the verified ID token. The sign-in must be at most 5 minutes old. Steps run in this order: revoke refresh tokens → photos, metadata backups, avatar → completions, usernames, feedback → leaderboard mirror → user document tree → Auth user. Idempotent; reports success only after the Auth user is deleted. |
| Tests | 27 unit (order, failure at every step then retry, user-not-found) and 9 emulator (full footprint including metadata backups, prefix-collision guard, idempotence, 450 completions, revocation). |
| Smoke test | Runbook §8: two-account controlled test. |
| Rollback | `firebase functions:delete deleteAccount --region us-central1 --project touchgrass-today`. The app then says deletion "isn't available right now". Deletions already done are permanent by design. |

### Prerequisites outside Firebase deploys (owner actions)

| ID | What | Blocks |
|---|---|---|
| X-5 | Register Android and iOS apps for `com.touchgrass.app`, add fingerprints, run `flutterfire configure` (runbook §1) | Android and iOS builds |
| X-6 | Upload key and `key.properties` (§2) | Android release |
| X-4 | One Maps key per platform, each restricted (§9) | Safe key exposure |
| X-8 / X-11 | Privacy policy and store disclosures (§10, `PHASE_7A_PRIVACY_DISCLOSURE_DRAFT.md`) | Store submission |
| iOS | Mac steps (§11) | iOS release |

## Post-deployment monitoring (first 48 hours)

- **Firestore and Storage → Usage → Rules:** denied-request rate.
  - A spike after S-1 means a legitimate upload shape was missed. Roll back S-1 and report.
  - A spike after R-1 without H-1 means the window is open; deploy H-1.
- **Cloud Logging, `deleteAccount`:**
  - `"Account deletion incomplete"` errors (retry-safe; investigate if repeated);
  - latency near 300 s (large accounts).
- **Crashlytics:** new `FAILED_PRECONDITION` or permission-denied exceptions.
- **Indexes:** none in "Error" state.
