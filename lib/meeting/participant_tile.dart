import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import '../theme/colors.dart';
import 'meeting_state.dart';

/// Tuile vidéo d'un participant CRUX.
class ParticipantTile extends StatelessWidget {
  final ParticipantUi participant;

  const ParticipantTile({super.key, required this.participant});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: participant.isSpeaking
              ? Border.all(color: AppColors.primary, width: 2)
              : null,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (participant.videoTrack != null)
              VideoTrackRenderer(participant.videoTrack!)
            else
              Center(
                child: Text(
                  participant.name
                      .substring(0, participant.name.length.clamp(1, 2))
                      .toUpperCase(),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                ),
              ),
            // Badge nom + micro
            Positioned(
              bottom: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (participant.isMuted) ...[
                      const Icon(Icons.mic_off, color: Colors.white, size: 14),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      participant.name,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
