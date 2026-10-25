# Phase 7B — Storage Containment Runbook

**Scope:** deploy ONLY the interim Firebase Storage rules to `touchgrass-today`. Nothing else changes.

**Status:** prepared. Read-only checks have been executed. Deployment and smoke tests are **not executed until the owner explicitly authorizes them**; the report records whether they ran.

**Labels:**
- **READ-ONLY**: changes nothing.
- **⚠️ PRODUCTION**: needs explicit authorization for exactly this scope.

## 1. Preconditions (all must hold)

| # | Check | How (READ-ONLY) | Expected |
|---|---|---|---|
| P1 | Repository state | `git branch --show-current`, `git rev-parse --short HEAD` | `release-hardening-pass`, `67c5a38` |
| P2 | CLI logged in (never log in for this) | `firebase login:list` | One account listed |
| P3 | Target project | `firebase projects:list` → `touchgrass-today` "TouchGrass", number `760620662222`. Cross-check:<br>• `firebase_options.dart` and `google-services.json` use `touchgrass-today` and bucket `touchgrass-today.firebasestorage.app`;<br>• the live web bundle references only `touchgrass-today.firebasestorage.app`. | All agree. **Don't confuse it with `gen-lang-client-0754598293`**, which is also named "TouchGrass". |
| P4 | Live rules unchanged since review | `node tool/export_live_rules.mjs --project touchgrass-today`, then `sha256sum ops-out/live-rules/<new>/storage.rules` | `c550222392960371d52680406c5b18657b20a530de5f7ce84f1d18c04729579d`. **If different, STOP**: someone changed production; re-review. |
| P5 | Interim file unchanged since approval | `sha256sum deploy/interim/storage.interim.rules deploy/interim/firebase.interim-storage.json` | `630dc9a02b1985b144a72ef847a9582adf2befc47a979d9ce55478b216dcff17` and `bccfb9894225ae92db63d45e12bb6c0601d2fd302c817cb728a678804a9d3bb2` |
| P6 | Tests | `cd firestore-tests && npm test` (`JAVA_HOME` = JDK 21+) | 424/424 |
| P7 | Rollback artifact present | `cd ops-out/rollback/storage-live-2026-10-19 && sha256sum -c SHA256SUMS` | Both files OK |
| P8 | The deploy config contains only `storage` | `cat deploy/interim/firebase.interim-storage.json` | `{"storage":{"rules":"storage.interim.rules"}}` |

## 2. Deployment — ⚠️ PRODUCTION

```
firebase deploy --only storage --config deploy/interim/firebase.interim-storage.json --project touchgrass-today
```

**Why this command is narrow** (checked in the firebase-tools 15.19.1 source):
- `--config` makes `deploy/interim/` the project root, so the CLI loads only that file. It contains only `storage`, and `firebase.json` isn't touched.
- `--only storage` restricts the deploy to Storage rules.
- No `.firebaserc` exists in that folder, so the project must be given explicitly with `--project touchgrass-today`.
- The CLI compiles the rules, then releases them to the project's **default bucket**, which it looks up from the Firebase Storage API (`defaultBucket`). That is `touchgrass-today.firebasestorage.app`.

**Expected output:**
- the rules "compiled successfully";
- "released rules storage.interim.rules to firebase.storage";
- "Deploy complete!";
- exit code 0.

**Stop conditions:**
- a nonzero exit;
- any mention of Firestore, Functions or Hosting;
- a project other than `touchgrass-today`;
- a compile error.

If any of these occur: **don't retry with different flags**. Run §3 step 1 read-only to learn the actual state, then report.

## 3. Post-deployment verification

1. **READ-ONLY: the live rules are the interim rules.**
   ```
   node tool/export_live_rules.mjs --project touchgrass-today
   ```
   The new snapshot's `storage.rules` must be byte-identical to `deploy/interim/storage.interim.rules`. Check that the SHA-256 is `630dc9a0…dcff17`, or that `comparison.md` lists Storage as differing **from the repo's `storage.rules`** while a manual `diff` against the interim file is empty.
2. **READ-ONLY: nothing else changed.**
   - The Firestore rules SHA in the new snapshot equals the previous snapshot's.
   - `firebase firestore:indexes` still lists none.
   - `firebase functions:list` still lists none.
3. **Smoke tests (owner, with test accounts only; never real users' photos):**

   | # | Test | How | Expected |
   |---|---|---|---|
   | S1 | Cross-user read denied | Firebase console → Storage → Rules → **Rules Playground**: `get` `/b/touchgrass-today.firebasestorage.app/o/completion_photos/<testA uid>/x.jpg`, authenticated as `<testB uid>` | Denied |
   | S2 | Cross-user list denied | Playground: `list` `/b/…/o/completion_photos/<testA uid>`, as `<testB uid>` | Denied |
   | S3 | Root listing denied | Playground: `list` `/b/…/o/completion_photos`, as `<testB uid>` | Denied |
   | S4 | Unauthenticated read denied | Playground: `get` `/b/…/o/completion_photos/<testA uid>/x.jpg`, unauthenticated | Denied |
   | S5 | Owner access allowed | Playground: `get` as `<testA uid>` | Allowed |
   | S6 | Invalid upload refused | Playground: `create` `/b/…/o/completion_photos/<testA uid>/x.html` as `<testA uid>`, content type `text/html` | Denied |
   | S7 | Live app: completion works | Sign in to `https://touchgrass-today.web.app` as test account A; complete a challenge with a photo | Saves; the photo shows in the Journal |
   | S8 | Live app: avatar change works | Same account: Settings → change photo | Works (it was denied before) |
   | S9 | Live app: existing photos display | Journal and map with existing entries | Images load (token URLs; unaffected) |

   The Rules Playground is a simulator; it reads and changes nothing. S7–S9 use test accounts in the live app.
4. **Monitoring, 48 hours:** Firebase console → Storage → Usage → rules evaluations (denies). A spike of denies on legitimate uploads means a missed shape: stop and report.

## 4. Rollback — ⚠️ PRODUCTION, separate explicit authorization required

**Consequence:** rolling back **restores the cross-user photo exposure**. It is an emergency measure only, for when legitimate use is broken. Prefer a narrow forward fix.

**Prerequisite snapshot:** `ops-out/rollback/storage-live-2026-10-19/`.
- `storage.rules` is a byte-exact copy of the live rules (SHA-256 `c550222392960371d52680406c5b18657b20a530de5f7ce84f1d18c04729579d`), from two identical read-only exports.
- `firebase.json` contains only `storage`.
- `SHA256SUMS` and `README.txt` are included.
- `ops-out/` is git-ignored, so keep this folder until the coordinated release is done.

**Command:**
```
cd ops-out/rollback/storage-live-2026-10-19 && sha256sum -c SHA256SUMS && cd ../../..
firebase deploy --only storage --config ops-out/rollback/storage-live-2026-10-19/firebase.json --project touchgrass-today
```

**Alternative:** Firebase console → Storage → Rules shows the version history, and the previous version can be restored there.

**After a rollback:** re-export read-only and confirm the SHA-256 is `c5502223…29579d`.

## 5. Troubleshooting

| Symptom | Likely cause | Action |
|---|---|---|
| "Firebase Storage has not been set up" | Wrong project | STOP; re-check P3 |
| Compile error | The file changed | STOP; re-check P5 and P6 |
| Permission error | The account lacks Firebase Rules Admin | Owner fixes IAM; don't switch accounts in-session |
| Live app uploads fail after deploy | A shape the tests missed | Collect the error code (no URLs); report; forward-fix or authorized rollback |
| The export shows different live rules | A concurrent change | STOP; the state is unknown; re-review |

## 6. Not in scope (separate authorizations)

- Rotating download tokens or rewriting objects. See report §5 for the proposal.
- The Firestore rules, indexes, Functions, Hosting and the final `storage.rules`.
- Photo inventories and metadata stripping.
