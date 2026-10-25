# Phase 7G — Account deletion validation (AC-6)

**Status: Account deletion fixed locally; not verified in production.**
- No function is deployed (7F read-only check).
- The live web app's client-side cascade still fails for users with completions, and partially deletes users without any (7D §1).

`PHASE_7F_ACCOUNT_DELETION_VALIDATION.md` holds the full requirement-by-requirement mapping; it still applies. This file records what changed in 7G and the current evidence.

## 1. Changes in Phase 7G

| Change | Why | Evidence |
|---|---|---|
| `deleteUserData` writes **`deletedAccounts/{uid}`** (`markedAt`, `expiresAt` = +2 h; no other data) **immediately before** deleting `users/{uid}` | With the final Firestore rules this stops a still-valid session re-creating the profile, and so uploading again (Storage requires the profile). There's never a moment when the profile is gone but could be re-created. | Unit: the step order includes the marker before the profile, and the "failure at every step + retry" loop now covers the marker step. Emulator: the marker holds only timestamps, exists only for the deleted uid, and a retry rewrites it. Rules: 4 `users` tests + the parity race sequence. |
| Firestore rules: `users/{uid}` **create** refused if `deletedAccounts/{uid}` exists; clients can't read or write markers (catch-all deny) | Same | `users.test.mjs` (Phase 7G block) |

**Marker retention:** uids are never reused by Firebase Auth, so a marker only ever blocks a deleted account. `expiresAt` is there so the owner *may* enable a Firestore TTL policy on `deletedAccounts.expiresAt`, which is a production configuration change of its own. Without TTL, markers stay (uid + two timestamps). **Owner decision:** whether to keep them, and for how long. Disclose it with the deletion exceptions.

## 2. Requirements re-checked (local evidence, this run)

- **Requester and authorization:**
  - uid only from the verified token;
  - recent sign-in (≤5 min, boundary and skew cases);
  - unsafe uids refused before any step.
- **Only the requester's data:** owner-field queries and `/`-terminated prefixes; a look-alike uid (`alice2`) and other users are untouched (emulator).
- **Shapes and data covered:**
  - 0/1/3 completions × with/without photos;
  - challenge photos, metadata backups, avatar;
  - Journal, challenges and aiUsage (recursive);
  - leaderboard, usernames, feedback;
  - an account with no data;
  - data left after the Auth user is already gone.
- **Failures and retries:**
  - a failure at *every* step reports an error, later steps don't run, and the Auth user survives (deleted last), so a retry finishes;
  - "user not found" at the Auth steps counts as done; any other Auth error is an error, never success.
- **Concurrency and late uploads:**
  - two concurrent requests both finish with nothing left;
  - a late upload during deletion is removed by the bounded second sweep (it runs once, no loop);
  - after deletion, uploads and profile re-creation are refused (final rules).
- **Download links:** they stop working once deleted (emulator).
- **Logs:** one line (uid + counts); no contents.
- **Client:** re-auth → server → sign-out; honest "couldn't confirm, retrying is safe" and "isn't available … not deleted" messages (Flutter tests).

## 3. Deployment scope (re-verified 2026-10-21 after the 7G change)

- **Local manifest discovery** (`firebase-functions` `/__/functions.yaml`, the mechanism firebase-tools uses at deploy time):
  - **one endpoint**, `deleteAccount` (`gcfv2`, `us-central1`, callable, 300 s);
  - **no params section** (no secret can be resolved or created);
  - `requiredAPIs: []`.
- **Imports:** `lib/index.js` declares 0 params. It requires only `firebase-functions/v2/https`, `firebase-functions/logger`, `firebase-admin/{app,firestore,storage,auth}` and `./accountDeletion`; `lib/accountDeletion.js` requires nothing. The AI callable (`aiVerification.ts`) isn't loaded.
- **Command (AC-6):** `firebase deploy --only functions:deleteAccount --project touchgrass-today`
- **Side effects of a first-ever Functions deploy in this project:**
  - enables Cloud Functions, Cloud Build, Artifact Registry, Cloud Run, Eventarc, Pub/Sub and Cloud Storage APIs;
  - creates service identities;
  - may grant service-agent roles;
  - may ask about an Artifact Registry cleanup policy (choose a short retention).
- **Abort** (Ctrl-C) on any secret prompt, any other function listed, or any region other than `us-central1`.
- **Post-check:** `firebase functions:list --project touchgrass-today` shows only `deleteAccount`.
- **Order:** F-1 first (harmless: the live client never calls it), then the coordinated window: R-1 (marker guard and the new client's rules) + S-2 + I-1 + H-1.

## 4. Production verification after authorization (dedicated test accounts only)

`PHASE_7E_ACCOUNT_DELETION_RELEASE_PLAN.md` §6, plus for 7G:
- the `deletedAccounts/<testUid>` marker exists with only `markedAt`/`expiresAt`;
- with R-1 + S-2 live, a second signed-in browser for the deleted test account can neither upload nor re-create the profile.

Never test with real users' accounts.

## 5. Partial deletions from the live client (design; production audit needs approval PD-1)

| Question | Answer |
|---|---|
| Who | Users with **zero completions** who pressed Delete Account in the live web app. Its cascade deleted challenges, Journal, leaderboard entry and username claim, then failed at `users/{uid}` (7D §1). Users with completions lost nothing. |
| Evidence of an incomplete deletion | `users/{uid}` exists **and** `usernames/{profile.username}` is missing or not owned by that uid. Every legitimate profile holds its username claim (rules require it at creation; renames are atomic). A returning user gets the leaderboard mirror back at sign-in, but not the username claim. |
| Telling it apart from a legitimate account | An empty new account still has its claim, and an empty Journal or challenge list alone is never enough. Supporting (not deciding) signals: `totalCompletions == 0`, empty `memories` and `challenges`. |
| Audit method (read-only; needs a new reviewed command) | Read `users` with a field mask (`username`, `totalCompletions`) and the matching `usernames` docs. Output: counts on stdout; candidate uids only in the 0600 `ops-out/` file. No emails, names or photos. |
| Resuming deletion safely | Recommended: after F-1 + H-1, the user re-confirms in the app and the server function finishes everything (idempotent, own-uid only). Operator-run completion only with a written policy and per-uid approval. |
| Other users | Untouched: every step is keyed to one uid |
| Logs kept | The function's single deletion line; the audit file under `ops-out/` until the decision is made |
| Communication | **Owner/legal decision.** No contact commitment is made here. Suggested accurate wording, if used: "Your deletion request may not have finished. Some data (for example your Journal and username) was removed; your profile and photos were not." |
