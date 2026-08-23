TouchGrass Documentation
TouchGrass is a cross-platform mobile and web app that turns going outside into a daily habit, using AI-verified photo challenges, XP, streaks, and a bit of friendly competition. This page covers what it is, who it's for, and everything needed to install, configure, run, and extend it.

Try at touchgrass.web.app

GitHub Repository: https://github.com/tttmmcode/TouchGrass

Demo Video: https://www.youtube.com/watch?v=zFVLTNaPELM 

01
Purpose
Most people spend the majority of their day on a screen, even though brief, regular time outdoors has measurable benefits for mood, focus, sleep, and cardiovascular health. The gap isn't awareness. It's habit: there's no daily nudge or reward loop pulling someone off the couch the way a screen pulls them in.
TouchGrass closes that gap by applying game mechanics, daily challenges, XP, streaks, leagues, and achievements to the single behavior of stepping outside. Each day the app assigns one challenge, such as finding something red in nature or sitting outside for five minutes without a phone. The user completes it, photographs proof, and an AI vision model verifies the photo actually matches the challenge before rewarding XP. The result is logged permanently as a journal entry and a pin on a personal map, so the habit compounds into a visible record of time spent outdoors.
02
Target audience
Screen-time reducers
People who want to spend less time on their phone and more time outside, but need structure to make it a habit rather than an occasional intention.
Streak-driven habit builders
Users who respond well to daily quests, XP, and streak mechanics,-the same hooks as habit-tracking and gamified fitness apps- redirected toward outdoor time.
Casual competitors
Players who enjoy leaderboards and league promotion without the pressure or intensity of a hardcore fitness app.
Memory keepers
Anyone building a personal record of outdoor time. The map and journal double as a lightweight, location-tagged diary.
The app is free to use, requires no special equipment, and is designed for a single sitting of five to forty minutes per day depending on the challenge's difficulty.
03
Main features
Feature
Description
Daily challenges
One new challenge per day per user, across categories like nature, mindfulness, and exploration, at three difficulty tiers (Easy / Medium / Hard), each with its own XP reward and time estimate.
AI photo verification
The user photographs proof of completion. Google's Gemini vision model checks the photo against the challenge's description and success criteria before the completion is accepted.
XP & levels
Every verified completion awards XP. Level is a deterministic function of total XP.
Leagues
Eight XP-tier leagues that a user's total XP places them into, shown below.
Streaks & Rainy Days
Consecutive daily completions build a streak. Rainy Days are a limited, earnable grace mechanic that protects a streak through a missed day.
Weekly leaderboard
A per-league leaderboard ranked by XP earned since the last Monday-midnight UTC reset, reading from a privacy-safe public mirror rather than full user documents.
Achievements
Badge unlocks for milestones: streak length, total completions, category variety, and more.
Adventure map & journal
Every completion is saved with its photo, caption, and optional location, viewable as pins on a map or as a chronological journal.
Companion
A woodland mascot that reacts to completions and streak milestones.
Entitlement tiers planned
Data model and gating scaffolding for a future free/premium split. Not monetized yet; see Known limitations.
Accounts
Email/password, Google Sign-In, and Sign in with Apple (mobile only).
Notifications
Push notification plumbing for daily-challenge reminders, streak warnings, and achievement unlocks. Mobile is fully wired; web needs an additional key, see Configuration.

The eight leagues
Seedling · 0+
Sprout · 300+
Wildflower · 700+
Forest · 1,500+
Mountain · 3,000+
Summit · 6,000+
Sky Trail · 10,000+
Aurora · 20,000+
04
Architecture & tech stack
TouchGrass is a single Flutter codebase targeting Android, iOS, and Web from one source tree, backed by Firebase.
Client
Flutter / Dart (SDK ^3.12.1) for UI and application logic across all platforms.
Riverpod for state management. Screens are ConsumerWidget/ConsumerStatefulWidgets reading from providers in lib/providers/.
go_router for declarative, URL-based navigation, also required for correct web deep-linking.
Backend (Firebase project touchgrass-today)
Firebase Authentication, email/password, Google, and Apple sign-in.
Cloud Firestore, the primary database: users, challenges, completions, memories, leaderboard mirror.
Firebase Storage for completion photos and profile avatars.
Cloud Functions (TypeScript, functions/), a written and unit-tested server-side verification function not yet deployed.
Firebase Hosting, serving the web build on two sites: a primary URL and a legacy rollback URL.
Analytics, Crashlytics, Performance, and Cloud Messaging for telemetry, crash reporting, and push notifications.
AI & Integrations
Google Gemini (google_generative_ai), the multimodal vision model that verifies a submitted photo against a challenge's description and success criteria.
Google Maps (google_maps_flutter) renders the Adventure Map.
Geolocator / Geocoding handle device location and reverse-geocoding for tagging memories.
See pubspec.yaml for the exact, versioned dependency list.
05
Project structure
touchgrass/
├── lib/
│   ├── main.dart                # App entry point
│   ├── firebase_options.dart    # Generated Firebase config
│   ├── core/                    # Constants, config, errors, router, utils
│   ├── models/                  # Immutable data models
│   ├── providers/                # Riverpod state & business-logic glue
│   ├── repositories/             # Firebase read/write boundary
│   ├── services/                 # Wrappers around external SDKs
│   ├── features/                 # One folder per user-facing area:
│   │   ├── achievements/  auth/  camera/  challenges/
│   │   ├── companions/  home/  leaderboard/  leagues/
│   │   └── map/  onboarding/  profile/  settings/  streak/
│   ├── companions/               # Companion mascot widget + painter
│   ├── theme/                    # Colors, spacing, typography
│   └── widgets/                  # Shared, reusable widgets
├── test/                         # Mirrors lib/ — unit & widget tests
├── functions/                    # Cloud Functions (TypeScript)
│   └── src/
│       ├── index.ts              # Callable function entry point
│       └── rewards.ts            # Pure, unit-testable reward logic
├── android/ ios/ web/ macos/ windows/ linux/  # Platform projects
├── firestore.rules               # Firestore security rules
├── storage.rules                 # Storage security rules
├── firebase.json                 # Multi-site Hosting, Functions, rules paths
├── .firebaserc                   # Firebase project/target aliases
├── pubspec.yaml                  # Flutter dependencies & app metadata
├── secrets.json                  # Local-only build secrets (gitignored)
├── KNOWN_BUGS.md
├── QA_CHECKLIST.md
├── RELEASE_GUIDE.md
└── STORE_LISTING.md
Layering convention. features/ screens read from providers/, which call repositories/, which call services/ or Firebase SDKs directly for simple cases. Repositories return a typed Result<T> rather than throwing raw Firebase exceptions, so UI code never has to catch SDK-specific error types.
06
Installation & local setup
Prerequisites
Tool
Notes
Flutter SDK
Match environment.sdk: ^3.12.1 in pubspec.yaml. Run flutter doctor after install and resolve anything it flags.
Node.js 20+
Only needed if working on functions/ (Cloud Functions).
Firebase CLI
npm install -g firebase-tools, then firebase login.
Android Studio / Xcode
Only needed for the platform you're building for. Xcode (macOS only) is required for any iOS build.
A Firebase project
This repo is wired to touchgrass-today. To run against your own project instead, see Configuration.

Steps
Clone the repository and enter it:
git clone https://github.com/tttmmcode/TouchGrass.git
cd touchgrass
Install Flutter dependencies:
flutter pub get
Confirm your toolchain is healthy:
flutter doctor
Create secrets.json in the project root (never commit this file). See Configuration for its contents.
Run the app:
flutter run --dart-define-from-file=secrets.json
If you're also working on Cloud Functions:
cd functions
npm install
07
Configuration
TouchGrass takes every secret and environment-specific value through Flutter's --dart-define mechanism. Nothing sensitive is hardcoded in source.
secrets.json
Create this file at the project root. It's already listed in .gitignore.
secrets.json
{
  "GEMINI_API_KEY": "your-gemini-api-key-here"
}
🌱
Works without a key
Get a key from Google AI Studio. Without one, the app still runs, and challenges can still be completed: photo verification silently falls back to an honor-system approval instead of a real AI check. This is intentional. The app should never be unusable just because a key isn't configured.
Pass it at build or run time with --dart-define-from-file=secrets.json, or supply individual keys directly:
flutter run --dart-define=GEMINI_API_KEY=your-key-here
All recognized --dart-define keys
Key
Required
Default
Purpose
GEMINI_API_KEY
No
''
Enables real AI photo verification. Empty means the honor-system fallback applies.
FCM_VAPID_KEY
No
''
Enables web push notifications. Get this from Firebase Console → Project Settings → Cloud Messaging → Web Push certificates. Empty means notifications silently no-op on web; mobile is unaffected.
ENVIRONMENT
No
development
One of development, staging, production. Gates which challenge-verification implementation the app can construct. No production build has shipped from this repo yet.

Firebase project setup
The app is already wired to the touchgrass-today Firebase project via the generated lib/firebase_options.dart and per-platform config files. iOS has no GoogleService-Info.plist checked in yet; see Known limitations.
To point the app at a different Firebase project, such as your own sandbox:
firebase login
flutterfire configure   # regenerates firebase_options.dart and platform config files
Then deploy security rules and Cloud Functions once you have Blaze billing enabled, to your project:
firebase deploy --only firestore: rules, storage
Google Maps API key
The Adventure Map feature needs a Google Maps API key, configured per platform:
Android: android/local.properties (or an environment-injected Gradle property)
iOS: ios/Runner/AppDelegate.swift
Web: embedded once in web/index.html
See RELEASE_GUIDE.md for how to restrict this key by platform and bundle ID before shipping.
08
Running the app
Web (Chrome)
flutter run -d chrome --dart-define-from-file=secrets.json
Android (device or emulator)
flutter run -d android --dart-define-from-file=secrets.json
iOS (device or simulator — macOS only)
flutter run -d ios --dart-define-from-file=secrets.json
Hot reload (r) and hot restart (R) work as usual once the app is running.
09
Testing
Full Flutter test suite
flutter test
Static analysis — must report zero issues before any commit
flutter analyze
Cloud Functions test suite — pure logic, no emulator needed
cd functions
npm test
Tests mirror lib/'s structure: test/providers/camera_providers_test.dart tests lib/providers/camera_providers.dart, and so on. New logic, especially anything touching XP, streak, or entitlement calculations, should ship with a corresponding unit test rather than relying on manual QA alone.
10
Building & deployment
Web
flutter build web --release --dart-define-from-file=secrets.json
firebase deploy --only hosting:main    # primary: touchgrass.web.app
firebase deploy --only hosting: today   # legacy/rollback: touchgrass-today.web.app
Hosting is a multi-site setup: both sites currently serve identical builds from the same Firebase project, with touchgrass.web.app as the primary URL and touchgrass-today.web.app kept live as a rollback target.
Android / iOS
See RELEASE_GUIDE.md for the full, step-by-step signing and store-submission checklist: keystore generation, bundle ID fixes, App Store Connect / Play Console setup, TestFlight and closed testing. In short:
flutter build appbundle --release   # Android, for Play Store
flutter build apk --release         # Android, for direct install/testing
# iOS: archive and distribute via Xcode (Product → Archive)
Cloud Functions not deployed.
Written and unit-tested, but not deployed. See functions/README.md for the exact prerequisites, Blaze billing and secret configuration, and the deliberately sequenced deploy and cutover steps.
11
Data model reference
Primary Firestore collections. See lib/core/constants/app_constants.dart for the authoritative names.
Collection
Purpose
users/{uid}
Full user document: profile, XP, streak, level, league, achievements, and private fields like email. Owner-read-only.
leaderboard_public/{uid}
Safe-to-share mirror of a subset of the user document. Any signed-in user may read this; leaderboard queries read from here, never from users/, so no client can see another user's private fields.
usernames/{username}
Username-uniqueness registry. Doc data is just {uid: <owner>}.
users/{uid}/challenges/{date}
Per-user, per-day assigned challenge.
users/{uid}/memories/{memoryId}
Journal/map entries: photo, caption, location.
users/{uid}/aiUsage/{YYYY-MM}
Server-authoritative AI-verification quota counters. Never client-writable.
completions/{uid_challengeId}
One record per completed challenge. A deterministic ID prevents duplicate completions for the same day.
challenges/{challengeId}
The challenge catalogue. Read-only to clients.
achievements/{achievementId}
The achievement catalogue. Read-only to clients.

Derived values
Computed identically on the client (AppConstants) and cross-checked in Firestore. rules:
Level = floor(xp / 100) + 1
League, see the XP thresholds in Main features
Firebase Storage paths: completion_photos/{uid}/... and user_avatars/{uid}..., both owner-scoped and size-capped at 10MB and 5MB respectively.
12
Security model
Firestore rules enforce per-document ownership, bound how much XP, level, or streak a single client write can legitimately change, a stopgap against direct-API abuse until server-computed rewards via Cloud Functions are live, and keep completions immutable once created.
Storage rules restrict photo uploads to their owning user's own path and enforce size caps.
AI-verification quota is tracked server-side only, in a subcollection no client can write to, so quota can't be reset by reinstalling the app.
Secrets such as the Gemini key and Maps key are never committed to source control; see Configuration.
📋
Living document
This project maintains an honest, continuously updated account of security posture and known gaps in KNOWN_BUGS.md. Worth reading before extending anything security-sensitive.
13
User manual
Getting started
Open the app and create an account with email/password, Google, or Apple.
Complete the brief onboarding flow.
Your first daily challenge is waiting on the Home screen.
Completing a daily challenge
From the Home screen, tap Start Challenge to read the challenge's description and objective.
Go do the activity outside.
Tap the camera button and take a photo that shows you completed it.
Wait a moment while the photo is verified, either a real AI check or, if AI verification isn't configured, an automatic honor-system approval.
If verification fails, choose Retake Photo, Retry Verification on the same photo, or Submit Anyway to log it without AI confirmation.
Write a short caption describing your experience, then submit. You'll see your XP reward, streak update, and any achievements unlocked.
Viewing your history
Map tab: every completion with a location appears as a pin you can tap for details.
Journal tab: a chronological list of every completion, with photo and caption.
Tracking progress
Profile tab, level, XP progress, streak, league, and unlocked achievements.
Leaderboard tab, your league's weekly ranking, resetting every Monday at midnight UTC.
Leagues tab, an overview of all eight leagues and their XP thresholds.
Streak protection
Missing a day breaks your streak unless you have a Rainy Day available, a limited grace mechanic earned automatically at 7- and 30-day streak milestones.
Account & privacy
Settings → Account lets you export your data or delete your account entirely.
Location is used only to tag your own map pins. It's never shared with other users or sold to third parties.
14
Known limitations
TouchGrass maintains a detailed, honestly updated list of known issues, their root causes, and their fix status in KNOWN_BUGS.md. Headline items as of this writing:
Server-side AI verification is written and unit-tested but not yet deployed. The live app still verifies photos and computes rewards client-side, which works but isn't tamper-proof.
Sign in with Apple is mobile-only. The web build shows a clear message rather than attempting it.
Web push notifications need a Firebase-generated VAPID key not yet supplied at build time.
iOS has no GoogleService-Info.plist checked in yet, and the Android Firebase config's package name needs re-registering to match the app's real bundle ID before a release build. Both are external Firebase Console actions, tracked in RELEASE_GUIDE.md.
Achievement unlocking is computed client-side even in the not-yet-live server-verification path. It's bounded so the worst case is a cosmetic badge, not XP manipulation, but it isn't fully server-authoritative yet.
Always check KNOWN_BUGS.md directly for the current, complete state. It's treated as a living document, updated whenever an issue is found or fixed, rather than a one-time snapshot.
15
References
In this repository
README.md Quick project pointer
KNOWN_BUGS.mdLiving log of known issues, root causes, fix status
QA_CHECKLIST.md Manual QA checklist
RELEASE_GUIDE.mdStep-by-step App Store / Play Store release process
STORE_LISTING.md App store listing copy and screenshot specs
functions/README.mdCloud Functions status, architecture, deploy sequence
External documentation
Flutterdocs.flutter.dev ↗
riverpod.dev ↗
go_routerpub.dev ↗
Firebasefirebase.google.com/docs ↗
Firestore security rulesfirebase.google.com ↗
Gemini APIai.google.dev ↗
google_maps_flutterpub.dev ↗
TouchGrass Documentation — kept in sync with DOCUMENTATION.md in the repository root. 
