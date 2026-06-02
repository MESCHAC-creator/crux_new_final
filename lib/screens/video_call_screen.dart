import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_fonts/google_fonts.dart';
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
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _pc;
  MediaStream? _localStream;

  bool _micOn = true;
  bool _camOn = true;
  bool _loading = true;
  bool _remoteConnected = false;
  String? _error;

  StreamSubscription? _callSub;
  StreamSubscription? _candidateSub;

  final _db = FirebaseFirestore.instance;

  String get _docId =>
      'room_${widget.meetingId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}';

  static const _iceConfig = {
    'iceServers': [
      {
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
        ]
      },
    ],
    'sdpSemantics': 'unified-plan',
  };

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

      final cam = await Permission.camera.request();
      final mic = await Permission.microphone.request();
      if (!cam.isGranted || !mic.isGranted) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'Camera and microphone permissions required.';
          });
        }
        return;
      }

      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {'facingMode': 'user', 'width': 640, 'height': 480},
      });
      if (mounted) setState(() => _localRenderer.srcObject = _localStream);

      _pc = await createPeerConnection(_iceConfig);

      for (final track in _localStream!.getTracks()) {
        await _pc!.addTrack(track, _localStream!);
      }

      _pc!.onTrack = (event) {
        if (event.streams.isNotEmpty && mounted) {
          setState(() {
            _remoteRenderer.srcObject = event.streams[0];
            _remoteConnected = true;
            _loading = false;
          });
        }
      };

      _pc!.onConnectionState = (state) {
        if (!mounted) return;
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          setState(() { _remoteConnected = true; _loading = false; });
        } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          setState(() => _remoteConnected = false);
        }
      };

      _pc!.onIceCandidate = (c) {
        if (c.candidate == null) return;
        final col = widget.isHost ? 'offerCandidates' : 'answerCandidates';
        _db.collection('webrtc_rooms').doc(_docId).collection(col).add({
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        });
      };

      if (widget.isHost) {
        await _hostCall();
      } else {
        await _joinCall();
      }

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() { _loading = false; _error = 'Failed to start call: $e'; });
      }
    }
  }

  Future<void> _hostCall() async {
    final offer = await _pc!.createOffer({
      'offerToReceiveVideo': 1,
      'offerToReceiveAudio': 1,
    });
    await _pc!.setLocalDescription(offer);

    await _db.collection('webrtc_rooms').doc(_docId).set({
      'offer': {'type': offer.type, 'sdp': offer.sdp},
      'meetingId': widget.meetingId,
      'createdAt': FieldValue.serverTimestamp(),
    });

    _callSub = _db.collection('webrtc_rooms').doc(_docId)
        .snapshots().listen((snap) async {
      if (!snap.exists) return;
      final data = snap.data()!;
      if (data['answer'] != null && await _pc?.getRemoteDescription() == null) {
        await _pc?.setRemoteDescription(RTCSessionDescription(
          data['answer']['sdp'], data['answer']['type'],
        ));
      }
    });

    _candidateSub = _db.collection('webrtc_rooms').doc(_docId)
        .collection('answerCandidates').snapshots().listen((snap) {
      for (final ch in snap.docChanges) {
        if (ch.type == DocumentChangeType.added) {
          final d = ch.doc.data()!;
          _pc?.addCandidate(RTCIceCandidate(
              d['candidate'], d['sdpMid'], d['sdpMLineIndex']));
        }
      }
    });
  }

  Future<void> _joinCall() async {
    final snap = await _db.collection('webrtc_rooms').doc(_docId).get();
    if (!snap.exists || snap.data()?['offer'] == null) {
      if (mounted) {
        setState(() {
          _error = 'Meeting not found.\nAsk the host to start the call first.';
          _loading = false;
        });
      }
      return;
    }

    final offerData = snap.data()!['offer'];
    await _pc!.setRemoteDescription(
        RTCSessionDescription(offerData['sdp'], offerData['type']));

    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);

    await _db.collection('webrtc_rooms').doc(_docId).update({
      'answer': {'type': answer.type, 'sdp': answer.sdp},
    });

    _candidateSub = _db.collection('webrtc_rooms').doc(_docId)
        .collection('offerCandidates').snapshots().listen((snap) {
      for (final ch in snap.docChanges) {
        if (ch.type == DocumentChangeType.added) {
          final d = ch.doc.data()!;
          _pc?.addCandidate(RTCIceCandidate(
              d['candidate'], d['sdpMid'], d['sdpMLineIndex']));
        }
      }
    });
  }

  Future<void> _leave() async {
    _callSub?.cancel();
    _candidateSub?.cancel();
    if (widget.isHost) {
      try { await _db.collection('webrtc_rooms').doc(_docId).delete(); } catch (_) {}
    }
    await _localStream?.dispose();
    await _pc?.close();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _callSub?.cancel();
    _candidateSub?.cancel();
    _localStream?.dispose();
    _pc?.close();
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

  Widget _buildLoading() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(color: Colors.white),
          const SizedBox(height: 20),
          Text(
            widget.isHost ? 'Creating meeting...' : 'Connecting...',
            style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14),
          ),
        ]),
      );

  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 56),
            const SizedBox(height: 16),
            Text(_error!,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    color: Colors.white70, fontSize: 14, height: 1.5)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _leave,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: Text('Back', style: GoogleFonts.poppins(color: Colors.white)),
            ),
          ]),
        ),
      );

  Widget _buildCall() {
    return Stack(children: [
      Positioned.fill(
        child: _remoteConnected
            ? RTCVideoView(_remoteRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
            : _buildWaiting(),
      ),

      // Local PiP
      Positioned(
        top: 16, right: 16, width: 110, height: 150,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.primary, width: 2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: _camOn
                ? RTCVideoView(_localRenderer, mirror: true,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                : Container(
                    color: Colors.black87,
                    child: const Icon(Icons.videocam_off,
                        color: Colors.white54, size: 32)),
          ),
        ),
      ),

      // Top bar
      Positioned(
        top: 0, left: 0, right: 0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Colors.black87, Colors.transparent],
            ),
          ),
          child: Row(children: [
            const Icon(Icons.fiber_manual_record, color: Colors.red, size: 12),
            const SizedBox(width: 6),
            Text(
              widget.meetingId.length > 14
                  ? widget.meetingId.substring(0, 14)
                  : widget.meetingId,
              style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12),
            ),
            const Spacer(),
            if (!_remoteConnected)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.orange),
                ),
                child: Text('Waiting...',
                    style: GoogleFonts.poppins(
                        color: Colors.orange,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ),
          ]),
        ),
      ),

      // Bottom controls
      Positioned(
        bottom: 0, left: 0, right: 0,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 32),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter, end: Alignment.topCenter,
              colors: [Colors.black87, Colors.transparent],
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _Btn(
                icon: _micOn ? Icons.mic : Icons.mic_off,
                label: _micOn ? 'Mute' : 'Unmute',
                active: _micOn,
                onTap: () {
                  for (final t in _localStream?.getAudioTracks() ?? []) {
                    t.enabled = !_micOn;
                  }
                  setState(() => _micOn = !_micOn);
                },
              ),
              _Btn(
                icon: _camOn ? Icons.videocam : Icons.videocam_off,
                label: _camOn ? 'Camera' : 'Cam Off',
                active: _camOn,
                onTap: () {
                  for (final t in _localStream?.getVideoTracks() ?? []) {
                    t.enabled = !_camOn;
                  }
                  setState(() => _camOn = !_camOn);
                },
              ),
              _Btn(
                icon: Icons.flip_camera_ios,
                label: 'Flip',
                active: true,
                onTap: () async {
                  for (final t in _localStream?.getVideoTracks() ?? []) {
                    await Helper.switchCamera(t);
                  }
                },
              ),
              _Btn(
                icon: Icons.call_end,
                label: 'End',
                active: false,
                isEnd: true,
                onTap: _leave,
              ),
            ],
          ),
        ),
      ),
    ]);
  }

  Widget _buildWaiting() {
    return Container(
      color: const Color(0xFF1A1A2E),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
                gradient: AppColors.primaryGradient, shape: BoxShape.circle),
            child: const Icon(Icons.person, color: Colors.white, size: 40),
          ),
          const SizedBox(height: 16),
          Text(
            widget.isHost
                ? 'Share the ID to invite participants'
                : 'Connecting to meeting...',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14),
          ),
          if (widget.isHost) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: widget.meetingId));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('ID copied!', style: GoogleFonts.poppins()),
                  backgroundColor: AppColors.success,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ));
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.copy, color: Colors.white54, size: 14),
                  const SizedBox(width: 8),
                  Text(widget.meetingId,
                      style: GoogleFonts.poppins(
                          color: Colors.white70,
                          fontSize: 13,
                          letterSpacing: 1)),
                ]),
              ),
            ),
          ],
        ]),
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

  const _Btn({
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
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 54, height: 54,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: Icon(icon, color: fg, size: 24),
        ),
        const SizedBox(height: 6),
        Text(label,
            style: GoogleFonts.poppins(color: Colors.white54, fontSize: 10)),
      ]),
    );
  }
}
