# CRUX — Premium Video Conferencing App

CRUX is a high-performance, secure mobile video conferencing application built with Flutter. It supports real-time communication using WebRTC and LiveKit, with a robust backend powered by Firebase.

## 🚀 Features

- **High-Quality Video/Audio:** Powered by LiveKit & WebRTC for low-latency P2P and hosted calls.
- **Secure Meetings:** End-to-end encryption, passcode protection (4-6 digits), and secure device verification.
- **Deep Linking:** Join meetings instantly via `crux://join/{meetingId}` or HTTPS (https://crux-3c6be.web.app/join/{id}).
- **Real-time Interaction:** In-meeting chat (public/private), hand raising, and reaction emojis.
- **Accessibility & AI:** Speech-to-Text (STT) for live transcriptions and Text-to-Speech (TTS) for a voice-guided assistant.
- **Multi-language Support:** 32 supported locales including French (default), English, Spanish, Russian, and several African languages (Wolof, Hausa, Yoruba, Malagasy).
- **Customization:** 8-color accent palette and persistent Dark/Light mode.
- **Meeting Tools:** Real-time meeting notes saved to history and automated meeting reports.

## 🛠 Tech Stack

- **Frontend:** Flutter (Material 3)
- **State Management:** Provider
- **Backend:** Firebase (Auth, Firestore, Messaging, Storage)
- **Video Infrastructure:** LiveKit / WebRTC
- **Native Integration:** Kotlin (Android) for Picture-in-Picture (PiP) and Foreground Services.

## 📦 Getting Started

### Prerequisites

- Flutter SDK (>=3.10.0)
- Android Studio / VS Code
- Firebase Project setup
- LiveKit Server instance

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/your-repo/crux.git
   cd crux
   ```

2. **Install dependencies:**
   ```bash
   flutter pub get
   ```

3. **Configure Firebase:**
   - Add your `google-services.json` to `android/app/`.
   - Update `lib/firebase_options.dart` if necessary.

4. **Environment Setup:**
   - Copy `.env.example` to `.env` and fill in your LiveKit and Firebase credentials.

5. **Run the app:**
   ```bash
   flutter run
   ```

## 🏗 Architecture

The project follows a modular service-based architecture:

- `lib/services/`: Core logic (Auth, Meeting, Notifications, LiveKit).
- `lib/providers/`: State management for UI updates.
- `lib/screens/`: UI views (Login, Home, Meeting Lobby, Video Call).
- `lib/widgets/`: Reusable UI components.
- `lib/theme/`: Centralized styling and color schemes.

## 🔐 Security & Compliance

- **Device Gate:** Mandatory security checks (root/jailbreak detection, disk space, OS version).
- **Authentication:** Supports Google Sign-In, Email/Password, and Anonymous guest access.
- **Permissions:** Runtime requests for Microphone, Camera, and Storage.

## 🌍 Localization

CRUX is localized into 32 languages. Translations are managed in `lib/l10n/app_translations.dart` and through `.arb` files.

---

Developed with ❤️ for a seamless conferencing experience.
