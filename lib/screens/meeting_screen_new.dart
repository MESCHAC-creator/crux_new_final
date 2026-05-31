import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme/premium_colors.dart';
import '../services/agora_service.dart';
import '../config/app_config.dart';
import '../models/meeting_model.dart';
import '../widgets/premium_button.dart';

class MeetingScreenNew extends StatefulWidget {
  final String meetingId;
  final String meetingName;
  final String userId;

  const MeetingScreenNew({
    Key? key,
    required this.meetingId,
    required this.meetingName,
    required this.userId,
  }) : super(key: key);

  @override
  State<MeetingScreenNew> createState() => _MeetingScreenNewState();
}

class _MeetingScreenNewState extends State<MeetingScreenNew> {
  late RtcEngine _engine;
  late AgoraService _agoraService;
  bool _localUserJoined = false;
  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isScreenSharing = false;
  Map<int, bool> _remoteUsers = {};
  int? _localUid;

  @override
  void initState() {
    super.initState();
    _initializeAgora();
  }

  Future<void> _initializeAgora() async {
    // Request permissions
    await [Permission.microphone, Permission.camera].request();

    _agoraService = AgoraService();

    try {
      // Initialize Agora
      _engine = createAgoraRtcEngine();
      await _engine.initialize(RtcEngineContext(
        appId: Config.agoraAppId,
      ));

      // Setup listeners
      _engine.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
            setState(() => _localUserJoined = true);
            debugPrint('[Agora] Joined channel: ${connection.channelId}');
          },
          onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
            setState(() => _remoteUsers[remoteUid] = true);
            debugPrint('[Agora] Remote user joined: $remoteUid');
          },
          onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
            setState(() => _remoteUsers.remove(remoteUid));
            debugPrint('[Agora] Remote user left: $remoteUid');
          },
          onError: (ErrorCodeType err, String msg) {
            debugPrint('[Agora] ERROR: $err - $msg');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error: $msg')),
              );
            }
          },
        ),
      );

      // Enable video
      await _engine.enableVideo();
      await _engine.enableAudio();

      // Setup video configuration
      await _engine.setVideoEncoderConfiguration(
        VideoEncoderConfiguration(
          dimensions: const VideoDimensions(width: 1280, height: 720),
          frameRate: 30,
          bitrate: 2500,
        ),
      );

      // Get token and join channel
      final token = await _agoraService.getToken(widget.meetingId);

      await _engine.joinChannel(
        token: token,
        channelId: widget.meetingId,
        options: RtcChannelMediaOptions(
          autoSubscribeAudio: true,
          autoSubscribeVideo: true,
          publishMicrophoneTrack: true,
          publishCameraTrack: true,
          clientRoleType: ClientRoleType.broadcaster,
        ),
      );

      // Setup local video
      await _engine.startPreview();
    } catch (e) {
      debugPrint('[Agora] Init error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to initialize: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _engine.leaveChannel();
    _engine.release();
    super.dispose();
  }

  Widget _buildLocalVideo() {
    if (!_localUserJoined) {
      return const Center(child: CircularProgressIndicator());
    }
    return AgoraVideoView(
      controller: VideoViewController(
        rtcEngine: _engine,
        canvas: const VideoCanvas(uid: 0),
      ),
    );
  }

  Widget _buildRemoteVideo(int uid) {
    return AgoraVideoView(
      controller: VideoViewController.remote(
        rtcEngine: _engine,
        canvas: VideoCanvas(uid: uid),
        connection: RtcConnection(channelId: widget.meetingId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Confirm exit
        return await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('End Meeting?'),
            content: const Text('Are you sure you want to leave the meeting?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Stay'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Leave'),
              ),
            ],
          ),
        ) ??
            false;
      },
      child: Scaffold(
        backgroundColor: PremiumColors.darkBackground,
        body: Stack(
          children: [
            // Video grid
            _remoteUsers.isEmpty
                ? _buildLocalVideo()
                : GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _remoteUsers.length == 1 ? 1 : 2,
                childAspectRatio: 9 / 16,
              ),
              itemCount: _remoteUsers.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) return _buildLocalVideo();
                final remoteUid = _remoteUsers.keys.toList()[index - 1];
                return _buildRemoteVideo(remoteUid);
              },
            ),

            // Top bar with meeting info
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      PremiumColors.darkBackground,
                      PremiumColors.darkBackground.withValues(alpha: 0),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                padding: const EdgeInsets.all(16),
                child: SafeArea(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.meetingName,
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                color: PremiumColors.snowWhite,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${_remoteUsers.length + 1} participant(s)',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: PremiumColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: PremiumColors.flamePrimaryWithOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: PremiumColors.flamePrimary,
                            width: 1.5,
                          ),
                        ),
                        child: const Text(
                          'REC',
                          style: TextStyle(
                            color: PremiumColors.flamePrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Control bar at bottom
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      PremiumColors.darkBackground.withValues(alpha: 0),
                      PremiumColors.darkBackground,
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                padding: const EdgeInsets.all(24),
                child: SafeArea(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Mic toggle
                      _MeetingControlButton(
                        icon: _isMuted ? Icons.mic_off : Icons.mic,
                        isActive: !_isMuted,
                        label: _isMuted ? 'Unmute' : 'Mute',
                        onPressed: () async {
                          await _engine.muteLocalAudioStream(_isMuted);
                          setState(() => _isMuted = !_isMuted);
                        },
                      ),

                      // Camera toggle
                      _MeetingControlButton(
                        icon: _isCameraOff ? Icons.videocam_off : Icons.videocam,
                        isActive: !_isCameraOff,
                        label: _isCameraOff ? 'Turn On' : 'Camera',
                        onPressed: () async {
                          await _engine.muteLocalVideoStream(_isCameraOff);
                          setState(() => _isCameraOff = !_isCameraOff);
                        },
                      ),

                      // Screen share
                      _MeetingControlButton(
                        icon: Icons.screen_share,
                        isActive: _isScreenSharing,
                        label: 'Share',
                        onPressed: () {
                          setState(() => _isScreenSharing = !_isScreenSharing);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Screen share - coming soon')),
                          );
                        },
                      ),

                      // Leave call
                      _MeetingControlButton(
                        icon: Icons.call_end,
                        isActive: true,
                        label: 'End',
                        isEnd: true,
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Floating action menu (if needed)
            Positioned(
              bottom: 120,
              right: 16,
              child: FloatingActionButton.small(
                backgroundColor: PremiumColors.icePrimary,
                onPressed: () {
                  // Open participants or more options
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Participants: Coming soon')),
                  );
                },
                child: const Icon(Icons.people, color: PremiumColors.snowWhite),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MeetingControlButton extends StatefulWidget {
  final IconData icon;
  final bool isActive;
  final String label;
  final VoidCallback onPressed;
  final bool isEnd;

  const _MeetingControlButton({
    required this.icon,
    required this.isActive,
    required this.label,
    required this.onPressed,
    this.isEnd = false,
  });

  @override
  State<_MeetingControlButton> createState() => _MeetingControlButtonState();
}

class _MeetingControlButtonState extends State<_MeetingControlButton> {
  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isEnd
        ? PremiumColors.errorRed
        : widget.isActive
            ? PremiumColors.icePrimary
            : PremiumColors.surfaceGray;

    final iconColor = widget.isEnd || widget.isActive
        ? PremiumColors.snowWhite
        : PremiumColors.textSecondary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: bgColor.withValues(alpha: 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(widget.icon, color: iconColor, size: 24),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.label,
          style: TextStyle(
            color: PremiumColors.textTertiary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
