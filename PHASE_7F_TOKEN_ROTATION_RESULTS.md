# Phase 7F — Challenge-photo token rotation: audit, experiment and staged plan

**Status: Legacy links NOT remediated.** No production inventory, experiment or rotation was run in 7F.
- **Blocker:** this machine has no Google Cloud credentials for the operator tools. `gcloud` isn't installed and no Application Default Credentials (ADC) exist (checked 2026-10-21, existence only).
- **Proven so far (7E):** an existing token URL opens a photo without sign-in in production.
- **Not yet proven:** that removing a token stops that URL.

## 1. Phase B — dry-run audit (done locally)

Command reviewed: `node lib/ops/opsCli.js photo-token-rotate --project touchgrass-today --real-project --out ../ops-out/rotation/dry-1.json --max 1000`.

**Call graph checked:** `opsCli.main` → `refusal` → `rotatePhotoTokens(adminTokenStore, adminReferenceDeps, {mode: "dry-run"})`.

| Requirement | Finding | Action |
|---|---|---|
| Dry-run is read-only | **It was not.** The CLI took the shared lease `_ops/photoRewrite_lease` before every rotation, so a dry-run wrote and updated a Firestore document in production. `orphan-photos` did the same with its own lease, and so did a `photo-metadata-remediate` dry-run. | **Fixed:** `leaseFor(args)` returns no lease unless `--execute`. Unit test (every command's dry-run takes no lease); **emulator test runs the real CLI and asserts no `_ops` document and no object generation or metageneration changed.** |
| No tokens, metadata, Firestore or photo writes; no backups | Confirmed. In dry-run the rotation only lists, reads object metadata and queries references. The write paths (`patchMetadataIfUnchanged`, `rewriteIfGeneration`, `updateReference`) are reachable only with `mode === "execute"`. | Existing unit test "dry-run: writes nothing, downloads no photo content". |
| Reads only what's needed | **The reference queries read whole documents**, so completions' location fields and captions entered the process's memory (never output). | **Fixed:** field mask, so only `photoUrl` is read (`.select("photoUrl")`). Emulator test confirms the masked query still finds every link. |
| Output protected, excluded from Git | `--out` is written with mode 0600; `ops-out/` is in `.gitignore` (line 48). stdout carries counts only. | Existing tests. |
| Right project and bucket | The bucket defaults to `<project>.firebasestorage.app`. A foreign `--bucket` or the look-alike project could still be named. | **Fixed:** real-project runs refuse any `--bucket` other than the project's own, and refuse `gen-lang-client-0754598293`. The summary now prints `project` and `bucket`. Unit tests. |
| `--max 1000` truncation reported | `limitReached: true` plus `moreRemaining` in the summary when capped; the page cursor stays in the private file. A capped dry-run couldn't be resumed without pasting the cursor (an object path) into the shell. | **Fixed:** `--resume <dry-run file>` continues the listing (dry-run only; an execute run can't resume from a dry-run file). Unit tests: exact cap = complete; over cap = `limitReached`. |
| Scope: challenge photos only | Lists `completion_photos/` only. `user_avatars/` and `metadata_backup/` are outside the prefix; names must match `completion_photos/{uid}/{date or timestamp}.jpg` with a safe uid, otherwise `skipped-name`. | Existing tests. |
| Data-model inconsistencies | Not reported before. | **Added `referenceAnomalies`:** an owner's link to another user's photo (`otherOwnerPath`; it would break when that photo rotates), another bucket or host, unparseable, or no token. Counted once per user. Unit and emulator tests. |
| Where links are stored | Verified in the app: challenge-photo links live only in `completions.photoUrl` and `users/{uid}/memories.photoUrl`. Other `photoUrl` fields are avatars. | — |

**What the authorized dry-run reads:**
- object names and metadata (including the token list, held in memory only) under `completion_photos/`;
- for each user reached, the `photoUrl` field of their `completions` (`userId == uid`) and `users/{uid}/memories` documents.

**It reads no photo bytes and writes nothing in production.** Output: counts on stdout; object names (which contain uids) in the private file.

**Cost:**
- about one list call per 1000 objects, one metadata GET per photo, and two queries per user;
- Firestore reads are about 1 per document (masked queries are still billed per document);
- for ≤1000 photos this is well under $0.01.

## 2. Phase C — controlled revocation experiment (prepared, not run)

**Tool:** `functions/src/ops/revocationExperiment.ts` (new). It uses the **real** rotation CLI for the token steps. Rehearsed end to end on the emulators (`ops7c.emulator.test.ts`, "revocation experiment harness — rehearsal"):
- rewrite removal → verdict `revoked`;
- metadata removal on the emulator (which merges token lists) → tool `verify-failed`, harness `not-revoked`.

So the harness can't report a false success.

**What `setup` creates (synthetic, in production):**
- two Auth users, `tg-p7f-revocation-{owner,other}-<random>@example.com`, with random passwords that are never printed;
- one 16×16 metadata-free JPEG at `completion_photos/<owner>/2026-01-01.jpg`;
- one Journal document, `users/<owner>/memories/p7f-revocation`, holding its link.

No profile, no leaderboard entry, nothing other users can see.

**Verdict rule** (`interpretRevocation`, unit-tested):
- **`revoked`** only if, in every one of ≥3 samples spaced ~30 s apart, the old URL is refused (401/403/404) **and** the current link opens the photo in that same sample. This rules out outages and transient errors.
- **`not-revoked`** if the old URL opens even once.
- **`inconclusive`** otherwise.

**Every probe also checks:**
- MD5, content type and cache control unchanged;
- the owner can read through the Storage API, and the other test account gets 403;
- exactly one test object and one Journal document exist.

### Sequence and approval gates

Run from `functions/` after `npm ci && npm run build`. The state file holds the test accounts' passwords and the test photo's tokens; it stays under the git-ignored `ops-out/` and is deleted at cleanup.

| Step | Command | Writes | Gate |
|---|---|---|---|
| E-1 setup | `node lib/ops/revocationExperiment.js setup --project touchgrass-today --confirm-project touchgrass-today --state ../ops-out/experiment/state.json` | 2 Auth users, 1 object, 1 Firestore doc | **Approval AC-3a** (covers E-1…E-4 and E-7) |
| E-2 baseline | `node lib/ops/revocationExperiment.js probe --stage before --state ../ops-out/experiment/state.json` | none | AC-3a |
| — | Wait ≥ 11 min (the tool skips photos changed in the last 10 min) | — | — |
| E-3 add + move link | `node lib/ops/opsCli.js photo-token-rotate --project touchgrass-today --real-project --execute --confirm-project touchgrass-today --uid <testOwnerUid> --run-id p7f-exp --stop-before-remove --out ../ops-out/experiment/rotate-1.json` | metadata patch on the test object; 1 doc update; lease doc `_ops/photoRewrite_lease` | AC-3a |
| E-4 paused | `… probe --stage paused …` (old and new both open; link moved) | none | AC-3a |
| E-5 remove old | the same `photo-token-rotate` command **without** `--stop-before-remove`, `--run-id p7f-exp`, default `--remove-via metadata` | metadata patch | **Separate approval AC-3b** |
| E-6 verdict | `… probe --stage after --samples 5 --interval-ms 30000 …`, then repeated after ≥ 15 min (beyond the 300 s cache lifetime) | none | AC-3b |
| E-7 cleanup | `node lib/ops/revocationExperiment.js cleanup --state ../ops-out/experiment/state.json` | deletes everything from E-1 | AC-3a |

**Interpreting the result:**
- **`revoked` twice (immediately and ≥ 15 min later):** metadata removal revokes in production. Plan §3 may proceed with `--remove-via metadata`.
- **`not-revoked`:** stop. The next experiment is `--remove-via rewrite` on a fresh test object (same gates). If that is also `not-revoked`, rotation can't revoke links. The remaining options (deleting and re-creating objects under new names, or serving photos without token URLs) change the photo access model and need a separate design decision.
- **`inconclusive`:** repeat the probes. No conclusion until two `revoked` runs.

## 3. Staged production rotation (plan only)

Only after AC-3 shows `revoked`. Each stage is a separate approval (AC-4.n).

| Item | Plan |
|---|---|
| Eligibility | `completion_photos/{safeUid}/{date or timestamp}.jpg` with ≥1 token, unchanged for ≥10 min. Never `user_avatars/`. |
| Expected volume | From the AC-2 dry-run (`inspected`, `would-rotate`). Unknown until then. |
| Batches | Canary = the experiment. Then: AC-4.1 `--max 25`, AC-4.2 `--max 250`, AC-4.3 the remainder in runs of ≤1000. The tool processes one photo at a time (about 5 API calls each), which is its throttle. |
| Checkpoints | Each run's `--out` file; continue with `--resume <file>` (reuses the run id; finished photos skipped). |
| Idempotency | Rotation state on the object (`tgTokenRotation`, `tgTokenRotationState`, `tgTokenRotationNew` = a 16-hex hash, never the token). An interrupted photo resumes without a second new token. |
| Concurrency | Generation/metageneration preconditions on every object write; transactional link updates that only change a link still naming the same object; the shared lease stops two runs at once. |
| Partial failure | Links move before the old token is removed, so no saved link ever points at a dead token (invariant tested on every write). Failures are recorded per photo with the error class only. |
| Missing owner documents | `photosWithoutReferences`: rotated anyway (nothing to update); the old URL dies. |
| Broken links | `photosWithStaleReferences`: already broken before the run; reported, not repaired. Repair needs an owner decision. |
| Link anomalies | `referenceAnomalies.otherOwnerPath > 0` → **stop and review before rotating those users**: such a link would break. |
| Verification | Per photo, the tool confirms exactly one stored token (the new one) and an unchanged MD5. Revocation itself is proven by AC-3, because old tokens are never kept. After each stage, sample 5 rotated photos in the app with a test account's eyes: the owner's Journal still shows them. |
| Stop conditions | Any `verify-failed`, `references-failed` or `rotate-failed` above 1%; any `otherOwnerPath`; any user report of a missing photo. |
| Recovery | A photo stuck at `added` keeps both tokens (nothing broken): resume. There's no way to restore an old token; that is the point. |
| Audit | Counts per stage in `PHASE_7F` or later reports; the private `--out` files stay under `ops-out/` and are deleted after the incident closes. |

## 4. What can't be claimed yet

- That rotating a token invalidates the old URL in production: **unproven** until AC-3b.
- That any harvested link is dead: **no**, nothing has been rotated.
