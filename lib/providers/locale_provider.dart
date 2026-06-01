import 'package:flutter/material.dart';

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

  void setLanguage(String label) {
    final locale = languages[label];
    if (locale != null) {
      _locale = locale;
      _languageLabel = label;
      notifyListeners();
    }
  }
}
