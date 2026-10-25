# Phase 7H — AC-1: read-only photo-link inventory

**Status (2026-10-24):** authorized by the owner. **Not run.** It is blocked on the two steps in §1.

**Scope of the approval:** one read-only inventory of the challenge-photo download links in project `touchgrass-today`
(bucket `touchgrass-today.firebasestorage.app`). No production writes. It authorizes nothing else: no token creation,
revocation or rotation, no metadata/GPS inventory, no deploy, no IAM change.

## 1. What only you can do (in your own terminal)

The Google Cloud CLI is installed (SDK 590.0.0) and signed in. The active account is the same one the Firebase CLI uses,
compared by hash, and the configured project is `touchgrass-today`.

**What's missing:** Application Default Credentials. The file `%APPDATA%\gcloud\application_default_credentials.json`
does not exist, and the operator CLI uses ADC. I will not run this login for you.

```
gcloud auth application-default login
gcloud auth application-default set-quota-project touchgrass-today
```

The first command opens a browser; sign in with the TouchGrass owner account. The second is needed only if the first
doesn't already say "Quota project touchgrass-today was added to ADC".

Then tell me you're ready. Please don't paste any output that contains a token.

## 2. What I check before running it

| Check | How |
|---|---|
| ADC present, account is the owner account | The file exists (never read); `gcloud auth list` account hash equals the Firebase CLI account hash |
| Project and bucket | The CLI accepts only `touchgrass-today` ↔ `touchgrass-today.firebasestorage.app` (exact allowlist) |
| No emulator or project variables set | `FIRESTORE_EMULATOR_HOST`, `FIREBASE_STORAGE_EMULATOR_HOST`, `GCLOUD_PROJECT`, `GOOGLE_CLOUD_PROJECT` unset (the CLI also refuses mismatches) |
| Read-only | No `--execute`, so mode `read-only`. The tests prove it below |
| Output protected | `ops-out/` is git-ignored, and only the owner, SYSTEM and Administrators can access it (NTFS ACL). A new file only, never overwritten |
| Current code | `cd functions && npm ci && npm run build && npm test` passes |

**Read-only proof (local, rerun in 7H):**
- `functions/src/ops/readOnlyGuarantee.test.ts` runs every command through the real dispatch against fakes that throw on
  any write (and a control shows `--execute` is caught).
- `ops7c.emulator.test.ts` snapshots every Firestore document and Storage object before and after all CLI dry-runs.

## 3. The command (run from `functions/`)

```
node lib/ops/opsCli.js photo-token-rotate --project touchgrass-today --real-project --out ../ops-out/rotation/dry-1.json --max 1000
```

**What it reads:**
- the names and metadata of objects under `completion_photos/`;
- for each owner reached, only the `photoUrl` field of their completions and Journal entries (field mask).

**What it doesn't touch:** no photo bytes, and no writes in production, not even a lease.

**What it produces:**
- **stdout:** counts only, plus `"operationMode": "read-only"`, the project and the bucket;
- **`ops-out/rotation/dry-1.json`:** aggregates and per-photo outcomes keyed by a 16-hex hash of the object name. No
  object names, uids, URLs, tokens or generations. Its `nextPageToken`, present only if more than 1,000 photos exist,
  is a Storage cursor that encodes one object path, so the file stays private.

**Cost:** about 1,000 object metadata reads plus a few Firestore reads per user, well under $0.01.

**If `moreRemaining` is shown,** continue the same read-only inventory:
`--resume ../ops-out/rotation/dry-1.json --out ../ops-out/rotation/dry-2.json` (same command otherwise).

## 4. Stop rules

- Any refusal or error: stop, and report only the class and code the CLI prints.
- Don't retry with another account, a broader role, another project, or any write mode.
- A permission error (`code 403` / `PERMISSION_DENIED`) is not fixed by changing IAM under this approval.

## 5. What gets reported back (aggregates only)

- Whether it completed.
- `inspected`, and `counts` (`would-rotate`, `no-token`, `too-recent`, `skipped-name`, `gone`, `rotate-failed`).
- `photosWithoutReferences` and `photosWithStaleReferences`.
- `referenceAnomalies` (`otherOwnerPath`, `otherBucketOrHost`, `unparseable`, `withoutToken`).
- `writes`: the writes a later rotation **would** make.
- `limitReached`.
- Confirmation that the read-only guarantee held.

No object names, URLs, uids, tokens or coordinates.
