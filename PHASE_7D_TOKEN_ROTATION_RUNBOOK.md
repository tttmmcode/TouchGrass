# Phase 7D — Challenge-Photo Token Rotation Runbook

**Status: tool reviewed, redesigned (two-phase) and tested locally. Nothing has run against production.**

**Precondition met in 7D:** the interim Storage rules are live (S-1 deployed 04:30Z on 2026-10-20; the live ruleset is byte-identical to `deploy/interim/storage.interim.rules`). Other users can no longer obtain new links through the SDK, so rotating now is meaningful.

**Blocker:** this machine has no Application Default Credentials (`gcloud` absent; no ADC file). The Admin-SDK tool can't reach production from here until **the owner** sets up credentials (§3.1). I will not log in or handle credentials.

## 1. What the tool does (`functions/src/ops/photoTokenRotation.ts`, `opsCli.js photo-token-rotate`)

**Scope:** only `completion_photos/{uid}/{yyyy-MM-dd | 10–16 digits}.jpg` with a safe uid. Profile photos (`user_avatars/`) and anything else are never touched (`skipped-name`).

**Per photo, in an order that never leaves a saved link pointing at a dead token:**

| Step | Action | Writes | If interrupted here |
|---|---|---|---|
| 0 | Skip if changed in the last 10 min (completion may be saving) or no token | — | — |
| 1 | **Add** a new random token next to the old one (metadata patch, conditional on generation **and** metageneration). Record `tgTokenRotation=<runId>`, `tgTokenRotationState=added`, `tgTokenRotationNew=<16-hex SHA-256 tag>`. | object metadata | Old and new tokens both valid; nothing broken |
| 2 | Point the owner's links at the new token: `completions` (`userId == uid`) and `users/{uid}/memories/*` whose `photoUrl` names this object. Each update is a transaction that rechecks the document. | Firestore `photoUrl` | Some links new, some old, all valid. A resume finds the added token by its tag and finishes. |
| 3 | Only if step 2 raised no error: **remove** the old token(s): `--remove-via metadata` (patch; no bytes touched) or `--remove-via rewrite` (same bytes re-uploaded, generation-checked) | object metadata or content | — |
| 4 | **Verify:** the token list is exactly `[new]`; MD5 is unchanged; otherwise `verify-failed` | — | — |

**Resume:**
- `--resume <out>` reuses the run ID and skips finished photos.
- State `added` reuses the recorded token (never a second one).
- State `done` only finishes links.
- If the recorded token can't be found, the outcome is `verify-failed` and the photo is left for review; the tool never guesses.

**Output privacy:**
- **stdout:** counts only.
- **`--out` file** (mode 0600): object names (they contain uids), generations, outcome, step, link counts, error class.
- **Never written:** tokens, token tags, URLs, photo bytes, captions, locations (unit-tested).

**Concurrency:**
- Shared Firestore lease `_ops/photoRewrite_lease` with the metadata job.
- Every write is conditional on generation or metageneration; atomic in real Cloud Storage (the emulator ignores preconditions, so a read-check runs first).
- A photo deleted mid-run (account deletion) is **not** recreated (unit + emulator).

### Review against the brief (§5.1)

| Requirement | Status |
|---|---|
| Challenge photos only; never avatars | ✅ name regex + prefix; tests |
| Ownership verified | ✅ the uid comes from the object path; links are searched only in that uid's documents; a link to another user's photo stored elsewhere is left alone (emulator) |
| Correct owner's records updated; unrelated data preserved | ✅ only the `photoUrl` field, only when it names this object |
| No tokens or URLs printed | ✅ |
| Missing objects / malformed records | ✅ `gone`, `changed-during-rotation`; malformed `photoUrl` → not a reference |
| Concurrent object changes | ✅ generation/metageneration preconditions |
| Idempotent / resumable without re-rotating | ✅ state on the object; tests |
| Per-object outcomes without private data | ✅ |
| No unnecessary content rewrite | ✅ default `metadata` mode never downloads or rewrites bytes |
| Never invalidates the current link before the replacement is stored | ✅ **(fixed in 7D:** the 7C version rewrote first, then updated links). Invariant checked after every write in the unit tests; emulator shows the old URL and the new link both work between steps 2 and 3. |
| Partial failure / interruption | ✅ |
| No effect on other users | ✅ `--uid` scope; `ali` ≠ `alice/` |
| Recovery procedure | ✅ §6 |

### Does removing a token actually revoke old URLs in production?

**Not yet known; it must be established on a test account (§4), not assumed.**

| Evidence so far | Source |
|---|---|
| `rewrite` mode: old URL refused, new link serves identical bytes | Emulator |
| `metadata` mode: the **emulator merges** token lists, so the old token survives. The tool reports `verify-failed` (`old-token-still-present`) and never claims success. | Emulator |
| Cloud Storage documents a metadata patch as replacing the value of each given custom key, so production `metadata` mode is *expected* to leave exactly one token | Not verified here |

**Decision rule:**
1. Run the canary with the default `metadata`.
2. If the canary's verification passes **and** the old URL is refused, use `metadata` for the full run.
3. Otherwise run the canary again with `--remove-via rewrite`.
4. If neither revokes, stop.

## 2. Preconditions (check every time)

| # | Check | Expected |
|---|---|---|
| P1 | Live Storage rules (read-only export) | SHA-256 `630dc9a0…dcff17`, the interim rules. If they read `c5502223…`, **stop**: rotation is pointless while the exposure is open. |
| P2 | Tool built from this tree | `cd functions && npm ci && npm run build`; unit 203/203 |
| P3 | Credentials | Owner-provided ADC (§3.1); never a key file in the repo |
| P4 | `--project touchgrass-today`, bucket `touchgrass-today.firebasestorage.app` (default) | — |
| P5 | No other photo job running | The lease is free (the CLI exits 3 if not) |

## 3. Read-only dry-run ⚠️ (authorization **AC-2**)

### 3.1 Credentials (owner action)

Install the Google Cloud CLI, then run `gcloud auth application-default login` as a project owner (or as an account with the Storage Object Viewer and Cloud Datastore Viewer roles for the dry-run). Never share or commit the resulting file.

### 3.2 Command

```
mkdir -p ops-out/rotation        # git-ignored; output stays on this machine
cd functions
node lib/ops/opsCli.js photo-token-rotate --project touchgrass-today --real-project --out ../ops-out/rotation/dry-1.json
```

### 3.3 What it does

| | |
|---|---|
| Reads | The **list of every object under `completion_photos/`** (private object names, which include uids) with metadata (generation, `updated`, token presence). For each user with photos: their `completions` documents and `users/{uid}/memories` documents, to count links. |
| Does NOT | Change tokens, write Firestore, download or upload photo bytes, modify metadata, create backups, delete anything, or print URLs or tokens (unit test: no write or read operations in dry-run). |
| Writes | Only the local `--out` file (0600) under `ops-out/`, which is git-ignored. Delete it after the rotation is verified. |
| stdout | `would-rotate`, `too-recent`, `no-token`, `skipped-name`, `gone`, `referencesUpdated` (links that would change), `moreRemaining` |
| Bounded | Default 200 photos per run. Repeat with `--resume`, or set `--max` for larger batches. |

**Analyse before any write:**
- an unexpected `skipped-name` count, which suggests unknown upload shapes;
- `would-rotate` versus the number of users;
- photos with 0 links: orphans, or completions saved without a link.

## 4. Test-account canary ⚠️ (authorization **AC-3**)

1. **Owner:** create test account T on the live web app. Complete 1–2 challenges with photos. From the browser's network panel or the Journal image, save **one** photo URL **privately**; never paste it into chat or tickets.
2. Before: `curl -s -o /dev/null -w "%{http_code}\n" "<saved URL>"` → `200`.
3. Run:
   ```
   node lib/ops/opsCli.js photo-token-rotate --project touchgrass-today --real-project \
     --uid <T uid> --execute --confirm-project touchgrass-today --run-id canary1 \
     --out ../ops-out/rotation/canary1.json
   ```
4. Expected: `rotated` = T's photo count; no `verify-failed`.
5. After: the same `curl` gives **403 or 404**. That is the evidence the old link is revoked in production.
6. Reload the live app as T: the Journal and challenge details show the photos (new links).
7. Sign in as test account U: U can't open T's photo through the app. Owner check with the Rules Playground: `get completion_photos/<T>/<file>` as U → denied.
8. Nothing else changed: other users' objects keep their generation and metageneration (spot-check 2 objects of another **test** account in the console).

**If step 5 still returns 200 with `metadata`:** repeat with `--remove-via rewrite --run-id canary2` on T, then re-check. If that also leaves 200, **stop and report**.

## 5. Staged production rotation ⚠️ (authorization **AC-4**; a separate request with the dry-run numbers)

| Item | Plan |
|---|---|
| Scope | Every `completion_photos/` object from the dry-run (the count comes from AC-2) |
| Batches | Stage 1 `--max 25`, then `--max 200` per run, chained with `--resume <previous out>` |
| Throttling | Sequential; each photo is about 2 metadata patches plus 1–3 small Firestore transactions. No parallelism. |
| Checkpoints | After each batch: outcome counts; spot-check one **test** account's photo still shows; stop conditions |
| Retry | `--resume` (same run ID) finishes `references-failed`, `rotate-failed` and `changed-during-rotation` safely |
| Concurrent changes | Preconditions; `too-recent` photos are retried in a mop-up run 24 h later with a new run ID |
| Monitoring | Firebase console → Storage → request errors; user reports of missing photos |
| Post-verification | A new dry-run with a **new** run ID should show only `would-rotate` for photos uploaded since (new tokens were only ever issued to owners). Test account: old link refused, app shows photos. |
| Recovery | §6 |

**Stop conditions:**
- any `verify-failed`;
- `references-failed` that a resume doesn't clear;
- `rotate-failed` above 1%;
- user reports of missing photos after a reload;
- the lease held unexpectedly;
- live rules no longer equal the interim (P1).

**Command (per batch):**
```
node lib/ops/opsCli.js photo-token-rotate --project touchgrass-today --real-project --execute \
  --confirm-project touchgrass-today --max 200 [--remove-via <canary result>] \
  --resume ../ops-out/rotation/<prev>.json --out ../ops-out/rotation/<next>.json
```
The first batch uses `--run-id prod1` instead of `--resume`.

## 6. Failure recovery

| Situation | Effect on users | Recovery |
|---|---|---|
| Stopped after step 1 | None (both tokens valid) | `--resume` |
| `references-failed` | None (the old token is kept until the links are all updated) | `--resume` |
| `changed-during-rotation` at step 3 | None (links use the new token, which is valid) | `--resume`, or leave it (the old token survives, so it isn't revoked; review) |
| `verify-failed: old-token-still-present` | None; **not revoked** | Switch to `--remove-via rewrite` for those names with a new run (canary first) |
| App shows a broken photo | One user | `--resume`. If that fails, a project admin compares the object's token with the document in the console, without copying tokens anywhere. |

**Restoring an old token is deliberately not offered:** it would re-open every harvested link.

## 7. Not in this runbook

- **Profile-photo links:** by design they are visible to signed-in users and to anyone given the link. Rotating them needs a separate decision (C4) and must also update `users/{uid}.photoUrl` and `leaderboard_public/{uid}.photoUrl`.
- **Option B** (authenticated SDK reads with no persistent tokens): `PHASE_7C_PHOTO_TOKEN_REMEDIATION_PLAN.md` §2–3.
