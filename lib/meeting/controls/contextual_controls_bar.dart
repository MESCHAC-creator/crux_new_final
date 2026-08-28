import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/colors.dart';

enum ControlAction {
  mic,
  camera,
  handRaise,
  screenShare,
  reactions,
  settings,
  leave,
}

class ContextualControlsBar extends StatefulWidget {
  final bool isMicEnabled;
  final bool isCameraEnabled;
  final bool isHandRaised;
  final bool isScreenSharing;
  final bool isRecording;
  final Function(ControlAction) onControlAction;
  final Duration autoHideDelay;
  final bool initiallyVisible;

  const ContextualControlsBar({
    super.key,
    this.isMicEnabled = true,
    this.isCameraEnabled = true,
    this.isHandRaised = false,
    this.isScreenSharing = false,
    this.isRecording = false,
    required this.onControlAction,
    this.autoHideDelay = const Duration(seconds: 3),
    this.initiallyVisible = true,
  });

  @override
  State<ContextualControlsBar> createState() => _ContextualControlsBarState();
}

class _ContextualControlsBarState extends State<ContextualControlsBar>
    with SingleTickerProviderStateMixin {
  bool _isVisible = true;
  Timer? _hideTimer;
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _isVisible = widget.initiallyVisible;
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));
    
    if (_isVisible) {
      _animationController.forward();
    }
    
    _resetHideTimer();
  }

  @override
  void didUpdateWidget(ContextualControlsBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _resetHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(widget.autoHideDelay, () {
      if (mounted && _isVisible) {
        _hideControls();
      }
    });
  }

  void _showControls() {
    if (!_isVisible) {
      setState(() {
        _isVisible = true;
      });
      _animationController.forward();
      HapticFeedback.lightImpact();
    }
    _resetHideTimer();
  }

  void _hideControls() {
    if (_isVisible) {
      _animationController.reverse().then((_) {
        if (mounted) {
          setState(() {
            _isVisible = false;
          });
        }
      });
    }
  }

  void _handleControlAction(ControlAction action) {
    HapticFeedback.mediumImpact();
    widget.onControlAction(action);
    _resetHideTimer();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragUpdate: (details) {
        if (details.delta.dy < -5) {
          _showControls();
        } else if (details.delta.dy > 5) {
          _hideControls();
        }
      },
      onTap: _showControls,
      child: SlideTransition(
        position: _slideAnimation,
        child: Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: AppColors.border, width: 1),
            boxShadow: AppColors.softShadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildControlButton(
                icon: widget.isMicEnabled ? Icons.mic : Icons.mic_off,
                active: widget.isMicEnabled,
                onTap: () => _handleControlAction(ControlAction.mic),
                color: widget.isMicEnabled ? AppColors.success : AppColors.error,
              ),
              _buildControlButton(
                icon: widget.isCameraEnabled ? Icons.videocam : Icons.videocam_off,
                active: widget.isCameraEnabled,
                onTap: () => _handleControlAction(ControlAction.camera),
                color: widget.isCameraEnabled ? AppColors.success : AppColors.error,
              ),
              _buildControlButton(
                icon: Icons.back_hand,
                active: widget.isHandRaised,
                onTap: () => _handleControlAction(ControlAction.handRaise),
                color: widget.isHandRaised ? AppColors.handRaised : AppColors.textSecondary,
                showPulse: widget.isHandRaised,
              ),
              _buildControlButton(
                icon: Icons.screen_share,
                active: widget.isScreenSharing,
                onTap: () => _handleControlAction(ControlAction.screenShare),
                color: widget.isScreenSharing ? AppColors.screenShareActive : AppColors.textSecondary,
              ),
              _buildControlButton(
                icon: Icons.sentiment_satisfied_alt,
                active: false,
                onTap: () => _handleControlAction(ControlAction.reactions),
                color: AppColors.textSecondary,
              ),
              _buildControlButton(
                icon: Icons.settings,
                active: false,
                onTap: () => _handleControlAction(ControlAction.settings),
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              _buildLeaveButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
    required Color color,
    bool showPulse = false,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: active ? color.withValues(alpha: 0.2) : AppColors.surfaceVariant,
            shape: BoxShape.circle,
            border: Border.all(
              color: active ? color : AppColors.border,
              width: active ? 2 : 1,
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: Icon(
                  icon,
                  size: 24,
                  color: active ? color : AppColors.textPrimary,
                ),
              ),
              if (showPulse)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: color,
                        width: 2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeaveButton() {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      child: GestureDetector(
        onTap: () => _handleControlAction(ControlAction.leave),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.error,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.call_end,
            size: 24,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}