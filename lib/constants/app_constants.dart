class AppConstants {
  AppConstants._();

  /// Free plan call duration limit in minutes (1h45min = 105 minutes).
  static const int freeMinutes = 105;

  /// Monthly CRUX Pro price in FCFA
  static const int proPriceFcfa = 100000;

  /// Monthly CRUX Pro price in USD (100000 FCFA ÷ 600 = ~167 USD)
  static const int proPriceUsd = 167;

  /// Payment URL
  static const String paymentUrl = 'https://pay.djamo.com/qxmvj';
}
