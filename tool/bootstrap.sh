#!/usr/bin/env bash
# Generates the Flutter/Gradle scaffolding matching the installed Flutter SDK, merges it
# UNDER the custom AEGIS android sources (never overwrites them), patches the app module
# (minSdk 26 + Vosk + Firebase), fetches the Vosk model, converts the logo and builds the icon.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
TMP="$(mktemp -d)"

echo "==> Generating Android scaffold"
flutter create --no-pub --platforms=android --org com.aegis --project-name assistant "$TMP/scaffold" >/dev/null
mkdir -p android
cp -rn "$TMP/scaffold/android/." android/ || true
chmod +x android/gradlew || true

echo "==> Patching app module"
if [ -f android/app/build.gradle.kts ]; then
  APP_GRADLE=android/app/build.gradle.kts; KTS=1
else
  APP_GRADLE=android/app/build.gradle; KTS=0
fi
sed -i -E 's/minSdk(Version)?[[:space:]]*=?[[:space:]]*flutter\.minSdkVersion/minSdk = 26/' "$APP_GRADLE"
if ! grep -q "vosk-android" "$APP_GRADLE"; then
  if [ "$KTS" = "1" ]; then
    cat >> "$APP_GRADLE" <<'GRADLE'

dependencies {
    implementation("com.alphacephei:vosk-android:0.3.47")
    implementation("net.java.dev.jna:jna:5.13.0@aar")
}
GRADLE
  else
    cat >> "$APP_GRADLE" <<'GRADLE'

dependencies {
    implementation 'com.alphacephei:vosk-android:0.3.47'
    implementation 'net.java.dev.jna:jna:5.13.0@aar'
}
GRADLE
  fi
fi

echo "==> Firebase (email login + Google sign-in)"
if [ -f android/app/google-services.json ]; then
  python3 - <<'PY'
import os, re

def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()

def write(p, s):
    with open(p, "w", encoding="utf-8") as f:
        f.write(s)

# 1) declare the plugin version in settings.gradle(.kts)
for p in ("android/settings.gradle.kts", "android/settings.gradle"):
    if not os.path.exists(p):
        continue
    s = read(p)
    if "com.google.gms.google-services" in s:
        break
    kts = p.endswith(".kts")
    line = ('    id("com.google.gms.google-services") version "4.4.2" apply false\n'
            if kts else
            '    id "com.google.gms.google-services" version "4.4.2" apply false\n')
    n, c = re.subn(r"(\nplugins\s*\{\n)", lambda m: m.group(1) + line, s, count=1)
    if c:
        write(p, n)
    break

# 2) apply it in the app module
for p in ("android/app/build.gradle.kts", "android/app/build.gradle"):
    if not os.path.exists(p):
        continue
    s = read(p)
    if "com.google.gms.google-services" in s:
        break
    kts = p.endswith(".kts")
    line = ('    id("com.google.gms.google-services")\n'
            if kts else
            '    id "com.google.gms.google-services"\n')
    n, c = re.subn(r'(\n[ \t]*id\(?\s*"dev\.flutter\.flutter-gradle-plugin"\s*\)?[^\n]*\n)',
                   lambda m: m.group(1) + line, s, count=1)
    if c:
        write(p, n)
    break
PY
  grep -q "google-services" android/settings.gradle* && grep -q "google-services" android/app/build.gradle* \
    && echo "Firebase plugin applied" || echo "WARNING: could not patch Firebase plugin (email login will be hidden)"
  python3 - <<'PY'
import json
j = json.load(open("android/app/google-services.json"))
pk = [c["client_info"]["android_client_info"]["package_name"] for c in j["client"]]
print("google-services.json packages:", pk)
if "com.aegis.assistant" not in pk:
    print("WARNING: package com.aegis.assistant is NOT in google-services.json (check spelling!)")
if not any(c.get("oauth_client") for c in j["client"]):
    print("WARNING: no OAuth client in google-services.json (add SHA-1 + enable Google sign-in, then re-download)")
PY
else
  echo "android/app/google-services.json not found - email login will be hidden"
fi

echo "==> Disabling Android lint (not needed for the APK, crashes on some plugin sources)"
for f in android/build.gradle.kts android/build.gradle; do
  if [ -f "$f" ] && ! grep -q "aegis-lint-off" "$f"; then
    cat >> "$f" <<'GRADLE'

// aegis-lint-off
subprojects {
    tasks.configureEach {
        if (name.startsWith("lintVital") || name.startsWith("lintAnalyze") || name.startsWith("lintReport")) {
            enabled = false
        }
    }
}
GRADLE
  fi
done

echo "==> App logo (any .jpg/.jpeg in assets/images is converted to aegis_logo.png)"
LOGO_SRC="$(ls assets/images/*.jpg assets/images/*.jpeg 2>/dev/null | head -n 1 || true)"
if [ -n "$LOGO_SRC" ]; then
  echo "Converting $LOGO_SRC"
  if command -v convert >/dev/null 2>&1; then
    convert "$LOGO_SRC" -resize 1024x1024 assets/images/aegis_logo.png
  elif command -v magick >/dev/null 2>&1; then
    magick "$LOGO_SRC" -resize 1024x1024 assets/images/aegis_logo.png
  else
    python3 -m pip install --quiet --break-system-packages pillow
    LOGO_SRC="$LOGO_SRC" python3 - <<'PY'
import os
from PIL import Image
Image.open(os.environ["LOGO_SRC"]).convert("RGB").resize((1024, 1024)).save("assets/images/aegis_logo.png")
PY
  fi
fi

echo "==> Vosk wake-word model"
MODEL_DIR=android/app/src/main/assets/model
if [ ! -f "$MODEL_DIR/conf/model.conf" ]; then
  mkdir -p android/app/src/main/assets
  curl -fL -o "$TMP/vosk.zip" https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip
  unzip -q "$TMP/vosk.zip" -d "$TMP/vosk"
  rm -rf "$MODEL_DIR"
  mv "$TMP/vosk/vosk-model-small-en-us-0.15" "$MODEL_DIR"
fi

echo "==> Dependencies + launcher icon"
flutter pub get
dart run flutter_launcher_icons
echo "==> Bootstrap done"
