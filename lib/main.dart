import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'config/app_config.dart';
import 'services/agora_service.dart';
import 'services/error_handler_service.dart';
import 'services/localization_service.dart';
import 'firebase_options.dart';
import 'screens/login_screen_new.dart';
import 'screens/home_screen_new.dart';
import 'models/user_model.dart';
import 'theme/theme.dart';
import 'theme/premium_colors.dart';
import 'providers/auth_provider.dart';
import 'providers/meeting_provider.dart';

final logger = Logger();
final errorHandlerService = ErrorHandlerService();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load(fileName: '.env');

  try {
    // Initialize Firebase
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    logger.i('✅ Firebase initialisé');

    // Initialize Localization
    final localizationService = LocalizationService();
    await localizationService.initialize();
    logger.i('✅ Localization initialisée: ${localizationService.currentLanguage}');

    // Initialize Agora
    final agoraService = AgoraService();
    await agoraService.initialize(Config.agoraAppId);
    logger.i('✅ Agora initialisé');
  } catch (e) {
    logger.e('❌ Erreur lors de l\'initialisation: $e');
    errorHandlerService.logError('Main', 'Initialization: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late LocalizationService _localizationService;

  @override
  void initState() {
    super.initState();
    _localizationService = LocalizationService();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => MeetingProvider()),
        ChangeNotifierProvider(create: (_) => LocaleChangeNotifier()),
      ],
      child: Consumer<LocaleChangeNotifier>(
        builder: (context, localeNotifier, _) {
          return MaterialApp(
            title: 'CRUX - Premium Video Conference',
            debugShowCheckedModeBanner: false,
            locale: localeNotifier.locale,
            supportedLocales: const [
              Locale('en'),
              Locale('fr'),
              Locale('es'),
              Locale('ru'),
              Locale('de'),
            ],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: ThemeMode.light,
            home: const AuthWrapper(),
            routes: {
              '/login': (_) => const LoginScreenNew(),
              '/home': (_) => const HomeScreenNew(),
              '/settings': (_) => const SettingsScreenPlaceholder(),
            },
          );
        },
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: PremiumColors.cloudWhite,
            body: Center(
              child: CircularProgressIndicator(
                color: PremiumColors.flamePrimary,
                strokeWidth: 3,
              ),
            ),
          );
        }

        if (snapshot.hasData && snapshot.data != null) {
          final firebaseUser = snapshot.data!;
          final user = UserModel(
            uid: firebaseUser.uid,
            name: firebaseUser.displayName ??
                firebaseUser.email?.split('@')[0] ??
                'User',
            email: firebaseUser.email ?? '',
          );
          return HomeScreenNew(user: user);
        }

        return const LoginScreenNew();
      },
    );
  }
}

class LocaleChangeNotifier extends ChangeNotifier {
  late Locale _locale;
  late LocalizationService _localizationService;

  LocaleChangeNotifier() {
    _localizationService = LocalizationService();
    _locale = _localizationService.locale;
  }

  Locale get locale => _locale;

  Future<void> setLocale(String languageCode) async {
    await _localizationService.setLanguage(languageCode);
    _locale = Locale(languageCode);
    notifyListeners();
  }
}

// Placeholder for Settings (to be replaced with SettingsScreenNew)
class SettingsScreenPlaceholder extends StatelessWidget {
  const SettingsScreenPlaceholder({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: const Center(child: Text('Settings Coming Soon')),
    );
  }
}
