import 'package:flutter/material.dart';
import '../screens/splash_screen.dart';
import '../screens/login_screen.dart';
import '../screens/home_screen.dart';
import '../screens/meeting_screen.dart';
import '../screens/settings_screen.dart';
import '../models/user_model.dart';

class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';
  static const String home = '/home';
  static const String meeting = '/meeting';
  static const String settings = '/settings';

  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case splash:
        return MaterialPageRoute(builder: (_) => const SplashScreen());

      case login:
        return MaterialPageRoute(builder: (_) => const LoginScreen());

      case home:
        final user = settings.arguments as UserModel?;
        return MaterialPageRoute(
          builder: (_) => HomeScreen(user: user ?? UserModel(
            uid: '',
            email: '',
            name: 'Utilisateur',
          )),
        );

      case meeting:
        final args = settings.arguments as Map<String, dynamic>?;
        return MaterialPageRoute(
          builder: (_) => MeetingScreen(
            meetingId: args?['meetingId'] ?? '',
            meetingName: args?['meetingName'] ?? 'Réunion',
          ),
        );

      case settings:
        return MaterialPageRoute(builder: (_) => const SettingsScreen());

      default:
        return MaterialPageRoute(builder: (_) => const SplashScreen());
    }
  }
}