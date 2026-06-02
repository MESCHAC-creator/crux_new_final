import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleProvider extends ChangeNotifier {
  Locale _locale = const Locale('fr');
  String _languageLabel = 'Français';

  Locale get locale => _locale;
  String get languageLabel => _languageLabel;

  static const Map<String, Locale> languages = {
    'Français': Locale('fr'),
    'English': Locale('en'),
    'Español': Locale('es'),
    'Deutsch': Locale('de'),
  };

  LocaleProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('crux_language') ?? 'fr';
    final entry = languages.entries.firstWhere(
      (e) => e.value.languageCode == code,
      orElse: () => const MapEntry('Français', Locale('fr')),
    );
    _locale = entry.value;
    _languageLabel = entry.key;
    notifyListeners();
  }

  Future<void> setLanguage(String label) async {
    final loc = languages[label];
    if (loc != null) {
      _locale = loc;
      _languageLabel = label;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('crux_language', loc.languageCode);
      notifyListeners();
    }
  }
}
