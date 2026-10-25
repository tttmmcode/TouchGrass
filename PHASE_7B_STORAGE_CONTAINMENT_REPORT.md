# Phase 7B — Storage Containment Report

## Status: **NOT DEPLOYED** (awaiting explicit authorization)

Everything below is read-only investigation and local testing. No production resource has been changed. This section and §6–§7 will be updated if a deployment is authorized and performed.

## 1. Incident summary

The live Firebase Storage rules of `touchgrass-today` let **any signed-in user**:
- read, download, get metadata for, and obtain **tokenized download URLs** for every user's challenge (completion) photos;
- list any user's photo folder;
- list the `completion_photos` root, which **enumerates every user's folder (uid)**. This was newly found in 7B; Phase 7A had reported only per-user access.

Sign-up is open to anyone, so in practice any member of the public who creates an account can do this. Photos uploaded by earlier app versions may contain GPS coordinates in their metadata (B11).

The same rules let owners store any file type, of any size, at any path in their folder. They have no rule for `user_avatars/`, so profile-photo changes fail in the live app.

## 2. Verified facts (independently re-checked in 7B)

Commands were checked in `firebase help` and the firebase-tools source before they were run.

| Fact | Evidence |
|---|---|
| Target project | `firebase projects:list`: `touchgrass-today`, display name "TouchGrass", project number **760620662222**. The `apps:sdkconfig` project number and `project_id` match; `.firebaserc` default; `firebase_options.dart`. |
| Look-alike project | `gen-lang-client-0754598293`, also named "TouchGrass" (project number 616088093807). Nothing in the repo or the live web bundle references it. **Not the target.** |
| Storage bucket | `touchgrass-today.firebasestorage.app`: the `apps:sdkconfig` `storage_bucket`, `firebase_options.dart`, and the **only** bucket referenced by the public live web bundle (both sites serve the same `main.dart.js`, sha256 `eebdffefb406cc5c…`). The CLI releases Storage rules to the project's default bucket, read from the Firebase Storage API. |
| Live Storage rules | Read-only exports at 19:31Z and 23:54Z on 2026-10-19 (`tool/export_live_rules.mjs` → CLI MCP `get_security_rules`, `readOnlyHint`, GET only). Both are byte-identical, SHA-256 `c550222392960371d52680406c5b18657b20a530de5f7ce84f1d18c04729579d`. They match **no committed version** of `storage.rules`. |
| How the live web app uses Storage | Public `main.dart.js`:<br>• completion: `completion_photos/{uid}/{Date.now()}.jpg`, `image/jpeg`, client check < 10 MB, then `getDownloadURL`;<br>• avatar: `user_avatars/{uid}.png`, `image/png`, < 5 MB, then `getDownloadURL`;<br>• avatar delete (not-found tolerated);<br>• client-side account deletion: `listAll(completion_photos/{uid})`, then delete each item. |
| Exposure behaviour | Emulator-proven with the exact live ruleset: matrix T03–T07 ALLOW, T14–T19 ALLOW (`PHASE_7B_STORAGE_TEST_MATRIX.md`) |
| Firestore exposure of stored photo URLs | Live Firestore rules: `completions` and `users/{uid}/memories` (which hold the tokenized photo URLs) are **owner-only**. Tokens did not leak through Firestore. |

## 3. Before and after, per path

The interim rules are `deploy/interim/storage.interim.rules`, SHA-256 `630dc9a02b1985b144a72ef847a9582adf2befc47a979d9ce55478b216dcff17`.

### `completion_photos/{uid}/{file}` (challenge photos)

| Actor | LIVE (today) | INTERIM |
|---|---|---|
| Unauthenticated | Denied | Denied |
| Owner: get / download URL / metadata | Allowed | Allowed |
| Owner: list own folder | Allowed | Allowed (`match /completion_photos/{userId}`, list) |
| Owner: upload | **Anything**: any name, depth, type or size | Only `{yyyy-MM-dd}.jpg` or `{10–16 digits}.jpg`, `image/jpeg\|png\|webp\|heic\|heif`, < 10 MB |
| Owner: delete own | Allowed | Allowed (the live app's account deletion needs it) |
| Signed-in non-owner: get / URL / metadata | **ALLOWED** | **Denied** |
| Signed-in non-owner: list folder | **ALLOWED** | **Denied** |
| Signed-in: list the `completion_photos` root | **ALLOWED** (enumerates every uid) | **Denied** |
| Non-owner: upload / overwrite / delete / change metadata | Denied | Denied |

### `user_avatars/{uid}.png` (profile photos)

| Actor | LIVE | INTERIM |
|---|---|---|
| Unauthenticated read | Denied | Denied |
| Signed-in: get one avatar | Denied (no rule) | Allowed. The leaderboard shows avatars to signed-in users, though through stored token URLs. |
| Signed-in: list all avatars | Denied | **Denied.** Fixed in 7B: the Phase 7A file used `allow read`, which includes `list` and let anyone enumerate every avatar (matrix T33). |
| Owner: upload own `{uid}.png`, image, < 5 MB | **Denied** (avatar change broken today) | Allowed |
| Non-owner: overwrite; owner: other names or oversize | Denied | Denied |
| Owner: delete own avatar | Denied | Denied (unchanged; the live app tolerates it) |

### Everything else

- `metadata_backup/…` and any other path: **denied** in both. LIVE has no catch-all, but nothing matches those paths, so the default is deny. INTERIM has an explicit catch-all deny.
- Bucket-root listing: denied in both.

### Overlapping matches

Storage rules OR together every matching `allow`.
- In INTERIM, each path shape is matched by exactly one granting block:
  - `user_avatars/{f}`: one segment under that folder;
  - `completion_photos/{u}/{f}`: two segments;
  - `completion_photos/{u}`: list only, one segment.
- `/{allPaths=**}` only ever says `false`, so it can't grant anything.
- No wildcard of the form `{x=**}` grants access.
- Verified by T07, T08, T18 and T33–T36.

## 4. Upload validation limits

- The rules check the **declared** content type, the size, the path and the name. **They can't inspect the bytes.** Non-image bytes declared as `image/jpeg` are accepted (matrix T37).
- Firebase serves an object with its declared type, so a mislabelled file is served as an image.
- Validating real contents needs app-side or server-side checks. That's a documented limitation, not addressed here.

## 5. Tokenized download URLs: what the rules change does NOT fix

**Two kinds of access:**
- **SDK reads**: `getBytes`, `getMetadata`, `listAll` and `getDownloadURL`. Storage rules evaluate these, and the interim rules restrict them.
- **Token URLs**: `https://firebasestorage.googleapis.com/v0/b/<bucket>/o/<path>?alt=media&token=<t>`. These are served to **anyone holding the URL, without evaluating rules**. A rules deploy does not revoke tokens.

**Consequences:**
- Under the live rules, any signed-in user could call `getDownloadURL` on any listed photo (T04) and **keep that URL**. **Every URL obtained that way stays valid after the interim rules are deployed**, until the token is rotated or the object rewritten.
- Whether anyone did this is **unknown**.
  - Cloud Storage Data Access audit logs are off by default. **[OWNER]** Check Cloud Console → IAM & Admin → Audit Logs → Cloud Storage → "Data Read".
  - Firebase Storage's own request logs aren't available to this CLI.
- Legitimate token URLs are stored only in owner-readable Firestore documents (completions and Journal), and for avatars in the leaderboard mirror, where they are visible to signed-in users by design.

**Proposed separate remediation** (needs its own authorization; NOT part of this task):
1. Rotate the download token on every completion photo, using the Admin SDK to set a new `firebaseStorageDownloadTokens`. This revokes the old token **in production**.
2. In the same operation, update `photoUrl` in that user's `completions/*` and `users/{uid}/memories/*` documents, so the app keeps working.
3. Dry-run first, on a test account; resumable; with a manifest.

Without step 2, every existing photo link in the app breaks. This should be designed and tested like the Phase 6 metadata tool before it runs.

## 6. Deployment

**Not performed.** The proposed command (runbook §2) is:
```
firebase deploy --only storage --config deploy/interim/firebase.interim-storage.json --project touchgrass-today
```
- **Changed resource:** the Firebase Storage rules release for bucket `touchgrass-today.firebasestorage.app` in project `touchgrass-today`.
- **Nothing else.** `firebase.json` is not used or modified.

## 7. Post-deployment verification

**Not performed** (nothing has been deployed).

## 8. Local test evidence

| Command | Result |
|---|---|
| `cd firestore-tests && npm test` (emulator, `demo-` project) | Exit 0, **424/424**. Includes the 38-case LIVE vs INTERIM matrix, the 14 Phase 7A interim tests, and 6 live-exposure tests. |
| Matrix-only first run (before the fix) | 73/75: **found T07 (LIVE root listing) and T33 (INTERIM avatar listing)**. Fixed the interim rule and recorded the actual LIVE behaviour. |

Emulator results show how each ruleset behaves. They don't prove what is deployed.

## 9. Changes in this phase (local files only)

| File | Change |
|---|---|
| `deploy/interim/storage.interim.rules` | Avatars: `allow read` → `allow get` (no folder listing); header comment updated. Backup: `p7b/bak/`. |
| `firestore-tests/test/storage_containment_matrix.test.mjs` | New: 38 cases × 2 rulesets + the live-app sequence |
| `firestore-tests/test/fixtures/live-storage-2026-10-19.rules` | New: byte-exact copy of the live ruleset (public config, not a secret) |
| `PHASE_7B_STORAGE_CONTAINMENT_REPORT.md`, `PHASE_7B_STORAGE_CONTAINMENT_RUNBOOK.md`, `PHASE_7B_STORAGE_TEST_MATRIX.md` | New |
| `REMEDIATION_CHECKLIST.md`, `KNOWN_BUGS.md` | Phase 7B notes (no "fixed" claims) |
| `ops-out/live-rules/touchgrass-today-20261019T235405Z/` | New read-only snapshot (git-ignored); the earlier snapshot is untouched |
| `ops-out/rollback/storage-live-2026-10-19/` | New rollback artifact (git-ignored) |

## 10. Residual risks (after a successful deployment)

1. **Token URLs harvested while the rules were open stay valid** (§5). This is the main reason containment ≠ resolution.
2. **Historical GPS metadata** in older photos (B11). Anyone holding a URL could read it.
3. **Byte-level type spoofing** (§4).
4. **The final `storage.rules`** uses the same `allow read` construct on avatars that T33 caught. Fix it before the coordinated release.
5. **Unknown past access**; audit logs are probably off.
6. **The live Firestore rules issues** (Phase 7A) remain until the coordinated release.
7. **Possible notification duty** for the past exposure (legal; owner).
