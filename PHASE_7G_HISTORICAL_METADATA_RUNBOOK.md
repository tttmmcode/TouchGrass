# Phase 7G — Historical photo metadata runbook (AC-4, AC-5)

**Status: Historical metadata NOT assessed and NOT remediated.** New uploads are clean (§1), which does not resolve photos already stored. Nothing ran in production (no credentials).

Detailed procedure background: `PHASE_7D_HISTORICAL_PHOTO_REMEDIATION_RUNBOOK.md`. This file is the current command set; since 7G, remediation writes need `--mode production-mutation`.

## 1. Every upload path strips metadata first (re-verified 2026-10-21)

- **One upload boundary:** `lib/services/storage_service.dart` is the only `putData`/`putFile`/`putString`/`putBlob` call in `lib/`.
- **Challenge photos** go through `stripImageMetadata`: camera, gallery, web and retry. Journal entries reuse the completion's URL.
- **Profile photos** go through `sanitizeProfilePhoto`.
- **No offline upload queue; no server-side upload or import path.**
- Format detection uses bytes, not names or MIME types. Undecodable input (including HEIC on this decoder) is refused with a message, never uploaded unchecked.

| Case | Behaviour | Test |
|---|---|---|
| EXIF (camera make, GPS) | Removed losslessly | `image_metadata_test.dart` |
| XMP (can hold GPS) | Removed; ICC colour profile kept | same |
| Comments, APP3–13/15 | Removed | same |
| **EXIF thumbnail** (a second picture in the EXIF block) | Removed with APP1; the main image is intact | **7G:** `image_metadata_phase7g_test.dart` |
| Orientation 1–8 | Rotation applied to pixels, then re-encoded without metadata; displays upright | `image_metadata_formats_test.dart` |
| Data after EOI (MPF second image with GPS, motion-photo video, vendor trailer) | Not uploaded | `image_metadata_trailer_test.dart` |
| APPn between progressive scans | Dropped | same |
| Truncated JPEG / no EOI / random bytes / empty | Re-encoded or refused, never uploaded unchecked | same + formats test |
| PNG, GIF, TIFF (challenge) | Re-encoded as metadata-free JPEG | formats test |
| **Avatar PNG with data after IEND** | Trailer not uploaded | **7G** |
| **Rotated JPEG as avatar** | Upright PNG, no EXIF | **7G** |
| **HEIC** | Refused (not decodable here), never uploaded unchecked | **7G** |
| **Large photo (1600×1200, rotated)** | Complete, upright, no GPS | **7G** |
| Size limits | Client check after stripping; **enforced server-side** by rules (<10 MB / <5 MB, boundary-tested) | Rules P21–P23, P57–P59 |

**Historical avatars:** the live code (HEAD) redraws the cropped avatar from pixels to PNG, so there is no metadata. Avatars from builds older than HEAD were not checked: low risk, unverified.

## 2. AC-4 — Read-only historical inventory (needs approval)

| Question | Answer |
|---|---|
| Project and bucket | `touchgrass-today` / `touchgrass-today.firebasestorage.app` (enforced by the allowlist) |
| Eligible objects | `completion_photos/{uid}/{yyyy-MM-dd or 10–16-digit}.jpg`; other names are counted as `skipped-name` and not read. Avatars: not included (optional separate scan, owner decision). |
| Bytes | **Downloaded** into the tool's memory, never written to disk: the first 128 KB by default, the **whole file with `--full-read`** (needed to see appended images and video) |
| Examined | JPEG structure only: EXIF present, GPS sub-IFD present (yes/no), orientation, XMP, other APPn/COM, data after EOI |
| Output | Category counts (stdout). File (new, 0600, `ops-out/metadata/`): object name (contains uid), generation, category. **No coordinates, no image content, no URLs or tokens.** |
| Writes | **None** (read-only mode; proven by the 7G tests) |
| Batch size | `--max` per run (1000 suggested); continue with `--resume` |
| Failure | Per-object read errors → `unreadable`, and the run continues. A listing error stops the run, and the cursor stays in the last file. |
| Cost | Egress ≈ total bytes read. For 1,000 photos × ~0.5 MB ≈ 0.5 GB, a few cents. |
| Retention | Delete `ops-out/metadata/*.json` after remediation is verified, at the latest 30 days after the inventory |

**Commands** (from `functions/`):

```
node lib/ops/opsCli.js photo-metadata-inventory --project touchgrass-today --real-project --uid <testUid> --full-read --out ../ops-out/metadata/inv-test.json
node lib/ops/opsCli.js photo-metadata-inventory --project touchgrass-today --real-project --full-read --max 1000 --out ../ops-out/metadata/inv-1.json
node lib/ops/opsCli.js photo-metadata-inventory --project touchgrass-today --real-project --full-read --resume ../ops-out/metadata/inv-1.json --out ../ops-out/metadata/inv-2.json   # while "moreRemaining"
```

**Share back:** `inspected`, `counts` (clean, gps, other-metadata, appended-data, malformed, not-jpeg, header-beyond-read, unreadable, skipped-name), `needsRemediation`, `limitReached`.

## 3. AC-5 — Remediation (each step separately approved)

**Preconditions:**
- AC-4 is complete (no `moreRemaining`);
- the AC-3 token rotation is complete, because an in-place rewrite keeps the existing token and rotating first means remediation never re-saves a leaked token;
- counts have been presented.

| Step | Command (from `functions/`) | Writes |
|---|---|---|
| M-2 dry-run (read-only) | `node lib/ops/opsCli.js photo-metadata-remediate --project touchgrass-today --real-project --manifest ../ops-out/metadata/inv-1.json --out ../ops-out/metadata/rem-dry-1.json --max 200` | None (validates stripped copies in memory) |
| M-3 test account | `… photo-metadata-remediate … --manifest ../ops-out/metadata/inv-test.json --execute --mode production-mutation --confirm-project touchgrass-today --run-id m3test --out ../ops-out/metadata/rem-test.json` | Rewrites the test account's photos in place; backups at `metadata_backup/completion_photos/<uid>/m3test/` |
| M-4/M-5 stages | The same with `--manifest ../ops-out/metadata/inv-1.json --max 25`, then `--max 200` chained with `--resume <previous out>` | Rewrites plus backups |
| M-6 purge | Delete `metadata_backup/completion_photos/*/<runId>/` **14 days** after a verified run (console or a reviewed command) | Deletes backups |

**Per-photo safety:**
- download the exact inspected generation;
- strip losslessly and **validate**: a complete JPEG, no GPS/XMP/trailer, the same orientation, identical image data;
- back up as a new object with **no** download token (rules deny client access; per-uid path, so account deletion removes it);
- overwrite **only if** the generation is unchanged, keeping the content type, cache control and download token, so saved links keep working;
- re-read and verify.

If the overwrite doesn't happen (changed, deleted, failed), the backup is deleted again.

**Verification:**
- `exiftool -gps:all -xmp:all -trailer:all` on downloaded test copies (outside chat) shows nothing;
- the photos still display upright in the app;
- a re-inventory of processed ranges shows `needsRemediation: 0`.

**Stop if:**
- `verify-failed` > 0;
- any unexplained `validation-failed`;
- `write-failed` > 1%;
- any user report.

**Recovery:**
- backups for 14 days;
- restoring replaces the object and its token, so it's a manual, case-by-case action;
- the bucket's soft-delete window also keeps pre-rewrite generations. Owner: confirm its setting and disclose it.

**"Historical metadata remediated"** may only be claimed after a complete inventory, M-3 verified with `exiftool`, M-4/M-5 with 0 `verify-failed` and a clean re-inventory, and M-6 done.
