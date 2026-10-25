# Phase 7F — Production security status

**Status:**
- **Contained at rules level** (re-verified read-only this phase).
- **Legacy links not remediated.**
- **Historical metadata not assessed.**
- **The incident remains open.**

## 1. Live state, verified read-only on 2026-10-21

Method: firebase-tools' own GET-only Rules API helpers (releases list, ruleset get) under the account the Firebase CLI is already signed into. No account switch; nothing printed but hashes and release times. Script: scratchpad `p7f/live_rules_check.cjs`.

| Resource | Live | Repository | Verdict |
|---|---|---|---|
| Storage rules (`firebase.storage/touchgrass-today.firebasestorage.app`) | `630dc9a0…dcff17`, released **2026-10-20T04:30:20Z**; no release since | `deploy/interim/storage.interim.rules` `630dc9a0…dcff17` | **Byte-identical to the interim rules** |
| Firestore rules (`cloud.firestore`) | `eb6b6b1c…d0edc2`, released 2026-08-13 | `git show HEAD:firestore.rules` = `eb6b6b1c…`; the working-tree `firestore.rules` (`32f35342…`) is the unreleased R-1 | Unchanged since before the incident work |
| Cloud Functions | `firebase functions:list` → "No functions found" | `deleteAccount` exists locally only | Nothing deployed |
| Firebase apps | `firebase apps:list`: Android `com.example.touchgrass` (`…24eb…`), iOS (`…0906…`), 2 web apps | — | Unchanged; mismatch open (`PHASE_7F_FIREBASE_PLATFORM_CONFIGURATION.md`) |

Not re-run in 7F: the live smoke test (S1–S9, **32/32 on 2026-10-20 05:26Z**). The rules it tested are byte-identical to what is live now, so its results still describe the live rules. Rerunning it would be a new production operation (test accounts and objects) needing its own approval. It isn't needed until a rules change.

## 2. What is and isn't protected today

| Exposure | State | Evidence |
|---|---|---|
| Another user lists, opens or gets a link for someone's challenge photo through Firebase | **Blocked** | Live smoke S1–S6 (7E); rules unchanged since |
| Anyone lists profile photos | **Blocked** (single GET only, for signed-in users) | Live S8a–S8g (7E) |
| Uploads: wrong owner, type or size | **Blocked** | Live S7 (7E) |
| **Someone holding an old challenge-photo link** (harvested before 04:30Z on 2026-10-20) | **Still opens the photo without sign-in** | Live T1: HTTP 200 (7E) |
| GPS or metadata inside photos stored before the stripping fix | **Unknown**: not inventoried | — |
| Late uploads after account deletion | Not applicable live (no server-side deletion deployed); fixed locally in the final rules | `PHASE_7F_LATE_UPLOAD_MITIGATION.md` |

## 3. Leftover from the 7E smoke test

One 1×1 synthetic PNG avatar, `user_avatars/<smoke test account A>.png`. The account itself was self-deleted at 05:26Z on 2026-10-20.
- **Identity:** the exact uid is in the 7E run's local result file (`scratchpad p7e/live_result.json`, not in the repo). Before removal, confirm in the console that the object is 1×1, about 70 bytes, `image/png`, created 2026-10-20 ~05:26Z, and that **no Auth user** with that uid exists.
- **Removal:** a single-object delete in the Firebase console. This is a production deletion and needs explicit approval (G-AV). It was not done.

## 4. Production operations in Phase 7F

**Performed:** read-only only.
- rules releases list and ruleset get;
- `firebase functions:list`;
- `firebase apps:list`.

**Not performed:**
- token dry-run, experiment or rotation;
- metadata inventory or remediation;
- backups, deletions, the avatar removal;
- any deploy (Functions, Hosting, rules, indexes);
- app registrations;
- publication of policy, Terms or store listing;
- cleanup jobs;
- changes to user records, Auth, billing, Maps or AI.
