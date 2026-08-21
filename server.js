require('dotenv').config();

const express = require('express');
const cors = require('cors');
const path = require('path');
const rateLimit = require('express-rate-limit');
const admin = require('firebase-admin');
const { AccessToken } = require('livekit-server-sdk');

const app = express();

// ============================================================
// Firebase Admin Initialization
// ============================================================
if (!admin.apps.length) {
  if (process.env.FIREBASE_SERVICE_ACCOUNT) {
    const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
  } else {
    admin.initializeApp();
  }
}
const db = admin.firestore();

// ============================================================
// CORS — restriction des origines autorisées
// ============================================================
const allowedOrigins = (process.env.ALLOWED_ORIGINS || '')
  .split(',')
  .filter(Boolean);

app.use(
  cors({
    origin: (origin, callback) => {
      if (!origin) {
        return callback(null, true);
      }
      if (!allowedOrigins.length) {
        return callback(null, true);
      }
      const allowed = allowedOrigins.some((item) =>
        origin.startsWith(item.replace('/*', ''))
      );
      if (allowed) {
        return callback(null, true);
      }
      return callback(new Error(`CORS blocked: ${origin}`));
    },
    methods: ['GET', 'OPTIONS'],
    allowedHeaders: ['Authorization', 'Content-Type'],
  })
);

app.use(express.json({ limit: '10kb' }));

// ============================================================
// Configuration
// ============================================================
const LIVEKIT_API_KEY = process.env.LIVEKIT_API_KEY;
const LIVEKIT_API_SECRET = process.env.LIVEKIT_API_SECRET;
const PORT = process.env.PORT || 3000;
const TOKEN_TTL_SECONDS = Number(process.env.TOKEN_TTL_SECONDS || 3600);

if (!LIVEKIT_API_KEY || !LIVEKIT_API_SECRET) {
  console.error('LIVEKIT_API_KEY ou LIVEKIT_API_SECRET manquant');
  process.exit(1);
}

// ============================================================
// Rate limiting global
// ============================================================
app.use(
  rateLimit({
    windowMs: 60000,
    max: 100,
    standardHeaders: true,
    legacyHeaders: false,
  })
);

const tokenLimiter = rateLimit({
  windowMs: 60000,
  max: 30,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) => req.user?.uid || req.ip,
});

// ============================================================
// Firebase Authentication Middleware
// ============================================================
async function verifyFirebaseToken(req, res, next) {
  const header = req.headers.authorization;
  if (!header || !header.startsWith('Bearer ')) {
    return res.status(401).json({
      error: 'Authentification Firebase requise',
    });
  }

  const token = header.substring(7);
  try {
    const decoded = await admin.auth().verifyIdToken(token, true);
    req.user = decoded;
    next();
  } catch (error) {
    console.error('Firebase auth error:', error.code);
    return res.status(401).json({
      error: 'Token Firebase invalide',
    });
  }
}

// ============================================================
// Vérifier si un utilisateur est l'organisateur d'une réunion
// ============================================================
async function isMeetingOrganizer(meetingId, uid) {
  try {
    const doc = await db.collection('meetings').doc(meetingId).get();
    if (!doc.exists) return false;
    return doc.data().organizerId === uid;
  } catch (_) {
    return false;
  }
}

// ============================================================
// Health
// ============================================================
app.get('/', (req, res) => {
  res.json({
    status: 'ok',
    message: 'CRUX Server running',
    version: '2.1.0-secured',
    endpoints: {
      health: 'GET /',
      ping: 'GET /ping',
      token: 'GET /livekit-token (Bearer Firebase ID token required)',
    },
  });
});

app.get('/ping', (req, res) => {
  res.json({
    status: 'ok',
    service: 'crux-server',
    timestamp: Date.now(),
  });
});

// ============================================================
// LiveKit token — AUTHENTIFIÉ et sécurisé
// ============================================================
app.get(
  '/livekit-token',
  verifyFirebaseToken,
  tokenLimiter,
  async (req, res) => {
    try {
      const { room, identity, name, isHost } = req.query;

      if (!room || !identity || !name) {
        return res.status(400).json({
          error: 'Paramètres manquants',
          required: ['room', 'identity', 'name'],
        });
      }

      if (room.length > 100 || identity.length > 100 || name.length > 100) {
        return res.status(400).json({
          error: 'Paramètres trop longs',
        });
      }

      // Validation critique : identity === uid Firebase authentifié
      if (identity !== req.user.uid) {
        return res.status(403).json({
          error: 'Identité non autorisée',
        });
      }

      // Droit host : VÉRIFIÉ en base (organisateur de la réunion),
      // PAS via un simple query param `host=true` non authentifié
      let host = false;
      if (isHost === 'true') {
        host = await isMeetingOrganizer(room, req.user.uid);
        if (!host) {
          return res.status(403).json({
            error: 'Droits host refusés : vous n\'êtes pas l\'organisateur de cette réunion',
          });
        }
      }

      const at = new AccessToken(LIVEKIT_API_KEY, LIVEKIT_API_SECRET, {
        identity,
        name,
        ttl: TOKEN_TTL_SECONDS,
      });

      at.addGrant({
        roomJoin: true,
        room,
        canPublish: true,
        canSubscribe: true,
        canPublishData: true,
        canUpdateOwnMetadata: true,
        roomAdmin: host,
        roomRecord: host,
      });

      const token = await at.toJwt();

      console.log(
        `[${new Date().toISOString()}] Token OK user=${identity} room=${room} host=${host} ttl=${TOKEN_TTL_SECONDS}s`
      );

      return res.json({
        token,
        room,
        identity,
        isHost: host,
        expiresIn: TOKEN_TTL_SECONDS,
      });
    } catch (error) {
      console.error('Token error:', error);
      return res.status(500).json({
        error: 'Erreur génération token',
      });
    }
  }
);

// ============================================================
// Static web files
// ============================================================
app.use(express.static(path.join(__dirname, 'web/public')));

// ============================================================
// Web routes
// ============================================================
app.get('/login', (req, res) => {
  res.sendFile(path.join(__dirname, 'web/public/login/index.html'));
});

app.get('/signup', (req, res) => {
  res.sendFile(path.join(__dirname, 'web/public/signup/index.html'));
});

app.get('/app', (req, res) => {
  res.sendFile(path.join(__dirname, 'web/public/app/index.html'));
});

app.get('/join/:id', (req, res) => {
  res.sendFile(path.join(__dirname, 'web/public/join/index.html'));
});

// ============================================================
// SPA fallback
// ============================================================
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'web/public/index.html'));
});

// ============================================================
// Start
// ============================================================
app.listen(PORT, '0.0.0.0', () => {
  console.log(`CRUX Secured Server running on port ${PORT}`);
  console.log('Firebase Auth : ON');
  console.log('LiveKit JWT : ON');
  console.log(`Token TTL : ${TOKEN_TTL_SECONDS}s`);
});
