# Phase 7G — Release readiness, disclosures and production approval queue

**Overall: NOT RELEASE READY. Incident: contained at rules level; NOT closed.** Every remaining mandatory step needs production credentials, a production approval, a Mac, or an owner decision.

## 1. Dependency graph of what remains

```
Owner: install gcloud + `gcloud auth application-default login`   (credentials)
 └─ AC-1 read-only link inventory ── review ──┐
     └─ AC-2a/2b test-photo revocation experiment (approval ×2)
         └─ AC-3.1 → 3.2 → 3.3 staged rotation (approval per stage)
             └─ AC-5 metadata remediation (approval per stage) ── M-6 backup purge
 └─ AC-4 read-only metadata inventory (approval; independent of AC-1..3) ──┘

AC-6 deleteAccount deploy (approval; no credentials needed beyond firebase login)
 └─ coordinated window: R-1 Firestore rules + AC-7a Storage rules + AC-7b IAM grant + I-1 indexes + H-1 Hosting
     └─ two-account deletion test ── PD-1 partial-deletion audit (approval) ── owner/legal: contact policy

AC-8 app registrations (approval) ── owner: Android signing ── Android release build ── platform tests
                                  └─ Mac + Apple account: iOS build, device tests, TestFlight
AC-9 dev/prod separation (approvals; owner workflow decision)
AC-10 publication: policy / Terms / store listing (after the gates above) ── store submission (separate)
Owner/legal: D15–D17, D19, D20 disclosure decisions; deletion-marker retention; avatar scan (optional)
```

## 2. Mandatory gates

Legend:
- ✅ passed, with evidence;
- 🔧 fixed locally, not live;
- ⏳ ready, needs approval;
- 👤 owner;
- 🍎 needs a Mac;
- ❌ open.

| # | Gate | State |
|---|---|---|
| 1 | Live Storage rules verified | ✅ (read-only, 7F, 2026-10-21; nothing has deployed since, and 7G made no production calls) |
| 2 | Rotation dry-run proven read-only | ✅ locally (mutation traps + emulator snapshot); production run ⏳ AC-1 |
| 3 | Authorized inventory complete | ❌ 👤 credentials → ⏳ AC-1 |
| 4 | Old-link invalidation proven in production | ❌ ⏳ AC-2 |
| 5 | Challenge-photo rotation complete and verified | ❌ ⏳ AC-3 |
| 6 | Historical metadata assessed and remediated | ❌ ⏳ AC-4 / AC-5 |
| 7 | No unauthorized production operation | ✅ (none in 7G) |
| 8 | Deletion: local tests for missing data, failures, retries, concurrency, late uploads | ✅ |
| 9 | Late-upload mitigation + no profile re-creation | 🔧 (tests pass) → ⏳ AC-7 + R-1 |
| 10 | Deletion deploy scope verified | ✅ (manifest: one endpoint, no params) |
| 11 | Deletion works in production (test accounts) | ❌ ⏳ AC-6 + window |
| 12 | Partial-deletion recovery documented | ✅ (design); audit ⏳ PD-1; contact 👤 |
| 13 | AI-verification announcement removed; AI disabled | ✅ locally (shows in production with H-1) |
| 14 | Claims match behaviour | Partly (§3) |
| 15 | Android/iOS Firebase identifiers correct | ❌ ⏳ AC-8 |
| 16 | Android signing configured | ❌ 👤 |
| 17 | Full Android release build | ❌ (after 15 + 16; gates pass) |
| 18 | iOS built and validated | ❌ 🍎 (explicitly blocked: no macOS) |
| 19 | Platform tests (Auth, uploads, deletion, permissions) | ❌ (after 11, 15–18) |
| 20 | Dev/prod separation plan approved; local safeguards | Plan ✅; approval ⏳ AC-9; operator-tool safeguards ✅ |
| 21 | Regression suites pass | ✅ (final report §17) |
| 22 | Repository integrity | ✅ (final report §21) |

## 3. Privacy and store disclosures

| ID | Current local wording | Actual behaviour | Accurate now? | Depends on | Correction |
|---|---|---|---|---|---|
| D1 | Other users "can't browse or open" your challenge photos in the app; each has a private link; anyone you share it with can see it | True through Firebase (live rules). **Links harvested before 2026-10-20 04:30Z still open photos.** | Only after remediation | AC-3 | None; don't add an "owner-only" claim until AC-3 |
| D2 | Profile photo shown to other signed-in users; link-holders can see it | Live S8 | Yes | — | — |
| D3/D14 | Delete Account permanently deletes the account and the listed data | The live deletion is broken; local deletion is complete, except the retained items (analytics, crash reports, one log line, Storage soft-delete, **the deleted-account marker: uid + timestamps**) | After deployment | AC-6 + window | **Add the marker** to the deletion-exceptions text before publication (owner wording) |
| D4–D8, D12–D13 | Former AI claims removed | AI off | Yes | — | — |
| **D18** | Camera "AI verification — Coming soon!" | — | **Fixed in 7G** (removed) | H-1 to reach users | Done locally |
| D9 | "Your photos are not sent to any AI service: AI photo verification is turned off" | True for the new build; **the live build can send photos to Gemini** (entitled tiers) | After H-1 | H-1 | — |
| D10 | Earlier photos "may still contain location details" | True (unassessed) | Yes | Update after AC-5 | — |
| D11 | Location saved only if the setting is on | True for Firestore fields. **Old photo files** may embed GPS. | Only after remediation | AC-5 | Owner: add a caveat until then |
| D15 | "thousands of other explorers" | Unverified | Owner | — | Substantiate or remove |
| D16 | Retention periods | Placeholders | Owner | — | Owner/legal |
| D17 | Notice of the past exposure (any signed-in user could read photos until 2026-10-20) | Fact | Owner/legal | — | Decision needed |
| D19 | Terms #3 "never share identifiable photos publicly without your consent" | No intentional sharing; harvested links exist | Not verified | AC-3 | Legal review |
| **D20 (new)** | (nothing) | The live web app can send photos to Google Gemini for verification (paid tiers; the old key's state is unknown) | — | — | **Owner/legal:** whether past AI processing needs disclosure |
| — | Location, analytics, Crashlytics, Performance, Open-Meteo, geocoding | Listed in the in-app policy (Phase 3) | Yes | — | — |
| — | AI-generated challenges | None: challenges come from the built-in seed library | Yes | — | — |

**Publication:** nothing is published. AC-10 needs a separate approval and only for statements whose dependencies have passed.

## 4. Production approval queue

Stop at the first blocked item. Each row needs its own approval; none implies another.

| Gate | Operation (exact) | Reads | Writes | Sensitivity | Cost | Preconditions | Verification | Rollback limits |
|---|---|---|---|---|---|---|---|---|
| **AC-1** | `node lib/ops/opsCli.js photo-token-rotate --project touchgrass-today --real-project --out ../ops-out/rotation/dry-1.json --max 1000` | Object names and metadata; `photoUrl` fields | **None** | Private object names (uids) in a local file | < $0.01 | **Credentials (blocked now)**; `npm ci && npm run build && npm test` | `operationMode: read-only`; correct bucket; aggregates reviewed | — |
| AC-2a | Experiment setup, pause, cleanup (`PHASE_7G_TOKEN_ROTATION_RUNBOOK.md`) | Test object and doc | 2 test users, 1 test object, 1 doc, lease doc | Synthetic only | ~0 | AC-1 reviewed | Probes `before`/`paused` pass | `cleanup` |
| AC-2b | Remove the test object's old token | — | 1 metadata patch | Synthetic | ~0 | AC-2a paused passed | `revoked` twice, ≥15 min apart | None (by design) |
| AC-3.n | Staged rotation, `--mode production-mutation` | Photos' metadata, owner links | Tokens + links | Real users' links | Small | AC-2 `revoked`; anomalies reviewed | 0 `verify-failed`; app sample | Old tokens unrecoverable |
| AC-4 | Metadata inventory `--full-read` | **Photo bytes** (in memory) | None | Real photo content processed | Egress ≈ total bytes | Credentials | Counts reviewed | — |
| AC-5.n | Remediation stages + M-6 purge | Photo bytes | Rewrites + backups; purge deletes | Backups hold GPS until purged | Small | AC-3 done; AC-4 complete | `exiftool` on test copies; re-inventory | Backups 14 days |
| AC-6 | `firebase deploy --only functions:deleteAccount --project touchgrass-today` | — | One function + first-deploy API enablement and service identities | — | Within free quotas (estimate) | Unit/emulator green; manifest one endpoint | `functions:list` only `deleteAccount` | `functions:delete` |
| AC-7a | `firebase deploy --only storage --project touchgrass-today` (in the window with R-1, I-1, H-1) | — | Storage ruleset | — | 1 read per upload | AC-6; parity green | §4 of `PHASE_7G_STORAGE_RULES_DEPLOYMENT.md` | Redeploy the previous ruleset |
| AC-7b | Grant `roles/firebaserules.firestoreServiceAgent` to `service-760620662222@gcp-sa-firebasestorage.iam.gserviceaccount.com` (project IAM) | — | One IAM binding | — | 0 | Approve with AC-7a | IAM policy shows the binding | Remove the binding |
| AC-8 | `firebase apps:create ANDROID … com.touchgrass.app` and `IOS … com.touchgrass.app` (+ SHA fingerprints) | — | 2 app registrations | — | 0 | — | `apps:list`; `--full` gates | Remove the apps |
| AC-9 | Dev project + aliases (`PHASE_7G_FIREBASE_ENVIRONMENT_PLAN.md` §2) | — | New project only | — | Free on Spark | Owner decision | Dev builds hit dev | Delete the dev project |
| AC-10 | Hosting release (H-1, in the window) and publication of disclosures; store submission separately | — | Both Hosting sites; public text | Public | — | Gates 1–19 | — | Hosting rollback; republish |

**Not part of any gate above (separate approvals):**
- G-AV: delete the 7E leftover 1×1 test avatar;
- PD-1: the partial-deletion audit;
- the TTL policy for `deletedAccounts`.
