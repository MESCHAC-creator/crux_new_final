import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'wallpaper_config.dart';

/// Gère la persistance des préférences de fond d'écran CRUX.
class WallpaperManager {
  static const String _prefsKey = 'crux_wallpaper_config';

  late SharedPreferences _prefs;
  static final WallpaperManager _instance = WallpaperManager._internal();
  factory WallpaperManager() => _instance;
  WallpaperManager._internal();

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  WallpaperConfig get config {
    final json = _prefs.getString(_prefsKey);
    if (json == null) return WallpaperConfig.defaultConfig;
    try {
      return WallpaperConfig.fromJsonString(json);
    } catch (_) {
      return WallpaperConfig.defaultConfig;
    }
  }

  /// Copie l'image sélectionnée dans le stockage interne et renvoie le chemin stable.
  /// Indispensable : l'URI renvoyée par le Photo Picker expire à la fin du processus.
  Future<String> importImage(String sourcePath) async {
    final dir = Directory(
        '${(await getApplicationDocumentsDirectory()).path}/wallpaper');
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final target = File(
        '${dir.path}/wallpaper_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await File(sourcePath).copy(target.path);

    // Nettoyage des anciens fonds pour ne pas remplir le stockage
    dir
        .listSync()
        .where((f) => f.path != target.path)
        .forEach((f) => f.deleteSync());

    return target.path;
  }

  Future<void> save(WallpaperConfig config) async {
    await _prefs.setString(_prefsKey, config.toJsonString());
  }

  Future<void> reset() async {
    final dir = Directory(
        '${(await getApplicationDocumentsDirectory()).path}/wallpaper');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    await _prefs.remove(_prefsKey);
  }
}
