# Phase 7E — Challenge-Photo Token Rotation Status

**Status: legacy links NOT remediated.**
- The tool is ready and tested locally.
- The read-only dry-run is **prepared but not run**: authorization **and** owner-provided credentials are needed.
- The revocation experiment (Stage 4) is designed, not run.

Production evidence (smoke test T1, 05:26Z) confirms that an existing token URL opens a photo **without sign-in**.

## 1. Review against the 7E checklist

Tool: `functions/src/ops/photoTokenRotation.ts`, run through `opsCli.js photo-token-rotate`.

| Concern | Handling | Evidence |
|---|---|---|
| Missing objects | `gone`; deleted mid-run → `changed-during-rotation`, never recreated | unit + emulator |
| Missing or malformed owner records | Malformed `photoUrl` isn't treated as a link. Photos with no owner links are **counted** (`photosWithoutReferences`, 7E) and still rotated (nothing to update). | unit |
| Partial failure | Per-photo outcome plus `step` (add/references/remove/verify); the run continues | unit |
| Interrupted execution | State on the object (`added`/`done`, token tag); resume reuses the added token | unit + emulator |
| Repeated runs | Same run ID: no second token; finished photos only finish links | unit + emulator |
| Concurrent modifications | Generation/metageneration preconditions (atomic in real Cloud Storage; read-check first because the emulator ignores them) | unit + emulator |
| Duplicate references (completion + Journal entry) | Each document is updated and counted | unit |
| Firestore update failures | `references-failed`; the old token is **kept** while any link still uses it | unit (no-dead-link invariant) |
| Storage metadata failures | `rotate-failed` at `add`; nothing changed | unit |
| Stale saved URLs (a token the object no longer accepts) | Counted (`photosWithStaleReferences`, 7E) and repaired to the new token | unit |
| Retry and recovery | `--resume <out>`; runbook §6 | — |
| Per-object progress | `--out` entries (name, generations, outcome, step, link counts, error class) | — |
| Token and URL redaction | Never in stdout or `--out`; no token tags either | unit |
| Owner verification | uid from the object path; only that uid's documents are searched; a link to another user's photo inside someone's data is left alone | emulator |
| Profile photos excluded | Name regex + `completion_photos/` prefix | unit |
| No photo bytes rewritten by default | `--remove-via metadata` patches metadata only | unit (no read or rewrite operations) |

**7E additions** (unit tests 206 → 208 total functions, incl. the entry-point tests):
- **Dry-run aggregates:**
  - `photosWithoutReferences`;
  - `photosWithStaleReferences`;
  - `writes {metadataPatches, objectRewrites, linkUpdates}`: predicted in a dry-run, actual in execute.
- **`--stop-before-remove`:** stops once the new token is added and the links moved, with the old token still valid. That is the pause the revocation experiment needs. Re-running with the same `--run-id` and without the flag removes the old token. `awaiting-removal` is not a final outcome, so `--resume` continues it.

## 2. Read-only dry-run: prepared, not run

### Prerequisites (owner, in your own trusted terminal)

1. Install the Google Cloud CLI.
2. Run `gcloud auth application-default login` with an account that can read the project. I won't run auth flows, switch accounts or read credential files.
3. In `functions/`: `npm ci && npm run build`.

**Alternative:** run the same command yourself and share only the stdout summary (counts).

### Command

```
mkdir -p ops-out/rotation
cd functions
node lib/ops/opsCli.js photo-token-rotate --project touchgrass-today --real-project \
  --out ../ops-out/rotation/dry-1.json --max 1000
```

The bucket defaults to `touchgrass-today.firebasestorage.app`. Repeat with `--resume ../ops-out/rotation/dry-1.json --out …/dry-2.json` while `moreRemaining` is shown.

| | |
|---|---|
| **Reads** | Lists every object under `completion_photos/` (names include uids) with metadata; reads, in memory, whether tokens exist and their values (never output); for each uid with photos, its `completions` and `users/{uid}/memories` documents (only `photoUrl` is used) |
| **Does NOT** | Rotate tokens, write Firestore, patch metadata, download or upload photo bytes, create backups, delete anything (unit-tested: zero store operations) |
| **Writes** | Only `ops-out/rotation/dry-*.json` (mode 0600, git-ignored) on the owner's machine |
| **stdout** | `would-rotate`, `too-recent`, `no-token`, `skipped-name`, `gone`, `photosWithoutReferences`, `photosWithStaleReferences`, `writes`, `referencesUpdated` |
| **Cost** | Listing plus 1 metadata read per photo, plus 2 Firestore queries per user. Negligible at expected scale. |

### Report back (sanitized)

Totals only:
- eligible photos (`would-rotate`);
- excluded, by reason;
- photos without references;
- photos with stale links;
- predicted writes.

No uids or names.

## 3. Revocation experiment on a dedicated test object: designed, not run

**Authorization AC-3,** separate. Uses a new test account and a non-sensitive test photo.

1. The owner creates test account T on the live web app and completes one challenge with a test photo (a picture of a wall). The owner keeps the photo URL privately. Check: `curl -s -o /dev/null -w "%{http_code}" "$URL"` → **200**.
2. **Add + move links, keep the old token:**
   ```
   node lib/ops/opsCli.js photo-token-rotate --project touchgrass-today --real-project --uid <T> \
     --execute --confirm-project touchgrass-today --run-id revoke1 --stop-before-remove \
     --out ../ops-out/rotation/revoke1-a.json
   ```
   Expect `awaiting-removal: 1`.
3. Old URL → still **200**. The app (reload as T) shows the photo; its new link (from the network panel, private) → **200**.
4. **Remove the old token:** the same command **without** `--stop-before-remove`, with `--out …/revoke1-b.json`. Expect `rotated: 1`, `writes.metadataPatches: 1`.
5. **The decisive check:** old URL → **must not be 200**. New link → 200. The app still shows the photo.
6. Test account U: through the app or SDK, can't read T's photo (as in smoke checks S1a–S1c).
7. Unrelated objects unchanged: spot-check another test object's generation and metageneration in the console.
8. **If step 5 still returns 200:**
   - stop;
   - repeat on a **new** test photo with `--remove-via rewrite` (run `revoke2`);
   - if that also fails, the invalidation mechanism isn't understood: **no broad rotation**; investigate (e.g. Firebase download-token caching) with a narrowly scoped test only.

## 4. Staged rotation (after the experiment establishes the mechanism)

Each batch needs its own authorization, with the dry-run numbers. Details are in `PHASE_7D_TOKEN_ROTATION_RUNBOOK.md` §5–§6, unchanged.

| Item | Plan |
|---|---|
| Eligibility | Every `completion_photos/{uid}/{date or ts}.jpg` with a token, unchanged in the last 10 min |
| Batches | 25, then 200 per run, chained with `--resume`; sequential (no parallelism) |
| Ordering | Add token → move links → remove old (never a dead saved link) |
| Retry | `--resume` with the same run ID |
| Stop | any `verify-failed`; `references-failed` not cleared by resume; `rotate-failed` > 1%; user reports; live rules ≠ interim |
| Post-batch verification | Counts; a test account's photo still shows; a **sampled old test link** refused; a new dry-run (new run ID) shows only photos uploaded since |
| Evidence before claiming "legacy links remediated" | Step 5 of the experiment **and** a complete batch run with 0 `verify-failed` |
| Profile photos | Not rotated in this phase (decision C4) |
