#!/usr/bin/env bash
set -e

echo "=== Installation de Flutter ==="
git clone https://github.com/flutter/flutter.git --depth 1 || true
export PATH="$(pwd)/flutter/bin:$PATH"
flutter channel stable
flutter upgrade

echo "=== Extraction de Flutter 3.24.5 ==="
flutter version

echo "=== Vérification ==="
flutter doctor -v

echo "=== Flutter CLEAN & PUB GET ==="
flutter clean
flutter pub get

echo "=== Analyse du projet ==="
flutter analyze

echo "=== Flutter BUILD WEB (release) ==="
flutter build web --release \
  --base-href /crux_new_final/ \
  --dart-define=LIVEKIT_WSS_URL="${LIVEKIT_WSS_URL:-wss://crux-88fihb12.livekit.cloud}" \
  --dart-define=LIVEKIT_TOKEN_SERVER_URL="${LIVEKIT_TOKEN_SERVER_URL:-https://crux-6l6num.sandbox.livekit.io}" \
  --dart-define=FIREBASE_PROJECT_ID="${FIREBASE_PROJECT_ID:-crux-3c6be}" \
  --dart-define=APP_BASE_URL="${APP_BASE_URL:-https://schac-hub.github.io/crux_new_final/}"

echo "✅ Web build completed: $(du -sh build/web | cut -f1)"
ls -lh build/web/index.html
