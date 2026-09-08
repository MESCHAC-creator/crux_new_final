import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/colors.dart';

enum ElegantToastType { success, error, warning, info }

class ElegantToast extends StatefulWidget {
  final String title;
  final String message;
  final ElegantToastType type;
  final Duration duration;
  final VoidCallback onDismiss;

  const ElegantToast({
    super.key,
    required this.title,
    required this.message,
    required this.type,
    required this.duration,
    required this.onDismiss,
  });

  @override
  State<ElegantToast> createState() => _ElegantToastState();

  static OverlayEntry? _currentOverlayEntry;
  static Timer? _autoDismissTimer;

  static void show(
    BuildContext context, {
    required String title,
    required String message,
    required ElegantToastType type,
    Duration duration = const Duration(seconds: 4),
  }) {
    if (!context.mounted) return;

    // Dismiss existing toast if any
    dismissCurrent();

    final overlayState = Overlay.of(context);

    _currentOverlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          top: MediaQuery.of(context).padding.top + 16,
          left: 16,
          right: 16,
          child: Material(
            color: Colors.transparent,
            child: ElegantToast(
              title: title,
              message: message,
              type: type,
              duration: duration,
              onDismiss: () {
                dismissCurrent();
              },
            ),
          ),
        );
      },
    );

    overlayState.insert(_currentOverlayEntry!);

    _autoDismissTimer = Timer(duration, () {
      dismissCurrent();
    });
  }

  static void dismissCurrent() {
    _autoDismissTimer?.cancel();
    _autoDismissTimer = null;

    if (_currentOverlayEntry != null) {
      // We can let the widget handle its exit animation before removal if we want,
      // but to keep it robust and simple without global state-sync lag, we remove it.
      // Actually, we can use a local state controller or a callback.
      // Let's make a beautiful self-animating list or a stateful overlay entry.
      // To allow the exit animation to finish before removing, let's trigger it.
      _currentOverlayEntry?.remove();
      _currentOverlayEntry = null;
    }
  }
}

class _ElegantToastState extends State<ElegantToast>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _slideAnimation;
  late Animation<double> _opacityAnimation;
  late Animation<double> _scaleAnimation;

  double _dragOffset = 0.0;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(
        milliseconds: 550,
      ), // Framer motion feel: slightly longer, highly responsive physics
    );

    // Spring-like overshoot curve for entrance, fast-out for exit
    _slideAnimation = Tween<double>(begin: -80.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const ElasticOutCurve(0.85), // Soft bouncing spring physics
        reverseCurve: Curves.easeInBack,
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const ElasticOutCurve(0.85),
        reverseCurve: Curves.easeInBack,
      ),
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeIn,
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _controller.dispose();
    super.dispose();
  }

  void _dismissWithAnimation() {
    if (_isDisposed) return;
    _controller.reverse().then((_) {
      widget.onDismiss();
    });
  }

  Color _getTypeColor() {
    switch (widget.type) {
      case ElegantToastType.success:
        return AppColors.success;
      case ElegantToastType.error:
        return AppColors.error;
      case ElegantToastType.warning:
        return const Color(0xFFF59E0B);
      case ElegantToastType.info:
        return AppColors.info;
    }
  }

  IconData _getTypeIcon() {
    switch (widget.type) {
      case ElegantToastType.success:
        return Icons.check_circle_rounded;
      case ElegantToastType.error:
        return Icons.error_rounded;
      case ElegantToastType.warning:
        return Icons.warning_rounded;
      case ElegantToastType.info:
        return Icons.info_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final typeColor = _getTypeColor();
    final typeIcon = _getTypeIcon();

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final transformY = _slideAnimation.value + _dragOffset;
        return Opacity(
          opacity: _opacityAnimation.value,
          child: Transform.translate(
            offset: Offset(0, transformY),
            child: Transform.scale(scale: _scaleAnimation.value, child: child),
          ),
        );
      },
      child: GestureDetector(
        onVerticalDragUpdate: (details) {
          if (details.primaryDelta! < 0) {
            setState(() {
              _dragOffset += details.primaryDelta!;
            });
          }
        },
        onVerticalDragEnd: (details) {
          if (_dragOffset < -25.0) {
            _dismissWithAnimation();
          } else {
            setState(() {
              _dragOffset = 0.0;
            });
          }
        },
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(
              0xFF121624,
            ).withValues(alpha: 0.92), // Glass surface
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: typeColor.withValues(alpha: 0.25),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: typeColor.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 8),
                spreadRadius: 2,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Accent Icon with breathing ambient background
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: typeColor.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(typeIcon, color: typeColor, size: 22),
                      ),
                      const SizedBox(width: 14),
                      // Text Contents
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              style: GoogleFonts.spaceGrotesk(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              widget.message,
                              style: GoogleFonts.interTight(
                                color: const Color(0xFF8A8FA3),
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Close button
                      GestureDetector(
                        onTap: _dismissWithAnimation,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.03),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            color: Colors.white38,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Smooth Progress indicator at the bottom (shows duration remaining)
                _ToastProgressBar(duration: widget.duration, color: typeColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToastProgressBar extends StatefulWidget {
  final Duration duration;
  final Color color;

  const _ToastProgressBar({required this.duration, required this.color});

  @override
  State<_ToastProgressBar> createState() => _ToastProgressBarState();
}

class _ToastProgressBarState extends State<_ToastProgressBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: double.infinity,
          height: 3,
          color: Colors.white.withValues(alpha: 0.04),
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: 1.0 - _controller.value, // Shrinks as time runs out
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: const BorderRadius.only(
                  bottomRight: Radius.circular(3),
                  topRight: Radius.circular(3),
                ),
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.5),
                    blurRadius: 4,
                    spreadRadius: 0.5,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
