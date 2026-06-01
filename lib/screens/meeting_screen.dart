import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/colors.dart';
import '../services/jitsi_service.dart';
import '../services/meeting_service.dart';
import '../models/meeting_model.dart';

class MeetingScreen extends StatefulWidget {
  final String meetingId;
  final String meetingName;
  final String userId;
  final String userName;
  final String? userEmail;
  final bool isHost;

  const MeetingScreen({
    super.key,
    required this.meetingId,
    required this.meetingName,
    required this.userId,
    required this.userName,
    this.userEmail,
    this.isHost = false,
  });

  @override
  State<MeetingScreen> createState() => _MeetingScreenState();
}

class _MeetingScreenState extends State<MeetingScreen> {
  final _jitsi = JitsiService();
  final _meetingService = MeetingService();

  bool _isJoining = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _join();
  }

  Future<void> _join() async {
    try {
      await _meetingService.addParticipant(widget.meetingId, widget.userId);
      if (widget.isHost) {
        await _meetingService.updateMeetingStatus(widget.meetingId, MeetingStatus.ongoing);
      }

      await _jitsi.joinMeeting(
        meetingId: widget.meetingId,
        displayName: widget.userName,
        email: widget.userEmail,
      );

      if (mounted) setState(() => _isJoining = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isJoining = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  void dispose() {
    _meetingService.removeParticipant(widget.meetingId, widget.userId);
    if (widget.isHost) {
      _meetingService.updateMeetingStatus(widget.meetingId, MeetingStatus.ended);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: AppColors.error, size: 64),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                child: Text(
                  'Retour',
                  style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_isJoining) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3),
            const SizedBox(height: 20),
            Text(
              'Connexion à la réunion...',
              style: GoogleFonts.poppins(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              widget.meetingName,
              style: GoogleFonts.poppins(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    // Jitsi launched in its own UI — show a minimal overlay with back option
    return Stack(
      children: [
        Container(
          color: const Color(0xFF1A1A2E),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(40),
                    border: Border.all(color: AppColors.primary, width: 2),
                  ),
                  child: const Icon(Icons.video_call, color: AppColors.primary, size: 40),
                ),
                const SizedBox(height: 20),
                Text(
                  widget.meetingName,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Réunion en cours dans Jitsi',
                  style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  'ID: ${widget.meetingId.substring(0, widget.meetingId.length > 12 ? 12 : widget.meetingId.length)}...',
                  style: GoogleFonts.poppins(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          bottom: 32,
          left: 24,
          right: 24,
          child: ElevatedButton.icon(
            onPressed: () {
              _jitsi.hangUp();
              Navigator.pop(context);
            },
            icon: const Icon(Icons.call_end),
            label: Text(
              'Quitter la réunion',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }
}
