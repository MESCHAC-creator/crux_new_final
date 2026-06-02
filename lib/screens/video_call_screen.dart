import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/colors.dart';

// ─────────────────────────────────────────────
//  DATA MODEL for floating emoji reactions
// ─────────────────────────────────────────────
class _Reaction {
  final String emoji;
  final String id;
  double bottomOffset;
  double opacity;

  _Reaction({required this.emoji})
      : id = DateTime.now().microsecondsSinceEpoch.toString(),
        bottomOffset = 100,
        opacity = 1.0;
}

// ─────────────────────────────────────────────
//  WIDGET
// ─────────────────────────────────────────────
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
  // ── WebRTC ──────────────────────────────────
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _screenStream;

  // ── State flags ─────────────────────────────
  bool _micOn = true;
  bool _camOn = true;
  bool _loading = true;
  bool _remoteConnected = false;
  bool _answerSet = false;
  bool _sharingScreen = false;
  bool _showChat = false;
  bool _showEmojiBar = false;
  String? _error;
  String _loadingStep = 'Démarrage...';

  // ── Chat / Notes ─────────────────────────────
  int _chatTab = 0; // 0 = Chat, 1 = Notes
  final _chatController = TextEditingController();
  final _chatScrollController = ScrollController();
  final _notesController = TextEditingController();

  // ── Reactions ────────────────────────────────
  final List<_Reaction> _reactions = [];

  // ── Firestore streams ────────────────────────
  StreamSubscription? _callSub;
  StreamSubscription? _candidateSub;
  StreamSubscription<QuerySnapshot>? _reactionSub;

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

  // ── LIFECYCLE ───────────────────────────────
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _init();
    _listenReactions();
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _callSub?.cancel();
    _candidateSub?.cancel();
    _reactionSub?.cancel();
    _chatController.dispose();
    _chatScrollController.dispose();
    _notesController.dispose();
    _screenStream?.dispose();
    _localStream?.dispose();
    _pc?.close();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  // ── INITIALISATION ───────────────────────────
  Future<void> _init() async {
    try {
      if (mounted) setState(() => _loadingStep = 'Initialisation...');
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();

      if (mounted) setState(() => _loadingStep = 'Autorisations...');
      final cam = await Permission.camera.request().timeout(
        const Duration(seconds: 15),
        onTimeout: () => PermissionStatus.denied,
      );
      final mic = await Permission.microphone.request().timeout(
        const Duration(seconds: 15),
        onTimeout: () => PermissionStatus.denied,
      );

      if (!cam.isGranted || !mic.isGranted) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error =
                'Accès caméra et microphone requis.\nActivez-les dans Paramètres → Apps → CRUX → Autorisations.';
          });
        }
        return;
      }

      if (mounted) setState(() => _loadingStep = 'Démarrage caméra...');
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {'facingMode': 'user', 'width': 640, 'height': 480},
      }).timeout(
        const Duration(seconds: 20),
        onTimeout: () =>
            throw TimeoutException('Impossible d\'accéder à la caméra.'),
      );

      // ⚡ Show local camera immediately — don't wait for signaling
      if (mounted) {
        setState(() {
          _localRenderer.srcObject = _localStream;
          _loading = false;
        });
      }

      _pc = await createPeerConnection(_iceConfig);

      for (final track in _localStream!.getTracks()) {
        await _pc!.addTrack(track, _localStream!);
      }

      _pc!.onTrack = (event) {
        if (event.streams.isNotEmpty && mounted) {
          setState(() {
            _remoteRenderer.srcObject = event.streams[0];
            _remoteConnected = true;
          });
        }
      };

      _pc!.onConnectionState = (state) {
        if (!mounted) return;
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          setState(() => _remoteConnected = true);
        } else if (state ==
                RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state ==
                RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          setState(() => _remoteConnected = false);
        }
      };

      _pc!.onIceCandidate = (c) {
        if (c.candidate == null) return;
        final col =
            widget.isHost ? 'offerCandidates' : 'answerCandidates';
        _db
            .collection('webrtc_rooms')
            .doc(_docId)
            .collection(col)
            .add({
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
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Impossible de démarrer l\'appel:\n$e';
        });
      }
    }
  }

  // ── WEBRTC SIGNALING ────────────────────────
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

    _callSub = _db
        .collection('webrtc_rooms')
        .doc(_docId)
        .snapshots()
        .listen((snap) async {
      if (!snap.exists) return;
      final data = snap.data()!;
      if (data['answer'] != null && !_answerSet) {
        _answerSet = true;
        await _pc?.setRemoteDescription(RTCSessionDescription(
          data['answer']['sdp'],
          data['answer']['type'],
        ));
      }
    });

    _candidateSub = _db
        .collection('webrtc_rooms')
        .doc(_docId)
        .collection('answerCandidates')
        .snapshots()
        .listen((snap) {
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
    final snap =
        await _db.collection('webrtc_rooms').doc(_docId).get();
    if (!snap.exists || snap.data()?['offer'] == null) {
      if (mounted) {
        setState(() {
          _error =
              'Réunion introuvable.\nDemandez à l\'hôte de démarrer l\'appel d\'abord.';
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

    _candidateSub = _db
        .collection('webrtc_rooms')
        .doc(_docId)
        .collection('offerCandidates')
        .snapshots()
        .listen((snap) {
      for (final ch in snap.docChanges) {
        if (ch.type == DocumentChangeType.added) {
          final d = ch.doc.data()!;
          _pc?.addCandidate(RTCIceCandidate(
              d['candidate'], d['sdpMid'], d['sdpMLineIndex']));
        }
      }
    });
  }

  // ── SCREEN SHARE ────────────────────────────
  Future<void> _toggleScreenShare() async {
    if (_sharingScreen) {
      // Restore camera track
      final senders = await _pc!.getSenders();
      for (final sender in senders) {
        if (sender.track?.kind == 'video') {
          final cam = _localStream?.getVideoTracks();
          if (cam != null && cam.isNotEmpty) {
            await sender.replaceTrack(cam.first);
          }
        }
      }
      await _screenStream?.dispose();
      _screenStream = null;
      if (mounted) {
        setState(() {
          _sharingScreen = false;
          _localRenderer.srcObject = _localStream;
        });
      }
    } else {
      try {
        _screenStream = await navigator.mediaDevices.getDisplayMedia({
          'video': true,
          'audio': false,
        });
        final tracks = _screenStream!.getVideoTracks();
        if (tracks.isEmpty) return;

        final screenTrack = tracks.first;
        final senders = await _pc!.getSenders();
        for (final sender in senders) {
          if (sender.track?.kind == 'video') {
            await sender.replaceTrack(screenTrack);
          }
        }
        // Stop sharing automatically when user dismisses the system picker
        screenTrack.onEnded = () {
          if (mounted) _toggleScreenShare();
        };

        if (mounted) {
          setState(() {
            _sharingScreen = true;
            _localRenderer.srcObject = _screenStream;
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Partage d\'écran indisponible: $e',
                style: GoogleFonts.poppins()),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ));
        }
      }
    }
  }

  // ── REACTIONS ────────────────────────────────
  void _listenReactions() {
    _reactionSub = _db
        .collection('webrtc_rooms')
        .doc(_docId)
        .collection('reactions')
        .orderBy('ts', descending: true)
        .limit(30)
        .snapshots()
        .listen((snap) {
      for (final ch in snap.docChanges) {
        if (ch.type == DocumentChangeType.added) {
          final emoji = ch.doc.data()?['emoji'] as String?;
          // Only animate reactions from others (own reactions already shown locally)
          final sender = ch.doc.data()?['sender'] as String?;
          if (emoji != null && sender != widget.userName && mounted) {
            _spawnReaction(emoji);
          }
        }
      }
    });
  }

  void _spawnReaction(String emoji) {
    if (!mounted) return;
    final r = _Reaction(emoji: emoji);
    setState(() => _reactions.add(r));

    Future.delayed(const Duration(milliseconds: 50), () {
      if (!mounted) return;
      setState(() => r.bottomOffset = 340);
    });
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (!mounted) return;
      setState(() => r.opacity = 0.0);
    });
    Future.delayed(const Duration(milliseconds: 2300), () {
      if (!mounted) return;
      setState(() => _reactions.remove(r));
    });
  }

  void _sendReaction(String emoji) {
    // Animate locally immediately
    _spawnReaction(emoji);
    // Broadcast to others via Firestore
    _db
        .collection('webrtc_rooms')
        .doc(_docId)
        .collection('reactions')
        .add({
      'emoji': emoji,
      'sender': widget.userName,
      'ts': FieldValue.serverTimestamp(),
    });
  }

  // ── CHAT ────────────────────────────────────
  void _sendMessage() {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    _chatController.clear();
    _db
        .collection('meetings')
        .doc(widget.meetingId)
        .collection('chat')
        .add({
      'sender': widget.userName,
      'message': text,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // ── LEAVE ───────────────────────────────────
  Future<void> _leave() async {
    _callSub?.cancel();
    _candidateSub?.cancel();
    _reactionSub?.cancel();
    if (widget.isHost) {
      try {
        await _db.collection('webrtc_rooms').doc(_docId).delete();
      } catch (_) {}
    }
    await _screenStream?.dispose();
    await _localStream?.dispose();
    await _pc?.close();
    if (mounted) Navigator.pop(context);
  }

  // ── BUILD ────────────────────────────────────
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

  // ── LOADING SCREEN ───────────────────────────
  Widget _buildLoading() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(color: Colors.white),
          const SizedBox(height: 20),
          Text(_loadingStep,
              style:
                  GoogleFonts.poppins(color: Colors.white70, fontSize: 14)),
        ]),
      );

  // ── ERROR SCREEN ─────────────────────────────
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
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary),
              child: Text('Retour',
                  style: GoogleFonts.poppins(color: Colors.white)),
            ),
          ]),
        ),
      );

  // ── MAIN CALL UI ─────────────────────────────
  Widget _buildCall() {
    return Stack(children: [
      // Remote video (full screen) or waiting
      Positioned.fill(
        child: _remoteConnected
            ? RTCVideoView(_remoteRenderer,
                objectFit:
                    RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
            : _buildWaiting(),
      ),

      // Local camera PiP (top-right)
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
                ? RTCVideoView(_localRenderer,
                    mirror: !_sharingScreen,
                    objectFit: RTCVideoViewObjectFit
                        .RTCVideoViewObjectFitCover)
                : Container(
                    color: Colors.black87,
                    child: const Icon(Icons.videocam_off,
                        color: Colors.white54, size: 32)),
          ),
        ),
      ),

      // Top bar
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: _buildTopBar(),
      ),

      // Floating reactions
      ..._reactions.map(
        (r) => AnimatedPositioned(
          duration: const Duration(milliseconds: 2000),
          curve: Curves.easeOut,
          bottom: r.bottomOffset,
          left: MediaQuery.of(context).size.width / 2 - 22,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 700),
            opacity: r.opacity,
            child: Text(r.emoji,
                style: const TextStyle(fontSize: 38)),
          ),
        ),
      ),

      // Emoji quick bar
      AnimatedPositioned(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        bottom: _showEmojiBar ? (_showChat ? 390 + 70 : 70) : -60,
        left: 0,
        right: 0,
        child: _buildEmojiBar(),
      ),

      // Chat panel (slides up from bottom)
      AnimatedPositioned(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
        bottom: _showChat ? 0 : -400,
        left: 0,
        right: 0,
        height: 400,
        child: _buildChatPanel(),
      ),

      // Controls bar (shifts up when chat is open)
      AnimatedPositioned(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
        bottom: _showChat ? 400 : 0,
        left: 0,
        right: 0,
        child: _buildControls(),
      ),
    ]);
  }

  // ── TOP BAR ──────────────────────────────────
  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: Row(children: [
        const Icon(Icons.fiber_manual_record, color: Colors.red, size: 10),
        const SizedBox(width: 6),
        Text(
          widget.meetingId.length > 12
              ? widget.meetingId.substring(0, 12)
              : widget.meetingId,
          style:
              GoogleFonts.poppins(color: Colors.white70, fontSize: 12),
        ),
        if (_sharingScreen) ...[
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue),
            ),
            child: Text('Partage d\'écran',
                style: GoogleFonts.poppins(
                    color: Colors.blue,
                    fontSize: 10,
                    fontWeight: FontWeight.w600)),
          ),
        ],
        const Spacer(),
        if (!_remoteConnected)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange),
            ),
            child: Text('En attente...',
                style: GoogleFonts.poppins(
                    color: Colors.orange,
                    fontSize: 10,
                    fontWeight: FontWeight.w600)),
          ),
      ]),
    );
  }

  // ── EMOJI BAR ────────────────────────────────
  Widget _buildEmojiBar() {
    const emojis = ['👍', '❤️', '😂', '🎉', '🙏', '👏', '🔥', '😮'];
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.5), blurRadius: 12)
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: emojis
            .map((e) => GestureDetector(
                  onTap: () {
                    _sendReaction(e);
                    setState(() => _showEmojiBar = false);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(e,
                        style: const TextStyle(fontSize: 26)),
                  ),
                ))
            .toList(),
      ),
    );
  }

  // ── CHAT PANEL ───────────────────────────────
  Widget _buildChatPanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.7), blurRadius: 20)
        ],
      ),
      child: Column(children: [
        // Handle
        const SizedBox(height: 8),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(height: 4),

        // Tab bar
        Row(children: [
          _ChatTab(
            icon: Icons.chat_bubble_outline,
            label: 'Chat',
            selected: _chatTab == 0,
            onTap: () => setState(() => _chatTab = 0),
          ),
          _ChatTab(
            icon: Icons.notes,
            label: 'Notes',
            selected: _chatTab == 1,
            onTap: () => setState(() => _chatTab = 1),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down,
                color: Colors.white54, size: 22),
            onPressed: () =>
                setState(() => _showChat = false),
          ),
        ]),

        const Divider(color: Colors.white12, height: 1),

        // Content area
        Expanded(
          child: _chatTab == 0
              ? _buildChatMessages()
              : _buildNotes(),
        ),

        // Input (chat only)
        if (_chatTab == 0) _buildChatInput(),
      ]),
    );
  }

  Widget _buildChatMessages() {
    return StreamBuilder<QuerySnapshot>(
      stream: _db
          .collection('meetings')
          .doc(widget.meetingId)
          .collection('chat')
          .orderBy('timestamp', descending: true)
          .limit(100)
          .snapshots(),
      builder: (ctx, snap) {
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.chat_bubble_outline,
                  color: Colors.white24, size: 32),
              const SizedBox(height: 8),
              Text('Aucun message',
                  style: GoogleFonts.poppins(
                      color: Colors.white38, fontSize: 13)),
            ]),
          );
        }
        return ListView.builder(
          reverse: true,
          controller: _chatScrollController,
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: docs.length,
          itemBuilder: (ctx, i) {
            final d =
                docs[i].data()! as Map<String, dynamic>;
            final isMine = d['sender'] == widget.userName;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Align(
                alignment: isMine
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  constraints: BoxConstraints(
                      maxWidth:
                          MediaQuery.of(ctx).size.width * 0.72),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isMine
                        ? AppColors.primary
                        : Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isMine)
                        Text(
                          d['sender'] ?? '',
                          style: GoogleFonts.poppins(
                              color: Colors.white54,
                              fontSize: 10,
                              fontWeight: FontWeight.w600),
                        ),
                      Text(
                        d['message'] ?? '',
                        style: GoogleFonts.poppins(
                            color: Colors.white, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildChatInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _chatController,
            style: GoogleFonts.poppins(
                color: Colors.white, fontSize: 13),
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _sendMessage(),
            decoration: InputDecoration(
              hintText: 'Message...',
              hintStyle: GoogleFonts.poppins(
                  color: Colors.white38, fontSize: 13),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.08),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _sendMessage,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: AppColors.primary, shape: BoxShape.circle),
            child: const Icon(Icons.send, color: Colors.white, size: 18),
          ),
        ),
      ]),
    );
  }

  Widget _buildNotes() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(children: [
        Expanded(
          child: TextField(
            controller: _notesController,
            style: GoogleFonts.poppins(
                color: Colors.white, fontSize: 13, height: 1.5),
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            decoration: InputDecoration(
              hintText: 'Prenez vos notes ici...',
              hintStyle: GoogleFonts.poppins(
                  color: Colors.white38, fontSize: 13),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: Colors.white12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: Colors.white12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.primary),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(
                  ClipboardData(text: _notesController.text));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Notes copiées !',
                    style: GoogleFonts.poppins()),
                backgroundColor: AppColors.success,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ));
            },
            icon: const Icon(Icons.copy,
                size: 16, color: Colors.white54),
            label: Text('Copier les notes',
                style: GoogleFonts.poppins(
                    color: Colors.white54, fontSize: 12)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ]),
    );
  }

  // ── CONTROLS BAR ─────────────────────────────
  Widget _buildControls() {
    return Container(
      padding:
          const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        gradient: _showChat
            ? null
            : const LinearGradient(
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
            onTap: () {
              for (final t in _localStream?.getAudioTracks() ?? []) {
                t.enabled = !_micOn;
              }
              setState(() => _micOn = !_micOn);
            },
          ),
          _Btn(
            icon: _camOn ? Icons.videocam : Icons.videocam_off,
            label: _camOn ? 'Caméra' : 'Arrêt',
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
            icon: _sharingScreen
                ? Icons.stop_screen_share
                : Icons.screen_share,
            label: _sharingScreen ? 'Stopper' : 'Écran',
            active: !_sharingScreen,
            isHighlight: _sharingScreen,
            onTap: _toggleScreenShare,
          ),
          _Btn(
            icon: Icons.chat_bubble_outline,
            label: 'Chat',
            active: !_showChat,
            isHighlight: _showChat,
            onTap: () => setState(() {
              _showChat = !_showChat;
              if (_showChat) _showEmojiBar = false;
            }),
          ),
          _Btn(
            icon: Icons.emoji_emotions_outlined,
            label: 'Emoji',
            active: !_showEmojiBar,
            isHighlight: _showEmojiBar,
            onTap: () => setState(() {
              _showEmojiBar = !_showEmojiBar;
              if (_showEmojiBar) _showChat = false;
            }),
          ),
          _Btn(
            icon: Icons.call_end,
            label: 'Fin',
            active: false,
            isEnd: true,
            onTap: _leave,
          ),
        ],
      ),
    );
  }

  // ── WAITING SCREEN (no remote yet) ───────────
  Widget _buildWaiting() {
    return Container(
      color: const Color(0xFF1A1A2E),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                shape: BoxShape.circle),
            child: const Icon(Icons.person, color: Colors.white, size: 40),
          ),
          const SizedBox(height: 16),
          Text(
            widget.isHost
                ? 'Partagez l\'ID pour inviter des participants'
                : 'Connexion à la réunion...',
            textAlign: TextAlign.center,
            style:
                GoogleFonts.poppins(color: Colors.white70, fontSize: 14),
          ),
          if (widget.isHost) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () {
                Clipboard.setData(
                    ClipboardData(text: widget.meetingId));
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(
                  content: Text('ID copié !',
                      style: GoogleFonts.poppins()),
                  backgroundColor: AppColors.success,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.copy,
                      color: Colors.white54, size: 14),
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

// ─────────────────────────────────────────────
//  HELPER WIDGETS
// ─────────────────────────────────────────────

class _ChatTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChatTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? AppColors.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(children: [
          Icon(icon,
              size: 16,
              color: selected ? AppColors.primary : Colors.white54),
          const SizedBox(width: 6),
          Text(label,
              style: GoogleFonts.poppins(
                color: selected ? AppColors.primary : Colors.white54,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              )),
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
  final bool isHighlight;
  final VoidCallback onTap;

  const _Btn({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.isEnd = false,
    this.isHighlight = false,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    if (isEnd) {
      bg = Colors.red;
      fg = Colors.white;
    } else if (isHighlight) {
      bg = AppColors.primary;
      fg = Colors.white;
    } else if (active) {
      bg = Colors.white.withValues(alpha: 0.2);
      fg = Colors.white;
    } else {
      bg = Colors.white.withValues(alpha: 0.08);
      fg = Colors.white38;
    }

    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: Icon(icon, color: fg, size: 20),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: GoogleFonts.poppins(
                color: Colors.white54, fontSize: 9)),
      ]),
    );
  }
}
