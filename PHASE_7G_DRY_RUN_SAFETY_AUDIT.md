# Phase 7G — Dry-run and read-only safety audit

**Status:**
- Every operator command's dry-run is **proven read-only locally**, by mutation-trapping fakes and by full emulator snapshots.
- A central operation mode, exact production allowlists and fail-closed environment checks were added.
- Not run against production: no credentials on this machine.

## 1. Why this was re-audited

Phase 7F found that commands described as dry-runs **wrote a lease document to production Firestore**, and fixed it. Phase 7G treats that as a regression risk. Every command, flag and helper that could run against production was traced to the client methods it can call.

## 2. Inventory of commands

All live in `functions/src/ops/`; none is deployed. Run from `functions/` after `npm run build`.

| Command (mode) | Reads | Writes in production | Local output |
|---|---|---|---|
| `photo-token-rotate` (dry-run) | Bucket listing of `completion_photos/`; each object's metadata, held in memory: token list, generation, MD5, updated time. For each user reached, **only the `photoUrl` field** (field mask) of `completions` (`userId == uid`) and `users/{uid}/memories`. | **None**: no lease, no token, no metadata, no link. | `--out` file (new, 0600, under `ops-out/`): object names (contain uids), counts, the page cursor. stdout: counts. |
| `photo-metadata-inventory` (always read-only) | Listing; the first 128 KB of each photo, or **all bytes** with `--full-read` | **None** | Names, generation, category (never coordinates) |
| `photo-metadata-remediate` (dry-run) | The manifest (local); each listed photo's metadata and full bytes. It validates a stripped copy **in memory**. | **None**: no backup, no rewrite, no lease | Per-photo outcomes |
| `orphan-photos` (dry-run) | Listing; **existence only** (empty field mask, Phase 7G) of each photo's completion, Journal entry and profile | **None**: no deletion, no lease | Names and outcomes |
| `profile-photo-inventory` (always read-only) | **Only `photoUrl`** of `users` (field mask, Phase 7G; it used to read whole profiles, including email and settings) | **None** | Counts by URL kind; uids by kind in the file |
| `revocationExperiment probe` | The test photo's metadata, the test Journal document, the old and new token URLs (GET), signed-in metadata reads by the two **test** accounts | Signing the test accounts in updates their last-sign-in time (Auth) | The state file |
| `revocationExperiment setup` / `cleanup` | — | **Yes: test data only** (`--mode test-object-mutation`) | The state file; a redacted record after cleanup |
| `tool/export_live_rules.mjs` | Rules releases and rulesets through the Firebase MCP tool, which it refuses to call unless the tool is marked `readOnlyHint` | None | Snapshot under `ops-out/` |
| `tool/check_firebase_config.mjs --live` | `apps:list`, `apps:android:sha:list` | None | stdout |

**Resume:** `--resume <file>` reads a local file only. A capped rotation or inventory dry-run continues from the saved cursor, with no write.

## 3. Defects fixed in Phase 7G

| # | Finding | Fix | Evidence |
|---|---|---|---|
| G-1 | "Read-only unless `--execute`" was the only mode switch | **Central operation mode** `--mode read-only` (the default) / `test-object-mutation` / `production-mutation`. Writing needs `--execute` **and** a mutation mode; a mode without `--execute` is refused. `test-object-mutation` is only for `photo-token-rotate --uid <one test account>`. | Unit tests |
| G-2 | The bucket check accepted `<project>.appspot.com`, and any project name was usable against production | **Exact allowlist:** project `touchgrass-today` ↔ bucket `touchgrass-today.firebasestorage.app`. Anything else is refused before a client exists. | Unit tests |
| G-3 | With only one emulator host set, Firestore would hit the emulator while Storage hit production (or the reverse) | **Mixed environments are refused.** Emulator runs must use a `demo-` project id, which Firebase guarantees can't reach production. | Unit tests |
| G-4 | A `GCLOUD_PROJECT`/`GOOGLE_CLOUD_PROJECT` naming a different project could leave the environment ambiguous | Refused when it differs from `--project` | Unit tests |
| G-5 | `--out` could be any path (e.g. inside `functions/`, which a functions deploy uploads, or `build/web/`) and silently **overwrote** an existing file | Real-project runs must write under the git-ignored `ops-out/`; **an existing file is refused** (written with the `wx` flag) | Unit test + CLI subprocess test |
| G-6 | A malformed `--resume`/`--manifest` file produced a JSON parser message that can quote the file (object names, uids) | A fixed message ("can't be read as JSON") | CLI subprocess test (a planted "SECRET-UID" never appears) |
| G-7 | `profile-photo-inventory` read whole profiles; `orphan-photos` read whole completion and Journal documents | Field masks: only `photoUrl`, or existence only | Read-only tests; emulator snapshot run |
| G-8 | The experiment's setup and cleanup needed no explicit mutation mode; partial emulator variables weren't refused | `--mode test-object-mutation` is required in production; partial emulator variables and non-`demo-` rehearsals are refused | Unit tests |

## 4. How "read-only" is proven

1. **Mutation-trapping fakes** (`functions/src/ops/readOnlyGuarantee.test.ts`, 15 tests):
   - Each command runs through the real `runCommand`, the CLI's own dispatch including the Admin adapters, against fakes that expose only an allowlist of read methods (`getFiles`, `file`, `getMetadata`, `download`, `exists`, `collection`, `doc`, `getAll`, `where`, `select`, `orderBy`, `limit`, `startAfter`, `get`).
   - Any other call — `set`, `update`, `delete`, `runTransaction` (leases), `batch`, `save`, `setMetadata`, `deleteFiles` and so on — is recorded and throws.
   - Covered: every command's dry-run, including `--full-read` and `--uid` inventories, a resumed capped rotation, a failing object, unreadable photos, and a remediation dry-run from a real inventory manifest.
   - **Control:** an `--execute` rotation is caught at its lease (`runTransaction`), so the guard demonstrably works.
2. **Emulator snapshot** (`ops7c.emulator.test.ts`, "EVERY CLI dry-run command…"):
   - the compiled CLI runs as a subprocess, for all six dry-run variants;
   - **every Firestore document's update time** (recursively, all collections) and **every object's generation and metageneration** must be identical before and after;
   - stdout must carry no names, uids or tokens.

Results are in `PHASE_7G_FINAL_REPORT.md` §17.

## 5. What remains unproven

- Behaviour against **production** itself (no credentials).
- The dry-run's reads are bounded by `--max`. A capped run reports `limitReached: true` and "moreRemaining" and is continued with `--resume`, so nothing is skipped silently.

## 6. Output handling

`ops-out/` is git-ignored (`.gitignore` line 48), outside `functions/` and `build/`, so it can't be deployed or bundled. Files are created owner-only, never overwritten, and hold names, never tokens, URLs or coordinates.

**Retention:** keep the rotation and inventory files until the incident is closed, then delete them by hand (`ops-out/rotation/`, `ops-out/metadata/`). Nothing deletes them automatically.
