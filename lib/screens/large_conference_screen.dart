import 'dart:async';
import 'dart:convert';
import 'dart:ui' show ImageFilter;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../services/livekit_service.dart';
import '../services/meeting_service.dart';
import '../models/meeting_model.dart';
import '../services/note_service.dart';
import '../theme/colors.dart';
import '../providers/locale_provider.dart';
import '../services/pro_service.dart';

class LargeConferenceScreen extends StatefulWidget {
  final String meetingId;
  final String meetingName;
  final String userId;
  final String userName;
  final String? userEmail;
  final bool isHost;

  const LargeConferenceScreen({
    super.key,
    required this.meetingId,
    required this.meetingName,
    required this.userId,
    required this.userName,
    this.userEmail,
    this.isHost = false,
  });

  @override
  State<LargeConferenceScreen> createState() => _LargeConferenceScreenState();
}

class _LargeConferenceScreenState extends State<LargeConferenceScreen> with WidgetsBindingObserver {
  Room? _room;
  EventsListener<RoomEvent>? _roomListener;
  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _micOn = true;
  bool _camOn = true;
  bool _screenShareOn = false;
  bool _loading = true;
  String? _error;
  String? _organizerId;

  List<RemoteParticipant> _remoteParticipants = [];
  String? _activeSpeakerId;
  String _currentTranscription = "";

  // Monétisation
  Timer? _callTimer;
  int _secondsElapsed = 0;
  bool _isPro = false;

  // Panels
  bool _showChat = false;
  bool _showParticipants = false;
  bool _showNotes = false;
  String? _privateRecipientId;
  String? _privateRecipientName;
  bool _voiceAssistant = true;
  bool _handRaised = false;
  List<String> _raisedHands = [];

  final TextEditingController _noteController = TextEditingController();
  final _db = FirebaseFirestore.instance;
  StreamSubscription? _presenceSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPro();
    _init();
    _initSTT();
    _initPresenceListener();
    _announce("Réunion commencée. Je suis votre assistant Crux.");
  }

  Future<void> _checkPro() async {
    final pro = await ProService().checkProStatus(widget.userId);
    if (mounted) setState(() => _isPro = pro);
    _startCallTimer();
  }

  void _startCallTimer() {
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _secondsElapsed++);

      if (!_isPro) {
        final limitSeconds = AppConfig.freeMeetingDurationMinutes * 60;
        if (_secondsElapsed == limitSeconds - 300) {
          _announce("Attention, votre appel gratuit se terminera dans 5 minutes.");
        }
        if (_secondsElapsed >= limitSeconds) {
          timer.cancel();
          _showPaywall();
        }
      }
    });
  }

  void _showPaywall() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text("Temps écoulé", style: TextStyle(color: Colors.white)),
        content: const Text("Limite de 30 minutes atteinte. Passez à CRUX Pro pour des appels illimités."),
        actions: [
          TextButton(onPressed: () => _leave(), child: const Text("Quitter")),
          ElevatedButton(onPressed: () => ProService().startPayment(userId: widget.userId, userName: widget.userName), child: const Text("Devenir Pro")),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _presenceSubscription?.cancel();
    _room?.disconnect();
    _room?.dispose();
    _tts.stop();
    _speech.stop();
    super.dispose();
  }

  Future<void> _announce(String text) async {
    if (!_voiceAssistant) return;
    await _tts.setLanguage("fr-FR");
    await _tts.setPitch(1.0);
    await _tts.speak(text);
  }

  Future<void> _initSTT() async {
    try {
      bool available = await _speech.initialize();
      if (available) {
        _speech.listen(onResult: (val) {
          if (mounted) setState(() => _currentTranscription = val.recognizedWords);
        });
      }
    } catch (_) {}
  }

  void _initPresenceListener() {
    _presenceSubscription = _db
        .collection('meetings')
        .doc(widget.meetingId)
        .collection('presence')
        .snapshots()
        .listen((snap) {
      if (mounted) {
        setState(() {
          _raisedHands = snap.docs
              .where((doc) => (doc.data()['handRaised'] ?? false) == true)
              .map((doc) => doc.id)
              .toList();
        });
      }
    });
  }

  Future<void> _init() async {
    // 0. Load default mic & cam preferences
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _micOn = prefs.getBool('crux_mic_default') ?? true;
        _camOn = prefs.getBool('crux_cam_default') ?? true;
      });
    } catch (_) {}

    // 1. Register presence & update status
    await MeetingService().registerPresence(widget.meetingId, widget.userId, widget.userName);
    if (widget.isHost) {
      await MeetingService().updateMeetingStatus(widget.meetingId, MeetingStatus.ongoing);
    }

    // 2. Fetch LiveKit token
    final token = await LiveKitService.instance.fetchToken(
      room: widget.meetingId,
      identity: widget.userId,
      name: widget.userName,
      isHost: widget.isHost,
    );

    if (token == null) {
      setState(() {
        _loading = false;
        _error = "Le serveur de réunion ne répond pas.\n\n"
            "Si c'est la première utilisation de la journée, il peut mettre 60 secondes à démarrer. Veuillez réessayer dans un instant.";
      });
      return;
    }

    try {
      _room = Room(
        roomOptions: const RoomOptions(
          adaptiveStream: true, // Crucial for 1000+ participants
          dynacast: true,
          defaultVideoPublishOptions: VideoPublishOptions(
            simulcast: true,
          ),
        ),
      );
      _roomListener = _room!.createListener();
      _roomListener!
        ..on<RoomConnectedEvent>((_) {
          _refresh();
        })
        ..on<ParticipantConnectedEvent>((e) {
          _announce("${e.participant.name} vient de nous rejoindre.");
          _refresh();
        })
        ..on<ParticipantDisconnectedEvent>((e) {
          _announce("${e.participant.name} a quitté la salle.");
          _refresh();
        })
        ..on<ActiveSpeakersChangedEvent>((e) {
          if (e.speakers.isNotEmpty) {
            setState(() => _activeSpeakerId = e.speakers.first.identity);
          }
        })
        ..on<DataReceivedEvent>((e) {
          try {
            final text = utf8.decode(e.data);
            final msg = jsonDecode(text) as Map<String, dynamic>;
            if (msg['type'] == 'mute_all') {
              if (e.participant?.identity == _organizerId) {
                if (_micOn) {
                  _toggleMic();
                  _announce("L'organisateur a coupé votre micro.");
                }
              }
            }
          } catch (err) {
            if (kDebugMode) print('Error handling data received: $err');
          }
        });

      // Fetch organizerId
      try {
        final doc = await _db.collection('meetings').doc(widget.meetingId).get();
        if (doc.exists) {
          _organizerId = doc.data()?['organizerId'] as String?;
        }
      } catch (e) {
        if (kDebugMode) print("Error fetching organizerId: $e");
      }

      await _room!.connect(AppConfig.livekitUrl, token);
      await _room!.localParticipant?.setCameraEnabled(_camOn);
      await _room!.localParticipant?.setMicrophoneEnabled(_micOn);
      setState(() {
        _loading = false;
        _remoteParticipants = _room!.remoteParticipants.values.toList();
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = "Erreur fatale : $e";
      });
    }
  }

  void _refresh() {
    if (mounted) {
      setState(() => _remoteParticipants = _room!.remoteParticipants.values.toList());
    }
  }

  // ── Actions ──────────────────────────────────

  Future<void> _toggleMic() async {
    setState(() => _micOn = !_micOn);
    await _room?.localParticipant?.setMicrophoneEnabled(_micOn);
  }

  Future<void> _toggleCam() async {
    setState(() => _camOn = !_camOn);
    await _room?.localParticipant?.setCameraEnabled(_camOn);
  }

  Future<void> _muteAllOthers() async {
    final confirmMute = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text("Muter tout le monde ?", style: TextStyle(color: Colors.white)),
        content: const Text("Voulez-vous couper le micro de tous les autres participants ?", style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text("Couper"),
          ),
        ],
      ),
    );

    if (confirmMute == true && _room != null) {
      try {
        final data = utf8.encode(jsonEncode({'type': 'mute_all'}));
        await _room!.localParticipant?.publishData(data, reliable: true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Demande de coupure micro envoyée.")),
          );
        }
      } catch (e) {
        if (kDebugMode) print("Error muting all: $e");
      }
    }
  }

  Future<void> _toggleRaiseHand() async {
    setState(() => _handRaised = !_handRaised);
    await _db
        .collection('meetings')
        .doc(widget.meetingId)
        .collection('presence')
        .doc(widget.userId)
        .set({'handRaised': _handRaised}, SetOptions(merge: true));
    if (_handRaised) _announce("Vous avez levé la main.");
  }

  Future<void> _toggleScreenShare() async {
    setState(() => _screenShareOn = !_screenShareOn);
    await _room?.localParticipant?.setScreenShareEnabled(_screenShareOn);
  }

  Future<void> _switchCamera() async {
    final localParticipant = _room?.localParticipant;
    if (localParticipant == null) return;

    LocalVideoTrack? videoTrack;
    for (final pub in localParticipant.videoTrackPublications) {
      final track = pub.track;
      if (pub.source == TrackSource.camera && track is LocalVideoTrack) {
        videoTrack = track;
        break;
      }
    }
    if (videoTrack == null) return;

    final currentOptions = videoTrack.currentOptions;
    final currentPosition =
        currentOptions is CameraCaptureOptions ? currentOptions.cameraPosition : null;
    final nextPosition =
        currentPosition == CameraPosition.front ? CameraPosition.back : CameraPosition.front;

    try {
      await videoTrack.restartTrack(
        CameraCaptureOptions(cameraPosition: nextPosition),
      );
    } catch (e) {
      if (kDebugMode) print('Erreur lors du changement de caméra: $e');
    }
  }

  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline, color: Colors.white),
              title: const Text("Informations de la réunion", style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _showMeetingInfo();
              },
            ),
            ListTile(
              leading: Icon(Icons.back_hand, color: _handRaised ? AppColors.primary : Colors.white),
              title: Text(_handRaised ? "Baisser la main" : "Lever la main", style: const TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _toggleRaiseHand();
              },
            ),
            ListTile(
              leading: Icon(Icons.screen_share, color: _screenShareOn ? AppColors.primary : Colors.white),
              title: Text(_screenShareOn ? "Arrêter le partage" : "Partager l'écran", style: const TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _toggleScreenShare();
              },
            ),
            ListTile(
              leading: const Icon(Icons.cameraswitch, color: Colors.white),
              title: const Text("Changer de caméra", style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _switchCamera();
              },
            ),
            ListTile(
              leading: const Icon(Icons.share, color: Colors.white),
              title: const Text("Inviter des participants", style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                final joinUrl = 'https://crux-3c6be.web.app/join/${widget.meetingId}';
                Share.share("Rejoins ma réunion CRUX : ${widget.meetingName}\nID : ${widget.meetingId}\nLien : $joinUrl");
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showMeetingInfo() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(32),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Détails de la réunion",
                style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 20),
            _infoRow("Nom", widget.meetingName),
            _infoRow("Code", widget.meetingId),
            _infoRow("Hôte", widget.isHost ? "Vous" : "Un autre utilisateur"),
            const SizedBox(height: 20),
            Text("Sécurité",
                style: GoogleFonts.poppins(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 14)),
            const Text("Le chiffrement SSL est actif.", style: TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String val) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Text("$label: ", style: const TextStyle(color: Colors.white38)),
            Text(val, style: const TextStyle(color: Colors.white70)),
          ],
        ),
      );

  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text("Quitter?", style: TextStyle(color: Colors.white)),
        content: const Text("Voulez-vous quitter la réunion en cours?", style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Rester")),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text("Quitter")),
        ],
      ),
    );
    if (leave == true) _leave();
  }

  void _leave() {
    MeetingService().removePresence(widget.meetingId, widget.userId);
    _room?.disconnect();
    _room?.dispose();
    Navigator.pop(context);
  }

  // ── UI ───────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: AppColors.error, size: 64),
                const SizedBox(height: 16),
                Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 24),
                ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text("Retour"))
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: _loading
          ? _buildLoading()
          : Stack(children: [
              _buildVideoGrid(),
              _buildTopBar(),
              _buildSubtitleOverlay(),
              _buildBottomBar(),
              if (_showChat) _buildChatPanel(),
              if (_showParticipants) _buildParticipantsPanel(),
              if (_showNotes) _buildNotesPanel(),
            ]),
    );
  }

  Widget _buildLoading() => Center(
          child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
          const SizedBox(height: 20),
          Text("Préparation de votre espace...", style: GoogleFonts.poppins(color: Colors.white54, fontSize: 13)),
        ],
      ));

  Widget _buildVideoGrid() {
    final local = _room?.localParticipant;
    final List<dynamic> all = [
      if (local != null) local,
      ..._remoteParticipants,
    ];
    // Limit visible tiles to maintain performance in 1000+ sessions
    final visible = all.take(AppConfig.livekitVisibleTileCap).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(0, 90, 0, 110),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.8),
        itemCount: visible.length,
        itemBuilder: (_, i) => _buildParticipantTile(visible[i]),
      ),
    );
  }

  Widget _buildParticipantTile(dynamic p) {
    bool isSpeaking = _activeSpeakerId == p.identity;

    VideoTrack? videoTrack;
    bool isScreenShare = false;
    bool hasVideo = false;

    // Look for active, unmuted video tracks (either camera or screen share)
    if (p.videoTrackPublications != null) {
      for (final pub in p.videoTrackPublications) {
        if (pub.track != null && pub.track is VideoTrack && pub.muted == false) {
          videoTrack = pub.track as VideoTrack;
          isScreenShare = pub.source == TrackSource.screenShareVideo;
          hasVideo = true;
          break;
        }
      }
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isSpeaking ? AppColors.primary : Colors.white.withValues(alpha: 0.05), width: 2),
        boxShadow: isSpeaking ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 15)] : [],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(children: [
          Positioned.fill(
            child: hasVideo && videoTrack != null
                ? VideoTrackRenderer(
                    videoTrack,
                    fit: isScreenShare
                        ? VideoViewFit.contain
                        : VideoViewFit.cover,
                  )
                : Center(child: _buildAvatar(p.name ?? p.identity, large: true)),
          ),
          Positioned(
              bottom: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(8)),
                child: Text((p.name != null && p.name!.isNotEmpty) ? p.name! : "Invité",
                    style: GoogleFonts.poppins(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
              )),
          if (_raisedHands.contains(p.identity))
            const Positioned(top: 12, right: 12, child: Icon(Icons.back_hand, color: Colors.orange, size: 20)),
          if (isScreenShare)
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(6)),
                child: const Row(
                  children: [
                    Icon(Icons.screen_share, color: Colors.white, size: 12),
                    SizedBox(width: 4),
                    Text("ÉCRAN PARTAGÉ", style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
        ]),
      ),
    ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.9, 0.9));
  }

  Widget _buildAvatar(String name, {bool large = false}) {
    return Container(
      width: large ? 60 : 32,
      height: large ? 60 : 32,
      decoration: BoxDecoration(gradient: AppColors.primaryGradient, shape: BoxShape.circle),
      child: Center(
          child: Text(name.isNotEmpty ? name[0].toUpperCase() : "?",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: large ? 24 : 14))),
    );
  }

  Widget _buildSubtitleOverlay() {
    if (_currentTranscription.isEmpty) return const SizedBox();
    return Positioned(
      bottom: 110,
      left: 30,
      right: 30,
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
                color: Colors.black54, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: 0.1))),
            child: Text(_currentTranscription,
                textAlign: TextAlign.center, style: GoogleFonts.poppins(color: Colors.white, fontSize: 13, height: 1.4)),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          decoration: const BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black87, Colors.transparent])),
          child: SafeArea(
              child: Row(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.meetingName,
                  style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
              Text("ID: ${widget.meetingId}", style: GoogleFonts.poppins(color: Colors.white38, fontSize: 11)),
            ]),
            const Spacer(),
            _ActionBtn(
                icon: _voiceAssistant ? Icons.volume_up : Icons.volume_off,
                onTap: () => setState(() => _voiceAssistant = !_voiceAssistant)),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _announce("Voulez-vous vraiment quitter ?").then((_) => _confirmLeave()),
              child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.error.withValues(alpha: 0.5))),
                  child: const Text("Quitter",
                      style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold, fontSize: 12))),
            ),
          ])),
        ));
  }

  Widget _buildBottomBar() {
    return Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          decoration: const BoxDecoration(
              color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _ActionBtn(icon: _micOn ? Icons.mic : Icons.mic_off, color: _micOn ? null : AppColors.error, onTap: _toggleMic),
            _ActionBtn(
                icon: _camOn ? Icons.videocam : Icons.videocam_off, color: _camOn ? null : AppColors.error, onTap: _toggleCam),
            _ActionBtn(icon: Icons.chat_bubble_outline, onTap: () => setState(() => _showChat = true)),
            _ActionBtn(icon: Icons.note_alt_outlined, onTap: () => setState(() => _showNotes = true)),
            _ActionBtn(icon: Icons.people_outline, onTap: () => setState(() => _showParticipants = true)),
            _ActionBtn(icon: Icons.more_horiz, onTap: _showMoreOptions),
          ]),
        ));
  }

  // ── PANELS ───────────────────────────────────

  Widget _buildChatPanel() => _BasePanel(
      title: "Chat ${_privateRecipientName != null ? '(Privé à $_privateRecipientName)' : ''}",
      onClose: () => setState(() => _showChat = false),
      child: Column(children: [
        if (_privateRecipientId != null)
          Container(
              color: AppColors.primary.withOpacity(0.1),
              child: ListTile(
                  title: Text("Mode privé actif",
                      style: GoogleFonts.poppins(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold)),
                  trailing: IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () => setState(() {
                            _privateRecipientId = null;
                            _privateRecipientName = null;
                          })))),
        Expanded(
            child: StreamBuilder<QuerySnapshot>(
          stream: _db
              .collection('meetings')
              .doc(widget.meetingId)
              .collection('chat')
              .orderBy('timestamp', descending: true)
              .snapshots(),
          builder: (_, snap) {
            if (!snap.hasData) return const SizedBox();
            final messages = snap.data!.docs.where((d) {
              final data = d.data() as Map<String, dynamic>;
              if (data['isPrivate'] == true) {
                return data['recipientId'] == widget.userId || data['senderId'] == widget.userId;
              }
              return true;
            }).toList();
            return ListView.builder(
                reverse: true,
                itemCount: messages.length,
                itemBuilder: (_, i) => _ChatBubble(
                    data: messages[i].data() as Map<String, dynamic>, isMe: messages[i]['senderId'] == widget.userId));
          },
        )),
        _buildChatInput(),
      ]));

  Widget _buildChatInput() {
    final ctrl = TextEditingController();
    return Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Row(children: [
          Expanded(
              child: TextField(
                  controller: ctrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                      hintText: "Écrire...",
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none)))),
          const SizedBox(width: 8),
          IconButton(
              icon: const Icon(Icons.send, color: AppColors.primary),
              onPressed: () {
                if (ctrl.text.trim().isEmpty) return;
                _db.collection('meetings').doc(widget.meetingId).collection('chat').add({
                  'senderId': widget.userId,
                  'sender': widget.userName,
                  'message': ctrl.text,
                  'text': ctrl.text,
                  'timestamp': FieldValue.serverTimestamp(),
                  'isPrivate': _privateRecipientId != null,
                  'recipientId': _privateRecipientId
                });
                ctrl.clear();
              }),
        ]));
  }

  Widget _buildParticipantsPanel() {
    final local = _room?.localParticipant;
    final List<Participant> allParticipants = [
      if (local != null) local,
      ..._remoteParticipants,
    ];

    final isMeOrganizer = widget.isHost || widget.userId == _organizerId;

    return _BasePanel(
      title: "Membres (${allParticipants.length})",
      onClose: () => setState(() => _showParticipants = false),
      child: Column(
        children: [
          if (isMeOrganizer)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _muteAllOthers,
                  icon: const Icon(Icons.mic_off, color: Colors.white, size: 18),
                  label: const Text(
                    "Muter tous les autres",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: allParticipants.length,
              itemBuilder: (context, index) {
                final p = allParticipants[index];
                final isLocal = p == local;
                final isOrganizer = p.identity == _organizerId;

                bool isMicMuted = true;
                if (isLocal) {
                  isMicMuted = !_micOn;
                } else {
                  for (final pub in p.audioTrackPublications) {
                    if (!pub.muted) {
                      isMicMuted = false;
                      break;
                    }
                  }
                }

                String displayName = p.name ?? p.identity;
                if (isLocal) {
                  displayName += " (vous)";
                }
                if (isOrganizer) {
                  displayName += " 👑";
                }

                return ListTile(
                  leading: _buildAvatar(p.name ?? p.identity),
                  title: Text(
                    displayName,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    isMicMuted ? "Micro désactivé" : "Micro actif",
                    style: TextStyle(
                      color: isMicMuted ? Colors.white38 : Colors.greenAccent,
                      fontSize: 11,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isMicMuted ? Icons.mic_off : Icons.mic,
                        color: isMicMuted ? Colors.white38 : Colors.greenAccent,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      if (_raisedHands.contains(p.identity))
                        const Padding(
                          padding: EdgeInsets.only(right: 8.0),
                          child: Icon(Icons.back_hand, color: Colors.orange, size: 16),
                        ),
                      IconButton(
                        icon: const Icon(Icons.message_outlined, color: Colors.white38),
                        onPressed: () {
                          if (p.identity == widget.userId) return;
                          setState(() {
                            _privateRecipientId = p.identity;
                            _privateRecipientName = p.name ?? p.identity;
                            _showParticipants = false;
                            _showChat = true;
                          });
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesPanel() {
    return _BasePanel(
        title: "Notes de Réunion",
        onClose: () {
          NoteService.instance.saveMeetingNote(
              userId: widget.userId,
              meetingId: widget.meetingId,
              meetingName: widget.meetingName,
              content: _noteController.text);
          _announce("Notes sauvegardées.");
          setState(() => _showNotes = false);
        },
        child: Container(
          padding: const EdgeInsets.all(20),
          child: TextField(
            controller: _noteController,
            maxLines: null,
            style: GoogleFonts.poppins(color: Colors.white, height: 1.6),
            decoration: const InputDecoration(
                hintText: "Tapez vos notes ici... elles seront liées à l'historique de cette réunion.",
                hintStyle: TextStyle(color: Colors.white24),
                border: InputBorder.none),
          ),
        ));
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
  const _ActionBtn({required this.icon, required this.onTap, this.color});
  @override
  Widget build(BuildContext context) =>
      IconButton(icon: Icon(icon, color: color ?? Colors.white70, size: 26), onPressed: onTap);
}

class _BasePanel extends StatelessWidget {
  final String title;
  final Widget child;
  final VoidCallback onClose;
  const _BasePanel({required this.title, required this.child, required this.onClose});
  @override
  Widget build(BuildContext context) => Positioned.fill(
      child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
              color: Colors.black.withOpacity(0.9),
              child: Column(children: [
                AppBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    title: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16)),
                    leading: IconButton(icon: const Icon(Icons.close), onPressed: onClose)),
                Expanded(child: child),
              ])))).animate().slideY(begin: 1, end: 0, duration: 400.ms, curve: Curves.easeOutCubic);
}

class _ChatBubble extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isMe;
  const _ChatBubble({required this.data, required this.isMe});
  @override
  Widget build(BuildContext context) {
    String timeStr = '';
    if (data['timestamp'] != null) {
      final ts = data['timestamp'];
      DateTime? dt;
      if (ts is Timestamp) {
        dt = ts.toDate();
      } else if (ts is int) {
        dt = DateTime.fromMillisecondsSinceEpoch(ts);
      }
      if (dt != null) {
        final localDt = dt.toLocal();
        final hour = localDt.hour.toString().padLeft(2, '0');
        final minute = localDt.minute.toString().padLeft(2, '0');
        timeStr = "$hour:$minute";
      }
    }
    if (timeStr.isEmpty) {
      final now = DateTime.now();
      final hour = now.hour.toString().padLeft(2, '0');
      final minute = now.minute.toString().padLeft(2, '0');
      timeStr = "$hour:$minute";
    }

    return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: isMe ? AppColors.primary : Colors.white12, borderRadius: BorderRadius.circular(16)),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isMe)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(data['sender'] ?? 'Anonyme',
                            style: const TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.bold))),
                  Text(data['message'] ?? data['text'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 13)),
                  const SizedBox(height: 4),
                  Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (data['isPrivate'] == true) ...[
                              const Icon(Icons.lock, color: Colors.amber, size: 10),
                              const SizedBox(width: 4),
                              const Text("Privé",
                                  style: TextStyle(color: Colors.amber, fontSize: 9, fontWeight: FontWeight.bold)),
                              const SizedBox(width: 8),
                            ],
                            Text(timeStr, style: const TextStyle(color: Colors.white38, fontSize: 9)),
                          ])),
                ])));
  }
}
