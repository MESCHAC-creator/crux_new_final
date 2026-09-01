#!/bin/bash
set -e

# Installer Flutter s'il n'existe pas (cache Vercel)
if [ ! -d "$HOME/flutter" ]; then
  git clone https://github.com/flutter/flutter -b stable --depth 1 "$HOME/flutter"
fi

export PATH="HOME/flutter/bin:HOME/flutter/bin:HOME/flutter/bin:PATH"

flutter config --no-analytics
flutter build web --release \
  --dart-define=LIVEKIT_WSS_URL="wss://crux-88fihb12.livekit.cloud" \
  --dart-define=LIVEKIT_SERVER_URL="https://crux-6l6num.sandbox.livekit.io" \
  --dart-define=FIREBASE_PROJECT_ID="crux-3c6be"
