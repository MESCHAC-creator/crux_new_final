import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../theme/colors.dart';
import '../providers/locale_provider.dart';
import 'meeting_state.dart';
import '../wallpaper/glass_surface.dart';

/// En-tête de réunion CRUX avec durée, santé, copie lien.
/// Corrige le manque de Meet : durée au lieu de l'heure.
class MeetingHeader extends StatelessWidget {
  final int elapsedSeconds;
  final String roomUrl;
  final CallHealth health;

  const MeetingHeader({
    super.key,
    required this.elapsedSeconds,
    required this.roomUrl,
    required this.health,
  });

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Row(
          children: [
            // Durée écoulée, jamais l'heure courante
            Text(
              _formatDuration(elapsedSeconds),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 16),
            _HealthIndicator(health: health),
            const Spacer(),
            // Copie du lien en un seul tap
            IconButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: roomUrl));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Lien copié')),
                );
              },
              icon: const Icon(Icons.copy, color: AppColors.textSecondary),
              tooltip: 'Copier le lien',
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

class _HealthIndicator extends StatelessWidget {
  final CallHealth health;

  const _HealthIndicator({required this.health});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (health.level) {
      CallHealthLevel.good => (AppColors.success, 'Connexion bonne'),
      CallHealthLevel.fair => (const Color(0xFFF6C445), 'Connexion moyenne'),
      CallHealthLevel.poor => (AppColors.error, 'Connexion faible'),
    };

    return Chip(
      avatar: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
      label: Text(
        '${health.rttMs} ms',
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 12,
        ),
      ),
      backgroundColor: AppColors.surface.withOpacity(0.8),
      side: BorderSide.none,
    );
  }
}
