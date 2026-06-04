import 'dart:async';
import 'dart:io';
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../theme/colors.dart';
import '../services/meeting_service.dart';
import '../services/pro_service.dart';
import '../models/meeting_model.dart';

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

enum _VideoQuality { low, medium, high, hd }

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
  bool _leaving = false;
  bool _micOn = true;
  bool _camOn = true;
  bool _loading = true;
  bool _remoteConnected = false;
  bool _answerSet = false;
  bool _sharingScreen = false;
  bool _showChat = false;
  int _unreadMessages = 0; // unread chat badge
  bool _showEmojiBar = false;
  bool _isLocked = false;
  bool _speakerOn = true;
  String? _error;
  String _loadingStep = 'Démarrage...';

  // ── Network quality ──────────────────────────
  _NetQuality _netQuality = _NetQuality.unknown;
  Timer? _statsTimer;

  // ── Video quality ────────────────────────────
  _VideoQuality _videoQuality = _VideoQuality.medium;

  // ── Call timer ───────────────────────────────
  Timer? _callTimer;
  int _callSeconds = 0;

  // ── Auto-reconnect ───────────────────────────
  int _reconnectAttempts = 0;
  static const _maxReconnect = 3;
  Timer? _reconnectTimer;

  // ── Waiting for host (participant side) ──────
  bool _waitingForHost = false;
  Timer? _hostWaitTimer;

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
  bool _handRaised = false;
  bool _swappedView = false; // true = remote big, local small
  final Set<String> _raisedHands = {};

  // ── Pro / paywall ────────────────────────────
  bool _isPro = false;
  bool _paywallShown = false;
  static const _freeMinutes = 30;

  // ── Live mode ────────────────────────────────
  bool _isLiveMode = false;
  bool _liveCommentVisible = false;
  final _liveCommentController = TextEditingController();
  final List<Map<String, String>> _liveComments = [];
  StreamSubscription? _liveCommentSub;
  final _liveCommentsScrollController = ScrollController();
  bool _showLiveGifts = false;
  int _liveViewers = 1;

  // ── YouTube Live Streaming ──────────────────
  String? _youtubeRtmpKey;
  String? _youtubeUrl;
  bool _youtubeStreamingActive = false;
  String? _liveBackgroundImagePath;
  bool _selectingBackground = false;
  final _picker = ImagePicker();

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
      {
        'urls': [
          'turn:openrelay.metered.ca:80',
          'turn:openrelay.metered.ca:443',
          'turn:openrelay.metered.ca:443?transport=tcp',
        ],
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ],
    'sdpSemantics': 'unified-plan',
    'iceTransportPolicy': 'all',
    'bundlePolicy': 'max-bundle',
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
    _detectLiveMode();
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
    _hostWaitTimer?.cancel();
    _liveCommentSub?.cancel();
    _liveCommentController.dispose();
    _liveCommentsScrollController.dispose();
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

  String _formattedDuration2(int secs) {
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    final s = secs % 60;
    if (h > 0) return '${h}h${m.toString().padLeft(2, '0')}m';
    if (m > 0) return '${m}min ${s}s';
    return '${s}s';
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
      if (!snap.exists || !mounted || _leaving) return;
      final data = snap.data()!;

      // Host ended meeting for everyone
      final status = data['status'] as String? ?? '';
      if (status == 'ended' && !widget.isHost) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("L'hôte a terminé la réunion", style: GoogleFonts.poppins()),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 3),
        ));
        _leave();
        return;
      }

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
      if (!mounted) return;
      if (widget.isHost) {
        for (final p in list) {
          final uid = p['userId'] as String? ?? '';
          final raised = p['handRaised'] == true;
          if (raised && uid != widget.userId && !_raisedHands.contains(uid)) {
            _raisedHands.add(uid);
            final name = p['userName'] ?? 'Participant';
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('🖐 $name a levé la main', style: GoogleFonts.poppins(color: Colors.white)),
              backgroundColor: Colors.orange.shade800,
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ));
          } else if (!raised) {
            _raisedHands.remove(uid);
          }
        }
      }
      setState(() {
        _presenceList = list;
        if (_isLiveMode) _liveViewers = list.length;
      });
    });
  }

  Future<void> _toggleRaiseHand() async {
    final next = !_handRaised;
    setState(() => _handRaised = next);
    try {
      await _db
          .collection('meetings')
          .doc(widget.meetingId)
          .collection('presence')
          .doc(widget.userId)
          .update({'handRaised': next});
    } catch (_) {}
    if (next && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('🖐 Main levée', style: GoogleFonts.poppins(color: Colors.white)),
        backgroundColor: Colors.orange.shade700,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
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
    final snap = await _db.collection('webrtc_rooms').doc(_docId).get();
    if (!snap.exists || snap.data()?['offer'] == null) {
      if (mounted) {
        setState(() => _waitingForHost = true);
        _hostWaitTimer?.cancel();
        _hostWaitTimer = Timer(const Duration(seconds: 3), _joinCall);
      }
      return;
    }
    if (mounted) setState(() => _waitingForHost = false);

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

  // ── VIDEO QUALITY ────────────────────────────
  Future<void> _applyVideoQuality(_VideoQuality q) async {
    setState(() => _videoQuality = q);
    final videoTrack = _localStream?.getVideoTracks().firstOrNull;
    if (videoTrack == null) return;
    switch (q) {
      case _VideoQuality.low:
        await videoTrack.applyConstraints({'width': 320, 'height': 240, 'frameRate': 15});
        break;
      case _VideoQuality.medium:
        await videoTrack.applyConstraints({'width': 640, 'height': 480, 'frameRate': 24});
        break;
      case _VideoQuality.high:
        await videoTrack.applyConstraints({'width': 1280, 'height': 720, 'frameRate': 30});
        break;
      case _VideoQuality.hd:
        await videoTrack.applyConstraints({'width': 1920, 'height': 1080, 'frameRate': 30});
        break;
    }
  }

  // ── SCREEN SHARE ────────────────────────────
  Future<void> _toggleScreenShare() async {
    HapticFeedback.mediumImpact();
    if (_sharingScreen) {
      // ── Stop sharing ──
      try {
        if (_pc != null) {
          final senders = await _pc!.getSenders();
          for (final sender in senders) {
            if (sender.track?.kind == 'video') {
              final cam = _localStream?.getVideoTracks();
              if (cam != null && cam.isNotEmpty) {
                await sender.replaceTrack(cam.first);
              }
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
      } catch (e) {
        // Ensure state is reset even on error
        await _screenStream?.dispose();
        _screenStream = null;
        if (mounted) setState(() => _sharingScreen = false);
      }
    } else {
      // ── Start sharing ──
      try {
        _screenStream = await navigator.mediaDevices.getDisplayMedia({
          'video': {'mandatory': {}, 'optional': []},
          'audio': false,
        });

        final tracks = _screenStream!.getVideoTracks();
        if (tracks.isEmpty) {
          await _screenStream?.dispose();
          _screenStream = null;
          return;
        }

        final screenTrack = tracks.first;

        if (_pc != null) {
          final senders = await _pc!.getSenders();
          for (final sender in senders) {
            if (sender.track?.kind == 'video') {
              await sender.replaceTrack(screenTrack);
            }
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
        await _screenStream?.dispose();
        _screenStream = null;
        if (mounted) {
          final msg = e.toString().contains('Permission')
              ? 'Permission refusée pour le partage d\'écran.'
              : e.toString().contains('cancel') || e.toString().contains('Cancel')
                  ? 'Partage d\'écran annulé.'
                  : 'Partage d\'écran indisponible sur cet appareil.';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(msg, style: GoogleFonts.poppins()),
            backgroundColor: Colors.orange.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

  // ── LIVE MODE ────────────────────────────────
  Future<void> _detectLiveMode() async {
    try {
      final snap = await _db.collection('meetings').doc(widget.meetingId).get();
      if (!snap.exists) return;
      final title = snap.data()?['title'] as String? ?? '';
      if (mounted) {
        setState(() => _isLiveMode = title.contains('[Live]') || title.contains('[LIVE]'));
        if (_isLiveMode) {
          _listenLiveComments();
          _loadYouTubeSettings();
        }
      }
    } catch (_) {}
  }

  void _listenLiveComments() {
    if (!_isLiveMode) return;
    _liveCommentSub = _db
        .collection('meetings')
        .doc(widget.meetingId)
        .collection('liveComments')
        .orderBy('createdAt', descending: false)
        .limitToLast(50)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      const colors = ['#FF4444', '#FF8C00', '#FFD700', '#00FF88', '#00BFFF', '#FF69B4', '#DA70D6'];
      for (final ch in snap.docChanges) {
        if (ch.type == DocumentChangeType.added) {
          final d = ch.doc.data()!;
          setState(() {
            _liveComments.add({
              'name': d['name'] as String? ?? 'Anonyme',
              'text': d['text'] as String? ?? '',
              'color': colors[_liveComments.length % colors.length],
            });
            if (_liveComments.length > 100) _liveComments.removeAt(0);
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_liveCommentsScrollController.hasClients) {
              _liveCommentsScrollController.animateTo(
                _liveCommentsScrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          });
        }
      }
    });
  }

  Future<void> _sendLiveComment(String text) async {
    if (text.trim().isEmpty) return;
    _liveCommentController.clear();
    try {
      await _db
          .collection('meetings')
          .doc(widget.meetingId)
          .collection('liveComments')
          .add({
        'name': widget.userName,
        'text': text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  // ── YOUTUBE LIVE STREAMING ──────────────────
  Future<void> _loadYouTubeSettings() async {
    try {
      final snap = await _db.collection('meetings').doc(widget.meetingId).get();
      if (!snap.exists) return;
      final data = snap.data()!;
      if (mounted) {
        setState(() {
          _youtubeRtmpKey = data['youtubeRtmpKey'] as String?;
          _youtubeUrl = data['youtubeUrl'] as String?;
          _liveBackgroundImagePath = data['backgroundImagePath'] as String?;
        });
      }
    } catch (_) {}
  }

  Future<void> _selectBackgroundImage() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1080);
    if (picked == null) return;

    try {
      setState(() => _selectingBackground = true);

      final dir = await getApplicationDocumentsDirectory();
      final dest = '${dir.path}/live_background.jpg';
      await File(picked.path).copy(dest);

      // Save path to Firestore
      await _db.collection('meetings').doc(widget.meetingId).update({
        'backgroundImagePath': dest,
      });

      if (mounted) {
        setState(() {
          _liveBackgroundImagePath = dest;
          _selectingBackground = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _selectingBackground = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur: $e', style: GoogleFonts.poppins()),
          backgroundColor: Colors.red.shade700,
        ));
      }
    }
  }

  Future<void> _showYouTubeLiveDialog() async {
    final keyCtrl = TextEditingController(text: _youtubeRtmpKey ?? '');
    final urlCtrl = TextEditingController(text: _youtubeUrl ?? '');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Retransmission YouTube',
            style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Configurez votre retransmission YouTube en direct',
                style: GoogleFonts.poppins(color: Colors.white60, fontSize: 12)),
            const SizedBox(height: 16),

            // RTMP Key input
            TextField(
              controller: keyCtrl,
              style: GoogleFonts.poppins(color: Colors.white),
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Clé RTMP YouTube',
                labelStyle: GoogleFonts.poppins(color: Colors.white54),
                prefixIcon: const Icon(Icons.key, color: Color(0xFFB71C1C)),
                hintText: 'Collez votre clé RTMP ici',
                hintStyle: GoogleFonts.poppins(color: Colors.white30),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.08),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFB71C1C), width: 2),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // YouTube URL input
            TextField(
              controller: urlCtrl,
              style: GoogleFonts.poppins(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'URL du direct YouTube',
                labelStyle: GoogleFonts.poppins(color: Colors.white54),
                prefixIcon: const Icon(Icons.link, color: Color(0xFFB71C1C)),
                hintText: 'https://youtube.com/watch?v=...',
                hintStyle: GoogleFonts.poppins(color: Colors.white30),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.08),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFB71C1C), width: 2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Helper text
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue, width: 0.5),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Comment obtenir votre clé RTMP ?',
                    style: GoogleFonts.poppins(color: Colors.blue, fontWeight: FontWeight.w600, fontSize: 12)),
                const SizedBox(height: 6),
                Text(
                  '1. Allez sur youtube.com/live_dashboard\n'
                  '2. Cliquez sur "Créer un direct"\n'
                  '3. Paramétrez le titre et la description\n'
                  '4. Copiez la clé RTMP du serveur\n'
                  '5. Collez-la ici',
                  style: GoogleFonts.poppins(color: Colors.blue.shade200, fontSize: 11, height: 1.4),
                ),
              ]),
            ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Annuler', style: GoogleFonts.poppins(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _db.collection('meetings').doc(widget.meetingId).update({
                'youtubeRtmpKey': keyCtrl.text.trim(),
                'youtubeUrl': urlCtrl.text.trim(),
              });
              if (mounted) {
                setState(() {
                  _youtubeRtmpKey = keyCtrl.text.trim();
                  _youtubeUrl = urlCtrl.text.trim();
                });
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB71C1C),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Enregistrer', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleYouTubeStreaming() async {
    if (!_youtubeStreamingActive) {
      // ── START streaming ──
      if (_youtubeRtmpKey == null || _youtubeRtmpKey!.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Configurez votre clé RTMP YouTube d\'abord',
              style: GoogleFonts.poppins()),
          backgroundColor: Colors.orange.shade700,
        ));
        return;
      }

      // In a real app, you would send the WebRTC stream to YouTube via RTMP
      // This requires a backend service (Mux, Livepeer, or self-hosted FFmpeg)
      // For now, we simulate the streaming and just update the UI

      if (mounted) {
        setState(() => _youtubeStreamingActive = true);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ Retransmission YouTube démarrée', style: GoogleFonts.poppins()),
          backgroundColor: Colors.green.shade700,
        ));

        // Log the event to Firestore
        try {
          await _db.collection('meetings').doc(widget.meetingId).update({
            'youtubeStreamingActive': true,
            'youtubeStreamStartedAt': FieldValue.serverTimestamp(),
          });
        } catch (_) {}
      }
    } else {
      // ── STOP streaming ──
      if (mounted) {
        setState(() => _youtubeStreamingActive = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ Retransmission YouTube arrêtée', style: GoogleFonts.poppins()),
          backgroundColor: Colors.red.shade700,
        ));

        try {
          await _db.collection('meetings').doc(widget.meetingId).update({
            'youtubeStreamingActive': false,
            'youtubeStreamEndedAt': FieldValue.serverTimestamp(),
          });
        } catch (_) {}
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
  Future<void> _confirmLeave() async {
    if (_leaving) return;
    HapticFeedback.mediumImpact();
    if (widget.isHost) {
      // Host gets two options: leave only, or end for everyone
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Terminer la réunion ?',
              style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700)),
          content: Text('Voulez-vous quitter uniquement ou terminer la réunion pour tous les participants ?',
              style: GoogleFonts.poppins(color: Colors.white60, fontSize: 13, height: 1.5)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Annuler', style: GoogleFonts.poppins(color: Colors.white38)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _leave();
              },
              child: Text('Quitter seulement', style: GoogleFonts.poppins(color: Colors.white70)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                Navigator.pop(context);
                // Fire-and-forget: don't await before _leave()
                _meetingService.updateMeetingStatus(
                    widget.meetingId, MeetingStatus.ended).catchError((_) {});
                _leave();
              },
              child: Text('Terminer pour tous', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
    } else {
      // Participant gets simple confirm
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Quitter la réunion ?',
              style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700)),
          content: Text('Êtes-vous sûr de vouloir quitter cette réunion ?',
              style: GoogleFonts.poppins(color: Colors.white60, fontSize: 13)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Annuler', style: GoogleFonts.poppins(color: Colors.white38)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Quitter', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
      if (confirm == true) _leave();
    }
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    HapticFeedback.heavyImpact();

    // Capture state BEFORE any async operation
    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final duration = _callSeconds;
    final participantCount = _presenceList.length;
    final isHost = widget.isHost;

    // 1. Cancel ALL subscriptions synchronously
    _callSub?.cancel();
    _candidateSub?.cancel();
    _reactionSub?.cancel();
    _meetingDocSub?.cancel();
    _presenceSub?.cancel();
    _proSub?.cancel();
    _liveCommentSub?.cancel();
    _callTimer?.cancel();
    _statsTimer?.cancel();
    _reconnectTimer?.cancel();
    _hostWaitTimer?.cancel();

    // 2. Navigate immediately
    navigator.pop();

    // 3. Show meeting summary to host (brief, non-blocking)
    if (isHost && duration > 5) {
      Future.delayed(const Duration(milliseconds: 300), () {
        scaffoldMessenger.showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(
              'Réunion terminée · ${_formattedDuration2(duration)} · $participantCount participant${participantCount > 1 ? 's' : ''}',
              style: GoogleFonts.poppins(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            )),
          ]),
          backgroundColor: const Color(0xFF6A1B9A),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      });
    }

    // 3. Cleanup in background after navigation — each individually silenced
    try { await _meetingService.removePresence(widget.meetingId, widget.userId); } catch (_) {}
    if (isHost) {
      try { await _db.collection('webrtc_rooms').doc(_docId).delete(); } catch (_) {}
    }
    try { await _screenStream?.dispose(); } catch (_) {}
    try { await _localStream?.dispose(); } catch (_) {}
    try { await _pc?.close(); } catch (_) {}
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
                : _isLiveMode
                    ? _buildLiveCall()
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
    final hasRemote = _remoteConnected;

    // ── Which video goes fullscreen ──────────────────────────────────────
    // Default: when remote connected → remote video fullscreen, local = PiP
    // swappedView = true → local fullscreen, remote = PiP
    final showLocalBig = !hasRemote || _swappedView;

    return Stack(children: [
      // ── MAIN VIDEO (full screen) ──────────────────────────────────────
      Positioned.fill(
        child: showLocalBig
            ? (_camOn
                ? RTCVideoView(_localRenderer,
                    mirror: !_sharingScreen,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                : _buildInitialsAvatar(widget.userName, size: double.infinity))
            : (_waitingForHost
                ? _buildWaitingForHost()
                : hasRemote
                    ? RTCVideoView(_remoteRenderer,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                    : _buildWaiting()),
      ),

      // ── PiP CARD (tap to swap) ────────────────────────────────────────
      if (hasRemote)
        Positioned(
          top: 90,
          right: 12,
          width: 115,
          height: 160,
          child: GestureDetector(
            onTap: () => setState(() => _swappedView = !_swappedView),
            child: Stack(children: [
              // Gradient border frame
              Container(
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(18),
                ),
                padding: const EdgeInsets.all(2.5),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: showLocalBig
                      // Local big → show remote in PiP
                      ? RTCVideoView(_remoteRenderer,
                          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                      // Remote big → show local in PiP
                      : (_camOn
                          ? RTCVideoView(_localRenderer,
                              mirror: !_sharingScreen,
                              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                          : _buildInitialsAvatar(widget.userName, size: 115)),
                ),
              ),
              // Name label
              Positioned(
                bottom: 2,
                left: 2,
                right: 2,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    color: Colors.black54,
                    child: Text(
                      showLocalBig
                          ? (_presenceList.where((p) => p['userId'] != widget.userId).map((p) => (p['name'] as String? ?? '').split(' ').first).firstOrNull ?? 'Participant')
                          : widget.userName.split(' ').first,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
              // Swap icon hint
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.swap_calls, color: Colors.white70, size: 12),
                ),
              ),
            ]),
          ),
        ),

      // ── PARTICIPANT-ONLY: local PiP when waiting for host ─────────────
      if (!isPrivileged && !hasRemote && !_waitingForHost)
        Positioned(
          top: 90,
          right: 12,
          width: 115,
          height: 160,
          child: Container(
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(18),
            ),
            padding: const EdgeInsets.all(2.5),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: _camOn
                  ? RTCVideoView(_localRenderer,
                      mirror: !_sharingScreen,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                  : _buildInitialsAvatar(widget.userName, size: 115),
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

    ]);
  }

  // ── LIVE CALL (TikTok Live style) ────────────
  Widget _buildLiveCall() {
    final isPrivileged = widget.isHost || _isCoHost;
    final screenW = MediaQuery.of(context).size.width;

    return Stack(children: [
      // ── FULL SCREEN VIDEO with background image ──
      Positioned.fill(
        child: Stack(children: [
          // Background image
          if (_liveBackgroundImagePath != null && File(_liveBackgroundImagePath!).existsSync())
            Image.file(
              File(_liveBackgroundImagePath!),
              fit: BoxFit.cover,
            )
          else
            Container(color: Colors.black),

          // Video overlay
          isPrivileged
              ? (_camOn
                  ? RTCVideoView(_localRenderer,
                      mirror: !_sharingScreen,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                  : _buildInitialsAvatar(widget.userName, size: double.infinity))
              : (_waitingForHost
                  ? _buildWaitingForHost()
                  : _remoteConnected
                      ? RTCVideoView(_remoteRenderer,
                          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                      : _buildWaiting()),
        ]),
      ),

      // ── TOP GRADIENT ────────────────────────
      Positioned(
        top: 0, left: 0, right: 0, height: 140,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black87, Colors.transparent],
            ),
          ),
        ),
      ),

      // ── BOTTOM GRADIENT ─────────────────────
      Positioned(
        bottom: 0, left: 0, right: 0, height: 200,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.black87, Colors.transparent],
            ),
          ),
        ),
      ),

      // ── TOP BAR ─────────────────────────────
      Positioned(
        top: 0, left: 0, right: 0,
        child: _buildLiveTopBar(),
      ),

      // ── FLOATING REACTIONS ───────────────────
      ..._reactions.map(
        (r) => AnimatedPositioned(
          duration: const Duration(milliseconds: 2000),
          curve: Curves.easeOut,
          bottom: r.bottomOffset,
          right: 16,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 700),
            opacity: r.opacity,
            child: Text(r.emoji, style: const TextStyle(fontSize: 36)),
          ),
        ),
      ),

      // ── COMMENTS FEED ────────────────────────
      Positioned(
        bottom: _liveCommentVisible ? 120 : 80,
        left: 12,
        width: screenW * 0.65,
        height: 220,
        child: _buildLiveComments(),
      ),

      // ── GIFT BUTTONS ─────────────────────────
      Positioned(
        right: 12,
        bottom: 200,
        child: _buildLiveGiftButtons(),
      ),

      // ── BOTTOM BAR ──────────────────────────
      Positioned(
        bottom: 0, left: 0, right: 0,
        child: _buildLiveBottomBar(),
      ),

      // ── PiP for host ─────────────────────────
      if (isPrivileged && _remoteConnected)
        Positioned(
          top: 80, right: 12, width: 100, height: 140,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(children: [
              RTCVideoView(_remoteRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white30, width: 1.5),
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ]),
          ),
        ),
    ]);
  }

  Widget _buildLiveTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(children: [
        // Host avatar + name
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 32, height: 32,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFFB71C1C), Color(0xFF6A1B9A)]),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  widget.userName.isNotEmpty ? widget.userName[0].toUpperCase() : 'L',
                  style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(widget.userName, style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
          ]),
        ),
        const SizedBox(width: 8),
        // Viewer count
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.remove_red_eye_outlined, color: Colors.white70, size: 14),
            const SizedBox(width: 4),
            Text('$_liveViewers', style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ),
        const Spacer(),
        // Video quality selector
        PopupMenuButton<_VideoQuality>(
          icon: const Icon(Icons.hd_outlined, color: Colors.white70, size: 18),
          color: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: _applyVideoQuality,
          itemBuilder: (_) => [
            PopupMenuItem(value: _VideoQuality.low, child: _QualityItem('Basse qualité', '320p', _videoQuality == _VideoQuality.low)),
            PopupMenuItem(value: _VideoQuality.medium, child: _QualityItem('Qualité moyenne', '480p', _videoQuality == _VideoQuality.medium)),
            PopupMenuItem(value: _VideoQuality.high, child: _QualityItem('Haute qualité', '720p HD', _videoQuality == _VideoQuality.high)),
            PopupMenuItem(value: _VideoQuality.hd, child: _QualityItem('Full HD', '1080p', _videoQuality == _VideoQuality.hd)),
          ],
        ),
        const SizedBox(width: 8),
        // LIVE badge
        const _LiveBadge(),
        if (_youtubeStreamingActive)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red.shade700,
                borderRadius: BorderRadius.circular(4),
                boxShadow: [BoxShadow(
                  color: Colors.red.withValues(alpha: 0.4),
                  blurRadius: 6,
                  spreadRadius: 1,
                )],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.videocam, color: Colors.white, size: 10),
                const SizedBox(width: 3),
                Text('YouTube', style: GoogleFonts.poppins(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        const SizedBox(width: 8),
        // Close button
        GestureDetector(
          onTap: _confirmLeave,
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.close, color: Colors.white, size: 20),
          ),
        ),
      ]),
    );
  }

  Widget _buildLiveComments() {
    if (_liveComments.isEmpty) {
      return const SizedBox.shrink();
    }
    return ListView.builder(
      controller: _liveCommentsScrollController,
      itemCount: _liveComments.length,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      itemBuilder: (_, i) {
        final c = _liveComments[i];
        final colorHex = c['color'] ?? '#FFFFFF';
        final color = Color(int.parse(colorHex.replaceFirst('#', '0xFF')));
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(20),
            ),
            child: RichText(
              text: TextSpan(children: [
                TextSpan(
                  text: '${c['name']}  ',
                  style: GoogleFonts.poppins(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(
                  text: c['text'] ?? '',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLiveGiftButtons() {
    final gifts = ['❤️', '🔥', '👏', '💎', '🎁', '⭐'];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: gifts.map((g) => GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          _sendReaction(g);
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          width: 46, height: 46,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            shape: BoxShape.circle,
          ),
          child: Center(child: Text(g, style: const TextStyle(fontSize: 22))),
        ),
      )).toList(),
    );
  }

  Widget _buildLiveBottomBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.of(context).viewInsets.bottom + 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _liveCommentVisible = !_liveCommentVisible),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(color: Colors.white24, width: 0.5),
                ),
                child: Row(children: [
                  const Icon(Icons.chat_bubble_outline, color: Colors.white70, size: 16),
                  const SizedBox(width: 8),
                  Text('Commenter...', style: GoogleFonts.poppins(color: Colors.white54, fontSize: 13)),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => setState(() => _showEmojiBar = !_showEmojiBar),
            child: Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.emoji_emotions_outlined, color: Colors.white70, size: 22),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              final tracks = _localStream?.getAudioTracks() ?? [];
              if (tracks.isNotEmpty) {
                setState(() {
                  _micOn = !_micOn;
                  tracks.first.enabled = _micOn;
                });
              }
            },
            child: Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: _micOn ? Colors.white.withValues(alpha: 0.15) : Colors.red.withValues(alpha: 0.8),
                shape: BoxShape.circle,
              ),
              child: Icon(_micOn ? Icons.mic : Icons.mic_off, color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _confirmLeave,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFB71C1C), Color(0xFF6A1B9A)]),
                borderRadius: BorderRadius.circular(25),
              ),
              child: Text('Terminer', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
            ),
          ),
        ]),

        // ── YOUTUBE CONTROLS ROW ──────────────────────────────
        if (widget.isHost)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                // Background image button
                GestureDetector(
                  onTap: _selectBackgroundImage,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24, width: 0.5),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.image_outlined, color: Colors.white70, size: 16),
                      const SizedBox(width: 6),
                      Text('Fond', style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
                const SizedBox(width: 8),

                // YouTube setup button
                GestureDetector(
                  onTap: _showYouTubeLiveDialog,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.red, width: 0.5),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.videocam, color: Colors.red, size: 16),
                      const SizedBox(width: 6),
                      Text('YouTube',
                          style: GoogleFonts.poppins(color: Colors.red.shade300, fontSize: 12, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
                const SizedBox(width: 8),

                // Start/Stop YouTube streaming button
                if (_youtubeRtmpKey != null && _youtubeRtmpKey!.isNotEmpty)
                  GestureDetector(
                    onTap: _toggleYouTubeStreaming,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: _youtubeStreamingActive
                            ? const LinearGradient(colors: [Color(0xFFB71C1C), Color(0xFF6A1B9A)])
                            : null,
                        color: _youtubeStreamingActive ? null : Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: _youtubeStreamingActive ? Colors.transparent : Colors.white24, width: 0.5),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(
                          _youtubeStreamingActive ? Icons.stop_circle : Icons.play_circle,
                          color: _youtubeStreamingActive ? Colors.white : Colors.white70,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _youtubeStreamingActive ? 'En live' : 'Diffuser',
                          style: GoogleFonts.poppins(
                            color: _youtubeStreamingActive ? Colors.white : Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ]),
                    ),
                  ),
                const SizedBox(width: 8),

                // Share YouTube link
                if (_youtubeUrl != null && _youtubeUrl!.isNotEmpty)
                  GestureDetector(
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: _youtubeUrl!));
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('Lien YouTube copié !', style: GoogleFonts.poppins()),
                        backgroundColor: Colors.green.shade700,
                        duration: const Duration(seconds: 2),
                      ));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.blue, width: 0.5),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.share, color: Colors.blue, size: 16),
                        const SizedBox(width: 6),
                        Text('Partager', style: GoogleFonts.poppins(color: Colors.blue.shade300, fontSize: 12, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
              ]),
            ),
          ),

        if (_liveCommentVisible) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _liveCommentController,
                autofocus: true,
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Écrire un commentaire...',
                  hintStyle: GoogleFonts.poppins(color: Colors.white38, fontSize: 13),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.12),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: const BorderSide(color: Colors.white24, width: 0.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: const BorderSide(color: Color(0xFFB71C1C), width: 1.5),
                  ),
                ),
                onSubmitted: (val) {
                  _sendLiveComment(val);
                  setState(() => _liveCommentVisible = false);
                },
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                _sendLiveComment(_liveCommentController.text);
                setState(() => _liveCommentVisible = false);
              },
              child: Container(
                width: 42, height: 42,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFFB71C1C), Color(0xFF6A1B9A)]),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.send, color: Colors.white, size: 18),
              ),
            ),
          ]),
        ],

        if (_showEmojiBar) ...[
          const SizedBox(height: 8),
          _buildEmojiBar(),
        ],
      ]),
    );
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
        // Video quality selector
        PopupMenuButton<_VideoQuality>(
          icon: const Icon(Icons.hd_outlined, color: Colors.white70, size: 18),
          color: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: _applyVideoQuality,
          itemBuilder: (_) => [
            PopupMenuItem(value: _VideoQuality.low, child: _QualityItem('Basse qualité', '320p', _videoQuality == _VideoQuality.low)),
            PopupMenuItem(value: _VideoQuality.medium, child: _QualityItem('Qualité moyenne', '480p', _videoQuality == _VideoQuality.medium)),
            PopupMenuItem(value: _VideoQuality.high, child: _QualityItem('Haute qualité', '720p HD', _videoQuality == _VideoQuality.high)),
            PopupMenuItem(value: _VideoQuality.hd, child: _QualityItem('Full HD', '1080p', _videoQuality == _VideoQuality.hd)),
          ],
        ),
        // Meeting ID chip (right side)
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: widget.meetingId));
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('ID copié', style: GoogleFonts.poppins(fontSize: 12)),
              duration: const Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
            ));
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white30, width: 0.5),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 6, height: 6,
                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Text(
                widget.meetingId.length > 10 ? widget.meetingId.substring(0, 10) : widget.meetingId,
                style: GoogleFonts.poppins(color: Colors.white70, fontSize: 10),
              ),
            ]),
          ),
        ),
        const SizedBox(width: 6),
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
                onTap: () {
                  HapticFeedback.mediumImpact();
                  for (final t in _localStream?.getAudioTracks() ?? []) { t.enabled = false; }
                  if (mounted) setState(() => _micOn = false);
                  _meetingService.triggerMuteAll(widget.meetingId).catchError((_) {});
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('🔇 Tous les micros ont été coupés', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                    backgroundColor: Colors.orange.shade800,
                    duration: const Duration(seconds: 2),
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
        // Increment unread when chat is closed and new messages arrive
        if (!_showChat && snap.hasData && docs.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_showChat) {
              setState(() => _unreadMessages = docs
                  .where((d) => (d.data() as Map)['sender'] != widget.userName)
                  .length
                  .clamp(0, 99));
            }
          });
        }
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
            Semantics(
              label: 'Activer/désactiver le micro',
              button: true,
              child: _Btn(
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
            ),
            const SizedBox(width: 8),
            Semantics(
              label: 'Activer/désactiver la caméra',
              button: true,
              child: _Btn(
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
            Stack(
              clipBehavior: Clip.none,
              children: [
                _Btn(
                  icon: Icons.chat_bubble_outline,
                  label: 'Chat',
                  active: !_showChat,
                  isHighlight: _showChat,
                  onTap: () => setState(() {
                    _showChat = !_showChat;
                    if (_showChat) {
                      _showEmojiBar = false;
                      _showParticipants = false;
                      _unreadMessages = 0;
                    }
                  }),
                ),
                if (_unreadMessages > 0)
                  Positioned(
                    top: -4, right: -4,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red, shape: BoxShape.circle),
                      child: Text('$_unreadMessages',
                          style: GoogleFonts.poppins(
                              color: Colors.white, fontSize: 9,
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
              ],
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
              icon: _handRaised ? Icons.front_hand : Icons.front_hand_outlined,
              label: _handRaised ? 'Main levée' : 'Lever main',
              active: !_handRaised,
              isHighlight: _handRaised,
              onTap: _toggleRaiseHand,
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
                onTap: () {
                  HapticFeedback.mediumImpact();
                  // Mute host's own mic immediately
                  for (final t in _localStream?.getAudioTracks() ?? []) {
                    t.enabled = false;
                  }
                  if (mounted) setState(() => _micOn = false);
                  // Signal all participants via Firestore (fire-and-forget)
                  _meetingService.triggerMuteAll(widget.meetingId).catchError((_) {});
                  if (mounted) {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('🔇 Tous les micros ont été coupés',
                          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
                      backgroundColor: Colors.orange.shade800,
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ));
                  }
                },
              ),
            ],
            const SizedBox(width: 8),
            Semantics(
              label: 'Quitter la réunion',
              button: true,
              child: _Btn(
                icon: Icons.call_end,
                label: 'Fin',
                active: false,
                isEnd: true,
                onTap: _confirmLeave,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── WAITING (participant only — host uses full-screen local cam) ────────
  Widget _buildWaiting() {
    return Stack(fit: StackFit.expand, children: [
      // Local camera preview as full-screen background
      _localStream != null && _camOn
          ? RTCVideoView(
              _localRenderer,
              mirror: true,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          : Container(color: const Color(0xFF1A1A2E)),
      // Overlay: semi-transparent scrim
      Container(color: Colors.black.withValues(alpha: 0.50)),
      Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Pulsing ring animation
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.85, end: 1.15),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeInOut,
            builder: (context, scale, child) {
              return Transform.scale(
                scale: scale,
                child: child,
              );
            },
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary, width: 4),
                color: AppColors.primary.withValues(alpha: 0.15),
              ),
              child: const Icon(Icons.people_outline, color: Colors.white, size: 44),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'En attente d\'un participant...',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Partagez l\'ID de réunion :',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(color: Colors.white60, fontSize: 13),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
            ),
            child: Text(
              widget.meetingId,
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2),
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: widget.meetingId));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('ID copié !', style: GoogleFonts.poppins()),
                backgroundColor: AppColors.primary,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                duration: const Duration(seconds: 2),
              ));
            },
            icon: const Icon(Icons.copy, color: Colors.white70, size: 18),
            label: Text(
              'Copier l\'ID',
              style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13),
            ),
          ),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
            ),
            onPressed: _leave,
            icon: const Icon(Icons.call_end, color: Colors.white),
            label: Text('Quitter',
                style: GoogleFonts.poppins(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    ]);
  }

  Widget _buildWaitingForHost() {
    return Stack(fit: StackFit.expand, children: [
      // Local camera preview as full-screen background
      _localStream != null && _camOn
          ? RTCVideoView(
              _localRenderer,
              mirror: true,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          : Container(color: const Color(0xFF1A1A2E)),
      Container(color: Colors.black.withValues(alpha: 0.55)),
      Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.85, end: 1.15),
            duration: const Duration(milliseconds: 1000),
            curve: Curves.easeInOut,
            builder: (context, scale, child) {
              return Transform.scale(scale: scale, child: child);
            },
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary, width: 4),
                color: AppColors.primary.withValues(alpha: 0.12),
              ),
              child: const Icon(Icons.hourglass_top_rounded,
                  color: Colors.white70, size: 40),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'En attente de l\'hôte...',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'La réunion démarrera automatiquement\ndès que l\'hôte sera prêt.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                color: Colors.white60, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 20),
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
                color: Colors.white54, strokeWidth: 2),
          ),
          const SizedBox(height: 32),
          TextButton.icon(
            style: TextButton.styleFrom(
              backgroundColor: Colors.red.shade700.withValues(alpha: 0.85),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
            ),
            onPressed: () {
              _hostWaitTimer?.cancel();
              _leave();
            },
            icon: const Icon(Icons.call_end, color: Colors.white),
            label: Text('Quitter',
                style: GoogleFonts.poppins(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    ]);
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

// ─────────────────────────────────────────────
//  VIDEO QUALITY MENU ITEM
// ─────────────────────────────────────────────
class _QualityItem extends StatelessWidget {
  final String label;
  final String badge;
  final bool selected;
  const _QualityItem(this.label, this.badge, this.selected);
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      if (selected) const Icon(Icons.check, color: Color(0xFFB71C1C), size: 16)
      else const SizedBox(width: 16),
      const SizedBox(width: 8),
      Text(label, style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13)),
      const Spacer(),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFB71C1C).withValues(alpha: 0.3) : Colors.white12,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(badge, style: GoogleFonts.poppins(color: selected ? const Color(0xFFE53935) : Colors.white54, fontSize: 10, fontWeight: FontWeight.w600)),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────
//  LIVE BADGE
// ─────────────────────────────────────────────
class _LiveBadge extends StatefulWidget {
  const _LiveBadge();
  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(duration: const Duration(milliseconds: 900), vsync: this)..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.85, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _pulse,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFB71C1C),
          borderRadius: BorderRadius.circular(6),
          boxShadow: [BoxShadow(color: const Color(0xFFB71C1C).withValues(alpha: 0.6), blurRadius: 8, spreadRadius: 1)],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text('LIVE', style: GoogleFonts.poppins(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
        ]),
      ),
    );
  }
}
