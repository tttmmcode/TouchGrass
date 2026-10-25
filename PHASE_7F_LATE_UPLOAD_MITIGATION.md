# Phase 7F — Late-upload-after-deletion mitigation

**Decision: Option A (the uploader's profile must exist), implemented locally in the final `storage.rules` and tested on the emulator. Not deployed.** It ships with the final rules (S-2) in the coordinated release, which needs its own authorization.

## 1. The problem, re-verified against the code

`deleteAccount` (`functions/src/accountDeletion.ts`) runs these steps:
1. Revoke refresh tokens.
2. First Storage sweep: challenge photos, metadata backups, avatar.
3. Firestore deletes: completions, usernames, feedback, leaderboard mirror.
4. `recursiveDelete(users/{uid})`.
5. Second Storage sweep.
6. Delete the Auth user.

Revoking refresh tokens doesn't invalidate ID tokens already issued. Security rules don't check revocation, so another signed-in device can keep calling Storage and Firestore **for up to 1 hour**.

**What that device can actually still do** (verified in source, Phase 7F):

| Write | After step 4 (`users/{uid}` gone) | Why |
|---|---|---|
| Completion + Journal entry | **Refused** | `completeChallenge` commits one batch that also `update`s `users/{uid}` (`lib/repositories/user_repository.dart`); an update of a missing document fails, so the whole batch fails |
| Re-create the profile | Not done by the app | Profiles are created only in `_resolveUser`, after a **fresh sign-in**; a deleted Auth user can't sign in. A hand-written client could; see §5. |
| **Upload a challenge photo or avatar** | **Allowed before this fix** | The photo upload happens *before* the completion batch, and the Storage rules only checked the uid and file type |

So the gap is Storage only: an orphan photo, written after the second sweep, under a deleted uid. Nobody else can read it, because reads are owner-only, but it is personal data the deletion promised to remove.

## 2. Options compared

| Criterion | **A. Require `users/{uid}` for uploads** (rules) | **B. Scheduled cleanup sweep** |
|---|---|---|
| Closes the window | **Yes, synchronously.** After step 4 every upload is refused; everything uploaded before step 4 is removed by the second sweep (step 5). | Eventually: within one sweep interval after the 1 h token lifetime |
| Mechanism | `firestore.exists(/databases/(default)/documents/users/$(request.auth.uid))` in Storage rules | A new scheduled function: list `completion_photos/*` and `user_avatars/*`, look up each uid in Auth, delete objects of missing users after a grace period ≥ 2 h |
| New production infrastructure | None. The first deploy of cross-service rules grants Storage's service agent read access to Firestore (an IAM role the CLI adds) | Scheduled function, Cloud Scheduler job, its API and service account permissions; a second function in the deploy |
| Running cost | One Firestore document read per upload that passed every other check. At $0.06 per 100k reads (typical list price) that is about $0.06 per 100,000 uploads. | A full listing and an Auth lookup per user on every run, whether or not anyone deleted an account |
| False positives | None: it only refuses a write. | Must tell a deleted user from a slow sign-up; relies on Auth lookups and grace periods. A bug here deletes real users' photos. |
| Race conditions | Rules are evaluated per request; there's no gap between check and write that a client controls | Sweep vs. a user re-registering, vs. an in-progress upload, vs. an in-progress deletion |
| Effect on existing users | Users always get a profile at sign-in, before they can reach an upload screen. A legacy account with no profile can't upload, but it can't save a completion either (that batch needs the profile), so nothing regresses. | None visible |
| Offline and retries | The Storage SDK doesn't queue uploads offline; a retry after deletion is refused, which is correct | — |
| Challenge vs. profile photos | The same check on both | The same |
| Account creation | Profile is written in `_resolveUser` before any upload is possible | — |
| Maintainability | 1 function, 2 call sites, 3 new emulator cases, 1 static guard | A new job with monitoring, alerting and audit records |
| Coverage of a hand-made client that re-creates its own profile within the hour | No (§5) | Yes, once the Auth lookup runs |

**Recommendation: A.** It closes the window at the moment it opens, adds no scheduled infrastructure or standing cost, can't delete anyone's data by mistake, and is fully testable on the emulator. B is a larger, riskier system aimed at a residual case (§5) that only the deleted account's owner could create, and that exposes nothing to anyone else. The two are **not** combined.

## 3. What changed locally

**`storage.rules` (FINAL only; the live interim rules are untouched):**

```
function hasProfile() {
  return firestore.exists(/databases/(default)/documents/users/$(request.auth.uid));
}
```

This is appended as the **last** condition of `create, update` on `user_avatars/{fileName}` and `completion_photos/{userId}/{fileName}`. Placing it last means requests that fail on name, size or type are refused before the Firestore read, so they cost nothing.

**Tests (`firestore-tests/`):**
- `storage_release_parity.test.mjs`:
  - the suite now runs Firestore next to Storage;
  - alice, bob and mallory get profiles, so mallory's denials still prove *ownership* and not a missing profile;
  - new cases:
    - P71: no profile, own challenge photo → FINAL **DENY**, INTERIM ALLOW;
    - P72: no profile, own avatar → FINAL **DENY**, INTERIM ALLOW;
    - P73: no profile, wrong file name → DENY in both;
  - P71 and P72 are recorded as documented differences, with reasons;
  - a static check that every FINAL `create/update` ends in `&& hasProfile()`.
- `storage.test.mjs`: test users get profiles, as real users do.
- `helpers.mjs`: `storageEnv` also loads `firestore.rules`; `seedProfiles` added.

Results are in `PHASE_7F_FINAL_REPORT.md` §13.

## 4. Deployment notes (needs authorization; part of S-2)

- It deploys with `firebase deploy --only storage --project touchgrass-today` in the coordinated window, together with R-1 (Firestore rules), I-1 (indexes) and H-1 (web).
- **The first deploy of cross-service rules prompts to grant the Firebase Storage service agent a Firestore-read role.** That is an IAM change: approve it as part of S-2, or the cross-service check fails closed (all uploads refused).
- **Verification after deploy:**
  - an upload by a test account **with** a profile → allowed;
  - after `deleteAccount`, an upload with that account's still-valid ID token → refused;
  - the new app's full photo flow works.
- **Rollback:** redeploy the previous Storage ruleset. Firestore and the IAM grant are unaffected.
- **Smoke test impact:** the 7E live smoke script creates test accounts *without* a Firestore profile (no Firestore writes). Against the final rules its upload checks would be refused. A post-release smoke test needs a profile document per test account, which is a Firestore write to include in that test's authorization.

## 5. Residual risk (documented, not accepted on the owner's behalf)

Within the ≤1 h after deletion, a **hand-written** client using the deleted account's own unexpired ID token could re-create `users/{uid}`; the rules allow an owner to create their profile. It could then upload.
- This affects only that person's own (deleted) account: nobody else can read the photo.
- The app never does this, because profile creation happens only after a fresh sign-in.
- If the owner wants it closed too, the narrow addition is a server-only "deleted uid" marker that `firestore.rules` checks on profile creation. That is not implemented; it needs a retention decision for the marker.
