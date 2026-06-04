import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/error_handler_service.dart';
import 'firebase_options.dart';
import 'screens/splash_screen.dart';
import 'screens/home_screen.dart';
import 'screens/consent_screen.dart';
import 'screens/device_verification_screen.dart';
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
final errorHandlerService = ErrorHandlerService();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    logger.i('✅ Firebase initialisé');
  } catch (e) {
    logger.e('❌ Firebase init: $e');
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
            title: 'CRUX - Premium Video Conference',
            debugShowCheckedModeBanner: false,
            supportedLocales: const [
              Locale('fr'), Locale('en'), Locale('es'), Locale('de'),
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

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _deviceVerified = false;

  static Future<bool> _checkTermsAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('crux_terms_accepted') ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: AppColors.whiteBg,
            body: Center(
              child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3),
            ),
          );
        }
        if (snapshot.hasData && snapshot.data != null) {
          if (!_deviceVerified) {
            return DeviceVerificationScreen(
              onVerified: () => setState(() => _deviceVerified = true),
            );
          }
          final firebaseUser = snapshot.data!;
          final user = UserModel(
            uid: firebaseUser.uid,
            name: firebaseUser.displayName ?? firebaseUser.email?.split('@')[0] ?? 'Utilisateur',
            email: firebaseUser.email ?? '',
          );
          // Check terms accepted
          return FutureBuilder<bool>(
            future: _checkTermsAccepted(),
            builder: (ctx, snap) {
              if (!snap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
              if (snap.data == true) return HomeScreen(user: user);
              return ConsentScreen(user: user);
            },
          );
        }
        return const SplashScreen();
      },
    );
  }
}
