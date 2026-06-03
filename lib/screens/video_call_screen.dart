import 'dart:async';
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/colors.dart';
import '../services/meeting_service.dart';
import '../services/pro_service.dart';

// ─────────────────────────────────────────────
//  MODELS
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

enum _NetQuality { good, fair, poor, unknown }

// ─────────────────────────────────────────────
//  WIDGET
// ─────────────────────────────────────────────
class VideoCallScreen extends StatefulWidget {
  final String meetingId;
  final String userId;
  final String userName;
  final bool isHost;

  const VideoCallScreen({
    super.key,
    required this.meetingId,
    required this.userId,
    required this.userName,
    required this.isHost,
  });

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen>
    with TickerProviderStateMixin {
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
  bool _isLocked = false;
  bool _speakerOn = true;
  String? _error;
  String _loadingStep = 'Démarrage...';

  // ── Network quality ──────────────────────────
  _NetQuality _netQuality = _NetQuality.unknown;
  Timer? _statsTimer;

  // ── Call timer ───────────────────────────────
  Timer? _callTimer;
  int _callSeconds = 0;

  // ── Auto-reconnect ───────────────────────────
  int _reconnectAttempts = 0;
  static const _maxReconnect = 3;
  Timer? _reconnectTimer;

  // ── Chat / Notes ─────────────────────────────
  int _chatTab = 0;
  final _chatController = TextEditingController();
  final _chatScrollController = ScrollController();
  final _notesController = TextEditingController();

  // ── Reactions ────────────────────────────────
  final List<_Reaction> _reactions = [];

  // ── Co-host / mute-all / presence ───────────
  bool _isCoHost = false;
  int _lastMuteAllCount = 0;
  List<Map<String, dynamic>> _presenceList = [];
  bool _showParticipants = false;

  // ── Pro / paywall ────────────────────────────
  bool _isPro = false;
  bool _paywallShown = false;
  static const _freeMinutes = 30;

  // ── Firestore streams ────────────────────────
  StreamSubscription? _callSub;
  StreamSubscription? _candidateSub;
  StreamSubscription<QuerySnapshot>? _reactionSub;
  StreamSubscription? _meetingDocSub;
  StreamSubscription? _presenceSub;
  StreamSubscription<bool>? _proSub;

  final _db = FirebaseFirestore.instance;
  final _meetingService = MeetingService();
  final _proService = ProService();

  String get _docId =>
      'room_${widget.meetingId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}';

  static const _iceConfig = {
    'iceServers': [
      {
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
          'stun:stun2.l.google.com:19302',
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
    _listenMeetingDoc();
    _listenPresence();
    _listenProStatus();
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _callSub?.cancel();
    _candidateSub?.cancel();
    _reactionSub?.cancel();
    _meetingDocSub?.cancel();
    _presenceSub?.cancel();
    _proSub?.cancel();
    _callTimer?.cancel();
    _statsTimer?.cancel();
    _reconnectTimer?.cancel();
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

      // Read quality preference
      final prefs = await SharedPreferences.getInstance();
      final quality = prefs.getString('crux_video_quality') ?? 'HD (720p)';
      final constraints = _videoConstraints(quality);

      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': constraints,
      }).timeout(
        const Duration(seconds: 20),
        onTimeout: () =>
            throw TimeoutException('Impossible d\'accéder à la caméra.'),
      );

      if (mounted) {
        setState(() {
          _localRenderer.srcObject = _localStream;
          _loading = false;
        });
      }

      // Register presence now that we have media
      await _meetingService.registerPresence(
          widget.meetingId, widget.userId, widget.userName);

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
          _startCallTimer();
          _startStatsMonitor();
          _reconnectAttempts = 0;
        }
      };

      _pc!.onConnectionState = (state) {
        if (!mounted) return;
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          setState(() => _remoteConnected = true);
          _startCallTimer();
          _startStatsMonitor();
          _reconnectAttempts = 0;
        } else if (state ==
                RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state ==
                RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          setState(() {
            _remoteConnected = false;
            _netQuality = _NetQuality.poor;
          });
          _attemptReconnect();
        }
      };

      _pc!.onIceConnectionState = (state) {
        if (!mounted) return;
        if (state == RTCIceConnectionState.RTCIceConnectionStateChecking) {
          setState(() => _netQuality = _NetQuality.fair);
        } else if (state ==
            RTCIceConnectionState.RTCIceConnectionStateConnected) {
          setState(() => _netQuality = _NetQuality.good);
        } else if (state ==
                RTCIceConnectionState.RTCIceConnectionStateFailed ||
            state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
          setState(() => _netQuality = _NetQuality.poor);
        }
      };

      _pc!.onIceCandidate = (c) {
        if (c.candidate == null) return;
        final col = widget.isHost ? 'offerCandidates' : 'answerCandidates';
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

  Map<String, dynamic> _videoConstraints(String quality) {
    switch (quality) {
      case 'SD (480p)':
        return {'facingMode': 'user', 'width': 640, 'height': 480};
      case 'Full HD (1080p)':
        return {'facingMode': 'user', 'width': 1920, 'height': 1080};
      case 'HD (720p)':
      default:
        return {'facingMode': 'user', 'width': 1280, 'height': 720};
    }
  }

  // ── CALL TIMER ───────────────────────────────
  void _listenProStatus() {
    _proSub = _proService.proStream(widget.userId).listen((pro) {
      if (mounted) setState(() => _isPro = pro);
    });
  }

  void _startCallTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _callSeconds++);
      // Check 30-min free limit
      if (!_isPro && !_paywallShown && _callSeconds >= _freeMinutes * 60) {
        _paywallShown = true;
        _showPaywall();
      }
    });
  }

  void _showPaywall() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_clock, color: Colors.white, size: 36),
              ),
              const SizedBox(height: 12),
              Text(
                'Limite gratuite atteinte',
                style: GoogleFonts.poppins(
                  color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '30 minutes gratuites écoulées.\nPassez à Crux Pro pour continuer.',
                style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withOpacity(0.4)),
                ),
                child: Column(
                  children: [
                    Text('Crux Pro', style: GoogleFonts.poppins(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text('25 000 FCFA / mois', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20)),
                    const SizedBox(height: 8),
                    Text('✓ Réunions illimitées\n✓ Tous les participants\n✓ Accès immédiat',
                      style: GoogleFonts.poppins(color: Colors.white60, fontSize: 12, height: 1.6),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _leave();
              },
              child: Text('Quitter', style: GoogleFonts.poppins(color: Colors.white38)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: () async {
                Navigator.pop(context);
                try {
                  await _proService.startPayment(
                    userId: widget.userId,
                    userName: widget.userName,
                  );
                  // After returning from payment, re-check Pro status
                  final pro = await _proService.isPro(widget.userId);
                  if (mounted && pro) {
                    setState(() { _isPro = true; _paywallShown = false; });
                  } else if (mounted) {
                    // Not paid yet, show paywall again after 10s
                    Future.delayed(const Duration(seconds: 10), () {
                      if (mounted && !_isPro) _showPaywall();
                    });
                  }
                } catch (_) {
                  if (mounted) _showPaywall();
                }
              },
              child: Text('Passer Pro', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  String get _formattedDuration {
    final h = _callSeconds ~/ 3600;
    final m = (_callSeconds % 3600) ~/ 60;
    final s = _callSeconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ── STATS MONITOR ────────────────────────────
  void _startStatsMonitor() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_pc == null || !mounted) return;
      try {
        final stats = await _pc!.getStats();
        int packetsLost = 0;
        int packetsReceived = 0;
        for (final stat in stats) {
          final values = stat.values;
          if (values.containsKey('packetsLost')) {
            packetsLost += (values['packetsLost'] as num?)?.toInt() ?? 0;
          }
          if (values.containsKey('packetsReceived')) {
            packetsReceived +=
                (values['packetsReceived'] as num?)?.toInt() ?? 0;
          }
        }
        if (!mounted) return;
        final total = packetsLost + packetsReceived;
        if (total == 0) return;
        final lossRatio = packetsLost / total;
        setState(() {
          if (lossRatio < 0.02) {
            _netQuality = _NetQuality.good;
          } else if (lossRatio < 0.08) {
            _netQuality = _NetQuality.fair;
          } else {
            _netQuality = _NetQuality.poor;
          }
        });
      } catch (_) {}
    });
  }

  // ── AUTO-RECONNECT ───────────────────────────
  void _attemptReconnect() {
    if (_reconnectAttempts >= _maxReconnect) return;
    _reconnectAttempts++;
    final delay = Duration(seconds: _reconnectAttempts * 2);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () async {
      if (!mounted) return;
      try {
        await _pc?.restartIce();
        if (!widget.isHost) await _joinCall();
      } catch (_) {}
    });
  }

  // ── MEETING DOC LISTENER (lock + co-host + mute-all) ────────────────
  void _listenMeetingDoc() {
    _meetingDocSub = _db
        .collection('meetings')
        .doc(widget.meetingId)
        .snapshots()
        .listen((snap) {
      if (!snap.exists || !mounted) return;
      final data = snap.data()!;
      // co-host check
      final coHosts = List<String>.from(data['coHosts'] ?? []);
      final nowCoHost = coHosts.contains(widget.userId);
      // mute-all check
      final muteCount = (data['muteAllCount'] ?? 0) as int;
      final isPrivileged = widget.isHost || nowCoHost;
      if (muteCount > _lastMuteAllCount && !isPrivileged) {
        _lastMuteAllCount = muteCount;
        for (final t in _localStream?.getAudioTracks() ?? []) {
          t.enabled = false;
        }
        if (mounted) {
          setState(() => _micOn = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("L'hôte a coupé tous les micros",
                style: GoogleFonts.poppins()),
            backgroundColor: Colors.orange.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 3),
          ));
        }
      } else if (muteCount > _lastMuteAllCount) {
        _lastMuteAllCount = muteCount;
      }
      // isLocked check
      final locked = data['isLocked'] ?? false;
      if (mounted) setState(() {
        _isCoHost = nowCoHost;
        _isLocked = locked as bool;
      });
    });
  }

  // ── PRESENCE LISTENER ────────────────────────
  void _listenPresence() {
    _presenceSub = _meetingService
        .streamPresence(widget.meetingId)
        .listen((list) {
      if (mounted) setState(() => _presenceList = list);
    });
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
    final snap = await _db.collection('webrtc_rooms').doc(_docId).get();
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
    HapticFeedback.mediumImpact();
    if (_sharingScreen) {
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ));
        }
      }
    }
  }

  // ── LOCK (host/co-host) ──────────────────────
  Future<void> _toggleLock() async {
    HapticFeedback.mediumImpact();
    final next = !_isLocked;
    await _meetingService.setLocked(widget.meetingId, next);
    if (mounted) setState(() => _isLocked = next);
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
    HapticFeedback.lightImpact();
    _spawnReaction(emoji);
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
    HapticFeedback.selectionClick();
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
    HapticFeedback.heavyImpact();
    _callSub?.cancel();
    _candidateSub?.cancel();
    _reactionSub?.cancel();
    _meetingDocSub?.cancel();
    _presenceSub?.cancel();
    _callTimer?.cancel();
    _statsTimer?.cancel();
    _reconnectTimer?.cancel();
    await _meetingService.removePresence(widget.meetingId, widget.userId);
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

  Widget _buildLoading() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(color: Colors.white),
          const SizedBox(height: 20),
          Text(_loadingStep,
              style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14)),
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
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: Text('Retour',
                  style: GoogleFonts.poppins(color: Colors.white)),
            ),
          ]),
        ),
      );

  Widget _buildCall() {
    final isPrivileged = widget.isHost || _isCoHost;

    return Stack(children: [
      // ── MAIN VIDEO (full screen) ──────────────────────────────────────
      Positioned.fill(
        child: isPrivileged
            // Privileged: own camera big (TikTok Live style)
            ? (_camOn
                ? RTCVideoView(_localRenderer,
                    mirror: !_sharingScreen,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                : _buildInitialsAvatar(widget.userName, size: double.infinity))
            // Participant: remote host camera big
            : (_remoteConnected
                ? RTCVideoView(_remoteRenderer,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                : _buildWaiting()),
      ),

      // ── REMOTE CARD (for host/cohost when someone joined) ─────────────
      if (isPrivileged && _remoteConnected)
        Positioned(
          bottom: 85,
          right: 12,
          width: 120,
          height: 165,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(children: [
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white30, width: 1.5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: RTCVideoView(_remoteRenderer,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
              ),
              // participant label at bottom of their card
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(16)),
                  ),
                  child: Text(
                    _presenceList
                        .where((p) => p['userId'] != widget.userId)
                        .map((p) => (p['name'] as String? ?? '').split(' ').first)
                        .join(', '),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                        color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ]),
          ),
        ),

      // ── LOCAL PiP (for participants — their own camera, top-right) ────
      if (!isPrivileged)
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
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                  : _buildInitialsAvatar(widget.userName, size: 110),
            ),
          ),
        ),

      // ── TOP BAR ──────────────────────────────────────────────────────
      Positioned(top: 0, left: 0, right: 0, child: _buildTopBar()),

      // ── FLOATING REACTIONS ───────────────────────────────────────────
      ..._reactions.map(
        (r) => AnimatedPositioned(
          duration: const Duration(milliseconds: 2000),
          curve: Curves.easeOut,
          bottom: r.bottomOffset,
          left: MediaQuery.of(context).size.width / 2 - 22,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 700),
            opacity: r.opacity,
            child: Text(r.emoji, style: const TextStyle(fontSize: 38)),
          ),
        ),
      ),

      // ── EMOJI BAR ────────────────────────────────────────────────────
      AnimatedPositioned(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        bottom: _showEmojiBar ? (_showChat ? 390 + 70 : 70) : -60,
        left: 0,
        right: 0,
        child: _buildEmojiBar(),
      ),

      // ── PARTICIPANTS PANEL ───────────────────────────────────────────
      AnimatedPositioned(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
        bottom: _showParticipants ? 0 : -380,
        left: 0,
        right: 0,
        height: 380,
        child: _buildParticipantsPanel(),
      ),

      // ── CHAT PANEL ───────────────────────────────────────────────────
      AnimatedPositioned(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
        bottom: _showChat ? 0 : -400,
        left: 0,
        right: 0,
        height: 400,
        child: _buildChatPanel(),
      ),

      // ── CONTROLS ─────────────────────────────────────────────────────
      AnimatedPositioned(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
        bottom: (_showChat || _showParticipants) ? 400 : 0,
        left: 0,
        right: 0,
        child: _buildControls(),
      ),

      // ── HOST SOLO INVITE BANNER ──────────────────────────────────────
      if (isPrivileged && !_remoteConnected)
        Positioned(
          bottom: 75,
          left: 0,
          right: 0,
          child: Center(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                Clipboard.setData(ClipboardData(text: widget.meetingId));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('ID copié !', style: GoogleFonts.poppins()),
                  backgroundColor: AppColors.success,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.copy, color: Colors.white70, size: 15),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Inviter des participants',
                          style: GoogleFonts.poppins(
                              color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500)),
                      Text(widget.meetingId,
                          style: GoogleFonts.poppins(
                              color: Colors.white, fontSize: 15,
                              fontWeight: FontWeight.w800, letterSpacing: 2)),
                    ],
                  ),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }

  // ── INITIALS AVATAR ──────────────────────────
  Widget _buildInitialsAvatar(String name, {double size = 80}) {
    final parts = name.trim().split(' ');
    final initials = parts.length >= 2
        ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
        : name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
    return Container(
      width: size,
      height: size,
      color: Colors.black87,
      child: Center(
        child: Container(
          width: size * 0.6,
          height: size * 0.6,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              initials,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: size * 0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── TOP BAR ──────────────────────────────────
  Widget _buildTopBar() {
    Color netColor;
    String netLabel;
    switch (_netQuality) {
      case _NetQuality.good:
        netColor = Colors.green;
        netLabel = 'Excellent';
        break;
      case _NetQuality.fair:
        netColor = Colors.orange;
        netLabel = 'Moyen';
        break;
      case _NetQuality.poor:
        netColor = Colors.red;
        netLabel = 'Faible';
        break;
      case _NetQuality.unknown:
        netColor = Colors.grey;
        netLabel = '';
        break;
    }

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
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          widget.meetingId.length > 12
              ? widget.meetingId.substring(0, 12)
              : widget.meetingId,
          style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12),
        ),
        if (_remoteConnected && _callSeconds > 0) ...[
          const SizedBox(width: 8),
          Text(
            _formattedDuration,
            style: GoogleFonts.poppins(
                color: Colors.white60,
                fontSize: 12,
                fontFeatures: [const FontFeature.tabularFigures()]),
          ),
        ],
        if (_sharingScreen) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
        if (_isLocked) ...[
          const SizedBox(width: 8),
          const Icon(Icons.lock, color: Colors.amber, size: 14),
        ],
        if (_isCoHost) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.6)),
            ),
            child: Text('Co-hôte',
                style: GoogleFonts.poppins(
                    color: Colors.amber, fontSize: 9, fontWeight: FontWeight.w600)),
          ),
        ],
        const Spacer(),
        // Network quality dot
        if (_netQuality != _NetQuality.unknown) ...[
          Container(
            width: 8,
            height: 8,
            decoration:
                BoxDecoration(color: netColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(netLabel,
              style: GoogleFonts.poppins(color: netColor, fontSize: 10)),
          const SizedBox(width: 8),
        ],
        if (!_remoteConnected)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                    child: Text(e, style: const TextStyle(fontSize: 26)),
                  ),
                ))
            .toList(),
      ),
    );
  }

  // ── PARTICIPANTS PANEL ────────────────────────
  Widget _buildParticipantsPanel() {
    final isPrivileged = widget.isHost || _isCoHost;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.7), blurRadius: 20)
        ],
      ),
      child: Column(children: [
        const SizedBox(height: 8),
        Container(
          width: 40, height: 4,
          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            const Icon(Icons.people, color: Colors.white70, size: 18),
            const SizedBox(width: 8),
            Text('Participants (${_presenceList.length})',
                style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
            const Spacer(),
            if (isPrivileged)
              GestureDetector(
                onTap: () async {
                  HapticFeedback.mediumImpact();
                  await _meetingService.triggerMuteAll(widget.meetingId);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Tous les micros ont été coupés', style: GoogleFonts.poppins()),
                    backgroundColor: Colors.orange.shade700,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.6)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.mic_off, color: Colors.orange, size: 14),
                    const SizedBox(width: 5),
                    Text('Couper tous', style: GoogleFonts.poppins(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white54, size: 22),
              onPressed: () => setState(() => _showParticipants = false),
            ),
          ]),
        ),
        const Divider(color: Colors.white12, height: 1),
        Expanded(
          child: _presenceList.isEmpty
              ? Center(child: Text('Aucun participant', style: GoogleFonts.poppins(color: Colors.white38, fontSize: 13)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _presenceList.length,
                  itemBuilder: (ctx, i) {
                    final p = _presenceList[i];
                    final pId = p['userId'] as String? ?? '';
                    final pName = p['name'] as String? ?? 'Participant';
                    final isMe = pId == widget.userId;
                    final initial = pName.isNotEmpty ? pName[0].toUpperCase() : '?';
                    return ListTile(
                      leading: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(gradient: AppColors.primaryGradient, shape: BoxShape.circle),
                        child: Center(child: Text(initial,
                            style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16))),
                      ),
                      title: Text(
                        '$pName${isMe ? ' (Moi)' : ''}',
                        style: GoogleFonts.poppins(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      trailing: isPrivileged && !isMe
                          ? PopupMenuButton<String>(
                              color: const Color(0xFF282828),
                              icon: const Icon(Icons.more_vert, color: Colors.white54, size: 20),
                              onSelected: (action) async {
                                if (action == 'cohost') {
                                  await _meetingService.addCoHost(widget.meetingId, pId);
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    content: Text('$pName est maintenant co-hôte', style: GoogleFonts.poppins()),
                                    backgroundColor: AppColors.success,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ));
                                } else if (action == 'remove_cohost') {
                                  await _meetingService.removeCoHost(widget.meetingId, pId);
                                }
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(value: 'cohost',
                                    child: Row(children: [
                                      const Icon(Icons.star, color: Colors.amber, size: 16),
                                      const SizedBox(width: 8),
                                      Text('Nommer co-hôte', style: GoogleFonts.poppins(color: Colors.white, fontSize: 13)),
                                    ])),
                                PopupMenuItem(value: 'remove_cohost',
                                    child: Row(children: [
                                      const Icon(Icons.star_border, color: Colors.white54, size: 16),
                                      const SizedBox(width: 8),
                                      Text('Retirer co-hôte', style: GoogleFonts.poppins(color: Colors.white54, fontSize: 13)),
                                    ])),
                              ],
                            )
                          : null,
                    );
                  },
                ),
        ),
      ]),
    );
  }

  // ── CHAT PANEL ───────────────────────────────
  Widget _buildChatPanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.7), blurRadius: 20)
        ],
      ),
      child: Column(children: [
        const SizedBox(height: 8),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(height: 4),
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
            onPressed: () => setState(() => _showChat = false),
          ),
        ]),
        const Divider(color: Colors.white12, height: 1),
        Expanded(
          child: _chatTab == 0 ? _buildChatMessages() : _buildNotes(),
        ),
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: docs.length,
          itemBuilder: (ctx, i) {
            final d = docs[i].data()! as Map<String, dynamic>;
            final isMine = d['sender'] == widget.userName;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Align(
                alignment:
                    isMine ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(ctx).size.width * 0.72),
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
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _sendMessage(),
            decoration: InputDecoration(
              hintText: 'Message...',
              hintStyle:
                  GoogleFonts.poppins(color: Colors.white38, fontSize: 13),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.08),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _sendMessage,
          child: Container(
            width: 40,
            height: 40,
            decoration:
                BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
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
            style:
                GoogleFonts.poppins(color: Colors.white, fontSize: 13, height: 1.5),
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            decoration: InputDecoration(
              hintText: 'Prenez vos notes ici...',
              hintStyle:
                  GoogleFonts.poppins(color: Colors.white38, fontSize: 13),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white12),
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
              Clipboard.setData(ClipboardData(text: _notesController.text));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Notes copiées !', style: GoogleFonts.poppins()),
                backgroundColor: AppColors.success,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ));
            },
            icon: const Icon(Icons.copy, size: 16, color: Colors.white54),
            label: Text('Copier les notes',
                style:
                    GoogleFonts.poppins(color: Colors.white54, fontSize: 12)),
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
    final isPrivileged = widget.isHost || _isCoHost;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
      decoration: BoxDecoration(
        gradient: (_showChat || _showParticipants)
            ? null
            : const LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black87, Colors.transparent],
              ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Btn(
              icon: _micOn ? Icons.mic : Icons.mic_off,
              label: _micOn ? 'Micro' : 'Muet',
              active: _micOn,
              onTap: () {
                HapticFeedback.selectionClick();
                for (final t in _localStream?.getAudioTracks() ?? []) {
                  t.enabled = !_micOn;
                }
                setState(() => _micOn = !_micOn);
              },
            ),
            const SizedBox(width: 8),
            _Btn(
              icon: _camOn ? Icons.videocam : Icons.videocam_off,
              label: _camOn ? 'Caméra' : 'Arrêt',
              active: _camOn,
              onTap: () {
                HapticFeedback.selectionClick();
                for (final t in _localStream?.getVideoTracks() ?? []) {
                  t.enabled = !_camOn;
                }
                setState(() => _camOn = !_camOn);
              },
            ),
            const SizedBox(width: 8),
            _Btn(
              icon: Icons.flip_camera_ios,
              label: 'Flip',
              active: true,
              onTap: () async {
                HapticFeedback.selectionClick();
                for (final t in _localStream?.getVideoTracks() ?? []) {
                  await Helper.switchCamera(t);
                }
              },
            ),
            const SizedBox(width: 8),
            _Btn(
              icon: _speakerOn ? Icons.volume_up : Icons.volume_off,
              label: _speakerOn ? 'HP' : 'Muet HP',
              active: _speakerOn,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _speakerOn = !_speakerOn);
                try {
                  Helper.setSpeakerphoneOn(_speakerOn ? false : true);
                } catch (_) {}
              },
            ),
            const SizedBox(width: 8),
            _Btn(
              icon: _sharingScreen
                  ? Icons.stop_screen_share
                  : Icons.screen_share,
              label: _sharingScreen ? 'Stopper' : 'Écran',
              active: !_sharingScreen,
              isHighlight: _sharingScreen,
              onTap: _toggleScreenShare,
            ),
            const SizedBox(width: 8),
            _Btn(
              icon: Icons.chat_bubble_outline,
              label: 'Chat',
              active: !_showChat,
              isHighlight: _showChat,
              onTap: () => setState(() {
                _showChat = !_showChat;
                if (_showChat) { _showEmojiBar = false; _showParticipants = false; }
              }),
            ),
            const SizedBox(width: 8),
            _Btn(
              icon: Icons.people_outline,
              label: 'Participants',
              active: !_showParticipants,
              isHighlight: _showParticipants,
              onTap: () => setState(() {
                _showParticipants = !_showParticipants;
                if (_showParticipants) { _showChat = false; _showEmojiBar = false; }
              }),
            ),
            const SizedBox(width: 8),
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
            if (isPrivileged) ...[
              const SizedBox(width: 8),
              _Btn(
                icon: _isLocked ? Icons.lock : Icons.lock_open,
                label: _isLocked ? 'Déverrouiller' : 'Verrouiller',
                active: !_isLocked,
                isHighlight: _isLocked,
                onTap: _toggleLock,
              ),
              const SizedBox(width: 8),
              _Btn(
                icon: Icons.mic_off,
                label: 'Couper tous',
                active: true,
                onTap: () async {
                  HapticFeedback.mediumImpact();
                  await _meetingService.triggerMuteAll(widget.meetingId);
                },
              ),
            ],
            const SizedBox(width: 8),
            _Btn(
              icon: Icons.call_end,
              label: 'Fin',
              active: false,
              isEnd: true,
              onTap: _leave,
            ),
          ],
        ),
      ),
    );
  }

  // ── WAITING (participant only — host uses full-screen local cam) ────────
  Widget _buildWaiting() {
    return Container(
      color: const Color(0xFF1A1A2E),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
                gradient: AppColors.primaryGradient, shape: BoxShape.circle),
            child: Center(
              child: Text(
                widget.userName.isNotEmpty
                    ? widget.userName[0].toUpperCase()
                    : '?',
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Connexion à la réunion...',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 12),
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
                color: Colors.white54, strokeWidth: 2),
          ),
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
            style: GoogleFonts.poppins(color: Colors.white54, fontSize: 9)),
      ]),
    );
  }
}
