#!/bin/bash
set -e

echo "=== Installation de Flutter ==="

FLUTTER_VERSION="3.32.8"

if [ ! -f "$HOME/flutter/bin/flutter" ]; then
  rm -rf "$HOME/flutter"
  curl -sL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" -o /tmp/flutter.tar.xz
  echo "=== Extraction de Flutter ${FLUTTER_VERSION} ==="
  tar -xf /tmp/flutter.tar.xz -C "$HOME"
fi

# CORRIGÉ (bug #10) : $HOME et $PATH interpolés correctement
export PATH="$HOME/flutter/bin:$PATH"

echo "=== Vérification ==="
command -v flutter
flutter --version

flutter config --no-analytics

echo "=== flutter pub get ==="
flutter pub get

echo "=== Build web release ==="
# CORRIGÉ (bug #12) : WSS URL aligné sur le sandbox ID crux-6l6num
flutter build web --release \
  --base-href /crux_new_final/ \
  --dart-define=LIVEKIT_WSS_URL="wss://crux-6l6num.sandbox.livekit.io" \
  --dart-define=LIVEKIT_SANDBOX_ID="crux-6l6num" \
  --dart-define=LIVEKIT_TOKEN_SERVER_URL="https://cloud-api.livekit.io/api/sandbox/connection-details" \
  --dart-define=FIREBASE_PROJECT_ID="crux-3c6be"

echo "=== Contenu de build/web ==="
ls -la build/web
