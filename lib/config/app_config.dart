class AppConfig {
  AppConfig._();

  //==========================================================
  // ENVIRONNEMENT
  //==========================================================

  static const String environment = "production";

  static bool get isProduction => environment == "production";

  static bool get isDevelopment => !isProduction;

  //==========================================================
  // FIREBASE
  //==========================================================

  static const String firebaseProjectId = "crux-3c6be";

  //==========================================================
  // LIVEKIT
  //==========================================================

  /// Serveur LiveKit Cloud
  static const String livekitUrl =
      "wss://crux-88fihb12.livekit.cloud";

  /// Serveur de génération des JWT
  static const String livekitTokenServerUrl =
      "https://crux-new-final.onrender.com";

  /// URLs de secours
  static const List<String> livekitFallbackUrls = [
    "https://crux-new-final.onrender.com",
  ];

  //==========================================================
  // LIMITES
  //==========================================================

  /// Réunion P2P
  static const int p2pMaxParticipants = 6;

  /// Réunion LiveKit
  static const int livekitMaxParticipants = 5000;

  /// Durée gratuite
  static const int freeMeetingDurationMinutes = 30;

  /// Nombre de vidéos affichées
  static const int livekitVisibleTileCap = 16;

  //==========================================================
  // TIMEOUTS
  //==========================================================

  static const Duration tokenTimeout =
      Duration(seconds: 15);

  static const Duration roomConnectionTimeout =
      Duration(seconds: 20);

  static const Duration reconnectDelay =
      Duration(seconds: 3);

  static const int maxReconnectAttempts = 5;
}
