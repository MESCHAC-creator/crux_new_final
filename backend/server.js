// backend/server.js
// CRUX LiveKit Token Server v2.2.0
// Firebase Auth + Firestore host validation + LiveKit JWT + Rate limiting

require('dotenv').config();

const express = require('express');
const cors = require('cors');
const rateLimit = require('express-rate-limit');
const admin = require('firebase-admin');
const { AccessToken } = require('livekit-server-sdk');

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
// Express
// ============================================================
const app = express();
app.use(express.json({ limit: '10kb' }));

// ============================================================
// CORS
// ============================================================
const allowedOrigins = (process.env.ALLOWED_ORIGINS || '')
  .split(',')
  .filter(Boolean);

app.use(
  cors({
    origin: (origin, callback) => {
      // Flutter mobile apps have no origin
      if (!origin) return callback(null, true);
      // No restriction configured → allow
      if (!allowedOrigins.length) return callback(null, true);

      const allowed = allowedOrigins.some((item) =>
        origin.startsWith(item.replace('/*', ''))
      );
      if (allowed) return callback(null, true);
      return callback(new Error(`CORS blocked: ${origin}`));
    },
    methods: ['GET', 'POST', 'PUT', 'OPTIONS'],
    allowedHeaders: ['Authorization', 'Content-Type'],
  })
);

// ============================================================
// Configuration
// ============================================================
const LIVEKIT_API_KEY = process.env.LIVEKIT_API_KEY;
const LIVEKIT_API_SECRET = process.env.LIVEKIT_API_SECRET;
const PORT = process.env.PORT || 3000;
// 🔒 SÉCURITÉ : TTL 1h par défaut (pas 24h). Minimum 5 minutes.
const TOKEN_TTL_SECONDS = Math.max(
  300,
  Number(process.env.TOKEN_TTL_SECONDS || 3600)
);

if (!LIVEKIT_API_KEY || !LIVEKIT_API_SECRET) {
  console.error('LIVEKIT_API_KEY ou LIVEKIT_API_SECRET manquant');
  process.exit(1);
}

// ============================================================
// Rate limiting
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
    return res.status(401).json({ error: 'Authentification Firebase requise' });
  }
  const token = header.substring(7);
  try {
    const decoded = await admin.auth().verifyIdToken(token, true);
    req.user = decoded;
    next();
  } catch (error) {
    console.error('Firebase auth error:', error.code);
    return res.status(401).json({ error: 'Token Firebase invalide' });
  }
}

// ============================================================
// Helpers
// ============================================================
async function isMeetingOrganizerOrCohost(meetingId, uid) {
  try {
    const snap = await db.collection('meetings').doc(meetingId).get();
    if (!snap.exists) return false;
    const data = snap.data();
    if (data.organizerId === uid) return true;
    if (Array.isArray(data.coHosts) && data.coHosts.includes(uid)) return true;
    return false;
  } catch (error) {
    console.error('Firestore host check error:', error.message);
    return false;
  }
}

async function isScheduledMeetingOrganizerOrCohost(meetingId, uid) {
  try {
    const snap = await db.collection('scheduled_meetings').doc(meetingId).get();
    if (!snap.exists) return false;
    const data = snap.data();
    if (data.organizerId === uid) return true;
    if (Array.isArray(data.coHosts) && data.coHosts.includes(uid)) return true;
    return false;
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
    service: 'CRUX LiveKit Token Server',
    version: '2.2.0',
    endpoints: {
      health: 'GET /',
      ping: 'GET /ping',
      token: 'GET /livekit-token | GET /api/livekit-token',
      meetings: {
        create: 'POST /api/meetings',
        getByCode: 'GET /api/meetings/code/:code',
        getById: 'GET /api/meetings/:id',
        addParticipant: 'PUT /api/meetings/:id/participants',
      },
    },
  });
});

app.get('/ping', (req, res) => {
  res.json({
    status: 'ok',
    service: 'crux-token-server',
    timestamp: Date.now(),
  });
});

// ============================================================
// Meeting Management Endpoints
// ============================================================

// Generate a random meeting code (8 characters, uppercase)
function generateMeetingCode() {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  let code = '';
  for (let i = 0; i < 8; i++) {
    code += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return code;
}

// Generate a random meeting ID (12 characters, uppercase)
function generateMeetingId() {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  let id = '';
  for (let i = 0; i < 12; i++) {
    id += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return id;
}

// POST /api/meetings - Create a new meeting
app.post('/api/meetings', verifyFirebaseToken, async (req, res) => {
  try {
    const { title, description, organizerName, passcode, isLargeConference } = req.body;
    const userId = req.user.uid;

    if (!title || !organizerName) {
      return res.status(400).json({ error: 'Titre et nom de l\'organisateur requis' });
    }

    // Validate passcode if provided
    if (passcode && (passcode.length < 4 || passcode.length > 6)) {
      return res.status(400).json({ error: 'Le code d\'accès doit faire 4 à 6 chiffres' });
    }
    if (passcode && !/^\d+$/.test(passcode)) {
      return res.status(400).json({ error: 'Le code d\'accès ne doit contenir que des chiffres' });
    }

    const meetingId = generateMeetingId();
    const meetingCode = generateMeetingCode();
    const now = new Date();
    const endTime = new Date(now.getTime() + 60 * 60 * 1000); // 1 hour from now

    const meetingData = {
      id: meetingId,
      title,
      description: description || '',
      organizer: organizerName,
      organizerId: userId,
      startTime: admin.firestore.Timestamp.fromDate(now),
      endTime: admin.firestore.Timestamp.fromDate(endTime),
      participants: [userId],
      channelName: meetingId,
      status: 'ongoing',
      createdAt: admin.firestore.Timestamp.fromDate(now),
      isRecording: false,
      isLocked: false,
      passcode: passcode || null,
      isLargeConference: isLargeConference || false,
      meetingCode,
      coHosts: [],
    };

    await db.collection('meetings').doc(meetingId).set(meetingData);

    console.log(`[${new Date().toISOString()}] Meeting created: ${meetingId} by ${userId}`);

    return res.status(201).json({
      id: meetingId,
      meetingCode,
      ...meetingData,
    });
  } catch (error) {
    console.error('Create meeting error:', error);
    return res.status(500).json({ error: 'Erreur création réunion' });
  }
});

// GET /api/meetings/code/:code - Get meeting by code
app.get('/api/meetings/code/:code', verifyFirebaseToken, async (req, res) => {
  try {
    const { code } = req.params;
    const upperCode = code.toUpperCase();

    const snap = await db
      .collection('meetings')
      .where('meetingCode', '==', upperCode)
      .limit(1)
      .get();

    if (snap.empty) {
      return res.status(404).json({ error: 'Réunion introuvable' });
    }

    const doc = snap.docs[0];
    const meetingData = doc.data();

    return res.json({
      id: doc.id,
      ...meetingData,
    });
  } catch (error) {
    console.error('Get meeting by code error:', error);
    return res.status(500).json({ error: 'Erreur récupération réunion' });
  }
});

// GET /api/meetings/:id - Get meeting by ID
app.get('/api/meetings/:id', verifyFirebaseToken, async (req, res) => {
  try {
    const { id } = req.params;

    const doc = await db.collection('meetings').doc(id).get();

    if (!doc.exists) {
      return res.status(404).json({ error: 'Réunion introuvable' });
    }

    const meetingData = doc.data();

    return res.json({
      id: doc.id,
      ...meetingData,
    });
  } catch (error) {
    console.error('Get meeting by ID error:', error);
    return res.status(500).json({ error: 'Erreur récupération réunion' });
  }
});

// PUT /api/meetings/:id/participants - Add participant to meeting
app.put('/api/meetings/:id/participants', verifyFirebaseToken, async (req, res) => {
  try {
    const { id } = req.params;
    const userId = req.user.uid;

    await db.collection('meetings').doc(id).update({
      participants: admin.firestore.FieldValue.arrayUnion(userId),
    });

    console.log(`[${new Date().toISOString()}] Participant ${userId} added to meeting ${id}`);

    return res.json({ success: true });
  } catch (error) {
    console.error('Add participant error:', error);
    return res.status(500).json({ error: 'Erreur ajout participant' });
  }
});

// ============================================================
// Core token handler (factorisé)
// ============================================================
async function handleTokenRequest(req, res) {
  try {
    const { room, identity, name, isHost } = req.query;

    if (!room || !identity || !name) {
      return res.status(400).json({
        error: 'Paramètres manquants',
        required: ['room', 'identity', 'name'],
      });
    }

    if (room.length > 100 || identity.length > 100 || name.length > 100) {
      return res.status(400).json({ error: 'Paramètres trop longs' });
    }

    // 🔒 Contrôle d'identité strict : identity === uid Firebase
    if (identity !== req.user.uid) {
      return res.status(403).json({ error: 'Identité non autorisée' });
    }

    // 🔒 Contrôle host : vérifié dans Firestore (meetings OU scheduled_meetings)
    // Plus simple param `?isHost=true` qui marche sans contrôle.
    let host = false;
    if (isHost === 'true') {
      host =
        (await isMeetingOrganizerOrCohost(room, req.user.uid)) ||
        (await isScheduledMeetingOrganizerOrCohost(room, req.user.uid));
      if (!host) {
        return res.status(403).json({
          error: 'Droits host refusés : vous n\'êtes pas organisateur de cette réunion',
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
    return res.status(500).json({ error: 'Erreur génération token' });
  }
}

// Deux routes compatibles : ancienne (racine) + nouvelle (/api)
app.get('/livekit-token', verifyFirebaseToken, tokenLimiter, handleTokenRequest);
app.get('/api/livekit-token', verifyFirebaseToken, tokenLimiter, handleTokenRequest);

// ============================================================
// 404
// ============================================================
app.use((req, res) => {
  res.status(404).json({ error: 'Route introuvable' });
});

// ============================================================
// Start
// ============================================================
app.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 CRUX LiveKit Token Server v2.2.0 port ${PORT}`);
  console.log('Firebase Auth : ON');
  console.log('Firestore host check : ON');
  console.log('LiveKit JWT : ON');
  console.log('Meeting Management API : ON');
  console.log(`Token TTL : ${TOKEN_TTL_SECONDS}s (${(TOKEN_TTL_SECONDS / 3600).toFixed(1)}h)`);
});
