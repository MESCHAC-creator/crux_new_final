# CRUX — Flutter Video Conferencing App

## Project Identity
- **App name:** CRUX
- **Type:** Mobile video conferencing (Android-first, iOS stubs present)
- **Bundle ID:** `com.example.crux`
- **Firebase project:** `crux-8aa85`
- **Deep link scheme:** `crux://join/{meetingId}`
- **Payment gateway:** Djamo (25 000 XOF, `https://pay.djamo.com/qxmvj`)
- **Version:** 2.38.0+1 (pubspec) / versionCode 3 (Gradle)

---

## Architecture

```
lib/
├── main.dart                # Entry: Firebase init → DeviceVerification gate → AuthWrapper → deep link setup
├── firebase_options.dart    # Firebase config (projectId: crux-8aa85)
├── config/app_config.dart
├── constants/app_constants.dart
├── routes/app_routes.dart   # Named routes: splash, login, signup, home, meeting, settings, profile…
│
├── models/
│   ├── user_model.dart      # uid, email, name, profileImageUrl, createdAt, isOnline
│   ├── meeting_model.dart   # id, title, description, organizer, organizerId, startTime, endTime,
│   │                        # participants[], channelName, status (scheduled/ongoing/ended),
│   │                        # isRecording, isLocked, recordingUrl, passcode
│   └── meeting_report_model.dart
│
├── providers/               # All ChangeNotifier — wrap with Consumer<> or context.watch<>
│   ├── auth_provider.dart   # wraps AuthService; loading/error states
│   ├── meeting_provider.dart
│   ├── theme_provider.dart  # dark/light, persisted to SharedPreferences
│   ├── locale_provider.dart # 32 languages, persisted
│   └── color_provider.dart  # 8-color accent palette
│
├── services/
│   ├── auth_service.dart          # FirebaseAuth: email/password, Google Sign-In, password reset
│   ├── user_service.dart          # Firestore users collection; base64 photo encoding
│   ├── meeting_service.dart       # Firestore meetings CRUD + presence + chat sub-collections
│   ├── notification_service.dart  # FCM + flutter_local_notifications; engagement reminders
│   ├── smart_notification_scheduler.dart
│   ├── pro_service.dart           # isPro flag, proExpiry, Djamo payment link
│   ├── device_verification_service.dart  # Android 8+ / iOS 14+, root/jailbreak, 100 MB free
│   ├── secure_storage_service.dart       # flutter_secure_storage wrapper
│   ├── localization_service.dart         # language persistence (SharedPreferences)
│   ├── error_handler_service.dart
│   ├── input_validator.dart
│   └── error_logger.dart
│
├── screens/
│   ├── splash_screen.dart
│   ├── login_screen.dart           # 36 KB — email/password auth UI
│   ├── signup_screen.dart          # 26 KB — registration with validation
│   ├── consent_screen.dart         # terms acceptance gate
│   ├── home_screen.dart            # 43 KB — dashboard: meeting list, create/join/share
│   ├── meeting_screen.dart         # lobby before joining call
│   ├── video_call_screen.dart      # 416 KB / 9 496 lines — core WebRTC P2P call
│   │                               # features: mic, camera, screen share (PiP-aware),
│   │                               # chat, reactions, more-options DraggableScrollableSheet
│   ├── guest_join_screen.dart      # deep-link guest join (anonymous Firebase auth)
│   ├── profile_screen.dart         # 36 KB — photo upload, display name, stats
│   ├── setting_screen.dart         # 48 KB — theme, language, color, security settings
│   ├── device_verification_screen.dart
│   ├── privacy_policy_screen.dart
│   ├── terms_screen.dart
│   └── meeting_report_screen.dart
│
├── widgets/
│   ├── custom_button.dart       # loading state + animations
│   ├── custom_textfield.dart
│   ├── meeting_card.dart
│   ├── host_controls_panel.dart # mute all, lock, end meeting
│   ├── meeting_chat.dart
│   ├── reaction_emojis.dart     # 👍 🎉 ❤️ etc.
│   └── premium_button.dart
│
├── theme/
│   ├── colors.dart          # AppColors (primary=#E74C3C, secondary, error, warning, success…)
│   ├── premium_colors.dart
│   └── theme.dart           # Material 3, Poppins font, light + dark themes
│
├── utils/
│   ├── validators.dart
│   ├── app_formatter.dart
│   ├── extensions.dart
│   └── constants.dart
│
└── l10n/
    ├── app_translations.dart  # 214 KB — all strings for 32 locales
    └── *.arb                  # en, fr, es, de, ru + generated per locale
```

---

## Firestore Collections

| Collection | Key fields |
|---|---|
| `users/{uid}` | name, email, photoBase64, isPro, proExpiry, lastPayment, isOnline |
| `meetings/{id}` | title, organizer, organizerId, participants[], status, passcode, isLocked, isRecording |
| `meetings/{id}/presence/{uid}` | userId, name, micOn, cameraOn, timestamp |
| `meetings/{id}/chat/{msgId}` | sender, text, timestamp |

---

## Android Native (Kotlin)

| File | Role |
|---|---|
| `MainActivity.kt` | MethodChannels: `com.example.crux/pip` (PiP 16:9), `com.example.crux/screen_share`; auto-PiP on home button when inCall |
| `CallForegroundService.kt` | Foreground service (mic + camera types); channels: call (LOW) + screen share (HIGH); START_STICKY |

**BroadcastReceiver:** `com.example.crux.STOP_SCREEN_SHARE_FROM_NOTIFICATION` → fires `stopScreenShareFromNotification` to Dart.

---

## Key Packages

| Package | Version | Purpose |
|---|---|---|
| flutter_webrtc | >=1.0.0 <2.0.0 | P2P video/audio; Firebase Firestore as signaling |
| firebase_auth | 5.3.2 | Email/password + Google + anonymous (guests) |
| cloud_firestore | 5.4.3 | Real-time DB + signaling |
| firebase_messaging | 15.1.3 | FCM push notifications |
| flutter_local_notifications | 17.0.0 | Local + engagement reminders |
| provider | 6.1.2 | State management |
| app_links | 6.3.3 | Deep links crux://join/{id} |
| google_sign_in | 6.2.1 | Google OAuth |
| shared_preferences | 2.3.0 | theme, language, color, terms |
| flutter_secure_storage | 9.0.0 | Secure credential storage |
| permission_handler | 11.3.0 | Mic, camera, storage |
| speech_to_text | 7.0.0 | Voice input |
| image_picker | 1.1.2 | Profile photo |
| share_plus | 10.0.0 | Share meeting link |
| google_fonts | 6.2.1 | Poppins (primary font) |
| flutter_animate | 4.2.0 | Animations |
| hive + hive_flutter | 2.2.3 | Local NoSQL (not heavily used yet) |
| device_info_plus | 10.0.0 | Device security check |
| crypto | 3.0.3 | Passcode hashing |
| url_launcher | 6.3.0 | Djamo payment URL |
| timezone | 0.9.4 | Scheduled notifications |

---

## Android Build Config

- **AGP:** 8.3.2 | **Gradle:** 8.7 | **Kotlin:** 2.2.0
- **compileSdk / targetSdk:** 35 | **minSdk:** 24 | **NDK:** 27.0.12077973
- **Signing:** `android/app/crux.keystore` (alias: crux_key, pass: crux2024!)
- **Multidex:** enabled | **Minify/Shrink:** disabled
- **Desugar:** `com.android.tools:desugar_jdk_libs:2.1.4`
- **CI:** GitHub Actions `.github/workflows/build-apk.yml` — builds on `main`, `schac-claude`, `claude/kind-babbage-vqDxq`

---

## Git Branches & Workflow

- **Active dev branch:** `schac-claude`
- **PR #4:** `schac-claude` → `main`
- All changes go to `schac-claude`, never directly to `main`

---

## Security Rules

- Device gate: Android 8+ / iOS 14+, root/jailbreak detection, ≥100 MB free disk
- Meeting passcode: 4–6 digits, hashed with `crypto`
- Input validated via `InputValidator` + `utils/validators.dart`
- Permissions requested at runtime (mic, camera, storage)
- Anonymous Firebase auth for guest join (no account required)

---

## Localization

**Default:** French (`fr`)
**Supported (32):** fr, en, es, de, ru, pt, it, ar, zh, hi, ja, ko, tr, vi, id, nl, pl, uk, sv, ha, yo, sw, am, fa, ro, el, cs, hu, bn, th, mg, wo

---

## Code Conventions

- `StatelessWidget` whenever possible; `const` constructors always
- Provider pattern: `ChangeNotifier` services via `MultiProvider` in `main.dart`
- Screens import services via `Provider.of<XProvider>(context)`
- Meeting ID: 12-char uppercase UUID via `uuid` package
- Error display: `ErrorHandlerService.showError(context, message)`
- All async errors caught, logged via `ErrorLogger`, shown via `ErrorHandlerService`

---

## Skills / Agents Available (Claude Code)

### Built-in Skills (bundled)
| Skill | Trigger | Purpose |
|---|---|---|
| `graphify` | `/graphify` | Codebase → knowledge graph (graph at `graphify-out/`) |
| `deep-research` | `/deep-research` | Multi-source web research report |
| `code-review` | `/code-review` | Diff review for bugs + cleanups |
| `simplify` | `/simplify` | Refactor for clarity/efficiency |
| `verify` | `/verify` | Run app and observe behavior |
| `run` | `/run` | Launch app, screenshot, confirm changes |
| `security-review` | `/security-review` | Security audit of current branch diff |
| `review` | `/review` | PR review |
| `init` | `/init` | Initialize/regenerate CLAUDE.md |
| `loop` | `/loop` | Recurring task on interval |
| `update-config` | `/update-config` | Edit Claude Code settings.json |
| `session-start-hook` | `/session-start-hook` | Setup repo startup hooks |
| `keybindings-help` | `/keybindings-help` | Customize keyboard shortcuts |
| `fewer-permission-prompts` | `/fewer-permission-prompts` | Auto-allowlist read-only tools |
| `claude-api` | `/claude-api` | Anthropic API reference |

### User-created Skills
| Skill | Location | Status |
|---|---|---|
| `graphify` | `~/.claude/skills/graphify/SKILL.md` | ✅ Active — knowledge graph at `graphify-out/` |

> **Note:** `graphify` both bundled AND installed as user skill. User version takes precedence. Knowledge graph (`graphify-out/graph.json`, 1 673 nodes, 2 231 edges, 73 communities) pre-built — queries skip extraction, answer directly.

---

## External Anthropic Agents (platform.claude.ai)

Config: `.claude/agents.json` | Script: `.claude/call_agent.sh`
Requires: `ANTHROPIC_API_KEY` env var (set as GitHub Actions secret + local env)

| Clé | Nom | ID | Rôle |
|---|---|---|---|
| `qa` | QA Optimization Engineer | `agent_015QMiVaMNm8hFVa6kPsFUeN` | Tests, qualité, lint, régression |
| `engineer` | Software Engineer | `agent_01Fp1BYHo58i95pvXAmpjpJg` | Features, architecture, code review |
| `designer` | UI UX Designer | `agent_01QttyRFst44bXDvuk8YvKEG` | UI/UX, design system, composants |
| `architect` | Product Architect | `agent_012ueTDMb36eXpHtxqszhT7p` | Décisions techniques, scalabilité |
| `orchestrator` | Project Orchestrator | `agent_015ieYimCRksmDf4Ab3pp8hF` | Coordination, planification |

**Usage dans Claude Code (via Bash tool):**
```bash
.claude/call_agent.sh qa "Review this Dart code for test coverage: ..."
.claude/call_agent.sh architect "Should we move to Riverpod or keep Provider?"
.claude/call_agent.sh designer "Review this screen layout for UX issues: ..."
```

**Quand les utiliser:**
- `orchestrator` → planification sprint, priorisation features
- `architect` → changements d'architecture, choix techniques majeurs
- `engineer` → implémentation complexe, PR review
- `designer` → nouveaux écrans, design system, accessibilité
- `qa` → avant chaque push, review code critique, tests manquants