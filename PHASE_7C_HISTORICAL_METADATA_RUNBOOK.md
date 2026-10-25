# Phase 7C — Historical Photo Metadata Runbook

**Status: prepared; nothing has run against production.** The inventory reads private photos, and the remediation rewrites them. Each step marked ⚠️ needs its own explicit authorization.

**Tool:** `functions/src/ops/` (`jpegMetadata.ts`, `photoMetadataJob.ts`, `opsCli.ts`). Build it with `cd functions && npm ci && npm run build`, then run `node lib/ops/opsCli.js <command> …`. It uses Application Default Credentials; no key files are read or written.

## 1. Risk assessment

### How historical photos were produced

Read from the committed (released) code at HEAD `67c5a38`, and from the live bundle's upload calls (Phase 7B).

| Source | Released behaviour | Can the stored photo hold location? |
|---|---|---|
| **Camera** capture (web on phones; mobile builds were never released) | `compressJpeg` decoded, rotated and re-encoded with the `image` package. Its `encodeJpg` **writes the decoded EXIF back out** (Phase 4 finding N-2), so camera GPS EXIF survived. | **Yes: EXIF GPS likely** whenever the phone's camera recorded location |
| **Gallery** pick | `image_picker` with `maxWidth`/`imageQuality`, then `putData` of those bytes **without stripping**. On web, resizing goes through a canvas, which drops metadata; when no re-render happens, the original bytes go up as picked. | **Possible**: EXIF/XMP GPS, and in the rare case of unmodified phone JPEGs, an **appended MPF image or motion-photo video** after the image |
| New app (not released) | `stripImageMetadata` before upload. **Phase 7C fix:** it now also drops data after EOI and APPn between scans. | No (unit-tested) |

**Exposure context:**
- Under the live Storage rules, any signed-in user could read these files. Anyone holding a harvested token URL still can (token plan).
- So the GPS in old photos is **not only a data-minimisation issue**. The B11 note "only the owner can read these files" was written for the intended rules and is not true of production (KNOWN_BUGS B11 update).

**How many photos are affected is unknown** until §3 runs.

## 2. Tool review (Phase 6 + 7A + 7C)

| Required property | State | Evidence |
|---|---|---|
| Dry-run by default | ✅ Only `--execute` writes; any other mode is a dry-run | unit + emulator |
| Inventory minimises private data | ✅ stdout gets counts only; names go only to the `--out` file (mode 0600); no coordinates, bytes or URLs | unit (`summary`, report regex) |
| Never prints signed URLs or tokens | ✅ | unit |
| Ownership established before changes | ✅ Only `completion_photos/{uid}/{date or timestamp}.jpg`; the uid comes from the path; `--uid` scopes a run to one user | unit |
| Backups stored safely | ✅ `metadata_backup/completion_photos/{uid}/{runId}/{file}`: denied to all clients by both rulesets (P80–P84); deleted by `deleteAccount` | rules + functions emulator |
| Backups don't reuse the token | ✅ A new Admin SDK object without `firebaseStorageDownloadTokens` (7A); the original's token is refused on the backup | emulator |
| Backups match account-deletion expectations | ✅ Per-user prefix. **7C fix:** a backup whose overwrite didn't happen (photo deleted or replaced meanwhile, or a write error) is **deleted again**, so no copy outlives its photo. If that delete fails, it is reported. | unit (4) + emulator |
| Resume is safe | ✅ `--resume <out>` skips finished photos; a failed photo is retried at the same generation | unit |
| Interrupted runs recoverable | ✅ The manifest lists each photo's outcome and backup path | unit |
| Re-checked before modification | ✅ Generation compared before the write; `ifGenerationMatch` on the write (atomic in real Cloud Storage only; the emulator ignores it); a full re-inspection of the bytes | unit + emulator |
| Concurrent executions controlled | ✅ **7C:** remediation and token rotation share a Firestore lease (`_ops/photoRewrite_lease`, 1 h TTL) | emulator |
| Idempotent retries | ✅ Clean photos are skipped; stripping is idempotent | unit |
| One failure doesn't affect others | ✅ Per-photo try/catch; outcomes recorded per photo | unit |
| Distinct outcomes | ✅ `would-rewrite`, `rewritten`, `already-clean`, `changed-since-inventory`, `gone`, `not-strippable`, `validation-failed`, `write-failed`, `verify-failed` (+ `detail`) | unit |
| **Appended data (7C)** | ✅ Stripping now ends at EOI, and APPn between scans are dropped. `validateStripped` compares SOS→EOI data without APPn. A full-read inventory reports `appended-data`. | unit (7) + emulator |
| Header-only inventory limitation | ⚠️ A header read can't see data appended after the image. Use `--full-read` (downloads every photo) if appended data must be counted. Every photo that **is** remediated is read in full, so appended data is removed there anyway. | unit |

## 3. Read-only inventory ⚠️ (authorization M-1)

**What it reads:**
- the list of objects under `completion_photos/` (names, generations, metadata, including whether a token exists; tokens are never output);
- for each `{uid}/{date|timestamp}.jpg`, the first 128 KB (default), or the **whole file** with `--full-read`.

**What it writes:** nothing in production. One local JSON file (`--out`, mode 0600) holds object names, generations and categories. **Treat it as personal data**: it contains uids. Store it encrypted and delete it after the remediation's retention window.

```
# 3a. Canary: the owner's TEST account only
node lib/ops/opsCli.js photo-metadata-inventory --project touchgrass-today --real-project \
  --uid <test uid> --full-read --out inv-test.json

# 3b. Everything, bounded and resumable
node lib/ops/opsCli.js photo-metadata-inventory --project touchgrass-today --real-project \
  --max 1000 --out inv-1.json
node lib/ops/opsCli.js photo-metadata-inventory --project touchgrass-today --real-project \
  --resume inv-1.json --out inv-2.json        # until no "moreRemaining"
```

**Output (stdout):**
- counts per category: `clean`, `gps`, `other-metadata`, `appended-data` (full read only), `not-jpeg`, `malformed`, `header-beyond-read`, `unreadable`, `skipped-name`;
- `needsRemediation`.

**Decision point:** if `gps + other-metadata + appended-data` is 0 and `header-beyond-read` is 0, stop. Nothing needs remediation.

**Optional:** run `--full-read` once if appended data should be **counted** (more egress). Remediation removes appended data from every photo it rewrites either way.

## 4. Dry-run ⚠️ (authorization M-2; writes nothing)

```
node lib/ops/opsCli.js photo-metadata-remediate --project touchgrass-today --real-project \
  --manifest inv-1.json --out rem-dry-1.json --max 200
```

For each listed photo, the dry-run downloads it, builds the stripped copy and **validates** it in memory:
- a complete JPEG;
- no GPS, XMP, other APPn or trailer;
- the same orientation;
- identical image data.

It reports `would-rewrite`, `not-strippable` or `validation-failed`. **Stop condition:** any `validation-failed` you can't explain.

## 5. Sample validation ⚠️ (authorization M-3; TEST account only)

Never open real users' photos to check them.

1. **Create the sample.** On the live web app, signed in as the test account, upload two photos from a phone with location tagging on: one from the camera, one from the gallery. Ideally include a phone that writes motion photos or MPF.
2. **Inventory the test account:** `photo-metadata-inventory --uid <test uid> --full-read --out inv-test.json`. Expect `gps` and/or `appended-data`.
3. **Remediate the test account only:**
   ```
   node lib/ops/opsCli.js photo-metadata-remediate --project touchgrass-today --real-project \
     --manifest inv-test.json --execute --confirm-project touchgrass-today --run-id canary1 --out rem-test.json
   ```
   The manifest contains only the test account's photos.
4. **Verify:**
   - The Journal shows both photos (token unchanged).
   - Download them as the test account, then check with `exiftool -G -a -gps:all <file>`: there should be no GPS and no trailer (`exiftool -trailer:all`).
   - Compare orientation and appearance against the original.
   - The backup exists at `metadata_backup/completion_photos/<test uid>/canary1/`.

## 6. Backup design

- **Location:** `metadata_backup/completion_photos/{uid}/{runId}/{file}`, the per-user prefix that `deleteAccount` removes.
- **Format:** a **new** object holding the original bytes, with the original's content type and **no download token**. No client can read it (rules P80–P84).
- **Removal:** written only when `--no-backup` is not given; deleted again automatically if the overwrite doesn't happen (7C).
- **Retention:** keep backups for **14 days** after a validated run, then delete them (authorization M-6):
  ```
  gcloud storage rm --recursive "gs://touchgrass-today.firebasestorage.app/metadata_backup/completion_photos/*/<runId>/"
  ```
  The backups contain the GPS the job removed. Keeping them longer defeats the purpose.
- **Soft delete:** the bucket's soft-delete window (owner check) also keeps the **pre-rewrite generation** of each photo, and later the deleted backups, recoverable by project admins for that window. Disclose or shorten it if needed.

## 7. Resumable migration ⚠️ (authorization M-4, M-5)

Run in stages, bounded by `--max`. Each stage uses the inventory manifest and resumes from the previous stage's `--out`. Every command below is `node lib/ops/opsCli.js … --project touchgrass-today --real-project` plus the options shown.

| Stage | Command | Go criteria to continue |
|---|---|---|
| 1 | `photo-metadata-remediate --manifest inv-1.json --execute --confirm-project touchgrass-today --run-id hist1 --max 25 --out rem-1.json` | `rewritten` = processed − (`already-clean` + `gone` + `changed-since-inventory`); **0** `verify-failed`, **0** `validation-failed`; no user reports |
| 2 | the same, `--max 200 --resume rem-1.json --out rem-2.json` | the same |
| 3 | repeat with `--resume` until the inventory's `needsRemediation` photos are all final | — |

- **Interrupted runs:** rerun with `--resume <last out>`. Finished photos are skipped; a photo whose write failed is retried, because its generation is unchanged.
- **The lease:** a second run (or a token rotation) waits; the CLI exits with code 3. A crashed holder's lease expires after 1 h.

## 8. Post-migration verification

1. Run a fresh inventory (§3b with `--full-read` on a sample `--max 200`): `needsRemediation` should be 0 for the processed range.
2. Check the outcome counts in the `rem-*.json` files: every remediated photo is `rewritten` or explained.
3. Test account: the Journal and challenge details show the photos; the downloaded files contain no GPS.
4. Watch the Firebase console for 48 h: Storage errors, user reports.

## 9. Stop conditions

Stop and report on any of these:
- `verify-failed` > 0;
- an unexplained `validation-failed`;
- `write-failed` above 1%;
- any user report of a missing or distorted photo;
- the lease held unexpectedly;
- an unexpected spike in `skipped-name` or `not-jpeg` (a sign of unknown upload shapes).

## 10. Cost and runtime (estimates; the count is unknown until §3)

- **Inventory (header):** 128 KB per photo. **Full read** and **remediation:** the whole photo is downloaded; remediation also re-uploads it.
- **From a laptop:** internet egress of about photo size × count. For example, 1,000 photos × 0.5 MB ≈ 0.5 GB per full pass, a few cents at list price.
- **Operations:** a few class-A/B operations per photo.
- **Runtime:** roughly 0.3–1 s per photo sequentially (not measured on production).

## 11. Authorization checkpoints (summary)

| ID | Operation | Writes to production |
|---|---|---|
| M-1 | Inventory (test account, then all) | No |
| M-2 | Remediation dry-run | No |
| M-3 | Remediation on the **test account** | Yes (test photos and their backups) |
| M-4 | Stage 1 (`--max 25`) | Yes |
| M-5 | Remaining stages | Yes |
| M-6 | Delete the run's backups after 14 days | Yes (deletes backups) |

**Ordering with the token plan:** run token rotation C2 **before** this job. Rotation is urgent (it revokes harvested links); this job then keeps the current, rotated token. They can't overlap (shared lease).
