# AI photo verification — future server-side design (deferred)

**Status (2026-10-17): not implemented and not enabled.** AI photo verification stays off on every tier, and every completion uses the honor system. Building or enabling anything here needs separate owner approval. This document records the intended design so that approval can be given with the costs and risks known.

## What exists today
- **Client:** no Gemini key, SDK or endpoint (removed in Phase 1, D-06). Every web build is scanned for secrets (`tool/check_web_bundle_secrets.mjs`); the Phase 3 build is clean.
- **Server:** `functions/src/index.ts` → `verifyChallengeCompletion` (callable, `us-central1`, Gemini secret `GEMINI_API_KEY`, model `gemini-2.5-flash`). It is **not deployed** ("No functions found", 2026-10-17). Its per-tier quota table is in `functions/src/rewards.ts` (`free` 0, `premium` 30 per month, `admin_test` unlimited).
- **Key:** the owner reports that the old exposed key was revoked on 2026-10-17 (not independently verified). No new key is stored anywhere in the repo or in Secret Manager.

## Gaps to close before enabling
The undeployed function predates Phases 2 and 3. Before any deploy it must:
1. **Write the Journal entry in the same transaction** as the completion and reward (D-13). Today it writes a completion without a Journal entry.
2. **Use the fixed photo path** `completion_photos/{uid}/{yyyy-MM-dd}.jpg`, and store the same download URL the client uses. Today it stores the raw storage path as `photoUrl`.
3. **Respect `settings.locationEnabled`** (D-09) for any location it records.
4. **Use the user's local day** and the D-01 `lastCompletionDate` logic (D-15). Phase 2 started on this.

## Architecture
1. The client uploads the photo to its fixed path (the same as today).
2. The client calls `verifyChallengeCompletion({challengeId, storagePath})` with an **App Check** token.
3. The function:
   - checks Auth, App Check, ownership of the storage path, and the date;
   - checks entitlement and the quota (a transaction on `users/{uid}/aiUsage/{period}`);
   - **sniffs the MIME type** of the stored bytes;
   - calls Gemini with the photo and the challenge's success criteria.
4. **If the photo matches:** in one transaction, write the completion, the reward and the Journal entry. Return the committed result.
5. **If it doesn't match, or Gemini fails:** return a verdict. The client offers the honor-system path, which records `overrideUsed`.
6. The client never sees the key or calls Gemini directly.

## App Check
- Enforce on the callable (`enforceAppCheck: true`).
- Providers:
  - **Android:** Play Integrity.
  - **iOS:** App Attest, with DeviceCheck as fallback.
  - **Web:** reCAPTCHA Enterprise.
- Roll out in monitoring mode first, then enforce.
- Provider quotas and costs to confirm at setup:
  - Play Integrity standard requests have a daily free allowance.
  - reCAPTCHA Enterprise has a monthly free tier, and billing beyond it.
- Needs the apps registered under their final IDs (X-5) and console access (owner).

## Authorization and abuse protection
- **Authentication:** Firebase Auth required. The path must be under the caller's own folder; the challenge must be the caller's own and dated within ±1 day.
- **Entitlement:** tier read from the profile's `entitlementTier`, which clients can't change (rules, D-07).
- **Quota:**
  - per user per month, in a server-only collection (`aiUsage`, client writes denied);
  - incremented in the same transaction as the call record, so concurrent calls can't exceed it;
  - a project-wide daily ceiling as a circuit breaker.
- **Resource limits:** `maxInstances`, a 60 s timeout, and a photo size cap (10 MB, matching the Storage rules).
- **Retries:** one Gemini call per completion ID. A retry returns the stored verdict instead of calling Gemini again.

## Privacy implications
- Photos would be sent to Google (Gemini API), a new processor. Before enabling:
  - update the privacy policy (`PrivacyCopy.privacyPolicyText`, which says photos are not sent to any AI service);
  - update the store Data Safety and privacy labels (X-11).
- **Use the paid tier only.** Google's Gemini API terms allow free-tier prompts to be used to improve Google's products; user photos must not go there. Confirm the current terms at the time.
- Don't store Gemini's raw response. Keep only a verdict, a reason and a confidence score.
- Location is never sent to Gemini.

## Expected billing (estimate, not a quote)
- **Rates:** Gemini API pricing page, read 2026-10-17. `gemini-2.5-flash` paid tier: **$0.30 per 1M input tokens** (images included) and **$2.50 per 1M output tokens**, with thinking tokens counted as output.
- **Per verification** (assumed: ~2,000 input tokens for a phone photo plus prompt, up to ~1,000 output tokens):
  - input: 2,000 × $0.30 / 1M ≈ $0.0006;
  - output: 1,000 × $2.50 / 1M ≈ $0.0025;
  - total ≈ **$0.003**.
- **Per premium user:** 30 verifications a month ≈ **$0.09 a month** at most.
- **At scale:** 1,000 premium users using every verification ≈ **$90 a month**.
- **Cloud Functions, Firestore and Storage:** small next to Gemini, within the Blaze free allowances at that scale.
- **Secret Manager:** a few cents a month at most for one key.
- **Recommended:** a billing budget alert, and a Gemini API key restricted to the Generative Language API.

## Approval needed before any of this
1. Product: which tiers get AI verification, and the quotas.
2. A new Gemini key created by the owner, stored only via `firebase functions:secrets:set GEMINI_API_KEY`.
3. App Check registration (needs X-5).
4. The privacy policy and store disclosure changes above.
5. A deploy plan, like the `deleteAccount` checklist.
