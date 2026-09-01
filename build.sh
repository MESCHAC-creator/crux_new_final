#!/bin/bash
set -e

echo "=== HOME: $HOME ==="

# Supprime un éventuel clone incomplet précédent
rm -rf "$HOME/flutter"

# Clone Flutter (avec log visible, sans silencieux)
git clone https://github.com/flutter/flutter -b stable --depth 1 "$HOME/flutter"

# Vérifie que le binaire existe
ls "$HOME/flutter/bin/"

export PATH="HOME/flutter/bin:HOME/flutter/bin:HOME/flutter/bin:PATH"
which flutter || { echo "ERREUR: flutter introuvable dans PATH"; exit 1; }

flutter --version
flutter config --no-analytics
flutter build web --release \
  --dart-define=LIVEKIT_WSS_URL="wss://crux-88fihb12.livekit.cloud" \
  --dart-define=LIVEKIT_TOKEN_SERVER_URL="https://crux-6l6num.sandbox.livekit.io" \
  --dart-define=FIREBASE_PROJECT_ID="crux-3c6be"
