import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/premium_colors.dart';
import '../models/meeting_model.dart';

class WaitingRoomScreen extends StatefulWidget {
  final String meetingId;
  final String meetingName;
  final String userId;
  final String userName;

  const WaitingRoomScreen({
    Key? key,
    required this.meetingId,
    required this.meetingName,
    required this.userId,
    required this.userName,
  }) : super(key: key);

  @override
  State<WaitingRoomScreen> createState() => _WaitingRoomScreenState();
}

class _WaitingRoomScreenState extends State<WaitingRoomScreen> {
  bool _isVideoEnabled = false;
  bool _isAudioEnabled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PremiumColors.darkBackground,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated waiting icon
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [
                    PremiumColors.flamePrimary,
                    PremiumColors.accentOrange,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: PremiumColors.flamePrimary.withValues(alpha: 0.4),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: const Icon(
                Icons.hourglass_empty,
                color: PremiumColors.snowWhite,
                size: 60,
              ),
            )
                .animate()
                .scale(duration: 1000.ms)
                .then()
                .shimmer(duration: 2000.ms)
                .animate(onPlay: (controller) => controller.repeat())
                .rotate(duration: 3000.ms, begin: 0, end: 1),

            const SizedBox(height: 32),

            // Meeting info
            Text(
              'Waiting Room',
              style: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: PremiumColors.snowWhite,
              ),
            ),

            const SizedBox(height: 12),

            Text(
              widget.meetingName,
              style: GoogleFonts.poppins(
                fontSize: 16,
                color: PremiumColors.textTertiary,
              ),
            ),

            const SizedBox(height: 32),

            // Status message
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: PremiumColors.icePrimary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: PremiumColors.icePrimary.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: PremiumColors.icePrimary,
                    size: 24,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Waiting for host to admit you',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: PremiumColors.icePrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 48),

            // Device settings
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: PremiumColors.surfaceGray.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: PremiumColors.borderGray),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Prepare Your Devices',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: PremiumColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Camera toggle
                  _DeviceToggle(
                    icon: Icons.videocam,
                    label: 'Camera',
                    isEnabled: _isVideoEnabled,
                    onChanged: (value) =>
                        setState(() => _isVideoEnabled = value),
                  ),

                  const SizedBox(height: 12),

                  // Microphone toggle
                  _DeviceToggle(
                    icon: Icons.mic,
                    label: 'Microphone',
                    isEnabled: _isAudioEnabled,
                    onChanged: (value) =>
                        setState(() => _isAudioEnabled = value),
                  ),
                ],
              ),
            ),

            const Spacer(),

            // Leave button
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: PremiumColors.errorRed,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Leave Waiting Room',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      color: PremiumColors.snowWhite,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceToggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isEnabled;
  final ValueChanged<bool> onChanged;

  const _DeviceToggle({
    required this.icon,
    required this.label,
    required this.isEnabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PremiumColors.darkBackground.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: isEnabled ? PremiumColors.successGreen : PremiumColors.textTertiary,
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: PremiumColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          Switch(
            value: isEnabled,
            onChanged: onChanged,
            activeColor: PremiumColors.successGreen,
          ),
        ],
      ),
    );
  }
}
