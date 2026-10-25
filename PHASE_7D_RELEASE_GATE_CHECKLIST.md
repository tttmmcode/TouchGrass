# Phase 7D — Release Gate Checklist

**Legend:**
- ✅ done and verified;
- ⏳ ready, needs authorization;
- ❌ open;
- 👤 owner action.

Production evidence is labelled **LIVE**; everything else is local.

**State (2026-10-20, after Phase 7D):**
- Interim Storage rules are **LIVE and verified**.
- Everything after that is pending.
- **Not release-ready.**

## 1. Storage rules

| # | Gate | State |
|---|---|---|
| 1.1 | Interim rules (S-1) live | ✅ **LIVE**: deployed 04:30Z on 2026-10-20; the export is byte-identical to `deploy/interim/storage.interim.rules` (`630dc9a0…`) |
| 1.2 | Live access behaviour smoke-tested with test accounts (S1–S9) | 👤 Owner (`PHASE_7D_PRODUCTION_SECURITY_RUNBOOK.md` §2.1) |
| 1.3 | Final `storage.rules` correct and parity-gated | ✅ local (569/569; static grant inventory) |
| 1.4 | Final rules deployed with the new web build (S-2 + H-1, same window) | ⏳ coordinated release |

## 2. Existing download-token exposure

| # | Gate | State |
|---|---|---|
| 2.1 | Rotation tool never breaks a saved link; challenge photos only | ✅ local (7D two-phase; unit invariant + emulator) |
| 2.2 | AC-2 dry-run (read-only) | ⏳ needs authorization **and** owner ADC (blocker) |
| 2.3 | AC-3 canary on a test account proves the old link is refused **in production**, and picks `metadata` vs `rewrite` | ⏳ |
| 2.4 | AC-4 staged rotation complete, plus a mop-up after 24 h | ⏳ |
| 2.5 | Exposure closed only when 2.4 is verified | ❌ |

## 3. Historical photo metadata

| # | Gate | State |
|---|---|---|
| 3.1 | New uploads stripped (EXIF/XMP/GPS, between scans, after EOI; avatars) | ✅ local (29 + 3 tests) |
| 3.2 | Inventory M-1 (after 2.4) | ⏳ |
| 3.3 | Test-account remediation M-3, then staged M-4/M-5 | ⏳ |
| 3.4 | Backups purged after 14 days (M-6) | ⏳ |

## 4. Account deletion

| # | Gate | State |
|---|---|---|
| 4.1 | Root cause established (live client cascade refused by the immutable-completion rules) | ✅ |
| 4.2 | Server deletion complete, idempotent, concurrency-safe, with a second Storage sweep | ✅ local (unit 203, emulator 36) |
| 4.3 | F-1: deploy `deleteAccount` only | ⏳ |
| 4.4 | Two-account production test | ⏳ after 4.3 + H-1 |
| 4.5 | Decision on the ≤1 h post-deletion token window | 👤 |

## 5. Profile-photo visibility

| # | Gate | State |
|---|---|---|
| 5.1 | No listing in either ruleset | ✅ LIVE (interim) + local (final) |
| 5.2 | Disclosure says signed-in users, and anyone given the link, can see it | ✅ local copy (D2) |
| 5.3 | Decision: rotate avatar tokens / move to SDK reads (C4) | 👤 |

## 6. Rules parity and configuration

| # | Gate | State |
|---|---|---|
| 6.1 | Same 64 behaviour cases against both rulesets; only P37/P43 may differ | ✅ |
| 6.2 | Exact grant inventory per file (any new or widened grant fails) | ✅ |
| 6.3 | `firebase.json` → `storage.rules`; the interim config contains only `storage` | ✅ |
| 6.4 | `.firebaserc`, `firebase_options.dart` and `firestore.rules` agree on `touchgrass-today` / `touchgrass-today.firebasestorage.app`; no `gen-lang-client-` reference | ✅ (new test) |
| 6.5 | Every deploy uses a narrow `--only` target and an explicit `--project` | Process |

## 7. Web and mobile compatibility

| # | Gate | State |
|---|---|---|
| 7.1 | Flutter format / analyze / tests | ✅ see the final report |
| 7.2 | Web release build, and the bundle scan shows only the public Firebase web key | ✅ see the final report |
| 7.3 | Coordinated window R-1 + S-2 + H-1, with I-1 indexes first (7A manifest) | ⏳ |
| 7.4 | Smoke test after the release (completion, Journal, avatar, leaderboard, deletion) | ⏳ |

## 8. Privacy disclosures

| # | Gate | State |
|---|---|---|
| 8.1 | False claims corrected in the local copy and listing (D1–D8, D12–D14) | ✅ local, regression-tested |
| 8.2 | D1 published only after 2.4; D3/D14 only after 4.4; D11 after 3.3 | ⏳ |
| 8.3 | Retention periods, notification duty, marketing claims | 👤 (D15–D17) |
| 8.4 | Hosted privacy policy and store forms submitted | 👤 separate authorization |

## 9. Firebase configuration

| # | Gate | State |
|---|---|---|
| 9.1 | Indexes (I-1) deployed (the completions query needs them) | ⏳ (7A B13) |
| 9.2 | Firestore rules R-1 (create-only completions, profile-photo rule, …) | ⏳ coordinated |
| 9.3 | Cloud Storage audit logs, soft delete and versioning reviewed | 👤 |

## 10. Signing and platform validation (re-checked read-only in 7D)

| # | Gate | State |
|---|---|---|
| 10.1 | Android release signing (`android/key.properties`) | ❌ absent (B7) |
| 10.2 | Firebase Android app for `com.touchgrass.app` | ❌ `google-services.json` is for `com.example.touchgrass`, while the app ID is `com.touchgrass.app` (B6) |
| 10.3 | iOS build, signing and entitlements (needs a Mac) | ❌ (B6) |
| 10.4 | Maps key restrictions (B5) | 👤 |

## Release order

Each step is separately authorized.

1. ✅ S-1.
2. Smoke tests (1.2).
3. AC-2 → AC-3 → AC-4 (rotation).
4. M-1 → M-6 (historical metadata).
5. F-1.
6. I-1.
7. Coordinated R-1 + S-2 + H-1.
8. Two-account deletion test (4.4).
9. Publish only the disclosures whose gates have passed.
10. Signing and platforms (10.x) before any store submission.
