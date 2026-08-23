# TouchGrass — Project Documentation

TouchGrass is a cross-platform mobile and web app that turns going outside into a daily habit, using AI-verified photo challenges, XP, streaks, and a bit of friendly competition.

This document is the technical and user reference for the project. For other project documents, see [References](#references) at the end.


Try at https://touchgrass.web.app/#/home

GitHub Repository: https://github.com/tttmmcode/TouchGrass

Demo Video: https://www.youtube.com/watch?v=zFVLTNaPELM 


---

## Table of Contents

1. [Purpose](#purpose)
2. [Target Audience](#target-audience)
3. [Main Features](#main-features)
4. [Architecture & Tech Stack](#architecture--tech-stack)
5. [Project Structure](#project-structure)
6. [Installation & Local Setup](#installation--local-setup)
7. [Configuration](#configuration)
8. [Running the App](#running-the-app)
9. [Testing](#testing)
10. [Building & Deployment](#building--deployment)
11. [Data Model Reference](#data-model-reference)
12. [Security Model](#security-model)
13. [User Manual](#user-manual)
14. [Known Limitations](#known-limitations)
15. [References](#references)

---

## Purpose

Most people spend the majority of their day on a screen, even though brief, regular time outdoors has measurable benefits for mood, focus, sleep, and cardiovascular health. The gap isn't awareness, it's habit: there's no daily nudge or reward loop pulling someone off the couch the way a screen pulls them in.

TouchGrass closes that gap by applying game mechanics, daily challenges, XP, streaks, leagues, and achievements, to the single behavior of stepping outside. Each day the app assigns one challenge (e.g. "find something red in nature," "sit outside for five minutes without your phone"). The user completes it, photographs proof, and an AI vision model verifies the photo actually matches the challenge before rewarding XP. The result is logged permanently as a journal entry and a pin on a personal map, so the habit compounds into a visible record of time spent outdoors.

## Target Audience

- **People who want to spend less time on their phone and more time outside**, but need structure or motivation to make it a habit rather than an occasional intention.
- **Habit-and-streak-driven users** who respond well to daily quests, XP, and streak mechanics (the same psychological hooks as habit-tracking and gamified fitness apps, redirected toward outdoor time).
- **Casual competitive players** who enjoy leaderboards and league promotion without the pressure of a hardcore fitness app.
- **Anyone building a personal record of outdoor memories** — the map and journal features double as a lightweight, location-tagged diary of time spent outside.

The app is free to use, requires no special equipment, and is designed for a single sitting of 5–40 minutes per day depending on the challenge's difficulty.

## Main Features

| Feature | Description |
|---|---|
| **Daily Challenges** | One new challenge per day per user, generated across categories (nature, mindfulness, exploration, physical activity, etc.) at three difficulty tiers (Easy / Medium / Hard), each with its own XP reward and time estimate. |
| **AI Photo Verification** | The user photographs proof of completion; Google's Gemini vision model checks the photo against the challenge's description and success criteria before the completion is accepted. |
| **XP & Levels** | Every verified completion awards XP; level is a deterministic function of total XP. |
| **Leagues** | Eight XP-tier leagues (Seedling → Sprout → Wildflower → Forest → Mountain → Summit → Sky Trail → Aurora) that a user's total XP places them into. |
| **Streaks & Rainy Days** | Consecutive daily completions build a streak. "Rainy Days" are a limited, earnable grace mechanic that protects a streak through a missed day. |
| **Weekly Leaderboard** | A per-league leaderboard ranked by XP earned since the last Monday-midnight UTC reset, reading from a privacy-safe public mirror of user data rather than full user documents. |
| **Achievements** | Badge unlocks for milestones (streak length, total completions, category variety, etc.). |
| **Adventure Map & Journal** | Every completion is saved with its photo, caption, and (optional) location, viewable as pins on a map or as a chronological journal. |
| **Companion** | A woodland mascot that reacts to completions and streak milestones. |
| **Entitlement tiers** | Data model and gating scaffolding for a future free/premium split (see [Known Limitations](#known-limitations); not monetized yet). |
| **Accounts** | Email/password, Google Sign-In, and Sign in with Apple (mobile only — see limitations). |
| **Notifications** | Push notification plumbing for daily-challenge reminders, streak warnings, and achievement unlocks (mobile; web requires additional setup — see [Configuration](#configuration)). |

## Architecture & Tech Stack

TouchGrass is a single Flutter codebase targeting **Android, iOS, and Web** from one source tree, backed by Firebase.

**Client**
- **Flutter / Dart** (SDK `^3.12.1`) — UI and application logic for all platforms.
- **Riverpod** (`flutter_riverpod`, `riverpod_annotation`) — state management; screens are `ConsumerWidget`/`ConsumerStatefulWidget`s reading from `StateNotifierProvider`/`StateProvider`s in `lib/providers/`.
- **go_router** — declarative, URL-based navigation (also required for correct web deep-linking).

**Backend (Firebase, project `touchgrass-today`)**
- **Firebase Authentication** — email/password, Google, and Apple sign-in.
- **Cloud Firestore** — primary database (users, challenges, completions, memories, leaderboard mirror).
- **Firebase Storage** — completion photos and profile avatars.
- **Cloud Functions** (TypeScript, `functions/`) — a written and unit-tested server-side verification function; **not yet deployed** (see [Known Limitations](#known-limitations)).
- **Firebase Hosting** — serves the web build, on two sites (primary + legacy rollback — see [Building & Deployment](#building--deployment)).
- **Firebase Analytics, Crashlytics, Performance, Cloud Messaging (FCM)** — telemetry, crash reporting, and push notifications.

**AI**
- **Google Gemini** (`google_generative_ai` package) — multimodal vision model used to verify a submitted photo against a challenge's description and success criteria.

**Other integrations**
- **Google Maps** (`google_maps_flutter`) — renders the Adventure Map.
- **Geolocator / Geocoding** — device location and reverse-geocoding for tagging memories.

See `pubspec.yaml` for the exact, versioned dependency list.

## Project Structure

```
touchgrass/
├── lib/
│   ├── main.dart                # App entry point
│   ├── firebase_options.dart    # Generated Firebase config (per-platform)
│   ├── core/                    # Cross-cutting: constants, config, errors, router, utils
│   ├── models/                  # Immutable data models (ChallengeModel, UserModel, ...)
│   ├── providers/                # Riverpod providers — app state and business-logic glue
│   ├── repositories/             # Firebase read/write boundary (one per collection/domain)
│   ├── services/                 # Thin wrappers around external SDKs (Gemini, Storage, Auth, ...)
│   ├── features/                 # One folder per user-facing feature area:
│   │   ├── achievements/  auth/  camera/  challenges/  companions/
│   │   ├── home/  leaderboard/  leagues/  map/  onboarding/
│   │   └── profile/  settings/  streak/
│   ├── companions/               # Companion mascot widget + painter
│   ├── theme/                    # Colors, spacing, typography
│   └── widgets/                  # Shared, reusable widgets
├── test/                         # Mirrors lib/ structure — unit and widget tests
├── functions/                    # Cloud Functions (TypeScript) — see functions/README.md
│   └── src/
│       ├── index.ts              # Callable function entry point
│       └── rewards.ts            # Pure reward/entitlement logic (unit-testable, no Firebase SDK import)
├── android/  ios/  web/  macos/  windows/  linux/  # Platform-specific project files
├── firestore.rules               # Firestore security rules
├── storage.rules                 # Storage security rules
├── firebase.json                 # Firebase project config (multi-site Hosting, Functions, rules paths)
├── .firebaserc                   # Firebase project/target aliases
├── pubspec.yaml                  # Flutter dependencies and app metadata
├── secrets.json                  # Local-only build secrets (gitignored — see Configuration)
├── KNOWN_BUGS.md                 # Honest, running log of known issues and their status
├── QA_CHECKLIST.md               # Manual QA checklist
├── RELEASE_GUIDE.md              # Step-by-step App Store / Play Store release checklist
└── STORE_LISTING.md              # App Store / Play Store listing copy
```

**Layering convention**: `features/` screens read from `providers/`, which call `repositories/`, which call `services/` (or Firebase SDKs directly for simple cases). Repositories return a typed `Result<T>` rather than throwing raw Firebase exceptions, so UI code never has to catch SDK-specific error types.

## Installation & Local Setup

### Prerequisites

| Tool | Notes |
|---|---|
| [Flutter SDK](https://docs.flutter.dev/get-started/install) | Matching `environment.sdk: ^3.12.1` in `pubspec.yaml`. Run `flutter doctor` after install and resolve any flagged issues. |
| [Node.js](https://nodejs.org/) 20+ | Only needed if working on `functions/` (Cloud Functions). |
| [Firebase CLI](https://firebase.google.com/docs/cli) | `npm install -g firebase-tools`, then `firebase login`. |
| Android Studio / Xcode | Only needed for the platform(s) you're building for. Xcode (macOS only) is required for any iOS build. |
| A Firebase project | This repo is wired to project `touchgrass-today` via `.firebaserc`/`firebase_options.dart`. To run against your own Firebase project instead, see the note in [Configuration](#configuration). |

### Steps

```bash
# 1. Clone the repository
git clone https://github.com/tttmmcode/TouchGrass.git
cd touchgrass

# 2. Install Flutter dependencies
flutter pub get

# 3. Confirm your toolchain is healthy
flutter doctor

# 4. Provide local secrets (see Configuration below)
#    Create secrets.json in the project root — never commit this file.

# 5. Run the app (see "Running the App" for platform-specific variants)
flutter run --dart-define-from-file=secrets.json
```

If you're working on Cloud Functions as well:

```bash
cd functions
npm install
```

## Configuration

TouchGrass takes all secret/environment-specific values via Flutter's `--dart-define` mechanism — **nothing sensitive is hardcoded in source**.

### `secrets.json`

Create this file at the project root (it's gitignored):

```json
{
  "GEMINI_API_KEY": "your-gemini-api-key-here"
}
```

Get a key from [Google AI Studio](https://aistudio.google.com/app/apikey). Without this key, the app still runs and challenges can still be completed — photo verification silently falls back to an "honor system" approval instead of a real AI check (see `lib/providers/camera_providers.dart`'s `honorSystemVerificationResult`). This is intentional: the app must never be unusable just because a key isn't configured.

Pass it at build/run time with `--dart-define-from-file=secrets.json`, or supply individual keys directly:

```bash
flutter run --dart-define=GEMINI_API_KEY=your-key-here
```

### All recognized `--dart-define` keys

| Key | Required | Default | Purpose |
|---|---|---|---|
| `GEMINI_API_KEY` | No | `''` (empty) | Enables real AI photo verification. Empty = honor-system fallback. |
| `FCM_VAPID_KEY` | No | `''` (empty) | Enables web push notifications. Get this from Firebase Console → Project Settings → Cloud Messaging → Web Push certificates. Empty = notifications silently no-op on web (mobile is unaffected). |
| `ENVIRONMENT` | No | `development` | One of `development`, `staging`, `production`. Gates which challenge-verification implementation the app can construct (see `functions/README.md`'s "fail-closed, environment-branched wiring" section) — currently no production build has ever shipped from this repo. |

### Firebase project setup

The app is already wired to the `touchgrass-today` Firebase project via the generated `lib/firebase_options.dart` and per-platform config files (`android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist` — the latter is not currently checked into this repo, see [Known Limitations](#known-limitations)).

To point the app at a **different** Firebase project (e.g. your own sandbox):

```bash
firebase login
flutterfire configure   # regenerates lib/firebase_options.dart and platform config files
```

Then deploy the security rules and (once you have Blaze billing enabled) Cloud Functions to your project:

```bash
firebase deploy --only firestore:rules,storage
```

### Google Maps API key

The Adventure Map feature requires a Google Maps API key, configured per-platform:
- **Android**: `android/local.properties` (or an environment-injected Gradle property).
- **iOS**: `ios/Runner/AppDelegate.swift`.
- **Web**: embedded once in `web/index.html`.

See `RELEASE_GUIDE.md` for how to restrict this key by platform and bundle ID before shipping.

## Running the App

```bash
# Web (Chrome)
flutter run -d chrome --dart-define-from-file=secrets.json

# Android (device or emulator)
flutter run -d android --dart-define-from-file=secrets.json

# iOS (device or simulator — macOS only)
flutter run -d ios --dart-define-from-file=secrets.json
```

Hot reload (`r`) and hot restart (`R`) work as usual once the app is running.

## Testing

```bash
# Full Flutter test suite (unit + widget tests, mirrors test/ to lib/)
flutter test

# Static analysis — must report zero issues before any commit
flutter analyze

# Cloud Functions test suite (pure logic, no Firebase emulator needed)
cd functions
npm test
```

Tests are organized to mirror `lib/`'s structure (e.g. `test/providers/camera_providers_test.dart` tests `lib/providers/camera_providers.dart`). New logic, especially anything touching XP/streak/entitlement calculations, should ship with a corresponding unit test rather than relying on manual QA alone.

## Building & Deployment

### Web

```bash
flutter build web --release --dart-define-from-file=secrets.json
firebase deploy --only hosting:main    # primary: touchgrass.web.app
firebase deploy --only hosting:today   # legacy/rollback: touchgrass-today.web.app
```

Hosting is configured as a multi-site setup (`firebase.json`'s `hosting` array + `.firebaserc`'s `targets`): both sites currently serve identical builds from the same Firebase project, `touchgrass.web.app` as the primary URL and `touchgrass-today.web.app` kept live as a rollback target.

### Android / iOS

See **`RELEASE_GUIDE.md`** for the full, step-by-step signing and store-submission checklist (keystore generation, bundle ID fixes, App Store Connect / Play Console setup, TestFlight/closed testing). In short:

```bash
flutter build appbundle --release   # Android, for Play Store
flutter build apk --release         # Android, for direct install/testing
# iOS: archive and distribute via Xcode (Product → Archive)
```

### Cloud Functions

Written and unit-tested, but **not deployed** — see `functions/README.md` for the exact prerequisites (Blaze billing, secret configuration) and the deliberately sequenced deploy/cutover steps.

## Data Model Reference

Primary Firestore collections (see `lib/core/constants/app_constants.dart` for the authoritative names):

| Collection | Purpose |
|---|---|
| `users/{uid}` | Full user document — profile, XP, streak, level, league, achievements, private fields (email, etc.). Owner-read-only. |
| `leaderboard_public/{uid}` | Safe-to-share mirror of a subset of the user document (`displayName`, `username`, `photoUrl`, `xp`, `weeklyXp`, `streak`, `currentLeague`). Any signed-in user may read this; leaderboard queries read from here, never from `users/`, so no client can see another user's private fields. |
| `usernames/{username}` | Username-uniqueness registry; doc data is just `{uid: <owner>}`. |
| `users/{uid}/challenges/{date}` | Per-user, per-day assigned challenge. |
| `users/{uid}/memories/{memoryId}` | Journal/map entries (photo, caption, location). |
| `users/{uid}/aiUsage/{YYYY-MM}` | Server-authoritative AI-verification quota counters (never client-writable). |
| `completions/{uid_challengeId}` | One record per completed challenge; deterministic ID prevents duplicate completions for the same day. |
| `challenges/{challengeId}` | The challenge catalogue (read-only to clients). |
| `achievements/{achievementId}` | The achievement catalogue (read-only to clients). |

Key derived values, computed identically on the client (`AppConstants`) and cross-checked in `firestore.rules` (`levelForXp`, `leagueForXp`):
- **Level** = `floor(xp / 100) + 1`
- **League** thresholds (XP): Aurora ≥ 20,000 · Sky Trail ≥ 10,000 · Summit ≥ 6,000 · Mountain ≥ 3,000 · Forest ≥ 1,500 · Wildflower ≥ 700 · Sprout ≥ 300 · Seedling (default)

Firebase Storage paths: `completion_photos/{uid}/...` and `user_avatars/{uid}...`, both owner-scoped and size-capped (10MB / 5MB respectively).

## Security Model

- **Firestore rules** (`firestore.rules`) enforce per-document ownership, bound how much XP/level/streak a single client write can legitimately change (a stopgap against direct-API abuse until server-computed rewards via Cloud Functions are live), and keep completions immutable once created.
- **Storage rules** (`storage.rules`) restrict photo uploads to their owning user's own path and enforce size caps.
- **AI-verification quota** is tracked server-side only, in a subcollection no client can write to, so quota can't be reset by reinstalling the app.
- Secrets (Gemini key, Maps key) are never committed to source control; see [Configuration](#configuration).

This project maintains an honest, continuously-updated account of security posture and known gaps in `KNOWN_BUGS.md` — worth reading before extending anything security-sensitive.

## User Manual

### Getting started
1. Open the app and create an account (email/password, Google, or Apple).
2. Complete the brief onboarding flow.
3. Your first daily challenge is waiting on the Home screen.

### Completing a daily challenge
1. From the Home screen, tap **Start Challenge** to read the challenge's description and objective.
2. Go do the activity outside.
3. Tap the camera button and take a photo that shows you completed it.
4. Wait a moment while the photo is verified (an AI check, or, if AI verification isn't configured for your build/account, an automatic honor-system approval).
5. If verification fails, you can either **Retake Photo**, **Retry Verification** on the same photo, or **Submit Anyway** to log it without AI confirmation.
6. Write a short caption describing your experience, then submit. You'll see your XP reward, streak update, and any achievements unlocked.

### Viewing your history
- **Map tab**: every completion with a location appears as a pin you can tap for details.
- **Journal tab**: a chronological list of every completion, with photo and caption.

### Tracking progress
- **Profile tab**: level, XP progress, streak, league, and unlocked achievements.
- **Leaderboard tab**: your league's weekly ranking (resets every Monday at midnight UTC).
- **Leagues tab**: an overview of all eight leagues and their XP thresholds.

### Streak protection
Missing a day breaks your streak unless you have a **Rainy Day** available — a limited grace mechanic earned automatically at 7- and 30-day streak milestones.

### Account & privacy
- **Settings → Account** lets you export your data or delete your account entirely.
- Location is used only to tag your own map pins; it's never shared with other users or sold to third parties.

## Known Limitations

TouchGrass maintains a detailed, honestly updated list of known issues, their root causes, and their fix status in **`KNOWN_BUGS.md`**. Headline items as of this writing:

- **Server-side AI verification** is written and unit-tested (`functions/`) but not yet deployed — the live app still verifies photos and computes rewards client-side, which is workable but not tamper-proof.
- **Sign in with Apple** is mobile-only; the web build shows a clear message rather than attempting it.
- **Web push notifications** require a Firebase-generated VAPID key not yet supplied at build time.
- **iOS** has no `GoogleService-Info.plist` checked into this repo yet, and the Android Firebase config's package name needs to be re-registered to match the app's real bundle ID before a release build — both are external Firebase Console actions, tracked in `RELEASE_GUIDE.md`.
- **Achievement unlocking** is computed client-side even in the (not-yet-live) server-verification path — bounded so the worst case is a cosmetic badge, not XP manipulation, but not yet fully server-authoritative.

Always check `KNOWN_BUGS.md` directly for the current, complete state — it is treated as a living document, updated every time an issue is found or fixed, not a one-time snapshot.

## References

**In this repository**
- [`README.md`](README.md) — quick project pointer
- [`KNOWN_BUGS.md`](KNOWN_BUGS.md) — living log of known issues, root causes, and fix status
- [`QA_CHECKLIST.md`](QA_CHECKLIST.md) — manual QA checklist
- [`RELEASE_GUIDE.md`](RELEASE_GUIDE.md) — step-by-step App Store / Play Store release process
- [`STORE_LISTING.md`](STORE_LISTING.md) — app store listing copy and screenshot specs
- [`functions/README.md`](functions/README.md) — Cloud Functions status, architecture, and deployment sequence

**External documentation**
- [Flutter documentation](https://docs.flutter.dev/)
- [Riverpod documentation](https://riverpod.dev/)
- [go_router documentation](https://pub.dev/packages/go_router)
- [Firebase documentation](https://firebase.google.com/docs)
- [Cloud Firestore security rules reference](https://firebase.google.com/docs/firestore/security/get-started)
- [Google Gemini API documentation](https://ai.google.dev/gemini-api/docs)
- [Google Maps Platform (Flutter) documentation](https://pub.dev/packages/google_maps_flutter)

