class Config {
  static const String firebaseProjectId = 'crux-8aa85';
  static const String environment = 'production';
  static bool get isProduction => environment == 'production';
  static bool get isDevelopment => environment == 'development';
}
