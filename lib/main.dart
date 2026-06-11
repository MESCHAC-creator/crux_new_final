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

final logger = Logger();

// ---------------------------------------------------------------------------
// Locales that flutter_localizations does NOT support natively.
// Any locale outside this set falls back to French for Material/Cupertino
// internals (button labels, date pickers, etc.) while our AppTranslations
// handles all visible app text in the correct language.
// ---------------------------------------------------------------------------
const _flutterUnsupportedLocales = {'ha', 'yo', 'mg', 'wo'};

/// Returns the locale to use for Material/Cupertino widgets.
/// For locales unsupported by flutter_localizations, falls back to French
/// so widgets never throw a "no localizations found" error.
Locale _materialFallback(Locale locale) =>
    _flutterUnsupportedLocales.contains(locale.languageCode)
        ? const Locale('fr')
        : locale;

// ---------------------------------------------------------------------------
// Fallback delegates — accept every locale, load French for unsupported ones.
// Applied globally in MaterialApp AND in _DeviceBlockedApp so the grey-screen
// can NEVER appear regardless of which screen is shown.
// ---------------------------------------------------------------------------
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

// The shared delegate list used in EVERY MaterialApp in this app.
const List<LocalizationsDelegate<dynamic>> _localizationsDelegates = [
  _FallbackMaterialLocalizationsDelegate.instance,
  _FallbackCupertinoLocalizationsDelegate.instance,
  GlobalWidgetsLocalizations.delegate,
];

// ---------------------------------------------------------------------------

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
/// Uses the same fallback delegates so it never grey-screens on any locale.
class _DeviceBlockedApp extends StatelessWidget {
  final String reason;
  const _DeviceBlockedApp({required this.reason});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: _localizationsDelegates,
      supportedLocales: LocaleProvider.languages.values.toList(),
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
            // Every locale the app supports — drives the language picker.
            supportedLocales: LocaleProvider.languages.values.toList(),
            // Force the user-chosen locale; Flutter won't override it.
            locale: localeProvider.locale,
            // Shared delegates: accept all locales, fall back to French for
            // the 4 locales (ha, yo, mg, wo) not in flutter_localizations.
            localizationsDelegates: _localizationsDelegates,
            // Safety net: if somehow locale ends up outside supportedLocales
            // (e.g. system locale on first launch), default to French.
            localeResolutionCallback: (locale, supported) {
              if (locale == null) return const Locale('fr');
              // Exact match first
              for (final s in supported) {
                if (s.languageCode == locale.languageCode) return s;
              }
              return const Locale('fr');
            },
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
  late final Stream<User?> _authStream;
  String? _pendingMeetingId; // set when app is opened via a deep link

  @override
  void initState() {
    super.initState();
    _authStream = FirebaseAuth.instance.authStateChanges();
    _loadTerms();
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    final appLinks = AppLinks();

    // App already open — stream of incoming links
    appLinks.uriLinkStream.listen((uri) {
      _handleDeepLink(uri);
    });

    // App started cold via a link
    final initialUri = await appLinks.getInitialLink();
    if (initialUri != null) {
      _handleDeepLink(initialUri);
    }
  }

  void _handleDeepLink(Uri uri) {
    // crux://join/MEETING_ID  OR  https://*.*/join/MEETING_ID
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
      setState(() => _pendingMeetingId = mid);
      return;
    }

    // If already authenticated (non-anonymous), route to home-screen join flow
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

  Future<void> _joinMeetingAsAuthenticatedUser(String meetingId) async {
    // Fetch meeting, then push MeetingScreen (passcode handled inside MeetingScreen)
    try {
      final doc = await FirebaseFirestore.instance
          .collection('meetings')
          .doc(meetingId)
          .get();
      if (!mounted) return;
      if (!doc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Réunion introuvable')),
        );
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
      // Fallback to guest join screen on error
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => GuestJoinScreen(meetingId: meetingId)),
        );
      }
    }
  }

  Future<void> _loadTerms() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _termsAccepted = prefs.getBool('crux_terms_accepted') ?? false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0A0A0F) : AppColors.whiteBg;

    // While SharedPreferences hasn't loaded yet, show spinner
    if (_termsAccepted == null) {
      return Scaffold(
        backgroundColor: bg,
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3),
        ),
      );
    }

    return StreamBuilder<User?>(
      stream: _authStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: bg,
            body: const Center(
              child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3),
            ),
          );
        }

        // Deep link pending — route based on auth state
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
