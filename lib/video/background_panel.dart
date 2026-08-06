import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/colors.dart';
import '../wallpaper/glass_surface.dart';
import 'virtual_background_controller.dart';
import 'virtual_background_mode.dart';

/// Bandeau compact de sélection du fond vidéo virtuel (segmentation MLKit).
/// Affiché entre la grille de participants et la barre de contrôles.
class BackgroundPanel extends StatelessWidget {
  final VirtualBackgroundController controller;

  const BackgroundPanel({super.key, required this.controller});

  Future<void> _pickImage(BuildContext context) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      controller.setMode(VirtualBackgroundImage(File(picked.path)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = controller.mode;

    return GlassSurface(
      borderRadius: 16,
      child: SizedBox(
        height: 56,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          children: [
            _BgOption(
              label: 'Aucun',
              icon: Icons.block,
              selected: mode is VirtualBackgroundNone,
              onTap: () => controller.setMode(const VirtualBackgroundNone()),
            ),
            const SizedBox(width: 8),
            _BgOption(
              label: 'Flou léger',
              icon: Icons.blur_on,
              selected: mode is VirtualBackgroundBlurLight,
              onTap: () =>
                  controller.setMode(const VirtualBackgroundBlurLight()),
            ),
            const SizedBox(width: 8),
            _BgOption(
              label: 'Flou fort',
              icon: Icons.blur_circular,
              selected: mode is VirtualBackgroundBlurStrong,
              onTap: () =>
                  controller.setMode(const VirtualBackgroundBlurStrong()),
            ),
            const SizedBox(width: 8),
            _BgOption(
              label: 'Image',
              icon: Icons.image,
              selected: mode is VirtualBackgroundImage,
              onTap: () => _pickImage(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _BgOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _BgOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withOpacity(0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color:
                        selected ? AppColors.primary : AppColors.textSecondary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
