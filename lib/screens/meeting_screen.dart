import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/colors.dart';
import '../services/webrtc_service.dart';
import '../services/meeting_service.dart';
import '../models/meeting_model.dart';

class MeetingScreen extends StatefulWidget {
  final String meetingId;
  final String meetingName;
  final String userId;
  final bool isHost;

  const MeetingScreen({
    super.key,
    required this.meetingId,
    required this.meetingName,
    required this.userId,
    this.isHost = false,
  });

  @override
  State<MeetingScreen> createState() => _MeetingScreenState();
}

class _MeetingScreenState extends State<MeetingScreen> {
  final _webrtc = WebRTCService();
  final _meetingService = MeetingService();

  bool _isMicOn = true;
  bool _isCameraOn = true;
  bool _isSpeakerOn = true;
  bool _isJoining = true;
  late Stopwatch _stopwatch;

  @override
  void initState() {
    super.initState();
    _stopwatch = Stopwatch()..start();
    _join();
  }

  Future<void> _join() async {
    await _webrtc.initialize();
    await _webrtc.joinMeeting(
      meetingId: widget.meetingId,
      userId: widget.userId,
      isHost: widget.isHost,
    );
    await _meetingService.addParticipant(widget.meetingId, widget.userId);
    await _meetingService.updateMeetingStatus(widget.meetingId, MeetingStatus.ongoing);
    if (mounted) setState(() => _isJoining = false);
  }

  @override
  void dispose() {
    _stopwatch.stop();
    _webrtc.leaveMeeting(widget.meetingId);
    _meetingService.removeParticipant(widget.meetingId, widget.userId);
    super.dispose();
  }

  Future<void> _toggleMic() async {
    final newMuted = !_webrtc.isMuted.value;
    await _webrtc.muteAudio(newMuted);
    setState(() => _isMicOn = !newMuted);
  }

  Future<void> _toggleCamera() async {
    final newOff = !_webrtc.isCameraOff.value;
    await _webrtc.muteVideo(newOff);
    setState(() => _isCameraOn = !newOff);
  }

  Future<void> _toggleSpeaker() async {
    setState(() => _isSpeakerOn = !_isSpeakerOn);
    await _webrtc.enableSpeakerphone(_isSpeakerOn);
  }

  void _endCall() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.whiteBg,
        title: Text(
          'Quitter la réunion?',
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          'Vous allez quitter ${widget.meetingName}',
          style: GoogleFonts.poppins(color: AppColors.textSecondary),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Annuler',
              style: GoogleFonts.poppins(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (widget.isHost) {
                _meetingService.updateMeetingStatus(widget.meetingId, MeetingStatus.ended);
              }
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: Text(
              'Quitter',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    String pad(int n) => n.toString().padLeft(2, '0');
    if (d.inHours == 0) return '${pad(d.inMinutes.remainder(60))}:${pad(d.inSeconds.remainder(60))}';
    return '${pad(d.inHours)}:${pad(d.inMinutes.remainder(60))}:${pad(d.inSeconds.remainder(60))}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _isJoining
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: AppColors.primary),
                    SizedBox(height: 16),
                    Text(
                      'Connexion en cours...',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              )
            : Stack(
                children: [
                  // Remote video (full screen)
                  _RemoteVideo(renderer: _webrtc.remoteRenderer),

                  // Local video (small, top-right)
                  Positioned(
                    top: 80,
                    right: 16,
                    child: _LocalVideo(
                      renderer: _webrtc.localRenderer,
                      isCameraOn: _isCameraOn,
                      onSwitch: () => _webrtc.switchCamera(),
                    ),
                  ),

                  // Header
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _Header(
                      meetingName: widget.meetingName,
                      stopwatch: _stopwatch,
                      formatDuration: _formatDuration,
                      remoteUserCount: _webrtc.remoteUserCount,
                      isConnected: _webrtc.isConnected,
                    ),
                  ),

                  // Controls
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: _Controls(
                      isMicOn: _isMicOn,
                      isCameraOn: _isCameraOn,
                      isSpeakerOn: _isSpeakerOn,
                      onToggleMic: _toggleMic,
                      onToggleCamera: _toggleCamera,
                      onToggleSpeaker: _toggleSpeaker,
                      onEndCall: _endCall,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _RemoteVideo extends StatelessWidget {
  final RTCVideoRenderer renderer;
  const _RemoteVideo({required this.renderer});

  @override
  Widget build(BuildContext context) {
    if (renderer.srcObject == null) {
      return Container(
        color: const Color(0xFF1A1A2E),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.person, color: Colors.white30, size: 100),
              const SizedBox(height: 16),
              Text(
                'En attente de participants...',
                style: GoogleFonts.poppins(color: Colors.white54, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }
    return RTCVideoView(renderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover);
  }
}

class _LocalVideo extends StatelessWidget {
  final RTCVideoRenderer renderer;
  final bool isCameraOn;
  final VoidCallback onSwitch;
  const _LocalVideo({required this.renderer, required this.isCameraOn, required this.onSwitch});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSwitch,
      child: Container(
        width: 100,
        height: 140,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary, width: 2),
          color: Colors.black,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: isCameraOn && renderer.srcObject != null
              ? RTCVideoView(renderer, mirror: true)
              : const Center(
                  child: Icon(Icons.videocam_off, color: Colors.white54, size: 32),
                ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String meetingName;
  final Stopwatch stopwatch;
  final String Function(Duration) formatDuration;
  final ValueNotifier<int> remoteUserCount;
  final ValueNotifier<bool> isConnected;

  const _Header({
    required this.meetingName,
    required this.stopwatch,
    required this.formatDuration,
    required this.remoteUserCount,
    required this.isConnected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0.85), Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meetingName,
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                StreamBuilder(
                  stream: Stream.periodic(const Duration(seconds: 1)),
                  builder: (_, __) => Text(
                    formatDuration(stopwatch.elapsed),
                    style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[400]),
                  ),
                ),
              ],
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: isConnected,
            builder: (_, connected, __) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: connected ? Colors.green.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: connected ? Colors.green : Colors.white30,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    connected ? Icons.wifi : Icons.wifi_off,
                    color: connected ? Colors.greenAccent : Colors.white54,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  ValueListenableBuilder<int>(
                    valueListenable: remoteUserCount,
                    builder: (_, count, __) => Text(
                      '${count + 1}',
                      style: GoogleFonts.poppins(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  final bool isMicOn;
  final bool isCameraOn;
  final bool isSpeakerOn;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleCamera;
  final VoidCallback onToggleSpeaker;
  final VoidCallback onEndCall;

  const _Controls({
    required this.isMicOn,
    required this.isCameraOn,
    required this.isSpeakerOn,
    required this.onToggleMic,
    required this.onToggleCamera,
    required this.onToggleSpeaker,
    required this.onEndCall,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.95), Colors.transparent],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ControlButton(
                icon: isMicOn ? Icons.mic : Icons.mic_off,
                label: 'Micro',
                isActive: isMicOn,
                onTap: onToggleMic,
              ),
              _ControlButton(
                icon: isCameraOn ? Icons.videocam : Icons.videocam_off,
                label: 'Caméra',
                isActive: isCameraOn,
                onTap: onToggleCamera,
              ),
              _ControlButton(
                icon: isSpeakerOn ? Icons.volume_up : Icons.volume_off,
                label: 'Son',
                isActive: isSpeakerOn,
                onTap: onToggleSpeaker,
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: onEndCall,
              icon: const Icon(Icons.call_end),
              label: Text(
                'Quitter la réunion',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppColors.primary : Colors.grey;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: color, width: 2),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: GoogleFonts.poppins(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
