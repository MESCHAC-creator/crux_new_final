import 'package:flutter/material.dart';
import '../conference_theme.dart';
import '../colors.dart';

class ConferenceAnimations {
  ConferenceAnimations._();

  // Speaker appearance animation
  static Widget speakerAppearance({
    required Widget child,
    required AnimationController controller,
  }) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final scale = ConferenceTheme.speakerAppearanceAnimation(controller);
        return Transform.scale(
          scale: scale.value,
          child: FadeTransition(
            opacity: controller,
            child: child,
          ),
        );
      },
      child: child,
    );
  }

  // Particle emitter for emoji reactions
  static Widget particleEmitter({
    required Widget child,
    required AnimationController controller,
  }) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return FadeTransition(
          opacity: Tween<double>(begin: 1.0, end: 0.0).animate(
            CurvedAnimation(
              parent: controller,
              curve: ConferenceTheme.emojiCurve,
            ),
          ),
          child: child,
        );
      },
      child: child,
    );
  }

  // Pulse ring for audio activity
  static Widget pulseRing({
    required Widget child,
    required AnimationController controller,
    required double audioLevel,
  }) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final pulse = Tween<double>(begin: 1.0, end: 1.0 + audioLevel * 0.3).animate(
          CurvedAnimation(
            parent: controller,
            curve: Curves.easeInOut,
          ),
        );
        
        return Transform.scale(
          scale: pulse.value,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: ConferenceTheme.audioWave.withValues(alpha: audioLevel * 0.5),
                width: 2,
              ),
            ),
            child: child,
          ),
        );
      },
      child: child,
    );
  }

  // Stats gauge animation for network metrics
  static Widget statsGauge({
    required Widget child,
    required AnimationController controller,
    required double value,
    required double maxValue,
  }) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final progress = (value / maxValue).clamp(0.0, 1.0);
        final animatedProgress = Tween<double>(begin: 0.0, end: progress).animate(
          CurvedAnimation(
            parent: controller,
            curve: Curves.easeOut,
          ),
        );
        
        return CustomPaint(
          painter: _StatsGaugePainter(
            progress: animatedProgress.value,
            color: _getStatsColor(value, maxValue),
          ),
          child: child,
        );
      },
      child: child,
    );
  }

  static Color _getStatsColor(double value, double maxValue) {
    final ratio = value / maxValue;
    if (ratio < 0.33) return AppColors.networkExcellent;
    if (ratio < 0.66) return AppColors.networkGood;
    if (ratio < 0.9) return AppColors.networkPoor;
    return AppColors.networkCritical;
  }

  // Slide transition for layout changes
  static Widget layoutTransition({
    required Widget child,
    required AnimationController controller,
    SlideDirection direction = SlideDirection.left,
  }) {
    return SlideTransition(
      position: _getSlideAnimation(direction, controller),
      child: FadeTransition(
        opacity: controller,
        child: child,
      ),
    );
  }

  static Animation<Offset> _getSlideAnimation(
    SlideDirection direction,
    AnimationController controller,
  ) {
    Offset begin;
    switch (direction) {
      case SlideDirection.left:
        begin = const Offset(-1.0, 0);
        break;
      case SlideDirection.right:
        begin = const Offset(1.0, 0);
        break;
      case SlideDirection.up:
        begin = const Offset(0, 1.0);
        break;
      case SlideDirection.down:
        begin = const Offset(0, -1.0);
        break;
    }
    
    return Tween<Offset>(begin: begin, end: Offset.zero).animate(
      CurvedAnimation(
        parent: controller,
        curve: ConferenceTheme.layoutCurve,
      ),
    );
  }

  // Shimmer effect for loading states
  static Widget shimmer({
    required Widget child,
    required AnimationController controller,
  }) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.transparent,
                Colors.white.withValues(alpha: 0.3),
                Colors.transparent,
              ],
              stops: [
                controller.value - 0.3,
                controller.value,
                controller.value + 0.3,
              ],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: child,
    );
  }

  // Bounce animation for interactive elements
  static Widget bounce({
    required Widget child,
    required AnimationController controller,
  }) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final scale = Tween<double>(begin: 1.0, end: 1.1).animate(
          CurvedAnimation(
            parent: controller,
            curve: Curves.elasticOut,
          ),
        );
        
        return Transform.scale(
          scale: scale.value,
          child: child,
        );
      },
      child: child,
    );
  }

  // Rotation animation for loading indicators
  static Widget rotation({
    required Widget child,
    required AnimationController controller,
  }) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return Transform.rotate(
          angle: controller.value * 6.28319, // 2 * PI
          child: child,
        );
      },
      child: child,
    );
  }
}

enum SlideDirection {
  left,
  right,
  up,
  down,
}

class _StatsGaugePainter extends CustomPainter {
  final double progress;
  final Color color;

  _StatsGaugePainter({
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;
    
    // Background
    final backgroundPaint = Paint()
      ..color = AppColors.borderSubtle
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    
    canvas.drawCircle(center, radius, backgroundPaint);
    
    // Progress arc
    if (progress > 0) {
      final progressPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      
      final startAngle = -3.14159 / 2; // Start from top
      final sweepAngle = progress * 6.28319; // 2 * PI
      
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_StatsGaugePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}