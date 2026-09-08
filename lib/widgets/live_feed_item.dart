import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import '../theme/colors.dart';

/// Item du flux vidéo en direct (TikTok-style) - 48px avatar + scrollable
class LiveFeedItem extends StatefulWidget {
  final RemoteParticipant participant;
  final bool isHandRaised;
  final bool isActive;
  final VoidCallback? onTap;
  final VoidCallback? onDismiss;

  const LiveFeedItem({
    super.key,
    required this.participant,
    this.isHandRaised = false,
    this.isActive = false,
    this.onTap,
    this.onDismiss,
  });

  @override
  State<LiveFeedItem> createState() => _LiveFeedItemState();
}

class _LiveFeedItemState extends State<LiveFeedItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _dismissController;
  late Animation<Offset> _dismissAnimation;

  @override
  void initState() {
    super.initState();
    _dismissController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _dismissAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(1.0, 0),
    ).animate(
      CurvedAnimation(parent: _dismissController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _dismissController.dispose();
    super.dispose();
  }

  void _handleDismiss() {
    _dismissController.forward().then((_) {
      widget.onDismiss?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _dismissAnimation,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Dismissible(
          key: ValueKey(widget.participant.sid),
          direction: DismissDirection.endToStart,
          onDismissed: (_) => _handleDismiss(),
          child: GestureDetector(
            onTap: widget.onTap,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color:
                    widget.isActive
                        ? AppColors.surfaceElevated
                        : AppColors.cardBackground,
                border: Border.all(
                  color:
                      widget.isActive
                          ? AppColors.borderFocused
                          : AppColors.border,
                  width: widget.isActive ? 1.5 : 1.0,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ─ Avatar
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: AppColors.cardBackgroundAlt,
                        child: Text(
                          widget.participant.name.substring(0, 1).toUpperCase(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),

                      // ─ Audio ring (pulse si en train de parler)
                      if (widget.isActive)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.cameraActive,
                                width: 2,
                              ),
                            ),
                          ),
                        ),

                      // ─ Hand raised indicator
                      if (widget.isHandRaised)
                        Positioned(
                          bottom: -2,
                          right: -2,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: AppColors.handRaised,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.pan_tool,
                              size: 10,
                              color: AppColors.textOnPrimary,
                            ),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(width: 8),

                  // ─ Nom + statut
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.participant.name,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget
                                .participant
                                .audioTrackPublications
                                .isNotEmpty)
                              const Padding(
                                padding: EdgeInsets.only(right: 4),
                                child: Icon(
                                  Icons.mic,
                                  size: 10,
                                  color: AppColors.micActive,
                                ),
                              ),
                            if (widget
                                .participant
                                .videoTrackPublications
                                .isNotEmpty)
                              const Icon(
                                Icons.videocam,
                                size: 10,
                                color: AppColors.cameraActive,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  // ─ Menu (long-press)
                  PopupMenuButton(
                    itemBuilder:
                        (context) => [
                          PopupMenuItem(
                            onTap: widget.onTap,
                            child: const Row(
                              children: [
                                Icon(Icons.push_pin, size: 16),
                                SizedBox(width: 8),
                                Text('Épingler'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            onTap: _handleDismiss,
                            child: const Row(
                              children: [
                                Icon(Icons.visibility_off, size: 16),
                                SizedBox(width: 8),
                                Text('Masquer'),
                              ],
                            ),
                          ),
                        ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
