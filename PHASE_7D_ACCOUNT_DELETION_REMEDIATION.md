# Phase 7D — Account Deletion Remediation

**Status: root cause confirmed; the server-side fix is complete locally and tested (unit + emulator). NOT deployed.** Nothing was deleted in production.

## 1. Root cause (evidence, not assumption)

The **live** web app (`touchgrass-today.web.app` / `touchgrass.web.app`) is an older build. The current code was never deployed. Its Delete Account runs a **client-side cascade**. The order below was read from the public `main.dart.js` (both sites serve the same bundle, `eebdffef…`):

| # | Client operation | Live Firestore rule (= HEAD `67c5a38`, export `eb6b6b1c…`) | Result |
|---|---|---|---|
| 1 | Query `completions` where `userId == uid` | read: owner | OK |
| 2 | **Batch-delete those completions** | `allow update, delete: if false` | **permission-denied** if the user has ≥1 completion. **First failing operation.** |
| 3 | Delete `users/{uid}/challenges/*` | owner may write | OK |
| 4 | Delete `users/{uid}/memories/*` (Journal) | `allow delete: if isOwner` | OK |
| 5 | Delete `leaderboard_public/{uid}` | owner may delete | OK |
| 6 | Delete `usernames/{name}` | owner may delete | OK |
| 7 | **Delete `users/{uid}`** | `allow delete: if false` | **permission-denied** |
| 8 | Delete `user_avatars/{uid}.png` | (Storage) | never reached |
| 9 | `listAll` + delete `completion_photos/{uid}/*` | (Storage) | never reached |
| 10 | Delete the Auth user | — | never reached |

**Consequences:**
- A user **with completions**: nothing is deleted, and an error is shown.
- A user **without completions**: challenges, Journal, leaderboard entry and username **are deleted**, then step 7 fails. The account, profile document, photos and avatar remain. This is a **partial deletion reported as a failure**.
- `users/{uid}/aiUsage` is never attempted by the live client.

**Why this is not "just a rules bug":** the rules deny client deletes on purpose. Completions are create-only and immutable, which is what anti-cheat and XP integrity depend on. A trusted backend must do the deletion. Loosening the rules would trade one problem for another.

## 2. Local fix (already in the repository; hardened in 7D)

- **Server:** `deleteAccount` callable (`functions/src/index.ts`) → `performAccountDeletion` (`functions/src/accountDeletion.ts`), Admin SDK, `us-central1`, 300 s timeout.
- **Client:** `CloudAccountDeletionService` (`lib/services/account_deletion_service.dart`). The user re-authenticates, then the client calls the function and signs out only on `{deleted: true}`. Messages are honest: "couldn't confirm" on a timeout, "isn't available" when the function is missing. The client never claims success itself.

**Order:**
1. Revoke refresh tokens.
2. Storage: `completion_photos/{uid}/`, `metadata_backup/completion_photos/{uid}/`, `user_avatars/{uid}.png`.
3. `completions`, `usernames` and `feedback` owned by the uid; `leaderboard_public/{uid}`.
4. `users/{uid}` with every subcollection (challenges, memories, aiUsage).
5. **Storage again (7D).**
6. The Auth user, last.

**Guards:**
- The uid comes only from the verified ID token.
- The sign-in must be at most 5 minutes old (`failed-precondition` otherwise).
- `isSafeUid`.
- Prefixes end in `/`, so `alice` never matches `alice2`.

**7D change: second Storage sweep (step 5).**
- *Problem:* another device's ID token stays valid for up to 1 h after refresh tokens are revoked. That device could upload a photo after step 2, and the photo would outlive the account. Orphan cleanup skips users without a profile, so it would never remove it.
- *Fix:* the sweep runs before the Auth deletion. A failure there is reported and leaves the Auth user in place for a retry.
- *Residual window:* an upload in the ≤1 h **after** step 6 is still possible with an unexpired ID token. It would be an orphan under a deleted uid; see §6.

## 3. Test evidence (this run)

| Test | Where | Result |
|---|---|---|
| Request checks: unauthenticated, stale sign-in (boundaries), clock skew, unsafe uid | unit | pass |
| Exact order; the Auth user last; the second sweep present | unit | pass |
| Failure at **every** distinct step stops later steps; a retry finishes | unit (10) | pass |
| Second-sweep failure: error reported, Auth user survives | unit (new) | pass |
| Auth user already gone (lost response) counts as done; other Auth errors never count as success | unit | pass |
| Full cleanup: Firestore, Storage photos, **metadata backups**, avatar, Auth | emulator | pass |
| Another user and a **uid-prefix look-alike** untouched | emulator | pass |
| Idempotent repeat; pagination beyond one batch (450 completions) | emulator | pass |
| Storage failure mid-way: account stays usable, retry finishes | emulator | pass |
| Failure at the Auth step: retry completes | emulator | pass |
| Sessions revoked before any deletion | emulator | pass |
| **Two concurrent requests**: nothing left; another user untouched (7D) | emulator | pass |
| **Photo uploaded by another session mid-deletion** is removed by the second sweep (7D) | emulator | pass |
| **Photo download links stop working** after deletion (7D) | emulator | pass |
| Rotation or metadata jobs running during deletion: no resurrection, no orphan backup | emulator (7C/7D) | pass |
| Client: re-auth → server → sign-out ordering; honest messages | Flutter | pass |

Suite totals are in `PHASE_7D_FINAL_REPORT.md` §4.

## 4. Data inventory and deletion semantics

| Data | Deleted by `deleteAccount` | Notes |
|---|---|---|
| Auth account | Yes (last) | Refresh tokens revoked first |
| `users/{uid}` + challenges, memories (Journal), aiUsage | Yes | `recursiveDelete` |
| `completions` (`userId == uid`) | Yes | Batches of 400 |
| `usernames` (`uid == uid`) | Yes | The name becomes available again |
| `leaderboard_public/{uid}` | Yes | Disappears from leaderboards at the next read |
| `feedback` (`userId == uid`) | Yes | |
| Challenge photos, avatar, metadata backups | Yes (twice) | Token links die with the object |
| Analytics (GA4) events | **No** | Kept for the GA4 retention period. The app clears the user ID and resets the analytics ID. **[owner: state the period]** |
| Crashlytics reports | **No** | Provider retention. Tokens are redacted (7C). |
| Cloud Logging entry "Account deleted" (uid + counts) | **No** (kept by design) | Security audit trail; minimal data. **[owner: log retention]** |
| Storage soft-delete copies | **Not immediately** | Recoverable by project admins for the bucket's soft-delete window **[owner: check]** |
| Firestore backups / PITR | n/a | None configured (verified read-only in 7A) |
| Other users' data | Never touched | Nothing in the data model is shared across users |

## 5. Retry and recovery

- Every step is "delete whatever is still there", so the operation is idempotent.
- A failure at any step returns an error. The user can sign in again and retry, because the Auth user is deleted last.
- "Couldn't confirm" (timeout or connection loss) tells the user that a retry is safe and finishes the job.
- An operator can re-run `performAccountDeletion` for a uid from a trusted shell if a user can no longer sign in. This is not built as a tool; it would need its own authorization.

## 6. Residual risks

1. **Live users can't delete their accounts until the coordinated release** (F-1 + H-1). The live client's flow can't work under any safe ruleset.
2. **Up to 1 h after deletion,** a still-unexpired ID token on another device could upload a photo or recreate a document. Options:
   - a scheduled sweep for uids without an Auth user (extend orphan cleanup, which is not deployed);
   - require App Check, which narrows but doesn't close the window.
   **Owner decision.**
3. **Users who already tried the live deletion** may hold a partially deleted account (no Journal or username, profile still present). After F-1 they can delete again. Consider telling users who contacted support.

## 7. Production prerequisites (each separately authorized)

1. The Blaze plan is verified (7A). The first functions deploy enables the Cloud Functions, Cloud Build, Artifact Registry and Cloud Run APIs.
2. **F-1:** `firebase deploy --only functions:deleteAccount --project touchgrass-today`. The `functions` config is in `firebase.json`. Deploy **only** this function: AI verification stays disabled and is not exported for deployment, per the 7A manifest.
3. **H-1:** a new web build, so the live client calls the function. The old client's cascade keeps failing until then.
4. Disclosures (deletion copy) are published only after the test below passes.

## 8. Controlled two-account test (after F-1, before announcing deletion)

1. Create test accounts **A** and **B** on the live app (new build). Give each 2 completions with photos, a Journal caption, a profile photo, a username and a feedback message.
2. Record the expected footprint privately: counts only, no URLs.
3. As **A**, sign in again, then Settings → Delete Account. Expected: success, then signed out.
4. Verify A is gone, read-only:
   - Firebase console: Auth user absent;
   - `users/{A}` absent;
   - no `completions`, `usernames` or `feedback` for A;
   - no `leaderboard_public/{A}`;
   - Storage: no `completion_photos/{A}/`, no `user_avatars/{A}.png`, no `metadata_backup/completion_photos/{A}/`.
5. A's old photo link (saved privately before step 3) returns 404 or 403.
6. **B is unchanged:** B signs in and sees all of their data and photos.
7. Function logs show one "Account deleted" entry with A's uid and counts, and no errors.
8. Retry case: B deletes, with the network cut during the call. The app says "couldn't confirm". Retrying succeeds.
