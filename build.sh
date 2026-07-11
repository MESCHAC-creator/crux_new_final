#!/usr/bin/env bash
set -e

mkdir -p build/outputs

echo "=== FLUTTER CLEAN & PUB GET ==="
flutter clean
flutter pub get

echo "=== GENERATE APP ICONS ==="
flutter pub run flutter_launcher_icons:main

echo "=== FLUTTER BUILD APK (release) ==="
flutter build apk --release --no-tree-shake-icons 2>&1 | tail -300

APK=$(find build/app/outputs/flutter-apk -name "app-release.apk" 2>/dev/null | head -1)
[ -z "$APK" ] && APK=$(find build/app/outputs/apk -name "app-release.apk" 2>/dev/null | head -1)
[ -z "$APK" ] && APK=$(find . -name "app-release.apk" ! -path "*/.pub-cache/*" ! -path "*/debug/*" 2>/dev/null | head -1)

if [ -z "$APK" ]; then
  echo "❌ APK not found — listing build/app/outputs/:"
  find build/app/outputs 2>/dev/null || echo "(empty)"
  exit 1
fi
cp "$APK" build/outputs/crux-release.apk
echo "✅ APK: $(du -sh build/outputs/crux-release.apk | cut -f1) — source: $APK"

echo "=== FLUTTER BUILD AAB (release) ==="
flutter build appbundle --release --no-tree-shake-icons 2>&1 | tail -300

AAB=$(find build/app/outputs/bundle -name "app-release.aab" 2>/dev/null | head -1)
[ -z "$AAB" ] && AAB=$(find . -name "app-release.aab" ! -path "*/.pub-cache/*" 2>/dev/null | head -1)

if [ -z "$AAB" ]; then
  echo "❌ AAB not found — listing build/app/outputs/:"
  find build/app/outputs 2>/dev/null || echo "(empty)"
  exit 1
fi
cp "$AAB" build/outputs/crux-release.aab
echo "✅ AAB: $(du -sh build/outputs/crux-release.aab | cut -f1) — source: $AAB"
