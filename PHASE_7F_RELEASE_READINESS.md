# Phase 7F — Release readiness, disclosures and deployment plan

**Overall: NOT RELEASE READY. Incident status: contained at rules level; partially remediated (locally). Not closed.**

**Legend:**
- ✅ passed, with evidence;
- 🔧 fixed locally (not live);
- ⏳ ready, needs authorization;
- 👤 owner action or decision;
- ❌ open or blocked.

## 1. Mandatory gates

| # | Gate | State | Evidence or blocker |
|---|---|---|---|
| 1 | Live Storage rules independently verified | ✅ | Read-only export 2026-10-21: byte-identical to interim |
| 2 | Test-account security checks | ✅ (7E, same rules) | Live smoke 32/32, 2026-10-20 |
| 3 | Token behaviour understood from production evidence | ❌ | Needs ADC → AC-2 → AC-3a/b |
| 4 | Old challenge links invalidated | ❌ | AC-4 stages after AC-3 shows `revoked` |
| 5 | Historical photos inventoried | ❌ | M-1 (needs ADC + approval) |
| 6 | Historical metadata remediated and verified | ❌ | M-3…M-6 |
| 7 | No unrelated production change | ✅ | 7F performed read-only operations only |
| 8 | Deletion tested (completions × photos, failures, retries, concurrency) | ✅ local | Unit + emulator (final report §13) |
| 9 | Late uploads mitigated | 🔧 | Final `storage.rules` `hasProfile()`; ships with S-2 |
| 10 | Deletion deploy scope verified | ✅ local | Manifest: one endpoint, no params |
| 11 | Deletion works end to end in production | ❌ | F-1 + coordinated release + the two-account test |
| 12 | Partial-deletion recovery plan | ✅ designed | Owner/legal decision on contact vs. completion |
| 13 | Android app ID = Firebase registration | ❌ | G-1 |
| 14 | iOS bundle = Firebase registration | ❌ | G-1 |
| 15 | Android signing configured | ❌ 👤 | `PHASE_7F_ANDROID_SIGNING_GUIDE.md` |
| 16 | Android release build | ❌ | After 13 + 15 (gates proven 14/14) |
| 17 | iOS release build on a Mac | ❌ | No macOS here |
| 18 | Platform tests (Auth, Storage, Firestore, deletion) | ❌ | After 11, 13, 16, 17 |
| 19 | Claims match behaviour | Partly | §2 |
| 20 | AI photo verification disabled | ✅ | Manifest has no AI endpoint; the client has no key; bundle scan |
| 21 | New uploads strip metadata | ✅ local | Flutter tests; single upload boundary |
| 22 | Regression suites pass | ✅ | Final report §13 |
| 23 | No secrets in bundles or logs | ✅ web | Bundle scan; Android after 16 |
| 24 | Repository integrity | ✅ | Final report §18–19 |

## 2. User-facing claims (Phase I classification)

| ID | Claim (current local wording) | Classification | Why |
|---|---|---|---|
| D1 | Other users "can't browse or open" your challenge photos; each is shown through a private link that anyone you share it with can see | **Accurate only after legacy data remediation** | True for access through Firebase (live). But links harvested during the exposure still open photos until AC-4. |
| D2 | Profile photo shown to other signed-in users; anyone they share its link with can see it | **Accurate today** | Live S8 |
| D3 / D14 | Delete Account permanently deletes the account and the listed data | **Accurate only after a specific approved deployment** (F-1 + H-1; S-2 for late uploads) | Live deletion is broken (7D §1) |
| D4–D8, D12–D13 | AI claims removed (verify, improve AI, AI-powered challenges, Gemini) | **Accurate today** | AI off; Flutter guard tests; `STORE_LISTING.md` line 133 states AI is disabled |
| D9 | "Your photos are not sent to any AI service" | **Accurate today** | No AI endpoint deployed; client has no key |
| D10 | Earlier photos "may still contain location details" | **Accurate today** | Historical GPS unassessed |
| D11 | Location saved only if the setting is on | **Accurate only after legacy data remediation** for photo **files** | Firestore fields: true. Old photo files may embed GPS. |
| D15 | "thousands of other explorers" | **Requires a user or legal decision** | Unsubstantiated |
| D16 | Retention periods (analytics, crash, logs, soft delete) | **Requires a user or legal decision** | Placeholders |
| D17 | Notice of the past exposure | **Requires a user or legal decision** | Whether notification is required |
| **D18 (new, 7F)** | Camera screen: "AI verification — Coming soon!" / "AI verification is a premium feature, coming soon" (`camera_screen.dart` ~1620–1635; `camera_providers.dart` reason text) | **Requires a user or legal decision** | Not false about today (honor system), but it announces a future feature that would send photos to an AI service. If kept, the privacy policy must change before that feature ships. Left unchanged. |
| D19 (new) | Settings Terms #3: "we will never share identifiable photos publicly without your consent" | **Not yet verified** for links already harvested | No intentional sharing exists, but harvested links (D1) are a form of exposure. Legal review. |

AI capability was not reintroduced. The Flutter group "no false privacy or AI claims (Phase 7D)" keeps the removed claims from returning.

**Publication** (privacy policy, Terms, store listing) needs separate authorization (P-1) and only covers statements whose dependency has passed.

## 3. Deployment and operations plan (each row is a separate approval)

The brief's order is kept, with these dependency-driven adjustments:
- M-1 (the read-only inventory) can run right after AC-2, independently of the rotation.
- F-1 can deploy before the coordinated window: the live client never calls it.
- G-1 is independent and can happen any time.
- S-2's late-upload mitigation ships inside the coordinated release.

| # | Operation | Exact scope | Writes | Preconditions | Verify | Rollback |
|---|---|---|---|---|---|---|
| 0 | **Owner:** `gcloud auth application-default login` in your own terminal | Local credentials | — | — | `functions/` tools stop failing with an auth error | `gcloud auth application-default revoke` |
| AC-2 | Rotation dry-run: `node lib/ops/opsCli.js photo-token-rotate --project touchgrass-today --real-project --out ../ops-out/rotation/dry-1.json --max 1000` | `completion_photos/` metadata; owners' `photoUrl` fields | **None** | 0; `npm ci && npm run build` | Summary: `limitReached`, counts, `referenceAnomalies` | — |
| M-1 | Metadata inventory, `--full-read` (`PHASE_7F_HISTORICAL_METADATA_REMEDIATION.md` §4) | Photo bytes in memory | **None** | 0 | `needsRemediation`, categories | — |
| AC-3a | Experiment setup, pause and cleanup (`PHASE_7F_TOKEN_ROTATION_RESULTS.md` §2) | 2 test users, 1 test object, 1 doc, the lease doc | Test data only | 0 | Probes `before` and `paused` pass | `cleanup` |
| AC-3b | Remove the test object's old token | 1 metadata patch | Test object | AC-3a paused passed | Verdict `revoked`, twice, ≥15 min apart | — |
| AC-4.n | Staged rotation (25 → 250 → rest) | `completion_photos/` tokens + owner links | Yes | AC-3b `revoked`; `otherOwnerPath` 0 | 0 `verify-failed`; sample in app | Resume; old tokens irrecoverable by design |
| M-3…M-6 | Metadata remediation stages + backup purge | Photo bytes in place; backups | Yes | AC-4 done; M-1 | `exiftool` on test copies; re-inventory | Backups (14 days) |
| F-1 | `firebase deploy --only functions:deleteAccount --project touchgrass-today` | One function + first-deploy API enablement | Yes | Unit 216/216; manifest one endpoint | `functions:list` = only `deleteAccount` | `functions:delete` |
| G-1 | `firebase apps:create` Android + iOS (`com.touchgrass.app`); SHA fingerprints | Two app registrations | Yes | — | `apps:list`; `test_android_gates.sh --full` | Remove the new apps |
| R-1 + I-1 + S-2 + H-1 | Coordinated release: `--only firestore:rules`, `--only firestore:indexes`, `--only storage` (**final rules incl. `hasProfile()`; approve the Storage→Firestore IAM grant**), `--only hosting` | Rules, indexes, both Hosting sites | Yes | F-1; bundle scan; parity suite | New client flows; late-upload refusal; old client not served | Release history + previous rulesets |
| E2E | Two-account deletion test | Test accounts | Test data | F-1 + H-1 | `PHASE_7F_ACCOUNT_DELETION_VALIDATION.md` §4 | — |
| PD-1 | Partial-deletion audit (new read-only command) | `users.username`, `usernames` | None | Command written + reviewed | Counts | — |
| G-AV | Delete the 7E leftover test avatar | 1 object | Delete | Identity confirmed (`PHASE_7F_PRODUCTION_SECURITY_STATUS.md` §3) | Object gone | — |
| P-1 | Publish policy, Terms, store listing | Statements whose gates passed | Publication | §2 | — | Republish |
| Store | Submissions | — | — | Every gate in §1 | — | — |

**Every deploy uses the narrow `--only` target named above.** A broad `firebase deploy` is never used. Approval for one row never covers another.

## 4. Remaining exceptions needing explicit acceptance before release

- **Residual late-upload case** (a hand-made client re-creating its own profile within an hour of deleting the account): `PHASE_7F_LATE_UPLOAD_MITIGATION.md` §5.
- **Avatars from builds older than HEAD** not scanned for metadata.
- **Sign in with Apple tokens** not revoked on deletion (B14).
- **One Firebase project** for development and production.
