import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'wallpaper_config.dart';

/// Gère la persistance des préférences de fond d'écran CRUX.
///
/// CORRECTIFS :
///   * `_prefs` n'est plus `late` : si `init()` n'a pas encore été appelé,
///     on renvoie la configuration par défaut au lieu de lancer une
///     LateInitializationError qui écran-noircissait l'application ;
///   * les fichiers importés sont nettoyés de façon asynchrone et tolérante
///     aux erreurs (un fichier verrouillé ne fait plus planter l'import) ;
///   * `importImage` conserve l'extension d'origine.
class WallpaperManager {
  static const String _prefsKey = 'crux_wallpaper_config';
  static const String _folderName = 'wallpaper';

  SharedPreferences? _prefs;

  static final WallpaperManager _instance = WallpaperManager._internal();
  factory WallpaperManager() => _instance;
  WallpaperManager._internal();

  bool get isReady => _prefs != null;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// Configuration persistée, ou celle par défaut si rien n'est lisible.
  WallpaperConfig get configOrDefault {
    final prefs = _prefs;
    if (prefs == null) return WallpaperConfig.defaultConfig;

    final json = prefs.getString(_prefsKey);
    if (json == null || json.isEmpty) return WallpaperConfig.defaultConfig;

    try {
      final config = WallpaperConfig.fromJsonString(json);
      // L'image a pu être supprimée par le système : on ne référence jamais
      // un fichier absent (sinon Image.file jette une exception au build).
      if (config.hasImage && !File(config.imagePath!).existsSync()) {
        return WallpaperConfig.defaultConfig;
      }
      return config;
    } catch (_) {
      return WallpaperConfig.defaultConfig;
    }
  }

  /// Ancien nom conservé pour compatibilité.
  WallpaperConfig get config => configOrDefault;

  Future<Directory> _wallpaperDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/$_folderName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Copie l'image sélectionnée dans le stockage interne et renvoie le chemin
  /// stable. Indispensable : l'URI renvoyée par le Photo Picker expire à la
  /// fin du processus.
  Future<String> importImage(String sourcePath) async {
    final dir = await _wallpaperDir();

    var extension =
        sourcePath.contains('.')
            ? sourcePath.split('.').last.toLowerCase()
            : 'jpg';
    if (extension.length > 5) extension = 'jpg';

    final target = File(
      '${dir.path}/wallpaper_${DateTime.now().millisecondsSinceEpoch}.$extension',
    );
    await File(sourcePath).copy(target.path);

    // Nettoyage des anciens fonds pour ne pas remplir le stockage.
    await for (final entity in dir.list()) {
      if (entity.path == target.path) continue;
      try {
        await entity.delete(recursive: true);
      } catch (_) {
        // Fichier encore utilisé par le rendu : sans gravité.
      }
    }

    return target.path;
  }

  Future<void> save(WallpaperConfig config) async {
    await init();
    await _prefs!.setString(_prefsKey, config.toJsonString());
  }

  Future<void> reset() async {
    await init();
    try {
      final dir = await _wallpaperDir();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // Rien à supprimer.
    }
    await _prefs!.remove(_prefsKey);
  }
}
