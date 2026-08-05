import 'dart:convert';

class WallpaperConfig {
  /// Chemin du fichier copié dans le stockage interne de l'app.
  /// null = fond par défaut du thème CRUX (gradient Obsidian).
  final String? imagePath;
  
  /// Rayon de flou en dp, 0..maxBlur. iOS utilise ~15-30 pour l'écran d'accueil.
  final double blurRadius;
  
  /// Flou progressif : très flou en haut, net en bas (comportement iOS 26).
  final bool progressiveBlur;
  
  /// Voile sombre par-dessus l'image, garantit le contraste du texte. 0.0..0.8
  final double scrim;

  static const double maxBlur = 50.0;
  static const double maxScrim = 0.8;

  const WallpaperConfig({
    this.imagePath,
    this.blurRadius = 0.0,
    this.progressiveBlur = false,
    this.scrim = 0.35,
  });

  bool get hasImage => imagePath != null && imagePath!.isNotEmpty;

  static const WallpaperConfig defaultConfig = WallpaperConfig();

  WallpaperConfig copyWith({
    String? imagePath,
    double? blurRadius,
    bool? progressiveBlur,
    double? scrim,
  }) {
    return WallpaperConfig(
      imagePath: imagePath ?? this.imagePath,
      blurRadius: blurRadius ?? this.blurRadius,
      progressiveBlur: progressiveBlur ?? this.progressiveBlur,
      scrim: scrim ?? this.scrim,
    );
  }

  Map<String, dynamic> toJson() => {
    'imagePath': imagePath,
    'blurRadius': blurRadius,
    'progressiveBlur': progressiveBlur,
    'scrim': scrim,
  };

  factory WallpaperConfig.fromJson(Map<String, dynamic> json) => WallpaperConfig(
    imagePath: json['imagePath'] as String?,
    blurRadius: (json['blurRadius'] as num?)?.toDouble() ?? 0.0,
    progressiveBlur: json['progressiveBlur'] as bool? ?? false,
    scrim: (json['scrim'] as num?)?.toDouble() ?? 0.35,
  );

  String toJsonString() => jsonEncode(toJson());
  
  factory WallpaperConfig.fromJsonString(String json) => 
    WallpaperConfig.fromJson(jsonDecode(json));
}