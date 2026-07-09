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
    'Русский': Locale('ru'),
    'Português': Locale('pt'),
    'Italiano': Locale('it'),
    'العربية': Locale('ar'),
    '中文': Locale('zh'),
    'हिन्दी': Locale('hi'),
    '日本語': Locale('ja'),
    '한국어': Locale('ko'),
    'Türkçe': Locale('tr'),
    'Tiếng Việt': Locale('vi'),
    'Bahasa Indonesia': Locale('id'),
    'Nederlands': Locale('nl'),
    'Polski': Locale('pl'),
    'Українська': Locale('uk'),
    'Svenska': Locale('sv'),
    'Hausa': Locale('ha'),
    'Yorùbá': Locale('yo'),
    'Kiswahili': Locale('sw'),
    'አማርኛ': Locale('am'),
    'فارسی': Locale('fa'),
    'Română': Locale('ro'),
    'Ελληνικά': Locale('el'),
    'Čeština': Locale('cs'),
    'Magyar': Locale('hu'),
    'বাংলা': Locale('bn'),
    'ภาษาไทย': Locale('th'),
    'Malagasy': Locale('mg'),
    'Wolof': Locale('wo'),
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
      notifyListeners(); // Immediate UI update — no grey screen
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('crux_language', loc.languageCode);
    }
  }
}
