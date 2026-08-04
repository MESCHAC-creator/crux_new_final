// backend/server.js
// v2.0.0 — Ajout : authentification Firebase obligatoire, rate limiting, validation d'identité

require('dotenv').config();

const express = require('express');
const cors = require('cors');
const rateLimit = require('express-rate-limit');
const admin = require('firebase-admin');
const { AccessToken } = require('livekit-server-sdk');

// ── Firebase Admin SDK ───────────────────────────────────────────────────
if (!admin.apps.length) {
  // En production : utiliser GOOGLE_APPLICATION_CREDENTIALS ou ADC
  // En dev local : firebase emulators ou service account JSON
  admin.initializeApp();
}

const app = express();

// ── CORS ─────────────────────────────────────────────────────────────────
const allowedOrigins = (process.env.ALLOWED_ORIGINS || '').split(',').filter(Boolean);

app.use(
  cors({
    origin: (origin, callback) => {
      // Autoriser les apps mobiles (pas d'origine) + origins whitelistées
      if (!origin) return callback(null, true);
      if (
        !allowedOrigins.length || // développement : tout autoriser si non défini
        allowedOrigins.some((o) => origin.startsWith(o.replace('/*', '')))
      ) {
        return callback(null, true);
      }
      callback(new Error(`CORS: origin ${origin} not allowed`));
    },
    methods: ['GET', 'OPTIONS'],
    allowedHeaders: ['Authorization', 'Content-Type'],
  })
);

app.use(express.json({ limit: '10kb' }));

// ── Configurations ────────────────────────────────────────────────────────
const LIVEKIT_API_KEY = process.env.LIVEKIT_API_KEY;
const LIVEKIT_API_SECRET = process.env.LIVEKIT_API_SECRET;
const PORT = process.env.PORT || 3000;
const TOKEN_TTL_SECONDS = parseInt(process.env.TOKEN_TTL_SECONDS || '86400', 10);

if (!LIVEKIT_API_KEY || !LIVEKIT_API_SECRET) {
  console.error('❌ LIVEKIT_API_KEY et LIVEKIT_API_SECRET sont requis');
  process.exit(1);
}

// ── Rate Limiting ─────────────────────────────────────────────────────────
// Limite globale : 100 req/min par IP
const globalLimiter = rateLimit({
  windowMs: 60_000,
  max: 100,
  message: { error: 'Trop de requêtes, réessayez dans une minute' },
  standardHeaders: true,
  legacyHeaders: false,
});

// Limite spécifique pour les tokens : 30 tokens/min par IP
const tokenLimiter = rateLimit({
  windowMs: 60_000,
  max: 30,
  message: { error: 'Limite de génération de tokens atteinte' },
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) => req.user?.uid || req.ip, // par utilisateur Firebase si auth
});

app.use(globalLimiter);

// ── Middleware : vérifier le token Firebase ID ────────────────────────────
const verifyFirebaseToken = async (req, res, next) => {
  const authHeader = req.headers.authorization;

  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({
      error: 'Authentification requise',
      hint: 'Fournissez un Bearer token Firebase dans le header Authorization',
    });
  }

  const idToken = authHeader.slice(7); // Retire "Bearer "

  try {
    const decodedToken = await admin.auth().verifyIdToken(idToken, true); // checkRevoked = true
    req.user = decodedToken;
    next();
  } catch (err) {
    const message =
      err.code === 'auth/id-token-revoked'
        ? 'Session révoquée, reconnectez-vous'
        : err.code === 'auth/id-token-expired'
        ? 'Session expirée, reconnectez-vous'
        : 'Token invalide';

    return res.status(401).json({ error: message, code: err.code });
  }
};

// ── Health check ──────────────────────────────────────────────────────────
app.get('/', (req, res) => {
  res.json({
    status: 'ok',
    service: 'CRUX LiveKit Token Server',
    version: '2.0.0',
    endpoints: {
      health: 'GET /',
      ping: 'GET /ping',
      token: 'GET /livekit-token (auth required)',
    },
  });
});

app.get('/ping', (req, res) => {
  res.json({ status: 'ok', ts: Date.now() });
});

// ── LiveKit token endpoint ────────────────────────────────────────────────
// Protégé : Firebase auth obligatoire + rate limit
app.get('/livekit-token', verifyFirebaseToken, tokenLimiter, async (req, res) => {
  const { room, identity, name, isHost } = req.query;

  // Validation des paramètres requis
  if (!room || !identity || !name) {
    return res.status(400).json({
      error: 'Paramètres manquants',
      required: ['room', 'identity', 'name'],
      optional: ['isHost'],
    });
  }

  // Validation de longueur
  if (room.length > 100 || identity.length > 100 || name.length > 100) {
    return res.status(400).json({ error: 'Paramètres trop longs (max 100 caractères)' });
  }

  // SÉCURITÉ : l'identité doit correspondre à l'UID Firebase authentifié
  if (identity !== req.user.uid) {
    return res.status(403).json({
      error: 'Identité non autorisée',
      hint: "L'identité doit correspondre à votre UID Firebase",
    });
  }

  const hostGrant = isHost === 'true';

  try {
    const at = new AccessToken(LIVEKIT_API_KEY, LIVEKIT_API_SECRET, {
      identity,
      name: decodeURIComponent(name),
      ttl: TOKEN_TTL_SECONDS,
    });

    at.addGrant({
      roomJoin: true,
      room: decodeURIComponent(room),
      canPublish: true,
      canSubscribe: true,
      canPublishData: true,
      canUpdateOwnMetadata: true,
      // Droits hôte uniquement si demandé
      roomAdmin: hostGrant,
      roomCreate: hostGrant,
      roomRecord: hostGrant,
    });

    const token = await at.toJwt();

    console.log(`✅ Token généré : user=${identity} room=${room} host=${hostGrant}`);

    return res.json({
      token,
      room: decodeURIComponent(room),
      identity,
      isHost: hostGrant,
      expiresIn: TOKEN_TTL_SECONDS,
    });
  } catch (err) {
    console.error('❌ Token generation error:', err);
    return res.status(500).json({ error: 'Erreur lors de la génération du token' });
  }
});

// ── 404 handler ───────────────────────────────────────────────────────────
app.use((req, res) => {
  res.status(404).json({ error: `Route ${req.method} ${req.path} introuvable` });
});

// ── Error handler global ──────────────────────────────────────────────────
app.use((err, req, res, _next) => {
  if (err.message?.includes('CORS')) {
    return res.status(403).json({ error: err.message });
  }
  console.error('Unhandled error:', err);
  res.status(500).json({ error: 'Erreur interne du serveur' });
});

app.listen(PORT, () => {
  console.log(`🚀 CRUX LiveKit Token Server v2.0 démarré sur le port ${PORT}`);
  console.log(`   Authentification Firebase : ACTIVÉE`);
  console.log(`   Rate limiting : 30 tokens/min/utilisateur`);
});
