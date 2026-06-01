import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:logger/logger.dart';
import 'services/error_handler_service.dart';
import 'firebase_options.dart';
import 'screens/splash_screen.dart';
import 'screens/home_screen.dart';
import 'models/user_model.dart';
import 'theme/colors.dart';
import 'theme/theme.dart';

final logger = Logger();
final errorHandlerService = ErrorHandlerService();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    logger.i('✅ Firebase initialisé');
  } catch (e) {
    logger.e('❌ Firebase init: $e');
  }

  // Permissions caméra & micro pour WebRTC
  await _requestMediaPermissions();

  runApp(const MyApp());
}

Future<void> _requestMediaPermissions() async {
  try {
    final statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();
    logger.i('📷 Caméra: ${statuses[Permission.camera]}');
    logger.i('🎤 Micro: ${statuses[Permission.microphone]}');
  } catch (e) {
    logger.w('⚠️ Permissions: $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CRUX - Premium Video Conference',
      debugShowCheckedModeBanner: false,
      supportedLocales: const [Locale('fr'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      home: const AuthWrapper(),
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
          return const Scaffold(
            backgroundColor: AppColors.whiteBg,
            body: Center(
              child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3),
            ),
          );
        }

        if (snapshot.hasData && snapshot.data != null) {
          final firebaseUser = snapshot.data!;
          final user = UserModel(
            uid: firebaseUser.uid,
            name: firebaseUser.displayName ?? firebaseUser.email?.split('@')[0] ?? 'Utilisateur',
            email: firebaseUser.email ?? '',
          );
          return HomeScreen(user: user);
        }

        return const SplashScreen();
      },
    );
  }
}
