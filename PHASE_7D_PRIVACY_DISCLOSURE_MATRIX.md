# Phase 7D — Privacy & Feature Disclosure Matrix

**Scope:** every material user-facing claim about photos, location, deletion, visibility and AI. Sources:
- in-app copy (`lib/…`);
- `STORE_LISTING.md`;
- the 7A privacy draft (`PHASE_7A_PRIVACY_DISCLOSURE_DRAFT.md`, unchanged).

Local drafts and UI text were corrected where the truth is clear. **Nothing was published.** Regression tests in `test/core/privacy_copy_test.dart` (group "no false privacy or AI claims") fail if the false claims return.

**Ready?:**
- **Yes**: the statement is true of what is live or of the build it ships in.
- **After X**: it becomes true only after operation X.
- **Owner**: needs an owner fact or decision.

| # | Where | Previous statement | Actual implementation (verified) | Technical fix needed | Wording now (local) | Ready? |
|---|---|---|---|---|---|---|
| D1 | In-app privacy policy (`privacy_copy.dart`) | "Your challenge photos, which only you can see." | **Live since S-1 (04:30Z on 2026-10-20):** other users can't list or open them through Firebase. Every photo still has a bearer link; links harvested before S-1 work until rotation (AC-4). | Token rotation (AC-2…AC-4). Later, Option B (no persistent links). | "Other TouchGrass users can't browse or open them in the app. Each photo is shown through a private web link, so anyone you share a photo's link with can see that photo." | **After AC-4** (until then, harvested links contradict the first sentence) |
| D2 | In-app policy | Profile photo "shown on the leaderboard" | The avatar link is in `leaderboard_public`, readable by every signed-in user; the link works for anyone holding it | None (by design) or C4 | Added: "Your profile photo is shown to other signed-in users, and anyone they share its link with can see it." | Yes |
| D3 | In-app policy + Delete Account dialog | "…deletes your account and **everything** saved with it" | `deleteAccount` deletes all user data (incl. backups, a second Storage sweep). **Not deployed:** the live app's deletion fails at Firestore (`PHASE_7D_ACCOUNT_DELETION_REMEDIATION.md` §1). Analytics, crash data, a deletion log line and the soft-delete window persist. | F-1 + H-1 + the two-account test | "…deletes your account and **the data** saved with it: [list]". The policy keeps "Usage analytics and crash reports already sent to Firebase are kept…". | **After F-1 + H-1 + test.** Retention periods: Owner. |
| D4 | Onboarding | "snap a photo, and our AI will verify your completion" | AI verification is disabled on every tier (D-06); honor system | None (keep AI off) | "snap a photo, and add it to your Journal." | Yes |
| D5 | Terms of Service (Settings) | "Challenge photos you submit may be used to improve AI verification." | No photo is sent to any AI service or used for training | None | "Challenge photos you submit are stored to show in your Journal. They are not used to train or improve AI…" | Yes (legal review: Owner) |
| D6 | Challenge details | Label "AI Verdict" over the honor-system reason | No AI ran | None | Label "Verification" | Yes |
| D7 | Journal badge | Entries without `verificationMethod` defaulted to "🤖 AI Verified" | Unknown method; no AI | Model default → `auto_approved` | "✓ Auto-Approved" | Yes (Flutter test) |
| D8 | Camera permission / Help | "camera access to **verify** your outdoor adventures"; "take a photo … to verify it" | Photos aren't verified | None | "…to **photograph** your outdoor adventures"; "…to **complete** it" | Yes |
| D9 | In-app policy | "Your photos are not sent to any AI service: AI photo verification is turned off" | True: the client has no AI key, and the server verifier isn't deployed | — | unchanged | Yes |
| D10 | Remove-locations dialog | "photos saved with earlier versions … may still contain location details" | True: historical GPS is unremediated (M-1…M-5) | Historical remediation | unchanged | Yes (update after M-5) |
| D11 | In-app policy | Location saved "only if 'Save location with adventures' is on" | True for Firestore fields. **Historical photo files** may embed GPS regardless; new uploads are stripped (incl. appended data, 7C). | Historical remediation | unchanged; flagged | **After M-5** (or add a caveat sentence: Owner) |
| D12 | `STORE_LISTING.md` description | "let AI verify your adventure"; "AI Photo Verification — Gemini Vision…"; "AI verifies it instantly" | AI disabled | None | "add it to your Journal"; "Photo Journal — …"; "Save it to your Journal" | Yes (not submitted) |
| D13 | `STORE_LISTING.md` release notes | "Daily outdoor challenges powered by AI"; "Photo verification with Gemini Vision" | Challenges come from the built-in seed library (`aiGenerated: false`); AI disabled | None | "A new outdoor challenge every day"; "A photo Journal of your adventures" | Yes |
| D14 | `STORE_LISTING.md` data safety | Photos purpose "Challenge verification photos"; deletion "Settings → Account → Delete Account" | Journal and avatar photos; deletion not deployed | F-1 | Purpose corrected; deletion marked as a **release gate**; photo-link and avatar visibility stated | **After F-1** for the deletion line |
| D15 | `STORE_LISTING.md` | "alongside thousands of other explorers" | Unverified user count (marketing) | — | unchanged | **Owner** (substantiate or remove) |
| D16 | 7A privacy draft | Retention periods for analytics, crash, logs, soft delete | Placeholders | — | unchanged | **Owner** |
| D17 | Anywhere | Notice of the past exposure (photos readable by any signed-in user until 2026-10-20) | Fact, from the live rules exports | — | none | **Owner / legal** (whether notification is required) |

**Not changed** (outside scope or already accurate):
- the in-app weather and location explanations (accurate, D-09);
- the `ai_feature_locked_card.dart` text ("being upgraded"), which promises nothing it doesn't deliver.
