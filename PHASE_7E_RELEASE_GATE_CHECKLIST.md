# Phase 7E — Release Gate Checklist

**Legend:**
- ✅ passed (evidence named);
- ⏳ ready, needs authorization;
- ❌ open;
- 👤 owner action.

**LIVE** marks production evidence.

**Overall: NOT RELEASE READY.**

| Area | Status (7E vocabulary) |
|---|---|
| Storage rules | **Contained at rules level**, verified LIVE (32/32 smoke checks) |
| Legacy links | **Not remediated:** LIVE T1 shows an old token URL opens without sign-in |
| Historical metadata | **Not assessed** |
| Account deletion | **Fixed locally:** production unchanged |

## 1. Storage rules

| # | Gate | State |
|---|---|---|
| 1.1 | Interim rules live and byte-identical to the reviewed file | ✅ LIVE (exports at 04:30Z and 05:01Z) |
| 1.2 | S1–S9 live smoke test with dedicated test accounts | ✅ LIVE 32/32 (`PHASE_7E_PRODUCTION_SMOKE_TEST_RESULTS.md`) |
| 1.3 | Leftover test avatar removed | 👤 optional (console) |
| 1.4 | Final rules parity-gated | ✅ local (rules 569/569) |
| 1.5 | Final rules deployed with the web build | ⏳ coordinated window |

## 2. Legacy download links (challenge photos)

| # | Gate | State |
|---|---|---|
| 2.1 | Tool safe: no dead saved link, no byte rewrite, resumable, redacted, challenge-only | ✅ local (unit + emulator) |
| 2.2 | Dry-run aggregates (no references / stale links / predicted writes) and the experiment pause | ✅ local (7E) |
| 2.3 | Owner credentials (ADC) | 👤 **blocker** |
| 2.4 | AC-2 read-only dry-run | ⏳ |
| 2.5 | AC-3 revocation experiment on a test object; old URL refused **in production** | ⏳ |
| 2.6 | AC-4 staged rotation, 0 `verify-failed` | ⏳ |
| 2.7 | "Legacy links remediated" | ❌ only after 2.5 + 2.6 |

## 3. Historical metadata

| # | Gate | State |
|---|---|---|
| 3.1 | New uploads stripped (challenge + profile) | ✅ local (Flutter tests) |
| 3.2 | Inventory M-1 → "assessed" | ⏳ after 2.6 |
| 3.3 | Test-account remediation, staged M-3…M-5 → "remediated" | ⏳ |
| 3.4 | Backup purge M-6 | ⏳ |

## 4. Account deletion

| # | Gate | State |
|---|---|---|
| 4.1 | Root cause verified | ✅ |
| 4.2 | Local fix + tests (0/1/3 completions × photos; concurrency; second sweep; failures) | ✅ local (unit 208, emulator 43) |
| 4.3 | **Deploy blocker removed:** the entry point declares no secrets (AI moved out) | ✅ local (7E) |
| 4.4 | Post-deletion upload window: rules cross-check or sweep | 👤 decision |
| 4.5 | F-1 deploy | ⏳ |
| 4.6 | Two-account end-to-end test → "verified in production" | ⏳ after 4.5 + H-1 |

## 5. Profile photos

| # | Gate | State |
|---|---|---|
| 5.1 | No listing; single GET for signed-in users; owner-only writes | ✅ LIVE (S8a–S8g) |
| 5.2 | Disclosure covers link visibility | ✅ local copy |
| 5.3 | Rotation / SDK reads decision (C4) | 👤 |

## 6. Disclosures

Each one is ready only when its dependency has passed.

| Statement | Depends on | State |
|---|---|---|
| D1 photos not browsable by other users | 2.7 (harvested links) | ❌ |
| D2 profile-photo link visibility | — | ✅ wording |
| D3/D14 deletion | 4.6 | ❌ |
| D4–D8, D12–D13 AI claims removed | — | ✅ wording (AI stays off; 7E also removed AI from the deploy entry point) |
| D10/D11 location in old photos | 3.3 | ❌ |
| Retention periods, notification duty, marketing claims | — | 👤 |
| Publication of the policy, Terms and store listing | all of the above | ⏳ separate authorization |

## 7. Firebase configuration and platforms

| # | Gate | State |
|---|---|---|
| 7.1 | Project and bucket consistent across `.firebaserc`, `firebase_options.dart`, rules | ✅ local test |
| 7.2 | Firebase Android **and iOS** apps registered for `com.touchgrass.app` (both are `com.example.touchgrass` today) | ⏳ production change (`PHASE_7E_ANDROID_RELEASE_READINESS.md` §3) |
| 7.3 | Android release signing + Play App Signing | 👤 |
| 7.4 | Android gates | ✅ 14/14 |
| 7.5 | Android `--full` build | ❌ after 7.2 |
| 7.6 | iOS build on a Mac | ❌ not validated (no macOS) |
| 7.7 | Indexes I-1, Firestore rules R-1 | ⏳ coordinated window |
| 7.8 | Maps / API key restrictions | 👤 |

## 8. Local regression (this run)

See `PHASE_7E_FINAL_REPORT.md` §4. Every suite is listed with actual counts and exit codes.

## Order of the remaining production steps

Each is separately authorized.

1. Owner provides ADC.
2. AC-2 dry-run.
3. AC-3 revocation experiment.
4. AC-4 staged rotation.
5. M-1 inventory, then M-3…M-6.
6. F-1.
7. Register the Android and iOS apps (7.2).
8. Coordinated I-1 + R-1 + S-2 + H-1.
9. Two-account deletion test.
10. Publish the disclosures whose gates passed.
11. Signing and store submission (out of scope).
