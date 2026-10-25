# Phase 7F — Account deletion validation

**Status:**
- **Account deletion fixed locally.** Production is unchanged: no function is deployed (`firebase functions:list`, 2026-10-21: "No functions found").
- The live web app still can't delete accounts; users without completions are left partially deleted.
- **Not "verified in production":** that needs F-1, H-1 and the two-account test.

## 1. Deployment graph (verified this phase)

| Check | Evidence | Result |
|---|---|---|
| Entry point | `functions/package.json` `main: lib/index.js`; `firebase.json` functions source `functions`, codebase `default`, predeploy `npm run build` | — |
| What a deploy discovers | **Local manifest discovery** — the same mechanism firebase-tools uses. `firebase-functions` 7.4 serving `/__/functions.yaml` from `functions/`, run locally, no production calls. | Exactly **one endpoint: `deleteAccount`**, `platform: gcfv2`, `region: [us-central1]`, `callableTrigger`, `timeoutSeconds: 300`. **No `params` section. `requiredAPIs: []`.** |
| AI isolated | `lib/index.js` requires only `firebase-functions/v2/https`, `firebase-functions/logger`, `firebase-admin/{app,firestore,storage,auth}`, `./accountDeletion`. `lib/accountDeletion.js` requires nothing. `defineSecret` occurrences in `lib/index.js`: **0**. | AI callable (`aiVerification.ts`) not loaded; AI stays disabled |
| Secrets created or updated by `--only functions:deleteAccount` | firebase-tools resolves every declared param before `--only` (7E finding); the manifest declares none | **None** |
| Guard against regressions | `entryPoint.test.ts`: the entry exports exactly `deleteAccount` and declares no params | Passes (unit run) |
| Extra source uploaded | The deploy package is the whole `functions/` directory minus `node_modules`, `.git`, `*.log`. That includes the operator tools under `lib/ops/` **as files**; none is exported, so none becomes a function. | No secrets: `functions/.env*` absent |
| Web build changes | The compatible web build (H-1) is the whole current app, not a deletion-only patch. It must ship with R-1/S-2/I-1 (`PHASE_7E_ACCOUNT_DELETION_RELEASE_PLAN.md` §5). | Not deployed |
| Hosting scope | `firebase deploy --only hosting` publishes `build/web` to **both** targets (`today`, `main`) | Needs its own approval |

## 2. Semantics checked (tests in this run: see `PHASE_7F_FINAL_REPORT.md` §13)

| Requirement | How it's met | Test |
|---|---|---|
| Authenticated requester only | uid taken from the verified ID token | unit: refuses unauthenticated callers |
| Recent authentication | `auth_time` ≤ 5 min (boundary, skew, missing and non-numeric cases) | unit ×7 |
| Only the requester's data | owner-field queries, `/`-terminated prefixes, `isSafeUid` | emulator: a look-alike uid (`alice2`) untouched; unit: unsafe uid refused before any step |
| Protected completions | Admin SDK (rules don't apply) | emulator: 0/1/3 completions × with/without photos |
| Challenge photos, avatar, backups | 2 Storage sweeps: `completion_photos/{uid}/`, `metadata_backup/completion_photos/{uid}/`, `user_avatars/{uid}.png` | emulator: full footprint |
| Journal, challenges, aiUsage, profile | `recursiveDelete(users/{uid})` | emulator: full footprint |
| Leaderboard, username, feedback | `leaderboard_public/{uid}`, `usernames` where `uid ==`, `feedback` where `userId ==` | emulator: full footprint |
| Every user-data collection covered | All `firestore.rules` collections compared: only global `challenges` and `achievements` aren't touched (they hold no user data) | Source review (7F) |
| Missing or partial data | Every step tolerates absence | emulator: no-data account; data left after the Auth user is gone |
| Storage failure, Firestore failure, Auth failure, interruption | Error returned, later steps not run, **Auth user deleted last**, every step idempotent, so a retry finishes | unit: failure at every step + retry; emulator: Storage and Auth failure + retry |
| Never success while cleanup remains | `{deleted: true}` only after all steps; other Auth errors are errors | unit |
| Not stranded | The Auth user survives every failure, so the user can sign in and retry | unit + emulator |
| Concurrent requests | Both finish, nothing left | emulator |
| Upload during deletion | Second sweep after the Firestore steps; **7F:** final rules refuse uploads once `users/{uid}` is gone (`PHASE_7F_LATE_UPLOAD_MITIGATION.md`) | emulator: late upload removed; rules: P71/P72 |
| Second sweep bounded | Runs **once**, no loop. A concurrent uploader can't extend it. With the 7F rules, no upload can land after step 4. | Source review; unit order test |
| Download links | Objects deleted, so their token URLs die | emulator: links dead after deletion |
| Sanitized outcome | One log line: uid + counts | Source review |
| Accurate client status | Re-auth → server → sign-out; "couldn't confirm, retrying is safe" on timeout; "isn't available … not deleted" when the function is missing | Flutter tests |

## 3. Partial deletions from the live app: recovery plan (design only; no production access)

**Who may be affected:** users with **zero completions** who pressed Delete Account in the live web app. In that case the live cascade deleted:
- `users/{uid}/challenges/*`;
- `users/{uid}/memories/*` (the Journal);
- `leaderboard_public/{uid}`;
- `usernames/{name}`.

It then failed at `users/{uid}`, so the profile, avatar, photos and Auth user remain (7D §1). Users with ≥1 completion lost nothing.

**Signature** (from the app's invariants):
- `users/{uid}` exists, with `totalCompletions == 0`;
- **and** `usernames/{profile.username}` is missing or not owned by `uid`.

Every legitimate profile holds a claimed username: the Firestore rules require it at creation, and later renames are atomic. A returning user gets the leaderboard mirror back at sign-in, but not the username claim, so a missing claim is the durable trace. A Journal and challenge list that are both empty strengthen the signal. They don't prove it alone: a brand-new account can look the same.

**Avoiding false positives:** an empty new account still has its username claim. Only the missing claim marks a candidate, and no automatic deletion is proposed.

**Audit** (needs a new read-only operator command and its own authorization):
- reads `users` (fields `username`, `totalCompletions` only) and `usernames/{name}`;
- outputs counts to stdout and candidate uids to the 0600 `ops-out/` file;
- reads no photos, emails or names.

**Recovery options** (owner and legal decision):
1. **Recommended:** after F-1 + H-1 are live, contact candidates (an email from the Auth record, read only at that point). Say that an earlier deletion request may not have completed, and that Delete Account now works. The user re-confirms in the app, and the server-side function finishes everything. This makes no destructive operator action on an ambiguous signal.
2. Operator-run `deleteAccount`-equivalent for candidates who don't respond within N days. It honours their original request but acts on inference; needs a written policy.

**Communication:** don't say "your data was deleted". Say: "Your deletion request may not have finished. Some data (for example your Journal and username) was removed; your profile and photos were not."

## 4. Deployment sequence (each separately authorized)

| Step | Exact operation | Scope | Verify |
|---|---|---|---|
| **F-1** | `firebase deploy --only functions:deleteAccount --project touchgrass-today` from the repo root | Creates one gen-2 function in `us-central1`. **First functions deploy in this project:** enables Cloud Functions, Cloud Build, Artifact Registry, Cloud Run, Eventarc, Pub/Sub and Cloud Storage APIs; creates service identities; may grant service-agent IAM roles; may ask for an Artifact Registry cleanup policy (choose a short retention). | **Abort** if it prompts for any secret, lists any function other than `deleteAccount`, or names another region. After: `firebase functions:list` → only `deleteAccount`. |
| **H-1** (with R-1, S-2, I-1) | `flutter build web --release` (never with `secrets.json`), then `firebase deploy --only hosting --project touchgrass-today` | Both Hosting targets | Bundle scan before deploy; the new client's deletion flow |
| **E2E** | Two dedicated test accounts, A and B (`PHASE_7E_ACCOUNT_DELETION_RELEASE_PLAN.md` §6) | Test data only | A's footprint gone everywhere; A's old photo link 403/404; B unchanged; one log line; a network-cut retry for B says "couldn't confirm" and the retry succeeds |

No rules or configuration change is needed for deletion itself. The profile requirement in S-2 belongs to the late-upload mitigation.

**Rollback:** `firebase functions:delete deleteAccount --region us-central1 --project touchgrass-today`. The new client then says the feature "isn't available"; nothing is deleted.
