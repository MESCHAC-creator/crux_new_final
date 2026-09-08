#!/usr/bin/env bash
set -e

echo "=== Installation de Flutter ==="
if [ ! -d "flutter" ]; then
  git clone https://github.com/flutter/flutter.git --depth 1 --branch stable
fi

export PATH="$(pwd)/flutter/bin:$PATH"
flutter upgrade
flutter --version
flutter doctor -v

echo "=== Nettoyage & dépendances ==="
flutter clean
flutter pub get

echo "=== Analyse ==="
flutter analyze

echo "=== Build web (release) ==="
flutter build web --release \
  --base-href /crux_new_final/ \
  --dart-define=LIVEKIT_WSS_URL="${LIVEKIT_WSS_URL:-wss://crux-88fihb12.livekit.cloud}" \
  --dart-define=LIVEKIT_TOKEN_SERVER_URL="${LIVEKIT_TOKEN_SERVER_URL:-https://cloud-api.livekit.io/api/sandbox/connection-details}" \
  --dart-define=FIREBASE_PROJECT_ID="${FIREBASE_PROJECT_ID:-crux-3c6be}"

echo "✅ Build completed: $(du -sh build/web | cut -f1)"
