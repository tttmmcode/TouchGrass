# Phase 7C — Release Privacy Checklist

These are the gates that must pass before the photo-privacy incident can be called closed, and before **any** release that touches Storage, photos or privacy text. They exist so the problems found in Phases 7A–7C can't come back.

**Legend:**
- ✅ done locally and tested;
- ⏳ ready, needs authorization;
- ❌ open;
- 👤 owner action.

**Current state (2026-10-20):**
- **Production is unchanged and still exposed.** The live Storage rules SHA-256 is `c5502223…29579d`.
- No gate that needs production has passed.

## G1. Rules: containment and parity

| # | Gate | How to check | State |
|---|---|---|---|
| G1.1 | INTERIM (S-1) deployed **and** verified live | Read-only re-export: the live `storage.rules` SHA-256 equals `630dc9a02b1985b144a72ef847a9582adf2befc47a979d9ce55478b216dcff17` | ⏳ **Pending authorization**: the Phase 7B question is still unanswered |
| G1.2 | FINAL `storage.rules` doesn't allow avatar listing | `storage_release_parity.test.mjs` P50–P52, plus the static check | ✅ Fixed in 7C (`allow read` → `allow get`). Regression proof: the pre-fix file listed avatars. |
| G1.3 | FINAL and INTERIM differ only in documented, owner-only ways | The parity test's `DIFFERENCES` (P37, P43); any other difference fails | ✅ |
| G1.4 | No new or widened grant in either file | The static grant inventory must equal the reviewed table | ✅ (the test **fails** on any change; update the table only after review) |
| G1.5 | `firebase.json` deploys FINAL; the interim config deploys only INTERIM | Parity test, config check | ✅ |
| G1.6 | The full rules suite passes before **every** rules deploy | `cd firestore-tests && npm test`: 568/568 at 7C | ✅ (re-run before each deploy) |
| G1.7 | Live rules re-exported and diffed **right before** any rules deploy | `node tool/export_live_rules.mjs --project touchgrass-today` | Each time |
| G1.8 | Rules deploys use only the narrow commands in the manifest | `--only storage` / `--only firestore:rules,storage`; never a bare `firebase deploy` | Each time |

## G2. Download-token links

| # | Gate | State |
|---|---|---|
| G2.1 | **C2: every completion-photo token rotated and the owners' links updated**, after G1.1 | ⏳ Tool and tests ready (`photo-token-rotate`; emulator: old URL refused). Needs AC-2, AC-3 (test-account canary) and AC-4. **Must not run before G1.1.** |
| G2.2 | Canary verified on a test account: old URL refused, photo still shows after reload | ⏳ AC-3 |
| G2.3 | Mop-up run 24 h later for `too-recent` photos | ⏳ AC-5 |
| G2.4 | C3: the app reads private photos through the authenticated SDK by path; new completions store token-free URLs | ❌ Designed (token plan §2, Option B), not implemented. Web CORS to be verified on a test account. |
| G2.5 | C4: persisted tokens retired; a decision on profile-photo links | ❌ After C3 |
| G2.6 | Crash reports never contain token URLs | ✅ Redaction at every Crashlytics entry point (`secret_redaction.dart`, 5 tests) |
| G2.7 | Cloud Storage Data Access audit logs enabled, so future access can be established | 👤 Owner decision (small cost) |

## G3. Photo metadata

| # | Gate | State |
|---|---|---|
| G3.1 | New challenge photos are uploaded without EXIF/XMP/GPS, without APPn between scans, and **with nothing after the end of the image** | ✅ (`stripImageMetadata`; 29 tests; the 5 trailer tests failed before the 7C fix) |
| G3.2 | New profile photos are uploaded without metadata | ✅ `sanitizeProfilePhoto` at the upload boundary (3 tests) |
| G3.3 | Historical photos inventoried (read-only) | ⏳ M-1 (`PHASE_7C_HISTORICAL_METADATA_RUNBOOK.md` §3) |
| G3.4 | Historical photos remediated after the test-account canary; backups deleted after 14 days | ⏳ M-2 … M-6 |
| G3.5 | Bucket soft-delete / versioning windows known and disclosed | 👤 `gcloud storage buckets describe …` |

## G4. Account deletion and cleanup

| # | Gate | State |
|---|---|---|
| G4.1 | `deleteAccount` deployed and tested live with a test account (D-04 / F-1) | ⏳ Not deployed. **The live web app's deletion fails at Firestore before it touches Storage** (7C, from the live bundle and the live Firestore rules), so users of the live app can't delete their photos today. |
| G4.2 | Deletion removes photos, metadata backups and the avatar; never another user's | ✅ Functions emulator (uid look-alike untouched) |
| G4.3 | Photo-rewriting jobs can't recreate a deleted user's photo or leave a backup behind | ✅ 7C: generation-checked rewrites; backup removed if the overwrite doesn't happen (unit + emulator) |
| G4.4 | Photo-rewriting jobs can't overlap | ✅ Shared lease (emulator) |
| G4.5 | Orphan cleanup stays dry-run and unscheduled until approved | ✅ (not exported by `index.ts`) |

## G5. Web and mobile compatibility (coordinated release)

| # | Gate | State |
|---|---|---|
| G5.1 | FINAL rules + the new web build deployed in the **same window** (R-1 + S-2 + H-1); FINAL alone would block the live app's `{timestamp}.jpg` uploads (P37) | ⏳ (`PHASE_7A_DEPLOYMENT_MANIFEST.md`) |
| G5.2 | The web build compiles without `secrets.json`, and the bundle scan is clean | Re-run at release |
| G5.3 | Flutter suite, analyze and format | ✅ 479 tests, analyze 0, format 0 changed (7C) |
| G5.4 | Smoke test on a test account after the release: completion with photo, Journal, avatar change, leaderboard | ⏳ At release |

## G6. Disclosures (review-ready; nothing published)

| # | Gate | State |
|---|---|---|
| G6.1 | "Your challenge photos, which only you can see" is published only after G1.1 **and** G2.1 | ❌ Today it is **false** (report §9, G-1) |
| G6.2 | Profile-photo visibility worded accurately ("other TouchGrass users, and anyone they share the image link with") | ❌ Draft wording in report §9 |
| G6.3 | Location-in-photos statement matches G3 | ❌ Draft wording in report §9 |
| G6.4 | Deletion statements published only after G4.1 | ❌ (M-2 in the 7A draft) |
| G6.5 | Retention: soft delete, backups (14 days), analytics and crash data | 👤 Owner to fill in periods |
| G6.6 | Whether the past exposure must be notified | 👤 Legal decision |

## Release order (so nothing reintroduces the exposure)

1. **S-1** (G1.1). Verify it live by read-only re-export.
2. **C2** token rotation (G2.1–G2.3): canary first, then the full run.
3. Historical metadata (G3.3–G3.4): inventory, dry-run, canary, staged.
4. **F-1** `deleteAccount` (G4.1).
5. **Coordinated window:** R-1 + S-2 (FINAL rules, parity-gated by G1.2–G1.6) + H-1 (web build).
6. **C3**, then **C4** (G2.4, G2.5). Remove token-URL rendering for private photos.
7. Publish the corrected disclosures (G6) only for statements whose gates have passed.

**Closing condition:** the incident is closed only when all of these hold:
- G1.1 is verified live;
- G2.1 is verified on a canary and complete;
- G3.4 is complete;
- G6.1–G6.3 are published accurately.

Passing the rules tests is **not** sufficient.
