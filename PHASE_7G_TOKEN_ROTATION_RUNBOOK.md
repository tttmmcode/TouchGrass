# Phase 7G — Challenge-photo token rotation runbook (AC-1 → AC-3)

**Status:**
- **Legacy links not remediated.** Nothing has run in production.
- **Blocker:** this machine has no Google Cloud CLI and no Application Default Credentials (checked 2026-10-21, existence only).

This runbook supersedes the commands in `PHASE_7F_TOKEN_ROTATION_RESULTS.md`, which stays as the record. Since 7G every writing step needs an explicit `--mode`.

## 0. Prerequisites (owner, own terminal)

1. Install the Google Cloud CLI and run `gcloud auth application-default login` with the Google account that owns `touchgrass-today`. Don't paste anything from that flow into chat.
2. From the repo root: `cd functions && npm ci && npm run build && npm test`. Expect all tests to pass (see the 7G final report for the count).
3. Create the output folders: `mkdir -p ../ops-out/rotation ../ops-out/experiment` (git-ignored, not deployable).

## AC-1 — Read-only challenge-link inventory

```
node lib/ops/opsCli.js photo-token-rotate --project touchgrass-today --real-project --out ../ops-out/rotation/dry-1.json --max 1000
```

| | |
|---|---|
| Mode | `read-only` (default; the summary prints `"operationMode": "read-only"`) |
| Reads | Object names and metadata under `completion_photos/` (token lists held in memory only); the **`photoUrl` field only** of each reached owner's `completions` and `users/{uid}/memories` |
| Photo bytes | None |
| Writes | **None in production** (no lease since 7F; proven by the 7G mutation-trap and emulator snapshot tests). One new local file under `ops-out/`, owner-only, never overwritten. |
| Sensitive output | The file contains object names, which include uids. Don't share it; report aggregates only. |
| Cost | About 1 list call per 1000 objects, 1 metadata GET per photo, 2 masked queries per user: well under $0.01 for 1000 photos |
| If capped | The summary shows `limitReached: true` and `moreRemaining`. Continue with `--resume ../ops-out/rotation/dry-1.json --out ../ops-out/rotation/dry-2.json` (still read-only). |
| Stop if | Any permission error; `operationMode` other than read-only; `bucket` other than `touchgrass-today.firebasestorage.app` |

**Share back (aggregates only):**
- `inspected`, `counts`, `limitReached`;
- `photosWithoutReferences`, `photosWithStaleReferences`;
- `referenceAnomalies.*`;
- `writes` (the prediction for a real rotation).

**How to read them:**
- `would-rotate` = eligible photos.
- `photosWithoutReferences` = photos no owner document names; they still rotate.
- `photosWithStaleReferences` = links already broken; reported, not repaired.
- `referenceAnomalies.otherOwnerPath > 0` → **stop**: those links would break when the other user's photo rotates. Review before any stage.
- `too-recent` = changed in the last 10 minutes; it will be included next time.
- `skipped-name` = unexpected object names (never written).

## AC-2 — Dedicated test-photo revocation experiment

**Goal:** prove in production that removing a token makes its old URL stop working, before any real photo is touched. Rehearsed on the emulators every test run: rewrite removal → `revoked`; the emulator's merging metadata patch → `not-revoked`, never a false success.

| Step | Command | Writes | Approval |
|---|---|---|---|
| 1 Setup | `node lib/ops/revocationExperiment.js setup --project touchgrass-today --confirm-project touchgrass-today --mode test-object-mutation --state ../ops-out/experiment/state.json` | 2 test Auth users (`tg-p7f-revocation-{owner,other}-<random>@example.com`, random passwords never printed), one 16×16 metadata-free JPEG at `completion_photos/<testOwner>/2026-01-01.jpg`, one Journal doc holding its link | **AC-2a** (covers steps 1–4 and 8) |
| 2 Baseline | `node lib/ops/revocationExperiment.js probe --stage before --state ../ops-out/experiment/state.json` | None (test sign-ins update their last-sign-in time) | AC-2a |
| — | **Wait ≥ 11 minutes** (photos changed in the last 10 minutes are skipped) | — | — |
| 3 Add the new token and move the link | `node lib/ops/opsCli.js photo-token-rotate --project touchgrass-today --real-project --execute --mode test-object-mutation --confirm-project touchgrass-today --uid <testOwnerUid> --run-id p7g-exp --stop-before-remove --out ../ops-out/experiment/rotate-1.json` | Metadata patch on the test object; 1 doc update; lease doc `_ops/photoRewrite_lease` | AC-2a |
| 4 Paused probe | `… probe --stage paused …`: the old and new links both open; the saved link has moved | None | AC-2a |
| 5 **Remove the old token** | The same `photo-token-rotate` command **without** `--stop-before-remove`, `--run-id p7g-exp`, new `--out ../ops-out/experiment/rotate-2.json` | Metadata patch | **AC-2b, separate** |
| 6 Verdict | `… probe --stage after --samples 5 --interval-ms 30000 …` | None | AC-2b |
| 7 Verdict again ≥ 15 min later | Repeat step 6 (beyond the 300 s cache lifetime) | None | AC-2b |
| 8 Cleanup | `node lib/ops/revocationExperiment.js cleanup --mode test-object-mutation --state ../ops-out/experiment/state.json` | Deletes exactly what step 1 created (both test users, the object, the user's Firestore tree); keeps a redacted record | AC-2a |

**What each probe checks:**
- the MD5, content type and cache control are unchanged;
- the owner can read through the Storage API, and the other test account gets 403;
- exactly one test object and one Journal document exist;
- stage-specific token checks.

**Verdict rule:**
- `revoked` only if the old URL is refused (401/403/404) in **every** sample *and* the new link opens in the same sample;
- `not-revoked` if it opens even once;
- otherwise `inconclusive`.

**Decision:**
- **`revoked` twice:** proceed to AC-3 with `--remove-via metadata`.
- **`not-revoked`:** stop. Repeat AC-2 with `--remove-via rewrite` on a fresh test object. If that also fails, bulk rotation can't revoke links, and the remaining options (re-creating objects under new names, or serving photos without token URLs) are architecture decisions.
- **`inconclusive`:** repeat the probes. No conclusion until two `revoked` runs.

**Cleanup failure:** the command reports which of photo, Journal document and old-URL check didn't pass, and exits 1. The state file is kept so cleanup can be re-run. Nothing outside the recorded test identities is touched.

## AC-3 — Staged rotation (each stage separately approved)

**Preconditions:**
- AC-2 `revoked` twice;
- the AC-1 aggregates reviewed;
- `referenceAnomalies.otherOwnerPath` = 0, or the affected users excluded after review.

**Stage commands** (the `--max` values are the stage sizes; adjust them to AC-1's `would-rotate`):

```
node lib/ops/opsCli.js photo-token-rotate --project touchgrass-today --real-project --execute --mode production-mutation --confirm-project touchgrass-today --max 25  --out ../ops-out/rotation/stage-1.json
node lib/ops/opsCli.js photo-token-rotate --project touchgrass-today --real-project --execute --mode production-mutation --confirm-project touchgrass-today --resume ../ops-out/rotation/stage-1.json --max 250 --out ../ops-out/rotation/stage-2.json
node lib/ops/opsCli.js photo-token-rotate --project touchgrass-today --real-project --execute --mode production-mutation --confirm-project touchgrass-today --resume ../ops-out/rotation/stage-2.json --max 1000 --out ../ops-out/rotation/stage-3a.json   # repeat with --resume until nothing remains
```

| Item | Rule |
|---|---|
| Selection | `completion_photos/{safeUid}/{yyyy-MM-dd or 10–16 digit timestamp}.jpg` with ≥1 token, unchanged for ≥10 min. Profile photos are **never** included (different prefix). |
| Throughput | One photo at a time, about 5 API calls each. That is the rate limit; a 250-photo stage takes minutes. |
| Order per photo | Add the new token (old one still valid) → update owner links in transactions → remove the old token → verify exactly one token and an unchanged MD5 |
| Resume and idempotency | `--resume` reuses the run id and skips finished photos. A photo interrupted mid-way keeps its added token (state on the object) and is finished, never given a second token. |
| Concurrency | Generation and metageneration preconditions on object writes; transactional link updates that only change a link still naming the same object; the shared lease blocks parallel runs |
| Retries | Re-run with `--resume`. A photo failing twice is excluded and reviewed by hand. |
| Missing owners / broken links | Missing owners: rotated (no link to update). Broken links: counted, not repaired. |
| Verification | Per photo, the tool verifies the stored token list = the new token only. Old-link death is proven by AC-2, since old tokens are never stored. After each stage, the owner's Journal is checked in the app with a test account (sample). |
| Stop | Any `verify-failed`; `references-failed` or `rotate-failed` > 1%; any `otherOwnerPath`; any user report |
| Audit | Aggregate counts per stage in the next phase report; `--out` files stay private in `ops-out/` |
| Rollback | None for revocation, by design. A photo stuck at `added` still has both tokens: nothing is broken; resume. |
| Photo bytes | Not touched with the default `--remove-via metadata` |
