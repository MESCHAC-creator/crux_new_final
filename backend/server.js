require('dotenv').config();

const express = require('express');
const cors = require('cors');
const { AccessToken } = require('livekit-server-sdk');

const app = express();

app.use(cors());
app.use(express.json());

const LIVEKIT_API_KEY = process.env.LIVEKIT_API_KEY;
const LIVEKIT_API_SECRET = process.env.LIVEKIT_API_SECRET;
const PORT = process.env.PORT || 3000;

const TOKEN_TTL_SECONDS = 86400; // 24 heures


// Health check
app.get('/', (req, res) => {
  res.json({
    status: 'ok',
    message: 'Crux LiveKit Token Server is running',
    endpoints: [
      '/ping',
      '/livekit-token'
    ]
  });
});


// Ping test
app.get('/ping', (req, res) => {
  res.json({
    status: 'ok',
    service: 'crux-livekit-token'
  });
});


// Generate LiveKit JWT
// GET /livekit-token?room=MEETING_ID&identity=USER_ID&name=USER_NAME
app.get('/livekit-token', async (req, res) => {

  const { room, identity, name } = req.query;


  if (!room || !identity) {
    return res.status(400).json({
      error: 'room and identity are required'
    });
  }


  if (!LIVEKIT_API_KEY || !LIVEKIT_API_SECRET) {
    return res.status(500).json({
      error: 'LiveKit credentials not configured on server'
    });
  }


  try {

    const at = new AccessToken(
      LIVEKIT_API_KEY,
      LIVEKIT_API_SECRET,
      {
        identity,
        name: name || identity,
        ttl: TOKEN_TTL_SECONDS
      }
    );


    at.addGrant({
      roomJoin: true,
      room: room,
      canPublish: true,
      canSubscribe: true,
      canPublishData: true
    });


    // Host permissions
    if (req.query.host === 'true') {

      at.addGrant({
        roomAdmin: true,
        roomRecord: true
      });

    }


    const token = await at.toJwt();


    return res.json({
      token,
      room,
      identity
    });


  } catch (error) {

    console.error('LiveKit token generation error:', error);

    return res.status(500).json({
      error: 'Failed to generate LiveKit token'
    });

  }

});


// Start server
app.listen(PORT, () => {
  console.log(
    `CRUX LiveKit Token server running on port ${PORT}`
  );
});
