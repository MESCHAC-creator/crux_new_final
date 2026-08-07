import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/colors.dart';

enum NetworkQuality { excellent, good, poor, critical, unknown }

class NetworkStats {
  final double latencyMs;
  final double jitterMs;
  final double packetLossPercent;
  final int bitrateKbps;

  const NetworkStats({
    required this.latencyMs,
    required this.jitterMs,
    required this.packetLossPercent,
    required this.bitrateKbps,
  });

  NetworkQuality get quality {
    if (latencyMs > 300 || packetLossPercent > 10) return NetworkQuality.critical;
    if (latencyMs > 150 || packetLossPercent > 5 || jitterMs > 30) {
      return NetworkQuality.poor;
    }
    if (latencyMs > 80 || packetLossPercent > 1 || jitterMs > 15) {
      return NetworkQuality.good;
    }
    return NetworkQuality.excellent;
  }

  Color get color {
    switch (quality) {
      case NetworkQuality.excellent:
        return AppColors.networkExcellent;
      case NetworkQuality.good:
        return AppColors.networkGood;
      case NetworkQuality.poor:
        return AppColors.networkPoor;
      case NetworkQuality.critical:
        return AppColors.networkCritical;
      case NetworkQuality.unknown:
        return AppColors.textTertiary;
    }
  }

  String get label {
    switch (quality) {
      case NetworkQuality.excellent:
        return 'Excellent';
      case NetworkQuality.good:
        return 'Bon';
      case NetworkQuality.poor:
        return 'Faible';
      case NetworkQuality.critical:
        return 'Critique';
      case NetworkQuality.unknown:
        return 'Inconnu';
    }
  }

  String get summary =>
      '${latencyMs.toStringAsFixed(0)}ms · ${packetLossPercent.toStringAsFixed(1)}% perte';
}

/// Widget compact (3 barres) affiché dans la toolbar de réunion
class NetworkQualityBars extends StatelessWidget {
  final NetworkStats? stats;
  final VoidCallback? onTap;

  const NetworkQualityBars({super.key, this.stats, this.onTap});

  @override
  Widget build(BuildContext context) {
    final quality = stats?.quality ?? NetworkQuality.unknown;
    final color = stats?.color ?? AppColors.textTertiary;

    return GestureDetector(
      onTap: onTap != null
          ? () => _showNetworkDetails(context)
          : null,
      child: Tooltip(
        message: stats != null
            ? '${stats!.label} — ${stats!.summary}'
            : 'Réseau inconnu',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(3, (i) {
            final isActive = _barActive(quality, i);
            return Container(
              width: 4,
              height: 6.0 + i * 4.0,
              margin: const EdgeInsets.only(right: 2),
              decoration: BoxDecoration(
                color: isActive ? color : color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        ),
      ),
    );
  }

  bool _barActive(NetworkQuality q, int barIndex) {
    switch (q) {
      case NetworkQuality.excellent:
        return true;
      case NetworkQuality.good:
        return barIndex <= 1;
      case NetworkQuality.poor:
        return barIndex == 0;
      case NetworkQuality.critical:
      case NetworkQuality.unknown:
        return false;
    }
  }

  void _showNetworkDetails(BuildContext context) {
    if (stats == null) return;
    showModalBottomSheet(
      context: context,
      builder: (_) => _NetworkDetailsSheet(stats: stats!),
    );
  }
}

/// Sheet détaillé — pour les utilisateurs qui veulent diagnostiquer
class _NetworkDetailsSheet extends StatelessWidget {
  final NetworkStats stats;
  const _NetworkDetailsSheet({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: stats.color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: stats.color.withOpacity(0.4), blurRadius: 6),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Réseau ${stats.label}',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _StatRow(
            label: 'Latence',
            value: '${stats.latencyMs.toStringAsFixed(0)} ms',
            isGood: stats.latencyMs < 80,
            isWarning: stats.latencyMs < 150,
          ),
          const Divider(height: 1, color: AppColors.divider),
          _StatRow(
            label: 'Gigue (Jitter)',
            value: '${stats.jitterMs.toStringAsFixed(1)} ms',
            isGood: stats.jitterMs < 15,
            isWarning: stats.jitterMs < 30,
          ),
          const Divider(height: 1, color: AppColors.divider),
          _StatRow(
            label: 'Perte de paquets',
            value: '${stats.packetLossPercent.toStringAsFixed(2)}%',
            isGood: stats.packetLossPercent < 1,
            isWarning: stats.packetLossPercent < 5,
          ),
          const Divider(height: 1, color: AppColors.divider),
          _StatRow(
            label: 'Débit',
            value: '${stats.bitrateKbps} kbps',
            isGood: stats.bitrateKbps > 500,
            isWarning: stats.bitrateKbps > 200,
          ),
          if (stats.quality == NetworkQuality.poor ||
              stats.quality == NetworkQuality.critical) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warningSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.warning.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.tips_and_updates_outlined,
                      color: AppColors.warning, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Conseil : désactivez la caméra pour économiser la bande passante',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 12,
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isGood;
  final bool isWarning;

  const _StatRow({
    required this.label,
    required this.value,
    required this.isGood,
    required this.isWarning,
  });

  Color get _color {
    if (isGood) return AppColors.success;
    if (isWarning) return AppColors.warning;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                value,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Dot simple pour l'AppBar (home screen)
class NetworkQualityDot extends StatefulWidget {
  final NetworkStats? stats;
  const NetworkQualityDot({super.key, this.stats});

  @override
  State<NetworkQualityDot> createState() => _NetworkQualityDotState();
}

class _NetworkQualityDotState extends State<NetworkQualityDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stats = widget.stats;
    final color = stats?.color ?? AppColors.networkExcellent;
    final quality = stats?.quality ?? NetworkQuality.excellent;

    return Tooltip(
      message: stats != null ? 'Réseau : ${stats.label}' : 'Connexion active',
      child: FadeTransition(
        opacity: quality == NetworkQuality.critical ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: color.withOpacity(0.5), blurRadius: 6, spreadRadius: 1)],
          ),
        ),
      ),
    );
  }
}
