import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import '../config/app_config.dart';
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
  RtcEngine? _engine;
  int? _remoteUid;
  bool _micOn = true;
  bool _camOn = true;
  bool _loading = true;
  String? _error;

  // Channel name: only alphanumeric + underscore, max 64 chars
  String get _channel =>
      'CRUX_${widget.meetingId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}'
          .substring(0, widget.meetingId.length.clamp(0, 58) + 5);

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
    // Check App ID configured
    if (Config.agoraAppId == 'REMPLACE_PAR_TON_AGORA_APP_ID' ||
        Config.agoraAppId.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error =
              'App ID Agora non configuré.\nSuivez les instructions dans les paramètres.';
        });
      }
      return;
    }

    // Request camera + mic permissions
    final cam = await Permission.camera.request();
    final mic = await Permission.microphone.request();
    if (!cam.isGranted || !mic.isGranted) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Autorisations caméra et microphone requises.';
        });
      }
      return;
    }

    try {
      _engine = createAgoraRtcEngine();
      await _engine!.initialize(RtcEngineContext(appId: Config.agoraAppId));

      _engine!.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (connection, elapsed) {
            if (mounted) setState(() => _loading = false);
          },
          onUserJoined: (connection, remoteUid, elapsed) {
            if (mounted) setState(() => _remoteUid = remoteUid);
          },
          onUserOffline: (connection, remoteUid, reason) {
            if (mounted) setState(() => _remoteUid = null);
          },
          onError: (err, msg) {
            if (mounted) {
              setState(() {
                _loading = false;
                _error = 'Erreur Agora: $msg';
              });
            }
          },
        ),
      );

      await _engine!.enableVideo();
      await _engine!.startPreview();

      await _engine!.joinChannel(
        token: '',
        channelId: _channel,
        uid: 0,
        options: const ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileCommunication,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Impossible de démarrer l\'appel : $e';
        });
      }
    }
  }

  Future<void> _leave() async {
    await _engine?.leaveChannel();
    await _engine?.release();
    _engine = null;
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _engine?.leaveChannel();
    _engine?.release();
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

  Widget _buildLoading() => Center(
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

  Widget _buildError() => Center(
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
                style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14, height: 1.5),
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

  Widget _buildCall() {
    return Stack(
      children: [
        // Remote video fullscreen (or waiting screen)
        Positioned.fill(
          child: _remoteUid != null
              ? AgoraVideoView(
                  controller: VideoViewController.remote(
                    rtcEngine: _engine!,
                    canvas: VideoCanvas(uid: _remoteUid!),
                    connection: RtcConnection(channelId: _channel),
                  ),
                )
              : _buildWaiting(),
        ),

        // Local video PiP (top-right)
        Positioned(
          top: 16,
          right: 16,
          width: 110,
          height: 150,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary, width: 2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: _camOn
                  ? AgoraVideoView(
                      controller: VideoViewController(
                        rtcEngine: _engine!,
                        canvas: const VideoCanvas(uid: 0),
                      ),
                    )
                  : Container(
                      color: Colors.black87,
                      child: const Icon(Icons.videocam_off, color: Colors.white54, size: 32),
                    ),
            ),
          ),
        ),

        // Top gradient bar
        Positioned(
          top: 0, left: 0, right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
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
                  widget.meetingId.length > 14
                      ? widget.meetingId.substring(0, 14)
                      : widget.meetingId,
                  style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12),
                ),
                const Spacer(),
                if (_remoteUid == null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.orange),
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
          bottom: 0, left: 0, right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 32),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black87, Colors.transparent],
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _Btn(
                  icon: _micOn ? Icons.mic : Icons.mic_off,
                  label: _micOn ? 'Micro' : 'Muet',
                  active: _micOn,
                  onTap: () async {
                    await _engine?.muteLocalAudioStream(_micOn);
                    setState(() => _micOn = !_micOn);
                  },
                ),
                _Btn(
                  icon: _camOn ? Icons.videocam : Icons.videocam_off,
                  label: _camOn ? 'Caméra' : 'Off',
                  active: _camOn,
                  onTap: () async {
                    await _engine?.muteLocalVideoStream(_camOn);
                    setState(() => _camOn = !_camOn);
                  },
                ),
                _Btn(
                  icon: Icons.flip_camera_ios,
                  label: 'Retourner',
                  active: true,
                  onTap: () => _engine?.switchCamera(),
                ),
                _Btn(
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
              width: 80, height: 80,
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
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('ID copié !', style: GoogleFonts.poppins()),
                    backgroundColor: AppColors.success,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ));
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

class _Btn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final bool isEnd;
  final VoidCallback onTap;
  const _Btn({required this.icon, required this.label, required this.active, required this.onTap, this.isEnd = false});

  @override
  Widget build(BuildContext context) {
    final bg = isEnd ? Colors.red : active ? Colors.white.withOpacity(0.2) : Colors.white.withOpacity(0.08);
    final fg = isEnd ? Colors.white : active ? Colors.white : Colors.white38;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54, height: 54,
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
