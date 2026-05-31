class AppConstants {
  // API Endpoints
  static const String agoraTokenUrl = 'http://localhost:8081/rtc';
  static const String firebaseProjectId = 'crux-8aa85';

  // Agora Config
  static const int agoraDefaultUid = 0;
  static const int agoraMaxParticipants = 20;
  static const Duration tokenExpireDuration = Duration(hours: 1);

  // Duration & Timeout
  static const Duration requestTimeout = Duration(seconds: 30);
  static const Duration shortAnimationDuration = Duration(milliseconds: 300);
  static const Duration normalAnimationDuration = Duration(milliseconds: 500);
  static const Duration longAnimationDuration = Duration(milliseconds: 800);

  // UI Constants
  static const double defaultPadding = 16.0;
  static const double defaultBorderRadius = 12.0;
  static const double defaultElevation = 4.0;

  // Validation Rules
  static const int minNameLength = 2;
  static const int maxNameLength = 50;
  static const int minEmailLength = 5;
  static const int maxEmailLength = 100;
  static const int minPasswordLength = 6;
  static const int maxPasswordLength = 128;
  static const int maxMeetingTitleLength = 100;

  // Cache Duration
  static const Duration cacheDuration = Duration(hours: 24);
  static const Duration shortCacheDuration = Duration(minutes: 5);

  // Meeting Config
  static const int maxMeetingDuration = 120; // minutes
  static const int minMeetingDuration = 1; // minute
  static const String defaultMeetingLanguage = 'fr';

  // Error Messages
  static const String networkErrorMessage = 'Erreur réseau - Vérifiez votre connexion';
  static const String timeoutErrorMessage = 'Délai d\'attente dépassé';
  static const String unknownErrorMessage = 'Une erreur inconnue s\'est produite';

  // Success Messages
  static const String loginSuccessMessage = '✅ Connexion réussie';
  static const String logoutSuccessMessage = '✅ Déconnexion réussie';
  static const String meetingCreatedMessage = '✅ Réunion créée avec succès';
}

// Routes
class AppRoutes {
  static const String splash = '/splash';
  static const String login = '/login';
  static const String home = '/home';
  static const String meeting = '/meeting';
  static const String settings = '/settings';
}

// Preferences Keys
class PreferencesKeys {
  static const String userIdKey = 'user_id';
  static const String userNameKey = 'user_name';
  static const String userEmailKey = 'user_email';
  static const String rememberMeKey = 'remember_me';
  static const String lastLoginKey = 'last_login';
  static const String languageKey = 'language';
  static const String themeKey = 'theme';
  static const String notificationsKey = 'notifications_enabled';
}