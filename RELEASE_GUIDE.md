# TouchGrass Release Guide

Step-by-step checklist for getting to App Store and Play Store.

---

## PART 1 — BEFORE YOU BUILD

### 1. Fix Firebase bundle IDs

The Firebase project was configured with `com.example.touchgrass`. You must update it:

**Android — currently a real, live mismatch, not just a future step:**
`android/app/build.gradle.kts`'s `applicationId` is already `com.touchgrass.app` ✅, but
`android/app/google-services.json`'s `package_name` still says `com.example.touchgrass` — these
two values do not match *today*. This is not just cosmetic: Firebase/Google Sign-In package-name
validation can reject the mismatch at runtime on Android release builds. Fix:
- In Firebase Console → Project Settings → Your Apps → Android app
  - Add a new Android app with package name `com.touchgrass.app`
  - Download the new `google-services.json` → replace `android/app/google-services.json`

**iOS:**
- In Xcode → Runner target → General → Bundle Identifier
  - Change from `com.example.touchgrass` to `com.touchgrass.app`
- In Firebase Console → Project Settings → Your Apps → iOS app
  - Add a new iOS app with Bundle ID `com.touchgrass.app`
  - Download the new `GoogleService-Info.plist` → replace `ios/Runner/GoogleService-Info.plist`
- Re-run: `dart run flutterfire_cli:flutterfire configure`

### 2. Restrict the Google Maps API key

1. Go to: [Google Cloud Console](https://console.cloud.google.com) → APIs & Services → Credentials
2. Find the Maps API key currently in `android/local.properties`
3. Click Edit → Application restrictions → Android apps
4. Add: `com.touchgrass.app` + your release SHA-1 fingerprint
5. For iOS, create a separate key restricted to iOS + your Bundle ID

### 3. App Icon Artwork

Place files at:
- `assets/icon/icon.png` — 1024×1024 px, no transparency, brand content in center 66%
- `assets/icon/icon_foreground.png` — 1024×1024 px transparent background, icon in safe zone

Then run:
```bash
flutter pub get
dart run flutter_launcher_icons
```

This generates all icon sizes for both platforms automatically.

### 4. Cloud Functions & secrets (Gemini, VAPID)

Not required to ship the app as-is (the client-side Gemini flow still works without these), but
required to close KNOWN_BUGS.md B1/B2 (server-authoritative AI verification) and B4 (web push):

- **Gemini server-side verification** — `functions/src/index.ts` is written and compiles, but is
  not deployed. Full deploy/cutover sequence (Blaze billing → secret → deploy → client cutover →
  rules tightening, in that exact order) is in `functions/README.md` — do not skip ahead in that
  order, it's sequenced deliberately.
- **Web push VAPID key** — Firebase Console → Project Settings → Cloud Messaging → Web Push
  certificates → generate one, then build web with `--dart-define=FCM_VAPID_KEY=<key>`. No other
  code change needed — `NotificationService.getToken()` already picks it up
  (`lib/services/notification_service.dart`).

---

## PART 2 — ANDROID RELEASE SIGNING

### Generate a keystore

```bash
keytool -genkey -v \
  -keystore ~/touchgrass-release.jks \
  -alias touchgrass \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000
```

**⚠️ CRITICAL: Back up the .jks file securely. If you lose it, you cannot update your app.**

### Create key.properties (never commit this file)

Create `android/key.properties`:
```
storePassword=<your store password>
keyPassword=<your key password>
keyAlias=touchgrass
storeFile=<absolute path to touchgrass-release.jks>
```

### Build a signed release APK/AAB

```bash
# App Bundle (required for Play Store)
flutter build appbundle --release

# APK (for direct install testing)
flutter build apk --release
```

---

## PART 3 — IOS RELEASE SIGNING

1. In Xcode → Runner target → Signing & Capabilities
   - Team: Select your Apple Developer account
   - Bundle Identifier: `com.touchgrass.app`
   - Signing Certificate: iOS Distribution
2. Create an App ID in [developer.apple.com](https://developer.apple.com):
   - Identifier: `com.touchgrass.app`
   - Enable: Push Notifications, Sign In with Apple
3. Archive in Xcode: Product → Archive → Distribute App → App Store Connect

---

## PART 4 — PRIVACY POLICY & SUPPORT URLS

You must host these pages before App Store review:

**Minimum privacy policy must state:**
- What data is collected (email, photos, location, usage analytics)
- How it's used (account management, map display, app improvement)
- Firebase/Google as data processor
- How users can delete their data (in-app Settings → Account → Delete Account)
- Contact email

**Suggested hosting:** GitHub Pages, Notion public page, or a simple HTML file on any host.

URLs to register:
- Privacy Policy: `https://touchgrass.app/privacy`
- Support / Contact: `https://touchgrass.app/support`

---

## PART 5 — TESTFLIGHT (iOS)

1. Upload build via Xcode Archive (see Part 3)
2. In App Store Connect → TestFlight → Add testers
3. Internal testing: up to 100 Apple developer account users (instant)
4. External testing: up to 10,000 users (requires Beta App Review, ~1 day)
5. Minimum 25 external testers recommended before release
6. Collect feedback via TestFlight's built-in feedback tool

---

## PART 6 — GOOGLE CLOSED TESTING (Android)

1. In Google Play Console → Testing → Closed testing → Create track
2. Upload the signed `.aab` from Part 2
3. Add testers by email list or Google Group
4. Play Console requires at least 20 testers for 14 days before open testing

---

## PART 7 — APP STORE CONNECT SUBMISSION

1. Create app in App Store Connect:
   - Name: TouchGrass
   - Primary language: English
   - Bundle ID: `com.touchgrass.app`
   - SKU: `touchgrass-ios-v1`
2. Fill in metadata from `STORE_LISTING.md`
3. Upload screenshots (see screenshot specs in STORE_LISTING.md)
4. Set pricing: Free
5. Set age rating: 4+
6. Submit for review (typical: 1–3 days)

---

## PART 8 — PLAY STORE SUBMISSION

1. Create app in Google Play Console
2. Complete the Data Safety form (use the table in STORE_LISTING.md)
3. Fill in store listing from `STORE_LISTING.md`
4. Upload signed `.aab`
5. Set content rating: Everyone
6. Set pricing: Free
7. Publish to closed testing first → open testing → production

---

## FINAL CHECKLIST

- [ ] Bundle IDs updated to `com.touchgrass.app` (Android + iOS + Firebase)
- [ ] New `google-services.json` downloaded (fixes the live Android package-name mismatch, see Part 1)
- [ ] New `GoogleService-Info.plist` downloaded (iOS has none checked in at all yet)
- [ ] Maps API key restricted to `com.touchgrass.app` + SHA-1
- [ ] Cloud Function deployed and client cut over, or explicitly deferred (see functions/README.md)
- [ ] FCM VAPID key generated and passed at web build time, or explicitly deferred (KNOWN_BUGS.md B4)
- [ ] App icon artwork placed and `dart run flutter_launcher_icons` run
- [ ] `key.properties` created with real keystore credentials
- [ ] `key.properties` and `*.jks` in `.gitignore` ✅ (already done)
- [ ] Privacy Policy URL live and accessible
- [ ] Support URL live and accessible
- [ ] App Store listing copy ready (see STORE_LISTING.md)
- [ ] Screenshots captured (8 per device type)
- [ ] Feature graphic created (Android, 1024×500 px)
- [ ] TestFlight external testing run with 25+ testers
- [ ] Google Closed Testing run with 20+ testers
- [ ] No crashes in 7-day production-equivalent build
- [ ] `dart analyze` → No issues ✅
