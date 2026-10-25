# TouchGrass Cloud Functions — Server-Side Verification

## Status: code complete, unit-tested, NOT deployed, NOT tested against live Firebase

> **Update 2026-10-17 (remediation Phases 1–2):**
> - The Flutter client **no longer calls Gemini at all**, and AI verification is off (audit D-06). Statements below that say the app "still calls Gemini directly" are historical.
> - `verifyChallengeCompletion` now decides the day using `lastCompletionDate` (audit D-01).
> - A second callable, `deleteAccount`, was added; see its section below.
> - Nothing has been deployed.

This directory did not exist before this pass. `src/index.ts` is a real,
complete implementation of `verifyChallengeCompletion` — not a stub — but it
has never been built, deployed, or run against a live Firestore/Storage/
Gemini environment. There is no Blaze billing configured on this project (a
decision only you can make in the Firebase Console), so I could not deploy or
test it, and I'm not claiming otherwise.

**The Flutter app still calls Gemini directly** (`lib/services/gemini_service.dart`)
and computes rewards client-side (`lib/repositories/user_repository.dart`).
That flow is untouched and still the one actually running. Switching the
client over to call this function instead is a separate, deliberate step —
see "Cutting the client over" below — not done as part of this pass, because
it would mean rewiring the core camera/verification flow without any way to
verify it actually works, which is a bad trade against a currently-working
system.

## `deleteAccount` — server-side account deletion (audit D-04, remediation Phase 2)

**Status:** the code is complete and tested, and it is **not deployed**. Deploying needs the Blaze plan and your explicit approval (see `REMEDIATION_CHECKLIST.md`, D-04).

**What it does:** a callable that deletes the **caller's** account. The uid always comes from the verified ID token, never from request data. The function refuses to run unless the caller signed in within the last 5 minutes; the app re-authenticates first. It then deletes, in this order:
1. Completion photos (`completion_photos/{uid}/…`; the trailing slash means `alice` never matches `alice2`) and the avatar.
2. Completions, username claims, the leaderboard mirror, and feedback.
3. `users/{uid}`, recursively, including challenges, memories and aiUsage.
4. Finally, the Firebase Auth user.

**How failures and retries behave:**
- Every step is idempotent. After a failure, a retry resumes cleanly, and the Auth account is deleted last so the user can still sign in to retry.
- The function returns `{deleted: true}` only after every step has succeeded. Otherwise it returns an error.
- The app (`lib/services/account_deletion_service.dart`) shows success only after that confirmation. Until the function is deployed, the app's delete button fails closed with an honest "not deleted" message.

**Tests:**
- `npm test` runs the unit tests (request guard, sign-in freshness boundaries, Auth-step idempotency).
- `npm run test:emulator` runs against the real Firestore, Storage and Auth emulators on a `demo-` project. It covers full cleanup, cross-user and uid-prefix isolation, idempotency, pagination past 400 docs, and partial failure followed by a retry. It needs Java 21 or newer; see `firestore-tests/README.md`.

**Deploying it later (only with approval):**

```
firebase deploy --only functions:deleteAccount
```

Deploy it **by name**.

**Phase 7E:** `verifyChallengeCompletion` (AI, disabled) now lives in `src/aiVerification.ts` and is **not exported** from `src/index.ts`.
- **Why:** firebase-tools resolves every param the loaded code declares **before** applying `--only`. While the AI callable was in `index.ts`, its `GEMINI_API_KEY` secret meant even a by-name `deleteAccount` deploy would prompt for, and create, that secret, or fail.
- **Guard:** `src/entryPoint.test.ts` fails if the entry point exports anything but `deleteAccount` or declares any param.
- **Re-enabling AI** means re-exporting that module in a reviewed change, with its own approval.

**Phase 7F:**
- **What a deploy discovers.** The local manifest (`firebase-functions` serving `/__/functions.yaml` from this directory) lists exactly one endpoint, `deleteAccount`, with no params and no required APIs.
- **Operator tools (`src/ops/`, never deployed).** Dry-runs take no lease and write nothing (`leaseFor`). `revocationExperiment.ts` is the scripted production experiment that proves whether removing a download token revokes its URL (`PHASE_7F_TOKEN_ROTATION_RESULTS.md`).

**Phase 7G:**
- **Operation mode.** `--mode read-only` is the default. Writes need `--execute` plus `--mode test-object-mutation` (rotation scoped with `--uid`) or `--mode production-mutation`.
- **Exact production allowlist:** `touchgrass-today` with the `touchgrass-today.firebasestorage.app` bucket. Emulator runs must use a `demo-` project id. Half-set emulator variables and a conflicting `GCLOUD_PROJECT` are refused.
- **Output:** a new file under `ops-out/`, never overwritten.
- **Proof:** `src/ops/readOnlyGuarantee.test.ts` and the emulator snapshot test (`PHASE_7G_DRY_RUN_SAFETY_AUDIT.md`).
- **Deletion marker.** `deleteAccount` writes `deletedAccounts/{uid}` (timestamps only) before deleting the profile, so `firestore.rules` can refuse a re-created profile (`PHASE_7G_ACCOUNT_DELETION_VALIDATION.md`).

**Phase 7H:**
- **Deletion marker first.** It is now written right after session revocation, before any data is deleted. `firestore.rules` refuse every client create for that uid until the marker's `expiresAt` (2 h).
- **Local development never reaches production.** `npm run serve` and `npm run shell` use `--project demo-touchgrass-dev`, and `serve` also starts the Firestore, Storage and Auth emulators. Before 7H, `serve` ran this code against the real database.
- **Strict test runs.** `npm test` and `npm run test:emulator` run through `../tool/strict_node_test.mjs`, because Node 22 reports a suite whose `describe()` throws as passing.
- **Operator CLI, real-project runs:**
  - refused before anything is contacted when no Application Default Credentials file exists;
  - `--out` must be inside this repository's `ops-out/`, and its folder is created before any read;
  - a read-only `photo-token-rotate` file holds no object names or uids (hashed per-photo outcomes);
  - errors print the class and a short code only.

  AC-1 steps: `PHASE_7H_AC1_RUNBOOK.md`.

**Services it uses:** Cloud Functions 2nd gen, which runs on Cloud Run and is built with Cloud Build and Artifact Registry. It also uses Firestore, Cloud Storage and Firebase Auth, which the project already uses.

**Estimated cost:** see `REMEDIATION_CHECKLIST.md`, D-04. At expected volumes it should fall within Blaze's no-cost quotas.

## Entitlement enforcement (Phase 12)

This function also enforces AI-verification entitlement server-side before
spending a Gemini call: reads `entitlementTier` off the user doc (never
client-writable — see `lib/models/entitlement.dart`), rejects `free`-tier
callers outright, and checks a monthly quota against
`users/{uid}/aiUsage/{YYYY-MM}` (also never client-writable — Firestore
rules block all client writes to that subcollection). Usage counts
(attempted/successful/rejected/failed) are incremented here regardless of
outcome, so a user can't reset their quota by reinstalling the app or
editing local state.

**Not yet wired into the live app**: `entitlementTier` defaults to `free`
for every existing user (nothing has ever written a different value), and
the Flutter client doesn't check `canUseAiVerificationProvider` anywhere in
the actual camera flow yet — see `lib/widgets/ai_feature_locked_card.dart`
for the ready-to-use "Coming Soon" UI once that gating is turned on. Turning
it on today would immediately lock AI verification for 100% of users, since
nobody has been granted anything above `free` — don't flip this on until
there's an actual way to grant `premium` (a payment provider, or manual
Console/Admin SDK grants for a private beta).

## What this function does

Implements the flow: client uploads photo to Storage → calls this callable
function with `{challengeId, storagePath}` → function verifies the caller's
real Firebase Auth identity, loads the challenge, checks for an existing
completion (idempotent — a retried call never awards twice), downloads the
photo itself via the Admin SDK, calls Gemini with a server-held secret,
and — only if Gemini says it matches — computes XP/streak/level/league and
writes the completion + user update + leaderboard mirror in one transaction.
The client only ever receives the result; it never gets to declare
`verified`, a confidence score, or an XP amount itself.

## Code structure

Pure reward/entitlement/Gemini-response-parsing logic lives in `src/rewards.ts`
— deliberately free of any `firebase-admin`/`firebase-functions` runtime
import, so it can be unit-tested with plain `node:test` (`src/rewards.test.ts`,
49 tests, including `isOwnedStoragePath`/`parseVerifyRequestData`/
`isQuotaExhausted` — request-shape and ownership validation that used to be
untested inline logic in the handler) without an emulator, credentials, or
network access. `src/index.ts` imports from it rather than redefining the
logic inline. Run the tests with:

```
cd functions
npm test
```

This is genuinely run, not just written — see the "Commands actually
executed" section of the project's hardening report for the real output.

## What this function deliberately does NOT do yet

- **Achievement unlocking.** `AchievementDefinition.computeNewlyEarned`
  (16 achievements across several threshold types) was not ported to
  TypeScript in this pass — porting it faithfully needed more time than was
  available, and a rushed, unverified port risked being *wrong* in a way
  that's worse than not having it. Today, achievement unlocking stays
  client-computed even after cutover (bounded by the A1 Firestore rules —
  see main firestore.rules — so at worst this is cosmetic badge forgery, not
  XP/leaderboard manipulation).
- This is a documented gap, not a silent omission — port it before treating
  this function as a full replacement for `awardCompletionRewards`, not just
  for the verification step.

**Weekly XP reset is now ported** (`resolveWeeklyXp`/`nextMondayMidnightUtc`
in `src/rewards.ts`, mirroring the Monday-boundary logic in
`awardCompletionRewards`) — an earlier version of this function carried
`weeklyXp` through unchanged, which would have silently broken the weekly
leaderboard for anyone completing challenges via this function. Fixed and
covered by `rewards.test.ts`'s `resolveWeeklyXp` suite before any deployment
ever happened, so this was never live.

## Client-side abstraction (not yet adopted by the live camera flow)

`lib/services/challenge_verification_service.dart` defines
`ChallengeVerificationService`, an interface with two real implementations:
`LocalGeminiVerificationService` (wraps today's live client flow — Gemini
verify, then `UserRepository.awardCompletionRewards`) and
`RemoteVerificationService` (calls this callable via the `cloud_functions`
package).

**Fail-closed, environment-branched wiring (added in a second hardening
pass on this codebase):**

- `challengeVerificationServiceProvider` branches on
  `EnvironmentConfig.isProduction` (`--dart-define=ENVIRONMENT=production`):
  non-production (development, or `ENVIRONMENT=staging` — what
  `touchgrass-today.web.app` is actually built with today) resolves to
  Local; production resolves to Remote.
- `LocalGeminiVerificationService`'s constructor throws `StateError`
  unconditionally (not `assert`, which is stripped from `--release` builds —
  exactly the build mode production ships in) if `EnvironmentConfig.isProduction`
  is true. A production build cannot construct the insecure local path even
  by accident.
- `RemoteVerificationService` is fail-closed by construction: every path
  through `submit()` either returns a real server-verified acceptance or
  throws — there's no branch that falls back to local/insecure verification.
- **No production build has ever been made from this repository** — only
  development and `ENVIRONMENT=staging` — so none of this changes behavior
  for anyone using the app today. This was confirmed with the maintainer
  before implementing: defaulting to Remote unconditionally today, with the
  function undeployed, would have broken challenge completion entirely on
  the live testing site.

**`CameraNotifier` (`lib/providers/camera_providers.dart`) does not use this
abstraction yet**, deliberately: its flow shows the user a caption-entry step
*between* a successful verification and the completion being created. This
function's contract is atomic — verify and reward happen together, by
design, so a client can't call a real "verify" step and then fabricate the
reward write on its own — so there's no room in that contract for a step in
the middle. Adopting the remote path there means either dropping the caption
step or collecting it before verification instead of after: a real UX
decision, not just an implementation swap, and one this pass deliberately
left for whoever does the actual cutover rather than deciding silently.

## Before this can be deployed (external actions only you can do)

1. **Enable Firebase Blaze (pay-as-you-go) billing** on the `touchgrass-today`
   project — Cloud Functions cannot deploy on the free Spark plan. Firebase
   Console → Project Settings → Usage and billing.
2. **Set the Gemini secret** (never commit it to source control):
   ```
   firebase functions:secrets:set GEMINI_API_KEY
   ```
   Use a key you're comfortable being the server-side production key — this
   is a separate concern from whatever key you use for local/web client
   testing (see KNOWN_BUGS.md B2).
3. **Install dependencies and build:**
   ```
   cd functions
   npm install
   npm run build
   ```
4. **Deploy:**
   ```
   firebase deploy --only functions
   ```
   I have not run this, and won't without your explicit go-ahead per this
   project's standing rule that deploys are yours to trigger.

## Cutting the client over (after deployment, and only once verified working)

This is real follow-up work, not a checkbox:

1. Add the `cloud_functions` package to `pubspec.yaml`.
2. Add a Flutter service that calls
   `FirebaseFunctions.instance.httpsCallable('verifyChallengeCompletion')`
   with `{challengeId, storagePath}` (Storage upload stays client-side and
   unchanged — only the verification+reward step moves server-side).
3. Replace the direct `GeminiService.verifyPhoto()` call inside
   `lib/providers/camera_providers.dart`'s verification flow with a call to
   that new service, preserving the existing `_generation` cancellation-guard
   pattern around it.
4. Once the client no longer needs `GeminiService`/`EnvironmentConfig.geminiApiKey`
   for production builds, remove the client-side Gemini call path and stop
   passing `--dart-define=GEMINI_API_KEY` to release builds entirely — that's
   what actually closes KNOWN_BUGS.md B2 (the client-embedded key).
5. **Only after the above is verified working**, tighten `firestore.rules`:
   - `completions/{completionId}`: change `allow create` to `if false` —
     Admin SDK writes bypass rules entirely, so once the function is the only
     path, direct client writes should be blocked outright.
   - `isValidUserWrite()`: remove `xp`, `level`, `currentLeague`, `streak`,
     `longestStreak`, `totalCompletions`, `achievements` from the
     client-writable field list — the A1 bounds in the current rules become
     unnecessary once client writes to those fields are blocked entirely
     rather than just bounded.

Doing step 5 before steps 1-4 are deployed and verified would break the
currently-working app for every user — deliberately sequenced last.

## Rollback strategy

Because this pass never deploys anything and never cuts the client over, there is
no rollback to perform yet — but for whoever does eventually flip the switch:

- **Before rules are tightened (steps 1-4 above):** rollback is a single
  revert — flip `challengeVerificationServiceProvider` back to
  `LocalGeminiVerificationService`. The Cloud Function stays deployed but
  unused; nothing about the currently-working client path was ever touched,
  so there's nothing to undo there. `firebase functions:delete
  verifyChallengeCompletion` is optional cleanup, not required for safety.
- **After rules are tightened (step 5):** this is the point of no easy
  return — once `completions/{completionId}`'s `allow create` is `if false`
  and reward fields are removed from `isValidUserWrite()`'s allow-list, the
  client-side path can no longer write completions or rewards at all, even
  if you revert the provider flip. Rolling back at that point means
  reverting the `firestore.rules` deploy *first* (restoring the A1-bounded
  client-writable rules in this repo's git history), then reverting the
  client. This is exactly why step 5 is sequenced last and only after the
  server path is proven — don't reach this point without being confident.

## Testing this locally (once you have Node 22 + Java 21 for the emulator)

```
cd functions
npm install
npm run build
firebase emulators:start --only functions,firestore,storage
```

I could not run this myself in this environment (no Java 21 available for
the Firestore/Storage emulators — see the earlier Firestore rules work in
this project for the same limitation).
