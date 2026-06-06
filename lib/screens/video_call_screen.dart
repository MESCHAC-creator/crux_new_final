import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
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
import 'package:provider/provider.dart';
import '../providers/locale_provider.dart';
import '../l10n/app_translations.dart';
import '../theme/colors.dart';
import '../services/meeting_service.dart';
import '../services/pro_service.dart';
import '../services/user_service.dart';
import '../models/meeting_model.dart';
import '../models/meeting_report_model.dart';
import '../constants/app_constants.dart';
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

enum _CameraFilter { natural, warm, cool, vivid, bw, soft }

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
    with TickerProviderStateMixin, WidgetsBindingObserver {
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

  // ── Camera filters ───────────────────────────
  _CameraFilter _cameraFilter = _CameraFilter.natural;
  final bool _autoQuality = true;

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
  bool _callFrozen = false;           // true = call frozen, waiting for upgrade
  StreamSubscription<bool>? _proConfirmSub; // listens for real-time pro activation
  static const _freeMinutes = AppConstants.freeMinutes;

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
  bool _waveRunning = false; // only animate when someone speaks

  // ── Participant profile cache (Zoom-like) ────
  Uint8List? _ownPhotoBytes;             // local user's photo
  final Map<String, Uint8List?> _participantPhotos = {};
  final Map<String, String> _participantNames = {};
  final Map<String, bool> _participantCamOn = {};  // remote cam state
  final Map<String, StreamSubscription<Map<String, dynamic>?>> _profileSubs = {};

  // ── Live transcription ───────────────────────
  bool _showTranscript = false;
  final List<Map<String, String>> _transcriptLines = [];
  bool _sttListening = false;
  String? _sttPartialText; // live partial result shown in real-time
  final stt.SpeechToText _sttService = stt.SpeechToText();
  bool _sttAvailable = false;
  bool _sttInitializing = false;

  // ── Drawing whiteboard ────────────────────────
  bool _showWhiteboard = false;
  final List<_WbElement> _wbElements = [];          // synced from Firestore
  final List<Offset?> _wbCurrentPoints = [];        // stroke in progress
  Offset? _wbShapeStart;                            // shape drag start
  Color _wbColor = const Color(0xFF1A1A2E);
  double _wbWidth = 4.0;
  _WbTool _wbTool = _WbTool.pen;
  bool _wbFilled = false;
  final List<List<_WbElement>> _wbUndoHistory = [];
  final List<List<_WbElement>> _wbRedoHistory = [];
  Offset? _wbLaserPos;
  Timer? _wbLaserTimer;
  bool _wbSyncEnabled = false;
  StreamSubscription? _whiteboardSub;

  // ── Polls ────────────────────────────────────
  bool _showPolls = false;
  List<Map<String, dynamic>> _activePolls = [];
  StreamSubscription? _pollsSub;
  final Map<String, String> _myPollVotes = {};

  // ── Recording & Noise ────────────────────────
  bool _isRecordingLocally = false;
  Timer? _recordingBlinkTimer;
  bool _recordingBlink = false;
  bool _noiseCancellation = true;
  MediaRecorder? _mediaRecorder;
  String? _recordingPath;

  // ── Spotlight & Summary ──────────────────────
  String? _spotlightUserId;
  String? _meetingSummary;

  // ── Church mode ──────────────────────────────
  bool _isChurchMode = false;
  String? _offeringLink; // Lien de paiement pour offrandes

  // ── Live mode ────────────────────────────────
  bool _isLiveMode = false;
  bool _liveCommentVisible = false;
  final _liveCommentController = TextEditingController();
  final List<Map<String, String>> _liveComments = [];
  StreamSubscription? _liveCommentSub;
  final _liveCommentsScrollController = ScrollController();
  int _liveViewers = 1;

  // ── YouTube Live Streaming ──────────────────
  String? _youtubeRtmpKey;
  String? _youtubeUrl;
  bool _youtubeStreamingActive = false;
  String? _liveBackgroundImagePath;
  final _picker = ImagePicker();

  // ── Picture-in-Picture (TikTok-style) ────────
  static const _pipChannel = MethodChannel('com.example.crux/pip');
  bool _isInPipMode = false;
  bool _pipSupported = false;

  // ── Security & Rate Limiting ─────────────────
  Timer? _inactivityTimer;
  static const Duration _inactivityTimeout = Duration(minutes: 15);
  static const int _maxMessageLength = 500;
  final Map<String, DateTime> _lastCallTime = {};
  static const Duration _minCallInterval = Duration(milliseconds: 200);

  // ── Feature 1: Kick participant ──────────────
  StreamSubscription? _kickSub;

  // ── Feature 2: Mute individual ───────────────
  StreamSubscription? _muteSub;

  // ── Feature 5: Waiting room ──────────────────
  bool _waitingRoomEnabled = false;
  List<Map<String, dynamic>> _waitingList = [];
  StreamSubscription? _waitingSub;

  // ── Feature 6: Meeting passcode ──────────────
  String? _meetingPasscode;

  // ── Feature 7: Mirror video ───────────────────
  bool _mirrorVideo = true;

  // ── Feature 8: Hide self view ─────────────────
  bool _hideSelfView = false;

  // ── Feature 9: HD video ───────────────────────
  bool _hdEnabled = false;

  // ── Feature 11: Private chat ──────────────────
  String? _chatRecipient;   // display name, null = everyone
  String? _chatRecipientId; // userId, null = everyone

  // ── Feature 14: Remote recording badge ───────
  bool _remoteRecording = false;

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

  // ── Feature N1: Q&A ──────────────────────────
  bool _showQA = false;
  List<Map<String, dynamic>> _qaList = [];
  StreamSubscription? _qaSub;
  final Set<String> _myQAUpvotes = {};

  // ── Feature N2: Attendance ───────────────────
  List<Map<String, dynamic>> _attendanceLog = [];

  // ── Feature N3: Cam off signal ───────────────
  StreamSubscription? _camOffSub;

  // ── Feature N4: Host permissions ─────────────
  bool _allowParticipantChat = true;
  bool _allowParticipantReactions = true;
  bool _allowParticipantScreenShare = true;
  bool _muteOnEntry = false;

  // ── Feature N5: Side-by-side ─────────────────
  bool _sideBySide = false;

  // ── Feature N6: Agenda ───────────────────────
  String _meetingAgenda = '';
  bool _showAgendaPanel = false;
  final _agendaController = TextEditingController();

  // ── Feature N7: Low-light ─────────────────────
  bool _lowLightMode = false;

  // ── Feature N8: Star messages ─────────────────
  Set<String> _starredMessageIds = {};

  // ── Feature N9: Chat search ───────────────────
  bool _chatSearchActive = false;
  String _chatSearchQuery = '';
  final _chatSearchController = TextEditingController();

  // ── Feature N10: Join/leave sounds ───────────
  bool _joinLeaveSounds = true;
  int _prevPresenceCount = 0;

  // ── Feature N11: Hand raise queue ────────────
  List<String> _handRaiseOrder = [];

  // ── Feature N15: Activities panel ────────────
  bool _showActivities = false;

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
      duration: const Duration(milliseconds: 700),
    );
    // Each bar animates between a minimum height and maximum height
    _waveAnims = List.generate(3, (i) {
      return Tween<double>(begin: 0.15, end: 1.0).animate(
        CurvedAnimation(
          parent: _waveController,
          curve: Interval(i * 0.15, 0.55 + i * 0.15, curve: Curves.easeInOut),
        ),
      );
    });
    _init();
    _initPip();
    _detectLiveMode();
    _listenReactions();
    _listenPolls();
    _listenMeetingDoc();
    _listenPresence();
    _listenProStatus();
    _loadOwnPhoto();
    _resetInactivityTimer();
    _monitorConnectionHealth();
    _listenQA();
    _loadStarredMessages();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pipChannel.invokeMethod('setInCall', {'inCall': false}).catchError((_) {});
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
    _pollsSub?.cancel();
    _whiteboardSub?.cancel();
    _wbLaserTimer?.cancel();
    _recordingBlinkTimer?.cancel();
    if (_isRecordingLocally) { _mediaRecorder?.stop().catchError((_) {}); }
    _kickSub?.cancel();
    _muteSub?.cancel();
    _waitingSub?.cancel();
    for (final sub in _profileSubs.values) { sub.cancel(); }
    _profileSubs.clear();
    _bannerHideTimer?.cancel();
    _speakingTimer?.cancel();
    _proConfirmSub?.cancel();
    _qaSub?.cancel();
    _camOffSub?.cancel();
    _waveController.dispose();
    _liveCommentController.dispose();
    _liveCommentsScrollController.dispose();
    _chatController.dispose();
    _chatScrollController.dispose();
    _notesController.dispose();
    _agendaController.dispose();
    _chatSearchController.dispose();
    // whiteboard controller removed — drawing canvas has no text input
    _screenStream?.dispose();
    _localStream?.dispose();
    _pc?.close();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  // ── PICTURE-IN-PICTURE ────────────────────────

  Future<void> _initPip() async {
    WidgetsBinding.instance.addObserver(this);
    try {
      final supported = await _pipChannel.invokeMethod<bool>('isSupported') ?? false;
      if (mounted) setState(() => _pipSupported = supported);

      // Listen for PiP mode changes from native
      _pipChannel.setMethodCallHandler((call) async {
        if (call.method == 'pipModeChanged' && mounted) {
          final isInPip = call.arguments['isInPip'] as bool? ?? false;
          setState(() => _isInPipMode = isInPip);
        }
      });

      // setInCall(true) is deferred to _init() after permissions are confirmed
    } catch (_) {}
  }

  Future<void> _enterPip() async {
    try {
      await _pipChannel.invokeMethod('enterPip');
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Auto-enter PiP when app goes to background during a call
    if (state == AppLifecycleState.inactive && !_isInPipMode && _pipSupported) {
      _enterPip();
    }
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

      // Permissions confirmed — now safe to start foreground service
      _pipChannel.invokeMethod('setInCall', {'inCall': true}).catchError((_) {});

      if (mounted) setState(() => _loadingStep = 'Démarrage caméra...');

      // Read quality preference
      final prefs = await SharedPreferences.getInstance();
      final quality = prefs.getString('crux_video_quality') ?? 'HD (720p)';
      final constraints = _videoConstraints(quality);

      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
          'sampleRate': 48000,
        },
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

      // Feature N2: Record attendance join
      try {
        await _db.collection('meetings').doc(widget.meetingId)
            .collection('attendance').doc(widget.userId).set({
          'userId': widget.userId,
          'name': widget.userName,
          'joinedAt': FieldValue.serverTimestamp(),
          'leftAt': null,
        });
      } catch (_) {}

      // Feature N14: Auto-mute on entry (participants only)
      if (!widget.isHost) {
        try {
          final meetingSnap = await _db.collection('meetings').doc(widget.meetingId).get();
          if (meetingSnap.exists) {
            final autoMute = meetingSnap.data()?['muteOnEntry'] as bool? ?? false;
            if (autoMute && mounted) {
              _localStream?.getAudioTracks().forEach((t) => t.enabled = false);
              setState(() => _micOn = false);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Votre micro a été désactivé automatiquement à l\'entrée',
                    style: GoogleFonts.poppins(color: Colors.white)),
                backgroundColor: Colors.orange.shade700,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                duration: const Duration(seconds: 3),
              ));
            }
          }
        } catch (_) {}
      }

      // Feature N3: Listen for cam-off signal
      _camOffSub = _db.collection('meetings').doc(widget.meetingId)
          .collection('camOffSignals').doc(widget.userId)
          .snapshots().listen((snap) {
        if (!snap.exists || !mounted) return;
        final data = snap.data();
        if (data != null && data['camOff'] == true) {
          _localStream?.getVideoTracks().forEach((t) => t.enabled = false);
          if (mounted) {
            setState(() => _camOn = false);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Votre caméra a été désactivée par l\'hôte',
                  style: GoogleFonts.poppins(color: Colors.white)),
              backgroundColor: Colors.orange.shade700,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              duration: const Duration(seconds: 3),
            ));
          }
          // Clear the signal
          _db.collection('meetings').doc(widget.meetingId)
              .collection('camOffSignals').doc(widget.userId)
              .delete().catchError((_) {});
        }
      });

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

      _pc?.onIceCandidate = (c) {
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
        _listenWaitingRoom();
      } else {
        await _joinCall();
      }
      _listenKickSignal();
      _listenMuteSignal();
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
    if (_callTimer != null) return;
    _callStartTime = DateTime.now();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _callFrozen) return;
      final elapsed = DateTime.now().difference(_callStartTime!).inSeconds;
      setState(() => _callSeconds = elapsed);

      // Warning at half of free time
      if (!_isPro && !_warningShown && elapsed >= (_freeMinutes * 60 ~/ 2)) {
        _warningShown = true;
        final remaining = _freeMinutes - elapsed ~/ 60;
        if (mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
            content: Row(children: [
              const Icon(Icons.timer, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(
                '⏱ $remaining minute${remaining > 1 ? 's' : ''} restante${remaining > 1 ? 's' : ''} — passez à CRUX PRO',
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
              )),
            ]),
            backgroundColor: Colors.orange.shade800,
            duration: const Duration(seconds: 8),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            action: SnackBarAction(
              label: 'PRO',
              textColor: Colors.white,
              onPressed: _showPaywall,
            ),
          ));
        }
      }

      // Final 30-second warning
      if (!_isPro && elapsed >= (_freeMinutes * 60 - 30) &&
          elapsed < (_freeMinutes * 60 - 20)) {
        if (mounted) {
          ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
            content: Row(children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(
                '⚠️ 30 secondes restantes ! L\'appel va être mis en pause.',
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
              )),
            ]),
            backgroundColor: Colors.deepOrange.shade700,
            duration: const Duration(seconds: 10),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ));
        }
      }

      // Paywall + freeze at 30 min
      if (!_isPro && !_paywallShown && elapsed >= _freeMinutes * 60) {
        _paywallShown = true;
        _freezeCall();
        _showPaywall();
      }
    });
  }

  /// Freeze the call: mute mic, turn off cam, pause timer UI
  void _freezeCall() {
    if (_callFrozen) return;
    _callFrozen = true;
    // Mute mic
    _localStream?.getAudioTracks().forEach((t) => t.enabled = false);
    // Turn off camera
    _localStream?.getVideoTracks().forEach((t) => t.enabled = false);
    if (mounted) setState(() { _micOn = false; _camOn = false; });
  }

  /// Restore the call after pro upgrade
  void _restoreCall() {
    if (!_callFrozen) return;
    _callFrozen = false;
    _localStream?.getAudioTracks().forEach((t) => t.enabled = true);
    _localStream?.getVideoTracks().forEach((t) => t.enabled = true);
    if (mounted) setState(() { _micOn = true; _camOn = true; });
  }

  void _showPaywall() {
    // Start real-time listener — auto-dismiss when pro is activated
    _proConfirmSub?.cancel();
    _proConfirmSub = _proService.proStream(widget.userId).listen((isPro) {
      if (isPro && mounted) {
        _proConfirmSub?.cancel();
        _proConfirmSub = null;
        setState(() { _isPro = true; _paywallShown = false; _warningShown = false; });
        _restoreCall();
        // Close paywall dialog if open
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
        _showProActivatedBanner();
      }
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (_) => PopScope(
        canPop: false,
        child: _PaywallDialog(
          userId: widget.userId,
          userName: widget.userName,
          proService: _proService,
          freeMinutes: _freeMinutes,
          onProConfirmed: () {
            _proConfirmSub?.cancel();
            _proConfirmSub = null;
            if (mounted) {
              setState(() { _isPro = true; _paywallShown = false; _warningShown = false; });
              _restoreCall();
              Navigator.of(context).pop();
              _showProActivatedBanner();
            }
          },
          onLeave: () {
            _proConfirmSub?.cancel();
            _proConfirmSub = null;
            Navigator.pop(context);
            _leave();
          },
        ),
      ),
    );
  }

  void _showProActivatedBanner() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.workspace_premium, color: Colors.white, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text('🎉 Bienvenue dans CRUX PRO ! Réunions illimitées.',
            style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600))),
      ]),
      backgroundColor: const Color(0xFF6A1B9A),
      duration: const Duration(seconds: 5),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
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

  Widget _buildFreeTimePill() {
    final totalFree = _freeMinutes * 60;
    final remaining = (totalFree - _callSeconds).clamp(0, totalFree);
    final rm = remaining ~/ 60;
    final rs = remaining % 60;
    final label = '$rm:${rs.toString().padLeft(2, '0')}';
    final isUrgent = remaining <= 60;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isUrgent ? Colors.red.withValues(alpha: 0.85) : Colors.orange.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isUrgent ? Colors.red : Colors.orange,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_outlined, color: Colors.white, size: 11),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              fontFeatures: [const FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'FREE',
            style: GoogleFonts.poppins(
              color: Colors.white70,
              fontSize: 8,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
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
        // Auto-adaptive quality
        if (_autoQuality) {
          if (_netQuality == _NetQuality.poor && _videoQuality != _VideoQuality.low) {
            setState(() => _videoQuality = _VideoQuality.low);
            _applyVideoQuality(_videoQuality);
          } else if (_netQuality == _NetQuality.fair && _videoQuality == _VideoQuality.high) {
            setState(() => _videoQuality = _VideoQuality.medium);
            _applyVideoQuality(_videoQuality);
          } else if (_netQuality == _NetQuality.good && _videoQuality == _VideoQuality.low) {
            setState(() => _videoQuality = _VideoQuality.medium);
            _applyVideoQuality(_videoQuality);
          }
        }
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
        if (mounted) {
          setState(() {
            _participantSpeaking[widget.userId] = false;
            if (_activeSpeakerId == widget.userId) { _activeSpeakerId = null; }
          });
        }
      }
      return;
    }
    try {
      final stats = await _pc?.getStats();
      if (stats == null || !mounted) return;
      double audioLevel = 0;
      for (final report in stats) {
        final values = report.values;
        // Prefer media-source (outbound local audio level) — most reliable
        if (values['type'] == 'media-source') {
          final level = values['audioLevel'];
          if (level != null) {
            audioLevel = (level as num).toDouble();
            break;
          }
        }
        // Fallback: track stats
        if (values['type'] == 'track' && values['kind'] == 'audio') {
          final level = values['audioLevel'];
          if (level != null && audioLevel == 0) {
            audioLevel = (level as num).toDouble();
          }
        }
        // Fallback: inbound-rtp (for remote audio monitoring)
        if (values['type'] == 'inbound-rtp' && values['mediaType'] == 'audio') {
          final level = values['audioLevel'];
          if (level != null && audioLevel == 0) audioLevel = (level as num).toDouble();
        }
      }
      // Threshold: 0.005 for better Android sensitivity
      final isSpeaking = audioLevel > 0.005 || (_micOn && audioLevel > 0);
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
              _startWaveAnimation();
              _scheduleBannerHide();
            } else if (_activeSpeakerId == widget.userId) {
              _activeSpeakerId = null;
              _stopWaveAnimation();
            }
          });
        }
      }
    } catch (_) {}
  }

  void _scheduleBannerHide() {
    _bannerHideTimer?.cancel();
    _bannerHideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _bannerVisible = false);
        _stopWaveAnimation();
      }
    });
  }

  void _startWaveAnimation() {
    if (!_waveRunning) {
      _waveRunning = true;
      _waveController.repeat(reverse: true);
    }
  }

  void _stopWaveAnimation() {
    // Only stop if no one is speaking
    final anyoneSpeaking = _participantSpeaking.values.any((v) => v);
    if (!anyoneSpeaking) {
      _waveRunning = false;
      _waveController.stop();
      _waveController.reset();
    }
  }

  // ── SPEECH-TO-TEXT (live transcription) ──────

  /// Maps a BCP-47 language code to a speech_to_text locale identifier.
  static String _sttLocaleFor(String langCode) {
    const map = <String, String>{
      'fr': 'fr_FR',
      'en': 'en_US',
      'es': 'es_ES',
      'de': 'de_DE',
      'ru': 'ru_RU',
      'pt': 'pt_BR',
      'it': 'it_IT',
      'ar': 'ar_SA',
      'zh': 'zh_CN',
      'hi': 'hi_IN',
      'ja': 'ja_JP',
      'ko': 'ko_KR',
      'tr': 'tr_TR',
      'vi': 'vi_VN',
      'id': 'id_ID',
      'nl': 'nl_NL',
      'pl': 'pl_PL',
      'uk': 'uk_UA',
      'sv': 'sv_SE',
      'ha': 'ha_NG',
      'yo': 'yo_NG',
      'sw': 'sw_KE',
      'am': 'am_ET',
      'fa': 'fa_IR',
      'ro': 'ro_RO',
      'el': 'el_GR',
      'cs': 'cs_CZ',
      'hu': 'hu_HU',
      'bn': 'bn_IN',
      'th': 'th_TH',
      'mg': 'fr_FR', // fallback to French
      'wo': 'fr_FR', // fallback to French
    };
    return map[langCode] ?? 'fr_FR';
  }

  Future<void> _initStt() async {
    if (_sttInitializing) return;
    _sttInitializing = true;
    try {
      _sttAvailable = await _sttService.initialize(
        onError: (error) {
          _log.w('STT error: ${error.errorMsg}');
          if (mounted) setState(() { _sttListening = false; _sttPartialText = null; });
          // Auto-restart on transient errors
          if (mounted && _sttListening) {
            Future.delayed(const Duration(seconds: 1), _restartSttListening);
          }
        },
        onStatus: (status) {
          _log.i('STT status: $status');
          if ((status == 'done' || status == 'notListening') && mounted && _sttListening) {
            Future.delayed(const Duration(milliseconds: 300), _restartSttListening);
          }
        },
      );
    } finally {
      _sttInitializing = false;
    }
  }

  Future<void> _startTranscription() async {
    if (_sttListening) return;
    if (!_sttAvailable) {
      if (mounted) setState(() => _sttInitializing = true);
      await _initStt();
      if (mounted) setState(() => _sttInitializing = false);
    }
    if (!_sttAvailable) {
      if (mounted) {
        final lang = Provider.of<LocaleProvider>(context, listen: false).locale.languageCode;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppTranslations.t('stt_unavailable', lang), style: GoogleFonts.poppins()),
          backgroundColor: Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 4),
        ));
      }
      return;
    }
    if (mounted) setState(() { _sttListening = true; _sttPartialText = null; });
    _restartSttListening();
  }

  void _restartSttListening() {
    if (!mounted || !_sttListening || !_sttAvailable) return;
    if (_sttService.isListening) return; // already listening — don't double-start
    final langCode = Provider.of<LocaleProvider>(context, listen: false).locale.languageCode;
    final localeId = _sttLocaleFor(langCode);
    _sttService.listen(
      listenOptions: stt.SpeechListenOptions(
        localeId: localeId,
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 2),
        partialResults: true, // show words as they are spoken
        cancelOnError: false,
      ),
      onResult: (result) {
        if (!mounted) return;
        if (result.finalResult) {
          if (result.recognizedWords.isNotEmpty) {
            setState(() {
              _transcriptLines.add({
                'speaker': widget.userName,
                'text': result.recognizedWords,
              });
              _sttPartialText = null;
            });
          }
        } else {
          // Show partial result in real-time
          if (mounted) setState(() => _sttPartialText = result.recognizedWords.isNotEmpty ? result.recognizedWords : null);
        }
      },
    );
  }

  Future<void> _stopTranscription() async {
    if (mounted) setState(() { _sttListening = false; _sttPartialText = null; });
    await _sttService.stop();
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
      // Feature 14: remote recording badge
      final isRecording = data['isRecording'] as bool? ?? false;
      // Feature 5: waiting room enabled
      final waitingRoomEnabled = data['waitingRoomEnabled'] as bool? ?? false;
      // Feature 6: passcode
      final passcode = data['passcode'] as String?;
      // Feature N4: host permissions
      final allowChat = data['allowChat'] as bool? ?? true;
      final allowReactions = data['allowReactions'] as bool? ?? true;
      final allowScreenShare = data['allowScreenShare'] as bool? ?? true;
      final muteOnEntry = data['muteOnEntry'] as bool? ?? false;
      // Feature N6: agenda
      final agenda = data['agenda'] as String? ?? '';
      if (mounted) {
        setState(() {
          _isCoHost = nowCoHost;
          _isLocked = locked as bool;
          _remoteRecording = isRecording;
          _waitingRoomEnabled = waitingRoomEnabled;
          _meetingPasscode = passcode;
          _allowParticipantChat = allowChat;
          _allowParticipantReactions = allowReactions;
          _allowParticipantScreenShare = allowScreenShare;
          _muteOnEntry = muteOnEntry;
          _meetingAgenda = agenda;
          _agendaController.text = agenda;
        });
      }

      // Feature N14: auto-mute on entry (applied once after init)
    });
  }

  // ── PRESENCE LISTENER ────────────────────────
  void _listenPresence() {
    _presenceSub = _meetingService
        .streamPresence(widget.meetingId)
        .listen((list) {
      if (!mounted) return;
      // Notify ALL participants (not just host) when someone raises their hand
      for (final p in list) {
        final uid = p['userId'] as String? ?? '';
        final raised = p['handRaised'] == true;
        if (raised && uid != widget.userId && !_raisedHands.contains(uid)) {
          _raisedHands.add(uid);
          final name = p['userName'] ?? (p['name'] as String? ?? 'Participant');
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('✋ $name a levé la main', style: GoogleFonts.poppins(color: Colors.white)),
            backgroundColor: Colors.orange.shade800,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ));
        } else if (!raised) {
          _raisedHands.remove(uid);
        }
      }
      // Feature N10: join/leave sounds
      final newCount = list.length;
      if (_joinLeaveSounds && _prevPresenceCount > 0) {
        if (newCount > _prevPresenceCount) {
          SystemSound.play(SystemSoundType.click);
        } else if (newCount < _prevPresenceCount) {
          HapticFeedback.lightImpact();
        }
      }
      _prevPresenceCount = newCount;

      // Feature N11: hand raise queue
      final newQueue = <String>[];
      for (final p in list) {
        final uid = p['userId'] as String? ?? '';
        if (p['handRaised'] == true && uid.isNotEmpty) {
          if (!newQueue.contains(uid)) newQueue.add(uid);
        }
      }
      // Preserve original order of existing entries, add new ones at end
      final updatedQueue = <String>[];
      for (final uid in _handRaiseOrder) {
        if (newQueue.contains(uid)) updatedQueue.add(uid);
      }
      for (final uid in newQueue) {
        if (!updatedQueue.contains(uid)) updatedQueue.add(uid);
      }

      setState(() {
        _presenceList = list;
        _handRaiseOrder = updatedQueue;
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
            _startWaveAnimation();
            _scheduleBannerHide();
          } else if (_activeSpeakerId == uid) {
            _activeSpeakerId = null;
            _stopWaveAnimation();
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
      } catch (e, st) {
        _log.e('Error stopping screen share: $e', stackTrace: st);
        await _screenStream?.dispose();
        _screenStream = null;
        if (mounted) setState(() => _sharingScreen = false);
      }
    } else {
      // ── Start sharing ──
      try {
        // iOS does not support screen capture via WebRTC
        if (!kIsWeb && Platform.isIOS) {
          _log.w('Screen share: Not supported on iOS');
          if (mounted) {
            final lang = Provider.of<LocaleProvider>(context, listen: false).locale.languageCode;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(AppTranslations.t('screen_share_ios', lang), style: GoogleFonts.poppins()),
              backgroundColor: Colors.orange.shade700,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              duration: const Duration(seconds: 3),
            ));
          }
          return;
        }

        // If peer connection not yet established, show a helpful message
        // (happens when participant count is still 0 / signaling not complete)
        if (_pc == null) {
          _log.w('Screen share: Peer connection not initialized yet');
          if (mounted) {
            final lang = Provider.of<LocaleProvider>(context, listen: false).locale.languageCode;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                AppTranslations.t('screen_share_wait', lang),
                style: GoogleFonts.poppins(),
              ),
              backgroundColor: Colors.orange.shade700,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              duration: const Duration(seconds: 4),
            ));
          }
          return;
        }

        _log.i('Starting screen share - requesting display media');
        _screenStream = await navigator.mediaDevices.getDisplayMedia({
          'video': {'mandatory': {}, 'optional': []},
          'audio': false,
        });

        if (_screenStream == null) {
          _log.w('Screen share: getDisplayMedia returned null');
          if (mounted) {
            final lang = Provider.of<LocaleProvider>(context, listen: false).locale.languageCode;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(AppTranslations.t('screen_share_unavailable', lang), style: GoogleFonts.poppins()),
              backgroundColor: Colors.orange.shade700,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ));
          }
          return;
        }

        final tracks = _screenStream!.getVideoTracks();
        _log.i('Screen share: Got ${tracks.length} video tracks');
        if (tracks.isEmpty) {
          _log.w('Screen share: No video tracks in screen stream');
          await _screenStream?.dispose();
          _screenStream = null;
          if (mounted) {
            final lang = Provider.of<LocaleProvider>(context, listen: false).locale.languageCode;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(AppTranslations.t('screen_share_no_track', lang), style: GoogleFonts.poppins()),
              backgroundColor: Colors.orange.shade700,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ));
          }
          return;
        }

        final screenTrack = tracks.first;
        _log.i('Screen share: Replacing video track with screen track');

        // Replace video track in all senders
        final senders = await _pc!.getSenders();
        _log.i('Screen share: Found ${senders.length} senders');

        bool trackReplaced = false;
        for (final sender in senders) {
          _log.i('Screen share: Sender track kind: ${sender.track?.kind}');
          if (sender.track?.kind == 'video') {
            try {
              await sender.replaceTrack(screenTrack);
              _log.i('Screen share: Track replaced successfully');
              trackReplaced = true;
            } catch (e, st) {
              _log.e('Screen share: Error replacing track: $e', stackTrace: st);
            }
          }
        }

        if (!trackReplaced) {
          _log.w('Screen share: No video track was replaced');
        }

        screenTrack.onEnded = () {
          _log.i('Screen share: Track ended callback triggered');
          if (mounted) _toggleScreenShare();
        };

        if (mounted) {
          setState(() {
            _sharingScreen = true;
            _localRenderer.srcObject = _screenStream;
          });
          _log.i('Screen share: State updated, sharing active');
        }
      } catch (e, st) {
        _log.e('Screen share error: $e\nStackTrace: $st', stackTrace: st);
        await _screenStream?.dispose();
        _screenStream = null;
        if (mounted) {
          final msg = e.toString().contains('Permission')
              ? 'Permission refusée pour le partage d\'écran.'
              : e.toString().contains('cancel') || e.toString().contains('Cancel')
                  ? 'Partage d\'écran annulé.'
                  : e.toString().contains('NotAllowedError')
                      ? 'Partage d\'écran non autorisé.'
                      : e.toString().contains('NotSupportedError')
                          ? 'Partage d\'écran non supporté sur cet appareil.'
                          : 'Erreur: ${e.toString().substring(0, 100)}';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(msg, style: GoogleFonts.poppins()),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 4),
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
          _isChurchMode = title.contains('[Église]') || title.contains('[Eglise]') || title.contains('[EGLISE]');
          _offeringLink = snap.data()?['offeringLink'] as String?;
          _meetingPasscode = snap.data()?['passcode'] as String?;
          _waitingRoomEnabled = snap.data()?['waitingRoomEnabled'] as bool? ?? false;
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
        });
      }
    } catch (e) {
      if (mounted) {
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

      // YouTube RTMP streaming requires an RTMP relay server on the backend.
      // The app opens YouTube Studio so the streamer can start the live,
      // while Firestore flags notify viewers. This is the standard mobile approach.
      if (mounted) {
        // Open YouTube Studio / Live Dashboard so host can go live manually
        final ytUrl = Uri.parse('https://studio.youtube.com');
        try { await launchUrl(ytUrl, mode: LaunchMode.externalApplication); } catch (_) {}

        setState(() => _youtubeStreamingActive = true);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('🔴 Live activé — ouverture YouTube Studio', style: GoogleFonts.poppins()),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 4),
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
    // Feature N2: Record leftAt
    _db.collection('meetings').doc(widget.meetingId)
        .collection('attendance').doc(widget.userId)
        .update({'leftAt': FieldValue.serverTimestamp()}).catchError((_) {});

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
    _kickSub?.cancel();
    _muteSub?.cancel();
    _waitingSub?.cancel();
    _liveCommentSub?.cancel();
    _qaSub?.cancel();
    _camOffSub?.cancel();
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
    // PiP mode: show minimal video-only view without any controls or panels
    if (_isInPipMode) return _buildPipView();

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

  /// Minimal view shown inside the PiP window — just video, no controls
  Widget _buildPipView() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        // Remote video fullscreen
        if (_remoteRenderer.renderVideo)
          RTCVideoView(
            _remoteRenderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          )
        else
          _buildLocalVideoView(),

        // Meeting ID label at top
        Positioned(
          top: 4, left: 6,
          child: Text(
            widget.meetingId.substring(0, math.min(8, widget.meetingId.length)),
            style: GoogleFonts.poppins(
              color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w600,
            ),
          ),
        ),

        // Mic status indicator
        Positioned(
          bottom: 4, right: 6,
          child: Icon(
            _micOn ? Icons.mic : Icons.mic_off,
            color: _micOn ? Colors.white70 : Colors.redAccent,
            size: 14,
          ),
        ),
      ]),
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
            // Show "Open Settings" button for permission errors
            if (_error?.toLowerCase().contains('autorisation') ?? false) ...[
              ElevatedButton.icon(
                onPressed: openAppSettings,
                icon: const Icon(Icons.settings),
                label: const Text('Ouvrir Paramètres'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade700,
                ),
              ),
              const SizedBox(height: 12),
            ],
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
              label: Text('Réessayer', style: GoogleFonts.poppins(color: const Color(0xFFB71C1C))),
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
    // Spotlight overrides: spotlighted user goes fullscreen
    final spotlightLocal = _spotlightUserId == widget.userId;
    final spotlightRemote = _spotlightUserId != null && _spotlightUserId != widget.userId;
    final showLocalBig = !hasRemote || _swappedView || spotlightLocal;

    return Stack(children: [
      // ── MAIN VIDEO (full screen) ──────────────────────────────────────
      Positioned.fill(
        child: spotlightRemote
            ? (_buildRemoteVideo())
            : spotlightLocal
                ? (_camOn ? _buildLocalVideoView() : _buildVideoOff(widget.userName, _ownPhotoBytes))
                : showLocalBig
                    ? (_camOn
                        ? _buildLocalVideoView()
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
                      // Remote big → show local in PiP (hide self view check)
                      : _hideSelfView
                          ? Container(
                              color: const Color(0xFF1A1529),
                              child: Center(
                                child: GestureDetector(
                                  onTap: () => setState(() => _hideSelfView = false),
                                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                                    const Icon(Icons.visibility_off, color: Colors.white38, size: 20),
                                    const SizedBox(height: 4),
                                    Text('Afficher', style: GoogleFonts.poppins(color: Colors.white38, fontSize: 9)),
                                  ]),
                                ),
                              ),
                            )
                          : (_camOn
                              ? _buildLocalVideoView()
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
                  ? _buildLocalVideoView()
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

      // ── TRANSCRIPT PANEL ─────────────────────────────────────────────
      AnimatedPositioned(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
        bottom: _showTranscript ? 0 : -380,
        left: 0,
        right: 0,
        height: 380,
        child: _buildTranscriptPanel(),
      ),

      // ── WHITEBOARD PANEL ─────────────────────────────────────────────
      AnimatedPositioned(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
        bottom: _showWhiteboard ? 0 : -400,
        left: 0,
        right: 0,
        height: 400,
        child: _buildWhiteboardPanel(),
      ),

      // ── POLLS PANEL ──────────────────────────────────────────────────
      AnimatedPositioned(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
        bottom: _showPolls ? 0 : -400,
        left: 0,
        right: 0,
        height: 400,
        child: _buildPollsPanel(),
      ),

      // ── Q&A PANEL ────────────────────────────────────────────────────
      AnimatedPositioned(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
        bottom: _showQA ? 0 : -400,
        left: 0,
        right: 0,
        height: 400,
        child: _buildQAPanel(),
      ),

      // ── AGENDA PANEL ─────────────────────────────────────────────────
      AnimatedPositioned(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
        bottom: _showAgendaPanel ? 0 : -400,
        left: 0,
        right: 0,
        height: 400,
        child: _buildAgendaPanel(),
      ),

      // ── ACTIVITIES PANEL ─────────────────────────────────────────────
      AnimatedPositioned(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
        bottom: _showActivities ? 0 : -400,
        left: 0,
        right: 0,
        height: 400,
        child: _buildActivitiesPanel(),
      ),

      // ── RECORDING INDICATOR ──────────────────────────────────────────
      if (_isRecordingLocally)
        Positioned(
          top: 60,
          right: 12,
          child: AnimatedOpacity(
            opacity: _recordingBlink ? 1.0 : 0.3,
            duration: const Duration(milliseconds: 400),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(6)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.fiber_manual_record, color: Colors.white, size: 10),
                const SizedBox(width: 4),
                Text('REC', style: GoogleFonts.poppins(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ),

      // ── CONTROLS ─────────────────────────────────────────────────────
      AnimatedPositioned(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
        bottom: (_showChat || _showParticipants || _showTranscript || _showWhiteboard || _showPolls || _showQA || _showAgendaPanel || _showActivities) ? 400 : 0,
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
                  ? _buildLocalVideoView()
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
        if (_callSeconds > 0) ...[
          const SizedBox(width: 8),
          // Feature N13: Color-coded tappable timer
          GestureDetector(
            onTap: () {
              // Show meeting stats dialog
              showDialog(context: context, builder: (ctx) => AlertDialog(
                backgroundColor: const Color(0xFF1A1A2E),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: Text('Statistiques', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700)),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  _InfoRow(icon: Icons.timer, label: 'Durée', value: _formattedDuration),
                  _InfoRow(icon: Icons.people, label: 'Participants', value: '${_presenceList.length}'),
                  _InfoRow(icon: Icons.fiber_manual_record, label: 'Enregistrement', value: _isRecordingLocally ? 'Actif' : 'Inactif'),
                ]),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Fermer', style: GoogleFonts.poppins(color: Colors.white60)))],
              ));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _callSeconds < 1800
                    ? Colors.green.withValues(alpha: 0.15)
                    : _callSeconds < 5400
                        ? Colors.orange.withValues(alpha: 0.15)
                        : Colors.red.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _callSeconds < 1800 ? Colors.green.withValues(alpha: 0.4) : _callSeconds < 5400 ? Colors.orange.withValues(alpha: 0.4) : Colors.red.withValues(alpha: 0.5)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.timer_outlined,
                    color: _callSeconds < 1800 ? Colors.green : _callSeconds < 5400 ? Colors.orange : Colors.red,
                    size: 11),
                const SizedBox(width: 4),
                Text(
                  _formattedDuration,
                  style: GoogleFonts.poppins(
                      color: _callSeconds < 1800 ? Colors.green : _callSeconds < 5400 ? Colors.orange : Colors.red,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [const FontFeature.tabularFigures()]),
                ),
              ]),
            ),
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
        if (_meetingPasscode != null && _meetingPasscode!.isNotEmpty) ...[
          const SizedBox(width: 6),
          const Tooltip(
            message: 'Réunion protégée par un code',
            child: Icon(Icons.lock_outline, color: Colors.lightBlue, size: 14),
          ),
        ],
        if (_remoteRecording || _isRecordingLocally) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.fiber_manual_record, color: Colors.white, size: 8),
              const SizedBox(width: 3),
              Text('REC', style: GoogleFonts.poppins(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
            ]),
          ),
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
        // E2E encryption indicator
        if (_remoteConnected) ...[
          const SizedBox(width: 6),
          Tooltip(
            message: 'Chiffrement bout-en-bout actif (DTLS-SRTP)',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.lock, color: Colors.green, size: 10),
                const SizedBox(width: 3),
                Text('E2E', style: GoogleFonts.poppins(color: Colors.green, fontSize: 9, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ],
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
      duration: const Duration(milliseconds: 250),
      child: AnimatedScale(
        scale: _bannerVisible ? 1.0 : 0.85,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutBack,
        child: IgnorePointer(
          ignoring: !_bannerVisible,
          child: Center(
            child: Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7F0000), Color(0xFF6A1B9A)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(color: const Color(0xFFB71C1C).withValues(alpha: 0.5), blurRadius: 14, spreadRadius: 1),
                  BoxShadow(color: const Color(0xFF6A1B9A).withValues(alpha: 0.35), blurRadius: 24),
                ],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.mic, size: 13, color: Colors.white70),
                const SizedBox(width: 6),
                _buildSoundWave(small: true),
                const SizedBox(width: 8),
                Text(displayName,
                    style: GoogleFonts.poppins(
                        color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700,
                        letterSpacing: 0.2)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  // ── SOUND WAVE ANIMATION ─────────────────────
  Widget _buildSoundWave({bool small = false, Color? color}) {
    final maxH = small ? 14.0 : 20.0;
    final minH = small ? 3.0 : 4.0;
    final w = small ? 3.0 : 4.5;
    final barColor = color ?? Colors.white.withValues(alpha: 0.95);
    return SizedBox(
      height: maxH,
      child: AnimatedBuilder(
        animation: _waveController,
        builder: (_, __) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(3, (i) {
            // barH goes from minH to maxH
            final barH = minH + (maxH - minH) * _waveAnims[i].value;
            return Container(
              width: w,
              height: barH,
              margin: EdgeInsets.symmetric(horizontal: small ? 1.5 : 2),
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ),
    );
  }

  // ── EMOJI BAR ────────────────────────────────
  Widget _buildEmojiBar() {
    const emojis = ['👍', '❤️', '😂', '🎉', '😮', '👏', '🙏', '🔥', '😢', '💯', '🎊', '✨'];
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
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
        children: [
          ...emojis
              .map((e) => GestureDetector(
                    onTap: () {
                      _sendReaction(e);
                      setState(() => _showEmojiBar = false);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Text(e, style: const TextStyle(fontSize: 22)),
                    ),
                  )),
          GestureDetector(
            onTap: () {
              setState(() => _showEmojiBar = false);
              _showFullEmojiPicker();
            },
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add, color: Colors.white70, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  // ── PARTICIPANTS PANEL ────────────────────────
  Widget _buildParticipantsPanel() {
    final isPrivileged = widget.isHost || _isCoHost;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: _buildParticipantsPanelContent(isPrivileged),
      ),
    );
  }

  Widget _buildParticipantsPanelContent(bool isPrivileged) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xCC181828),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.7), blurRadius: 20)
        ],
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 0.5)),
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
            // Feature N11: hand raise queue count badge
            if (_handRaiseOrder.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.6)),
                ),
                child: Text('✋ ${_handRaiseOrder.length}', style: GoogleFonts.poppins(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
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
        // Waiting room section (host only)
        if (isPrivileged && _waitingList.isNotEmpty)
          Container(
            color: Colors.orange.withValues(alpha: 0.08),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Text('Salle d\'attente (${_waitingList.length})',
                    style: GoogleFonts.poppins(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.w700)),
              ),
              ..._waitingList.map((w) {
                final wId = w['id'] as String? ?? '';
                final wName = w['name'] as String? ?? 'Inconnu';
                return ListTile(
                  dense: true,
                  leading: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.2), shape: BoxShape.circle),
                    child: Center(child: Text(wName.isNotEmpty ? wName[0].toUpperCase() : '?',
                        style: GoogleFonts.poppins(color: Colors.orange, fontWeight: FontWeight.w700))),
                  ),
                  title: Text(wName, style: GoogleFonts.poppins(color: Colors.white, fontSize: 12)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    GestureDetector(
                      onTap: () => _admitParticipant(wId),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.withValues(alpha: 0.6))),
                        child: Text('Admettre', style: GoogleFonts.poppins(color: Colors.green, fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => _denyParticipant(wId),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.withValues(alpha: 0.5))),
                        child: Text('Refuser', style: GoogleFonts.poppins(color: Colors.red, fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ]),
                );
              }),
              const Divider(color: Colors.white12, height: 1),
            ]),
          ),
        // Feature N11: Hand raise queue
        if (_handRaiseOrder.isNotEmpty)
          Container(
            color: Colors.orange.withValues(alpha: 0.06),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Text('✋ File d\'attente (${_handRaiseOrder.length})',
                    style: GoogleFonts.poppins(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.w700)),
              ),
              ..._handRaiseOrder.asMap().entries.map((entry) {
                final idx = entry.key + 1;
                final uid = entry.value;
                final name = _participantNames[uid] ?? uid;
                return ListTile(
                  dense: true,
                  leading: Text('$idx.', style: GoogleFonts.poppins(color: Colors.orange, fontWeight: FontWeight.w700, fontSize: 14)),
                  title: Text(name, style: GoogleFonts.poppins(color: Colors.white, fontSize: 12)),
                  trailing: isPrivileged ? GestureDetector(
                    onTap: () => _toggleSpotlight(uid),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.purple.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.purple.withValues(alpha: 0.5))),
                      child: Text('Appeler', style: GoogleFonts.poppins(color: Colors.purple, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ) : null,
                );
              }),
              const Divider(color: Colors.white12, height: 1),
            ]),
          ),
        Expanded(
          child: _presenceList.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.person_off_outlined, color: Colors.white24, size: 40),
                  const SizedBox(height: 8),
                  Text('En attente de participants...', style: GoogleFonts.poppins(color: Colors.white38, fontSize: 13)),
                ]))
              : RefreshIndicator(
                  onRefresh: () async {
                    HapticFeedback.lightImpact();
                    _loadParticipantProfiles(_presenceList);
                  },
                  color: AppColors.primary,
                  child: ListView.builder(
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
                        decoration: const BoxDecoration(gradient: AppColors.primaryGradient, shape: BoxShape.circle),
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
                                } else if (action == 'kick') {
                                  await _kickParticipant(pId, pName);
                                } else if (action == 'mute') {
                                  await _muteParticipant(pId);
                                } else if (action == 'rename') {
                                  await _renameParticipant(pId, pName);
                                } else if (action == 'transfer_host') {
                                  await _transferHost(pId, pName);
                                } else if (action == 'spotlight') {
                                  _toggleSpotlight(pId);
                                } else if (action == 'turn_off_cam') {
                                  await _sendCamOffSignal(pId);
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    content: Text('Caméra désactivée pour $pName', style: GoogleFonts.poppins()),
                                    backgroundColor: Colors.orange.shade700,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    duration: const Duration(seconds: 2),
                                  ));
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
                                PopupMenuItem(value: 'mute',
                                    child: Row(children: [
                                      const Icon(Icons.mic_off, color: Colors.orange, size: 16),
                                      const SizedBox(width: 8),
                                      Text('Couper le micro', style: GoogleFonts.poppins(color: Colors.white, fontSize: 13)),
                                    ])),
                                PopupMenuItem(value: 'rename',
                                    child: Row(children: [
                                      const Icon(Icons.drive_file_rename_outline, color: Colors.lightBlue, size: 16),
                                      const SizedBox(width: 8),
                                      Text('Renommer', style: GoogleFonts.poppins(color: Colors.white, fontSize: 13)),
                                    ])),
                                PopupMenuItem(value: 'spotlight',
                                    child: Row(children: [
                                      Icon(_spotlightUserId == pId ? Icons.star : Icons.star_outline, color: Colors.purple, size: 16),
                                      const SizedBox(width: 8),
                                      Text(_spotlightUserId == pId ? 'Retirer spotlight' : 'Mettre en avant',
                                          style: GoogleFonts.poppins(color: Colors.white, fontSize: 13)),
                                    ])),
                                if (widget.isHost) PopupMenuItem(value: 'transfer_host',
                                    child: Row(children: [
                                      const Icon(Icons.swap_horiz, color: Colors.amber, size: 16),
                                      const SizedBox(width: 8),
                                      Text('Transférer le rôle hôte', style: GoogleFonts.poppins(color: Colors.white, fontSize: 13)),
                                    ])),
                                PopupMenuItem(value: 'turn_off_cam',
                                    child: Row(children: [
                                      const Icon(Icons.videocam_off, color: Colors.orange, size: 16),
                                      const SizedBox(width: 8),
                                      Text('Éteindre la caméra', style: GoogleFonts.poppins(color: Colors.white, fontSize: 13)),
                                    ])),
                                PopupMenuItem(value: 'kick',
                                    child: Row(children: [
                                      const Icon(Icons.person_remove, color: Colors.red, size: 16),
                                      const SizedBox(width: 8),
                                      Text('Retirer de la réunion', style: GoogleFonts.poppins(color: Colors.red, fontSize: 13)),
                                    ])),
                              ],
                            )
                          : null,
                    );
                  },
                ),
                ),
        ),
      ]),
    );
  }

  // ── CHAT PANEL ───────────────────────────────
  Widget _buildChatPanel() {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xCC181828),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.7), blurRadius: 20)],
            border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 0.5)),
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
        // Feature N9: search bar or tab row
        if (_chatSearchActive)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _chatSearchController,
                  autofocus: true,
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
                  onChanged: (v) => setState(() => _chatSearchQuery = v),
                  decoration: InputDecoration(
                    hintText: 'Rechercher dans le chat...',
                    hintStyle: GoogleFonts.poppins(color: Colors.white38, fontSize: 12),
                    prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 18),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.08),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () => setState(() {
                  _chatSearchActive = false;
                  _chatSearchQuery = '';
                  _chatSearchController.clear();
                }),
              ),
            ]),
          )
        else
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
            // Feature N8: starred tab
            _ChatTab(
              icon: Icons.star_outline,
              label: '★',
              selected: _chatTab == 2,
              onTap: () => setState(() => _chatTab = 2),
            ),
            const Spacer(),
            // Feature N9: search button
            IconButton(
              icon: const Icon(Icons.search, color: Colors.white54, size: 20),
              onPressed: () => setState(() => _chatSearchActive = true),
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down,
                  color: Colors.white54, size: 22),
              onPressed: () => setState(() => _showChat = false),
            ),
          ]),
        const Divider(color: Colors.white12, height: 1),
        Expanded(
          child: _chatTab == 0
              ? _buildChatMessages()
              : _chatTab == 1
                  ? _buildNotes()
                  : _buildStarredMessages(),
        ),
        if (_chatTab == 0 && (_allowParticipantChat || widget.isHost || _isCoHost)) _buildChatInput(),
        if (_chatTab == 0 && !_allowParticipantChat && !widget.isHost && !_isCoHost)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Center(child: Text('Le chat est désactivé par l\'hôte',
                  style: GoogleFonts.poppins(color: Colors.red, fontSize: 12))),
            ),
          ),
      ]),
        ),
      ),
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
        // Filter: show public messages and DMs involving this user
        var visibleDocs = docs.where((doc) {
          final data = doc.data()! as Map<String, dynamic>;
          final recipientId = data['recipientId'] as String?;
          final senderId = data['senderId'] as String? ?? '';
          if (recipientId == null) return true; // public
          return recipientId == widget.userId || senderId == widget.userId;
        }).toList();

        // Feature N9: search filter
        if (_chatSearchQuery.isNotEmpty) {
          final q = _chatSearchQuery.toLowerCase();
          visibleDocs = visibleDocs.where((doc) {
            final msg = ((doc.data()! as Map<String, dynamic>)['message'] as String? ?? '').toLowerCase();
            return msg.contains(q);
          }).toList();
        }

        if (visibleDocs.isEmpty) {
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
          itemCount: visibleDocs.length,
          itemBuilder: (ctx, i) {
            final doc = visibleDocs[i];
            final d = doc.data()! as Map<String, dynamic>;
            final isMine = d['sender'] == widget.userName;
            final senderId = d['senderId'] as String? ?? '';
            final senderPhoto = isMine
                ? _ownPhotoBytes
                : (senderId.isNotEmpty ? _participantPhotos[senderId] : null);
            final senderName = d['sender'] as String? ?? '';
            final senderInitial = senderName.isNotEmpty ? senderName[0].toUpperCase() : '?';
            final recipientId = d['recipientId'] as String?;
            final recipientName = d['recipientName'] as String?;
            final imageBase64 = d['imageBase64'] as String?;
            final reactions = d['reactions'] as Map<String, dynamic>? ?? {};

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

            final isStarred = _starredMessageIds.contains(doc.id);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: GestureDetector(
                onLongPress: () => _showMessageActionSheet(doc.id),
                child: Column(
                  crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    // DM label
                    if (recipientId != null)
                      Padding(
                        padding: EdgeInsets.only(
                            left: isMine ? 0 : 40, right: isMine ? 40 : 0, bottom: 2),
                        child: Text(
                          isMine
                              ? 'Message privé à ${recipientName ?? 'quelqu\'un'}'
                              : 'Message privé',
                          style: GoogleFonts.poppins(color: Colors.lightBlue, fontSize: 10, fontStyle: FontStyle.italic),
                        ),
                      ),
                    Row(
                      mainAxisAlignment:
                          isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (!isMine) ...[avatarWidget, const SizedBox(width: 6)],
                        Flexible(
                          child: Container(
                            constraints: BoxConstraints(
                                maxWidth: MediaQuery.of(ctx).size.width * 0.65),
                            padding: imageBase64 != null
                                ? const EdgeInsets.all(4)
                                : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: recipientId != null
                                  ? (isMine ? Colors.blue.shade800 : Colors.blue.withValues(alpha: 0.15))
                                  : (isMine ? AppColors.primary : Colors.white.withValues(alpha: 0.1)),
                              borderRadius: BorderRadius.circular(12),
                              border: recipientId != null
                                  ? Border.all(color: Colors.lightBlue.withValues(alpha: 0.4)) : null,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!isMine)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 2),
                                    child: Text(senderName,
                                        style: GoogleFonts.poppins(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w600)),
                                  ),
                                if (imageBase64 != null)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.memory(
                                      base64Decode(imageBase64),
                                      width: 200,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                else
                                  Text(d['message'] ?? '',
                                      style: GoogleFonts.poppins(color: Colors.white, fontSize: 13)),
                              ],
                            ),
                          ),
                        ),
                        if (isMine) ...[const SizedBox(width: 6), avatarWidget],
                      ],
                    ),
                    // Feature N8: Star indicator
                    if (isStarred)
                      Padding(
                        padding: EdgeInsets.only(top: 2, left: isMine ? 0 : 40, right: isMine ? 40 : 0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
                          children: [
                            const Icon(Icons.star, color: Colors.amber, size: 11),
                            const SizedBox(width: 3),
                            Text('Sauvegardé', style: GoogleFonts.poppins(color: Colors.amber, fontSize: 9)),
                          ],
                        ),
                      ),
                    // Reaction counts
                    if (reactions.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(
                            top: 4, left: isMine ? 0 : 40, right: isMine ? 40 : 0),
                        child: Wrap(
                          spacing: 4,
                          children: reactions.entries.map((e) {
                            final users = (e.value as List<dynamic>);
                            final iMine = users.contains(widget.userId);
                            return GestureDetector(
                              onTap: () => _toggleMessageReaction(doc.id, e.key),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: iMine
                                      ? AppColors.primary.withValues(alpha: 0.3)
                                      : Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: iMine ? AppColors.primary : Colors.white24,
                                    width: 0.5,
                                  ),
                                ),
                                child: Text('${e.key} ${users.length}',
                                    style: GoogleFonts.poppins(fontSize: 11, color: Colors.white)),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildChatInput() {
    final isDM = _chatRecipientId != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // DM indicator
        if (isDM)
          GestureDetector(
            onTap: _showRecipientSelector,
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.lightBlue.withValues(alpha: 0.4)),
              ),
              child: Row(children: [
                const Icon(Icons.lock, color: Colors.lightBlue, size: 12),
                const SizedBox(width: 6),
                Expanded(child: Text('À: $_chatRecipient',
                    style: GoogleFonts.poppins(color: Colors.lightBlue, fontSize: 11))),
                const Icon(Icons.close, color: Colors.lightBlue, size: 14),
              ]),
            ),
          )
        else
          GestureDetector(
            onTap: _showRecipientSelector,
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(children: [
                const Icon(Icons.people_outline, color: Colors.white38, size: 12),
                const SizedBox(width: 6),
                Text('À: Tout le monde', style: GoogleFonts.poppins(color: Colors.white38, fontSize: 11)),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down, color: Colors.white38, size: 14),
              ]),
            ),
          ),
        Row(children: [
          // Image picker
          GestureDetector(
            onTap: _sendImageMessage,
            child: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08), shape: BoxShape.circle),
              child: const Icon(Icons.image_outlined, color: Colors.white54, size: 18),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _chatController,
              style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessageWithRecipient(),
              decoration: InputDecoration(
                hintText: isDM ? 'Message privé...' : 'Message...',
                hintStyle: GoogleFonts.poppins(color: Colors.white38, fontSize: 13),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.08),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sendMessageWithRecipient,
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                  color: isDM ? Colors.blue.shade700 : AppColors.primary, shape: BoxShape.circle),
              child: const Icon(Icons.send, color: Colors.white, size: 18),
            ),
          ),
        ]),
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
                borderSide: const BorderSide(color: AppColors.primary),
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

  // ── TRANSCRIPT PANEL ─────────────────────────
  Widget _buildTranscriptPanel() {
    final lang = Provider.of<LocaleProvider>(context, listen: false).locale.languageCode;
    final scrollCtrl = ScrollController();

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xCC141420),
            border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.12))),
          ),
          child: Column(children: [
            // ── Header ──────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(children: [
                // Animated mic indicator
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _sttListening ? Colors.red : Colors.white24,
                    boxShadow: _sttListening
                        ? [BoxShadow(color: Colors.red.withValues(alpha: 0.5), blurRadius: 6)]
                        : [],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    AppTranslations.t('subtitles_live', lang),
                    style: GoogleFonts.poppins(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
                // Start/stop button
                if (_sttInitializing)
                  const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                  )
                else
                  GestureDetector(
                    onTap: () => _sttListening ? _stopTranscription() : _startTranscription(),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _sttListening
                            ? Colors.red.withValues(alpha: 0.2)
                            : Colors.green.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _sttListening
                              ? Colors.red.withValues(alpha: 0.6)
                              : Colors.green.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(
                          _sttListening ? Icons.stop : Icons.mic,
                          color: _sttListening ? Colors.red : Colors.green,
                          size: 11,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _sttListening
                              ? AppTranslations.t('stt_stop', lang)
                              : AppTranslations.t('stt_start', lang),
                          style: GoogleFonts.poppins(
                            color: _sttListening ? Colors.red : Colors.green,
                            fontSize: 9, fontWeight: FontWeight.w700,
                          ),
                        ),
                      ]),
                    ),
                  ),
                const SizedBox(width: 8),
                // Clear button
                if (_transcriptLines.isNotEmpty)
                  IconButton(
                    onPressed: () => setState(() { _transcriptLines.clear(); _sttPartialText = null; }),
                    icon: const Icon(Icons.delete_outline, color: Colors.white38, size: 16),
                    padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                    tooltip: 'Effacer',
                  ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: () { _stopTranscription(); setState(() => _showTranscript = false); },
                  icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                  padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                ),
              ]),
            ),
            const Divider(color: Colors.white10, height: 1),

            // ── Transcript content ───────────────────
            Expanded(
              child: _transcriptLines.isEmpty && _sttPartialText == null
                  ? Center(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(
                          _sttListening ? Icons.mic : Icons.mic_none,
                          color: _sttListening
                              ? Colors.green.withValues(alpha: 0.7)
                              : Colors.white24,
                          size: 36,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _sttInitializing
                              ? AppTranslations.t('stt_initializing', lang)
                              : _sttListening
                                  ? AppTranslations.t('stt_listening', lang)
                                  : AppTranslations.t('stt_tap_start', lang),
                          style: GoogleFonts.poppins(color: Colors.white38, fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          AppTranslations.t('stt_will_appear', lang),
                          style: GoogleFonts.poppins(color: Colors.white24, fontSize: 11),
                        ),
                      ]),
                    )
                  : ListView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                      // +1 for partial result row
                      itemCount: _transcriptLines.length + (_sttPartialText != null ? 1 : 0),
                      itemBuilder: (_, i) {
                        // Last item = partial (live) result
                        if (i == _transcriptLines.length && _sttPartialText != null) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: RichText(
                              text: TextSpan(children: [
                                TextSpan(
                                  text: '${widget.userName}: ',
                                  style: GoogleFonts.poppins(
                                      color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w600),
                                ),
                                TextSpan(
                                  text: _sttPartialText!,
                                  style: GoogleFonts.poppins(
                                      color: Colors.white38, fontSize: 13,
                                      height: 1.5, fontStyle: FontStyle.italic),
                                ),
                              ]),
                            ),
                          );
                        }
                        final line = _transcriptLines[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: RichText(
                            text: TextSpan(children: [
                              TextSpan(
                                text: '${line['speaker'] ?? ''}: ',
                                style: GoogleFonts.poppins(
                                    color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                              TextSpan(
                                text: line['text'] ?? '',
                                style: GoogleFonts.poppins(
                                    color: Colors.white70, fontSize: 13, height: 1.5),
                              ),
                            ]),
                          ),
                        );
                      },
                    ),
            ),

            // ── Footer ──────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                const Icon(Icons.info_outline, color: Colors.white24, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    AppTranslations.t('stt_device_only', lang),
                    style: GoogleFonts.poppins(color: Colors.white38, fontSize: 10),
                  ),
                ),
                if (!_isPro)
                  GestureDetector(
                    onTap: _showPaywall,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)]),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        AppTranslations.t('activate_pro', lang),
                        style: GoogleFonts.poppins(
                            color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

// ── DRAWING WHITEBOARD ────────────────────────
  void _listenWhiteboard() {
    if (_wbSyncEnabled) return;
    _wbSyncEnabled = true;
    _whiteboardSub?.cancel();
    _whiteboardSub = _db
        .collection('meetings')
        .doc(widget.meetingId)
        .collection('whiteboard')
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final docs = snap.docs.map((d) => d.data()).toList()
        ..sort((a, b) => ((a['clientTs'] as int? ?? 0).compareTo(b['clientTs'] as int? ?? 0)));
      setState(() {
        _wbElements.clear();
        for (final d in docs) {
          try {
            final type = d['elementType'] as String? ?? 'stroke';
            if (type == 'stroke') {
              final rawPts = d['points'] as List<dynamic>? ?? [];
              final points = rawPts.map((p) => Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble())).toList();
              _wbElements.add(_WbStroke(
                points: points,
                color: Color(d['color'] as int? ?? Colors.black.toARGB32()),
                width: (d['width'] as num? ?? 4).toDouble(),
                isErase: d['isErase'] as bool? ?? false,
              ));
            } else if (type == 'shape') {
              final s = d['start'] as Map?;
              final e = d['end'] as Map?;
              if (s != null && e != null) {
                _wbElements.add(_WbShape(
                  start: Offset((s['x'] as num).toDouble(), (s['y'] as num).toDouble()),
                  end: Offset((e['x'] as num).toDouble(), (e['y'] as num).toDouble()),
                  shapeType: _WbShapeType.values.firstWhere((v) => v.name == (d['shapeType'] as String? ?? 'rect'), orElse: () => _WbShapeType.rect),
                  color: Color(d['color'] as int? ?? Colors.black.toARGB32()),
                  width: (d['width'] as num? ?? 2).toDouble(),
                  filled: d['filled'] as bool? ?? false,
                ));
              }
            } else if (type == 'text') {
              final pos = d['position'] as Map?;
              if (pos != null) {
                _wbElements.add(_WbText(
                  position: Offset((pos['x'] as num).toDouble(), (pos['y'] as num).toDouble()),
                  text: d['text'] as String? ?? '',
                  color: Color(d['color'] as int? ?? Colors.black.toARGB32()),
                  fontSize: (d['fontSize'] as num? ?? 16).toDouble(),
                ));
              }
            }
          } catch (_) {}
        }
      });
    });
  }

  Future<void> _clearWhiteboard() async {
    _whiteboardSub?.cancel();
    _whiteboardSub = null;
    _wbSyncEnabled = false;
    setState(() {
      _wbElements.clear();
      _wbCurrentPoints.clear();
      _wbShapeStart = null;
      _wbUndoHistory.clear();
      _wbRedoHistory.clear();
    });
    try {
      final snap = await _db.collection('meetings').doc(widget.meetingId).collection('whiteboard').get();
      final batch = _db.batch();
      for (final doc in snap.docs) { batch.delete(doc.reference); }
      await batch.commit();
    } catch (_) {} finally {
      _listenWhiteboard();
    }
  }

  Future<void> _saveWbElement(_WbElement element) async {
    try {
      Map<String, dynamic> data = {
        'author': widget.userName,
        'clientTs': DateTime.now().millisecondsSinceEpoch,
        'ts': FieldValue.serverTimestamp(),
      };
      if (element is _WbStroke) {
        if (element.points.isEmpty) return;
        data['elementType'] = 'stroke';
        data['points'] = element.points.map((p) => {'x': p.dx, 'y': p.dy}).toList();
        data['color'] = element.color.toARGB32();
        data['width'] = element.width;
        data['isErase'] = element.isErase;
      } else if (element is _WbShape) {
        data['elementType'] = 'shape';
        data['start'] = {'x': element.start.dx, 'y': element.start.dy};
        data['end'] = {'x': element.end.dx, 'y': element.end.dy};
        data['shapeType'] = element.shapeType.name;
        data['color'] = element.color.toARGB32();
        data['width'] = element.width;
        data['filled'] = element.filled;
      } else if (element is _WbText) {
        data['elementType'] = 'text';
        data['position'] = {'x': element.position.dx, 'y': element.position.dy};
        data['text'] = element.text;
        data['color'] = element.color.toARGB32();
        data['fontSize'] = element.fontSize;
      }
      await _db.collection('meetings').doc(widget.meetingId).collection('whiteboard').add(data);
    } catch (_) {}
  }

  void _wbUndo() {
    if (_wbUndoHistory.isEmpty) return;
    setState(() {
      _wbRedoHistory.add(List.from(_wbElements));
      _wbElements.clear();
      _wbElements.addAll(_wbUndoHistory.removeLast());
    });
  }

  void _wbRedo() {
    if (_wbRedoHistory.isEmpty) return;
    setState(() {
      _wbUndoHistory.add(List.from(_wbElements));
      _wbElements.clear();
      _wbElements.addAll(_wbRedoHistory.removeLast());
    });
  }

  Widget _buildWhiteboardPanel() {
    final isPrivileged = widget.isHost || _isCoHost;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xF0F5F5F5),
            border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.15))),
          ),
          child: Column(children: [
            // ── HEADER ──────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
                ),
              ),
              child: Row(children: [
                const Icon(Icons.draw_rounded, color: Colors.white70, size: 16),
                const SizedBox(width: 8),
                Text('Tableau collaboratif', style: GoogleFonts.poppins(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                const Spacer(),
                // Undo
                _WbIconBtn(icon: Icons.undo_rounded, active: _wbUndoHistory.isNotEmpty, onTap: _wbUndo),
                // Redo
                _WbIconBtn(icon: Icons.redo_rounded, active: _wbRedoHistory.isNotEmpty, onTap: _wbRedo),
                // Export (save as image — shows snackbar since flutter_screenshot not available)
                _WbIconBtn(icon: Icons.download_rounded, active: true, onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Capture d\'écran disponible avec la touche screenshot', style: GoogleFonts.poppins(fontSize: 12)),
                    backgroundColor: const Color(0xFF1A1A2E),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ));
                }),
                if (isPrivileged) ...[
                  const SizedBox(width: 4),
                  _WbIconBtn(icon: Icons.delete_outline, active: true, onTap: _clearWhiteboard, color: Colors.redAccent),
                ],
                const SizedBox(width: 4),
                _WbIconBtn(icon: Icons.close, active: true, onTap: () => setState(() => _showWhiteboard = false)),
              ]),
            ),

            // ── TOOL BAR ROW 1: Tools ────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              color: const Color(0xFF1A1A2E),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _WbToolBtn(icon: Icons.pan_tool_alt_outlined, label: 'Sel', tool: _WbTool.select, current: _wbTool, onTap: (t) => setState(() => _wbTool = t)),
                  _WbToolBtn(icon: Icons.edit_rounded, label: 'Stylo', tool: _WbTool.pen, current: _wbTool, onTap: (t) => setState(() => _wbTool = t)),
                  _WbToolBtn(icon: Icons.horizontal_rule_rounded, label: 'Ligne', tool: _WbTool.line, current: _wbTool, onTap: (t) => setState(() => _wbTool = t)),
                  _WbToolBtn(icon: Icons.arrow_right_alt_rounded, label: 'Flèche', tool: _WbTool.arrow, current: _wbTool, onTap: (t) => setState(() => _wbTool = t)),
                  _WbToolBtn(icon: Icons.rectangle_outlined, label: 'Rect', tool: _WbTool.rect, current: _wbTool, onTap: (t) => setState(() => _wbTool = t)),
                  _WbToolBtn(icon: Icons.circle_outlined, label: 'Cercle', tool: _WbTool.circle, current: _wbTool, onTap: (t) => setState(() => _wbTool = t)),
                  _WbToolBtn(icon: Icons.change_history_outlined, label: 'Tri', tool: _WbTool.triangle, current: _wbTool, onTap: (t) => setState(() => _wbTool = t)),
                  _WbToolBtn(icon: Icons.text_fields_rounded, label: 'Texte', tool: _WbTool.text, current: _wbTool, onTap: (t) => setState(() { _wbTool = t; _showTextInput(); })),
                  _WbToolBtn(icon: Icons.auto_fix_high_rounded, label: 'Efface', tool: _WbTool.eraser, current: _wbTool, onTap: (t) => setState(() => _wbTool = t)),
                  _WbToolBtn(icon: Icons.highlight_rounded, label: 'Laser', tool: _WbTool.laser, current: _wbTool, onTap: (t) => setState(() => _wbTool = t)),
                  // Fill toggle (for shapes)
                  if ([_WbTool.rect, _WbTool.circle, _WbTool.triangle].contains(_wbTool))
                    GestureDetector(
                      onTap: () => setState(() => _wbFilled = !_wbFilled),
                      child: Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _wbFilled ? Colors.white.withValues(alpha: 0.2) : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white38),
                        ),
                        child: Text('Rempli', style: GoogleFonts.poppins(color: Colors.white70, fontSize: 10)),
                      ),
                    ),
                ]),
              ),
            ),

            // ── TOOL BAR ROW 2: Colors + Width ───────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              color: const Color(0xFF16213E),
              child: Row(children: [
                // Colors
                for (final c in const [
                  Color(0xFF000000), Color(0xFFFFFFFF), Color(0xFFEF4444), Color(0xFF3B82F6),
                  Color(0xFF22C55E), Color(0xFFF59E0B), Color(0xFFEC4899), Color(0xFF8B5CF6),
                  Color(0xFF06B6D4), Color(0xFFFF6B35), Color(0xFF84CC16), Color(0xFF6B7280),
                ])
                  GestureDetector(
                    onTap: () => setState(() { _wbColor = c; if (_wbTool == _WbTool.eraser) _wbTool = _WbTool.pen; }),
                    child: Container(
                      width: 20, height: 20,
                      margin: const EdgeInsets.only(right: 5),
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _wbColor == c ? Colors.white : Colors.white24,
                          width: _wbColor == c ? 2.5 : 1,
                        ),
                        boxShadow: _wbColor == c ? [BoxShadow(color: c.withValues(alpha: 0.6), blurRadius: 6)] : null,
                      ),
                    ),
                  ),
                const Spacer(),
                // Stroke widths
                for (final w in [2.0, 4.0, 6.0, 10.0, 16.0])
                  GestureDetector(
                    onTap: () => setState(() => _wbWidth = w),
                    child: Container(
                      width: 24, height: 24,
                      margin: const EdgeInsets.only(left: 4),
                      decoration: BoxDecoration(
                        color: _wbWidth == w ? Colors.white.withValues(alpha: 0.2) : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(color: _wbWidth == w ? Colors.white : Colors.white24),
                      ),
                      child: Center(child: Container(
                        width: w.clamp(2, 14), height: w.clamp(2, 14),
                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      )),
                    ),
                  ),
              ]),
            ),

            // ── CANVAS ──────────────────────────────────────────────
            Expanded(
              child: ClipRect(
                child: GestureDetector(
                  onPanStart: (d) {
                    if (_wbTool == _WbTool.pen || _wbTool == _WbTool.eraser) {
                      setState(() => _wbCurrentPoints.add(d.localPosition));
                    } else if (_wbTool == _WbTool.laser) {
                      _wbLaserTimer?.cancel();
                      setState(() => _wbLaserPos = d.localPosition);
                    } else if ([_WbTool.line, _WbTool.arrow, _WbTool.rect, _WbTool.circle, _WbTool.triangle].contains(_wbTool)) {
                      setState(() { _wbShapeStart = d.localPosition; _wbCurrentPoints.add(d.localPosition); });
                    }
                  },
                  onPanUpdate: (d) {
                    if (_wbTool == _WbTool.pen || _wbTool == _WbTool.eraser) {
                      setState(() => _wbCurrentPoints.add(d.localPosition));
                    } else if (_wbTool == _WbTool.laser) {
                      setState(() => _wbLaserPos = d.localPosition);
                    } else if ([_WbTool.line, _WbTool.arrow, _WbTool.rect, _WbTool.circle, _WbTool.triangle].contains(_wbTool)) {
                      setState(() {
                        if (_wbCurrentPoints.isNotEmpty) { _wbCurrentPoints[_wbCurrentPoints.length - 1] = d.localPosition; }
                        else { _wbCurrentPoints.add(d.localPosition); }
                      });
                    }
                  },
                  onPanEnd: (_) {
                    if (_wbTool == _WbTool.pen || _wbTool == _WbTool.eraser) {
                      final pts = _wbCurrentPoints.whereType<Offset>().toList();
                      if (pts.isNotEmpty) {
                        final el = _WbStroke(
                          points: pts,
                          color: _wbTool == _WbTool.eraser ? Colors.white : _wbColor,
                          width: _wbTool == _WbTool.eraser ? 24.0 : _wbWidth,
                          isErase: _wbTool == _WbTool.eraser,
                        );
                        setState(() {
                          _wbUndoHistory.add(List.from(_wbElements));
                          _wbRedoHistory.clear();
                          _wbElements.add(el);
                          _wbCurrentPoints.clear();
                        });
                        _saveWbElement(el);
                      }
                    } else if (_wbTool == _WbTool.laser) {
                      _wbLaserTimer?.cancel();
                      _wbLaserTimer = Timer(const Duration(milliseconds: 800), () {
                        if (mounted) setState(() => _wbLaserPos = null);
                      });
                    } else if ([_WbTool.line, _WbTool.arrow, _WbTool.rect, _WbTool.circle, _WbTool.triangle].contains(_wbTool)) {
                      if (_wbShapeStart != null && _wbCurrentPoints.isNotEmpty) {
                        final end = _wbCurrentPoints.last;
                        final shapeType = _wbTool == _WbTool.line ? _WbShapeType.line
                          : _wbTool == _WbTool.arrow ? _WbShapeType.arrow
                          : _wbTool == _WbTool.rect ? _WbShapeType.rect
                          : _wbTool == _WbTool.circle ? _WbShapeType.circle
                          : _WbShapeType.triangle;
                        final el = _WbShape(
                          start: _wbShapeStart!,
                          end: end is Offset ? end : _wbShapeStart!,
                          shapeType: shapeType,
                          color: _wbColor,
                          width: _wbWidth,
                          filled: _wbFilled,
                        );
                        setState(() {
                          _wbUndoHistory.add(List.from(_wbElements));
                          _wbRedoHistory.clear();
                          _wbElements.add(el);
                          _wbCurrentPoints.clear();
                          _wbShapeStart = null;
                        });
                        _saveWbElement(el);
                      }
                    }
                  },
                  child: CustomPaint(
                    painter: _WhiteboardPainter(
                      elements: _wbElements,
                      currentPoints: _wbCurrentPoints,
                      currentColor: _wbTool == _WbTool.eraser ? Colors.white : _wbColor,
                      currentWidth: _wbTool == _WbTool.eraser ? 24.0 : _wbWidth,
                      currentTool: _wbTool,
                      shapeStart: _wbShapeStart,
                      laserPos: _wbLaserPos,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _showTextInput() {
    String inputText = '';
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Ajouter du texte', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700)),
        content: TextField(
          autofocus: true,
          style: GoogleFonts.poppins(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Entrez votre texte...',
            hintStyle: GoogleFonts.poppins(color: Colors.white38),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.white24)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.white24)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFFF4081))),
          ),
          onChanged: (v) => inputText = v,
        ),
        actions: [
          TextButton(onPressed: () { setState(() => _wbTool = _WbTool.pen); Navigator.pop(context); },
            child: Text('Annuler', style: GoogleFonts.poppins(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF4081), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () {
              if (inputText.trim().isNotEmpty) {
                final el = _WbText(
                  position: const Offset(100, 100),
                  text: inputText.trim(),
                  color: _wbColor,
                  fontSize: _wbWidth * 4 + 12,
                );
                setState(() {
                  _wbUndoHistory.add(List.from(_wbElements));
                  _wbRedoHistory.clear();
                  _wbElements.add(el);
                  _wbTool = _WbTool.pen;
                });
                _saveWbElement(el);
              }
              Navigator.pop(context);
            },
            child: Text('Ajouter', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ── POLLS ─────────────────────────────────────

  void _listenPolls() {
    _pollsSub?.cancel();
    _pollsSub = _db
        .collection('meetings')
        .doc(widget.meetingId)
        .collection('polls')
        .where('isActive', isEqualTo: true)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _activePolls = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      });
    });
  }

  Future<void> _createPoll(String question, List<String> options) async {
    await _db
        .collection('meetings')
        .doc(widget.meetingId)
        .collection('polls')
        .add({
      'question': question,
      'options': options.map((o) => {'text': o, 'votes': []}).toList(),
      'isActive': true,
      'createdBy': widget.userId,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _votePoll(String pollId, int optionIndex) async {
    if (_myPollVotes[pollId] != null) return;
    setState(() => _myPollVotes[pollId] = optionIndex.toString()); // optimistic
    final ref = _db.collection('meetings').doc(widget.meetingId).collection('polls').doc(pollId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final opts = List<Map<String, dynamic>>.from(snap['options'] as List);
      final votes = List<String>.from(opts[optionIndex]['votes'] as List);
      if (!votes.contains(widget.userId)) votes.add(widget.userId);
      opts[optionIndex] = {...opts[optionIndex], 'votes': votes};
      tx.update(ref, {'options': opts});
    });
  }

  Future<void> _endPoll(String pollId) async {
    await _db.collection('meetings').doc(widget.meetingId).collection('polls').doc(pollId).update({'isActive': false});
  }

  void _showCreatePollDialog() {
    final questionCtrl = TextEditingController();
    final opts = [TextEditingController(), TextEditingController()];
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setSt) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text('Créer un sondage', style: GoogleFonts.poppins(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: questionCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(labelText: 'Question', labelStyle: const TextStyle(color: Colors.white60), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.white24), borderRadius: BorderRadius.circular(8))),
            ),
            const SizedBox(height: 12),
            ...opts.asMap().entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                controller: e.value,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(labelText: 'Option ${e.key + 1}', labelStyle: const TextStyle(color: Colors.white60), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.white24), borderRadius: BorderRadius.circular(8))),
              ),
            )),
            if (opts.length < 4)
              TextButton.icon(
                onPressed: () => setSt(() => opts.add(TextEditingController())),
                icon: const Icon(Icons.add, color: Colors.blueAccent, size: 16),
                label: Text('Ajouter une option', style: GoogleFonts.poppins(color: Colors.blueAccent, fontSize: 13)),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Annuler', style: GoogleFonts.poppins(color: Colors.white60))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            onPressed: () {
              final q = questionCtrl.text.trim();
              final os = opts.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
              if (q.isEmpty || os.length < 2) return;
              _createPoll(q, os);
              Navigator.pop(ctx);
            },
            child: Text('Lancer', style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      )),
    );
  }

  Widget _buildPollsPanel() {
    return Container(
      color: const Color(0xFF0F0F1E),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Text('Sondages', style: GoogleFonts.poppins(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
            const Spacer(),
            if (widget.isHost) IconButton(icon: const Icon(Icons.add_circle_outline, color: Colors.blueAccent), onPressed: _showCreatePollDialog),
            IconButton(icon: const Icon(Icons.close, color: Colors.white60), onPressed: () => setState(() => _showPolls = false)),
          ]),
        ),
        const Divider(color: Colors.white12),
        Expanded(
          child: _activePolls.isEmpty
              ? Center(child: Text('Aucun sondage actif', style: GoogleFonts.poppins(color: Colors.white38, fontSize: 13)))
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _activePolls.length,
                  itemBuilder: (_, i) {
                    final poll = _activePolls[i];
                    final pollId = poll['id'] as String;
                    final opts = List<Map<String, dynamic>>.from(poll['options'] as List);
                    final totalVotes = opts.fold<int>(0, (acc, o) => acc + (o['votes'] as List).length);
                    final myVote = _myPollVotes[pollId];
                    return Card(
                      color: const Color(0xFF1A1A2E),
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(poll['question'] as String, style: GoogleFonts.poppins(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600))),
                            if (widget.isHost) IconButton(icon: const Icon(Icons.stop_circle_outlined, color: Colors.redAccent, size: 18), onPressed: () => _endPoll(pollId), tooltip: 'Terminer'),
                          ]),
                          const SizedBox(height: 8),
                          ...opts.asMap().entries.map((e) {
                            final votes = (e.value['votes'] as List).length;
                            final pct = totalVotes == 0 ? 0.0 : votes / totalVotes;
                            final selected = myVote == e.key.toString();
                            return GestureDetector(
                              onTap: myVote == null ? () => _votePoll(pollId, e.key) : null,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: selected ? Colors.blueAccent : Colors.white24),
                                ),
                                child: Stack(children: [
                                  if (myVote != null) FractionallySizedBox(
                                    widthFactor: pct,
                                    child: Container(height: 36, decoration: BoxDecoration(color: Colors.blueAccent.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(8))),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    child: Row(children: [
                                      Expanded(child: Text(e.value['text'] as String, style: GoogleFonts.poppins(color: Colors.white, fontSize: 13))),
                                      if (myVote != null) Text('$votes (${(pct * 100).round()}%)', style: GoogleFonts.poppins(color: Colors.white60, fontSize: 11)),
                                    ]),
                                  ),
                                ]),
                              ),
                            );
                          }),
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }

  // ── RECORDING & NOISE ─────────────────────────

  Future<void> _toggleLocalRecording() async {
    if (_isRecordingLocally) {
      // ── Stop recording ──────────────────────────
      try {
        await _mediaRecorder?.stop();
      } catch (_) {}
      _mediaRecorder = null;
      _recordingBlinkTimer?.cancel();
      setState(() {
        _isRecordingLocally = false;
        _recordingBlink = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          _recordingPath != null
              ? '🎬 Enregistrement sauvegardé : ${_recordingPath!.split('/').last}'
              : '⏹ Enregistrement arrêté',
          style: GoogleFonts.poppins(),
        ),
        backgroundColor: Colors.grey.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 4),
      ));
      // Update Firestore recording flag
      _db.collection('meetings').doc(widget.meetingId)
          .update({'isRecording': false}).catchError((_) {});
    } else {
      // ── Start recording ─────────────────────────
      try {
        final audioTrack = _localStream?.getAudioTracks().firstOrNull;
        if (audioTrack == null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('❌ Aucune piste audio disponible', style: GoogleFonts.poppins()),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ));
          return;
        }
        final dir = await getApplicationDocumentsDirectory();
        final ts = DateTime.now().millisecondsSinceEpoch;
        _recordingPath = '${dir.path}/crux_rec_${widget.meetingId}_$ts.mp4';
        _mediaRecorder = MediaRecorder();
        await _mediaRecorder!.start(
          _recordingPath!,
          audioChannel: RecorderAudioChannel.INPUT,
          videoTrack: _localStream?.getVideoTracks().firstOrNull,
        );
        setState(() => _isRecordingLocally = true);
        _recordingBlinkTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
          if (mounted) setState(() => _recordingBlink = !_recordingBlink);
        });
        // Update Firestore recording flag
        _db.collection('meetings').doc(widget.meetingId)
            .update({'isRecording': true}).catchError((_) {});
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('🔴 Enregistrement démarré', style: GoogleFonts.poppins()),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 2),
        ));
      } catch (e) {
        setState(() => _isRecordingLocally = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ Erreur enregistrement: $e', style: GoogleFonts.poppins()),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    }
  }

  Future<void> _toggleNoiseCancellation() async {
    setState(() => _noiseCancellation = !_noiseCancellation);
    try {
      final tracks = _localStream?.getAudioTracks() ?? [];
      for (final track in tracks) {
        await track.applyConstraints({'noiseSuppression': _noiseCancellation, 'echoCancellation': _noiseCancellation});
      }
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(_noiseCancellation ? 'Réduction de bruit activée' : 'Réduction de bruit désactivée', style: GoogleFonts.poppins()),
      backgroundColor: _noiseCancellation ? Colors.green : Colors.orange,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 2),
    ));
  }

  void _toggleSpotlight(String userId) {
    setState(() => _spotlightUserId = _spotlightUserId == userId ? null : userId);
  }

  // ── FEATURE 1: Kick listener ──────────────────
  void _listenKickSignal() {
    _kickSub?.cancel();
    _kickSub = _db
        .collection('meetings')
        .doc(widget.meetingId)
        .collection('kickSignals')
        .doc(widget.userId)
        .snapshots()
        .listen((snap) {
      if (!snap.exists || !mounted) return;
      final kicked = snap.data()?['kicked'] as bool? ?? false;
      if (kicked) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Vous avez été retiré de la réunion',
              style: GoogleFonts.poppins(color: Colors.white)),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 4),
        ));
        _leave();
      }
    });
  }

  Future<void> _kickParticipant(String pId, String pName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Retirer $pName ?',
            style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700)),
        content: Text('Ce participant sera retiré de la réunion.',
            style: GoogleFonts.poppins(color: Colors.white60, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('Annuler', style: GoogleFonts.poppins(color: Colors.white38))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Retirer', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _db.collection('meetings').doc(widget.meetingId)
          .collection('kickSignals').doc(pId).set({'kicked': true});
    } catch (_) {}
  }

  // ── FEATURE 2: Mute individual ────────────────
  void _listenMuteSignal() {
    _muteSub?.cancel();
    _muteSub = _db
        .collection('meetings')
        .doc(widget.meetingId)
        .collection('muteSignals')
        .doc(widget.userId)
        .snapshots()
        .listen((snap) {
      if (!snap.exists || !mounted) return;
      final muteSignal = snap.data()?['muteSignal'] as bool? ?? false;
      if (muteSignal) {
        for (final t in _localStream?.getAudioTracks() ?? []) {
          t.enabled = false;
        }
        if (mounted) {
          setState(() => _micOn = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Votre micro a été coupé par l\'hôte',
                style: GoogleFonts.poppins(color: Colors.white)),
            backgroundColor: Colors.orange.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 3),
          ));
        }
        // Clear the signal
        _db.collection('meetings').doc(widget.meetingId)
            .collection('muteSignals').doc(widget.userId)
            .set({'muteSignal': false}).catchError((_) {});
      }
    });
  }

  Future<void> _muteParticipant(String pId) async {
    try {
      await _db.collection('meetings').doc(widget.meetingId)
          .collection('muteSignals').doc(pId)
          .set({'muteSignal': true, 'timestamp': FieldValue.serverTimestamp()});
    } catch (_) {}
  }

  // ── FEATURE 3: Rename participant ─────────────
  Future<void> _renameParticipant(String pId, String currentName) async {
    final ctrl = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Renommer le participant',
            style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          style: GoogleFonts.poppins(color: Colors.white),
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Nouveau nom',
            hintStyle: GoogleFonts.poppins(color: Colors.white38),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.08),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: Text('Annuler', style: GoogleFonts.poppins(color: Colors.white38))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text('Renommer', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (newName == null || newName.isEmpty) return;
    try {
      await _db.collection('meetings').doc(widget.meetingId)
          .collection('presence').doc(pId).update({'name': newName});
      if (mounted) setState(() => _participantNames[pId] = newName);
    } catch (_) {}
  }

  // ── FEATURE 4: Transfer host ──────────────────
  Future<void> _transferHost(String pId, String pName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Transférer le rôle hôte ?',
            style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700)),
        content: Text('Transférer le rôle hôte à $pName ?',
            style: GoogleFonts.poppins(color: Colors.white60, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('Annuler', style: GoogleFonts.poppins(color: Colors.white38))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Transférer', style: GoogleFonts.poppins(color: Colors.black, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _db.collection('meetings').doc(widget.meetingId)
          .update({'hostId': pId});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Rôle hôte transféré à $pName',
            style: GoogleFonts.poppins(color: Colors.white)),
        backgroundColor: Colors.amber.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ));
    } catch (_) {}
  }

  // ── FEATURE 5: Waiting room ───────────────────
  void _listenWaitingRoom() {
    _waitingSub?.cancel();
    _waitingSub = _db
        .collection('meetings')
        .doc(widget.meetingId)
        .collection('waitingRoom')
        .where('status', isEqualTo: 'waiting')
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _waitingList = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      });
    });
  }

  Future<void> _admitParticipant(String uid) async {
    try {
      await _db.collection('meetings').doc(widget.meetingId)
          .collection('waitingRoom').doc(uid).update({'status': 'admitted'});
    } catch (_) {}
  }

  Future<void> _denyParticipant(String uid) async {
    try {
      await _db.collection('meetings').doc(widget.meetingId)
          .collection('waitingRoom').doc(uid).update({'status': 'denied'});
    } catch (_) {}
  }

  Future<void> _toggleWaitingRoom() async {
    final next = !_waitingRoomEnabled;
    try {
      await _db.collection('meetings').doc(widget.meetingId)
          .update({'waitingRoomEnabled': next});
      if (mounted) {
        setState(() => _waitingRoomEnabled = next);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(next ? 'Salle d\'attente activée' : 'Salle d\'attente désactivée',
              style: GoogleFonts.poppins(color: Colors.white)),
          backgroundColor: next ? Colors.green.shade700 : Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (_) {}
  }

  // ── FEATURE 6: Passcode ───────────────────────
  Future<void> _showSetPasscodeDialog() async {
    final ctrl = TextEditingController(text: _meetingPasscode ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Code d\'accès',
            style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          style: GoogleFonts.poppins(color: Colors.white),
          keyboardType: TextInputType.number,
          maxLength: 8,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '4-8 chiffres',
            hintStyle: GoogleFonts.poppins(color: Colors.white38),
            prefixIcon: const Icon(Icons.lock, color: Colors.amber),
            counterStyle: GoogleFonts.poppins(color: Colors.white38),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.08),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: Text('Annuler', style: GoogleFonts.poppins(color: Colors.white38))),
          if (_meetingPasscode != null)
            TextButton(onPressed: () => Navigator.pop(ctx, ''),
                child: Text('Supprimer', style: GoogleFonts.poppins(color: Colors.red))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text('Définir', style: GoogleFonts.poppins(color: Colors.black, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null) return;
    try {
      await _db.collection('meetings').doc(widget.meetingId)
          .update({'passcode': result.isEmpty ? FieldValue.delete() : result});
      if (mounted) setState(() => _meetingPasscode = result.isEmpty ? null : result);
    } catch (_) {}
  }

  // ── FEATURE 9: HD Toggle ──────────────────────
  Future<void> _toggleHD() async {
    final next = !_hdEnabled;
    setState(() => _hdEnabled = next);
    if (next) {
      await _applyVideoQuality(_VideoQuality.hd);
    } else {
      await _applyVideoQuality(_VideoQuality.medium);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(next ? 'Vidéo HD activée (1080p)' : 'Vidéo HD désactivée',
          style: GoogleFonts.poppins(color: Colors.white)),
      backgroundColor: next ? Colors.blue.shade700 : Colors.grey,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 2),
    ));
  }

  // ── FEATURE 10: Speaker toggle ────────────────
  void _toggleSpeaker() {
    HapticFeedback.selectionClick();
    final next = !_speakerOn;
    setState(() => _speakerOn = next);
    try {
      Helper.setSpeakerphoneOn(next);
    } catch (_) {}
  }

  // ── FEATURE 12: Image in chat ─────────────────
  Future<void> _sendImageMessage() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery, imageQuality: 60, maxWidth: 800);
      if (picked == null) return;
      final bytes = await File(picked.path).readAsBytes();
      final base64Str = base64Encode(bytes);
      await _db.collection('meetings').doc(widget.meetingId)
          .collection('chat').add({
        'sender': widget.userName,
        'senderId': widget.userId,
        'imageBase64': base64Str,
        'timestamp': FieldValue.serverTimestamp(),
        if (_chatRecipientId != null) 'recipientId': _chatRecipientId,
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erreur envoi image', style: GoogleFonts.poppins()),
        backgroundColor: Colors.red,
      ));
    }
  }

  // ── FEATURE 13: Message reactions ────────────
  Future<void> _toggleMessageReaction(String docId, String emoji) async {
    try {
      final ref = _db.collection('meetings').doc(widget.meetingId)
          .collection('chat').doc(docId);
      final snap = await ref.get();
      if (!snap.exists) return;
      final reactions = Map<String, dynamic>.from(snap.data()?['reactions'] ?? {});
      final users = List<String>.from(reactions[emoji] ?? []);
      if (users.contains(widget.userId)) {
        users.remove(widget.userId);
      } else {
        users.add(widget.userId);
      }
      reactions[emoji] = users;
      await ref.update({'reactions': reactions});
    } catch (_) {}
  }

  // Delegates to the real MediaRecorder implementation
  void _toggleLocalRecordingWithSync() => _toggleLocalRecording();

  // ── FEATURE 11+12: Send message with recipient + DM selector ──
  void _sendMessageWithRecipient() {
    final text = _chatController.text.trim();
    if (text.isEmpty || text.length > _maxMessageLength) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Message: 1-$_maxMessageLength caractères', style: GoogleFonts.poppins()),
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
    _db.collection('meetings').doc(widget.meetingId)
        .collection('chat').add({
      'sender': widget.userName,
      'senderId': widget.userId,
      'message': text,
      'timestamp': FieldValue.serverTimestamp(),
      if (_chatRecipientId != null) 'recipientId': _chatRecipientId,
      if (_chatRecipient != null) 'recipientName': _chatRecipient,
    });
  }

  void _showRecipientSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          Text('Envoyer à...', style: GoogleFonts.poppins(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.people, color: Colors.white70),
            title: Text('Tout le monde', style: GoogleFonts.poppins(color: Colors.white)),
            trailing: _chatRecipientId == null
                ? const Icon(Icons.check_circle, color: AppColors.primary) : null,
            onTap: () {
              setState(() { _chatRecipient = null; _chatRecipientId = null; });
              Navigator.pop(context);
            },
          ),
          ..._presenceList.where((p) => p['userId'] != widget.userId).map((p) {
            final pId = p['userId'] as String? ?? '';
            final pName = _participantNames[pId] ?? (p['name'] as String? ?? 'Participant');
            return ListTile(
              leading: Container(
                width: 36, height: 36,
                decoration: const BoxDecoration(gradient: AppColors.primaryGradient, shape: BoxShape.circle),
                child: Center(child: Text(pName[0].toUpperCase(),
                    style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700))),
              ),
              title: Text(pName, style: GoogleFonts.poppins(color: Colors.white)),
              trailing: _chatRecipientId == pId
                  ? const Icon(Icons.check_circle, color: AppColors.primary) : null,
              onTap: () {
                setState(() { _chatRecipient = pName; _chatRecipientId = pId; });
                Navigator.pop(context);
              },
            );
          }),
        ]),
      ),
    );
  }

  // ── Feature N8+N13: Message action sheet ─────
  void _showMessageActionSheet(String docId) {
    const quickEmojis = ['👍', '❤️', '😂', '😮', '😢', '🔥'];
    final isStarred = _starredMessageIds.contains(docId);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: quickEmojis.map((e) => GestureDetector(
              onTap: () {
                Navigator.pop(context);
                _toggleMessageReaction(docId, e);
              },
              child: Text(e, style: const TextStyle(fontSize: 32)),
            )).toList(),
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: Icon(isStarred ? Icons.star : Icons.star_outline, color: Colors.amber),
            title: Text(isStarred ? 'Retirer des sauvegardés' : 'Sauvegarder le message',
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 14)),
            onTap: () {
              Navigator.pop(context);
              _toggleStarMessage(docId);
            },
          ),
        ]),
      ),
    );
  }

  // ── Feature N8: Starred messages view ────────
  Widget _buildStarredMessages() {
    return StreamBuilder<QuerySnapshot>(
      stream: _db.collection('meetings').doc(widget.meetingId)
          .collection('chat').orderBy('timestamp', descending: true).limit(100).snapshots(),
      builder: (ctx, snap) {
        final docs = snap.data?.docs ?? [];
        final starred = docs.where((d) => _starredMessageIds.contains(d.id)).toList();
        if (starred.isEmpty) {
          return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.star_outline, color: Colors.white24, size: 40),
            const SizedBox(height: 8),
            Text('Aucun message sauvegardé', style: GoogleFonts.poppins(color: Colors.white38, fontSize: 13)),
            const SizedBox(height: 4),
            Text('Appuyez longuement sur un message pour le sauvegarder',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(color: Colors.white24, fontSize: 11)),
          ]));
        }
        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: starred.length,
          itemBuilder: (_, i) {
            final doc = starred[i];
            final d = doc.data()! as Map<String, dynamic>;
            final isMine = d['sender'] == widget.userName;
            final text = d['message'] as String? ?? '';
            final sender = d['sender'] as String? ?? '';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
                children: [
                  Flexible(
                    child: Container(
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(ctx).size.width * 0.65),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isMine ? AppColors.primary : Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        if (!isMine) Text(sender, style: GoogleFonts.poppins(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w600)),
                        Text(text, style: GoogleFonts.poppins(color: Colors.white, fontSize: 13)),
                        const SizedBox(height: 2),
                        const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.star, color: Colors.amber, size: 10),
                          SizedBox(width: 3),
                          Text('Sauvegardé', style: TextStyle(color: Colors.amber, fontSize: 9)),
                        ]),
                      ]),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── FEATURE 16: Full emoji picker ─────────────
  void _showFullEmojiPicker() {
    const allEmojis = [
      '👍','❤️','😂','🎉','😮','👏','🙏','🔥','😢','💯','🎊','✨',
      '😍','🤩','😆','🤣','😭','😡','🥳','🫶','🫡','💪','🤝','✌️',
      '🌟','⚡','💥','🌈','🍀','🎯','🏆','👑','💎','🎵','🎶','🎸',
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: 320,
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          Text('Réactions', style: GoogleFonts.poppins(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8, mainAxisSpacing: 8, crossAxisSpacing: 8,
              ),
              itemCount: allEmojis.length,
              itemBuilder: (_, i) => GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  _sendReaction(allEmojis[i]);
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(child: Text(allEmojis[i], style: const TextStyle(fontSize: 22))),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ── AI SUMMARY ────────────────────────────────

  void _generateMeetingSummary() {
    if (_transcriptLines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Aucune transcription disponible — activez les sous-titres d\'abord', style: GoogleFonts.poppins()),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      return;
    }

    final durationMin = _callSeconds ~/ 60;
    final durationSec = _callSeconds % 60;
    final allText = _transcriptLines.map((l) => (l['text'] ?? '').toString()).join(' ');

    // Word frequency analysis (stop-words excluded)
    final stopWords = {'le','la','les','de','du','un','une','des','et','en','est','à','que','qui','je','tu','il','elle','nous','vous','ils','elles','pas','plus','par','sur','avec','pour','dans','se','ce','ne','on','au','aux','son','sa','ses','leur','mais','ou','donc','or','ni','si','très','bien','comme','tout','tous','toutes','être','avoir','faire','dit','dire','aussi','même','encore','quand','puis','après','avant','sous','entre','sans','lors','dont','quoi','quel','quelle','était','été','peut','cette','cela','lui','ceci'};
    final words = <String, int>{};
    for (final w in allText.toLowerCase().split(RegExp(r'\s+'))) {
      final clean = w.replaceAll(RegExp(r'[^\wÀ-ÿ]'), '');
      if (clean.length > 3 && !stopWords.contains(clean)) {
        words[clean] = (words[clean] ?? 0) + 1;
      }
    }
    final topWords = (words.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
        .take(8).map((e) => e.key).toList();

    // Detect questions (lines ending with ?)
    final questions = _transcriptLines
        .where((l) => (l['text'] ?? '').toString().trim().endsWith('?'))
        .map((l) => '• ${l['speaker'] ?? 'Participant'}: ${l['text']}')
        .take(5)
        .toList();

    // Detect action items (lines containing action keywords)
    final actionKeywords = RegExp(r'\b(faut|devons|devez|doit|doivent|prévu|prévoir|prévoyons|action|objectif|tâche|mission|deadline|livraison|rapport|envoyer|appeler|contacter|vérifier|terminer|préparer|organiser|planifier)\b', caseSensitive: false);
    final actions = _transcriptLines
        .where((l) => actionKeywords.hasMatch((l['text'] ?? '').toString()))
        .map((l) => '• ${l['text']}')
        .take(5)
        .toList();

    // Per-speaker word count
    final speakerCounts = <String, int>{};
    for (final l in _transcriptLines) {
      final spk = (l['speaker'] ?? 'Inconnu').toString();
      speakerCounts[spk] = (speakerCounts[spk] ?? 0) + 1;
    }
    final sortedSpeakers = speakerCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final summary = StringBuffer();
    summary.writeln('📋 RÉSUMÉ DE RÉUNION');
    summary.writeln('─' * 30);
    summary.writeln('⏱ Durée : $durationMin min $durationSec s');
    summary.writeln('👥 Participants : ${_participantNames.length + 1}');
    summary.writeln('🗣 Interventions : ${_transcriptLines.length}');
    summary.writeln('');

    summary.writeln('🔑 Sujets principaux :');
    summary.writeln('  ${topWords.join(' • ')}');
    summary.writeln('');

    if (sortedSpeakers.isNotEmpty) {
      summary.writeln('🎙 Prise de parole :');
      for (final e in sortedSpeakers.take(5)) {
        final pct = (_transcriptLines.isNotEmpty
            ? (e.value / _transcriptLines.length * 100).round()
            : 0);
        summary.writeln('  ${e.key}: ${e.value} interventions ($pct%)');
      }
      summary.writeln('');
    }

    if (questions.isNotEmpty) {
      summary.writeln('❓ Questions posées :');
      for (final q in questions) { summary.writeln(q); }
      summary.writeln('');
    }

    if (actions.isNotEmpty) {
      summary.writeln('✅ Points d\'action détectés :');
      for (final a in actions) { summary.writeln(a); }
      summary.writeln('');
    }

    summary.writeln('─' * 30);
    summary.writeln('Généré par CRUX • ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}');

    setState(() => _meetingSummary = summary.toString());
    _showSummaryDialog();
  }

  void _showSummaryDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Row(children: [
          const Icon(Icons.auto_awesome, color: Colors.amber, size: 20),
          const SizedBox(width: 8),
          Text('Résumé IA', style: GoogleFonts.poppins(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        ]),
        content: SingleChildScrollView(
          child: Text(_meetingSummary ?? '', style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13, height: 1.6)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Fermer', style: GoogleFonts.poppins(color: Colors.white60))),
        ],
      ),
    );
  }

  // ── CAMERA FILTER HELPERS ─────────────────────

  static List<double> _filterMatrix(_CameraFilter f) {
    switch (f) {
      case _CameraFilter.warm:
        return [
          1.2, 0.0, 0.0, 0.0, 10,
          0.0, 1.05, 0.0, 0.0, 5,
          0.0, 0.0, 0.85, 0.0, -10,
          0.0, 0.0, 0.0, 1.0, 0,
        ];
      case _CameraFilter.cool:
        return [
          0.85, 0.0, 0.0, 0.0, -5,
          0.0, 1.0, 0.0, 0.0, 5,
          0.0, 0.0, 1.2, 0.0, 15,
          0.0, 0.0, 0.0, 1.0, 0,
        ];
      case _CameraFilter.vivid:
        return [
          1.4, -0.1, -0.1, 0.0, 10,
          -0.1, 1.4, -0.1, 0.0, 10,
          -0.1, -0.1, 1.4, 0.0, 10,
          0.0, 0.0, 0.0, 1.0, 0,
        ];
      case _CameraFilter.bw:
        return [
          0.33, 0.59, 0.11, 0.0, 0,
          0.33, 0.59, 0.11, 0.0, 0,
          0.33, 0.59, 0.11, 0.0, 0,
          0.0, 0.0, 0.0, 1.0, 0,
        ];
      case _CameraFilter.soft:
        return [
          0.9, 0.05, 0.05, 0.0, 10,
          0.05, 0.9, 0.05, 0.0, 10,
          0.05, 0.05, 0.9, 0.0, 10,
          0.0, 0.0, 0.0, 1.0, 0,
        ];
      case _CameraFilter.natural:
        return [
          1, 0, 0, 0, 0,
          0, 1, 0, 0, 0,
          0, 0, 1, 0, 0,
          0, 0, 0, 1, 0,
        ];
    }
  }

  Widget _buildLocalVideoView({RTCVideoViewObjectFit objectFit = RTCVideoViewObjectFit.RTCVideoViewObjectFitCover}) {
    final view = RTCVideoView(_localRenderer, mirror: _mirrorVideo, objectFit: objectFit);
    Widget filtered = _cameraFilter == _CameraFilter.natural
        ? view
        : ColorFiltered(colorFilter: ColorFilter.matrix(_filterMatrix(_cameraFilter)), child: view);
    // Feature N7: Low-light brightness boost
    if (_lowLightMode) {
      filtered = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          1.5, 0, 0, 0, 30,
          0, 1.5, 0, 0, 30,
          0, 0, 1.5, 0, 30,
          0, 0, 0, 1, 0,
        ]),
        child: filtered,
      );
    }
    if (!_hdEnabled) return filtered;
    // HD badge overlay
    return Stack(children: [
      filtered,
      Positioned(
        bottom: 8, left: 8,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(color: Colors.blue.shade700, borderRadius: BorderRadius.circular(4)),
          child: Text('HD', style: GoogleFonts.poppins(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
        ),
      ),
    ]);
  }

  void _showFiltersPanel() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final filters = [
            (_CameraFilter.natural, '🌿', 'Naturel'),
            (_CameraFilter.warm, '🌅', 'Chaud'),
            (_CameraFilter.cool, '❄️', 'Froid'),
            (_CameraFilter.vivid, '🌈', 'Vivid'),
            (_CameraFilter.bw, '⬛', 'N&B'),
            (_CameraFilter.soft, '🌸', 'Doux'),
          ];
          return Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A2E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 16),
              Text('Filtres Caméra',
                style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: filters.map((t) {
                  final (filter, emoji, label) = t;
                  final selected = _cameraFilter == filter;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _cameraFilter = filter);
                      setLocal(() {});
                    },
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected ? const Color(0xFFFF4081).withValues(alpha: 0.25) : Colors.white10,
                          border: Border.all(
                            color: selected ? const Color(0xFFFF4081) : Colors.white24,
                            width: selected ? 2 : 1,
                          ),
                        ),
                        child: Center(
                          child: Text(emoji, style: const TextStyle(fontSize: 24)),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(label,
                        style: GoogleFonts.poppins(
                          color: selected ? const Color(0xFFFF4081) : Colors.white60,
                          fontSize: 11,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                        )),
                    ]),
                  );
                }).toList(),
              ),
            ]),
          );
        },
      ),
    );
  }

  // ════════════════════════════════════════════
  // FEATURE N1: Q&A
  // ════════════════════════════════════════════

  void _listenQA() {
    _qaSub?.cancel();
    _qaSub = _db
        .collection('meetings')
        .doc(widget.meetingId)
        .collection('qa')
        .orderBy('votes', descending: true)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _qaList = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      });
    });
  }

  Future<void> _submitQuestion(String text) async {
    if (text.trim().isEmpty) return;
    try {
      await _db.collection('meetings').doc(widget.meetingId).collection('qa').add({
        'question': text.trim(),
        'askedBy': widget.userName,
        'askedById': widget.userId,
        'votes': 0,
        'voterIds': <String>[],
        'answered': false,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<void> _upvoteQuestion(String qaId) async {
    if (_myQAUpvotes.contains(qaId)) return;
    setState(() => _myQAUpvotes.add(qaId));
    try {
      final ref = _db.collection('meetings').doc(widget.meetingId).collection('qa').doc(qaId);
      await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) return;
        final voterIds = List<String>.from(snap['voterIds'] as List? ?? []);
        if (voterIds.contains(widget.userId)) return;
        voterIds.add(widget.userId);
        tx.update(ref, {'votes': (snap['votes'] as int? ?? 0) + 1, 'voterIds': voterIds});
      });
    } catch (_) {
      setState(() => _myQAUpvotes.remove(qaId));
    }
  }

  Future<void> _markAnswered(String qaId) async {
    try {
      await _db.collection('meetings').doc(widget.meetingId).collection('qa').doc(qaId)
          .update({'answered': true});
    } catch (_) {}
  }

  Widget _buildQAPanel() {
    final isPrivileged = widget.isHost || _isCoHost;
    final qCtrl = TextEditingController();
    final unanswered = _qaList.where((q) => q['answered'] != true).toList();
    final answered = _qaList.where((q) => q['answered'] == true).toList();
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xCC181828),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 0.5)),
        ),
        child: Column(children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(children: [
              const Icon(Icons.quiz_outlined, color: Colors.white70, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text('Questions & Réponses',
                  style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15))),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white54, size: 22),
                onPressed: () => setState(() => _showQA = false),
              ),
            ]),
          ),
          // Input row
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: StatefulBuilder(builder: (ctx, setLocal) {
              return Row(children: [
                Expanded(
                  child: TextField(
                    controller: qCtrl,
                    style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Posez votre question...',
                      hintStyle: GoogleFonts.poppins(color: Colors.white38, fontSize: 12),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.08),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    _submitQuestion(qCtrl.text);
                    qCtrl.clear();
                  },
                  child: Container(
                    width: 38, height: 38,
                    decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                    child: const Icon(Icons.send, color: Colors.white, size: 16),
                  ),
                ),
              ]);
            }),
          ),
          const Divider(color: Colors.white12, height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                ...unanswered.map((q) => _buildQACard(q, isPrivileged, false)),
                if (answered.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('Répondues', style: GoogleFonts.poppins(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
                  ...answered.map((q) => _buildQACard(q, isPrivileged, true)),
                ],
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildQACard(Map<String, dynamic> q, bool isPrivileged, bool isAnswered) {
    final qaId = q['id'] as String? ?? '';
    final question = q['question'] as String? ?? '';
    final askedBy = q['askedBy'] as String? ?? '';
    final votes = q['votes'] as int? ?? 0;
    final alreadyUpvoted = _myQAUpvotes.contains(qaId);
    return Opacity(
      opacity: isAnswered ? 0.55 : 1.0,
      child: Card(
        color: const Color(0xFF1E1E30),
        margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(question, style: GoogleFonts.poppins(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600))),
              if (isAnswered)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.green.withValues(alpha: 0.5))),
                  child: Text('✓ Répondu', style: GoogleFonts.poppins(color: Colors.green, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
            ]),
            const SizedBox(height: 4),
            Text('— $askedBy', style: GoogleFonts.poppins(color: Colors.white38, fontSize: 11)),
            const SizedBox(height: 8),
            Row(children: [
              GestureDetector(
                onTap: alreadyUpvoted ? null : () => _upvoteQuestion(qaId),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: alreadyUpvoted ? AppColors.primary.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: alreadyUpvoted ? AppColors.primary : Colors.white24),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.thumb_up_outlined, color: alreadyUpvoted ? AppColors.primary : Colors.white54, size: 13),
                    const SizedBox(width: 5),
                    Text('$votes', style: GoogleFonts.poppins(color: alreadyUpvoted ? AppColors.primary : Colors.white54, fontSize: 12, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
              const Spacer(),
              if (isPrivileged && !isAnswered)
                GestureDetector(
                  onTap: () => _markAnswered(qaId),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.green.withValues(alpha: 0.5))),
                    child: Text('Marquer répondu', style: GoogleFonts.poppins(color: Colors.green, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ),
            ]),
          ]),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════
  // FEATURE N2: Attendance
  // ════════════════════════════════════════════

  void _listenAttendance() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setLocal) {
        _db.collection('meetings').doc(widget.meetingId)
            .collection('attendance').snapshots().listen((snap) {
          if (!ctx2.mounted) return;
          setLocal(() {
            _attendanceLog = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
          });
        });
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(children: [
            const Icon(Icons.checklist, color: Colors.white70, size: 20),
            const SizedBox(width: 8),
            Text('Présences', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
          ]),
          content: SizedBox(
            width: double.maxFinite,
            child: _attendanceLog.isEmpty
                ? Text('Aucune présence enregistrée', style: GoogleFonts.poppins(color: Colors.white38))
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _attendanceLog.length,
                    itemBuilder: (_, i) {
                      final entry = _attendanceLog[i];
                      final name = entry['name'] as String? ?? 'Inconnu';
                      final joinedTs = entry['joinedAt'];
                      final leftTs = entry['leftAt'];
                      final joined = joinedTs is Timestamp ? joinedTs.toDate() : null;
                      final left = leftTs is Timestamp ? leftTs.toDate() : null;
                      Duration? dur;
                      if (joined != null && left != null) dur = left.difference(joined);
                      final durStr = dur != null
                          ? '${dur.inMinutes}m ${dur.inSeconds.remainder(60)}s'
                          : (joined != null ? 'En réunion' : '');
                      return ListTile(
                        dense: true,
                        leading: Container(
                          width: 32, height: 32,
                          decoration: const BoxDecoration(gradient: AppColors.primaryGradient, shape: BoxShape.circle),
                          child: Center(child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))),
                        ),
                        title: Text(name, style: GoogleFonts.poppins(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          joined != null
                              ? 'Entrée: ${joined.hour}:${joined.minute.toString().padLeft(2, '0')}'
                              : '',
                          style: GoogleFonts.poppins(color: Colors.white38, fontSize: 10),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: left != null ? Colors.grey.withValues(alpha: 0.2) : Colors.green.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(durStr, style: GoogleFonts.poppins(color: left != null ? Colors.grey : Colors.green, fontSize: 10, fontWeight: FontWeight.w700)),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Fermer', style: GoogleFonts.poppins(color: Colors.white60))),
          ],
        );
      }),
    );
  }

  // ════════════════════════════════════════════
  // FEATURE N3: Turn off participant camera
  // ════════════════════════════════════════════

  Future<void> _sendCamOffSignal(String participantId) async {
    try {
      await _db.collection('meetings').doc(widget.meetingId)
          .collection('camOffSignals').doc(participantId)
          .set({'camOff': true, 'timestamp': FieldValue.serverTimestamp()});
    } catch (_) {}
  }

  // ════════════════════════════════════════════
  // FEATURE N4: Host controls sheet
  // ════════════════════════════════════════════

  void _showHostControlsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(builder: (ctx, setLocal) {
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          decoration: const BoxDecoration(
            color: Color(0xFF181828),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.shield_outlined, color: Colors.purple, size: 20),
              const SizedBox(width: 8),
              Text('Contrôles de la réunion', style: GoogleFonts.poppins(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 8),
            SwitchListTile(
              title: Text('Autoriser le chat', style: GoogleFonts.poppins(color: Colors.white, fontSize: 14)),
              subtitle: Text('Les participants peuvent envoyer des messages', style: GoogleFonts.poppins(color: Colors.white38, fontSize: 11)),
              value: _allowParticipantChat,
              // ignore: deprecated_member_use
              activeColor: AppColors.primary,
              onChanged: (v) async {
                setState(() => _allowParticipantChat = v);
                setLocal(() {});
                try { await _db.collection('meetings').doc(widget.meetingId).update({'allowChat': v}); } catch (_) {}
              },
            ),
            SwitchListTile(
              title: Text('Autoriser les réactions', style: GoogleFonts.poppins(color: Colors.white, fontSize: 14)),
              subtitle: Text('Les participants peuvent envoyer des emojis', style: GoogleFonts.poppins(color: Colors.white38, fontSize: 11)),
              value: _allowParticipantReactions,
              // ignore: deprecated_member_use
              activeColor: AppColors.primary,
              onChanged: (v) async {
                setState(() => _allowParticipantReactions = v);
                setLocal(() {});
                try { await _db.collection('meetings').doc(widget.meetingId).update({'allowReactions': v}); } catch (_) {}
              },
            ),
            SwitchListTile(
              title: Text('Autoriser le partage d\'écran', style: GoogleFonts.poppins(color: Colors.white, fontSize: 14)),
              subtitle: Text('Les participants peuvent partager leur écran', style: GoogleFonts.poppins(color: Colors.white38, fontSize: 11)),
              value: _allowParticipantScreenShare,
              // ignore: deprecated_member_use
              activeColor: AppColors.primary,
              onChanged: (v) async {
                setState(() => _allowParticipantScreenShare = v);
                setLocal(() {});
                try { await _db.collection('meetings').doc(widget.meetingId).update({'allowScreenShare': v}); } catch (_) {}
              },
            ),
            SwitchListTile(
              title: Text('Couper micro à l\'entrée', style: GoogleFonts.poppins(color: Colors.white, fontSize: 14)),
              subtitle: Text('Les nouveaux participants arrivent muets', style: GoogleFonts.poppins(color: Colors.white38, fontSize: 11)),
              value: _muteOnEntry,
              // ignore: deprecated_member_use
              activeColor: Colors.orange,
              onChanged: (v) async {
                setState(() => _muteOnEntry = v);
                setLocal(() {});
                try { await _db.collection('meetings').doc(widget.meetingId).update({'muteOnEntry': v}); } catch (_) {}
              },
            ),
          ]),
        );
      }),
    );
  }

  // ════════════════════════════════════════════
  // FEATURE N6: Agenda panel
  // ════════════════════════════════════════════

  Widget _buildAgendaPanel() {
    final isPrivileged = widget.isHost || _isCoHost;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xCC181828),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 0.5)),
        ),
        child: Column(children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(children: [
              const Icon(Icons.notes, color: Colors.white70, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text('Ordre du jour',
                  style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15))),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white54, size: 22),
                onPressed: () => setState(() => _showAgendaPanel = false),
              ),
            ]),
          ),
          const Divider(color: Colors.white12, height: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: isPrivileged
                  ? Column(children: [
                      Expanded(
                        child: TextField(
                          controller: _agendaController,
                          style: GoogleFonts.poppins(color: Colors.white, fontSize: 13, height: 1.6),
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          decoration: InputDecoration(
                            hintText: 'Entrez l\'ordre du jour de la réunion...',
                            hintStyle: GoogleFonts.poppins(color: Colors.white38, fontSize: 13),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.05),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white12)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white12)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary)),
                            contentPadding: const EdgeInsets.all(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            try {
                              await _db.collection('meetings').doc(widget.meetingId)
                                  .update({'agenda': _agendaController.text});
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text('Ordre du jour enregistré', style: GoogleFonts.poppins()),
                                backgroundColor: AppColors.success,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                duration: const Duration(seconds: 2),
                              ));
                            } catch (_) {}
                          },
                          icon: const Icon(Icons.save_outlined, size: 16),
                          label: Text('Enregistrer', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ])
                  : SingleChildScrollView(
                      child: Text(
                        _meetingAgenda.isEmpty ? 'Aucun ordre du jour défini.' : _meetingAgenda,
                        style: GoogleFonts.poppins(color: _meetingAgenda.isEmpty ? Colors.white38 : Colors.white70, fontSize: 13, height: 1.6),
                      ),
                    ),
            ),
          ),
        ]),
      ),
    );
  }

  // ════════════════════════════════════════════
  // FEATURE N8: Star messages
  // ════════════════════════════════════════════

  Future<void> _loadStarredMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList('starred_${widget.meetingId}') ?? [];
      if (mounted) setState(() => _starredMessageIds = Set<String>.from(raw));
    } catch (_) {}
  }

  Future<void> _toggleStarMessage(String msgId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final newSet = Set<String>.from(_starredMessageIds);
      if (newSet.contains(msgId)) {
        newSet.remove(msgId);
      } else {
        newSet.add(msgId);
      }
      setState(() => _starredMessageIds = newSet);
      await prefs.setStringList('starred_${widget.meetingId}', newSet.toList());
    } catch (_) {}
  }

  // ════════════════════════════════════════════
  // FEATURE N15: Activities panel
  // ════════════════════════════════════════════

  Widget _buildActivitiesPanel() {
    return DefaultTabController(
      length: 3,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xCC181828),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 0.5)),
          ),
          child: Column(children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                const Icon(Icons.grid_view, color: Colors.white70, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('Activités',
                    style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15))),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white54, size: 22),
                  onPressed: () => setState(() => _showActivities = false),
                ),
              ]),
            ),
            TabBar(
              labelColor: AppColors.primary,
              unselectedLabelColor: Colors.white38,
              indicatorColor: AppColors.primary,
              labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13),
              tabs: const [
                Tab(text: 'Sondages'),
                Tab(text: 'Q&R'),
                Tab(text: 'Tableau'),
              ],
            ),
            Expanded(
              child: TabBarView(children: [
                _buildPollsPanel(),
                _buildQAPanel(),
                Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.draw_outlined, color: Colors.white38, size: 48),
                    const SizedBox(height: 12),
                    Text('Ouvrir le tableau blanc', style: GoogleFonts.poppins(color: Colors.white54, fontSize: 14)),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _showActivities = false;
                          _showWhiteboard = true;
                          _listenWhiteboard();
                        });
                      },
                      icon: const Icon(Icons.draw_outlined),
                      label: Text('Ouvrir', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  // ── CONTROLS BAR ─────────────────────────────
  Widget _buildControls() {
    final lang = Provider.of<LocaleProvider>(context, listen: false).locale.languageCode;
    final isPrivileged = widget.isHost || _isCoHost;
    return SafeArea(
      top: false,
      child: Container(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 12),
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
              label: AppTranslations.t('tb_mic_toggle', lang),
              button: true,
              child: _Btn(
                icon: _micOn ? Icons.mic : Icons.mic_off,
                label: _micOn ? AppTranslations.t('tb_mic', lang) : AppTranslations.t('tb_muted', lang),
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
              label: AppTranslations.t('tb_cam_toggle', lang),
              button: true,
              child: _Btn(
                icon: _camOn ? Icons.videocam : Icons.videocam_off,
                label: _camOn ? AppTranslations.t('tb_cam', lang) : AppTranslations.t('tb_cam_off', lang),
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
              label: AppTranslations.t('tb_flip', lang),
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
              icon: Icons.auto_fix_high,
              label: AppTranslations.t('tb_filters', lang),
              active: _cameraFilter == _CameraFilter.natural,
              isHighlight: _cameraFilter != _CameraFilter.natural,
              onTap: _showFiltersPanel,
            ),
            const SizedBox(width: 8),
            // Feature N12: Screen share with permission check
            if (!_allowParticipantScreenShare && !isPrivileged)
              _Btn(
                icon: Icons.screen_share,
                label: AppTranslations.t('tb_screen', lang),
                active: false,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(AppTranslations.t('screen_share_disabled', lang), style: GoogleFonts.poppins()),
                    backgroundColor: Colors.orange.shade700,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    duration: const Duration(seconds: 3),
                  ));
                },
              )
            else
              _Btn(
                icon: _sharingScreen
                    ? Icons.stop_screen_share
                    : Icons.screen_share,
                label: _sharingScreen ? AppTranslations.t('tb_stop', lang) : AppTranslations.t('tb_screen', lang),
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
                  label: AppTranslations.t('tb_chat', lang),
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
            Stack(
              clipBehavior: Clip.none,
              children: [
                _Btn(
                  icon: Icons.people_outline,
                  label: AppTranslations.t('tb_participants', lang),
                  active: !_showParticipants,
                  isHighlight: _showParticipants,
                  onTap: () => setState(() {
                    _showParticipants = !_showParticipants;
                    if (_showParticipants) { _showChat = false; _showEmojiBar = false; }
                  }),
                ),
                if (_waitingList.isNotEmpty)
                  Positioned(
                    top: -4, right: -4,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                      child: Text('${_waitingList.length}',
                          style: GoogleFonts.poppins(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 8),
            _Btn(
              icon: _handRaised ? Icons.front_hand : Icons.front_hand_outlined,
              label: _handRaised ? AppTranslations.t('tb_hand_lower', lang) : AppTranslations.t('tb_hand_raise', lang),
              active: !_handRaised,
              isHighlight: _handRaised,
              onTap: _toggleRaiseHand,
            ),
            const SizedBox(width: 8),
            _Btn(
              icon: Icons.emoji_emotions_outlined,
              label: AppTranslations.t('tb_emoji', lang),
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
              label: AppTranslations.t('tb_info', lang),
              active: true,
              onTap: _showMeetingInfoPanel,
            ),
            const SizedBox(width: 8),
            _Btn(
              icon: _speakerOn ? Icons.volume_up : Icons.volume_off,
              label: _speakerOn ? AppTranslations.t('tb_speaker', lang) : AppTranslations.t('tb_earpiece', lang),
              active: _speakerOn,
              onTap: _toggleSpeaker,
            ),
            const SizedBox(width: 8),
            _Btn(
              icon: Icons.tune,
              label: AppTranslations.t('tb_options', lang),
              active: true,
              onTap: _showMoreOptionsSheet,
            ),
            if (isPrivileged) ...[
              const SizedBox(width: 8),
              _Btn(
                icon: _isLocked ? Icons.lock : Icons.lock_open,
                label: _isLocked ? AppTranslations.t('tb_unlock', lang) : AppTranslations.t('tb_lock', lang),
                active: !_isLocked,
                isHighlight: _isLocked,
                onTap: _toggleLock,
              ),
              const SizedBox(width: 8),
              _Btn(
                icon: Icons.mic_off,
                label: AppTranslations.t('tb_mute_all', lang),
                active: true,
                onTap: () {
                  HapticFeedback.mediumImpact();
                  // Keep host's own mic enabled — only signal OTHER participants to mute
                  // Do NOT mute the host's local audio track or set _micOn = false
                  // Signal all participants via Firestore (fire-and-forget)
                  _meetingService.triggerMuteAll(widget.meetingId).catchError((_) {});
                  if (mounted) {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('🔇 ${AppTranslations.t('tb_all_muted', lang)}',
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
            // ── CHURCH OFFERING BUTTON ──────────────────────
            if (_isChurchMode) ...[
              const SizedBox(width: 8),
              _Btn(
                icon: Icons.volunteer_activism,
                label: AppTranslations.t('tb_offering', lang),
                active: true,
                isHighlight: true,
                onTap: () {
                  HapticFeedback.mediumImpact();
                  _showOfferingPanel();
                },
              ),
            ],
            const SizedBox(width: 8),
            _Btn(
              icon: Icons.subtitles_outlined,
              label: AppTranslations.t('tb_subtitles', lang),
              active: !_showTranscript,
              isHighlight: _showTranscript,
              onTap: () {
                setState(() {
                  _showTranscript = !_showTranscript;
                  if (_showTranscript) {
                    _showChat = false;
                    _showParticipants = false;
                    _showWhiteboard = false;
                  }
                });
                // Auto-start transcription when panel opens
                if (_showTranscript && !_sttListening) {
                  _startTranscription();
                }
                // Auto-stop when panel closes
                if (!_showTranscript && _sttListening) {
                  _stopTranscription();
                }
              },
            ),
            const SizedBox(width: 8),
            _Btn(
              icon: Icons.draw_outlined,
              label: AppTranslations.t('tb_whiteboard', lang),
              active: !_showWhiteboard,
              isHighlight: _showWhiteboard,
              onTap: () => setState(() {
                _showWhiteboard = !_showWhiteboard;
                if (_showWhiteboard) {
                  _showChat = false;
                  _showParticipants = false;
                  _showTranscript = false;
                  _showPolls = false;
                  _listenWhiteboard();
                }
              }),
            ),
            const SizedBox(width: 8),
            _Btn(
              icon: Icons.poll_outlined,
              label: AppTranslations.t('tb_polls', lang),
              active: !_showPolls,
              isHighlight: _showPolls,
              onTap: () => setState(() {
                _showPolls = !_showPolls;
                if (_showPolls) {
                  _showChat = false;
                  _showParticipants = false;
                  _showTranscript = false;
                  _showWhiteboard = false;
                }
              }),
            ),
            const SizedBox(width: 8),
            _Btn(
              icon: _isRecordingLocally ? Icons.stop_circle_outlined : Icons.fiber_manual_record,
              label: _isRecordingLocally ? AppTranslations.t('tb_rec_stop', lang) : AppTranslations.t('tb_rec', lang),
              active: !_isRecordingLocally,
              isHighlight: _isRecordingLocally,
              onTap: _toggleLocalRecordingWithSync,
            ),
            const SizedBox(width: 8),
            _Btn(
              icon: _noiseCancellation ? Icons.noise_aware : Icons.noise_control_off,
              label: AppTranslations.t('tb_noise', lang),
              active: _noiseCancellation,
              isHighlight: !_noiseCancellation,
              onTap: _toggleNoiseCancellation,
            ),
            const SizedBox(width: 8),
            if (_transcriptLines.isNotEmpty)
              _Btn(
                icon: Icons.auto_awesome,
                label: AppTranslations.t('tb_summary', lang),
                active: true,
                onTap: _generateMeetingSummary,
              ),
            const SizedBox(width: 8),
            // Feature N1: Q&A button
            _Btn(
              icon: Icons.quiz_outlined,
              label: AppTranslations.t('tb_qa', lang),
              active: !_showQA,
              isHighlight: _showQA,
              onTap: () => setState(() {
                _showQA = !_showQA;
                if (_showQA) { _showChat = false; _showParticipants = false; _showWhiteboard = false; _showPolls = false; _showActivities = false; }
              }),
            ),
            const SizedBox(width: 8),
            // Feature N6: Agenda button
            _Btn(
              icon: Icons.notes,
              label: AppTranslations.t('tb_agenda', lang),
              active: !_showAgendaPanel,
              isHighlight: _showAgendaPanel,
              onTap: () => setState(() {
                _showAgendaPanel = !_showAgendaPanel;
                if (_showAgendaPanel) { _showChat = false; _showParticipants = false; _showWhiteboard = false; _showPolls = false; _showActivities = false; }
              }),
            ),
            const SizedBox(width: 8),
            // Feature N15: Activities panel
            _Btn(
              icon: Icons.grid_view,
              label: AppTranslations.t('tb_activities', lang),
              active: !_showActivities,
              isHighlight: _showActivities,
              onTap: () => setState(() {
                _showActivities = !_showActivities;
                if (_showActivities) { _showChat = false; _showParticipants = false; _showWhiteboard = false; _showPolls = false; _showQA = false; }
              }),
            ),
            // Feature N2: Attendance button (host/cohost only)
            if (isPrivileged) ...[
              const SizedBox(width: 8),
              _Btn(
                icon: Icons.checklist,
                label: AppTranslations.t('tb_attendance', lang),
                active: true,
                onTap: _listenAttendance,
              ),
            ],
            // Feature N4: Host controls (host/cohost only)
            if (isPrivileged) ...[
              const SizedBox(width: 8),
              _Btn(
                icon: Icons.shield_outlined,
                label: AppTranslations.t('tb_controls', lang),
                active: true,
                onTap: _showHostControlsSheet,
              ),
            ],
            const SizedBox(width: 8),
            if (_pipSupported)
              _Btn(
                icon: Icons.picture_in_picture_alt_rounded,
                label: 'Mini',
                active: true,
                onTap: _enterPip,
              ),
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
    ), // Container
    ); // SafeArea
  }

  // ── MORE OPTIONS SHEET ───────────────────────
  void _showMoreOptionsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final isPrivileged = widget.isHost || _isCoHost;
          return Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            decoration: const BoxDecoration(
              color: Color(0xFF181828),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 12),
              Text('Options', style: GoogleFonts.poppins(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),

              // Mirror video
              SwitchListTile(
                title: Text('Miroir vidéo', style: GoogleFonts.poppins(color: Colors.white, fontSize: 14)),
                subtitle: Text('Inverser l\'image de votre caméra', style: GoogleFonts.poppins(color: Colors.white38, fontSize: 11)),
                value: _mirrorVideo,
                // ignore: deprecated_member_use
                activeColor: AppColors.primary,
                onChanged: (v) {
                  setState(() => _mirrorVideo = v);
                  setLocal(() {});
                },
              ),

              // Hide self view
              SwitchListTile(
                title: Text('Masquer ma vue', style: GoogleFonts.poppins(color: Colors.white, fontSize: 14)),
                subtitle: Text('Cacher votre propre vidéo dans l\'interface', style: GoogleFonts.poppins(color: Colors.white38, fontSize: 11)),
                value: _hideSelfView,
                // ignore: deprecated_member_use
                activeColor: AppColors.primary,
                onChanged: (v) {
                  setState(() => _hideSelfView = v);
                  setLocal(() {});
                },
              ),

              // HD video
              SwitchListTile(
                title: Row(children: [
                  Text('Vidéo HD', style: GoogleFonts.poppins(color: Colors.white, fontSize: 14)),
                  const SizedBox(width: 8),
                  if (_hdEnabled) Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: Colors.blue.shade700, borderRadius: BorderRadius.circular(4)),
                    child: Text('HD', style: GoogleFonts.poppins(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
                ]),
                subtitle: Text('1080p Full HD', style: GoogleFonts.poppins(color: Colors.white38, fontSize: 11)),
                value: _hdEnabled,
                // ignore: deprecated_member_use
                activeColor: Colors.blue,
                onChanged: (v) async {
                  setLocal(() {});
                  await _toggleHD();
                  setLocal(() {});
                },
              ),

              // Waiting room (host only)
              if (isPrivileged) SwitchListTile(
                title: Text('Salle d\'attente', style: GoogleFonts.poppins(color: Colors.white, fontSize: 14)),
                subtitle: Text('Admettre manuellement les participants', style: GoogleFonts.poppins(color: Colors.white38, fontSize: 11)),
                value: _waitingRoomEnabled,
                // ignore: deprecated_member_use
                activeColor: Colors.orange,
                onChanged: (v) async {
                  setLocal(() {});
                  await _toggleWaitingRoom();
                  setLocal(() {});
                },
              ),

              // Passcode (host only)
              if (widget.isHost) ListTile(
                leading: const Icon(Icons.lock_outline, color: Colors.amber),
                title: Text(
                  _meetingPasscode != null && _meetingPasscode!.isNotEmpty
                      ? 'Code: $_meetingPasscode'
                      : 'Ajouter un code d\'accès',
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
                ),
                trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                onTap: () {
                  Navigator.pop(ctx);
                  _showSetPasscodeDialog();
                },
              ),

              // Feature N7: Low-light mode
              SwitchListTile(
                title: Text('Mode faible luminosité', style: GoogleFonts.poppins(color: Colors.white, fontSize: 14)),
                subtitle: Text('Améliore la visibilité dans l\'obscurité', style: GoogleFonts.poppins(color: Colors.white38, fontSize: 11)),
                value: _lowLightMode,
                // ignore: deprecated_member_use
                activeColor: Colors.amber,
                secondary: const Icon(Icons.brightness_6, color: Colors.amber),
                onChanged: (v) {
                  setState(() => _lowLightMode = v);
                  setLocal(() {});
                },
              ),

              // Feature N5: Side-by-side mode
              if (_sharingScreen) SwitchListTile(
                title: Text('Mode côte à côte', style: GoogleFonts.poppins(color: Colors.white, fontSize: 14)),
                subtitle: Text('Partage + caméra côte à côte', style: GoogleFonts.poppins(color: Colors.white38, fontSize: 11)),
                value: _sideBySide,
                // ignore: deprecated_member_use
                activeColor: Colors.blue,
                secondary: const Icon(Icons.view_column_outlined, color: Colors.blue),
                onChanged: (v) {
                  setState(() => _sideBySide = v);
                  setLocal(() {});
                },
              ),

              // Feature N10: Join/leave sounds
              SwitchListTile(
                title: Text('Sons d\'entrée/sortie', style: GoogleFonts.poppins(color: Colors.white, fontSize: 14)),
                subtitle: Text('Sons quand quelqu\'un rejoint ou quitte', style: GoogleFonts.poppins(color: Colors.white38, fontSize: 11)),
                value: _joinLeaveSounds,
                // ignore: deprecated_member_use
                activeColor: AppColors.primary,
                secondary: const Icon(Icons.notifications_outlined, color: Colors.white54),
                onChanged: (v) {
                  setState(() => _joinLeaveSounds = v);
                  setLocal(() {});
                },
              ),
            ]),
          );
        },
      ),
    );
  }

  // ── CHURCH OFFERING PANEL ────────────────────────────────────
  void _showOfferingPanel() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _OfferingSheet(
        meetingId: widget.meetingId,
        isHost: widget.isHost,
        initialLink: _offeringLink,
        onLinkSaved: (link) {
          setState(() => _offeringLink = link);
        },
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

  // ── PARTICIPANT MANAGE SHEET (host/co-host tap on gallery tile) ────
  void _showParticipantManageSheet(String pId, String pName, bool handRaised) {
    if (!widget.isHost && !_isCoHost) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        decoration: const BoxDecoration(
          color: Color(0xFF181828),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          Text(pName, style: GoogleFonts.poppins(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.mic_off, color: Colors.orange),
            title: Text('🔇 Couper le micro', style: GoogleFonts.poppins(color: Colors.white, fontSize: 14)),
            onTap: () async {
              Navigator.pop(context);
              await _muteParticipant(pId);
            },
          ),
          ListTile(
            leading: const Icon(Icons.star, color: Colors.amber),
            title: Text('👑 Nommer co-hôte', style: GoogleFonts.poppins(color: Colors.white, fontSize: 14)),
            onTap: () async {
              Navigator.pop(context);
              await _meetingService.addCoHost(widget.meetingId, pId);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('$pName est maintenant co-hôte', style: GoogleFonts.poppins()),
                backgroundColor: AppColors.success,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ));
            },
          ),
          if (handRaised)
            ListTile(
              leading: const Icon(Icons.front_hand, color: Colors.orangeAccent),
              title: Text('✋ Baisser la main', style: GoogleFonts.poppins(color: Colors.white, fontSize: 14)),
              onTap: () async {
                Navigator.pop(context);
                await _db.collection('meetings').doc(widget.meetingId)
                    .collection('presence').doc(pId)
                    .update({'handRaised': false}).catchError((_) {});
              },
            ),
          ListTile(
            leading: const Icon(Icons.door_back_door_outlined, color: Colors.redAccent),
            title: Text('🚪 Retirer de la réunion', style: GoogleFonts.poppins(color: Colors.redAccent, fontSize: 14)),
            onTap: () async {
              Navigator.pop(context);
              await _kickParticipant(pId, pName);
            },
          ),
        ]),
      ),
    );
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
                final isPrivilegedUser = widget.isHost || _isCoHost;

                return GestureDetector(
                  onLongPress: (!isMe && isPrivilegedUser)
                      ? () => _showParticipantManageSheet(uid, name, handRaised)
                      : null,
                  child: AnimatedContainer(
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
                            ? _buildLocalVideoView()
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
                            if (isSpeaking && !micMuted) ...[
                              const SizedBox(width: 4),
                              _buildSoundWave(
                                small: true,
                                color: const Color(0xFF4CAF50),
                              ),
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

                      // ── SPOTLIGHT BADGE ───────────────────────────
                      if (_spotlightUserId == uid)
                        Positioned(
                          top: 7, left: handRaised ? 44 : 7,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.purple.withValues(alpha: 0.85),
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: Colors.purple.withValues(alpha: 0.5), blurRadius: 6)],
                            ),
                            child: const Icon(Icons.star, color: Colors.white, size: 10),
                          ),
                        ),
                    ]),
                  ),
                ), // AnimatedContainer
                ); // GestureDetector
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

// ── CHURCH OFFERING SHEET ─────────────────────────────────────────────────────
class _OfferingSheet extends StatefulWidget {
  final String meetingId;
  final bool isHost;
  final String? initialLink;
  final void Function(String link) onLinkSaved;

  const _OfferingSheet({
    required this.meetingId,
    required this.isHost,
    required this.initialLink,
    required this.onLinkSaved,
  });

  @override
  State<_OfferingSheet> createState() => _OfferingSheetState();
}

class _OfferingSheetState extends State<_OfferingSheet> {
  late final TextEditingController _linkCtrl;
  bool _saving = false;
  bool _editMode = false;

  @override
  void initState() {
    super.initState();
    _linkCtrl = TextEditingController(text: widget.initialLink ?? '');
    _editMode = widget.isHost && (widget.initialLink == null || widget.initialLink!.isEmpty);
  }

  @override
  void dispose() {
    _linkCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveLink() async {
    final raw = _linkCtrl.text.trim();
    if (raw.isEmpty) return;

    // Auto-prepend https:// if needed
    final link = raw.startsWith('http') ? raw : 'https://$raw';
    final uri = Uri.tryParse(link);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Lien invalide. Ex: https://pay.djamo.com/votre-lien',
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 12)),
        backgroundColor: Colors.orange.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }

    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('meetings')
          .doc(widget.meetingId)
          .update({'offeringLink': link});
      _linkCtrl.text = link; // normalize the displayed link
      widget.onLinkSaved(link);
      if (mounted) {
        setState(() { _saving = false; _editMode = false; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ Lien d\'offrande enregistré!',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          backgroundColor: const Color(0xFF388E3C),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur sauvegarde: $e',
              style: GoogleFonts.poppins(color: Colors.white, fontSize: 12)),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    }
  }

  Future<void> _openLink() async {
    final link = widget.initialLink ?? _linkCtrl.text.trim();
    if (link.isEmpty) return;

    // Ensure valid URL — prepend https:// if missing
    final safeLink = link.startsWith('http') ? link : 'https://$link';
    final uri = Uri.tryParse(safeLink);
    if (uri == null || !uri.hasScheme) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Lien invalide. Vérifiez l\'URL.',
              style: GoogleFonts.poppins(color: Colors.white)),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
      return;
    }
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Impossible d\'ouvrir le lien: $e',
              style: GoogleFonts.poppins(color: Colors.white, fontSize: 12)),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 4),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const grad = LinearGradient(
      colors: [Color(0xFF4A148C), Color(0xFF880E4F)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    final hasLink = (widget.initialLink?.isNotEmpty ?? false) || _linkCtrl.text.isNotEmpty;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1529),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Center(child: Container(width: 36, height: 4,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 20),

        // Header
        Row(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(gradient: grad, borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.volunteer_activism, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Offrandes', style: GoogleFonts.poppins(color: Colors.white,
                fontWeight: FontWeight.w800, fontSize: 18)),
            Text('Faire une offrande à l\'Église', style: GoogleFonts.poppins(
                color: Colors.white54, fontSize: 12)),
          ])),
          if (widget.isHost && !_editMode && hasLink)
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: Colors.white54, size: 20),
              onPressed: () => setState(() => _editMode = true),
              tooltip: 'Modifier le lien',
            ),
        ]),
        const SizedBox(height: 24),

        if (_editMode && widget.isHost) ...[
          // Host: enter payment link
          Text('Configurez votre lien de paiement',
              style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: _linkCtrl,
            style: GoogleFonts.poppins(color: Colors.white),
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              hintText: 'https://pay.djamo.com/... ou autre lien',
              hintStyle: GoogleFonts.poppins(color: Colors.white38, fontSize: 12),
              prefixIcon: const Icon(Icons.link, color: Color(0xFF4A148C)),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.08),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFF4A148C), width: 2)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity, height: 50,
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: grad, borderRadius: BorderRadius.circular(25)),
              child: TextButton(
                style: TextButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25))),
                onPressed: _saving ? null : _saveLink,
                child: _saving
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.save_outlined, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Text('Enregistrer le lien', style: GoogleFonts.poppins(
                            color: Colors.white, fontWeight: FontWeight.w700)),
                      ]),
              ),
            ),
          ),
        ] else if (hasLink) ...[
          // Participants: show offering button
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                const Color(0xFF4A148C).withValues(alpha: 0.3),
                const Color(0xFF880E4F).withValues(alpha: 0.3),
              ]),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF4A148C).withValues(alpha: 0.5), width: 1),
            ),
            child: Column(children: [
              const Icon(Icons.church, color: Colors.white70, size: 40),
              const SizedBox(height: 12),
              Text('Contribuer à l\'œuvre de Dieu',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 6),
              Text('Tout don compte. Dieu bénit les donateurs.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(color: Colors.white60, fontSize: 12)),
            ]),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity, height: 54,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: grad,
                borderRadius: BorderRadius.circular(27),
                boxShadow: [BoxShadow(color: const Color(0xFF4A148C).withValues(alpha: 0.5), blurRadius: 16, offset: const Offset(0, 4))],
              ),
              child: TextButton(
                style: TextButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27))),
                onPressed: _openLink,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.favorite, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Text('Faire une offrande', style: GoogleFonts.poppins(
                      color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Vous serez redirigé vers le lien de paiement',
              style: GoogleFonts.poppins(color: Colors.white38, fontSize: 11)),
        ] else ...[
          // Host mode but no link yet, participant sees message
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(children: [
              const Icon(Icons.info_outline, color: Colors.white38, size: 36),
              const SizedBox(height: 12),
              Text('Aucun lien de paiement configuré',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(color: Colors.white54, fontSize: 13)),
              if (widget.isHost) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => setState(() => _editMode = true),
                  child: Text('Configurer maintenant →',
                      style: GoogleFonts.poppins(color: const Color(0xFF4A148C), fontWeight: FontWeight.w700)),
                ),
              ],
            ]),
          ),
        ],
        const SizedBox(height: 8),
      ]),
    );
  }
}

class _PaywallDialog extends StatefulWidget {
  final String userId;
  final String userName;
  final ProService proService;
  final VoidCallback onProConfirmed;
  final VoidCallback onLeave;
  final int freeMinutes;

  const _PaywallDialog({
    required this.userId,
    required this.userName,
    required this.proService,
    required this.onProConfirmed,
    required this.onLeave,
    this.freeMinutes = 30,
  });

  @override
  State<_PaywallDialog> createState() => _PaywallDialogState();
}

class _PaywallDialogState extends State<_PaywallDialog> with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  late Animation<double> _scale;
  bool _paymentOpened = false;  // true = user tapped pay, waiting confirmation
  bool _verifying = false;      // true = checking Firestore right now
  String? _statusMessage;       // feedback message to user

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

  Future<void> _openPayment() async {
    setState(() { _paymentOpened = true; _statusMessage = null; });
    await widget.proService.startPayment(
      userId: widget.userId,
      userName: widget.userName,
    );
    // After returning from Djamo, auto-verify
    if (mounted) _verifyPayment();
  }

  Future<void> _verifyPayment() async {
    if (_verifying) return;
    setState(() { _verifying = true; _statusMessage = 'Vérification en cours...'; });
    try {
      final isPro = await widget.proService.isPro(widget.userId);
      if (isPro) {
        widget.onProConfirmed();
      } else {
        setState(() {
          _verifying = false;
          _statusMessage = 'Paiement non encore confirmé. Réessayez dans quelques secondes.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _verifying = false;
          _statusMessage = 'Erreur vérification. Réessayez.';
        });
      }
    }
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
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── ICON PULSING ──
              ScaleTransition(
                scale: _scale,
                child: Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    gradient: grad, shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: const Color(0xFFB71C1C).withValues(alpha: 0.4), blurRadius: 24, spreadRadius: 4)],
                  ),
                  child: const Icon(Icons.workspace_premium, color: Colors.white, size: 36),
                ),
              ),
              const SizedBox(height: 16),

              // ── TITLE ──
              const Text('CRUX PRO',
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 2)),
              const SizedBox(height: 6),
              Text('Vos ${widget.freeMinutes} minutes gratuites sont écoulées.\nL\'appel est en pause.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 13, height: 1.5)),
              const SizedBox(height: 16),

              // ── PRICE CARD ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                decoration: BoxDecoration(gradient: grad, borderRadius: BorderRadius.circular(16)),
                child: Column(children: [
                  const Text('100 000 FCFA / mois',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  const Text('Accès illimité — Sans publicité',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 10),
                  // Lien Djamo visible + copiable
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(const ClipboardData(text: 'https://pay.djamo.com/qxmvj'));
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('Lien copié !', style: GoogleFonts.poppins()),
                        backgroundColor: const Color(0xFF6A1B9A),
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.link, color: Colors.white70, size: 13),
                        SizedBox(width: 5),
                        Text('pay.djamo.com/qxmvj',
                          style: TextStyle(color: Colors.white70, fontSize: 11, decoration: TextDecoration.underline, decorationColor: Colors.white54)),
                        SizedBox(width: 5),
                        Icon(Icons.copy, color: Colors.white54, size: 11),
                      ]),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 14),

              // ── FEATURES ──
              ...[
                ('Réunions illimitées', Icons.all_inclusive),
                ('Jusqu\'à 100 participants', Icons.group),
                ('Enregistrement cloud', Icons.cloud_upload),
                ('Fond d\'écran virtuel', Icons.blur_on),
                ('Support prioritaire', Icons.support_agent),
              ].map((f) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  const Icon(Icons.check_circle, color: Color(0xFFB71C1C), size: 16),
                  const SizedBox(width: 8),
                  Text(f.$1, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ]),
              )),
              const SizedBox(height: 20),

              // ── STATUS MESSAGE ──
              if (_statusMessage != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: _verifying
                        ? Colors.blue.withValues(alpha: 0.15)
                        : (_statusMessage!.contains('non encore') ? Colors.orange.withValues(alpha: 0.15) : Colors.red.withValues(alpha: 0.15)),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _verifying ? Colors.blue.withValues(alpha: 0.4) : Colors.orange.withValues(alpha: 0.4)),
                  ),
                  child: Row(children: [
                    if (_verifying)
                      const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70))
                    else
                      const Icon(Icons.info_outline, color: Colors.orange, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_statusMessage!,
                      style: GoogleFonts.poppins(color: Colors.white70, fontSize: 11))),
                  ]),
                ),
                const SizedBox(height: 12),
              ],

              // ── PAY BUTTON ──
              SizedBox(
                width: double.infinity, height: 52,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: grad,
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: [BoxShadow(color: const Color(0xFFB71C1C).withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  child: TextButton(
                    style: TextButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26))),
                    onPressed: _verifying ? null : _openPayment,
                    child: _verifying && !_paymentOpened
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                        : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            const Icon(Icons.payment, color: Colors.white, size: 18),
                            const SizedBox(width: 8),
                            Text(_paymentOpened ? 'Ouvrir le paiement Djamo' : 'Passer à CRUX PRO — 100 000 FCFA',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                          ]),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // ── "J'AI PAYÉ" BUTTON — only shown after payment opened ──
              if (_paymentOpened) ...[
                SizedBox(
                  width: double.infinity, height: 48,
                  child: OutlinedButton.icon(
                    icon: _verifying
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70))
                        : const Icon(Icons.check_circle_outline, color: Colors.white70, size: 18),
                    label: Text(_verifying ? 'Vérification...' : 'J\'ai effectué le paiement',
                      style: GoogleFonts.poppins(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    onPressed: _verifying ? null : _verifyPayment,
                  ),
                ),
                const SizedBox(height: 6),
                Text('Appuyez après avoir payé sur Djamo',
                  style: GoogleFonts.poppins(color: Colors.white30, fontSize: 10),
                  textAlign: TextAlign.center),
                const SizedBox(height: 8),
              ],

              // ── LEAVE BUTTON ──
              TextButton(
                onPressed: widget.onLeave,
                child: Text('Quitter la réunion',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 13)),
              ),
            ],
          ),
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

// ── WHITEBOARD HELPER WIDGETS ──────────────────
class _WbToolBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final _WbTool tool;
  final _WbTool current;
  final void Function(_WbTool) onTap;
  const _WbToolBtn({required this.icon, required this.label, required this.tool, required this.current, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final active = tool == current;
    return GestureDetector(
      onTap: () => onTap(tool),
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFFF4081).withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? const Color(0xFFFF4081) : Colors.white24, width: active ? 1.5 : 1),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: active ? const Color(0xFFFF4081) : Colors.white70, size: 16),
          Text(label, style: GoogleFonts.poppins(color: active ? const Color(0xFFFF4081) : Colors.white54, fontSize: 8, fontWeight: active ? FontWeight.w700 : FontWeight.w400)),
        ]),
      ),
    );
  }
}

class _WbIconBtn extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final Color? color;
  const _WbIconBtn({required this.icon, required this.active, required this.onTap, this.color});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: active ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Icon(icon, color: color ?? (active ? Colors.white70 : Colors.white24), size: 18),
      ),
    );
  }
}

// ── WHITEBOARD TOOL ENUM ───────────────────────
enum _WbTool { pen, line, arrow, rect, circle, triangle, text, eraser, laser, select }
enum _WbShapeType { line, arrow, rect, circle, triangle }

// ── WHITEBOARD ELEMENT TYPES ──────────────────
abstract class _WbElement {
  const _WbElement();
}

class _WbStroke extends _WbElement {
  final List<Offset> points;
  final Color color;
  final double width;
  final bool isErase;
  const _WbStroke({required this.points, required this.color, required this.width, this.isErase = false});
}

class _WbShape extends _WbElement {
  final Offset start;
  final Offset end;
  final _WbShapeType shapeType;
  final Color color;
  final double width;
  final bool filled;
  const _WbShape({required this.start, required this.end, required this.shapeType, required this.color, required this.width, this.filled = false});
}

class _WbText extends _WbElement {
  final Offset position;
  final String text;
  final Color color;
  final double fontSize;
  const _WbText({required this.position, required this.text, required this.color, required this.fontSize});
}

// ── WHITEBOARD PAINTER ─────────────────────────
class _WhiteboardPainter extends CustomPainter {
  final List<_WbElement> elements;
  final List<Offset?> currentPoints;
  final Color currentColor;
  final double currentWidth;
  final _WbTool currentTool;
  final Offset? shapeStart;
  final Offset? laserPos;

  const _WhiteboardPainter({
    required this.elements,
    required this.currentPoints,
    required this.currentColor,
    required this.currentWidth,
    required this.currentTool,
    this.shapeStart,
    this.laserPos,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // White background
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);

    // Draw all committed elements
    for (final el in elements) {
      _drawElement(canvas, el);
    }

    // Draw in-progress stroke/shape
    if (currentPoints.isNotEmpty) {
      if (currentTool == _WbTool.pen || currentTool == _WbTool.eraser) {
        _drawStrokePath(canvas, currentPoints.whereType<Offset>().toList(), currentColor, currentWidth, currentTool == _WbTool.eraser);
      } else if ([_WbTool.line, _WbTool.arrow, _WbTool.rect, _WbTool.circle, _WbTool.triangle].contains(currentTool) && shapeStart != null) {
        final previewEnd = currentPoints.whereType<Offset>().lastOrNull ?? shapeStart!;
        final previewShapeType = currentTool == _WbTool.line ? _WbShapeType.line
          : currentTool == _WbTool.arrow ? _WbShapeType.arrow
          : currentTool == _WbTool.rect ? _WbShapeType.rect
          : currentTool == _WbTool.circle ? _WbShapeType.circle
          : _WbShapeType.triangle;
        _drawShape(canvas, _WbShape(
          start: shapeStart!,
          end: previewEnd,
          shapeType: previewShapeType,
          color: currentColor.withValues(alpha: 0.6),
          width: currentWidth,
          filled: false,
        ));
      }
    }

    // Laser pointer
    if (laserPos != null) {
      final laserPaint = Paint()
        ..color = Colors.red.withValues(alpha: 0.85)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(laserPos!, 10, laserPaint);
      canvas.drawCircle(laserPos!, 5, Paint()..color = Colors.red);
    }
  }

  void _drawElement(Canvas canvas, _WbElement el) {
    if (el is _WbStroke) {
      _drawStrokePath(canvas, el.points, el.color, el.width, el.isErase);
    } else if (el is _WbShape) {
      _drawShape(canvas, el);
    } else if (el is _WbText) {
      _drawText(canvas, el);
    }
  }

  void _drawStrokePath(Canvas canvas, List<Offset> points, Color color, double width, bool isErase) {
    if (points.isEmpty) return;
    final paint = Paint()
      ..color = isErase ? Colors.white : color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (isErase) {
      paint.blendMode = BlendMode.src;
      paint.color = Colors.white;
    }

    final path = Path();
    path.moveTo(points.first.dx, points.first.dy);
    if (points.length == 1) {
      canvas.drawCircle(points.first, width / 2, Paint()..color = color..style = PaintingStyle.fill);
      return;
    }
    for (int i = 1; i < points.length - 1; i++) {
      final mid = Offset((points[i].dx + points[i + 1].dx) / 2, (points[i].dy + points[i + 1].dy) / 2);
      path.quadraticBezierTo(points[i].dx, points[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(points.last.dx, points.last.dy);
    canvas.drawPath(path, paint);
  }

  void _drawShape(Canvas canvas, _WbShape shape) {
    final paint = Paint()
      ..color = shape.color
      ..strokeWidth = shape.width
      ..strokeCap = StrokeCap.round
      ..style = shape.filled ? PaintingStyle.fill : PaintingStyle.stroke;

    final rect = Rect.fromPoints(shape.start, shape.end);

    switch (shape.shapeType) {
      case _WbShapeType.rect:
        canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)), paint);
        if (shape.filled) {
          canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)),
              Paint()..color = shape.color..style = PaintingStyle.stroke..strokeWidth = shape.width * 0.5);
        }
        break;
      case _WbShapeType.circle:
        canvas.drawOval(rect, paint);
        break;
      case _WbShapeType.triangle:
        final path = Path();
        final cx = (shape.start.dx + shape.end.dx) / 2;
        path.moveTo(cx, shape.start.dy);
        path.lineTo(shape.end.dx, shape.end.dy);
        path.lineTo(shape.start.dx, shape.end.dy);
        path.close();
        canvas.drawPath(path, paint);
        break;
      case _WbShapeType.line:
        canvas.drawLine(shape.start, shape.end, paint..style = PaintingStyle.stroke);
        break;
      case _WbShapeType.arrow:
        canvas.drawLine(shape.start, shape.end, paint..style = PaintingStyle.stroke);
        // Arrowhead
        final dx = shape.end.dx - shape.start.dx;
        final dy = shape.end.dy - shape.start.dy;
        final len = math.sqrt(dx * dx + dy * dy);
        if (len > 10) {
          final arrowLen = shape.width * 4 + 8;
          final angle = math.atan2(dy, dx);
          final arrowPath = Path();
          arrowPath.moveTo(shape.end.dx, shape.end.dy);
          arrowPath.lineTo(
            shape.end.dx - arrowLen * math.cos(angle - 0.45),
            shape.end.dy - arrowLen * math.sin(angle - 0.45),
          );
          arrowPath.moveTo(shape.end.dx, shape.end.dy);
          arrowPath.lineTo(
            shape.end.dx - arrowLen * math.cos(angle + 0.45),
            shape.end.dy - arrowLen * math.sin(angle + 0.45),
          );
          canvas.drawPath(arrowPath, paint..style = PaintingStyle.stroke..strokeWidth = shape.width);
        }
        break;
    }
  }

  void _drawText(Canvas canvas, _WbText el) {
    final tp = TextPainter(
      text: TextSpan(
        text: el.text,
        style: TextStyle(
          color: el.color,
          fontSize: el.fontSize,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.none,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, el.position);
  }

  @override
  bool shouldRepaint(_WhiteboardPainter old) => true;
}
