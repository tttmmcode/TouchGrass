# Phase 7A — Privacy & Disclosure Draft (NOT PUBLISHED)

**Status:** this is a draft for the owner. Nothing here has been published, submitted or changed in a store.
- Statements are drawn from the code and from read-only checks of the live project (2026-10-19).
- Anything that couldn't be verified is marked **[OWNER]**.
- Retention periods and legal terms set by providers are not stated as fact.

## 1. Material mismatches to fix before publishing

| # | What the app or policy says | What is actually true | Fix |
|---|---|---|---|
| M-1 | In-app policy: "Your challenge photos, which only you can see." | **False in production today.** The live Storage rules let any signed-in user read and list every user's completion photos (proved on the emulator with the exported live ruleset). | Deploy S-1 (interim Storage rules) before publishing. Consider whether this past exposure needs notifying under the laws that apply to you **[OWNER / legal]**. |
| M-2 | Policy and Settings: "Delete Account permanently deletes your account and everything saved with it." | The `deleteAccount` function **is not deployed**, so the current app's deletion fails with "isn't available right now". The live web app is older and runs an outdated client-side deletion that the rules partly block. | Deploy F-1 and run the §8 test before the store listing claims in-app deletion. |
| M-3 | "Photos saved with earlier versions may contain location details." (accurate) | Historical photos may carry GPS EXIF. Combined with M-1, anyone signed in could read them. | S-1 now; inventory (§7) and, if approved, the lossless strip. |
| M-4 | Not mentioned | Deleting an account doesn't revoke the user's **Sign in with Apple** tokens. | Implement revocation, or disclose it. Apple may require it **[OWNER verify]**. |
| M-5 | Not mentioned | Font files are fetched from Google at runtime (`google_fonts`, no bundled fonts), so the device's IP address reaches Google. | Disclose, or bundle the fonts. |
| M-6 | "Approximate location (about 1 km) is sent to Open-Meteo." | Accurate: coordinates are rounded to 2 decimals (`coarseCoordinate`), about 1.1 km. | Keep. |

## 2. Data-handling inventory

**Columns:**
- **Linked** means stored with, or keyed by, the user's account ID.
- **Shared** means sent to a party other than Google Firebase, which acts as the processor.

| Data | Purpose | Optional? | Linked? | Shared with | Who can see it | User control / deletion | After account deletion |
|---|---|---|---|---|---|---|---|
| Email address | Sign-in, account | Required (email/Google; Apple may relay) | Yes | — | Owner only (`users/{uid}`, private) | Delete account | Deleted (Firestore doc + Auth user) |
| Display name, username | Profile, leaderboard | Required (defaults exist) | Yes | — | All signed-in users if "Show on Leaderboard" is on | Edit; toggle leaderboard; delete account | Deleted (user doc, `usernames`, `leaderboard_public`) |
| Profile photo | Profile, leaderboard | Optional | Yes | — | All signed-in users (leaderboard; `user_avatars/` readable when signed in) | Change; delete account | Deleted (`user_avatars/{uid}.png`) |
| Google profile-photo URL | Default avatar for Google sign-in | Automatic for Google users | Yes | Viewers' devices load it from Google | Leaderboard viewers | Change photo | Deleted (field in user doc) |
| Challenge photos | Complete challenges; Journal | Required to complete a challenge | Yes | — | **Owner only after S-1** (see M-1) | Delete account (no per-photo delete) | Deleted (`completion_photos/{uid}/`, plus any `metadata_backup/completion_photos/{uid}/`) |
| Completions, Journal, captions, XP, streaks, achievements | Core game | Required | Yes | — | Owner only (aggregates XP, streak and league on the leaderboard) | Delete account; captions editable | Deleted |
| Precise location of a completion, place name, weather | Journal map pins | **Optional** ("Save location with adventures", default on) | Yes | Device geocoder (Apple/Google) for place names | Owner only | Toggle off; "Remove saved locations"; delete account | Deleted |
| Approximate location (~1.1 km) | Local weather | Optional (same toggle) | No (not stored) | **Open-Meteo** (third party) **[OWNER: check Open-Meteo's terms and retention]** | — | Toggle off | Not stored by TouchGrass |
| Device location for "you are here" on the map | Map display | Optional (OS permission) | No | Google Maps SDK / Maps JS loads map tiles **[OWNER: Google Maps terms]** | Stays on device (plus tile requests) | OS permission | — |
| Feedback / bug reports (message, type, app version) | Support | Optional | Yes | — | Developer (console) | Delete account | Deleted (`feedback` where `userId`) |
| Push token (FCM) and topic subscriptions | Notifications | Optional (permission) | Yes (`users/{uid}.fcmToken`) | — | Developer systems | Turn off notifications; delete account | Token deleted with the user doc. **[OWNER]** Topic subscriptions on the device end when the app is removed. |
| Analytics events, app-instance ID, user ID, device and app info | Product analytics (Firebase/Google Analytics) | **Not optional in the app today** (no opt-out toggle) **[OWNER: decide]** | Yes: user ID set to the uid; cleared on sign-out and deletion | Google Analytics | Developer | — | **Kept** for the Analytics data-retention period you configured **[OWNER: GA4 → Admin → Data retention; 2 or 14 months]**. The device's analytics ID is reset after deletion. Earlier events can be deleted with GA4's user-deletion tool **[OWNER]**. |
| Approximate location derived from IP by Analytics | Analytics geography | Automatic | Yes (via app instance) | Google Analytics | Developer | — | Same as above **[OWNER: whether to declare it as "approximate location" in Data safety]** |
| Crash reports (stack traces, device state, uid as user identifier) | Stability | Automatic in release builds | Yes (uid) | Firebase Crashlytics | Developer | — | **Kept** for Crashlytics' retention period **[OWNER: confirm in Firebase documentation]** |
| Performance traces (network request timings, custom traces) | Performance | Automatic | Not by uid **[OWNER verify]** | Firebase Performance Monitoring | Developer | — | Kept for Performance Monitoring's retention period **[OWNER]**. **[OWNER verify]** whether request URLs (such as the weather call's coordinates) are recorded with query parameters. |
| Auth records (provider IDs, sign-in timestamps) | Authentication | Required | Yes | Google / Apple sign-in providers | — | Delete account | Auth user deleted; refresh tokens revoked first |
| Server logs of deletion (uid and counts) | Operating `deleteAccount` | Automatic | Yes (uid) | Google Cloud Logging | Developer | — | Kept for the log bucket's retention **[OWNER: Cloud Logging `_Default` retention]** |
| Font downloads | UI fonts | Automatic | No | Google Fonts (IP address) | — | — | — |

**Server-side retention facts** (verified read-only, 2026-10-19):
- Firestore `(default)` has **no backup schedules**, **point-in-time recovery off**, and a version retention of 1 hour. Deleted documents are therefore not recoverable from backups.
- **[OWNER]** Cloud Storage soft-delete: check the bucket's soft-delete policy with `gcloud storage buckets describe gs://touchgrass-today.firebasestorage.app`. If enabled, deleted photos are recoverable for that window.

## 3. Proposed in-app wording

The current wording is in `lib/core/constants/privacy_copy.dart` and `account_deletion_service.dart`. Proposed changes are marked; the rest is already in the app.

1. **Delete-account confirmation** (in the app as `PrivacyCopy.deleteAccountWarning`; keep):
   > This permanently deletes your account and everything saved with it — your profile, XP and streak, challenge history, Journal entries and photos. This cannot be undone.

   Proposed addition for the second line of the dialog:
   > Usage analytics and crash reports already sent to Firebase aren't part of your account and are kept for a limited time.
2. **Success** (proposed; today the app just returns to sign-in):
   > Your account and its data have been deleted.
3. **Failure** (in the app; Phase 7A made the network case honest):
   - Couldn't finish: "We couldn't finish deleting your account. Please try again — anything already removed stays removed. If this keeps happening, email support@touchgrass.app."
   - Lost connection or timeout: "We couldn't confirm that your account was deleted because the connection was interrupted. Please check your connection and try again — retrying is safe and finishes anything left."
   - Stale sign-in: "For your security, please sign in again, then delete your account."
   - Function missing: "Account deletion isn't available right now, so your account was not deleted. Please try again later or email support@touchgrass.app."

   **[OWNER]** Confirm that `support@touchgrass.app` exists and is monitored.

## 4. Proposed privacy-policy section: "Deleting your account"

> You can delete your account at any time in the app: **Settings → Delete Account**. For your security we ask you to sign in again first. Deletion permanently removes your profile (email address, display name, username and profile photo), your username reservation, your XP, streaks and achievements, all your challenge completions, Journal entries and captions, any saved locations, all your challenge photos, your leaderboard entry and the feedback you sent. It also signs you out on your other devices.
>
> Some information is not part of your account and is not removed by this: usage analytics, crash reports and performance data already sent to Google Firebase are kept for the retention period configured for TouchGrass [OWNER: insert periods], and server logs recording that a deletion happened are kept for [OWNER: insert period]. Photos you completed with earlier app versions are deleted with your account like all other photos.
>
> If you can't use the app, you can request deletion at [OWNER: web link or email, see §6]. We will delete your account within [OWNER: period] and confirm by email.

**[OWNER / legal]:**
- the controller's name and contact details;
- the legal bases, if GDPR applies;
- the children's age policy;
- international transfers (Firestore location `nam5`, United States);
- the policy's effective date.

## 5. Store disclosures (checklists; fill in after resolving [OWNER] items)

### Google Play — Data safety

| Data type (Play category) | Collected | Shared | Optional | Purpose |
|---|---|---|---|---|
| Personal info → Email address | Yes | No | No | Account management, app functionality |
| Personal info → Name (display name/username) | Yes | No | No | App functionality |
| Personal info → User IDs | Yes | No* | No | Account management, analytics |
| Photos and videos → Photos | Yes | No | No | App functionality |
| Location → Precise location | Yes | No | **Yes** | App functionality |
| Location → Approximate location | Yes (weather; possibly via Analytics IP) | **Yes, Open-Meteo** [OWNER: Play's "shared" definition and service-provider exemption] | Yes | App functionality, analytics |
| App activity → App interactions | Yes | No* | No | Analytics |
| App info and performance → Crash logs, Diagnostics | Yes | No* | No | Analytics, app functionality |
| Device or other IDs | Yes (app-instance ID, FCM token) | No* | No | Analytics, app functionality |
| Messages → Other in-app messages (feedback) | Yes | No | Yes | App functionality |

\* Firebase acts as a service provider. Check Play's current guidance on whether that counts as "sharing" **[OWNER]**.

Also:
- **Encrypted in transit:** Yes (HTTPS).
- **Deletion:** users can request deletion. Provide the in-app path, **and** the web link Play requires for account deletion (§6).

### Apple — App Privacy

| Data type | Linked to user | Used for tracking | Purposes |
|---|---|---|---|
| Contact info → Email address | Yes | No | App functionality |
| User content → Photos | Yes | No | App functionality |
| User content → Other (Journal captions, feedback) | Yes | No | App functionality, customer support |
| Location → Precise | Yes (optional) | No | App functionality |
| Location → Coarse | No (weather; not stored) | No | App functionality |
| Identifiers → User ID | Yes | No | App functionality, analytics |
| Usage data → Product interaction | Yes | No | Analytics |
| Diagnostics → Crash data, performance data | Yes (crash data via uid) | No | App functionality |

- **[OWNER]** Tracking: the app has no advertising SDKs and does no cross-app tracking. Confirm Analytics is not linked to advertising (no Google Signals or ads personalization). Otherwise App Tracking Transparency applies.
- **[OWNER verify]** Sign in with Apple token revocation on deletion (M-4).

## 6. Store account-deletion requirements **[OWNER verify against current store rules]**

- **Google Play:** in-app deletion exists. Play also asks for a **web link** where users can request deletion without reinstalling. Options:
  1. after H-1 and F-1, the web app's Settings → Delete account at `https://touchgrass.web.app` (requires sign-in);
  2. a simple page on your site describing the in-app path plus an email request route.
- **Apple:** apps that let users create accounts must let them start deletion in the app. TouchGrass does (Settings → Delete Account); it works once F-1 is deployed. See M-4 about Apple token revocation.

## 7. Open questions for the owner

1. Is the past photo exposure (M-1) notifiable where you operate? **[legal]**
2. What are the GA4 data retention setting and the Crashlytics / Performance retention you'll state?
3. Should analytics have an opt-out toggle, or ask for consent first (for example in the EU/UK)?
4. What is the support email, and what is the published policy URL? Neither could be verified (`support@touchgrass.app` appears in the app).
5. Is there an age requirement or children's policy?
6. Will Sign in with Apple token revocation be implemented (M-4)?
7. Is Cloud Storage soft-delete enabled on the bucket, and for how long?
