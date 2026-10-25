# Phase 7G — AI-verification copy audit

**Status: done locally (not published; the live web app still shows its old build).**
- The camera no longer advertises future AI photo verification.
- No screen claims AI verification is active, available or coming.
- AI photo verification stays disabled.

## 1. What was found (search of `lib/`, `web/`, manifests, `STORE_LISTING.md`)

Searched for: "AI verification", "Coming soon", "AI photo verification", "AI verified", "premium feature", "verified by AI", "Gemini", "AI-powered", "our AI". Search areas:
- the camera, preview, upload, caption and result steps;
- Challenge details, the Journal and map;
- Settings, Help and onboarding;
- accessibility labels, tooltips and empty states;
- the web shell and manifests.

The app has no localization files; all copy is in Dart.

| Where | What users saw or heard | What it implied | Action |
|---|---|---|---|
| Camera caption step (`camera_screen.dart`) | Banner **"AI verification — Coming soon!"** with a ✨ icon; screen-reader label **"AI verification is a premium feature, coming soon. Your adventure was accepted."** Shown to every free-tier user after the photo uploaded. | That an AI service will check photos, and that paying unlocks it | **Removed.** Replaced by **"Photo added · Add a note, then save it to your Journal"** (camera icon; the same text as the screen-reader label). |
| Caption step button | **"Share Adventure"** | That the photo is shared with others; it is saved to the user's own Journal | **"Save to Journal"** |
| Completion record → Challenge details (`camera_providers.dart` → `challenge_detail_screen.dart`) | The stored reason, shown under **"Verification"**: "Honor-system approved — AI verification is a premium feature." or "Auto-approved — AI verification not configured." | AI verification as a premium feature | New completions store **"Completed on the honor system with your photo."** (no `aiLocked` key). The detail row is now **"Completion"**, and **legacy completions without an AI score also show the new line**, so the old wording never displays again. A completion an older app version actually checked with AI (it has a confidence score) keeps its stored explanation. |
| Journal badge (`adventure_memory_model.dart`) | **"🤖 AI Verified"** on entries an older app version checked with AI | That AI verification is a current feature | **"✓ Verified"**: still true for those entries, without advertising AI |
| `lib/widgets/ai_feature_locked_card.dart` | "AI Verification — Coming Soon" card | — | **Deleted.** It had no callers (a backup is in the scratchpad). |
| Privacy policy (`privacy_copy.dart`) | "Your photos are not sent to any AI service: AI photo verification is turned off, and challenges use the honor system." | True of this build | Kept; it is the one allowed match in the regression scan |
| `STORE_LISTING.md` line 133 | "No AI service receives photos (AI verification is disabled)." | True of this build | Kept |
| Dormant failure screen ("Verification Failed", "Retry Verification", "Submit Anyway") | Only reachable with an AI verdict, which can't occur | — | Unchanged; unreachable while AI is off |
| "We couldn't verify your photo right now." (`app_exception.dart`, `challenge_verification_service.dart`) | Only on the dormant server-verifier path | — | Unchanged |

**Unchanged on purpose:** caption prompts (`captionPrompt`, the ✨ prompt box) are fixed seed text, not AI. Code comments mentioning Gemini describe removed code; they are not user-visible.

## 2. AI stays disabled (verified this phase)

- **Client:** no Gemini key or SDK in `lib/`. Every completion is honor-system (`honorSystemVerificationResult`).
- **Server:** the deploy manifest has one endpoint, `deleteAccount`, and declares no params. `aiVerification.ts` isn't exported (7E/7F; rechecked by `entryPoint.test.ts` in this run).
- **Web bundle:** the scan in the final report shows no Gemini or `generativelanguage` reference.

## 3. Regression tests added

- `test/core/ai_copy_regression_test.dart` (9 tests):
  - scans every string literal in `lib/` for the phrases above (one allow-listed sentence, the privacy statement);
  - a self-check that the scanner really matches the old banner;
  - checks that the deleted card stays deleted;
  - checks the caption-step status line and button;
  - checks what Challenge details shows for new, legacy-premium, legacy-unconfigured and older AI-checked completions;
  - checks what a new completion writes.
- `test/providers/camera_providers_test.dart`: the honor-system result has no `aiLocked`, no premium, "coming soon" or verification wording, and only rule-accepted keys. It replaces the old tests that required the premium wording.
- `test/models/adventure_memory_model_test.dart`: the legacy badge reads "✓ Verified".

## 4. Disclosure item for the owner (not a UI fix)

The original audit (`TOUCHGRASS_AUDIT_REPORT.md` line 286) and the archived live bundle both show the **live** web app can send photos to Google Gemini for verification. The bundle contains the Gemini endpoint and inline image payloads; the free tier showed the "premium feature" message instead.
- Whether any user's photo was actually sent depends on tiers and on whether the old key still works (owner-reported revoked, X-1).
- Whether past AI processing must be disclosed is a **legal/owner decision** (D20 in `PHASE_7G_RELEASE_READINESS.md`).

**Publication** of the privacy policy, Terms or store listing needs separate approval (AC-10).
