# Phase 7F — Android release signing guide (owner-only steps)

**Status: not configured.** `android/key.properties` is absent and no keystore exists in the repository. Nothing about signing was generated, requested or stored in 7F. **These steps are done by you, on your machine. Never paste passwords, keystores or `key.properties` contents into chat, issues or reports.**

## 1. What the build already enforces (`android/app/build.gradle.kts`)

- **Release builds are always signed with the upload key** from `android/key.properties`. **There is no debug-key fallback:** a missing or incomplete file stops the build and names the missing field, never its value.
- `storeFile` must exist (a relative path resolves from `android/app`).
- Release builds also require `MAPS_API_KEY` in `android/local.properties`.
- Every build requires `google-services.json` to contain `com.touchgrass.app`. Today it doesn't (see `PHASE_7F_FIREBASE_PLATFORM_CONFIGURATION.md`).
- Debug builds use the standard debug key and need nothing from you, so debug and release can't be confused.
- Release: R8 minify and resource shrinking on. Crashlytics mapping upload is off unless `-P uploadCrashlyticsMapping=true`.
- Ignored by Git: `key.properties`, `*.jks` and `*.keystore` (root `.gitignore` lines 58–60 and `android/.gitignore`), plus `local.properties`.
- `tool/test_android_gates.sh` proves these gates. 14/14 in 7E; the 7F run is in the final report.

## 2. Create the upload key (once)

Run in your own terminal. `keytool` prompts for the passwords; don't put them on the command line, where they'd land in shell history:

```
keytool -genkeypair -v -keystore "%USERPROFILE%\keys\touchgrass-upload.jks" -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

- Keep the keystore **outside** the repository.
- Use a long random password from your password manager.

## 3. Point the build at it (local, never committed)

Create `android/key.properties`:

```
storeFile=C:\\Users\\<you>\\keys\\touchgrass-upload.jks
storePassword=<from your password manager>
keyAlias=upload
keyPassword=<from your password manager>
```

Add `MAPS_API_KEY=<Android-restricted Maps key>` to `android/local.properties`.

Then check Git ignores them: `git check-ignore -v android/key.properties android/local.properties` must print a rule for both.

## 4. Play App Signing: upload key vs app-signing key

- **Enrol in Play App Signing** when you create the app in Play Console. Google generates and keeps the **app-signing key**, which signs what users install. You keep only the **upload key**, which proves uploads come from you.
- **If the upload key is lost or leaked:** Play Console → App integrity → request an upload key reset. Google registers a new upload key after verification; installed users are unaffected.
- **Without Play App Signing,** losing the key means you can never update the app under the same package name. Don't skip enrolment.
- **Firebase fingerprints:** add the SHA-1 and SHA-256 of the debug key, the upload key and Play's **app-signing** certificate (from Play Console → App integrity) to the `com.touchgrass.app` Android app in Firebase. Google sign-in needs them. This is a project configuration change (gate G-1).
- **To print your fingerprints** (it prompts for the store password; it prints certificates only, never the private key): `keytool -list -v -keystore "%USERPROFILE%\keys\touchgrass-upload.jks" -alias upload`

## 5. Backup and recovery

- Keep two backups of the `.jks` and its passwords: one in your password manager (as an attachment) and one offline (an encrypted USB drive kept separately).
- Record the alias (`upload`), the creation date and the SHA-256 alongside the backups.
- Test a restore once: copy the backup to a new path, point `storeFile` at it, run `flutter build appbundle --release`.

## 6. CI (only if you add one; there are no workflows today)

- Store the keystore as a base64 CI secret and the passwords as separate secrets. Write `key.properties` at job start into the runner's temp directory and delete it at the end. Never echo the secrets, and don't upload `android/` as an artifact.

## 7. Build and verify (after G-1 and the steps above)

```
flutter build appbundle --release
```

Then verify:
- **Signer:** `jarsigner -verify -verbose -certs build\app\outputs\bundle\release\app-release.aab` reports the upload certificate (the SHA-256 matches §4), not "Android Debug".
- **Package:** `bundletool dump manifest --bundle build\app\outputs\bundle\release\app-release.aab` shows `package="com.touchgrass.app"` and no `android:debuggable="true"`.
- **No secrets in the artifact:** unzip the AAB and search for `storePassword`, `keyPassword`, `.jks`, `PRIVATE KEY`, `GEMINI` and `generativelanguage`. Expect no matches. The only `AIza…` key expected is the restricted Firebase Android key.
- **No secrets in logs:** the Gradle gates print field names only. Check the build output doesn't contain your passwords (it shouldn't; `keytool` and Gradle don't echo them).

**Don't upload to Google Play as part of this phase.** Store submission needs its own authorization.
