import 'package:flutter/foundation.dart';

import '../wallpaper/wallpaper_config.dart';
import '../wallpaper/wallpaper_manager.dart';

/// Expose le fond d'écran choisi par l'utilisateur à toute l'application.
///
/// Avant ce provider, `WallpaperManager` n'était lu qu'au moment d'ouvrir le
/// sélecteur : l'image importée n'apparaissait jamais sur l'accueil et
/// l'application ne se redessinait pas après « Appliquer ».
class WallpaperProvider extends ChangeNotifier {
  WallpaperProvider() {
    _config = WallpaperManager().configOrDefault;
  }

  WallpaperConfig _config = WallpaperConfig.defaultConfig;

  WallpaperConfig get config => _config;

  bool get hasCustomImage => _config.hasImage;

  /// Recharge depuis le stockage (utile après un init tardif).
  void refresh() {
    _config = WallpaperManager().configOrDefault;
    notifyListeners();
  }

  /// Importe une image depuis la galerie et l'applique immédiatement.
  Future<void> importAndApply(String sourcePath) async {
    final stored = await WallpaperManager().importImage(sourcePath);
    await apply(_config.copyWith(imagePath: stored));
  }

  /// Enregistre puis diffuse la configuration.
  Future<void> apply(WallpaperConfig config) async {
    _config = config;
    notifyListeners();
    await WallpaperManager().save(config);
  }

  /// Aperçu en direct sans écriture disque (sliders du sélecteur).
  void preview(WallpaperConfig config) {
    _config = config;
    notifyListeners();
  }

  /// Revient au fond CRUX par défaut et supprime les fichiers importés.
  Future<void> reset() async {
    _config = WallpaperConfig.defaultConfig;
    notifyListeners();
    await WallpaperManager().reset();
  }
}
