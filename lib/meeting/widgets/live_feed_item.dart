import 'package:flutter/material.dart';
import '../../theme/colors.dart';
import '../entities/participant_display.dart';

class LiveFeedItem extends StatelessWidget {
  final ParticipantDisplayState participantState;
  final VoidCallback? onTap;
  final VoidCallback? onSwipe;
  final bool showAudioIndicator;
  final bool showBadges;

  const LiveFeedItem({
    super.key,
    required this.participantState,
    this.onTap,
    this.onSwipe,
    this.showAudioIndicator = true,
    this.showBadges = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! > 0) {
          onSwipe?.call();
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        decoration: BoxDecoration(
          color:
              participantState.isSpeaking
                  ? AppColors.surfaceElevated
                  : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color:
                participantState.isSpeaking
                    ? AppColors.primary
                    : AppColors.borderSubtle,
            width: participantState.isSpeaking ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            _buildAvatar(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    participantState.displayName,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight:
                          participantState.isSpeaking
                              ? FontWeight.bold
                              : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (showBadges && participantState.hasHandRaised)
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.handRaised,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Main levée',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (showAudioIndicator) _buildAudioIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        shape: BoxShape.circle,
        border: Border.all(
          color:
              participantState.isSpeaking
                  ? AppColors.primary
                  : AppColors.border,
          width: participantState.isSpeaking ? 2 : 1,
        ),
      ),
      child: Stack(
        children: [
          Center(
            child: Text(
              participantState.initials,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          if (participantState.isSpeaking)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAudioIndicator() {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: Icon(
        participantState.isAudioActive ? Icons.mic : Icons.mic_off,
        size: 16,
        color:
            participantState.isAudioActive
                ? AppColors.success
                : AppColors.error,
      ),
    );
  }
}
