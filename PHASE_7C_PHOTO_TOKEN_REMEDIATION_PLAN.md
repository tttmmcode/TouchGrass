# Phase 7C — Photo Download-Token Remediation Plan

**Status: plan and tooling ready; nothing has run against production.** Every production step below needs its own explicit authorization (§6).

## Why this is needed

A Firebase Storage download URL has this form:

```
https://firebasestorage.googleapis.com/v0/b/<bucket>/o/<path>?alt=media&token=<uuid>
```

It opens the object for **anyone who holds it, signed in or not**. Storage rules are **not evaluated** for token URLs. This was emulator-proven in Phase 7C (P91): after the rules are fixed, an owner's token URL still opens the photo without sign-in, and a wrong token is refused.

The live Storage rules (still deployed as of 03:33Z on 2026-10-20) let **any signed-in user**:
- list the `completion_photos` root, which gives every user's ID;
- list each user's folder;
- call `getDownloadURL` on each photo, which gives the permanent token URL.

Anyone who did that **still holds working links**. Deploying S-1 (interim rules) stops new harvesting, but **does not revoke a single existing link**. Whether anyone harvested links is unknown: Cloud Storage data-access audit logs are off by default (owner check, report §8).

## 1. Every token-URL pathway (verified in the repository)

### 1.1 Where URLs are created, stored and used

| # | Pathway | Created by | Stored in | Read by | Who can read the stored URL |
|---|---|---|---|---|---|
| U1 | Challenge (completion) photo | `StorageService.uploadCompletionPhoto` → `ref.getDownloadURL()` (`lib/services/storage_service.dart`). The live web app does the same with `completion_photos/{uid}/{Date.now()}.jpg`. | `completions/{uid}_{date}.photoUrl`. Create-only: the rules require `…/o/completion_photos%2F{uid}%2F{date}.jpg(?…)`. | `challenge_detail_screen.dart` (CachedNetworkImage); `camera_screen.dart` (Image.network, success screen) | **Owner only.** Live and final Firestore rules both make `completions` owner-readable. |
| U2 | Journal entry (copy of U1) | `memory_repository.dart` copies `completion.photoUrl` | `users/{uid}/memories/{id}.photoUrl` | `map_screen.dart`: Journal list and marker sheet (CachedNetworkImage), map pin (`PhotoMarkerGenerator.loadImage` → NetworkImage) | **Owner only** |
| U3 | Profile photo | `StorageService.uploadProfilePhoto` → `getDownloadURL()` | `users/{uid}.photoUrl` **and** the public mirror `leaderboard_public/{uid}.photoUrl` | Leaderboard (only URLs passing `isTrustedAvatarUrl`), profile, home, settings | **Every signed-in user**, by design (leaderboard) |
| U4 | Google profile photo | Google sign-in (`picture` claim) | Same fields as U3 | Same as U3 | Every signed-in user. Not a TouchGrass Storage token. |
| U5 | AI verification (disabled, not deployed) | `functions/src/index.ts`, `challenge_verification_service.dart` | A Storage **path**, not a URL | — | n/a |
| U6 | Operator tools | `functions/src/ops/*` | Object **names** in the operator's private `--out` file only; never URLs or tokens (unit-tested) | — | Operator |
| U7 | Crash reports | Flutter image-load errors name the full URL | Crashlytics (mobile only). **Phase 7C:** tokens are redacted before recording (`secret_redaction.dart`, 5 tests). | — | Developer |

- **No analytics event carries a URL.** `logPhotoUploaded` sends only the challenge ID.
- **Web and mobile use the same Dart code** (upload, strip, render), so both persist and render token URLs.
- **The live web app is an older build** with the same token pattern. Its photo names are `{Date.now()}.jpg`.

### 1.2 What a holder of each URL type can do

| URL type | Opens without sign-in? | Revoked by a rules change? | Revoked by |
|---|---|---|---|
| Completion photo token URL (U1/U2) | **Yes** | **No** | Rotating the token (the object is rewritten with a new single token), or deleting the object |
| Profile photo token URL (U3) | **Yes.** Any signed-in user can read it from the leaderboard mirror and pass it on. | No | Rotation or deletion. Whether a client re-upload of the avatar replaces or keeps the existing token is **not verified**, so don't rely on it. |

**Privacy implication for profile photos:** "visible to signed-in users" in practice means **visible to anyone a signed-in user shares the link with**. Stopping the directory listing (Phase 7B/7C) prevents enumeration, but does **not** make an individual avatar private. Disclosures should say so (report §9, G-3).

### 1.3 Can existing photos render without a token URL?

**Not in the current app.** Every private-photo widget takes the stored URL and fetches it over HTTP, and nothing resolves a Storage path through the authenticated SDK.

## 2. Options assessed

### Option A: rotate tokens and rewrite the stored links

The new tool `functions/src/ops/photoTokenRotation.ts` (`opsCli.js photo-token-rotate`) handles each photo as follows:
1. It skips the photo if it changed in the last 10 minutes.
2. It rewrites the object with the **same bytes**, content type, cache control and custom metadata, plus **one new random token** and a run marker. The rewrite happens only if the object is still at the generation that was read, and the MD5 must match afterwards.
3. It updates the owner's links: `completions` where `userId == uid`, and `users/{uid}/memories/*`. Each update is a transaction that changes `photoUrl` only if the document still names this object.

| Question | Answer (with evidence) |
|---|---|
| Do existing stored URLs stop working? | The **old token stops working** (emulator: refused after rotation). The **stored links are updated** in the same pass, so the app keeps working (emulator: links open identical bytes with the new token). |
| Do legitimate screens break? | No, once the links are updated. **Open tabs or app sessions** that already loaded the old URL show the error fallback until they reload or refresh. Images already in the browser or device cache keep showing. |
| Selective? | Yes. `--uid <uid>` limits it to one user (the canary). `--max` bounds each run. |
| How are new URLs generated and stored? | The new token is `crypto.randomUUID()`. The URL is built exactly as the client SDKs format it (`downloadUrl()`, unit-tested round-trip). It is written only into that user's own documents. |
| Concurrent clients with stale URLs? | Their image loads fail until they reload. Uploads within 10 minutes are skipped, so a completion that is still saving never stores a revoked URL. A later run picks those photos up. |
| Safe to retry? | Yes. A photo rotated by an interrupted attempt carries the run's marker, so a resume with the same run ID **only finishes its links and never issues a second token** (unit and emulator tests). `--resume <out file>` reuses the run ID and skips finished photos. |
| Partial failures detected? | Each photo gets an outcome: `rotated`, `references-updated`, `too-recent`, `no-token`, `skipped-name`, `changed-during-rotation`, `gone`, `rotate-failed`, `verify-failed` or `references-failed`. Link counts are updated, current, or changed meanwhile. |
| Profile photos? | **Not handled by this tool.** Avatars are public to signed-in users by design, and the live rules never let anyone upload one (7B T26), so few or none exist. A separate decision (§4, C4). |
| Account deletion and cleanup compatible? | Yes. A photo deleted mid-rotation is **not recreated** (emulator), because of the generation check and the 404/412 handling. Link updates skip deleted documents. Rotation and metadata remediation share one lease; orphan cleanup deletes only if the generation is unchanged. |
| What it can't do | It can't recall copies already downloaded. It can't stop someone who still has a valid session **and** the live (open) rules from fetching a new link. **That is why S-1 must be deployed and verified first.** |

### Option B: authenticated SDK access (no persistent token)

The app would resolve each private photo by its **Storage path** and fetch the bytes with the Firebase SDK (`ref.getData()`) under the current user's identity, so the Storage rules are evaluated on every load.

| Aspect | Assessment |
|---|---|
| Data model | **No migration needed to read.** The object path can be parsed from every stored URL (the parser exists and is tested in `objectNameFromUrl`; a Dart twin is needed). The rules' completion `photoUrl` regex accepts a **token-free** URL (`([?].*)?` is optional), so new completions could store `…/o/<path>` without a token. |
| Mobile | `getData(maxSize)` uses the signed-in user's token, and the rules are enforced. Flutter's in-memory `ImageCache` caches decoded images; there is **no disk cache** unless one is added (more downloads than CachedNetworkImage today). |
| Web | The JS SDK's `getBytes` makes an authorized cross-origin request. **Unverified:** whether the bucket's CORS configuration allows it from both Hosting origins. Firebase documents a bucket CORS configuration for in-browser downloads, which would be a separate production change. Must be checked on a test account before shipping. |
| Expired session or sign-out | A load fails with `unauthenticated` or `unauthorized`. The widget must show the fallback and route to sign-in. That is real revocation: a signed-out device can't load private photos. |
| Caching and sharing | Bytes stay in app memory or the app's private cache. No shareable link exists. |
| Cost | The same bytes are downloaded. Without a disk cache there are more repeat downloads. Rules evaluations are billed as normal operations. |
| Revocation | Immediate. Rules apply on every load, and a token is never needed after migration. |
| Effort and risk | 4 render paths plus the map-pin loader; a new `ImageProvider` with loading and error states; widget tests; web CORS verification. **Not implemented in 7C:** it would change every photo screen and can only be verified against real Storage on web. |

### Option C: staged transition (recommended)

This combines A now with B later, with deadlines.

## 3. Recommended strategy

| Stage | What | Gate | Suggested deadline |
|---|---|---|---|
| **C1** | Deploy S-1 (interim Storage rules) and verify it read-only | Authorization AC-1 (Phase 7B question, still pending) | **Now** |
| **C2** | **Rotate every completion-photo token and rewrite the owner's links** (Option A) | C1 verified live, **then** AC-2 (dry-run), AC-3 (test-account canary), AC-4 (full run) | Within **7 days** of C1 |
| **C3** | Ship Option B in the app (SDK access by path; new completions store token-free URLs) | Coordinated release or the next one; web CORS verified on a test account | By the first release after the coordinated release |
| **C4** | Retire persisted tokens: one more rotation **without** link rewrites (no client uses them after C3). Decide on profile photos: either rotate avatars and update `users` and `leaderboard_public`, or accept "visible to signed-in users and anyone they share the link with" and disclose it. | C3 deployed and stable for 14 days | Within **30 days** of C3 |
| **End** | Remove token-URL rendering for private photos from the app | — | With C4 |

**Why C2 must not run before C1:** under the live rules, any signed-in user can call `getDownloadURL` again and get the **new** token. Rotating first would change nothing for an attacker.

**Why C2 shouldn't wait for C3:** C3 depends on the coordinated release, which is blocked on other items (D-04 deployment, signing, Firebase app registration). C2 works with **today's live web app unchanged**, because the stored links are updated.

**Combination with historical-metadata remediation:** both jobs rewrite objects. Run **C2 first** (urgent revocation), then the metadata job, which keeps whatever token is current. They share a lease, so they can't overlap.

## 4. Data migration requirements

| Stage | Firestore writes | Storage writes |
|---|---|---|
| C2 | `photoUrl` in `completions/*` (that user's) and `users/{uid}/memories/*` whose URL names the rotated object. Admin SDK; completions stay immutable to clients. | Every `completion_photos/{uid}/{name}.jpg` with a token is rewritten: same bytes, one new token, and the marker `tgTokenRotation=<runId>` |
| C3 | None required: paths are parsed from the existing URLs. Optional later clean-up: strip tokens from stored URLs. | None |
| C4 | None (C3 no longer reads the token), or `users` + `leaderboard_public` for avatars if rotated | Rewrite again (new run ID) |

## 5. Backward compatibility

- **Live web app (old build):** unaffected by C2 apart from open tabs (stale URLs, so reload). Uploads in the 10 minutes before a run are skipped.
- **New app (coordinated release):** the same stored-URL rendering until C3. C2 links are ordinary SDK-format URLs.
- **Firestore rules:** C2 writes through the Admin SDK and never relaxes rules. The rewritten URLs still match the completion `photoUrl` regex, so they stay valid if a document is ever re-validated.
- **Offline-cached Firestore documents (web persistence):** a client may hold the old URL until its listener refreshes. The image fails, then loads after the snapshot updates.

## 6. Procedure and authorization checkpoints

Each **AC** is a separate, explicit authorization. Approval of one is not approval of the next.

| AC | Operation (exact) | Reads | Writes | Evidence to collect |
|---|---|---|---|---|
| AC-1 | S-1: `firebase deploy --only storage --config deploy/interim/firebase.interim-storage.json --project touchgrass-today` | — | Storage rules release | Read-only re-export: live SHA-256 = `630dc9a0…dcff17` |
| AC-2 | **Dry-run** (enumerates private object names; reads object metadata and that user's Firestore documents for counting):<br>`node lib/ops/opsCli.js photo-token-rotate --project touchgrass-today --real-project --out <private file>` | Object list and metadata (including token presence; tokens are never output); `completions` per user; `memories` per user | **Nothing** in production; the local `--out` file only (mode 0600) | Counts: `would-rotate`, `too-recent`, `no-token`, `skipped-name`; links that would update |
| AC-3 | **Canary on a TEST account** (create it, complete 1–2 challenges with photos on the live web app, note one photo URL **privately**):<br>`… photo-token-rotate --project touchgrass-today --real-project --uid <test uid> --execute --confirm-project touchgrass-today --out <file>` | The test account's objects and docs | The test account's photos (rewritten) and links | (1) Old URL → HTTP 403/404 (`curl -s -o /dev/null -w "%{http_code}"`; don't paste the URL anywhere); (2) the Journal and challenge details show the photo after reload; (3) `--out` shows `rotated` and `refsUpdated ≥ 1` |
| AC-4 | **Full run**, bounded (`--max 500`), repeated with `--resume <previous out>` until done:<br>`… photo-token-rotate --project touchgrass-today --real-project --execute --confirm-project touchgrass-today --max 500 --out <file>` | All completion photos and their owners' docs | All completion photos with a token, plus the links | Outcome counts; zero `verify-failed`; `references-failed` resolved by a resume |
| AC-5 | Mop-up for `too-recent` photos: same command 24 h later with a **new** `--run-id`; finished photos are skipped through `--resume` | — | — | Every photo rotated or explained |
| AC-6 | (C4) Second rotation after C3, plus the avatar decision | — | — | — |

**Build the tool before use:** `cd functions && npm ci && npm run build`. It uses Application Default Credentials (`gcloud auth application-default login` by the owner); no key files.

**Stop conditions:**
- `verify-failed` greater than 0;
- `references-failed` that won't clear on resume;
- any user report of missing photos after a reload;
- an unexpected number of `skipped-name` photos;
- the lease is held unexpectedly.

On any of these: stop, keep the `--out` files, and report.

## 7. Recovery and rollback

- **Restoring an old token is not offered**, deliberately: it would re-enable every harvested link.
- **Links:** a resume with the same run ID re-points every link at the object's current token. This is idempotent.
- **Object content:** the rewrite keeps the bytes, and the MD5 is verified before any link changes. If the bucket has **soft delete** enabled (owner check, §8), the previous generation is restorable by a project admin for the soft-delete window. Soft-deleted objects are not served through download URLs.
- **If the app shows broken photos after C2:** run the same command with `--resume <out>`. If that fails, a project admin can read the current token from the object metadata in the Cloud Console and fix the one document by hand. Don't copy tokens into chat or tickets.

## 8. Operational and cost risks; owner checks

| Item | Notes |
|---|---|
| Egress | Each photo is downloaded once and re-uploaded. Run from a laptop, that is internet egress, about photo size × count. For example, 1,000 photos × 0.5 MB ≈ 0.5 GB, a few cents at list price. The actual count is unknown until AC-2. |
| Operations | Per photo: about 3 metadata reads, 1 download, 1 upload. Per user: 2 Firestore queries. Per link: 1 transaction. |
| Runtime | Sequential, roughly 0.5–1 s per photo from a laptop (estimate, not measured on production). |
| Soft delete / versioning | **Owner check:** `gcloud storage buckets describe gs://touchgrass-today.firebasestorage.app --format="default(soft_delete_policy,versioning)"`. Each rewrite leaves the previous generation soft-deleted for that window. If **object versioning** is enabled, old generations persist until deleted. |
| Audit logs | **Owner check:** Cloud Console → IAM & Admin → Audit Logs → Cloud Storage → Data Read. If it was off, past access can't be established. Consider enabling it now for future evidence (small cost). |
| Notification duty | Whether the past exposure must be notified is a legal question for the owner. |
