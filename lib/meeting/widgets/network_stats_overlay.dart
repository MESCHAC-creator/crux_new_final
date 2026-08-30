import 'package:flutter/material.dart';
import '../../theme/colors.dart';

class NetworkStatsOverlay extends StatefulWidget {
  final double fps;
  final int latency;
  final double bandwidth;
  final double jitter;
  final VoidCallback? onTap;

  const NetworkStatsOverlay({
    super.key,
    this.fps = 60.0,
    this.latency = 0,
    this.bandwidth = 0.0,
    this.jitter = 0.0,
    this.onTap,
  });

  @override
  State<NetworkStatsOverlay> createState() => _NetworkStatsOverlayState();
}

class _NetworkStatsOverlayState extends State<NetworkStatsOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  Offset _position = const Offset(20, 80);
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _isExpanded = !_isExpanded;
          });
          widget.onTap?.call();
        },
        onPanUpdate: (details) {
          setState(() {
            _position += details.delta;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: _isExpanded ? 200 : 100,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _getNetworkQualityColor(),
              width: 2,
            ),
            boxShadow: AppColors.softShadow,
          ),
          child: _isExpanded ? _buildExpandedStats() : _buildCompactStats(),
        ),
      ),
    );
  }

  Widget _buildCompactStats() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getNetworkQualityIcon(),
              size: 20,
              color: _getNetworkQualityColor(),
            ),
            const SizedBox(width: 8),
            Text(
              '${widget.fps.toInt()} FPS',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _buildLatencyGauge(),
      ],
    );
  }

  Widget _buildExpandedStats() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              _getNetworkQualityIcon(),
              size: 16,
              color: _getNetworkQualityColor(),
            ),
            const SizedBox(width: 4),
            const Text(
              'Réseau',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildStatRow('FPS', '${widget.fps.toInt()}'),
        _buildStatRow('Latence', '${widget.latency}ms'),
        _buildStatRow('Bande passante', '${widget.bandwidth.toStringAsFixed(1)} Mbps'),
        _buildStatRow('Jitter', '${widget.jitter.toStringAsFixed(1)}ms'),
        const SizedBox(height: 8),
        _buildLatencyGauge(),
      ],
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLatencyGauge() {
    final latencyRatio = (widget.latency / 200).clamp(0.0, 1.0);
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Container(
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(2),
          ),
          child: FractionallySizedBox(
            widthFactor: latencyRatio * _pulseAnimation.value,
            alignment: Alignment.centerLeft,
            child: Container(
              decoration: BoxDecoration(
                color: _getLatencyColor(),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        );
      },
    );
  }

  Color _getNetworkQualityColor() {
    if (widget.latency < 50) return AppColors.networkExcellent;
    if (widget.latency < 100) return AppColors.networkGood;
    if (widget.latency < 150) return AppColors.networkPoor;
    return AppColors.networkCritical;
  }

  IconData _getNetworkQualityIcon() {
    if (widget.latency < 50) return Icons.signal_cellular_alt;
    if (widget.latency < 100) return Icons.signal_cellular_4_bar;
    if (widget.latency < 150) return Icons.signal_cellular_alt_2_bar;
    return Icons.signal_cellular_0_bar;
  }

  Color _getLatencyColor() {
    if (widget.latency < 50) return AppColors.networkExcellent;
    if (widget.latency < 100) return AppColors.networkGood;
    if (widget.latency < 150) return AppColors.networkPoor;
    return AppColors.networkCritical;
  }
}