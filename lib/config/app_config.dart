class AppConfig {
  static const String firebaseProjectId = 'crux-3c6be';
  static const String environment = 'production';
  static bool get isProduction => environment == 'production';
  static bool get isDevelopment => environment == 'development';

  // LiveKit server URL (WebSocket) — livekit.cloud hosted
  static const String livekitUrl = 'wss://crux-88fihb12.livekit.cloud';
  static const String livekitApiKey = 'APIDnXJytuRnVpH';
  static const String livekitApiSecret = 'ImMJ5epOjxwTeG96CK8yp8qtp28tXBaGLDrjKc5aZC3';

  // Token server: generates signed LiveKit JWTs from your API key/secret
  // Endpoint: GET /livekit-token?room=<meetingId>&identity=<userId>&name=<userName>
  static const String livekitTokenServerUrl =
      'https://crux-new-final.onrender.com';

  /// P2P mesh limit (WebRTC direct — small meetings).
  static const int p2pMaxParticipants = 6;

  /// SFU limit (Zoom/Meet-style large webinars).
  static const int livekitMaxParticipants = 5000;

  /// Limite de durée pour les appels gratuits (en minutes)
  static const int freeMeetingDurationMinutes = 30;

  /// Max video tiles rendered on screen at once
  static const int livekitVisibleTileCap = 16;
}
