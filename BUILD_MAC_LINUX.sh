#!/usr/bin/env bash
set -euo pipefail
# Requires Flutter stable and Android SDK/Android Studio already installed.
cd "$(dirname "$0")"
flutter doctor
flutter create . --platforms=android --project-name=notecraft_ai --org=com.notecraft
python3 scripts/patch_android.py
flutter pub get
flutter build apk --debug
echo "APK created at build/app/outputs/flutter-apk/app-debug.apk"
