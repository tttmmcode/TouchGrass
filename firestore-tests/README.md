# firestore-tests — security rules regression suite

These are emulator-only allow/deny tests for `../firestore.rules` and `../storage.rules`. The package is for development only. It is never deployed, and it can't reach production: it uses the `demo-touchgrass-rules` project ID, which only exists inside the emulator.

## Run

You need Node 20 or newer and **Java 21 or newer**, which the Firebase emulators require. On this machine the system Java is 17, so point `JAVA_HOME` at Android Studio's bundled runtime first (PowerShell):

```powershell
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio1\jbr'
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
cd firestore-tests
npm install
npm test
```

`npm test` starts the Firestore and Storage emulators, runs every `test/*.test.mjs` file, and then shuts the emulators down.

`firebase.json` here points at deny-all placeholder rules, only so the emulators can start. Each suite then loads the **real** rules files from the repo root through `initializeTestEnvironment()`.

## What is covered

| File | Findings | Covers |
|---|---|---|
| `users.test.mjs` | D-02, D-07 | Initial account values. Profile edits. Streak-freeze purchases. Every legitimate and forged shape of the atomic completion-plus-reward batch. Server-granted entitlement. Isolation. |
| `social.test.mjs` | D-02, D-03 | Leaderboard mirror must equal the owner's profile. Username claims are create-only, including two concurrent claims for the same name. |
| `challenges.test.mjs` | D-06, S-6, S-7 | Reroll cap: 3 per day, boundaries, concurrency, no delete. Challenge and completion forgery. Memory ↔ completion integrity. |
| `storage.test.mjs` | D-05, S-8 | The Storage rules compile. Ownership, prefix collisions, content types (SVG denied), size limits, listing, no client deletes. |

## Rules for changing these tests

- Every security-relevant rule needs at least one **ALLOWS** case and one **DENIES** case.
- Never weaken a rule just to make a test pass.
- Never change a DENIES case into an ALLOWS case without an explicit, reviewed decision.
- Passing in the emulator proves the rule *files* are correct. It does **not** prove what's deployed in production. Before any deploy, confirm the live rules in the Firebase Console.

## Dependency note (Phase 6)

`package.json` pins `@grpc/grpc-js` to `^1.14.3` with npm `overrides`. The Firebase JS SDK (even `@firebase/firestore` 4.18 / firebase 13) still pins `~1.9`, which `npm audit` flags (GHSA-m9gg-hp2v-232j, GHSA-f596-whhp-79r4; fixed in 1.13.6). This package is dev-only emulator tooling that is never shipped or deployed, and the full rules suite passes on the overridden version. Remove the override once the SDK's own range includes a fixed grpc-js.
