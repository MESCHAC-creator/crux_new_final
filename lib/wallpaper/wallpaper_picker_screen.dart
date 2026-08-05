import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../theme/colors.dart';
import '../l10n/app_translations.dart';
import 'wallpaper_config.dart';
import 'wallpaper_manager.dart';
import 'app_background.dart';
import 'glass_surface.dart';
import '../providers/locale_provider.dart';

/// Écran de sélection du fond d'écran CRUX.
/// L'aperçu EST le fond réel : ce que vous voyez est ce que vous obtenez.
class WallpaperPickerScreen extends StatefulWidget {
  const WallpaperPickerScreen({super.key});

  @override
  State<WallpaperPickerScreen> createState() => _WallpaperPickerScreenState();
}

class _WallpaperPickerScreenState extends State<WallpaperPickerScreen> {
  late WallpaperConfig _draft;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _draft = WallpaperManager().config;
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      final path = await WallpaperManager().importImage(picked.path);
      setState(() => _draft = _draft.copyWith(imagePath: path));
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.read<LocaleProvider>().locale.languageCode;
    final t = AppTranslations.of(context);

    return AppBackground(
      config: _draft,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(t.get('wallpaper_title', lang) ?? 'Fond d\'écran'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GlassSurface(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _LabeledSlider(
                        label: t.get('blur', lang) ?? 'Floutage',
                        value: _draft.blurRadius,
                        max: WallpaperConfig.maxBlur,
                        display: '${_draft.blurRadius.round()} dp',
                        enabled: _draft.hasImage,
                        onChanged: (v) => setState(
                            () => _draft = _draft.copyWith(blurRadius: v)),
                      ),
                      _LabeledSlider(
                        label: t.get('scrim', lang) ?? 'Assombrissement',
                        value: _draft.scrim,
                        max: WallpaperConfig.maxScrim,
                        display:
                            '${(_draft.scrim / WallpaperConfig.maxScrim * 100).round()} %',
                        enabled: _draft.hasImage,
                        onChanged: (v) =>
                            setState(() => _draft = _draft.copyWith(scrim: v)),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.get('progressive_blur', lang) ??
                                      'Flou progressif',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyLarge
                                      ?.copyWith(
                                        color: AppColors.textPrimary,
                                      ),
                                ),
                                Text(
                                  t.get('progressive_blur_desc', lang) ??
                                      'Flou en haut, net en bas — améliore la lisibilité',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _draft.progressiveBlur,
                            onChanged: _draft.hasImage
                                ? (v) => setState(() => _draft =
                                    _draft.copyWith(progressiveBlur: v))
                                : null,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.image),
                      label: Text(
                          t.get('choose_photo', lang) ?? 'Choisir une photo'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() => _draft = WallpaperConfig.defaultConfig);
                      WallpaperManager().reset();
                    },
                    icon: const Icon(Icons.restore),
                    label: const Text(''),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _draft.hasImage
                    ? () async {
                        await WallpaperManager().save(_draft);
                        if (mounted) Navigator.pop(context);
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
                child: Text(t.get('apply', lang) ?? 'Appliquer'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  final String label;
  final double value;
  final double max;
  final String display;
  final bool enabled;
  final ValueChanged<double> onChanged;

  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.max,
    required this.display,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppColors.textPrimary,
                  ),
            ),
            Text(
              display,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ),
        Slider(
          value: value,
          max: max,
          onChanged: enabled ? onChanged : null,
        ),
      ],
    );
  }
}
