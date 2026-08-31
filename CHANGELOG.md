# CRUX - Changelog

## Version 2.39.0 (2026-08-31)

### 🚀 Major Feature Update - Zoom/Google Meet Parity

This update brings CRUX to feature parity with Zoom and Google Meet, with several enhancements that surpass the competition.

#### ✨ New Features Implemented

**Advanced Virtual Backgrounds**
- Multiple blur levels (light, medium, strong)
- Solid color backgrounds with preset colors
- Gradient backgrounds with predefined combinations
- Image backgrounds with opacity control
- Enhanced background panel UI with pickers

**Smart Reconnection System**
- Automatic reconnection with exponential backoff
- State restoration (mic, camera, screen share, hand raise)
- Network monitoring and status detection
- Maximum 8 reconnection attempts with smart retry logic
- Meeting state persistence across disconnections

**Bandwidth Optimization**
- Data saver mode for low-bandwidth environments
- Dynamic quality adjustment (360p to 1080p)
- Automatic bandwidth monitoring every 10 seconds
- Adaptive video quality based on network conditions
- Data usage statistics and reporting

**Web Keyboard Shortcuts**
- Ctrl/Cmd + D: Toggle microphone
- Ctrl/Cmd + E: Toggle camera
- Ctrl/Cmd + S: Toggle screen share
- Ctrl/Cmd + H: Raise/lower hand
- Ctrl/Cmd + C: Toggle chat
- Ctrl/Cmd + P: Toggle participants
- Ctrl/Cmd + R: Toggle reactions
- Ctrl/Cmd + F: Toggle fullscreen
- Alt + Q: Leave meeting
- Ctrl/Cmd + Shift + M: Mute all (host)

**Enhanced Accessibility**
- Screen reader optimization with semantic labels
- High contrast mode support
- Text scale factor adjustment (1.0x to 2.0x)
- Reduced motion mode for animations
- Audio descriptions for visual elements
- TTS integration for announcements
- Comprehensive accessibility widgets

**Breakout Rooms**
- Create up to 10 breakout rooms
- Auto-assign participants to rooms
- Manual participant movement between rooms
- Timer with countdown broadcast
- Main meeting return functionality
- Room capacity management

**Polls and Q&A**
- Create polls with multiple options
- Single or multiple answer support
- Anonymous voting option
- Real-time results with percentages
- Q&A with upvoting system
- Question archiving and management
- Live poll status tracking

**File Sharing in Chat**
- Share images and documents
- 50MB file size limit
- Firebase Storage integration
- File type validation
- Download and delete functionality
- Meeting-specific file organization

**AI-Powered Noise Reduction**
- Real-time audio noise filtering
- Configurable noise reduction levels
- Echo cancellation
- Automatic gain control
- Noise level monitoring
- Processing statistics

**Recording and Transcription**
- Audio/video meeting recording
- Live captions with speech-to-text
- Real-time transcription display
- Transcription export
- Recording management
- Firebase Storage for recordings

#### 🔧 Technical Improvements

**Build and Deployment**
- Updated version to 2.39.0 (build 241)
- Android build configuration updated
- Web build enabled and optimized
- GitHub Pages deployment workflow configured
- Base href set to `/crux_new_final/`
- Flutter 3.44.9 compatibility

**Dependencies**
- Added `file_picker: ^8.1.6` for file sharing
- Updated existing dependencies for compatibility
- Resolved package conflicts

**Code Quality**
- Fixed Flutter material imports for web compatibility
- Enhanced error handling across all services
- Improved logging and debugging
- Consistent singleton pattern implementation
- Firestore integration for data persistence

#### 📱 Platform Support

**Android**
- API 24+ (Android 7.0+) support maintained
- Enhanced build configuration
- Improved package conflict resolution
- Backup rules for sensitive data

**Web**
- Full browser compatibility (Chrome, Safari, Firefox, Edge)
- Responsive design for mobile/desktop
- Keyboard shortcuts support
- Accessibility optimizations
- Progressive loading for media streams

#### 🎯 Architecture

**New Services**
- `ReconnectionService`: Smart reconnection with state restoration
- `BandwidthService`: Bandwidth optimization and data saver
- `KeyboardShortcutsService`: Web keyboard shortcuts
- `AccessibilityService`: Screen reader and accessibility features
- `BreakoutRoomsService`: Breakout rooms management
- `PollsService`: Polls and Q&A functionality
- `FileSharingService`: File sharing in chat
- `NoiseReductionService`: AI-powered noise reduction
- `RecordingService`: Recording and transcription

**Enhanced Components**
- `VirtualBackgroundMode`: Added color and gradient modes
- `BackgroundPanel`: Enhanced UI with color/gradient pickers
- `VideoBackgroundController`: Improved background management

#### 🌐 Deployment

**GitHub Pages**
- Automatic deployment on push to main/master/schac branches
- Environment variable configuration for LiveKit and Firebase
- Optimized web build with base href
- Secure token management

**Android APK**
- Release build configuration updated
- Version code 7, version name 2.39.0
- ProGuard rules for code obfuscation
- Signing configuration maintained

---

## Version 2.38.3 (2026-08-30)

### 🎨 Améliorations UI/UX
- **Palette de couleurs optimisée** : Style professionnel inspiré de Zoom Web App
- **Bordures affinées** : Moins colorées, plus subtiles et professionnelles
- **Cartes améliorées** : Coins arrondis (12px) et ombres douces
- **Inputs modernisés** : Coins arrondis (8px) et meilleure visibilité
- **Switchs améliorés** : Outline de bordure ajouté pour meilleure visibilité

### 🔧 Corrections techniques
- **Flutter analyze** : 0 erreurs (tous les problèmes résolus)
- **LiveKit screen share** : Mise à jour de l'API setScreenShareEnabled
- **SpeakerMode** : Correction des références indéfinies
- **getTrack/TrackSource** : Mise à jour pour compatibilité LiveKit
- **@override annotations** : Ajout des annotations manquantes
- **Code cleanup** : Suppression des éléments non utilisés

### 🚀 Déploiement
- **GitHub Pages** : Workflow configuré pour déploiement automatique
- **Build web** : Base href configuré pour `/crux_new_final/`
- **Firebase Hosting** : Remplacé par GitHub Pages (comme demandé)
- **Android conflicts** : Résolution des conflits de packages lors de l'installation

### 📱 Android
- **Version** : 2.38.3 (versionCode 6)
- **Backup rules** : Fichier backup_rules.xml créé pour protéger les données sensibles
- **Package conflicts** : Résolution avec authorities providers uniques
- **Installations** : Plus de conflits lors de la mise à jour

### 🔒 Sécurité
- **Backend** : 0 vulnérabilités détectées (npm audit)
- **Firebase** : Permissions Firestore conservées
- **Data protection** : Exclusion des tokens sensibles du backup

### 🌐 Web
- **Join page** : Page web créée pour rejoindre les réunions directement
- **Accessibilité** : Interface responsive pour mobile/desktop
- **Browser support** : Chrome, Safari, Firefox, Edge compatibles

## Version 2.38.2 (2026-08-29)

### ✨ Nouvelles fonctionnalités
- **Architecture modulaire** : Système de layout de conférence avancé
- **Speaker mode** : Gestion intelligente des orateurs actifs
- **Live feed** : Flux vidéo pour participants supplémentaires
- **Réactions** : Système d'emojis animés
- **Network stats** : Overlay statistiques réseau en temps réel
- **Contextual controls** : Barre de contrôles auto-masquante

### 🏗️ Architecture
- **Conference layout engine** : Moteur de layout responsive
- **Meeting state provider** : Gestion d'état centralisée
- **Animation system** : Animations 120fps optimisées
- **Participant grid** : Grille virtuelle pour 10,000 participants

### 🎨 UI/UX
- **Design professionnel** : Style "TikTok Live" / Zoom
- **Animations fluides** : Transitions douces et naturelles
- **Thème Obsidian Mono** : Palette de couleurs unifiée

## Version 2.38.1 (2026-08-28)

### 🎯 Fonctionnalités de base
- **Audio/Vidéo** : Streaming bidirectionnel WebRTC
- **Partage d'écran** : Support LiveKit screen share
- **Chat** : Messagerie en temps réel
- **Participants** : Liste avec indicateurs de statut
- **Contrôles** : Micro, caméra, quitter, lever la main
- **Permissions** : Gestion des permissions caméra/micro

### 🔧 Infrastructure
- **Firebase** : Auth, Firestore, Cloud Functions
- **LiveKit** : Streaming temps réel
- **Token server** : Génération JWT sécurisée
- **Rate limiting** : Protection contre abus

### 📱 Plateformes
- **Android** : Support API 24+ (Android 7.0+)
- **iOS** : Support prévu
- **Web** : Support complet navigateurs modernes

---

## Notes de migration

### De 2.38.2 à 2.38.3
- Aucune action requise de l'utilisateur
- Mise à jour automatique recommandée
- Les préférences utilisateur sont préservées

### De 2.38.1 à 2.38.2
- Nouveaux modules ajoutés (backward compatible)
- Performance améliorée pour grandes réunions
- UI actualisée sans rupture de l'expérience

---

## Roadmap

### Prochaines versions (2.39.x)
- [ ] Sous-titres automatiques multi-langues
- [ ] Arrière-plans virtuels avec IA
- [ ] Salles de sous-groupes (breakout rooms)
- [ ] Tableau blanc collaboratif
- [ ] Sondages en temps réel
- [ ] Enregistrement cloud
- [ ] Intégration calendrier
- [ ] Mode faible luminosité

### Versions futures (3.0.x)
- [ ] Réduction de bruit par IA
- [ ] Reconnexion intelligente avancée
- [ ] Mode économie de données
- [ ] Accessibilité étendue (lecteurs d'écran)
- [ ] Support tablette optimisé
- [ ] Interface pour personnes âgées