# Real-browser journeys (emulators only)

Chrome runs real user journeys against a web build that talks only to the
local Firebase Emulator Suite, under the `demo-touchgrass-dev` project id.
No real Firebase project backs a `demo-` id, so nothing here can reach
production.

**Safety nets:**
- The harness refuses to run unless all four emulators answer on localhost.
- The browser aborts any request to a real Firebase or Google backend host,
  and the tests assert that none was attempted.
- A release build can't be pointed at the emulators: the app refuses
  `TG_FIREBASE_ENV=emulator` in release mode.

**Test data:** synthetic accounts (`*@example.test`), a browser-drawn photo
carrying a synthetic GPS EXIF block, and synthetic coordinates.

## Run

Commands are run from the repository root unless a step says otherwise.
Use Node 22 and Java 21+ (for the Firestore emulator), and have Chrome
installed (`playwright-core` uses it; no browser is downloaded).

1. **Generate the emulator rules.** They are the production rules with only
   the Storage host and bucket swapped (`tool/rules_for_env.mjs`):

   ```
   node tool/rules_for_env.mjs emulator deploy/dev/generated
   ```

2. **Build Functions:**

   ```
   cd functions && npm run build
   ```

3. **Start the emulators.** `FUNCTIONS_DISCOVERY_TIMEOUT=60` helps on a busy
   machine:

   ```
   firebase emulators:start --config firebase.emulator.json --project demo-touchgrass-dev
   ```

4. **Build the web app for the emulators.** Use a profile build; release
   builds refuse the emulators:

   ```
   flutter build web --profile --dart-define=TG_FIREBASE_ENV=emulator -o <dir>
   ```

5. **Run the journeys**, from `e2e/`:

   ```
   npm ci
   E2E_WEB_DIR=<dir> npm test
   ```

Screenshots are written to `e2e/artifacts/`, which is git-ignored.

## What the journeys cover

1. **Signed-out links.** A signed-out direct link to a protected route goes
   to sign-in.
2. **Sign-up.** Email sign-up and onboarding. The typed name is kept, no
   reminder permission is requested, and today's challenge is ready (phone
   viewport).
3. **Challenge completion.** The photo goes through the gallery picker, then
   the note and "Save to Journal". The backend shows the completion with the
   honor-system reason, the Journal entry and its note, XP and streak, and the
   stored photo has no EXIF/GPS.
4. **Reload.** A reload sends nothing to a real service. In emulator builds
   it signs the user out by design (see `DEVELOPMENT_ENVIRONMENT.md` §3).
   After signing in again, today shows as done.
5. **Feedback.** Feedback is stored for the signed-in user.
6. **Saved locations.** "Remove saved locations" clears them from the
   completion and the Journal entry.
7. **Leaderboard.** "Show on Leaderboard" off persists and removes the public
   entry.
8. **Session.** Sign out, then sign back in.
9. **Account deletion.** The real `deleteAccount` function runs in the
   Functions emulator. The Auth user, profile, Journal, completions, feedback
   and photos are gone, a timestamps-only deleted-account marker is left, and
   the confirmation is shown.
10. **Reroll.** On a desktop viewport the counter goes down and is saved.
