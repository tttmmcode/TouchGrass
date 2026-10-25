# Phase 7D — Historical Photo Metadata Remediation Runbook

**Status: tooling re-reviewed and tested locally; nothing has run against production.** This runbook supersedes the procedure in `PHASE_7C_HISTORICAL_METADATA_RUNBOOK.md` and keeps its risk assessment, which still holds:
- released versions could store GPS through the camera path (`encodeJpg` re-wrote EXIF);
- the gallery path uploaded bytes without stripping.

**Order:** after the token rotation (AC-4). Rotation is the urgent revocation; this job then keeps the current token.

**Blocker:** no Application Default Credentials on this machine (token runbook §3.1).

## 1. Pipeline review: new uploads (verified locally)

| Path | Processing | Evidence |
|---|---|---|
| Challenge photo, camera (all platforms) | `compressJpeg`: decode, bake orientation, **clear EXIF**, resize, re-encode; then `stripImageMetadata` at upload | Flutter tests |
| Challenge photo, gallery | `image_picker` output → `stripImageMetadata` in `StorageService.uploadCompletionPhoto` | Flutter tests |
| `stripImageMetadata`, upright JPEG | Lossless: walks every segment, drops APP1 (EXIF/XMP), APP3–13, APP15 and COM, including **between scans**; **stops at EOI**, so appended MPF images and motion-photo video are dropped; scan data copied byte-identical | 29 tests (5 failed before the 7C fix) |
| `stripImageMetadata`, rotated JPEG / other formats (PNG, WebP, GIF, TIFF…) | Decode, bake orientation, re-encode JPEG without metadata | tests for orientations 1–8 and each format |
| Corrupt or unsupported input | `UnreadableImageException`; never uploaded unchecked | tests |
| Profile photo | Crop redraws pixels; `sanitizeProfilePhoto` at upload keeps only image PNG chunks (drops eXIf, tEXt, iTXt/XMP, zTXt, tIME, anything after IEND) or re-encodes to PNG | 3 tests |
| Web vs Android vs iOS | The same Dart code on all platforms. The `image` package decodes on all three; platform pickers differ only before stripping. | review |
| Declared type / extension | Never trusted: stripping decides by magic bytes; rules can only check the declared type (P90) | tests |
| Server tool (`jpegMetadata.ts`) | Same EOI and between-scans handling; validation compares SOS→EOI image data | TS unit + emulator |

**Not covered:** HEIC/HEIF bytes uploaded by an *older* client. The current client's decoder can't read HEIC; `image_picker` normally converts on iOS. The inventory reports such files as `not-jpeg` for manual review.

## 2. Tool review (`photoMetadataJob.ts`, `opsCli.js`)

| Requirement | Status |
|---|---|
| Dry-run default | ✅ only `--execute` writes |
| `--uid` filter enforced | ✅ prefix `completion_photos/{uid}/`; the uid is validated; `ali` ≠ `alice` |
| Ownership before changes | ✅ only `completion_photos/{uid}/{date or ts}.jpg`; the backup path is derived from the same uid |
| Backups don't reuse tokens | ✅ new Admin object, no `firebaseStorageDownloadTokens` (emulator: the original token is refused) |
| Backups in the account-owned namespace | ✅ `metadata_backup/completion_photos/{uid}/{runId}/…` |
| Backup access | ✅ denied to every client in **both** rulesets (P80–P84) |
| Backups covered by deletion and retention | ✅ `deleteAccount` deletes the prefix (twice, 7D); retention purge M-6 |
| Concurrent deletion leaves no orphan backup | ✅ a backup is deleted when the overwrite doesn't happen (unit + emulator) |
| Concurrent runs | ✅ shared lease with rotation |
| Resume | ✅ `--resume` skips finished photos |
| Change detection | ✅ generation check plus `ifGenerationMatch` |
| Trailing data | ✅ removed and validated; counted by `--full-read` |
| No URLs, tokens or coordinates in logs | ✅ |
| Failure isolation | ✅ per-photo outcome |

## 3. Production inventory plan ⚠️ (M-1)

| Question | Answer |
|---|---|
| Objects inspected | Every `completion_photos/{uid}/{name}.jpg` (other names are counted as `skipped-name`, not read) |
| Metadata examined | JPEG structure: EXIF (GPS sub-IFD present, orientation), XMP, other APPn/COM, and with `--full-read` data after EOI. **Coordinates are never decoded, stored or printed:** GPS is a yes/no. |
| Bytes or metadata? | **Bytes.** The first 128 KB of each photo by default; the whole photo with `--full-read`. |
| Local output | `--out` JSON (0600): object names (with uids), generation, category. Counts on stdout. |
| User-identifying data | uids inside object names; nothing else |
| Protection | `ops-out/` (git-ignored) on the owner's machine; never shared |
| Retention | Delete after remediation is verified, at the latest 30 days after the inventory |
| Runtime / cost | Unknown until the AC-2 dry-run gives the object count. Header mode ≈ 128 KB × N egress; full mode ≈ photo size × N (e.g. 1,000 × 0.5 MB ≈ 0.5 GB, a few cents). Sequential, about 0.3–1 s per photo (estimate). |

```
mkdir -p ops-out/metadata && cd functions
node lib/ops/opsCli.js photo-metadata-inventory --project touchgrass-today --real-project \
  --uid <test uid> --full-read --out ../ops-out/metadata/inv-test.json          # canary account first
node lib/ops/opsCli.js photo-metadata-inventory --project touchgrass-today --real-project \
  --max 1000 --out ../ops-out/metadata/inv-1.json                               # then all, resumable
```

## 4. Dry-run ⚠️ (M-2; reads bytes, writes nothing)

`photo-metadata-remediate --manifest ../ops-out/metadata/inv-1.json --out ../ops-out/metadata/rem-dry-1.json --max 200`

It validates every stripped copy in memory: a complete JPEG, no metadata or trailer, the same orientation, identical image data. It reports `would-rewrite`, `not-strippable` or `validation-failed`.

## 5. Test-account remediation ⚠️ (M-3)

1. The owner uploads, as test account T on the live web app, 2–3 photos taken **with location on**:
   - one from the camera;
   - one from the gallery;
   - if available, a phone "motion photo".
2. Inventory T with `--full-read`. Expect `gps` and/or `appended-data`.
3. Remediate T:
   ```
   photo-metadata-remediate --project touchgrass-today --real-project --manifest inv-test.json \
     --execute --confirm-project touchgrass-today --run-id canaryM --out rem-test.json
   ```
4. **Verify,** downloading as T, outside chat:
   - `exiftool -gps:all -xmp:all -trailer:all <file>` shows nothing;
   - the image opens and is upright;
   - the saved link still works (token kept);
   - the backup exists under `metadata_backup/completion_photos/<T>/canaryM/` and is **not** openable with T's link.
5. **Recovery and resume:**
   - Download one backup in the admin console and confirm it is byte-identical to the original T saved before the run (`sha256sum`).
   - Rerun step 3 with `--resume rem-test.json`. Every photo is skipped as finished.
   - Restoring a photo from a backup is possible, but replaces the object, and with it the download token. Treat it as a manual, case-by-case action.
6. **Deletion interaction:** delete T (after F-1). `metadata_backup/completion_photos/<T>/` is gone.

## 6. Resumable staged rollout ⚠️ (M-4, M-5)

- **Stages:** `--max 25`, then `--max 200` per run, chained with `--resume`.
- **Stop conditions:**
  - `verify-failed` > 0;
  - an unexplained `validation-failed`;
  - `write-failed` > 1%;
  - any user report;
  - the lease held unexpectedly.
- **Post-verification:** a fresh `--full-read` inventory on a sample shows `needsRemediation` 0 for the processed range.

## 7. Cleanup and retention ⚠️ (M-6)

- Delete `metadata_backup/completion_photos/*/<runId>/` **14 days** after a verified run. The backups contain the GPS the job removed.
- The bucket's soft-delete window keeps the pre-rewrite generation and the deleted backups recoverable by admins. **[owner: check and disclose]**
- Delete the local `ops-out/metadata/*.json` files after verification.

## 8. Authorization gates

| Gate | Operation | Writes production |
|---|---|---|
| M-1 | Inventory (test account, then all) | No (reads photo bytes) |
| M-2 | Remediation dry-run | No (reads bytes) |
| M-3 | Test-account remediation | Yes (test photos and backups) |
| M-4 | Stage 1 (25) | Yes |
| M-5 | Remaining stages | Yes |
| M-6 | Backup purge | Yes (deletes backups) |
