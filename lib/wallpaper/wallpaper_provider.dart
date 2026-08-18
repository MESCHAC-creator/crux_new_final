import 'package:flutter/foundation.dart';

import '../wallpaper/wallpaper_config.dart';
import '../wallpaper/wallpaper_manager.dart';

/// Expose le fond d'écran CRUX comme un [ChangeNotifier] : tout écran qui
/// l'écoute (accueil, réunions...) se met à jour en direct dès qu'il change,
/// sans avoir besoin de rafraîchir manuellement après un retour d'écran.
class WallpaperProvider extends ChangeNotifier {
  WallpaperConfig _config;

  WallpaperProvider() : _config = WallpaperManager().config;

  /// Configuration actuellement affichée (aperçu compris — voir [preview]).
  WallpaperConfig get config => _config;

  /// Met à jour l'aperçu en direct (slider, bascule...) sans le persister.
  /// Utilisé pendant le réglage, et pour restaurer l'état d'origine si
  /// l'utilisateur quitte l'écran de sélection sans valider.
  void preview(WallpaperConfig config) {
    _config = config;
    notifyListeners();
  }

  /// Importe l'image choisie dans le stockage interne, puis l'applique et
  /// la persiste immédiatement comme fond d'écran courant.
  Future<void> importAndApply(String sourcePath) async {
    final path = await WallpaperManager().importImage(sourcePath);
    await apply(_config.copyWith(imagePath: path));
  }

  /// Persiste la configuration donnée comme fond d'écran courant.
  Future<void> apply(WallpaperConfig config) async {
    await WallpaperManager().save(config);
    _config = config;
    notifyListeners();
  }

  /// Restaure le fond CRUX par défaut (et le persiste).
  Future<void> reset() async {
    await WallpaperManager().reset();
    _config = WallpaperConfig.defaultConfig;
    notifyListeners();
  }
}
