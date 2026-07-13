require('dotenv').config();
const express = require('express');
const cors = require('cors');
const path = require('path');
const { AccessToken } = require('livekit-server-sdk');

const app = express();
app.use(cors());
app.use(express.json());

const LIVEKIT_API_KEY    = process.env.LIVEKIT_API_KEY || 'APIDnXJytuRnVpH';
const LIVEKIT_API_SECRET = process.env.LIVEKIT_API_SECRET || 'ImMJ5epOjxwTeG96CK8yp8qtp28tXBaGLDrjKc5aZC3';
const PORT               = process.env.PORT || 3000;
const TOKEN_TTL_SECONDS  = 86400; // 24h

// LiveKit Token Server Endpoints
app.get('/ping', (req, res) =>
  res.json({ status: 'ok', service: 'crux-livekit-token' })
);

app.get('/livekit-token', (req, res) => {
  const { room, identity, name } = req.query;

  if (!room || !identity) {
    return res.status(400).json({ error: 'room and identity are required' });
  }
  if (!LIVEKIT_API_KEY || !LIVEKIT_API_SECRET) {
    return res.status(500).json({ error: 'LiveKit credentials not configured on server' });
  }

  const at = new AccessToken(LIVEKIT_API_KEY, LIVEKIT_API_SECRET, {
    identity,
    name: name || identity,
    ttl: TOKEN_TTL_SECONDS,
  });

  at.addGrant({
    roomJoin: true,
    room,
    canPublish: true,
    canSubscribe: true,
    canPublishData: true,
  });

  if (req.query.host === 'true') {
    at.addGrant({
      roomAdmin: true,
      roomRecord: true,
    });
  }

  const token = at.toJwt();
  return res.json({ token, room, identity });
});

// Serve static assets from the web/public directory (CSS, JS, etc.)
app.use(express.static(path.join(__dirname, 'web/public')));

// Specific web routing mapped to the correct static index.html pages
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

// Catch-all route to serve the homepage or support any other SPA fallback
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'web/public/index.html'));
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`CRUX Server running on port ${PORT}`);
});
