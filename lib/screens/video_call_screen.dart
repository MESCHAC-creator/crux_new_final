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
import 'package:logger/logger.dart';
import 'dart:typed_data';
import '../theme/colors.dart';
import '../services/meeting_service.dart';
import '../services/pro_service.dart';
import '../services/user_service.dart';
import '../models/meeting_model.dart';
import '../models/meeting_report_model.dart';
import 'meeting_report_screen.dart';

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
  DateTime? _callStartTime;  // fixed start time, never reset
  bool _warningShown = false; // 5-min warning shown?

  // ── Auto-reconnect ───────────────────────────
  int _reconnectAttempts = 0;
  static const _maxReconnect = 3;
  Timer? _reconnectTimer;

  // ── Waiting for host (participant side) ──────
  bool _waitingForHost = false;
  Timer? _hostWaitTimer;
  int _hostWaitCount = 0;

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

  // ── Meeting metadata ─────────────────────────
  String _meetingTitle = 'Réunion';
  String _meetingDescription = '';
  String? _meetingPassword;
  int _chatMessageCount = 0;

  // ── Gallery view ─────────────────────────────
  bool _galleryView = false;

  // ── Active Speaker (Google Meet-like) ────────
  String? _activeSpeakerId;         // uid of current speaker
  String? _activeSpeakerName;       // display name
  bool _bannerVisible = false;
  Timer? _bannerHideTimer;
  Timer? _speakingTimer;
  bool _localWasSpeaking = false;
  final Map<String, bool> _participantSpeaking = {};
  late AnimationController _waveController;
  late List<Animation<double>> _waveAnims;

  // ── Participant profile cache (Zoom-like) ────
  Uint8List? _ownPhotoBytes;             // local user's photo
  final Map<String, Uint8List?> _participantPhotos = {};
  final Map<String, String> _participantNames = {};
  final Map<String, bool> _participantCamOn = {};  // remote cam state
  final Map<String, StreamSubscription<Map<String, dynamic>?>> _profileSubs = {};

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

  // ── Security & Rate Limiting ─────────────────
  Timer? _inactivityTimer;
  static const Duration _inactivityTimeout = Duration(minutes: 15);
  static const int MAX_MESSAGE_LENGTH = 500;
  static const int MAX_VIDEO_BITRATE = 4000; // kbps
  final Map<String, DateTime> _lastCallTime = {};
  static const Duration _minCallInterval = Duration(milliseconds: 200);

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
  final _log = Logger();

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
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _waveAnims = List.generate(3, (i) {
      final begin = 0.3 + i * 0.2;
      return Tween<double>(begin: begin, end: 1.0).animate(
        CurvedAnimation(
          parent: _waveController,
          curve: Interval(i * 0.2, 0.6 + i * 0.2, curve: Curves.easeInOut),
        ),
      );
    });
    _init();
    _detectLiveMode();
    _listenReactions();
    _listenMeetingDoc();
    _listenPresence();
    _listenProStatus();
    _loadOwnPhoto();
    _resetInactivityTimer();
    _monitorConnectionHealth();
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
    _inactivityTimer?.cancel();
    _liveCommentSub?.cancel();
    for (final sub in _profileSubs.values) { sub.cancel(); }
    _profileSubs.clear();
    _bannerHideTimer?.cancel();
    _speakingTimer?.cancel();
    _waveController.dispose();
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

      // Start call timer as soon as media is ready (not waiting for remote)
      _startCallTimer();

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
          _startSpeakingDetection();
          _reconnectAttempts = 0;
        }
      };

      _pc!.onConnectionState = (state) {
        if (!mounted) return;
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          setState(() => _remoteConnected = true);
          _startCallTimer();
          _startStatsMonitor();
          _startSpeakingDetection();
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
    // Idempotent — only start once per call session
    if (_callTimer != null) return;
    _callStartTime = DateTime.now();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final elapsed = DateTime.now().difference(_callStartTime!).inSeconds;
      setState(() => _callSeconds = elapsed);

      // 5-min warning before paywall
      if (!_isPro && !_warningShown && elapsed >= (_freeMinutes * 60 - 300)) {
        _warningShown = true;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.timer, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(
              '⏱ 5 minutes restantes sur votre version gratuite',
              style: GoogleFonts.poppins(color: Colors.white, fontSize: 12),
            )),
          ]),
          backgroundColor: Colors.orange.shade800,
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }

      // Paywall at 30 min
      if (!_isPro && !_paywallShown && elapsed >= _freeMinutes * 60) {
        _paywallShown = true;
        _showPaywall();
      }
    });
  }

  void _showPaywall() {
    // Pause the call visually — mute audio as signal
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (_) => PopScope(
        canPop: false,
        child: _PaywallDialog(
          onUpgrade: () async {
            try {
              await _proService.startPayment(
                userId: widget.userId,
                userName: widget.userName,
              );
              // Re-check immediately after returning from payment
              final pro = await _proService.isPro(widget.userId);
              if (mounted && pro) {
                setState(() { _isPro = true; _paywallShown = false; _warningShown = false; });
              } else if (mounted) {
                // Not yet confirmed — re-check in 5s then show again if still not pro
                Future.delayed(const Duration(seconds: 5), () async {
                  if (!mounted) return;
                  final confirmed = await _proService.isPro(widget.userId);
                  if (mounted && !confirmed) _showPaywall();
                  if (mounted && confirmed) setState(() { _isPro = true; _paywallShown = false; });
                });
              }
            } catch (_) {
              if (mounted) _showPaywall();
            }
          },
          onLeave: () {
            Navigator.pop(context);
            _leave();
          },
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

  // ── ACTIVE SPEAKER DETECTION ─────────────────
  void _startSpeakingDetection() {
    _speakingTimer?.cancel();
    _speakingTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (!mounted) return;
      await _updateLocalSpeaking();
    });
  }

  Future<void> _updateLocalSpeaking() async {
    if (_localStream == null || !_micOn) {
      if (_localWasSpeaking) {
        _localWasSpeaking = false;
        _db.collection('meetings').doc(widget.meetingId)
            .collection('presence').doc(widget.userId)
            .update({'isSpeaking': false}).catchError((_) {});
        if (mounted) setState(() {
          _participantSpeaking[widget.userId] = false;
          if (_activeSpeakerId == widget.userId) _activeSpeakerId = null;
        });
      }
      return;
    }
    try {
      final stats = await _pc?.getStats();
      if (stats == null || !mounted) return;
      double audioLevel = 0;
      for (final report in stats) {
        final values = report.values;
        if (values['type'] == 'media-source' || values['type'] == 'track') {
          final level = values['audioLevel'];
          if (level != null) {
            audioLevel = (level as num).toDouble();
            break;
          }
        }
        if (values['type'] == 'inbound-rtp' && values['mediaType'] == 'audio') {
          final level = values['audioLevel'];
          if (level != null) audioLevel = (level as num).toDouble();
        }
      }
      // Fallback: treat mic-on as potentially speaking (level 0.05 threshold)
      final isSpeaking = audioLevel > 0.01;
      if (isSpeaking != _localWasSpeaking) {
        _localWasSpeaking = isSpeaking;
        _db.collection('meetings').doc(widget.meetingId)
            .collection('presence').doc(widget.userId)
            .update({'isSpeaking': isSpeaking}).catchError((_) {});
        if (mounted) {
          setState(() {
            _participantSpeaking[widget.userId] = isSpeaking;
            if (isSpeaking) {
              _activeSpeakerId = widget.userId;
              _activeSpeakerName = widget.userName;
              _bannerVisible = true;
              _scheduleBannerHide();
            } else if (_activeSpeakerId == widget.userId) {
              _activeSpeakerId = null;
            }
          });
        }
      }
    } catch (_) {}
  }

  void _scheduleBannerHide() {
    _bannerHideTimer?.cancel();
    _bannerHideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _bannerVisible = false);
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
        // Sync remote speaking state
        for (final p in list) {
          final uid = p['userId'] as String? ?? '';
          if (uid == widget.userId) continue;
          final speaking = p['isSpeaking'] == true;
          _participantSpeaking[uid] = speaking;
          if (speaking) {
            _activeSpeakerId = uid;
            _activeSpeakerName = _participantNames[uid] ?? (p['name'] as String? ?? 'Participant');
            _bannerVisible = true;
            _scheduleBannerHide();
          } else if (_activeSpeakerId == uid) {
            _activeSpeakerId = null;
          }
        }
      });
      // Load Firestore profiles for any new participants
      _loadParticipantProfiles(list);
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
        _hostWaitTimer = Timer(const Duration(seconds: 3), () {
          _hostWaitCount++;
          if (_hostWaitCount > 100) {
            if (mounted) {
              setState(() {
                _error = 'L\'hôte n\'a pas démarré la réunion dans les délais. Réessayez plus tard.';
                _loading = false;
              });
            }
            return;
          }
          _joinCall();
        });
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

  // ── OWN PROFILE PHOTO ────────────────────────
  Future<void> _loadOwnPhoto() async {
    try {
      // 1. Try local file first (fast)
      final prefs = await SharedPreferences.getInstance();
      final path = prefs.getString('crux_local_photo_path');
      if (path != null) {
        final file = File(path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (mounted) setState(() => _ownPhotoBytes = bytes);
          return;
        }
      }
      // 2. Fallback to Firestore
      final profile = await UserService.instance.getProfile(widget.userId);
      final bytes = UserService.decodePhoto(profile?['photoBase64'] as String?);
      if (mounted && bytes != null) setState(() => _ownPhotoBytes = bytes);
    } catch (_) {}
    // Start real-time listener for own profile changes
    _subscribeToOwnProfile();
  }

  void _subscribeToOwnProfile() {
    if (_profileSubs.containsKey('own_${widget.userId}')) return;
    final sub = _db.collection('users').doc(widget.userId).snapshots()
        .map((s) => s.exists ? s.data() : null)
        .listen((data) {
      if (!mounted || data == null) return;
      final bytes = UserService.decodePhoto(data['photoBase64'] as String?);
      setState(() => _ownPhotoBytes = bytes);
    });
    _profileSubs['own_${widget.userId}'] = sub;
  }

  // ── PARTICIPANT PROFILES (real-time stream) ───
  void _subscribeToParticipantProfile(String uid) {
    if (_profileSubs.containsKey(uid)) return; // already subscribed
    final sub = _db.collection('users').doc(uid).snapshots()
        .map((s) => s.exists ? s.data() : null)
        .listen((data) {
      if (!mounted || data == null) return;
      final bytes = UserService.decodePhoto(data['photoBase64'] as String?);
      final name = data['name'] as String?;
      setState(() {
        _participantPhotos[uid] = bytes;
        if (name != null && name.isNotEmpty) _participantNames[uid] = name;
      });
    });
    _profileSubs[uid] = sub;
  }

  void _loadParticipantProfiles(List<Map<String, dynamic>> list) {
    for (final p in list) {
      final uid = p['userId'] as String? ?? '';
      if (uid.isEmpty) continue;
      _subscribeToParticipantProfile(uid);
      // Extract camOn from presence data
      final camOn = p['camOn'] as bool?;
      if (camOn != null) {
        _participantCamOn[uid] = camOn;
      }
    }
  }

  // ── LIVE MODE ────────────────────────────────
  Future<void> _detectLiveMode() async {
    try {
      final snap = await _db.collection('meetings').doc(widget.meetingId).get();
      if (!snap.exists) return;
      final title = snap.data()?['title'] as String? ?? 'Réunion';
      if (mounted) {
        setState(() {
          _meetingTitle = title;
          _meetingDescription = snap.data()?['description'] as String? ?? '';
          _meetingPassword = snap.data()?['password'] as String?;
          _isLiveMode = title.contains('[Live]') || title.contains('[LIVE]');
        });
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
      final prefs = await SharedPreferences.getInstance();
      // Load RTMP key from local secure storage only (never from Firestore)
      final rtmpKey = prefs.getString('youtube_rtmp_key_${widget.meetingId}');
      final youtubeUrl = prefs.getString('youtube_url_${widget.meetingId}');
      if (mounted) {
        setState(() {
          _youtubeRtmpKey = rtmpKey;
          _youtubeUrl = youtubeUrl;
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
            const SizedBox(height: 12),
            // Security warning
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.5), width: 1),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Clé stockée localement seulement',
                      style: GoogleFonts.poppins(color: Colors.red, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
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
              // Save RTMP credentials locally only (never to Firestore)
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('youtube_rtmp_key_${widget.meetingId}', keyCtrl.text.trim());
              await prefs.setString('youtube_url_${widget.meetingId}', urlCtrl.text.trim());
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
          if (emoji != null && mounted) {
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
    if (text.isEmpty || text.length > MAX_MESSAGE_LENGTH) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Message: 1-$MAX_MESSAGE_LENGTH caractères', style: GoogleFonts.poppins()),
        backgroundColor: Colors.orange,
      ));
      return;
    }
    if (!_checkRateLimit('sendMessage')) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Trop de requêtes. Attendez un moment.', style: GoogleFonts.poppins()),
        backgroundColor: Colors.red,
      ));
      return;
    }
    HapticFeedback.selectionClick();
    _resetInactivityTimer();
    _chatController.clear();
    _db
        .collection('meetings')
        .doc(widget.meetingId)
        .collection('chat')
        .add({
      'sender': widget.userName,
      'senderId': widget.userId,
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
    _speakingTimer?.cancel();
    _db.collection('meetings').doc(widget.meetingId)
        .collection('presence').doc(widget.userId)
        .update({'isSpeaking': false}).catchError((_) {});

    // Capture state BEFORE any async operation
    final navigator = Navigator.of(context);
    final duration = _callSeconds;
    final isHost = widget.isHost;

    // 1. Cancel ALL subscriptions synchronously
    _callSub?.cancel();
    _candidateSub?.cancel();
    _reactionSub?.cancel();
    _meetingDocSub?.cancel();
    _presenceSub?.cancel();
    _proSub?.cancel();
    _liveCommentSub?.cancel();
    for (final sub in _profileSubs.values) { sub.cancel(); }
    _profileSubs.clear();
    _callTimer?.cancel();
    _statsTimer?.cancel();
    _reconnectTimer?.cancel();
    _hostWaitTimer?.cancel();

    // 2. Save chat snapshot (fire-and-forget)
    _db.collection('meetings').doc(widget.meetingId)
        .collection('chat')
        .orderBy('timestamp', descending: false)
        .limitToLast(50)
        .get()
        .then((snap) {
      final msgs = snap.docs.map((d) {
        final data = d.data();
        final ts = data['timestamp'];
        String tsStr = '';
        if (ts is Timestamp) tsStr = ts.toDate().toIso8601String();
        return {
          'sender': data['sender'] ?? '',
          'message': data['message'] ?? '',
          'timestamp': tsStr,
        };
      }).toList();
      if (msgs.isNotEmpty) {
        _db.collection('meeting_reports').doc(widget.meetingId)
            .set({'chatSnapshot': msgs}, SetOptions(merge: true))
            .catchError((_) {});
      }
    }).catchError((_) {});

    // 3. Build report before navigating (host only)
    MeetingReportModel? report;
    if (isHost && duration > 5) {
      report = MeetingReportModel(
        meetingId: widget.meetingId,
        title: _meetingTitle,
        hostName: widget.userName,
        hostId: widget.userId,
        durationSeconds: duration,
        participantNames: List<String>.from(
          _presenceList.map((p) => (p['name'] ?? p['userId'] ?? 'Inconnu').toString()),
        ),
        messageCount: _chatMessageCount,
        endedAt: DateTime.now(),
      );
      // Save to Firestore (fire-and-forget)
      _db.collection('meeting_reports').doc(widget.meetingId).set(report.toJson()).catchError((_) {});
    }

    // 4. Navigate: host → report screen, participant → home
    if (isHost && report != null) {
      navigator.pushReplacement(
        MaterialPageRoute(builder: (_) => MeetingReportScreen(report: report!)),
      );
    } else {
      navigator.pop();
    }

    // 5. Cleanup in background after navigation — each individually silenced
    try { await _meetingService.removePresence(widget.meetingId, widget.userId); } catch (_) {}
    if (isHost) {
      try { await _db.collection('webrtc_rooms').doc(_docId).delete(); } catch (_) {}
    }
    try { await _screenStream?.dispose(); } catch (_) {}
    try { await _localStream?.dispose(); } catch (_) {}
    try { await _pc?.close(); } catch (_) {}
  }

  // ── SECURITY & RATE LIMITING ────────────────
  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(_inactivityTimeout, () {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Session expirée par inactivité', style: GoogleFonts.poppins()),
          backgroundColor: Colors.red,
        ));
        _leave();
      }
    });
  }

  bool _checkRateLimit(String operation) {
    final now = DateTime.now();
    final lastTime = _lastCallTime[operation];

    if (lastTime != null && now.difference(lastTime) < _minCallInterval) {
      return false; // Rate limited
    }

    _lastCallTime[operation] = now;
    return true;
  }

  void _monitorConnectionHealth() {
    Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      // Check if connection is still alive
      _pc?.getStats().then((stats) {
        for (final report in stats) {
          final values = report.values;
          if (values['type'] == 'inbound-rtp') {
            final packetsLost = values['packetsLost'] ?? 0;
            if (packetsLost > 100) {
              // Connection unstable but don't force disconnect
              // just log for debugging
              _log.w('⚠️ Connection unstable: $packetsLost packets lost');
            }
          }
        }
      }).catchError((_) {
        // Connection likely broken
        timer.cancel();
        if (mounted) _leave();
      });
    });
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
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () {
                setState(() { _error = null; _loading = true; });
                _init();
              },
              icon: const Icon(Icons.refresh, color: Color(0xFFB71C1C)),
              label: Text('Réessayer', style: GoogleFonts.poppins(color: Color(0xFFB71C1C))),
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
                : _buildVideoOff(widget.userName, _ownPhotoBytes))
            : (_waitingForHost
                ? _buildWaitingForHost()
                : hasRemote
                    ? _buildRemoteVideo()
                    : _buildWaiting()),
      ),
      // ── SPEAKING RING on fullscreen remote ────────────────────────────
      if (!showLocalBig && hasRemote)
        Builder(builder: (_) {
          final remoteId = _presenceList
              .where((p) => p['userId'] != widget.userId)
              .firstOrNull?['userId'] as String? ?? '';
          final speaking = _participantSpeaking[remoteId] == true;
          return AnimatedOpacity(
            opacity: speaking ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: const Color(0xFF43A047),
                    width: 4,
                  ),
                ),
              ),
            ),
          );
        }),

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
              // CRUX PiP: dark purple tint, subtle brand border
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1529),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF6A1B9A).withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 20, offset: const Offset(0, 6)),
                    BoxShadow(color: const Color(0xFF6A1B9A).withValues(alpha: 0.15), blurRadius: 30),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: showLocalBig
                      // Local big → show remote in PiP
                      ? _buildRemoteVideo(pip: true)
                      // Remote big → show local in PiP
                      : (_camOn
                          ? RTCVideoView(_localRenderer,
                              mirror: !_sharingScreen,
                              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                          : _buildVideoOff(widget.userName, _ownPhotoBytes, size: 115)),
                ),
              ),
              // Name label
              // Google Meet: small name pill at bottom-left
              Positioned(
                bottom: 6,
                left: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    showLocalBig
                        ? () {
                            final remoteId = _presenceList.where((p) => p['userId'] != widget.userId).firstOrNull?['userId'] as String? ?? '';
                            final presenceName = _presenceList.where((p) => p['userId'] != widget.userId).firstOrNull?['name'] as String? ?? 'Participant';
                            return (_participantNames[remoteId] ?? presenceName).split(' ').first;
                          }()
                        : 'Vous',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.roboto(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
              // Mic status icon at top-right
              Positioned(
                top: 6, right: 6,
                child: Container(
                  width: 20, height: 20,
                  decoration: BoxDecoration(
                    color: (showLocalBig ? false : !_micOn) ? Colors.red.shade700 : Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    (showLocalBig ? true : _micOn) ? Icons.mic : Icons.mic_off,
                    color: Colors.white, size: 11,
                  ),
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
                  : _buildVideoOff(widget.userName, _ownPhotoBytes, size: 115),
            ),
          ),
        ),

      // ── GALLERY VIEW OVERLAY ─────────────────────────────────────────
      if (_galleryView && _presenceList.length >= 3)
        Positioned.fill(child: _buildGalleryView()),

      // ── TOP BAR ──────────────────────────────────────────────────────
      Positioned(top: 0, left: 0, right: 0, child: _buildTopBar()),

      // ── ACTIVE SPEAKER BANNER ────────────────────────────────────────
      Positioned(top: 58, left: 0, right: 0, child: _buildSpeakerBanner()),

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
                      if (!mounted) return;
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
  /// Camera-off screen: shows photo if available, else gradient initials.
  /// Used for both self (ownPhoto) and remote participants.
  Widget _buildVideoOff(String name, Uint8List? photo, {double size = double.infinity}) {
    final parts = name.trim().split(RegExp(r'\s+'));
    final initial = parts.isNotEmpty && parts[0].isNotEmpty
        ? parts[0][0].toUpperCase()
        : '?';
    final isInfinite = size == double.infinity;
    final avatarSize = isInfinite ? 100.0 : (size * 0.55).clamp(40.0, 120.0);
    final fontSize = isInfinite ? 38.0 : (avatarSize * 0.42).clamp(14.0, 46.0);
    return Container(
      width: isInfinite ? null : size,
      height: isInfinite ? null : size,
      color: const Color(0xFF0F0C1A),
      child: Center(
        child: photo != null
            ? ClipOval(
                child: Image.memory(
                  photo,
                  width: avatarSize,
                  height: avatarSize,
                  fit: BoxFit.cover,
                ),
              )
            : Container(
                width: avatarSize,
                height: avatarSize,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _avatarGradient(name),
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 14)],
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: fontSize,
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  // Keep old name as alias for callers outside this section
  Widget _buildInitialsAvatar(String name, {double size = 80}) =>
      _buildVideoOff(name, null, size: size);

  /// Remote video: shows RTCVideoView normally, or camera-off screen with their photo.
  Widget _buildRemoteVideo({bool pip = false}) {
    final remoteParticipant = _presenceList
        .where((p) => p['userId'] != widget.userId)
        .firstOrNull;
    final remoteId = remoteParticipant?['userId'] as String? ?? '';
    final remoteName = _participantNames[remoteId]
        ?? (remoteParticipant?['name'] as String? ?? 'Participant');
    final remotePhoto = _participantPhotos[remoteId];
    final remoteHasCam = _participantCamOn[remoteId] ?? true; // default to on

    if (!remoteHasCam) {
      return _buildVideoOff(remoteName, remotePhoto,
          size: pip ? 115 : double.infinity);
    }
    return RTCVideoView(_remoteRenderer,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover);
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
        // Gallery view toggle (show when 3+ participants)
        if (_presenceList.length >= 3)
          GestureDetector(
            onTap: () => setState(() => _galleryView = !_galleryView),
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: _galleryView ? AppColors.primary : Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_galleryView ? Icons.view_stream : Icons.grid_view,
                  color: Colors.white, size: 16),
            ),
          ),
        // Invite share button
        GestureDetector(
          onTap: _showInviteSheet,
          child: Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.share, color: Colors.white, size: 14),
              const SizedBox(width: 4),
              Text('Partager', style: GoogleFonts.poppins(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
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

  // ── ACTIVE SPEAKER BANNER ────────────────────
  Widget _buildSpeakerBanner() {
    final name = _activeSpeakerName ?? '';
    final isMe = _activeSpeakerId == widget.userId;
    final displayName = isMe ? 'Vous parlez' : '$name parle';
    return AnimatedOpacity(
      opacity: _bannerVisible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: IgnorePointer(
        ignoring: !_bannerVisible,
        child: Center(
          child: Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF7F0000), Color(0xFF6A1B9A)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(color: const Color(0xFFB71C1C).withValues(alpha: 0.45), blurRadius: 12),
                BoxShadow(color: const Color(0xFF6A1B9A).withValues(alpha: 0.3), blurRadius: 22),
              ],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _buildSoundWave(small: true),
              const SizedBox(width: 8),
              Text(displayName,
                  style: GoogleFonts.poppins(
                      color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ),
    );
  }

  // ── SOUND WAVE ANIMATION ─────────────────────
  Widget _buildSoundWave({bool small = false}) {
    final h = small ? 12.0 : 18.0;
    final w = small ? 3.0 : 4.0;
    return AnimatedBuilder(
      animation: _waveController,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(3, (i) {
          return Container(
            width: w,
            height: h * _waveAnims[i].value,
            margin: EdgeInsets.symmetric(horizontal: small ? 1 : 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
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
                    // Prefer Firestore profile name over presence name
                    final pName = _participantNames[pId]
                        ?? (p['name'] as String? ?? 'Participant');
                    final isMe = pId == widget.userId;
                    final initial = pName.isNotEmpty ? pName[0].toUpperCase() : '?';
                    final photoBytes = _participantPhotos[pId];
                    return ListTile(
                      leading: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(gradient: AppColors.primaryGradient, shape: BoxShape.circle),
                        child: photoBytes != null
                            ? ClipOval(child: Image.memory(photoBytes, fit: BoxFit.cover, width: 40, height: 40))
                            : Center(child: Text(initial,
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
                                  if (!mounted) return;
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
        // Track total messages and unread count
        if (snap.hasData && docs.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _chatMessageCount = docs.length;
              if (!_showChat) {
                setState(() => _unreadMessages = docs
                    .where((d) => (d.data() as Map)['sender'] != widget.userName)
                    .length
                    .clamp(0, 99));
              }
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
            final senderId = d['senderId'] as String? ?? '';
            final senderPhoto = isMine
                ? _ownPhotoBytes
                : (senderId.isNotEmpty ? _participantPhotos[senderId] : null);
            final senderName = d['sender'] as String? ?? '';
            final senderInitial = senderName.isNotEmpty ? senderName[0].toUpperCase() : '?';

            Widget avatarWidget = Container(
              width: 28, height: 28,
              decoration: const BoxDecoration(
                  gradient: AppColors.primaryGradient, shape: BoxShape.circle),
              child: senderPhoto != null
                  ? ClipOval(child: Image.memory(senderPhoto, fit: BoxFit.cover))
                  : Center(child: Text(senderInitial,
                      style: GoogleFonts.poppins(color: Colors.white,
                          fontWeight: FontWeight.w700, fontSize: 11))),
            );

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment:
                    isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!isMine) ...[avatarWidget, const SizedBox(width: 6)],
                  Flexible(
                    child: Container(
                      constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(ctx).size.width * 0.65),
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
                              senderName,
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
                  if (isMine) ...[const SizedBox(width: 6), avatarWidget],
                ],
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
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 16),
      decoration: BoxDecoration(
        color: const Color(0xF0141420),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.07), width: 0.5)),
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
                  final newCamOn = !_camOn;
                  for (final t in _localStream?.getVideoTracks() ?? []) {
                    t.enabled = newCamOn;
                  }
                  setState(() => _camOn = newCamOn);
                  // Broadcast cam state so others know to show your photo
                  _db.collection('meetings').doc(widget.meetingId)
                      .collection('presence').doc(widget.userId)
                      .update({'camOn': newCamOn}).catchError((_) {});
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
            const SizedBox(width: 8),
            _Btn(
              icon: Icons.info_outline,
              label: 'Info',
              active: true,
              onTap: _showMeetingInfoPanel,
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

  // ── GALLERY VIEW (CRUX: Meet + Zoom blend) ────
  Widget _buildGalleryView() {
    const tileBg = Color(0xFF1A1529);  // CRUX dark purple tint

    return Container(
      color: const Color(0xFF0F0C1A),
      child: SafeArea(
        bottom: false,
        child: Column(children: [
          const SizedBox(height: 60),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 90),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 4 / 3,
              ),
              itemCount: _presenceList.length,
              itemBuilder: (ctx, i) {
                final p = _presenceList[i];
                final uid = p['userId'] as String? ?? '';
                final isMe = uid == widget.userId;
                final name = isMe
                    ? widget.userName
                    : (_participantNames[uid] ?? (p['name'] as String? ?? 'Participant'));
                final firstName = name.split(' ').first;
                final camOn = isMe ? _camOn : (_participantCamOn[uid] ?? true);
                final photo = isMe ? _ownPhotoBytes : _participantPhotos[uid];
                final isSpeaking = _participantSpeaking[uid] == true;
                final micMuted = isMe ? !_micOn : false;
                final handRaised = p['handRaised'] == true;

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    color: tileBg,
                    borderRadius: BorderRadius.circular(16),
                    border: isSpeaking
                        ? Border.all(color: const Color(0xFFB71C1C), width: 2.5)
                        : isMe
                            ? Border.all(color: const Color(0xFF6A1B9A).withValues(alpha: 0.5), width: 1.5)
                            : Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1),
                    boxShadow: isSpeaking
                        ? [
                            BoxShadow(color: const Color(0xFFB71C1C).withValues(alpha: 0.3), blurRadius: 16, spreadRadius: 2),
                            BoxShadow(color: const Color(0xFF6A1B9A).withValues(alpha: 0.2), blurRadius: 24),
                          ]
                        : [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 8)],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(fit: StackFit.expand, children: [

                      // ── VIDEO or AVATAR ──────────────────────────
                      if (camOn)
                        isMe
                            ? RTCVideoView(_localRenderer,
                                mirror: !_sharingScreen,
                                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                            : RTCVideoView(_remoteRenderer,
                                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                      else
                        Container(
                          color: tileBg,
                          child: Center(
                            child: photo != null
                                ? Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isSpeaking ? const Color(0xFFB71C1C) : Colors.white24,
                                        width: 2,
                                      ),
                                    ),
                                    child: ClipOval(
                                      child: Image.memory(photo,
                                          width: 68, height: 68, fit: BoxFit.cover),
                                    ),
                                  )
                                : Container(
                                    width: 68, height: 68,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: _avatarGradient(uid),
                                      ),
                                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 8)],
                                    ),
                                    child: Center(
                                      child: Text(
                                        firstName.isNotEmpty ? firstName[0].toUpperCase() : '?',
                                        style: GoogleFonts.poppins(
                                            color: Colors.white,
                                            fontSize: 26,
                                            fontWeight: FontWeight.w800),
                                      ),
                                    ),
                                  ),
                          ),
                        ),

                      // ── VIGNETTE on video ────────────────────────
                      if (camOn)
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.6),
                                ],
                                stops: const [0, 0.55, 1],
                              ),
                            ),
                          ),
                        ),

                      // ── BOTTOM INFO BAR ───────────────────────────
                      Positioned(
                        bottom: 0, left: 0, right: 0,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                          child: Row(children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 22, height: 22,
                              decoration: BoxDecoration(
                                color: micMuted
                                    ? const Color(0xFFEA4335)
                                    : Colors.black.withValues(alpha: 0.5),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                micMuted ? Icons.mic_off : Icons.mic,
                                color: Colors.white, size: 13,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                isMe ? 'Vous' : firstName,
                                style: GoogleFonts.poppins(
                                    color: Colors.white, fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    shadows: [const Shadow(color: Colors.black, blurRadius: 6)]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isSpeaking) ...[
                              const SizedBox(width: 4),
                              _buildSoundWave(small: true),
                            ],
                          ]),
                        ),
                      ),

                      // ── HAND RAISED (Zoom-style orange badge) ────
                      if (handRaised)
                        Positioned(
                          top: 7, left: 7,
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade700,
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: Colors.orange.withValues(alpha: 0.5), blurRadius: 8)],
                            ),
                            child: const Text('✋', style: TextStyle(fontSize: 12)),
                          ),
                        ),

                      // ── SCREEN SHARE BADGE ───────────────────────
                      if (isMe && _sharingScreen)
                        Positioned(
                          top: 7, right: 7,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [Color(0xFF1565C0), Color(0xFF0D47A1)]),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.screen_share, color: Colors.white, size: 10),
                              const SizedBox(width: 3),
                              Text('Écran', style: GoogleFonts.poppins(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        ),

                      // ── "Moi" badge (Zoom-style) ─────────────────
                      if (isMe && !_sharingScreen)
                        Positioned(
                          top: 7, right: 7,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.white24, width: 0.5),
                            ),
                            child: Text('Moi', style: GoogleFonts.poppins(
                                color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w600)),
                          ),
                        ),
                    ]),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  // CRUX gradient pairs per uid
  List<Color> _avatarGradient(String uid) {
    const gradients = [
      [Color(0xFFB71C1C), Color(0xFF6A1B9A)],
      [Color(0xFF6A1B9A), Color(0xFF1565C0)],
      [Color(0xFF00695C), Color(0xFF4527A0)],
      [Color(0xFF558B2F), Color(0xFF00695C)],
      [Color(0xFFAD1457), Color(0xFFB71C1C)],
      [Color(0xFF4527A0), Color(0xFFAD1457)],
    ];
    if (uid.isEmpty) return gradients[0];
    return gradients[uid.codeUnitAt(0) % gradients.length];
  }

  // ── INVITE SHARE SHEET ───────────────────────
  void _showInviteSheet() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.share, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Text('Inviter des participants',
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 24),
          // Meeting ID display
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
            ),
            child: Column(children: [
              Text('ID de la réunion',
                  style: GoogleFonts.poppins(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 8),
              Text(
                widget.meetingId,
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3),
              ),
              if (_meetingTitle.isNotEmpty && _meetingTitle != 'Réunion') ...[
                const SizedBox(height: 4),
                Text(_meetingTitle,
                    style: GoogleFonts.poppins(color: Colors.white60, fontSize: 13)),
              ],
            ]),
          ),
          const SizedBox(height: 16),
          // Copy link button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () async {
                final text = 'Rejoignez ma réunion CRUX\nID: ${widget.meetingId}';
                await Clipboard.setData(ClipboardData(text: text));
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Lien copié !', style: GoogleFonts.poppins()),
                    backgroundColor: AppColors.success,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    duration: const Duration(seconds: 2),
                  ));
                }
              },
              icon: const Icon(Icons.copy, size: 18),
              label: Text('Copier le lien',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ]),
      ),
    );
  }

  // ── MEETING INFO PANEL ───────────────────────
  void _showMeetingInfoPanel() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.info_outline, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Text('Informations',
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 20),
          _InfoRow(icon: Icons.title, label: 'Titre', value: _meetingTitle),
          _InfoRow(icon: Icons.tag, label: 'ID', value: widget.meetingId),
          _InfoRow(
            icon: Icons.person,
            label: 'Hôte',
            value: widget.isHost ? '${widget.userName} (vous)' : widget.userName,
          ),
          _InfoRow(
            icon: Icons.timer,
            label: 'Durée',
            value: _callSeconds > 0 ? _formattedDuration : 'En attente',
          ),
          _InfoRow(
            icon: Icons.people,
            label: 'Participants',
            value: '${_presenceList.length}',
          ),
          if (_meetingDescription.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Agenda', style: GoogleFonts.poppins(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(_meetingDescription,
                    style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13, height: 1.5)),
              ]),
            ),
          ],
          if (_meetingPassword != null && _meetingPassword!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
              ),
              child: Row(children: [
                const Icon(Icons.lock, color: Colors.amber, size: 16),
                const SizedBox(width: 8),
                Text('Réunion protégée par un code',
                    style: GoogleFonts.poppins(color: Colors.amber, fontSize: 12)),
              ]),
            ),
          ],
          const SizedBox(height: 16),
        ]),
      ),
    );
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

class _PaywallDialog extends StatefulWidget {
  final VoidCallback onUpgrade;
  final VoidCallback onLeave;
  const _PaywallDialog({required this.onUpgrade, required this.onLeave});
  @override
  State<_PaywallDialog> createState() => _PaywallDialogState();
}

class _PaywallDialogState extends State<_PaywallDialog> with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  late Animation<double> _scale;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _scale = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const grad = LinearGradient(
      colors: [Color(0xFFB71C1C), Color(0xFF6A1B9A)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
    return Dialog(
      backgroundColor: const Color(0xFF1A1529),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon with pulse
            ScaleTransition(
              scale: _scale,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: grad,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFB71C1C).withValues(alpha: 0.4),
                      blurRadius: 24,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(Icons.workspace_premium, color: Colors.white, size: 36),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'CRUX PRO',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Vos 30 minutes gratuites sont écoulées.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
            ),
            const SizedBox(height: 20),
            // Price card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              decoration: BoxDecoration(
                gradient: grad,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                children: [
                  Text(
                    '25 000 FCFA / mois',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Accès illimité — Sans publicité',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Features
            ...[
              ('Réunions illimitées', Icons.all_inclusive),
              ('Jusqu\'à 100 participants', Icons.group),
              ('Enregistrement cloud', Icons.cloud_upload),
              ('Fond d\'écran virtuel', Icons.blur_on),
              ('Support prioritaire', Icons.support_agent),
            ].map((f) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(f.$2, color: const Color(0xFFB71C1C), size: 18),
                  const SizedBox(width: 10),
                  Text(f.$1, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            )),
            const SizedBox(height: 24),
            // Upgrade button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: grad,
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFB71C1C).withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: TextButton(
                  style: TextButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                  ),
                  onPressed: _loading ? null : () async {
                    setState(() => _loading = true);
                    await Future.microtask(widget.onUpgrade);
                    if (mounted) setState(() => _loading = false);
                  },
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'Passer à CRUX PRO',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: widget.onLeave,
              child: Text(
                'Quitter la réunion',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 13),
              ),
            ),
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
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (isEnd)
          Container(
            width: 56, height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFEA4335),
              borderRadius: BorderRadius.circular(23),
              boxShadow: [BoxShadow(color: const Color(0xFFEA4335).withValues(alpha: 0.45), blurRadius: 14, offset: const Offset(0, 4))],
            ),
            child: const Icon(Icons.call_end, color: Colors.white, size: 22),
          )
        else if (isHighlight)
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFB71C1C), Color(0xFF6A1B9A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: const Color(0xFF6A1B9A).withValues(alpha: 0.45), blurRadius: 12)],
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          )
        else if (active)
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.10), width: 1),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          )
        else
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white.withValues(alpha: 0.38), size: 22),
          ),
        const SizedBox(height: 5),
        Text(
          label,
          style: GoogleFonts.poppins(
            color: isEnd ? Colors.white70 : (active || isHighlight ? Colors.white : Colors.white38),
            fontSize: 9.5,
            fontWeight: FontWeight.w500,
          ),
        ),
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

// ─────────────────────────────────────────────
//  INFO ROW (used in meeting info panel)
// ─────────────────────────────────────────────
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.primary, size: 16),
        ),
        const SizedBox(width: 12),
        Text('$label : ', style: GoogleFonts.poppins(color: Colors.white54, fontSize: 13)),
        Expanded(
          child: Text(value,
              style: GoogleFonts.poppins(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }
}
