# Guide de Déploiement du Backend LiveKit Token Server

## 📋 Vue d'ensemble

Le backend LiveKit Token Server est maintenant configuré et prêt à être déployé. Ce serveur gère:
- L'authentification Firebase
- La génération de tokens LiveKit sécurisés
- La gestion des réunions via Firestore
- Le contrôle d'accès et la validation des participants

## 🔧 Pré-requis

### 1. Clés LiveKit
- Récupérez votre `LIVEKIT_API_KEY` depuis votre dashboard LiveKit
- Récupérez votre `LIVEKIT_API_SECRET` depuis votre dashboard LiveKit

### 2. Firebase Service Account
- Allez dans la console Firebase > Paramètres du projet > Comptes de service
- Cliquez sur "Générer une nouvelle clé privée"
- Téléchargez le fichier JSON
- Convertissez le JSON en une seule ligne pour l'environnement

### 3. Options de Déploiement

Vous avez plusieurs options pour déployer le backend:

## 🚀 Option 1: Vercel (Recommandé pour la simplicité)

### Étape 1: Installer Vercel CLI
```bash
npm install -g vercel
```

### Étape 2: Configurer les variables d'environnement

Dans le dossier `backend`, créez ou modifiez le fichier `.env`:

```env
LIVEKIT_API_KEY=votre_clé_api_livekit
LIVEKIT_API_SECRET=votre_secret_api_livekit
PORT=3000
TOKEN_TTL_SECONDS=3600
ALLOWED_ORIGINS=
FIREBASE_SERVICE_ACCOUNT={"type":"service_account","project_id":"crux-3c6be",...}
```

### Étape 3: Déployer
```bash
cd backend
vercel
```

Suivez les instructions:
- Sélectionnez "Create" pour un nouveau projet
- Ajoutez les variables d'environnement demandées
- Le déploiement sera automatique

### Étape 4: Notez l'URL
Vercel vous donnera une URL comme: `https://crux-token-server.vercel.app`

## 🚀 Option 2: Railway (Recommandé pour la production)

### Étape 1: Créer un compte Railway
Allez sur [railway.app](https://railway.app) et créez un compte

### Étape 2: Importer le projet
1. Cliquez sur "New Project"
2. Sélectionnez "Deploy from GitHub repo"
3. Choisissez votre repository
4. Sélectionnez le dossier `backend`

### Étape 3: Configurer les variables d'environnement
Dans les settings du projet Railway, ajoutez:

- `LIVEKIT_API_KEY` = votre clé API LiveKit
- `LIVEKIT_API_SECRET` = votre secret API LiveKit
- `PORT` = 3000
- `TOKEN_TTL_SECONDS` = 3600
- `ALLOWED_ORIGINS` = (vide pour aucune restriction)
- `FIREBASE_SERVICE_ACCOUNT` = votre JSON Firebase en une ligne

### Étape 4: Déployer
Railway déploiera automatiquement. L'URL sera disponible dans le dashboard.

## 🚀 Option 3: Heroku

### Étape 1: Installer Heroku CLI
```bash
npm install -g heroku
```

### Étape 2: Créer l'application
```bash
cd backend
heroku create crux-token-server
```

### Étape 3: Configurer les variables
```bash
heroku config:set LIVEKIT_API_KEY=votre_clé
heroku config:set LIVEKIT_API_SECRET=votre_secret
heroku config:set PORT=3000
heroku config:set TOKEN_TTL_SECONDS=3600
heroku config:set ALLOWED_ORIGINS=
heroku config:set FIREBASE_SERVICE_ACCOUNT='{"type":"service_account",...}'
```

### Étape 4: Déployer
```bash
git push heroku main
```

## 🔗 Mettre à jour l'application Flutter

Une fois le backend déployé, mettez à jour votre application:

### 1. GitHub Actions Secrets
Dans votre repository GitHub, ajoutez ces secrets:

- `LIVEKIT_WSS_URL` = `wss://votre-serveur-livekit.cloud`
- `LIVEKIT_TOKEN_SERVER_URL` = `https://votre-backend-url.com`
- `FIREBASE_PROJECT_ID` = `crux-3c6be`
- `APP_BASE_URL` = `https://votre-app.web.app`

### 2. Configuration locale
Pour les tests locaux, définissez les variables d'environnement:

```bash
flutter run --dart-define=LIVEKIT_TOKEN_SERVER_URL=https://votre-backend-url.com
```

## ✅ Vérification du déploiement

Une fois déployé, testez le backend:

### Health Check
```bash
curl https://votre-backend-url.com/ping
```

Devrait retourner:
```json
{
  "status": "ok",
  "service": "crux-token-server",
  "timestamp": 1234567890
}
```

### Test de génération de token
```bash
curl -H "Authorization: Bearer YOUR_FIREBASE_TOKEN" \
  "https://votre-backend-url.com/api/livekit-token?room=test&identity=testuser&name=Test&isHost=false"
```

## 🔒 Sécurité

- **Ne commitez jamais** le fichier `.env` dans le repository
- Utilisez toujours des variables d'environnement en production
- Le token TTL est limité à minimum 5 minutes (300s) par défaut
- Le backend utilise rate limiting pour éviter les abus
- L'authentification Firebase est obligatoire pour toutes les requêtes

## 🐛 Dépannage

### Erreur: "Authentification Firebase requise"
- Vérifiez que vous passez le token Firebase dans le header `Authorization: Bearer <token>`
- Assurez-vous que l'utilisateur est connecté dans l'application Flutter

### Erreur: "Identité non autorisée"
- Vérifiez que `identity` dans la requête correspond à `uid` Firebase
- L'identité doit être strictement égale à l'UID Firebase authentifié

### Erreur: "Droits host refusés"
- Vérifiez que l'utilisateur est organisateur ou co-host dans Firestore
- Assurez-vous que la réunion existe dans la collection `meetings`

### Erreur de connexion LiveKit
- Vérifiez que `LIVEKIT_API_KEY` et `LIVEKIT_API_SECRET` sont corrects
- Assurez-vous que votre serveur LiveKit est accessible

## 📊 Monitoring

Une fois en production, surveillez:
- Les logs du backend (via Vercel/Railway/Heroku dashboard)
- Les erreurs d'authentification Firebase
- Les taux de génération de tokens
- Les erreurs de connexion LiveKit

## 🔄 Mise à jour

Pour mettre à jour le backend:
1. Modifiez le code dans `backend/server.js`
2. Poussez les changements sur GitHub
3. La plateforme de déploiement déploiera automatiquement

## 📞 Support

Si vous rencontrez des problèmes:
1. Vérifiez les logs du backend
2. Testez avec `curl` pour isoler le problème
3. Vérifiez les règles Firestore si vous avez des erreurs de permission
4. Consultez la documentation LiveKit et Firebase

---

**Note importante**: L'application Flutter a maintenant un mécanisme de fallback. Si le backend n'est pas disponible, elle utilisera directement Firestore. Une fois le backend déployé, toutes les fonctionnalités seront plus sécurisées et performantes.
