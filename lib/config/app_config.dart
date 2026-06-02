class Config {
  static const String firebaseProjectId = 'crux-8aa85';
  static const String environment = 'production';
  static bool get isProduction => environment == 'production';
  static bool get isDevelopment => environment == 'development';

  // Video calls use WebRTC P2P with Firebase Firestore as signaling (free, no vendor).
  // STUN: Google public servers (free, no account needed).
  // Agora App IDs kept for reference (not used):
  //   crux-8aa85:  729bb936e5084d53897e43c58ee8e946
  //   cruxapp:     da868f2afc7d407385e2d0a5394cf9d6
}
