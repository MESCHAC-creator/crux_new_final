# CRUX LiveKit Token Server

Backend Node.js server for CRUX video conferencing application. Handles meeting management and LiveKit token generation.

## Features

- **Firebase Authentication**: Secure token verification for all endpoints
- **Meeting Management**: Create, retrieve, and manage meetings via REST API
- **LiveKit Token Generation**: Secure JWT token generation for video calls
- **Firestore Integration**: Persistent meeting storage and host validation
- **Rate Limiting**: Protection against API abuse

## Setup

1. Install dependencies:
```bash
npm install
```

2. Configure environment variables:
```bash
cp .env.example .env
# Edit .env with your actual values
```

3. Start the server:
```bash
npm start
# For development with auto-reload:
npm run dev
```

## Environment Variables

- `LIVEKIT_API_KEY`: Your LiveKit API key (required)
- `LIVEKIT_API_SECRET`: Your LiveKit API secret (required)
- `PORT`: Server port (default: 3000)
- `TOKEN_TTL_SECONDS`: Token expiration time in seconds (default: 3600, minimum: 300)
- `ALLOWED_ORIGINS`: Comma-separated CORS origins (empty = no restriction)
- `FIREBASE_SERVICE_ACCOUNT`: Firebase service account JSON (optional)

## API Endpoints

### Health & Status
- `GET /` - Server status and available endpoints
- `GET /ping` - Simple health check

### Meeting Management
- `POST /api/meetings` - Create a new meeting
  - Body: `{ title, description, organizerName, passcode?, isLargeConference? }`
  - Returns: Meeting object with ID and code

- `GET /api/meetings/code/:code` - Get meeting by code
  - Params: `code` (8-character meeting code)
  - Returns: Meeting object or 404

- `GET /api/meetings/:id` - Get meeting by ID
  - Params: `id` (12-character meeting ID)
  - Returns: Meeting object or 404

- `PUT /api/meetings/:id/participants` - Add participant to meeting
  - Params: `id` (meeting ID)
  - Returns: Success confirmation

### LiveKit Tokens
- `GET /api/livekit-token` - Generate LiveKit JWT token
  - Query: `room`, `identity`, `name`, `isHost?`
  - Returns: `{ token, room, identity, isHost, expiresIn }`

- `GET /livekit-token` - Legacy endpoint (same as above)

## Security

- All endpoints require Firebase Authentication Bearer token
- Identity validation ensures users can only generate tokens for themselves
- Host validation checks Firestore for organizer/co-host permissions
- Rate limiting: 100 requests/minute general, 30 requests/minute for tokens

## Meeting Codes

- **Meeting ID**: 12-character alphanumeric identifier (internal use)
- **Meeting Code**: 8-character uppercase alphanumeric code (user-facing)
- Both are randomly generated and unique

## Error Handling

The API returns appropriate HTTP status codes:
- `200` - Success
- `201` - Created
- `400` - Bad request (missing/invalid parameters)
- `401` - Unauthorized (missing/invalid Firebase token)
- `403` - Forbidden (insufficient permissions)
- `404` - Not found (meeting doesn't exist)
- `500` - Server error

## Integration with Flutter App

The Flutter app uses the `BackendApiService` to communicate with this server:

```dart
final backendService = BackendApiService();

// Create meeting
final meeting = await backendService.createMeeting(
  title: 'My Meeting',
  organizerName: 'John Doe',
);

// Join by code
final meeting = await backendService.getMeetingByCode('ABC12345');

// Get LiveKit token
final tokenData = await backendService.getLiveKitToken(
  room: meetingId,
  identity: userId,
  name: userName,
);
```

## Troubleshooting

1. **"LIVEKIT_API_KEY ou LIVEKIT_API_SECRET manquant"**
   - Ensure your `.env` file contains both required LiveKit credentials

2. **CORS errors**
   - Check `ALLOWED_ORIGINS` in your `.env` file
   - For mobile apps, no origin is sent, so this should work automatically

3. **Firebase auth errors**
   - Ensure your Firebase project is properly configured
   - Check that the Firebase Admin SDK is initialized correctly

4. **Firestore errors**
   - Verify Firestore database rules allow the server to read/write
   - Check that the `FIREBASE_SERVICE_ACCOUNT` is valid if provided
