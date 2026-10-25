# Phase 7E — Account Deletion Release Plan

**Status: account deletion FIXED LOCALLY. Production is unchanged.** The live web app still can't delete accounts. Nothing was deployed and no account was deleted in production; only the smoke test's own two test accounts were self-deleted.

## 1. Root cause (re-verified against source)

The **live** web bundle runs a client-side cascade. Its first write is a batch delete of the user's `completions`. The live Firestore rules (`eb6b6b1c…` = HEAD) say `allow update, delete: if false` for completions, and the same for `users/{uid}`:
- users **with** completions: nothing is deleted;
- users **without** completions: challenges, Journal entries, leaderboard entry and username are deleted, then it fails at `users/{uid}`. Photos, avatar and Auth are never reached.

Evidence and the step table are in `PHASE_7D_ACCOUNT_DELETION_REMEDIATION.md` §1. The source and bundle are unchanged since then.

Completions are immutable **by design** (anti-cheat), so the fix is a trusted backend, not looser rules. The current source no longer contains the client cascade: `CloudAccountDeletionService` calls `deleteAccount`.

## 2. The local fix and its guarantees

`functions/src/accountDeletion.ts` (`performAccountDeletion`), called by the `deleteAccount` callable in `functions/src/index.ts`.

| Requirement | How |
|---|---|
| Verify requester; recent authentication | The uid comes only from the verified ID token; `auth_time` ≤ 5 min (`failed-precondition` otherwise; the client re-authenticates first) |
| Only the requester's data; no cross-user deletion | `isSafeUid`; prefixes end in `/`; owner-field queries; the uid look-alike `alice2` untouched (emulator) |
| Immutable completions | Admin SDK (rules don't apply to it) |
| Storage cleanup incl. profile and challenge photos and remediation backups | `completion_photos/{uid}/`, `metadata_backup/completion_photos/{uid}/`, `user_avatars/{uid}.png`, **twice** |
| Concurrent uploads | Refresh tokens revoked first; a **second Storage sweep** after the Firestore steps |
| Concurrent requests | Both finish; nothing left; another user untouched (emulator) |
| Partial failures | Any failure → error; the Auth user is deleted **last**, so the user can sign in and retry; every step is idempotent |
| Accurate states | `{deleted: true}` only after every step. Timeouts say "couldn't confirm", and that retrying is safe. A missing function says "isn't available … not deleted". |
| Retained data | GA4 events and Crashlytics reports (provider retention); one Cloud Logging line (uid + counts); the Storage soft-delete window. Disclosed in the privacy copy (D3). |

### Bounded race (Phase 7E)

- **Stopping condition:** the second sweep runs **exactly once**, immediately before the Auth deletion. There is no loop, so no unbounded race.
- **After the Auth deletion:** an upload from another device's still-unexpired ID token (≤1 h) would create an orphan under the deleted uid. Orphan cleanup intentionally skips users without a profile.
- **Proposed handling** (owner decision; not implemented):
  - **(a)** In the **final** Storage rules, make uploads require the user's profile document via a cross-service check (`firestore.exists(/databases/(default)/documents/users/$(request.auth.uid))`). Once `deleteAccount` removes `users/{uid}` (step 4), uploads are refused.
    - Costs one Firestore read per upload.
    - The first rules deploy grants Storage a Firestore read role: an IAM change needing its own approval.
  - **(b)** A post-deletion sweep for uids that no longer exist in Auth, run as an extended orphan-cleanup operator job.

## 3. Test evidence (this run)

| Suite | Deletion-related coverage | Result |
|---|---|---|
| Functions unit (`npm test`) | Request checks; exact order; failure at every distinct step + retry; second-sweep failure; Auth already gone; other Auth errors never success; revocation failure deletes nothing | **208/208** total, exit 0 |
| Functions emulator (`npm run test:emulator`) | Full footprint incl. backups and avatar; look-alike uid; idempotent; pagination (450); Storage failure + retry; Auth failure + retry; sessions revoked first; empty account; data after Auth already gone; **concurrent requests**; **late upload removed by the second sweep**; **links dead after deletion**; **7E: 0/1/3 completions × with/without photos (6 cases)**; **7E: second-sweep failure keeps the Auth user, retry finishes** | **43/43**, exit 0 |
| Flutter | Re-auth → server → sign-out ordering; honest messages | in the full suite (final report) |
| **Entry point (7E)** | `index.ts` exports only `deleteAccount` and declares **no params or secrets** | unit (2 tests) |

## 4. Deployment blocker found and fixed locally (Phase 7E)

**Problem:**
- `index.ts` also defined `verifyChallengeCompletion` (AI, disabled), with `defineSecret("GEMINI_API_KEY")`.
- firebase-tools 15.19.1 resolves **all** declared params **before** applying `--only` (`deploy/functions/prepare.js` → `build.resolveBackend`, then `params.handleSecret`). It also enables APIs for **all** functions in the build (Secret Manager if any function has secrets).
- So `firebase deploy --only functions:deleteAccount` would have:
  - prompted for and **created** the Gemini secret in Secret Manager (interactive), or failed (non-interactive);
  - enabled the Secret Manager API.
- The 7A manifest and the 7D deletion doc (which also wrongly said the AI function was "not exported") missed this.

**Fix:** the AI callable moved, unchanged, to `functions/src/aiVerification.ts`, which `index.ts` doesn't import.
- `entryPoint.test.ts` fails if the entry point exports anything but `deleteAccount` or declares any param.
- The source-ordering test for the AI guard now reads the new file.
- AI stays disabled; re-enabling it needs a reviewed re-export and its own approval.

## 5. Deployment plan (each step separately authorized)

| Step | Command | What it changes | Notes |
|---|---|---|---|
| F-1 | `firebase deploy --only functions:deleteAccount --project touchgrass-today` | Creates the `deleteAccount` function (2nd gen, `us-central1`) | **First functions deploy, so it also:** enables the Cloud Functions, Cloud Build, Artifact Registry, Cloud Run, Eventarc, Pub/Sub and Cloud Storage APIs; creates Pub/Sub and Eventarc service identities; may grant service-agent IAM roles; may ask about an **Artifact Registry cleanup policy** (choose a short retention). Billing: Blaze verified (7A); expected within the free quotas (D-04 estimate). The predeploy builds `functions/` (`npm run build`). |
| Pre-check | `cd functions && npm ci && npm test` (expect 208/208); `grep -c "defineSecret" lib/index.js` → 0 | — | Confirms the entry point has no secret |
| Deploy-time stop conditions | Any prompt for `GEMINI_API_KEY` or another secret; any function other than `deleteAccount` listed; a non-`us-central1` region | — | **Abort** (Ctrl-C) and report |
| Post-check | `firebase functions:list --project touchgrass-today` → only `deleteAccount` | — | Read-only |
| H-1 | `flutter build web --release` (no `secrets.json`), then `firebase deploy --only hosting --project touchgrass-today` | Both Hosting sites (`today`, `main` targets) | **Must ship in the coordinated window with R-1 (Firestore rules) + S-2 (final Storage rules) + I-1 (indexes)**, per the 7A manifest. The new client is built for those rules; deploying it alone isn't a supported combination. |
| Rollback | F-1: `firebase functions:delete deleteAccount --region us-central1 --project touchgrass-today` (the client then says "isn't available") | H-1: Hosting → release history → roll back, **together with** the rules | — |

**Should F-1 go before the coordinated window?** Harmless: the old live client never calls it. Deploying F-1 first lets the two-account test run on staging-like conditions as soon as H-1 lands.

## 6. End-to-end verification after F-1 + H-1 (dedicated test accounts only)

Follow `PHASE_7D_ACCOUNT_DELETION_REMEDIATION.md` §8: accounts A and B, each with completions, photos, a caption, an avatar, a username and feedback.

1. Delete A in the app. Check A's footprint is gone in every location, read-only in the console:
   - the Auth user;
   - `users/{A}` and its subcollections;
   - completions, usernames, feedback;
   - the leaderboard entry;
   - photos, avatar and backups.
2. A's old photo link returns 403 or 404.
3. B is unchanged.
4. Function logs show one "Account deleted" line.
5. A network-cut retry for B: "couldn't confirm", and the retry succeeds.

Then, **and only then**, the deletion disclosures (D3, D14) may be published.
