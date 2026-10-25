# Phase 7F — Historical photo metadata: audit and remediation status

**Status: Historical metadata NOT assessed and NOT remediated.**
- No production inventory was run in 7F.
- The operator tools need ADC, which this machine doesn't have.
- **That new uploads are clean does not resolve the historical risk.**

The step-by-step procedure (M-1…M-6) is unchanged and lives in `PHASE_7D_HISTORICAL_PHOTO_REMEDIATION_RUNBOOK.md` §3–§8. This file records what 7F verified and changed.

## 1. New uploads: every path audited (local code, Phase 7F)

There is exactly **one upload boundary**, `lib/services/storage_service.dart`. It is the only code in `lib/` that calls `putData`/`putFile`/`putString`/`putBlob` (grep, 2026-10-21). Every caller funnels through its two methods:

| Method | Callers (camera, gallery, web, retry, Journal) | Sanitizer, run before upload |
|---|---|---|
| `uploadCompletionPhoto` | The challenge camera flow (camera or gallery pick, mobile and web) and its retry. The Journal entry reuses the completion's URL; it never uploads its own copy. | `stripImageMetadata` (`lib/core/utils/image_metadata.dart`) |
| `uploadProfilePhoto` | Settings → profile photo (camera or gallery), after the crop screen | `sanitizeProfilePhoto` |

What the sanitizers do:
- **Format detection** uses the bytes (the JPEG SOI marker), never the file name, extension or declared MIME type.
- **JPEG** (lossless path):
  - drops APP1 (EXIF and XMP; both can carry GPS), APP3–APP13, APP15 and COM, **including segments between progressive scans**;
  - stops at the image's EOI, so appended MPF images (with their own EXIF/GPS), motion-photo video and vendor trailers are discarded;
  - embedded EXIF thumbnails go with APP1;
  - APP0/JFIF, APP2/ICC and APP14/Adobe are kept (no location in them).
- **JPEG with a non-normal EXIF orientation:** the rotation is baked into the pixels and the image re-encoded without metadata, so it doesn't display sideways.
- **PNG, WebP or anything else decodable:** re-encoded (challenge → JPEG; avatar → PNG keeping only image-drawing chunks; `eXIf`, `tEXt`/`zTXt`/`iTXt` (XMP), `tIME` and anything after `IEND` are dropped).
- **Unreadable or malformed input** throws `UnreadableImageException`: the upload is refused with a clear message rather than storing bytes whose metadata couldn't be checked.
- **Offline queue:** none. The Storage SDK doesn't queue uploads; a retry calls the same method again.
- **Server-side upload or import:** none in `functions/` (only the operator tools, which rewrite *stripped* versions of existing photos).

Evidence: the Flutter suite (`test/core/image_metadata_test.dart`, `image_metadata_formats_test.dart`, `image_metadata_trailer_test.dart`, `test/providers/camera_flow_test.dart`) in the 7F run (`PHASE_7F_FINAL_REPORT.md` §13).

## 2. Historical profile photos (new in 7F)

The live code (HEAD `67c5a38`) renders the cropped avatar with `ui.Image.toByteData(format: png)` (`_CropScreen`), a re-encode from pixels. **A PNG made that way contains no EXIF, XMP or GPS.** Avatars uploaded by builds older than HEAD weren't checked: risk low but unverified. The existing `profile-photo-inventory` command counts URL kinds only. A byte-level avatar scan would need a small tool addition and its own authorization (it reads every avatar). Owner decision, listed in the release readiness file.

## 3. The historical tool (re-reviewed)

| Requirement | State |
|---|---|
| Dry-run by default | ✅ Only `--execute` writes. **7F:** a remediation dry-run no longer takes the lease either (`leaseFor`), so it writes nothing at all. |
| Project and bucket restricted | ✅ `--real-project` is required. **7F:** a foreign `--bucket` and the look-alike project are refused. |
| Scoped to one test user | ✅ `--uid` (inventory) |
| Ownership | ✅ Only `completion_photos/{uid}/{date or timestamp}.jpg`; backups go to the **same uid's** `metadata_backup/completion_photos/{uid}/{runId}/` |
| Nothing sensitive logged | ✅ GPS is a yes/no category; coordinates are never decoded; stdout has counts; names only in the 0600 `--out` file |
| Malformed and appended content | ✅ categories `malformed`, `not-jpeg`, `header-beyond-read`, `appended-data` (the last needs `--full-read`) |
| Concurrent modification | ✅ every overwrite is conditional on the inspected generation (`changed-since-inventory`) |
| Interrupt and resume | ✅ `--resume` (cursor for the inventory; finished names for remediation) |
| Deletion races | ✅ the backup is removed again if the photo vanished or changed before the overwrite (tests) |
| Controlled backups | ✅ written as new objects **without** a download token; rules deny all client access; per-user path, so `deleteAccount` removes them (twice) |
| Retention | Backups purged 14 days after a verified run (M-6); local `--out` files deleted after verification |
| Synthetic tests | ✅ unit and emulator suites build JPEGs with EXIF GPS, XMP, comments, ICC, APP5, MPF trailers, motion-photo trailers, APPn between scans, missing EOI |

## 4. Production inventory (M-1): exact scope for approval

| Question | Answer |
|---|---|
| Reads | Object names and generations under `completion_photos/`; **photo bytes** (the whole file with `--full-read`, needed to see appended images) streamed into the tool's memory |
| Inspected | JPEG structure only: EXIF present, GPS sub-IFD present (yes/no), orientation, XMP, other APPn/COM, data after EOI |
| Never produced | Coordinates, image content, URLs, tokens |
| Output | stdout: category counts. `ops-out/metadata/*.json` (0600, git-ignored): object names (contain uids), generation, category |
| Writes | **None** in production |
| Cost | Egress ≈ total photo size (e.g. 1,000 × 0.5 MB ≈ 0.5 GB ≈ a few cents); exact once AC-2 gives the count |

**Commands** (from `functions/`):
- canary on a test account: `node lib/ops/opsCli.js photo-metadata-inventory --project touchgrass-today --real-project --uid <test uid> --full-read --out ../ops-out/metadata/inv-test.json`
- all photos: `node lib/ops/opsCli.js photo-metadata-inventory --project touchgrass-today --real-project --full-read --max 1000 --out ../ops-out/metadata/inv-1.json`, repeated with `--resume` while the summary says `moreRemaining`.

**Ordering:** the inventory is read-only and independent of the rotation. It can run as soon as ADC exists and it is authorized. Remediation (M-3…M-5) comes **after** the token rotation stages. An in-place rewrite keeps the existing token, so rotating first means remediation never re-saves a leaked token. M-6 purges the backups.

## 5. What must be true before "Historical metadata remediated"

1. A full-read inventory covering every object, with no `moreRemaining`.
2. M-3 on a test account verified with `exiftool` outside chat.
3. M-4/M-5 with 0 `verify-failed`, and a re-inventory showing `needsRemediation: 0`.
4. M-6 backups purged after 14 days.

None of these has happened.
