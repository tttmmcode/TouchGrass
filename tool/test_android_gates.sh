#!/usr/bin/env bash
# Android build-gate tests (Phase 7A) — LOCAL ONLY, never touches the
# repository's own android/ files or any Firebase project.
#
#   bash tool/test_android_gates.sh            # gate cases (Gradle dry-runs)
#   bash tool/test_android_gates.sh --full     # + real debug build and a
#                                              #   TEST-key-signed release build
#
# Works on a temporary copy of the project:
# - google-services.json is rewritten in the COPY ONLY to name
#   com.touchgrass.app (test fixture), unless the repo already has a real
#   config for it — so the signing gate can be reached past the X-5 gate;
# - android/local.properties in the copy gets the SDK paths only and a FAKE
#   Maps key; the real key is never copied;
# - signing material is generated per run (random password held in an
#   environment variable, never printed) and deleted afterwards. A test key
#   must never be used for a real release.
# Exit 0 = every case behaved as expected. Needs: flutter, JAVA_HOME (JDK 17+),
# python (or py) and, for --full, Android build-tools (apksigner, aapt2).
set -u
FULL=0; [ "${1:-}" = "--full" ] && FULL=1
REPO="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
PY=""
for c in python3 python py; do
  if command -v "$c" > /dev/null 2>&1 && "$c" -c "print(1)" > /dev/null 2>&1; then PY="$c"; break; fi
done
[ -n "$PY" ] || { echo "python not found"; exit 1; }
PASS=0; FAIL=0
ok()   { echo "PASS  $1"; PASS=$((PASS+1)); }
bad()  { echo "FAIL  $1"; FAIL=$((FAIL+1)); }
cleanup() { rm -rf "$WORK"; unset TG_TEST_PW; }
trap cleanup EXIT

echo "Copying the project to a temporary folder…"
# Tracked + untracked (not ignored) files that exist in the working tree.
( cd "$REPO" && git ls-files -co --exclude-standard | while IFS= read -r f; do [ -f "$f" ] && printf '%s\0' "$f"; done \
  | tar --null -cf - -T - ) | ( cd "$WORK" && tar -xf - ) || { echo "copy failed"; exit 1; }
P="$WORK"; A="$P/android"
# The Gradle wrapper is git-ignored (android/.gitignore) but not secret.
for w in gradlew gradlew.bat gradle/wrapper/gradle-wrapper.jar; do
  [ -f "$REPO/android/$w" ] && cp "$REPO/android/$w" "$A/$w"
done
[ -f "$A/gradlew" ] || { echo "No Gradle wrapper: run 'flutter build apk --config-only' once in the repo"; exit 1; }
chmod +x "$A/gradlew"
# SDK locations only — never the real MAPS_API_KEY.
grep -E '^(sdk\.dir|flutter\.sdk|flutter\.buildMode|flutter\.versionName|flutter\.versionCode)=' "$REPO/android/local.properties" > "$A/local.properties.base" 2>/dev/null || true
FAKE_MAPS="AIzaTESTONLYxxxxxxxxxxxxxxxxxxxxxxxxxxx"
"$PY" - "$A/app/google-services.json" <<'EOF'
import json, sys
p = sys.argv[1]
j = json.load(open(p, encoding="utf-8"))
pk = [c["client_info"]["android_client_info"]["package_name"] for c in j.get("client", [])]
if "com.touchgrass.app" not in pk:
    j["client"][0]["client_info"]["android_client_info"]["package_name"] = "com.touchgrass.app"
    json.dump(j, open(p, "w", encoding="utf-8"), indent=2)
    print("google-services.json in the COPY rewritten to com.touchgrass.app (test fixture)")
EOF
cp "$REPO/android/app/google-services.json" "$WORK/original-google-services.json"
(cd "$P" && flutter pub get > "$WORK/pubget.log" 2>&1) || { echo "flutter pub get failed"; exit 1; }

props() { cp "$A/local.properties.base" "$A/local.properties"; [ -n "${1:-}" ] && echo "MAPS_API_KEY=$1" >> "$A/local.properties"; true; }
gradle() { (cd "$A" && ./gradlew "$@" --dry-run --console=plain > "$WORK/gradle.log" 2>&1); echo $?; }
expect_stop() { # name task message
  local rc; rc=$(gradle "$2")
  if [ "$rc" != "0" ] && grep -q "TouchGrass build stopped" "$WORK/gradle.log" && grep -q -- "$3" "$WORK/gradle.log"; then ok "$1"
  else bad "$1 (exit $rc)"; grep -E "TouchGrass|•" "$WORK/gradle.log" | head -5; fi
  if [ -n "${TG_TEST_PW:-}" ] && grep -q -- "$TG_TEST_PW" "$WORK/gradle.log"; then bad "$1: password appeared in the output"; fi
}
expect_pass() { # name task
  local rc; rc=$(gradle "$2")
  if [ "$rc" = "0" ] && ! grep -q "TouchGrass build stopped" "$WORK/gradle.log"; then ok "$1"
  else bad "$1 (exit $rc)"; grep -E "TouchGrass|•|What went wrong" -A2 "$WORK/gradle.log" | head -8; fi
}

TG_TEST_PW=$("$PY" -c "import secrets;print(secrets.token_urlsafe(24))"); export TG_TEST_PW
KS="$WORK/test-upload.jks"
"$JAVA_HOME/bin/keytool" -genkeypair -keystore "$KS" -alias testupload -keyalg RSA -keysize 2048 -validity 7 \
  -dname "CN=TouchGrass TEST ONLY - never for release" -storepass:env TG_TEST_PW -keypass:env TG_TEST_PW -noprompt > /dev/null 2>&1 \
  || { echo "keytool failed"; exit 1; }
KSP=$(cd "$WORK" && pwd -W 2>/dev/null || pwd)/test-upload.jks
keyprops() { printf 'storeFile=%s\nstorePassword=%s\nkeyAlias=testupload\nkeyPassword=%s\n' "$KSP" "$TG_TEST_PW" "$TG_TEST_PW" > "$A/key.properties"; }

# Phase 8: emulator connections exist only in main.dart's emulator branch,
# and a release build refuses that environment (firebase_environment.dart;
# unit-tested), so release talks to production only.
EMU_RE="use(Firestore|Storage|Auth|Functions|Database)Emulator|connect[A-Za-z]*Emulator|10\.0\.2\.2"
grep -rnE "$EMU_RE" "$P/lib" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//' \
  | grep -v '/lib/main\.dart:' | grep -q . \
  && bad "emulator endpoints outside main.dart's emulator branch" \
  || ok "emulator endpoints only in main.dart"
grep -q "if (env == FirebaseEnv.emulator) await _connectEmulators();" "$P/lib/main.dart" \
  && grep -q "A release build cannot use the emulators" "$P/lib/core/config/firebase_environment.dart" \
  && ok "emulators only in the emulator environment, which release builds refuse" \
  || bad "emulator connection is not limited to the emulator environment"

echo "Gate cases (Gradle dry-runs; first one configures the build and is slow)…"
props "$FAKE_MAPS"; rm -f "$A/key.properties"
expect_pass  "debug build needs no signing material"                    :app:assembleDebug
props ""
expect_pass  "debug build without MAPS_API_KEY still runs"               :app:assembleDebug
grep -q "has no MAPS_API_KEY, so this build's map" "$WORK/gradle.log" && ok "…and warns that the map won't load" || bad "no missing-Maps-key warning"
props "$FAKE_MAPS"
expect_stop  "release without key.properties stops (no debug fallback)"  :app:assembleRelease "key.properties is missing"
expect_stop  "release bundle (AAB) without key.properties stops"         :app:bundleRelease   "key.properties is missing"
printf 'storeFile=%s\nkeyAlias=testupload\n' "$KSP" > "$A/key.properties"
expect_stop  "incomplete key.properties names the missing storePassword" :app:assembleRelease "has no 'storePassword'"
expect_stop  "incomplete key.properties names the missing keyPassword"   :app:assembleRelease "has no 'keyPassword'"
keyprops; sed -i.bak "s#^storeFile=.*#storeFile=$WORK/does-not-exist.jks#" "$A/key.properties"; rm -f "$A/key.properties.bak"
expect_stop  "a keystore path that doesn't exist stops"                  :app:assembleRelease "doesn't exist"
keyprops; props ""
expect_stop  "release without MAPS_API_KEY stops"                        :app:assembleRelease "no MAPS_API_KEY"
props "$FAKE_MAPS"
expect_pass  "complete signing config passes the gate"                   :app:bundleRelease
cp "$WORK/original-google-services.json" "$A/app/google-services.json"
if ! grep -q '"package_name": "com.touchgrass.app"' "$A/app/google-services.json"; then
  expect_stop "debug with the repo's current google-services.json stops (X-5)" :app:assembleDebug "has no Firebase app for 'com.touchgrass.app'"
  "$PY" - "$A/app/google-services.json" <<'EOF'
import json, sys
p = sys.argv[1]; j = json.load(open(p, encoding="utf-8"))
j["client"][0]["client_info"]["android_client_info"]["package_name"] = "com.touchgrass.app"
json.dump(j, open(p, "w", encoding="utf-8"), indent=2)
EOF
fi
echo '{"client": [' > "$WORK/broken.json"; cp "$A/app/google-services.json" "$WORK/good.json"; cp "$WORK/broken.json" "$A/app/google-services.json"
expect_stop  "malformed google-services.json stops"                      :app:assembleDebug "not valid JSON"
cp "$WORK/good.json" "$A/app/google-services.json"

if [ $FULL = 1 ]; then
  echo "Full builds (several minutes)…"
  BT=$(ls -d "${ANDROID_HOME:-${LOCALAPPDATA:-$HOME}/Android/Sdk}"/build-tools/* 2>/dev/null | grep -v rc | sort -V | tail -1)
  rm -f "$A/key.properties"
  if (cd "$P" && flutter build apk --debug > "$WORK/debug.log" 2>&1); then ok "real debug APK builds without signing material"; else bad "real debug APK build"; tail -20 "$WORK/debug.log"; fi
  keyprops
  if (cd "$P" && flutter build apk --release > "$WORK/release.log" 2>&1); then
    ok "release APK builds when signed with the (test) upload key"
    APK="$P/build/app/outputs/flutter-apk/app-release.apk"
    SIGNER=$("$BT/apksigner"* verify --print-certs "$APK" 2>/dev/null | grep -m1 "certificate SHA-256 digest" | awk '{print $NF}')
    TESTCERT=$("$JAVA_HOME/bin/keytool" -list -v -keystore "$KS" -storepass:env TG_TEST_PW 2>/dev/null | grep -m1 "SHA256:" | awk '{print $NF}' | tr -d ':' | tr 'A-F' 'a-f')
    DEBUGCERT=$("$JAVA_HOME/bin/keytool" -list -v -keystore "$HOME/.android/debug.keystore" -storepass android -alias androiddebugkey 2>/dev/null | grep -m1 "SHA256:" | awk '{print $NF}' | tr -d ':' | tr 'A-F' 'a-f')
    [ -n "$SIGNER" ] && [ "$SIGNER" = "$TESTCERT" ] && ok "APK is signed with the configured key" || bad "APK signer ($SIGNER) is not the configured key"
    [ "$SIGNER" != "$DEBUGCERT" ] && ok "APK is NOT signed with the debug key" || bad "APK is signed with the debug key"
    "$BT/apksigner"* verify "$APK" > /dev/null 2>&1 && ok "apksigner verify passes" || bad "apksigner verify"
    BADGE=$("$BT/aapt2"* dump badging "$APK" 2>/dev/null)
    echo "$BADGE" | grep -q "package: name='com.touchgrass.app'" && ok "package is com.touchgrass.app" || bad "package name"
    echo "$BADGE" | grep -q "application-debuggable" && bad "release APK is debuggable" || ok "release APK is not debuggable"
    echo "$BADGE" | grep -m1 -o "versionCode='[0-9]*' versionName='[^']*'" | sed 's/^/INFO  /'
    grep -q "uploadCrashlyticsMappingFile" "$WORK/release.log" && bad "Crashlytics mapping upload ran (must be opt-in)" || ok "no Crashlytics mapping upload (opt-in only)"
    grep -q -- "$TG_TEST_PW" "$WORK/release.log" && bad "password appeared in build output" || ok "password never printed"
  else bad "release APK build with test key"; tail -20 "$WORK/release.log"; fi
fi

rm -f "$A/key.properties" "$KS"
echo "$PASS passed, $FAIL failed."
[ $FAIL = 0 ]
