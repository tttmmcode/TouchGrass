# TouchGrass — development and test environments

**Rule:** day-to-day development and testing never touch production. The
production project is `touchgrass-today`, which serves both
`touchgrass-today.web.app` and `touchgrass.web.app`.

## 1. Environments

| Environment | Firebase project | Selected by | Use |
|---|---|---|---|
| `production` | `touchgrass-today` | release builds by default, or `--dart-define=TG_FIREBASE_ENV=production` | Real users. The only environment with Analytics, Performance and Crashlytics |
| `development` | `touchgrass-dev-n7j3f` ("TouchGrass DEV") | `--dart-define=TG_FIREBASE_ENV=development` (web only so far) | A shared cloud sandbox with synthetic data |
| `emulator` | `demo-touchgrass-dev` (local Emulator Suite) | debug and profile builds by default, or `--dart-define=TG_FIREBASE_ENV=emulator` | Local development and the browser journeys (`e2e/`) |

**Fail-closed rules** (`lib/core/config/firebase_environment.dart`, tested in
`test/core/firebase_environment_test.dart`):
- **Unknown values:** an unknown or misspelled `TG_FIREBASE_ENV` stops the app
  at startup with a configuration screen.
- **No emulators in release:** a release build can't select the emulators.
- **Project check:** each environment's options are checked against its
  expected project id.
- **Debug runs:** `flutter run` without flags now uses the emulators. Before
  Phase 8, debug runs wrote to production.
- **Telemetry:** outside production, Analytics, Performance and Crashlytics are
  off (`AnalyticsService`, `PerfService` and `CrashReporter` no-op).
- **Visible label:** non-production builds show a "DEV" or "EMULATOR" corner
  banner.

## 2. The development project `touchgrass-dev-n7j3f`

- **Plan:** Spark (free); no billing account linked.
- **Created** 2026-10-25 with `firebase projects:create`.
- **Enabled APIs:** Firestore and Identity Toolkit. Enabling them is free.
- **Web app:** "TouchGrass DEV web". No Analytics is linked, so there is no
  `measurementId`.
- **Firestore:** `(default)` in `nam5`.
- **Rules and indexes:** generated from the production rules by
  `tool/rules_for_env.mjs development` (only the profile-photo bucket name
  differs).
- **Auth:** email/password enabled.
- **Not available without Blaze (owner decision):** Cloud Storage (new default
  buckets need Blaze) and Cloud Functions. Until then the dev project can't
  store photos or run `deleteAccount`; use the emulators for those.
- **Hosting:** the default site `touchgrass-dev-n7j3f.web.app` exists but has
  no deploy yet. It is only useful once Storage exists.

**Deploying to the DEV project.** Never to production: the config lives in
`deploy/dev/`, whose `.firebaserc` knows only the dev project, and every
command names it explicitly.

```
node tool/rules_for_env.mjs development deploy/dev/generated
cd deploy/dev
firebase deploy --only auth,firestore --project touchgrass-dev-n7j3f
```

## 3. Local emulators (full stack, free)

`firebase.emulator.json` loads the emulator variant of the production rules
(Storage emulator host and the `demo-` bucket swapped in;
`tool/rules_for_env.mjs`) and the real `deleteAccount` function.

```
node tool/rules_for_env.mjs emulator deploy/dev/generated
cd functions && npm run build && cd ..
firebase emulators:start --config firebase.emulator.json --project demo-touchgrass-dev
flutter run -d chrome                 # debug → emulators by default
```

On a busy machine, set `FUNCTIONS_DISCOVERY_TIMEOUT=60`. The browser
journeys are in `e2e/README.md`.

**Emulator web builds sign out on reload (by design).**
- **Why:** on web, FlutterFire restores a saved sign-in while Firebase
  starts, before the app can point Auth at the emulator. That restore went to
  the real Auth service, and FlutterFire then silently ignored the emulator
  connection, so every later sign-in went there too (found in the Phase 8
  browser run).
- **What emulator builds do now:**
  - they never save the sign-in on web;
  - they check with the Auth SDK that it really uses the emulator;
  - if it doesn't, they clear the restored sign-in and stop with a
    configuration error that asks you to reload.
- **Production builds** are unchanged.

**Functions scripts** (`functions/package.json`): `npm run serve` and
`npm run shell` use `--project demo-touchgrass-dev`. `tool/test/dev_safety.test.mjs`
checks that no emulator or shell script can name a real project.

## 4. Tests (all local)

| Suite | Command |
|---|---|
| Flutter | `flutter test`, `flutter analyze`, `dart format --output=none --set-exit-if-changed lib test` |
| Functions | `cd functions && npm test && npm run test:emulator && npm run lint` |
| Rules | `cd firestore-tests && npm test` |
| Tools | `node tool/strict_node_test.mjs "tool/test/*.test.mjs"` |
| Android gates | `bash tool/test_android_gates.sh` |
| Browser journeys | see `e2e/README.md` |

Every Node suite runs through `tool/strict_node_test.mjs`, which also fails a
suite whose `describe()` throws. Node 22 alone reports that as passing.

**Windows note:** if a Node 22 copy lives under `%TEMP%`, Windows cleanup can
delete parts of it. npm then fails with exit 1 and no output; re-extract it.

## 5. What must never happen

- `firebase deploy` from the repository root without
  `--only <exact target> --project <id>`. Production deploys need the owner's
  approval for each operation (`RELEASE_PLAN.md`).
- Building the production web app with `--dart-define-from-file=secrets.json`.
- Production credentials in any dev or test flow.
