class AppConfig {
  static const String firebaseProjectId = 'crux-3c6be';

  static const String environment = 'production';

  static bool get isProduction => environment == 'production';

  static bool get isDevelopment => environment == 'development';


  // ============================================================
  // LIVEKIT CLOUD
  // URL WebSocket utilisée par l'application Flutter
  // Le token est obtenu depuis le serveur CRUX Token Server
  // ============================================================

  static const String livekitUrl =
      'wss://crux-88fihb12.livekit.cloud';


  // ============================================================
  // LIVEKIT TOKEN SERVER
  // Génère les JWT LiveKit sécurisés
  //
  // Flutter appelle automatiquement :
  // GET https://crux-new-final.onrender.com/livekit-token
  //
  // Les clés LiveKit restent côté serveur uniquement.
  // ============================================================

  static const String livekitTokenServerUrl =
      'https://crux-new-final.onrender.com';


  // Serveurs de secours du token server uniquement.
  // Ne jamais mettre ici des URLs wss:// LiveKit.
  static const List<String> livekitFallbackUrls = [];


  // ============================================================
  // LIMITES DE CONFERENCE
  // ============================================================

  /// Petites réunions P2P WebRTC directes.
  static const int p2pMaxParticipants = 6;


  /// Conférences LiveKit SFU.
  static const int livekitMaxParticipants = 5000;


  // ============================================================
  // LIMITES APPLICATION
  // ============================================================

  /// Durée gratuite des réunions en minutes.
  static const int freeMeetingDurationMinutes = 30;


  /// Nombre maximum de vidéos affichées simultanément.
  static const int livekitVisibleTileCap = 16;


  // ============================================================
  // OPTIONS PAR DEFAUT DES REUNIONS
  // ============================================================

  static const bool defaultCameraEnabled = true;

  static const bool defaultMicrophoneEnabled = true;

  static const bool defaultScreenShareEnabled = true;

  static const bool defaultChatEnabled = true;

  static const bool defaultRecordingEnabled = false;
}
