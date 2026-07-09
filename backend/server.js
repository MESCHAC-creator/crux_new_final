require('dotenv').config();
const express = require('express');
const cors = require('cors');
const { AccessToken } = require('livekit-server-sdk');

const app = express();
app.use(cors());
app.use(express.json());

const LIVEKIT_API_KEY    = process.env.LIVEKIT_API_KEY || 'APIDnXJytuRnVpH';
const LIVEKIT_API_SECRET = process.env.LIVEKIT_API_SECRET || 'ImMJ5epOjxwTeG96CK8yp8qtp28tXBaGLDrjKc5aZC3';
const PORT               = process.env.PORT || 3000;
const TOKEN_TTL_SECONDS  = 86400; // 24h

// Health check and root route
app.get('/', (req, res) =>
  res.json({ status: 'ok', message: 'Crux LiveKit Token Server is running', endpoints: ['/ping', '/livekit-token'] })
);

app.get('/ping', (req, res) =>
  res.json({ status: 'ok', service: 'crux-livekit-token' })
);

// Generate LiveKit JWT
// GET /livekit-token?room=MEETING_ID&identity=USER_ID&name=USER_NAME
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

  // Host gets admin controls (mute, remove, recording) on LiveKit rooms
  if (req.query.host === 'true') {
    at.addGrant({
      roomAdmin: true,
      roomRecord: true,
    });
  }

  const token = at.toJwt();
  return res.json({ token, room, identity });
});

app.listen(PORT, () =>
  console.log(`CRUX LiveKit token server running on port ${PORT}`)
);
