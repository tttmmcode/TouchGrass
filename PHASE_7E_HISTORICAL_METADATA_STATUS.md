# Phase 7E — Historical Photo Metadata Status

**Status: NOT assessed, NOT remediated.** The tool is ready and tested locally. No production inventory has run: it needs authorization **and** owner-provided credentials, and it is ordered **after** the token rotation.

## 1. Tool re-review (Phase 7E)

Unchanged since 7D (`functions/src/ops/photoMetadataJob.ts`, `jpegMetadata.ts`, `opsCli.ts`). Re-checked against the 7E list:

| Requirement | Status | Evidence |
|---|---|---|
| Dry-run default | ✅ only `--execute` writes | unit + emulator |
| `--uid` filter | ✅ prefix `completion_photos/{uid}/`; the uid is validated | unit |
| Ownership | ✅ uid from the object path; the backup path is derived from the same uid | unit |
| No coordinates, tokens or URLs in output | ✅ GPS is a yes/no; never decoded | unit |
| EXIF, XMP, trailing data, embedded (MPF) images, motion-photo video, APPn between scans | ✅ stripped and validated (SOS→EOI image data identical) | unit (7) + emulator |
| Safe backups | ✅ new object, no token, `metadata_backup/completion_photos/{uid}/{runId}/`; denied to all clients (live smoke X6 confirms for the owner) | emulator + **live** |
| Concurrent changes | ✅ generation check + `ifGenerationMatch` | unit + emulator |
| Overlapping runs | ✅ shared lease with rotation | emulator |
| Objects deleted during execution | ✅ no recreate; the backup is removed again | unit + emulator |
| Resume | ✅ `--resume` | unit |
| Backups within retention and deletion | ✅ deleted by `deleteAccount` (twice); purge after 14 days (M-6) | emulator |
| Links not broken | ✅ the token is **kept** on rewrite; the saved URL keeps working | emulator |

## 2. Inventory plan (M-1; authorization + credentials)

| Question | Answer |
|---|---|
| Objects enumerated | Every object under `completion_photos/`; only `{uid}/{date or ts}.jpg` are read |
| Bytes read? | **Yes.** The first 128 KB per photo (header mode), or the whole photo with `--full-read` (needed to see appended data) |
| Fields inspected | JPEG segments: EXIF presence, GPS sub-IFD presence (yes/no), orientation, XMP presence, other APPn/COM; with `--full-read`, data after EOI and APPn between scans |
| Local report | `ops-out/metadata/inv-*.json` (0600, git-ignored): object names (with uids), generation, category. stdout: counts. |
| Protection and retention | The owner's machine only; delete after verified remediation, at the latest 30 days |
| Cost | Unknown until the dry-run count. Header ≈ 128 KB × N egress; full ≈ photo size × N. |

Order: test account first (`--uid <T> --full-read`), then everything (`--max 1000` + `--resume`). Commands are in `PHASE_7D_HISTORICAL_PHOTO_REMEDIATION_RUNBOOK.md` §3.

## 3. Test-account remediation plan (M-3)

As in `PHASE_7D_HISTORICAL_PHOTO_REMEDIATION_RUNBOOK.md` §5:
- camera, gallery and, if possible, motion-photo uploads with location on;
- inventory `--full-read`;
- remediate with `--run-id canaryM`;
- verify with `exiftool -gps:all -xmp:all -trailer:all` (nothing left), that the image is upright and valid, that the saved link still works, and that the backup exists and can't be opened with the link;
- resume test; deletion interaction after F-1.

Rewrites (M-3…M-5), backups and the backup purge (M-6) each need separate authorization.

**Order:** after the token rotation (AC-4). The evidence hasn't changed: rotation stops harvested links reaching **any** photo content, GPS included, so it is the larger risk reduction per operation.
