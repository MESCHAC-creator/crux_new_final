import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/premium_colors.dart';

class HostControlsPanel extends StatelessWidget {
  final bool isRecording;
  final VoidCallback onToggleRecording;
  final VoidCallback onMuteAll;
  final VoidCallback onRemoveParticipant;
  final VoidCallback onEndMeeting;
  final int participantCount;

  const HostControlsPanel({
    super.key,
    required this.isRecording,
    required this.onToggleRecording,
    required this.onMuteAll,
    required this.onRemoveParticipant,
    required this.onEndMeeting,
    required this.participantCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: PremiumColors.darkBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: PremiumColors.flamePrimary.withValues(alpha: 0.3),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Host Controls',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: PremiumColors.snowWhite,
            ),
          ),
          const SizedBox(height: 16),

          // Recording control
          _HostControlButton(
            icon: Icons.fiber_manual_record,
            label: isRecording ? 'Stop Recording' : 'Start Recording',
            color: isRecording ? PremiumColors.errorRed : PremiumColors.successGreen,
            onPressed: onToggleRecording,
          ),

          const SizedBox(height: 8),

          // Mute all control
          _HostControlButton(
            icon: Icons.mic_off,
            label: 'Mute All Participants',
            color: PremiumColors.warningYellow,
            onPressed: onMuteAll,
          ),

          const SizedBox(height: 8),

          // Participants info
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: PremiumColors.textSecondary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.people,
                      color: PremiumColors.textTertiary,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$participantCount Participant(s)',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: PremiumColors.textTertiary,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: PremiumColors.icePrimary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Live',
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: PremiumColors.icePrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // End meeting button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onEndMeeting,
              style: ElevatedButton.styleFrom(
                backgroundColor: PremiumColors.errorRed,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                'End Meeting',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  color: PremiumColors.snowWhite,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HostControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _HostControlButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
              Icon(Icons.arrow_forward_ios, color: color, size: 14),
            ],
          ),
        ),
      ),
    );
  }
}
