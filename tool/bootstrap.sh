#!/usr/bin/env bash
# Generates the Flutter/Gradle scaffolding matching the installed Flutter SDK, merges it
# UNDER the custom AEGIS android sources (never overwrites them), patches the app module
# (minSdk 26 + Vosk), fetches the Vosk model and builds the launcher icon.
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
