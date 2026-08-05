import 'package:flutter/material.dart';
import '../theme/colors.dart';

/// Surface en verre dépoli CRUX — utilisée pour les panels flottants.
/// Équivalent du .ultraThinMaterial de iOS, adapté au thème Obsidian CRUX.
class GlassSurface extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final double opacity;

  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = 20.0,
    this.opacity = 0.72,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface.withOpacity(opacity),
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(
            color: Colors.white.withOpacity(0.08),
            width: 1,
          ),
        ),
        child: child,
      ),
    );
  }
}
