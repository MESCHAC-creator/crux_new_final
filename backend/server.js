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

// Security headers
app.use((req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('X-XSS-Protection', '1; mode=block');
  res.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
  next();
});

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
const NODE_ENV = process.env.NODE_ENV || 'production';
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
// Input Validation Helpers
// ============================================================
function validateMeetingInput(data) {
  const errors = [];
  
  if (!data.title || typeof data.title !== 'string' || data.title.trim().length === 0) {
    errors.push('Title is required and must be a non-empty string');
  }
  if (data.title && data.title.length > 200) {
    errors.push('Title must be less than 200 characters');
  }
  
  if (data.description && typeof data.description !== 'string') {
    errors.push('Description must be a string');
  }
  if (data.description && data.description.length > 1000) {
    errors.push('Description must be less than 1000 characters');
  }
  
  if (!data.organizerName || typeof data.organizerName !== 'string' || data.organizerName.trim().length === 0) {
    errors.push('Organizer name is required and must be a non-empty string');
  }
  if (data.organizerName && data.organizerName.length > 100) {
    errors.push('Organizer name must be less than 100 characters');
  }
  
  if (data.passcode !== undefined && data.passcode !== null) {
    if (typeof data.passcode !== 'string') {
      errors.push('Passcode must be a string');
    } else if (data.passcode.length > 0) {
      if (data.passcode.length < 4 || data.passcode.length > 6) {
        errors.push('Passcode must be 4-6 characters');
      }
      if (!/^\d+$/.test(data.passcode)) {
        errors.push('Passcode must contain only digits');
      }
    }
  }
  
  if (data.isLargeConference !== undefined && typeof data.isLargeConference !== 'boolean') {
    errors.push('isLargeConference must be a boolean');
  }
  
  return errors;
}

function validateMeetingCode(code) {
  const errors = [];
  
  if (!code || typeof code !== 'string') {
    errors.push('Meeting code is required and must be a string');
    return errors;
  }
  
  const upperCode = code.toUpperCase();
  if (!/^[A-Z0-9]{8}$/.test(upperCode)) {
    errors.push('Meeting code must be 8 alphanumeric characters');
  }
  
  return errors;
}

function validateMeetingId(id) {
  const errors = [];
  
  if (!id || typeof id !== 'string') {
    errors.push('Meeting ID is required and must be a string');
    return errors;
  }
  
  if (!/^[A-Z0-9]{12}$/.test(id)) {
    errors.push('Meeting ID must be 12 alphanumeric characters');
  }
  
  return errors;
}

function validateTokenParams(params) {
  const errors = [];
  
  if (!params.room || typeof params.room !== 'string') {
    errors.push('Room is required and must be a string');
  } else if (params.room.length > 100) {
    errors.push('Room must be less than 100 characters');
  }
  
  if (!params.identity || typeof params.identity !== 'string') {
    errors.push('Identity is required and must be a string');
  } else if (params.identity.length > 100) {
    errors.push('Identity must be less than 100 characters');
  }
  
  if (!params.name || typeof params.name !== 'string') {
    errors.push('Name is required and must be a string');
  } else if (params.name.length > 100) {
    errors.push('Name must be less than 100 characters');
  }
  
  if (params.isHost !== undefined && params.isHost !== 'true' && params.isHost !== 'false') {
    errors.push('isHost must be "true" or "false"');
  }
  
  return errors;
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
// Error Handler
// ============================================================
app.use((err, req, res, next) => {
  console.error('Error:', err.message);
  
  if (NODE_ENV === 'production') {
    res.status(500).json({ error: 'Internal server error' });
  } else {
    res.status(500).json({ error: err.message, stack: err.stack });
  }
});

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

    // Validate input
    const validationErrors = validateMeetingInput(req.body);
    if (validationErrors.length > 0) {
      return res.status(400).json({ error: 'Validation failed', details: validationErrors });
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
    console.error('Create meeting error:', error.message);
    return res.status(500).json({ error: 'Erreur création réunion' });
  }
});

// GET /api/meetings/code/:code - Get meeting by code
app.get('/api/meetings/code/:code', verifyFirebaseToken, async (req, res) => {
  try {
    const { code } = req.params;
    
    // Validate meeting code
    const validationErrors = validateMeetingCode(code);
    if (validationErrors.length > 0) {
      return res.status(400).json({ error: 'Validation failed', details: validationErrors });
    }
    
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
    console.error('Get meeting by code error:', error.message);
    return res.status(500).json({ error: 'Erreur récupération réunion' });
  }
});

// GET /api/meetings/:id - Get meeting by ID
app.get('/api/meetings/:id', verifyFirebaseToken, async (req, res) => {
  try {
    const { id } = req.params;
    
    // Validate meeting ID
    const validationErrors = validateMeetingId(id);
    if (validationErrors.length > 0) {
      return res.status(400).json({ error: 'Validation failed', details: validationErrors });
    }

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
    console.error('Get meeting by ID error:', error.message);
    return res.status(500).json({ error: 'Erreur récupération réunion' });
  }
});

// PUT /api/meetings/:id/participants - Add participant to meeting
app.put('/api/meetings/:id/participants', verifyFirebaseToken, async (req, res) => {
  try {
    const { id } = req.params;
    const userId = req.user.uid;
    
    // Validate meeting ID
    const validationErrors = validateMeetingId(id);
    if (validationErrors.length > 0) {
      return res.status(400).json({ error: 'Validation failed', details: validationErrors });
    }

    await db.collection('meetings').doc(id).update({
      participants: admin.firestore.FieldValue.arrayUnion(userId),
    });

    console.log(`[${new Date().toISOString()}] Participant ${userId} added to meeting ${id}`);

    return res.json({ success: true });
  } catch (error) {
    console.error('Add participant error:', error.message);
    return res.status(500).json({ error: 'Erreur ajout participant' });
  }
});

// ============================================================
// Core token handler (factorisé)
// ============================================================
async function handleTokenRequest(req, res) {
  try {
    const { room, identity, name, isHost } = req.query;

    // Validate token parameters
    const validationErrors = validateTokenParams(req.query);
    if (validationErrors.length > 0) {
      return res.status(400).json({ error: 'Validation failed', details: validationErrors });
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
