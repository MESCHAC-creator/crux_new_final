import 'dart:async';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_links/app_links.dart';
import 'services/notification_service.dart';
import 'services/device_verification_service.dart';
import 'firebase_options.dart';
import 'screens/splash_screen.dart';
import 'screens/home_screen.dart';
import 'screens/consent_screen.dart';
import 'screens/guest_join_screen.dart';
import 'screens/meeting_screen.dart';
import 'models/user_model.dart';
import 'providers/auth_provider.dart' show CruxAuthProvider;
import 'providers/meeting_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/locale_provider.dart';
import 'providers/color_provider.dart';
import 'routes/app_routes.dart';
import 'theme/colors.dart';
import 'theme/theme.dart';
import 'widgets/elegant_toast.dart';

final logger = Logger();

// ---------------------------------------------------------------------------
const _flutterUnsupportedLocales = {'ha', 'yo', 'mg', 'wo'};

Locale _materialFallback(Locale locale) =>
    _flutterUnsupportedLocales.contains(locale.languageCode)
    ? const Locale('fr')
    : locale;

class _FallbackMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _FallbackMaterialLocalizationsDelegate();
  static const instance = _FallbackMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      GlobalMaterialLocalizations.delegate.load(_materialFallback(locale));

  @override
  bool shouldReload(_FallbackMaterialLocalizationsDelegate old) => false;
}

class _FallbackCupertinoLocalizationsDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const _FallbackCupertinoLocalizationsDelegate();
  static const instance = _FallbackCupertinoLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      GlobalCupertinoLocalizations.delegate.load(_materialFallback(locale));

  @override
  bool shouldReload(_FallbackCupertinoLocalizationsDelegate old) => false;
}

const List<LocalizationsDelegate<dynamic>> _localizationsDelegates = [
  _FallbackMaterialLocalizationsDelegate.instance,
  _FallbackCupertinoLocalizationsDelegate.instance,
  GlobalWidgetsLocalizations.delegate,
];

// ---------------------------------------------------------------------------

void main() {
  // Capture Flutter framework errors
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    logger.e('Flutter Framework Error: ${details.exception}',
        error: details.exception, stackTrace: details.stack);
  };

  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    try {
      // 2. Ensure Firebase.initializeApp() is awaited
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: 40 * 1024 * 1024,
      );
      logger.i('✅ Firebase initialisé');
    } catch (e) {
      logger.e('❌ Firebase init error: $e');
      runApp(_ErrorApp(title: 'Erreur Firebase', message: e.toString()));
      return;
    }

    bool isSecure = true;
    String blockReason = '';
    try {
      final result = await DeviceVerificationService.instance.verifyDeviceSecurity();
      isSecure = result.$1;
      blockReason = result.$2;
    } catch (e) {
      logger.e('Device verification crash: $e');
    }

    if (!isSecure) {
      runApp(_DeviceBlockedApp(reason: blockReason));
      return;
    }

    try {
      unawaited(NotificationService().initialize());
    } catch (e) {
      logger.e('Notification init error: $e');
    }

    runApp(const MyApp());
  }, (error, stack) {
    // Capture asynchronous errors
    logger.e('🔥 Global Crash: $error', error: error, stackTrace: stack);
    runApp(_ErrorApp(title: 'Erreur au démarrage', message: error.toString()));
  });
}

class _ErrorApp extends StatelessWidget {
  final String title;
  final String message;
  const _ErrorApp({required this.title, required this.message});

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
                const Icon(Icons.bug_report, color: Colors.red, size: 72),
                const SizedBox(height: 24),
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 32),
                ElevatedButton(onPressed: () => exit(0), child: const Text('Quitter')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DeviceBlockedApp extends StatelessWidget {
  final String reason;
  const _DeviceBlockedApp({required this.reason});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: _localizationsDelegates,
      supportedLocales: const [Locale('fr')],
      home: Scaffold(
        backgroundColor: const Color(0xFF0F0C1A),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.security, color: Colors.orange, size: 72),
                const SizedBox(height: 24),
                const Text('Appareil restreint', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text(reason, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.6)),
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
            title: 'CRUX',
            debugShowCheckedModeBanner: false,
            supportedLocales: LocaleProvider.languages.values.toList(),
            locale: localeProvider.locale,
            localizationsDelegates: _localizationsDelegates,
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
  bool? _termsAccepted;
  late final Stream<User?> _authStream;
  String? _pendingMeetingId;

  @override
  void initState() {
    super.initState();
    _authStream = FirebaseAuth.instance.authStateChanges();
    _loadTerms();
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    try {
      final appLinks = AppLinks();
      appLinks.uriLinkStream.listen((uri) => _handleDeepLink(uri));
      final initialUri = await appLinks.getInitialLink();
      if (initialUri != null) _handleDeepLink(initialUri);
    } catch (e) {
      logger.w('Deep link init error: $e');
    }
  }

  void _handleDeepLink(Uri uri) {
    String? meetingId;
    if (uri.scheme == 'crux' && uri.host == 'join') {
      meetingId = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    } else if ((uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.pathSegments.length >= 2 &&
        uri.pathSegments[uri.pathSegments.length - 2] == 'join') {
      meetingId = uri.pathSegments.last;
    }

    if (meetingId == null || meetingId.isEmpty) return;
    final mid = meetingId.trim().toUpperCase();

    if (!mounted) {
      _pendingMeetingId = mid;
      return;
    }

    final current = FirebaseAuth.instance.currentUser;
    if (current != null && !current.isAnonymous) {
      _joinMeetingAsAuthenticatedUser(mid);
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => GuestJoinScreen(meetingId: mid)));
    }
  }

  Future<void> _joinMeetingAsAuthenticatedUser(String meetingId) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('meetings').doc(meetingId).get();
      if (!mounted) return;
      if (!doc.exists) {
        ElegantToast.show(context, title: 'Erreur', message: 'Réunion introuvable', type: ElegantToastType.error);
        return;
      }
      final data = doc.data()!;
      final current = FirebaseAuth.instance.currentUser!;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MeetingScreen(
            meetingId: meetingId,
            meetingName: data['title'] as String? ?? 'Réunion',
            userId: current.uid,
            userName: current.displayName ?? current.email ?? 'Invité',
            userEmail: current.email,
            isHost: false,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => GuestJoinScreen(meetingId: meetingId)));
      }
    }
  }

  Future<void> _loadTerms() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) setState(() => _termsAccepted = prefs.getBool('crux_terms_accepted') ?? false);
    } catch (e) {
      if (mounted) setState(() => _termsAccepted = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_termsAccepted == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0A0F),
        body: Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3)),
      );
    }

    return StreamBuilder<User?>(
      stream: _authStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF0A0A0F),
            body: Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3)),
          );
        }

        if (_pendingMeetingId != null) {
          final mid = _pendingMeetingId!;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _pendingMeetingId = null);
              final current = FirebaseAuth.instance.currentUser;
              if (current != null && !current.isAnonymous) {
                _joinMeetingAsAuthenticatedUser(mid);
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => GuestJoinScreen(meetingId: mid)),
                );
              }
            }
          });
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
