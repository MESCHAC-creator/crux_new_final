# CRUX - Changelog

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