import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ColorProvider extends ChangeNotifier {
  static const _key = 'crux_accent_color';

  // Predefined palette — iOS 26 inspired
  static const List<_ColorOption> palette = [
    _ColorOption('Rouge Crux',   Color(0xFFE74C3C), Color(0xFF9B59B6)),
    _ColorOption('Océan',        Color(0xFF0EA5E9), Color(0xFF6366F1)),
    _ColorOption('Forêt',        Color(0xFF10B981), Color(0xFF0EA5E9)),
    _ColorOption('Aurore',       Color(0xFFF59E0B), Color(0xFFEF4444)),
    _ColorOption('Minuit',       Color(0xFF6366F1), Color(0xFF8B5CF6)),
    _ColorOption('Rose',         Color(0xFFEC4899), Color(0xFF8B5CF6)),
    _ColorOption('Corail',       Color(0xFFFF6B6B), Color(0xFFFFE66D)),
    _ColorOption('Citron',       Color(0xFF84CC16), Color(0xFF22D3EE)),
  ];

  int _selectedIndex = 0;

  int get selectedIndex => _selectedIndex;
  Color get primary => palette[_selectedIndex].start;
  Color get secondary => palette[_selectedIndex].end;
  LinearGradient get gradient => LinearGradient(
    colors: [palette[_selectedIndex].start, palette[_selectedIndex].end],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  String get name => palette[_selectedIndex].name;

  ColorProvider() { _load(); }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedIndex = (prefs.getInt(_key) ?? 0).clamp(0, palette.length - 1);
    notifyListeners();
  }

  Future<void> setColor(int index) async {
    _selectedIndex = index.clamp(0, palette.length - 1);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, _selectedIndex);
    notifyListeners();
  }
}

class _ColorOption {
  final String name;
  final Color start;
  final Color end;
  const _ColorOption(this.name, this.start, this.end);
}
