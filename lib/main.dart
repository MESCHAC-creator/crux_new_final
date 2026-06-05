import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/notification_service.dart';
import 'services/device_verification_service.dart';
import 'firebase_options.dart';
import 'screens/splash_screen.dart';
import 'screens/home_screen.dart';
import 'screens/consent_screen.dart';
import 'models/user_model.dart';
import 'providers/auth_provider.dart' show CruxAuthProvider;
import 'providers/meeting_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/locale_provider.dart';
import 'providers/color_provider.dart';
import 'routes/app_routes.dart';
import 'theme/colors.dart';
import 'theme/theme.dart';

final logger = Logger();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── 1. Firebase ─────────────────────────────
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    logger.i('✅ Firebase initialisé');
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: 40 * 1024 * 1024,
    );
  } catch (e) {
    logger.e('❌ Firebase init error: $e');
  }

  // ── 2. Device verification (before runApp — cannot be bypassed) ─
  final (isSecure, blockReason) =
      await DeviceVerificationService.instance.verifyDeviceSecurity();

  // ── 3. Notifications ─────────────────────────
  try {
    await NotificationService().initialize();
  } catch (e) {
    logger.e('Notification init error: $e');
  }

  if (!isSecure) {
    runApp(_DeviceBlockedApp(reason: blockReason));
    return;
  }

  runApp(const MyApp());
}

/// Shown when the device fails security checks.
class _DeviceBlockedApp extends StatelessWidget {
  final String reason;
  const _DeviceBlockedApp({required this.reason});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF0F0C1A),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.security, color: Colors.red, size: 72),
                const SizedBox(height: 24),
                const Text(
                  'Appareil non compatible',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  reason,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // Stable navigator key — prevents navigation reset when locale/theme rebuilds
  static final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CruxAuthProvider()),
        ChangeNotifierProvider(create: (_) => MeetingProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider(create: (_) => ColorProvider()),
      ],
      child: Consumer2<ThemeProvider, LocaleProvider>(
        builder: (context, themeProvider, localeProvider, _) {
          return MaterialApp(
            navigatorKey: MyApp._navigatorKey,
            title: 'CRUX - Premium Video Conference',
            debugShowCheckedModeBanner: false,
            supportedLocales: const [
              Locale('fr'), Locale('en'), Locale('es'), Locale('de'),
              Locale('ru'), Locale('pt'), Locale('it'), Locale('ar'),
              Locale('zh'), Locale('hi'), Locale('ja'), Locale('ko'),
              Locale('tr'), Locale('vi'), Locale('id'), Locale('nl'),
              Locale('pl'), Locale('uk'), Locale('sv'), Locale('ha'),
              Locale('yo'), Locale('sw'), Locale('am'), Locale('fa'),
              Locale('ro'), Locale('el'), Locale('cs'), Locale('hu'),
              Locale('bn'), Locale('th'), Locale('mg'), Locale('wo'),
            ],
            locale: localeProvider.locale,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            onGenerateRoute: AppRoutes.generateRoute,
            home: const AuthWrapper(),
          );
        },
      ),
    );
  }
}

// StatefulWidget so terms & auth are cached — no re-run on locale/theme rebuild
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool? _termsAccepted;
  // Cache the stream to prevent StreamBuilder from re-subscribing on every
  // rebuild (locale/theme change) which would flash the loading screen.
  late final Stream<User?> _authStream;

  @override
  void initState() {
    super.initState();
    _authStream = FirebaseAuth.instance.authStateChanges();
    _loadTerms();
  }

  Future<void> _loadTerms() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _termsAccepted = prefs.getBool('crux_terms_accepted') ?? false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // While SharedPreferences hasn't loaded yet, show spinner
    if (_termsAccepted == null) {
      return const Scaffold(
        backgroundColor: AppColors.whiteBg,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3),
        ),
      );
    }

    return StreamBuilder<User?>(
      stream: _authStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: AppColors.whiteBg,
            body: Center(
              child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3),
            ),
          );
        }

        final user = snapshot.data;
        if (user == null) return const SplashScreen();

        final userModel = UserModel(
          uid: user.uid,
          name: user.displayName ?? user.email?.split('@')[0] ?? 'Utilisateur',
          email: user.email ?? '',
        );

        if (_termsAccepted == true) return HomeScreen(user: userModel);
        return ConsentScreen(user: userModel);
      },
    );
  }
}
