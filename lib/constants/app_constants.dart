/// Global app constants shared across screens.
class AppConstants {
  AppConstants._();

  /// Free plan call duration limit in minutes.
  /// Set to 2 for testing, revert to 30 for production.
  static const int freeMinutes = 2; // TEST — remettre à 30 après test

  /// Monthly CRUX Pro price in FCFA
  static const int proPriceFcfa = 25000;

  /// Payment URL
  static const String paymentUrl = 'https://pay.djamo.com/qxmvj';
}
