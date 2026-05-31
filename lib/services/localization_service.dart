import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalizationService {
  static final LocalizationService _instance = LocalizationService._internal();
  static const String _languageKey = 'selected_language';

  late SharedPreferences _prefs;
  String _currentLanguage = 'en';

  factory LocalizationService() => _instance;

  LocalizationService._internal();

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    _currentLanguage = _prefs.getString(_languageKey) ?? 'en';
  }

  Locale get locale => Locale(_currentLanguage);

  String get currentLanguage => _currentLanguage;

  Future<void> setLanguage(String languageCode) async {
    _currentLanguage = languageCode;
    await _prefs.setString(_languageKey, languageCode);
  }

  // Supported languages
  static const List<String> supportedLanguages = ['en', 'fr', 'es', 'ru', 'de'];
  static const Map<String, String> languageNames = {
    'en': 'English',
    'fr': 'Français',
    'es': 'Español',
    'ru': 'Русский',
    'de': 'Deutsch',
  };
}

class AppLocalizations {
  final Locale locale;
  final Map<String, String> _translations;

  AppLocalizations(this.locale, this._translations);

  static AppLocalizations? _current;

  static AppLocalizations get current => _current!;

  String get(String key, {String defaultValue = ''}) {
    return _translations[key] ?? defaultValue;
  }

  // Convenience getters
  String get appName => get('appName', defaultValue: 'CRUX');
  String get welcome => get('welcome');
  String get signIn => get('signIn');
  String get signUp => get('signUp');
  String get email => get('email');
  String get password => get('password');
  String get fullName => get('fullName');
  String get home => get('home');
  String get settings => get('settings');
  String get logout => get('logout');
  String get participants => get('participants');
  String get mute => get('mute');
  String get unmute => get('unmute');
  String get camera => get('camera');
  String get screenShare => get('screenShare');
  String get chat => get('chat');
  String get reactions => get('reactions');
  String get recordingStarted => get('recordingStarted');
  String get recordingStopped => get('recordingStopped');
  String get waitingRoom => get('waitingRoom');
  String get admit => get('admit');
  String get reject => get('reject');
  String get admitAll => get('admitAll');
  String get muteAll => get('muteAll');
  String get unmuteSelf => get('unmuteSelf');
  String get hostControls => get('hostControls');
}
