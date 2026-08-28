import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import '../../theme/colors.dart';
import '../entities/participant_display.dart';
import 'speaker_card.dart';

class ParticipantGridWidget extends StatelessWidget {
  final List<ParticipantDisplayState> participants;
  final int crossAxisCount;
  final double aspectRatio;
  final Function(String participantId)? onParticipantTap;
  final Function(String participantId)? onParticipantLongPress;
  final bool showAudioIndicators;
  final bool showBadges;

  const ParticipantGridWidget({
    super.key,
    required this.participants,
    this.crossAxisCount = 2,
    this.aspectRatio = 1.0,
    this.onParticipantTap,
    this.onParticipantLongPress,
    this.showAudioIndicators = true,
    this.showBadges = true,
  });

  @override
  Widget build(BuildContext context) {
    if (participants.isEmpty) {
      return _buildEmptyState();
    }

    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: aspectRatio,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      padding: const EdgeInsets.all(8),
      itemCount: participants.length,
      itemBuilder: (context, index) {
        final participant = participants[index];
        return _buildParticipantTile(participant);
      },
    );
  }

  Widget _buildParticipantTile(ParticipantDisplayState participant) {
    return GestureDetector(
      onTap: () => onParticipantTap?.call(participant.participantId),
      onLongPress: () => onParticipantLongPress?.call(participant.participantId),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(AppColors.radiusCard),
          border: Border.all(
            color: participant.isSpeaking
                ? AppColors.primary
                : AppColors.border,
            width: participant.isSpeaking ? 2 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppColors.radiusCard),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildParticipantContent(participant),
              _buildParticipantOverlay(participant),
              if (showAudioIndicators) _buildAudioIndicator(participant),
              if (showBadges && participant.hasHandRaised) 
                _buildHandRaisedBadge(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildParticipantContent(ParticipantDisplayState participant) {
    if (participant.isVideoEnabled) {
      final videoTrack = participant.participant.getTrack(TrackType.VIDEO);
      if (videoTrack != null && videoTrack is VideoTrack) {
        return VideoTrackRenderer(videoTrack as VideoTrack);
      } else {
        return _buildAvatarPlaceholder(participant);
      }
    } else {
      return _buildAvatarPlaceholder(participant);
    }
  }

  Widget _buildAvatarPlaceholder(ParticipantDisplayState participant) {
    return Container(
      color: AppColors.surfaceVariant,
      child: Center(
        child: Text(
          participant.initials,
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildParticipantOverlay(ParticipantDisplayState participant) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black.withValues(alpha: 0.6),
            ],
          ),
        ),
        child: Text(
          participant.displayName,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildAudioIndicator(ParticipantDisplayState participant) {
    return Positioned(
      top: 8,
      right: 8,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: participant.isAudioActive
              ? AppColors.success
              : AppColors.error,
          shape: BoxShape.circle,
        ),
        child: Icon(
          participant.isAudioActive ? Icons.mic : Icons.mic_off,
          size: 12,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  Widget _buildHandRaisedBadge() {
    return Positioned(
      top: 8,
      left: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.handRaised,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.back_hand,
              size: 10,
              color: AppColors.textPrimary,
            ),
            const SizedBox(width: 2),
            Text(
              'Main',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.people_outline,
            size: 48,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 16),
          Text(
            'Aucun participant',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class VirtualizedParticipantGrid extends StatelessWidget {
  final List<ParticipantDisplayState> participants;
  final int crossAxisCount;
  final double aspectRatio;
  final Function(String participantId)? onParticipantTap;
  final Function(String participantId)? onParticipantLongPress;
  final int maxVisibleItems;

  const VirtualizedParticipantGrid({
    super.key,
    required this.participants,
    this.crossAxisCount = 2,
    this.aspectRatio = 1.0,
    this.onParticipantTap,
    this.onParticipantLongPress,
    this.maxVisibleItems = 100,
  });

  @override
  Widget build(BuildContext context) {
    final visibleParticipants = participants.take(maxVisibleItems).toList();
    
    return ParticipantGridWidget(
      participants: visibleParticipants,
      crossAxisCount: crossAxisCount,
      aspectRatio: aspectRatio,
      onParticipantTap: onParticipantTap,
      onParticipantLongPress: onParticipantLongPress,
    );
  }
}