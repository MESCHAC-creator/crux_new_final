import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/colors.dart';
import '../services/meeting_service.dart';
import '../widgets/elegant_toast.dart';
import 'large_conference_screen.dart';

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
  final _meetingService = MeetingService();

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    await _meetingService.addParticipant(widget.meetingId, widget.userId);
    if (widget.isHost) {
      await _meetingService.updateMeetingStatus(widget.meetingId, MeetingStatus.ongoing);
    }
  }

  void _copyId() {
    Clipboard.setData(ClipboardData(text: widget.meetingId));
    ElegantToast.show(
      context,
      title: 'Succès',
      message: 'ID de la réunion copié dans le presse-papiers !',
      type: ElegantToastType.success,
    );
  }

  void _joinCall() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LargeConferenceScreen(
          meetingId: widget.meetingId,
          meetingName: widget.meetingName,
          userId: widget.userId,
          userName: widget.userName,
          userEmail: widget.userEmail,
          isHost: widget.isHost,
        ),
      ),
    ).then((_) {
      if (mounted) {
        _meetingService.removeParticipant(widget.meetingId, widget.userId);
        Navigator.pop(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF1A1A2E), Color(0xFF16213E)])),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(children: [
              Text(widget.meetingName, style: GoogleFonts.poppins(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text("ID : ${widget.meetingId}", style: const TextStyle(color: Colors.white54)),
              const Spacer(),
              _InfoCard(meetingId: widget.meetingId, onCopy: _copyId),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _joinCall,
                  icon: const Icon(Icons.videocam),
                  label: const Text("DÉMARRER L'APPEL"),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler", style: TextStyle(color: Colors.white38))),
            ]),
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String meetingId;
  final VoidCallback onCopy;
  const _InfoCard({required this.meetingId, required this.onCopy});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white12)),
      child: Column(children: [
        const Icon(Icons.verified_user_outlined, color: Colors.green, size: 40),
        const SizedBox(height: 16),
        const Text("Réunion Sécurisée", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text("Vos flux audio/vidéo transitent par LiveKit via WebRTC sécurisé.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, fontSize: 12)),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: onCopy,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(meetingId, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, letterSpacing: 1)),
              const SizedBox(width: 8),
              const Icon(Icons.copy, color: Colors.white38, size: 14),
            ]),
          ),
        ),
      ]),
    );
  }
}
