import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/webrtc_service.dart';
import '../theme/colors.dart';

class VideoCallScreen extends StatefulWidget {
  final String meetingId;
  final String userName;
  final bool isHost;

  const VideoCallScreen({
    super.key,
    required this.meetingId,
    required this.userName,
    required this.isHost,
  });

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  final _webrtc = WebRTCService();
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();

  bool _micOn = true;
  bool _camOn = true;
  bool _remoteConnected = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _init();
  }

  Future<void> _init() async {
    try {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();

      final local = await _webrtc.openMedia();
      _localRenderer.srcObject = local;

      _webrtc.onRemoteStream = (stream) {
        if (mounted) {
          setState(() {
            _remoteRenderer.srcObject = stream;
            _remoteConnected = true;
          });
        }
      };

      _webrtc.onCallEnded = () {
        if (mounted) _leave();
      };

      if (widget.isHost) {
        await _webrtc.createRoom(widget.meetingId);
      } else {
        final joined = await _webrtc.joinRoom(widget.meetingId);
        if (!joined && mounted) {
          setState(() => _error = 'Réunion introuvable. Vérifiez l\'ID.');
        }
      }

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString().replaceAll('Exception: ', ''); });
    }
  }

  Future<void> _leave() async {
    await _webrtc.hangUp(widget.meetingId);
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _loading
            ? _buildLoading()
            : _error != null
                ? _buildError()
                : _buildCall(),
      ),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: Colors.white),
          const SizedBox(height: 20),
          Text(
            widget.isHost ? 'Création de la réunion...' : 'Connexion en cours...',
            style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 56),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _leave,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: Text('Retour', style: GoogleFonts.poppins(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCall() {
    return Stack(
      children: [
        // Remote video (full screen)
        if (_remoteConnected)
          Positioned.fill(
            child: RTCVideoView(
              _remoteRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
          )
        else
          Positioned.fill(child: _buildWaiting()),

        // Local video (picture-in-picture top-right)
        Positioned(
          top: 16,
          right: 16,
          width: 100,
          height: 140,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _camOn
                  ? RTCVideoView(_localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                  : Container(color: Colors.black87, child: const Icon(Icons.videocam_off, color: Colors.white54)),
            ),
          ),
        ),

        // Top bar
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black87, Colors.transparent],
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.fiber_manual_record, color: Colors.red, size: 12),
                const SizedBox(width: 6),
                Text(
                  widget.meetingId.length > 12 ? widget.meetingId.substring(0, 12) : widget.meetingId,
                  style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12),
                ),
                const Spacer(),
                if (!_remoteConnected)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.orange, width: 1),
                    ),
                    child: Text(
                      'En attente...',
                      style: GoogleFonts.poppins(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Bottom controls
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black87, Colors.transparent],
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ControlBtn(
                  icon: _micOn ? Icons.mic : Icons.mic_off,
                  label: _micOn ? 'Micro' : 'Muet',
                  active: _micOn,
                  onTap: () async {
                    await _webrtc.toggleMic();
                    setState(() => _micOn = !_micOn);
                  },
                ),
                _ControlBtn(
                  icon: _camOn ? Icons.videocam : Icons.videocam_off,
                  label: _camOn ? 'Caméra' : 'Caméra off',
                  active: _camOn,
                  onTap: () async {
                    await _webrtc.toggleCamera();
                    setState(() => _camOn = !_camOn);
                  },
                ),
                _ControlBtn(
                  icon: Icons.flip_camera_ios,
                  label: 'Retourner',
                  active: true,
                  onTap: () => _webrtc.switchCamera(),
                ),
                _ControlBtn(
                  icon: Icons.call_end,
                  label: 'Raccrocher',
                  active: false,
                  isEnd: true,
                  onTap: _leave,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWaiting() {
    return Container(
      color: const Color(0xFF1A1A2E),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person, color: Colors.white, size: 40),
            ),
            const SizedBox(height: 16),
            Text(
              widget.isHost
                  ? 'Partagez l\'ID pour inviter des participants'
                  : 'Connexion à la réunion...',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14),
            ),
            if (widget.isHost) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: widget.meetingId));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('ID copié !', style: GoogleFonts.poppins()),
                      backgroundColor: AppColors.success,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.copy, color: Colors.white54, size: 14),
                      const SizedBox(width: 8),
                      Text(
                        widget.meetingId,
                        style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13, letterSpacing: 1),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ControlBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final bool isEnd;
  final VoidCallback onTap;

  const _ControlBtn({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.isEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isEnd
        ? Colors.red
        : active
            ? Colors.white.withOpacity(0.2)
            : Colors.white.withOpacity(0.08);
    final fg = isEnd ? Colors.white : active ? Colors.white : Colors.white38;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(icon, color: fg, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label, style: GoogleFonts.poppins(color: Colors.white54, fontSize: 10)),
        ],
      ),
    );
  }
}
