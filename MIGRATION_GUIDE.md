# 🚀 CRUX Premium - Migration Guide

## Après la fusion de la branche `refactor/premium-features`

### 1. Remplacer main.dart

```bash
# Old main.dart → backup
mv lib/main.dart lib/main_old.dart

# New main.dart → active
mv lib/main_new.dart lib/main.dart
```

### 2. Créer .env local

Copie `.env.example` et remplis tes credentials:

```bash
cp .env.example .env.local
```

Contenu de `.env.local`:
```env
AGORA_APP_ID=<your_agora_app_id>
AGORA_APP_CERTIFICATE=<your_agora_app_certificate>
AGORA_TOKEN_URL=https://your-agora-token-server.com/rtc
FIREBASE_PROJECT_ID=crux-8aa85
ENVIRONMENT=production
```

### 3. Dependencies

```bash
flutter pub get
```

### 4. Update pubspec.yaml (si nécessaire)

Les dépendances suivantes sont **déjà dans pubspec.yaml**:
- ✅ firebase_messaging
- ✅ dio
- ✅ flutter_dotenv
- ✅ flutter_animate
- ✅ google_fonts
- ✅ hive / hive_flutter
- ✅ provider
- ✅ permission_handler

### 5. Configuration Agora Token Server

Pour que la vidéoconférence fonctionne, tu dois avoir un serveur de tokens Agora.

**Option A: Use Agora's Token Generation Service**
```
https://github.com/AgoraIO/Tools/tree/master/DynamicKey/AgoraDynamicKey
```

**Option B: Hosted Solution**
```
Configure URL dans .env.local: AGORA_TOKEN_URL
```

### 6. Points Clés

#### Waiting Room Flow
```
Participant rejoins → WaitingRoomScreen
Host voit dans panel → "Admit All" ou "Admit" individuel
Participant → MeetingScreenNew
```

#### Host Controls
- **Recording** : Start/Stop (auto-saved to Firebase Storage)
- **Mute All** : Un clic pour couper tous les micros
- **Reactions** : Emoji (👍❤️😂😮👏🙌)
- **End Meeting** : Termine pour tous

#### Languages
Changeable via Settings → Language selector
Persistent via SharedPreferences

### 7. File Structure

```
lib/
├── main_new.dart         ← Rename to main.dart
├── config/
│   └── app_config.dart   ← NEW (externalized config)
├── services/
│   ├── localization_service.dart  ← NEW
│   └── (autres services)
├── screens/
│   ├── login_screen_new.dart      ← REMPLACE login_screen.dart
│   ├── home_screen_new.dart       ← REMPLACE home_screen.dart
│   ├── meeting_screen_new.dart    ← REMPLACE meeting_screen.dart
│   ├── waiting_room_screen.dart   ← NEW
│   └── (autres écrans)
├── widgets/
│   ├── premium_button.dart        ← NEW
│   ├── reaction_emojis.dart       ← NEW
│   ├── host_controls_panel.dart   ← NEW
│   ├── meeting_chat.dart          ← NEW
│   └── (autres widgets)
├── l10n/
│   ├── app_en.arb  ← NEW (5 langues)
│   ├── app_fr.arb
│   ├── app_es.arb
│   ├── app_ru.arb
│   └── app_de.arb
└── theme/
    └── premium_colors.dart        ← NEW (palette pro)
```

### 8. Testing Checklist

- [ ] `flutter pub get` sans erreurs
- [ ] Build APK debug : `flutter build apk`
- [ ] Tester sur device Android réel
- [ ] S'authentifier → HomeScreen
- [ ] Créer une réunion → WaitingRoom
- [ ] Host accepte participant → MeetingScreen
- [ ] Test mic/camera/screen share
- [ ] Test réactions emojis
- [ ] Tester host controls (mute all, recording)
- [ ] Tester changement de langue

### 9. Firebase Setup

**Firestore Collections nécessaires:**

```
meetings/
├── {meetingId}
│   ├── title
│   ├── description
│   ├── organizerId
│   ├── participants[]
│   ├── startTime
│   ├── status (scheduled, active, ended)
│   └── createdAt

waiting_room/
├── {meetingId}
│   └── {userId}
│       ├── name
│       ├── status (pending, admitted, rejected)
│       └── requestedAt

recordings/
├── {meetingId}
│   ├── hostId
│   ├── videoUrl
│   ├── duration
│   └── createdAt
```

### 10. Troubleshooting

**❌ Agora token error**
- Vérifie `.env.local` avec credentials correctes
- Vérifie `AGORA_TOKEN_URL` accessible
- Check logs : `flutter run -v`

**❌ Firebase init error**
- Vérifie `google-services.json` dans `android/app/`
- Vérifie credentials Firebase

**❌ Language not changing**
- Clear app cache : `flutter clean`
- Rebuilds : `flutter pub get`

### 11. Next Steps (Future)

Après cette migration, les futures features:

1. **Recording to Firebase Storage** (1h)
2. **Screen sharing implementation** (2h)
3. **Chat persistence to Firestore** (1.5h)
4. **Meeting history** (1h)
5. **Notifications** (2h)

### 12. Support

Pour les questions:
- Check les logs: `flutter run -v`
- Verify `.env.local` configuration
- Check Firebase console pour Firestore rules

---

**Happy coding! 🚀**
