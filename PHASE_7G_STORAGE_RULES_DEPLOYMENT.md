# Phase 7G — Final Storage rules and the Storage→Firestore permission (AC-7)

**Status:**
- The final rules are ready locally and tested; **not deployed**.
- The live Storage rules are the interim rules (`630dc9a0…`, released 2026-10-20T04:30:20Z, re-verified read-only in 7F).

## 1. What the final rules add (vs. the live interim rules)

| Change | Why | Test evidence |
|---|---|---|
| Uploads (challenge photo, avatar) require `users/{uid}` to exist: `hasProfile()`, evaluated **last** | Closes the late-upload window after `deleteAccount` (7F) | Parity P71/P72: FINAL DENY, INTERIM ALLOW (documented differences) |
| *(Firestore side, R-1)* A profile can't be created for a uid with a `deletedAccounts/{uid}` marker, which `deleteAccount` writes before deleting the profile (Phase 7G) | Stops a still-valid session re-creating its profile and uploading again | `users.test.mjs`: 4 tests. Parity: the full race sequence (upload OK → deletion → upload DENY → re-creation DENY → upload DENY; other users unaffected). |
| Owner delete removed; `{date}.jpg` names only | Deletion is server-side; one object per completion | Parity P37/P43 |

**Unchanged:**
- other users can't list, read or get links for challenge photos;
- avatars: single GET for signed-in users only, no listing;
- types (JPEG, PNG, WebP, HEIC, HEIF; never SVG or GIF) and sizes (<10 MB photos, <5 MB avatars).

**Signup:** the app creates `users/{uid}` in `_resolveUser` on the first sign-in, before any upload screen can be reached, so legitimate uploads aren't blocked. A legacy account without a profile can't upload, but it already couldn't save a completion (that batch updates the profile).

## 2. The permission the first deploy asks for (verified in firebase-tools 15.19.1 `lib/rulesDeploy.js`)

- **Trigger:** the CLI checks the Storage rules text for `firestore.get` or `firestore.exists`. Ours uses `firestore.exists`.
- **What it grants:**
  - **role** `roles/firebaserules.firestoreServiceAgent`;
  - **member** `service-760620662222@gcp-sa-firebasestorage.iam.gserviceaccount.com`, the Cloud Storage for Firebase service agent of project 760620662222;
  - **scope:** the **project** IAM policy. firebase-tools reads the policy, adds this one binding and writes it back (`setIamPolicy`, field mask `bindings`). This is the scope Firebase supports; there is no narrower resource-level grant for this feature.
- **Why it's needed:** Storage rules run as that service agent. Without Firestore read access, `firestore.exists(...)` errors, the rule evaluates to deny, and **every upload is refused** (fail closed).
- **What it allows:** the Storage rules engine can read Firestore documents *while evaluating rules*. Rules only return allow or deny; no data leaves through them. Only people who can deploy rules can change what is read. It does **not** give users, clients or the app any new access.
- **Cost:** one Firestore document read per upload that passes every other check. At typical list prices that is about $0.06 per 100,000 uploads.
- **How the grant happens:**
  - **interactive deploy:** the prompt "Cloud Storage for Firebase needs an IAM Role to use cross-service rules. Grant the new role?" Answer **yes only if AC-7b is approved**;
  - **`--non-interactive`:** skips the grant silently, so uploads fail;
  - **`--force`:** auto-approves the prompt. **Never use `--force` here.**
  - Alternatively, the owner grants the same role to the same member in Google Cloud Console → IAM beforehand. The CLI then sees it and doesn't prompt.

## 3. Approval requests (two separate decisions)

| Gate | Operation | Scope |
|---|---|---|
| **AC-7a** | `firebase deploy --only storage --project touchgrass-today` (from the repo root; `firebase.json` → `storage.rules`) | Replaces the Storage ruleset for the default bucket only. **No** Firestore rules, indexes, Functions or Hosting. |
| **AC-7b** | The IAM grant in §2 | One project-level role binding for the Storage service agent |

**Must deploy together with** (coordinated window, each also approved):
- R-1 `firebase deploy --only firestore:rules`: carries the profile-re-creation guard and the rules the new client needs;
- I-1 `--only firestore:indexes`;
- H-1 `--only hosting`, the new web client.

Deploying S-2 alone would break the **live** client, which names photos `{timestamp}.jpg` (P37) and deletes its own photos (P43). F-1 (`deleteAccount`) should be live first, because the deletion-marker guard expects the new function.

**Preconditions:**
- `firestore-tests: npm test` all passing, including parity;
- `sha256sum storage.rules` matches the reviewed hash recorded in the approval request;
- a read-only export of the live rules immediately before (`tool/export_live_rules.mjs`).

## 4. Verification after deploy (test accounts only)

1. Read-only export: the live Storage ruleset equals `storage.rules` byte for byte. Firestore is unchanged unless R-1 went in the same window.
2. `gcloud projects get-iam-policy touchgrass-today --flatten=bindings --filter="bindings.role:roles/firebaserules.firestoreServiceAgent"` shows exactly the one Storage service agent.
3. Test account **with** a profile: a challenge photo and an avatar upload succeed; the app shows them.
4. Another test account: can't read, list or get links for the first account's photo.
5. After `deleteAccount` (F-1) for a test account, using that account's still-valid session (a second signed-in browser): upload refused; profile re-creation refused (needs R-1).
6. Wrong name, type or size: refused.

## 5. Rollback

- Redeploy the previous Storage ruleset (Firebase console → Storage → Rules → history, or `firebase deploy --only storage` from the interim config).
- The IAM binding can stay; it is harmless without cross-service rules. Remove it in IAM if wanted.
- Firestore data is unaffected.
