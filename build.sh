#!/bin/bash
set -e

FLUTTER_VERSION="3.24.5"

if [ ! -f "$HOME/flutter/bin/flutter" ]; then
  rm -rf "$HOME/flutter"
  curl -sL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" -o /tmp/flutter.tar.xz
  tar -xf /tmp/flutter.tar.xz -C "$HOME"
fi

export PATH="HOME/flutter/bin:HOME/flutter/bin:HOME/flutter/bin:PATH"
flutter --version
flutter config --no-analytics
flutter build web --release \
  --dart-define=LIVEKIT_WSS_URL="wss://crux-88fihb12.livekit.cloud" \
  --dart-define=LIVEKIT_TOKEN_SERVER_URL="https://crux-6l6num.sandbox.livekit.io" \
  --dart-define=FIREBASE_PROJECT_ID="crux-3c6be"
