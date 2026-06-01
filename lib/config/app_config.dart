class Config {
  static const String firebaseProjectId = 'crux-8aa85';
  static const String environment = 'production';
  static bool get isProduction => environment == 'production';
  static bool get isDevelopment => environment == 'development';

  // Agora App ID — obtenu sur console.agora.io (gratuit, 10 000 min/mois)
  // Désactive "App Certificate" dans la console Agora pour le mode sans token
  static const String agoraAppId = 'REMPLACE_PAR_TON_AGORA_APP_ID';
}
