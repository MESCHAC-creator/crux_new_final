import 'dart:async';
import 'dart:convert';
import 'dart:ui' show ImageFilter;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../config/app_config.dart';
import '../providers/locale_provider.dart';
import '../services/error_handler_service.dart';
import '../services/livekit_service.dart';
import '../services/meeting_service.dart';
import '../services/pro_service.dart';
import '../theme/colors.dart';
import '../utils/logger.dart' as crux;

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
  State<LargeConferenceScreen> createState() =>
      _LargeConferenceScreenState();
}

class _LargeConferenceScreenState extends State<LargeConferenceScreen>
    with WidgetsBindingObserver {
  // ===========================================================================
  // CONFIGURATION WEBINAR
  // ===========================================================================

  static const int _maxVisibleVideos = 10;
  static const int _targetParticipants = 5000;

  // ===========================================================================
  // SERVICES
  // ===========================================================================

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final ErrorHandlerService _errorHandler = ErrorHandlerService();

  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();

  // ===========================================================================
  // LIVEKIT
  // ===========================================================================

  Room? _room;
  EventsListener<RoomEvent>? _roomListener;

  bool _isConnecting = false;
  bool _isReconnecting = false;

  int _reconnectAttempts = 0;

  // ===========================================================================
  // PARTICIPANTS
  // ===========================================================================

  List<RemoteParticipant> _remoteParticipants = [];

  String? _activeSpeakerId;
  String? _organizerId;

  // ===========================================================================
  // LOCAL MEDIA
  // ===========================================================================

  bool _micOn = true;
  bool _camOn = true;
  bool _screenSharing = false;

  // ===========================================================================
  // UI
  // ===========================================================================

  bool _loading = true;
  String? _error;

  bool _showChat = false;
  bool _showParticipants = false;
  bool _showNotes = false;
  bool _showMore = false;

  bool _voiceAssistant = false;
  bool _liveCaptions = false;
  bool _handRaised = false;

  final Set<String> _raisedHands = <String>{};

  // ===========================================================================
  // TRANSCRIPTION
  // ===========================================================================

  String _currentTranscription = '';

  // ===========================================================================
  // TIMER / PRO
  // ===========================================================================

  Timer? _callTimer;

  int _secondsElapsed = 0;

  bool _isPro = false;
  bool _paywallShown = false;

  // ===========================================================================
  // FIRESTORE
  // ===========================================================================

  StreamSubscription<QuerySnapshot>? _presenceSubscription;

  // ===========================================================================
  // CONTROLLERS
  // ===========================================================================

  late final TextEditingController _chatController;
  late final TextEditingController _noteController;

  // ===========================================================================
  // CHAT
  // ===========================================================================

  final List<_ChatMessage> _chatMessages = <_ChatMessage>[];

  // ===========================================================================
  // LIFECYCLE
  // ===========================================================================

  @override
  void initState() {
    super.initState();

    _chatController = TextEditingController();
    _noteController = TextEditingController();

    WidgetsBinding.instance.addObserver(this);

    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _callTimer?.cancel();

    _presenceSubscription?.cancel();

    _roomListener?.dispose();

    _room?.disconnect();

    _tts.stop();
    _speech.stop();

    _chatController.dispose();
    _noteController.dispose();

    super.dispose();
  }

  // ===========================================================================
  // INITIALISATION
  // ===========================================================================

  Future<void> _initialize() async {
    try {
      await _loadPreferences();
      await _checkPro();
      await _loadOrganizer();
      await _registerPresence();
      await _connect();

      _listenPresence();

      _startTimer();

      if (!mounted) return;

      setState(() {
        _loading = false;
      });
    } catch (e, st) {
      crux.logger.e(
        'Large conference initialization failed',
        error: e,
        stackTrace: st,
      );

      _showError(e);
    }
  }

  // ===========================================================================
  // PREFERENCES
  // ===========================================================================

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (!mounted) return;

      setState(() {
        _micOn = prefs.getBool('crux_mic_default') ?? true;
        _camOn = prefs.getBool('crux_cam_default') ?? true;
      });
    } catch (e) {
      crux.logger.w(
        'Could not load conference preferences',
        error: e,
      );
    }
  }

  // ===========================================================================
  // PRO
  // ===========================================================================

  Future<void> _checkPro() async {
    try {
      final value =
          await ProService().checkProStatus(widget.userId);

      if (!mounted) return;

      setState(() {
        _isPro = value;
      });
    } catch (e) {
      crux.logger.w(
        'Pro check failed',
        error: e,
      );
    }
  }

  // ===========================================================================
  // ORGANIZER
  // ===========================================================================

  Future<void> _loadOrganizer() async {
    try {
      final doc = await _db
          .collection(AppConfig.meetingsCollection)
          .doc(widget.meetingId)
          .get();

      if (!doc.exists) return;

      final data = doc.data();

      if (data == null) return;

      _organizerId = data['organizerId']?.toString();
    } catch (e) {
      crux.logger.w(
        'Could not load organizer',
        error: e,
      );
    }
  }

  // ===========================================================================
  // PRESENCE
  // ===========================================================================

  Future<void> _registerPresence() async {
    await MeetingService().registerPresence(
      widget.meetingId,
      widget.userId,
      widget.userName,
    );

    if (widget.isHost) {
      await MeetingService().updateMeetingStatus(
        widget.meetingId,
        MeetingStatus.ongoing,
      );
    }
  }

  void _listenPresence() {
    _presenceSubscription = _db
        .collection(AppConfig.meetingsCollection)
        .doc(widget.meetingId)
        .collection('presence')
        .snapshots()
        .listen(
      (snapshot) {
        if (!mounted) return;

        final hands = <String>{};

        for (final doc in snapshot.docs) {
          final data = doc.data();

          if (data['handRaised'] == true) {
            hands.add(doc.id);
          }
        }

        setState(() {
          _raisedHands
            ..clear()
            ..addAll(hands);
        });
      },
    );
  }

  // ===========================================================================
  // LIVEKIT CONNECTION
  // ===========================================================================

  Future<void> _connect() async {
    if (_isConnecting) return;

    _isConnecting = true;

    try {
      if (!AppConfig.isLiveKitConfigured) {
        throw Exception(
          'LiveKit n’est pas correctement configuré.',
        );
      }

      crux.logger.i(
        'Connecting to webinar ${widget.meetingId}',
      );

      final token =
          await LiveKitService.instance.fetchToken(
        room: widget.meetingId,
        identity: widget.userId,
        name: widget.userName,
        isHost: widget.isHost,
      );

      if (token == null || token.isEmpty) {
        throw Exception(
          'Impossible d’obtenir le token LiveKit.',
        );
      }

      await _disposeRoom();

      // -----------------------------------------------------------------------
      // ROOM OPTIMISÉE POUR GRANDE CONFÉRENCE
      // -----------------------------------------------------------------------

      final room = Room(
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          defaultVideoPublishOptions: VideoPublishOptions(
            simulcast: true,
          ),
        ),
      );

      _room = room;

      // -----------------------------------------------------------------------
      // EVENT LISTENER AVANT CONNECTION
      // -----------------------------------------------------------------------

      _roomListener = room.createListener();

      _setupRoomEvents(_roomListener!);

      // -----------------------------------------------------------------------
      // CONNECTION
      // -----------------------------------------------------------------------

      await room
          .connect(
            AppConfig.livekitWssUrl,
            token,
          )
          .timeout(
        AppConfig.roomConnectionTimeout,
        onTimeout: () {
          throw TimeoutException(
            'La connexion LiveKit a expiré.',
          );
        },
      );

      // -----------------------------------------------------------------------
      // LOCAL PARTICIPANT
      // -----------------------------------------------------------------------

      final local = room.localParticipant;

      if (local != null) {
        await local.setMicrophoneEnabled(_micOn);
        await local.setCameraEnabled(_camOn);
      }

      _refreshParticipants();

      _reconnectAttempts = 0;

      crux.logger.i(
        'Connected to webinar. '
        'remoteParticipants=${room.remoteParticipants.length}',
      );
    } finally {
      _isConnecting = false;
    }
  }

  // ===========================================================================
  // ROOM EVENTS
  // ===========================================================================

  void _setupRoomEvents(
    EventsListener<RoomEvent> listener,
  ) {
    listener
      ..on<RoomConnectedEvent>((_) {
        _refreshParticipants();
      })
      ..on<RoomDisconnectedEvent>((_) {
        if (!mounted) return;

        _attemptReconnect();
      })
      ..on<RoomReconnectingEvent>((_) {
        if (!mounted) return;

        setState(() {
          _isReconnecting = true;
        });
      })
      ..on<RoomReconnectedEvent>((_) {
        if (!mounted) return;

        _reconnectAttempts = 0;

        setState(() {
          _isReconnecting = false;
        });

        _refreshParticipants();
      })
      ..on<ParticipantConnectedEvent>((event) {
        _refreshParticipants();

        if (_voiceAssistant) {
          _announce(
            '${event.participant.name.isNotEmpty ? event.participant.name : 'Un participant'} a rejoint.',
          );
        }
      })
      ..on<ParticipantDisconnectedEvent>((event) {
        _refreshParticipants();

        if (_voiceAssistant) {
          _announce(
            '${event.participant.name.isNotEmpty ? event.participant.name : 'Un participant'} a quitté.',
          );
        }
      })
      ..on<ActiveSpeakersChangedEvent>((event) {
        if (!mounted) return;

        if (event.speakers.isEmpty) {
          setState(() {
            _activeSpeakerId = null;
          });
        } else {
          setState(() {
            _activeSpeakerId =
                event.speakers.first.identity;
          });
        }
      })
      ..on<ParticipantMetadataChangedEvent>((_) {
        _refreshParticipants();
      })
      ..on<TrackSubscribedEvent>((_) {
        _refreshParticipants();
      })
      ..on<TrackUnsubscribedEvent>((_) {
        _refreshParticipants();
      })
      ..on<DataReceivedEvent>(_handleDataReceived);
  }

  // ===========================================================================
  // PARTICIPANTS
  // ===========================================================================

  void _refreshParticipants() {
    final room = _room;

    if (!mounted || room == null) return;

    setState(() {
      _remoteParticipants =
          room.remoteParticipants.values.toList();
    });
  }

  /// IMPORTANT :
  ///
  /// La room peut contenir des milliers de participants.
  ///
  /// Cette méthode est la barrière de rendu :
  /// Flutter ne reçoit dans la grille que les 10 participants
  /// prioritaires.
  List<RemoteParticipant> get _visibleParticipants {
    final participants =
        List<RemoteParticipant>.from(
      _remoteParticipants,
    );

    participants.sort(
      (a, b) {
        // 1. Active speaker
        final aActive =
            a.identity == _activeSpeakerId;
        final bActive =
            b.identity == _activeSpeakerId;

        if (aActive && !bActive) return -1;
        if (!aActive && bActive) return 1;

        // 2. Participants avec vidéo publiée
        final aVideo = _hasVideo(a);
        final bVideo = _hasVideo(b);

        if (aVideo && !bVideo) return -1;
        if (!aVideo && bVideo) return 1;

        // 3. Nom
        return a.name
            .toLowerCase()
            .compareTo(
              b.name.toLowerCase(),
            );
      },
    );

    return participants
        .take(_maxVisibleVideos - 1)
        .toList();
  }

  bool _hasVideo(RemoteParticipant participant) {
    return participant.videoTrackPublications.values.any(
      (publication) =>
          publication.subscribed &&
          !publication.muted,
    );
  }

  int get _participantCount {
    final room = _room;

    if (room == null) {
      return _remoteParticipants.length + 1;
    }

    return room.remoteParticipants.length + 1;
  }

  // ===========================================================================
  // DATA MESSAGES
  // ===========================================================================

  void _handleDataReceived(DataReceivedEvent event) {
    try {
      final text = utf8.decode(event.data);

      final dynamic decoded = jsonDecode(text);

      if (decoded is! Map<String, dynamic>) {
        return;
      }

      final type = decoded['type']?.toString();

      if (type == 'mute_all') {
        final sender =
            event.participant?.identity;

        if (sender == _organizerId &&
            _micOn) {
          _toggleMic();

          _announce(
            'L’organisateur a coupé votre microphone.',
          );
        }

        return;
      }

      if (type == 'raise_hand') {
        final identity =
            decoded['identity']?.toString();

        if (identity == null) return;

        if (mounted) {
          setState(() {
            _raisedHands.add(identity);
          });
        }

        return;
      }

      if (type == 'lower_hand') {
        final identity =
            decoded['identity']?.toString();

        if (identity == null) return;

        if (mounted) {
          setState(() {
            _raisedHands.remove(identity);
          });
        }

        return;
      }

      if (type == 'chat') {
        final sender =
            decoded['sender']?.toString() ??
                'Participant';

        final message =
            decoded['message']?.toString() ?? '';

        if (message.isEmpty) return;

        if (mounted) {
          setState(() {
            _chatMessages.add(
              _ChatMessage(
                sender: sender,
                message: message,
                isMe: false,
              ),
            );
          });
        }
      }
    } catch (e) {
      crux.logger.w(
        'Invalid LiveKit data packet',
        error: e,
      );
    }
  }

  // ===========================================================================
  // RECONNECTION
  // ===========================================================================

  Future<void> _attemptReconnect() async {
    if (_isReconnecting ||
        !mounted ||
        _reconnectAttempts >=
            AppConfig.maxReconnectAttempts) {
      return;
    }

    _isReconnecting = true;

    _reconnectAttempts++;

    try {
      await Future<void>.delayed(
        AppConfig.reconnectDelay *
            _reconnectAttempts,
      );

      await _connect();

      if (mounted) {
        setState(() {
          _isReconnecting = false;
        });
      }
    } catch (e) {
      crux.logger.w(
        'Reconnect attempt $_reconnectAttempts failed',
        error: e,
      );

      if (mounted) {
        setState(() {
          _isReconnecting = false;
        });
      }

      if (_reconnectAttempts <
          AppConfig.maxReconnectAttempts) {
        unawaited(_attemptReconnect());
      }
    }
  }

  // ===========================================================================
  // TIMER
  // ===========================================================================

  void _startTimer() {
    _callTimer?.cancel();

    _callTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (!mounted) return;

        setState(() {
          _secondsElapsed++;
        });

        if (_isPro) return;

        final limit =
            AppConfig.freeMeetingDurationMinutes *
                60;

        final warning = limit - 300;

        if (_secondsElapsed == warning &&
            warning > 0) {
          _announce(
            'Attention, votre réunion gratuite se terminera dans 5 minutes.',
          );
        }

        if (_secondsElapsed >= limit &&
            !_paywallShown) {
          _paywallShown = true;

          _callTimer?.cancel();

          _showPaywall();
        }
      },
    );
  }

  String _formatDuration() {
    final hours = _secondsElapsed ~/ 3600;
    final minutes =
        (_secondsElapsed % 3600) ~/ 60;
    final seconds =
        _secondsElapsed % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  // ===========================================================================
  // AUDIO
  // ===========================================================================

  Future<void> _announce(String text) async {
    if (!_voiceAssistant) return;

    try {
      await _tts.setLanguage('fr-FR');
      await _tts.setPitch(1.0);
      await _tts.speak(text);
    } catch (e) {
      crux.logger.w(
        'TTS failed',
        error: e,
      );
    }
  }

  // ===========================================================================
  // MICROPHONE
  // ===========================================================================

  Future<void> _toggleMic() async {
    final room = _room;

    if (room == null) return;

    final local = room.localParticipant;

    if (local == null) return;

    final next = !_micOn;

    await local.setMicrophoneEnabled(next);

    if (!mounted) return;

    setState(() {
      _micOn = next;
    });
  }

  // ===========================================================================
  // CAMERA
  // ===========================================================================

  Future<void> _toggleCamera() async {
    final room = _room;

    if (room == null) return;

    final local = room.localParticipant;

    if (local == null) return;

    final next = !_camOn;

    await local.setCameraEnabled(next);

    if (!mounted) return;

    setState(() {
      _camOn = next;
    });
  }

  // ===========================================================================
  // SCREEN SHARE
  // ===========================================================================

  Future<void> _toggleScreenShare() async {
    final room = _room;

    if (room == null) return;

    final local = room.localParticipant;

    if (local == null) return;

    try {
      final next = !_screenSharing;

      await local.setScreenShareEnabled(
        next,
      );

      if (!mounted) return;

      setState(() {
        _screenSharing = next;
      });
    } catch (e) {
      crux.logger.w(
        'Screen share failed',
        error: e,
      );
    }
  }

  // ===========================================================================
  // CAMERA SWITCH
  // ===========================================================================

  Future<void> _switchCamera() async {
    final room = _room;

    if (room == null) return;

    final local = room.localParticipant;

    if (local == null) return;

    try {
      final publication =
          local.videoTrackPublications.values
              .firstWhere(
        (p) => p.track != null,
      );

      final track = publication.track;

      if (track != null) {
        await track.switchCamera();
      }
    } catch (e) {
      crux.logger.w(
        'Camera switch failed',
        error: e,
      );
    }
  }

  // ===========================================================================
  // RAISE HAND
  // ===========================================================================

  Future<void> _toggleRaiseHand() async {
    final next = !_handRaised;

    if (!mounted) return;

    setState(() {
      _handRaised = next;
    });

    await _db
        .collection(AppConfig.meetingsCollection)
        .doc(widget.meetingId)
        .collection('presence')
        .doc(widget.userId)
        .set(
      {
        'handRaised': next,
        'userId': widget.userId,
        'userName': widget.userName,
      },
      SetOptions(merge: true),
    );

    _sendData(
      {
        'type':
            next ? 'raise_hand' : 'lower_hand',
        'identity': widget.userId,
      },
    );
  }

  // ===========================================================================
  // LIVE CAPTIONS
  // ===========================================================================

  Future<void> _toggleCaptions() async {
    if (_liveCaptions) {
      await _speech.stop();

      if (!mounted) return;

      setState(() {
        _liveCaptions = false;
        _currentTranscription = '';
      });

      return;
    }

    try {
      final available =
          await _speech.initialize();

      if (!available) {
        return;
      }

      if (!mounted) return;

      setState(() {
        _liveCaptions = true;
      });

      await _speech.listen(
        localeId: 'fr_FR',
        onResult: (result) {
          if (!mounted) return;

          setState(() {
            _currentTranscription =
                result.recognizedWords;
          });
        },
      );
    } catch (e) {
      crux.logger.w(
        'Speech recognition failed',
        error: e,
      );

      if (mounted) {
        setState(() {
          _liveCaptions = false;
        });
      }
    }
  }

  // ===========================================================================
  // SEND DATA
  // ===========================================================================

  Future<void> _sendData(
    Map<String, dynamic> payload,
  ) async {
    final room = _room;

    if (room == null) return;

    try {
      final data = utf8.encode(
        jsonEncode(payload),
      );

      await room.localParticipant.publishData(
        data,
        reliable: true,
      );
    } catch (e) {
      crux.logger.w(
        'LiveKit data send failed',
        error: e,
      );
    }
  }

  // ===========================================================================
  // CHAT
  // ===========================================================================

  Future<void> _sendChat() async {
    final text =
        _chatController.text.trim();

    if (text.isEmpty) return;

    _chatController.clear();

    if (mounted) {
      setState(() {
        _chatMessages.add(
          _ChatMessage(
            sender: widget.userName,
            message: text,
            isMe: true,
          ),
        );
      });
    }

    await _sendData(
      {
        'type': 'chat',
        'sender': widget.userName,
        'senderId': widget.userId,
        'message': text,
      },
    );

    try {
      await _db
          .collection(AppConfig.meetingsCollection)
          .doc(widget.meetingId)
          .collection('chat')
          .add(
        {
          'senderId': widget.userId,
          'sender': widget.userName,
          'message': text,
          'timestamp':
              FieldValue.serverTimestamp(),
        },
      );
    } catch (e) {
      crux.logger.w(
        'Firestore chat failed',
        error: e,
      );
    }
  }

  // ===========================================================================
  // MUTE ALL
  // ===========================================================================

  Future<void> _muteAll() async {
    if (!_isOrganizer) return;

    await _sendData(
      {
        'type': 'mute_all',
        'senderId': widget.userId,
      },
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Demande de coupure envoyée aux intervenants.',
        ),
      ),
    );
  }

  bool get _isOrganizer {
    return widget.isHost ||
        widget.userId == _organizerId;
  }

  // ===========================================================================
  // LEAVE
  // ===========================================================================

  Future<void> _confirmLeave() async {
    final result =
        await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text(
            'Quitter la réunion ?',
            style: TextStyle(
              color: Colors.white,
            ),
          ),
          content: const Text(
            'Voulez-vous vraiment quitter cette conférence ?',
            style: TextStyle(
              color: Colors.white70,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, false),
              child: const Text('Rester'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    AppColors.error,
              ),
              child: const Text('Quitter'),
            ),
          ],
        );
      },
    );

    if (result == true) {
      await _leave();
    }
  }

  Future<void> _leave() async {
    try {
      _callTimer?.cancel();

      await MeetingService()
          .saveMeetingHistoryForUser(
        meetingId: widget.meetingId,
        userId: widget.userId,
        title: widget.meetingName,
        durationSeconds: _secondsElapsed,
        endMeeting: widget.isHost,
      );

      await MeetingService().removePresence(
        widget.meetingId,
        widget.userId,
      );

      await _disposeRoom();

      if (!mounted) return;

      Navigator.of(context).pop();
    } catch (e) {
      crux.logger.w(
        'Leave conference error',
        error: e,
      );

      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  // ===========================================================================
  // ROOM DISPOSAL
  // ===========================================================================

  Future<void> _disposeRoom() async {
    try {
      await _roomListener?.dispose();
    } catch (_) {}

    _roomListener = null;

    final room = _room;

    _room = null;

    if (room != null) {
      try {
        await room.disconnect();
      } catch (_) {}
    }

    _remoteParticipants = [];
  }

  // ===========================================================================
  // PAYWALL
  // ===========================================================================

  void _showPaywall() {
    if (!mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text(
            'Temps écoulé',
            style: TextStyle(
              color: Colors.white,
            ),
          ),
          content: Text(
            'La limite de '
            '${AppConfig.freeMeetingDurationMinutes} '
            'minutes de la formule gratuite est atteinte.',
            style: const TextStyle(
              color: Colors.white70,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _leave();
              },
              child: const Text('Quitter'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);

                ProService().startPayment(
                  userId: widget.userId,
                  userName: widget.userName,
                );
              },
              child: const Text(
                'Devenir Pro',
              ),
            ),
          ],
        );
      },
    );
  }

  // ===========================================================================
  // ERROR
  // ===========================================================================

  void _showError(Object error) {
    if (!mounted) return;

    final lang =
        context.read<LocaleProvider>()
            .locale.languageCode;

    setState(() {
      _loading = false;

      _error =
          _errorHandler.getMeetingErrorMessageL(
        error.toString(),
        lang,
      );
    });
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _buildError();
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Stack(
          children: [
            _buildConferenceBackground(),

            if (_loading)
              _buildLoading()
            else
              _buildMainConference(),

            if (_isReconnecting)
              _buildReconnectBanner(),

            if (_showChat)
              _buildChatPanel(),

            if (_showParticipants)
              _buildParticipantsPanel(),

            if (_showNotes)
              _buildNotesPanel(),

            if (_showMore)
              _buildMorePanel(),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // BACKGROUND
  // ===========================================================================

  Widget _buildConferenceBackground() {
    return Positioned.fill(
      child: Container(
        color: AppColors.background,
      ),
    );
  }

  // ===========================================================================
  // LOADING
  // ===========================================================================

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 2,
          ),
          const SizedBox(height: 20),
          Text(
            'Connexion au webinaire...',
            style: GoogleFonts.poppins(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'CRUX Large Conference',
            style: GoogleFonts.poppins(
              color: Colors.white38,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // MAIN
  // ===========================================================================

  Widget _buildMainConference() {
    return Stack(
      children: [
        Positioned.fill(
          child: _buildVideoArea(),
        ),

        _buildTopBar(),

        _buildCaptionOverlay(),

        _buildBottomControls(),
      ],
    );
  }

  // ===========================================================================
  // VIDEO AREA
  // ===========================================================================

  Widget _buildVideoArea() {
    final visible =
        _visibleParticipants;

    final totalTiles =
        visible.length + 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        10,
        90,
        10,
        120,
      ),
      child: totalTiles == 1
          ? _buildSoloSpeaker()
          : GridView.builder(
              physics:
                  const BouncingScrollPhysics(),
              gridDelegate:
                  SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount:
                    _calculateColumns(
                  totalTiles,
                ),
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio:
                    _calculateAspectRatio(
                  totalTiles,
                ),
              ),
              itemCount: totalTiles,
              itemBuilder: (_, index) {
                if (index == 0) {
                  return _buildLocalTile();
                }

                return _buildRemoteTile(
                  visible[index - 1],
                );
              },
            ),
    );
  }

  int _calculateColumns(int count) {
    if (count <= 2) return 1;
    if (count <= 4) return 2;
    if (count <= 9) return 3;
    return 5;
  }

  double _calculateAspectRatio(int count) {
    if (count <= 2) return 1.45;
    if (count <= 4) return 1.25;
    return 1.15;
  }

  // ===========================================================================
  // SOLO
  // ===========================================================================

  Widget _buildSoloSpeaker() {
    return _buildLocalTile(
      large: true,
    );
  }

  // ===========================================================================
  // LOCAL TILE
  // ===========================================================================

  Widget _buildLocalTile({
    bool large = false,
  }) {
    final room = _room;

    final local = room?.localParticipant;

    return _VideoTile(
      participant: local,
      name: '${widget.userName} (vous)',
      isLocal: true,
      active:
          _activeSpeakerId ==
          widget.userId,
      large: large,
      camEnabled: _camOn,
      raised:
          _raisedHands.contains(
        widget.userId,
      ),
    );
  }

  // ===========================================================================
  // REMOTE TILE
  // ===========================================================================

  Widget _buildRemoteTile(
    RemoteParticipant participant,
  ) {
    return _VideoTile(
      participant: participant,
      name: participant.name.isNotEmpty
          ? participant.name
          : 'Participant',
      active:
          participant.identity ==
          _activeSpeakerId,
      raised:
          _raisedHands.contains(
        participant.identity,
      ),
      large:
          participant.identity ==
          _activeSpeakerId,
    );
  }

  // ===========================================================================
  // TOP BAR
  // ===========================================================================

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding:
            const EdgeInsets.fromLTRB(
          16,
          12,
          16,
          18,
        ),
        decoration:
            const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black87,
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.meetingName,
                      maxLines: 1,
                      overflow:
                          TextOverflow.ellipsis,
                      style:
                          GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight:
                            FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration:
                              const BoxDecoration(
                            color: Colors.green,
                            shape:
                                BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$_participantCount participants',
                          style:
                              GoogleFonts.poppins(
                            color:
                                Colors.white60,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              _buildTopChip(
                icon: Icons.timer_outlined,
                text:
                    _formatDuration(),
              ),

              const SizedBox(width: 6),

              _CircleButton(
                icon: Icons.link,
                onTap: _copyLink,
              ),

              const SizedBox(width: 6),

              _CircleButton(
                icon: _voiceAssistant
                    ? Icons.volume_up
                    : Icons.volume_off,
                onTap: () {
                  setState(() {
                    _voiceAssistant =
                        !_voiceAssistant;
                  });
                },
              ),

              const SizedBox(width: 6),

              GestureDetector(
                onTap: _confirmLeave,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 9,
                  ),
                  decoration:
                      BoxDecoration(
                    color:
                        AppColors.error
                            .withValues(
                      alpha: 0.18,
                    ),
                    borderRadius:
                        BorderRadius.circular(
                      12,
                    ),
                    border:
                        Border.all(
                      color:
                          AppColors.error
                              .withValues(
                        alpha: 0.45,
                      ),
                    ),
                  ),
                  child: const Text(
                    'Quitter',
                    style: TextStyle(
                      color:
                          AppColors.error,
                      fontWeight:
                          FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopChip({
    required IconData icon,
    required String text,
  }) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 7,
      ),
      decoration:
          BoxDecoration(
        color: Colors.black45,
        borderRadius:
            BorderRadius.circular(
          999,
        ),
        border:
            Border.all(
          color: Colors.white10,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 13,
            color: Colors.white70,
          ),
          const SizedBox(width: 5),
          Text(
            text,
            style:
                GoogleFonts.poppins(
              color: Colors.white70,
              fontSize: 10,
              fontWeight:
                  FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // CAPTIONS
  // ===========================================================================

  Widget _buildCaptionOverlay() {
    if (!_liveCaptions ||
        _currentTranscription.isEmpty) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: 25,
      right: 25,
      bottom: 130,
      child: ClipRRect(
        borderRadius:
            BorderRadius.circular(18),
        child: BackdropFilter(
          filter:
              ImageFilter.blur(
            sigmaX: 15,
            sigmaY: 15,
          ),
          child: Container(
            padding:
                const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 13,
            ),
            decoration:
                BoxDecoration(
              color: Colors.black54,
              borderRadius:
                  BorderRadius.circular(
                18,
              ),
              border:
                  Border.all(
                color: Colors.white12,
              ),
            ),
            child: Text(
              _currentTranscription,
              textAlign:
                  TextAlign.center,
              style:
                  GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // BOTTOM CONTROLS
  // ===========================================================================

  Widget _buildBottomControls() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding:
            const EdgeInsets.fromLTRB(
          12,
          12,
          12,
          28,
        ),
        decoration:
            const BoxDecoration(
          color: AppColors.surface,
          borderRadius:
              BorderRadius.vertical(
            top: Radius.circular(28),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceEvenly,
            children: [
              _ControlButton(
                icon: _micOn
                    ? Icons.mic
                    : Icons.mic_off,
                label: 'Micro',
                active: _micOn,
                danger: !_micOn,
                onTap: _toggleMic,
              ),
              _ControlButton(
                icon: _camOn
                    ? Icons.videocam
                    : Icons.videocam_off,
                label: 'Caméra',
                active: _camOn,
                danger: !_camOn,
                onTap: _toggleCamera,
              ),
              _ControlButton(
                icon:
                    Icons.chat_bubble_outline,
                label: 'Chat',
                onTap: () {
                  setState(() {
                    _showChat = true;
                  });
                },
              ),
              _ControlButton(
                icon:
                    Icons.people_outline,
                label:
                    '$_participantCount',
                onTap: () {
                  setState(() {
                    _showParticipants =
                        true;
                  });
                },
              ),
              _ControlButton(
                icon:
                    Icons.note_alt_outlined,
                label: 'Notes',
                onTap: () {
                  setState(() {
                    _showNotes = true;
                  });
                },
              ),
              _ControlButton(
                icon:
                    Icons.more_horiz,
                label: 'Plus',
                onTap: () {
                  setState(() {
                    _showMore = true;
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // CHAT PANEL
  // ===========================================================================

  Widget _buildChatPanel() {
    return _BasePanel(
      title: 'Chat',
      onClose: () {
        setState(() {
          _showChat = false;
        });
      },
      child: Column(
        children: [
          Expanded(
            child: _chatMessages.isEmpty
                ? const Center(
                    child: Text(
                      'Aucun message',
                      style: TextStyle(
                        color:
                            Colors.white38,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding:
                        const EdgeInsets.all(
                      16,
                    ),
                    itemCount:
                        _chatMessages.length,
                    itemBuilder:
                        (_, index) {
                      final message =
                          _chatMessages[
                              index];

                      return _ChatBubble(
                        message: message,
                      );
                    },
                  ),
          ),

          Container(
            padding:
                const EdgeInsets.fromLTRB(
              12,
              8,
              12,
              20,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller:
                        _chatController,
                    style:
                        const TextStyle(
                      color: Colors.white,
                    ),
                    minLines: 1,
                    maxLines: 4,
                    decoration:
                        InputDecoration(
                      hintText:
                          'Écrire un message...',
                      hintStyle:
                          const TextStyle(
                        color:
                            Colors.white38,
                      ),
                      filled: true,
                      fillColor:
                          Colors.white
                              .withValues(
                        alpha: 0.06,
                      ),
                      border:
                          OutlineInputBorder(
                        borderRadius:
                            BorderRadius
                                .circular(
                          25,
                        ),
                        borderSide:
                            BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) =>
                        _sendChat(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _sendChat,
                  icon: const Icon(
                    Icons.send,
                    color:
                        AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // PARTICIPANTS PANEL
  // ===========================================================================

  Widget _buildParticipantsPanel() {
    return _BasePanel(
      title:
          'Participants ($_participantCount)',
      onClose: () {
        setState(() {
          _showParticipants = false;
        });
      },
      child: Column(
        children: [
          if (_isOrganizer)
            Padding(
              padding:
                  const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child:
                    ElevatedButton.icon(
                  onPressed: _muteAll,
                  icon: const Icon(
                    Icons.mic_off,
                  ),
                  label: const Text(
                    'Muter tous les autres',
                  ),
                  style:
                      ElevatedButton.styleFrom(
                    backgroundColor:
                        AppColors.error,
                    padding:
                        const EdgeInsets
                            .symmetric(
                      vertical: 13,
                    ),
                  ),
                ),
              ),
            ),

          Padding(
            padding:
                const EdgeInsets.symmetric(
              horizontal: 16,
            ),
            child: Container(
              padding:
                  const EdgeInsets.all(14),
              decoration:
                  BoxDecoration(
                color: AppColors.primary
                    .withValues(
                  alpha: 0.08,
                ),
                borderRadius:
                    BorderRadius.circular(
                  16,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.groups_2_outlined,
                    color:
                        AppColors.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Webinaire CRUX • '
                      'jusqu’à $_targetParticipants+ '
                      'participants',
                      style:
                          GoogleFonts.poppins(
                        color:
                            Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),

          Expanded(
            child: ListView.builder(
              itemCount:
                  _remoteParticipants.length +
                      1,
              itemBuilder:
                  (context, index) {
                if (index == 0) {
                  return _participantListTile(
                    name:
                        '${widget.userName} (vous)',
                    identity:
                        widget.userId,
                    organizer:
                        widget.userId ==
                            _organizerId,
                    local: true,
                  );
                }

                final participant =
                    _remoteParticipants[
                        index - 1];

                return _participantListTile(
                  name:
                      participant.name.isNotEmpty
                          ? participant.name
                          : 'Participant',
                  identity:
                      participant.identity,
                  organizer:
                      participant.identity ==
                          _organizerId,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _participantListTile({
    required String name,
    required String identity,
    bool organizer = false,
    bool local = false,
  }) {
    return ListTile(
      leading: _Avatar(
        name: name,
      ),
      title: Text(
        name,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
        ),
      ),
      subtitle: organizer
          ? const Text(
              'Organisateur',
              style: TextStyle(
                color:
                    AppColors.primary,
                fontSize: 10,
              ),
            )
          : null,
      trailing: Row(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          if (_raisedHands
              .contains(identity))
            const Icon(
              Icons.back_hand,
              color: Colors.orange,
              size: 17,
            ),
          if (!local)
            IconButton(
              icon: const Icon(
                Icons.message_outlined,
                color: Colors.white38,
              ),
              onPressed: () {
                setState(() {
                  _showParticipants =
                      false;
                  _showChat = true;
                });
              },
            ),
        ],
      ),
    );
  }

  // ===========================================================================
  // NOTES
  // ===========================================================================

  Widget _buildNotesPanel() {
    return _BasePanel(
      title: 'Notes de réunion',
      onClose: _saveNotesAndClose,
      child: Padding(
        padding:
            const EdgeInsets.all(20),
        child: TextField(
          controller:
              _noteController,
          expands: true,
          maxLines: null,
          minLines: null,
          style:
              GoogleFonts.poppins(
            color: Colors.white,
            height: 1.6,
          ),
          decoration:
              const InputDecoration(
            hintText:
                'Tapez vos notes ici...',
            hintStyle:
                TextStyle(
              color: Colors.white24,
            ),
            border:
                InputBorder.none,
          ),
        ),
      ),
    );
  }

  Future<void> _saveNotesAndClose() async {
    try {
      // Utilise le service existant du projet.
      await MeetingService()
          .saveMeetingHistoryForUser(
        meetingId: widget.meetingId,
        userId: widget.userId,
        title: widget.meetingName,
        durationSeconds:
            _secondsElapsed,
        endMeeting: false,
      );
    } catch (_) {}

    if (!mounted) return;

    setState(() {
      _showNotes = false;
    });
  }

  // ===========================================================================
  // MORE PANEL
  // ===========================================================================

  Widget _buildMorePanel() {
    return _BasePanel(
      title: 'Options',
      onClose: () {
        setState(() {
          _showMore = false;
        });
      },
      child: ListView(
        padding:
            const EdgeInsets.symmetric(
          vertical: 10,
        ),
        children: [
          _optionTile(
            icon:
                Icons.back_hand_outlined,
            title: _handRaised
                ? 'Baisser la main'
                : 'Lever la main',
            active: _handRaised,
            onTap: () {
              Navigator.pop(context);
              _toggleRaiseHand();
            },
          ),
          _optionTile(
            icon:
                Icons.closed_caption_outlined,
            title: _liveCaptions
                ? 'Désactiver les sous-titres'
                : 'Sous-titres en direct',
            active: _liveCaptions,
            onTap: () {
              Navigator.pop(context);
              _toggleCaptions();
            },
          ),
          _optionTile(
            icon:
                Icons.screen_share_outlined,
            title: _screenSharing
                ? 'Arrêter le partage'
                : 'Partager l’écran',
            active: _screenSharing,
            onTap: () {
              Navigator.pop(context);
              _toggleScreenShare();
            },
          ),
          _optionTile(
            icon:
                Icons.cameraswitch_outlined,
            title: 'Changer de caméra',
            onTap: () {
              Navigator.pop(context);
              _switchCamera();
            },
          ),
          _optionTile(
            icon:
                Icons.link_outlined,
            title:
                'Copier le lien de la réunion',
            onTap: () {
              Navigator.pop(context);
              _copyLink();
            },
          ),
          _optionTile(
            icon:
                Icons.info_outline,
            title:
                'Informations de la réunion',
            onTap: () {
              Navigator.pop(context);
              _showMeetingInfo();
            },
          ),
        ],
      ),
    );
  }

  Widget _optionTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: active
            ? AppColors.primary
            : Colors.white70,
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
        ),
      ),
      onTap: onTap,
    );
  }

  // ===========================================================================
  // MEETING INFO
  // ===========================================================================

  void _showMeetingInfo() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor:
          Colors.transparent,
      builder: (_) {
        return Container(
          padding:
              const EdgeInsets.all(24),
          decoration:
              const BoxDecoration(
            color: AppColors.surface,
            borderRadius:
                BorderRadius.vertical(
              top: Radius.circular(28),
            ),
          ),
          child: Column(
            mainAxisSize:
                MainAxisSize.min,
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                'Informations',
                style:
                    GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              _infoRow(
                'Nom',
                widget.meetingName,
              ),
              _infoRow(
                'ID',
                widget.meetingId,
              ),
              _infoRow(
                'Participants',
                '$_participantCount',
              ),
              _infoRow(
                'Vidéos affichées',
                '${_visibleParticipants.length + 1}/$_maxVisibleVideos',
              ),
              _infoRow(
                'Type',
                'Large Conference / Webinar',
              ),
              _infoRow(
                'Transport',
                'LiveKit SFU',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _infoRow(
    String label,
    String value,
  ) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
        vertical: 5,
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style:
                  const TextStyle(
                color:
                    Colors.white38,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style:
                  const TextStyle(
                color:
                    Colors.white70,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // COPY LINK
  // ===========================================================================

  Future<void> _copyLink() async {
    final link =
        AppConfig.webJoinLink(
      widget.meetingId,
    );

    await Clipboard.setData(
      ClipboardData(text: link),
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(
      const SnackBar(
        content: Text(
          'Lien de réunion copié.',
        ),
      ),
    );
  }

  // ===========================================================================
  // RECONNECT BANNER
  // ===========================================================================

  Widget _buildReconnectBanner() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Container(
          margin:
              const EdgeInsets.all(12),
          padding:
              const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          decoration:
              BoxDecoration(
            color: Colors.orange
                .withValues(
              alpha: 0.9,
            ),
            borderRadius:
                BorderRadius.circular(
              14,
            ),
          ),
          child: const Row(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              SizedBox(
                width: 15,
                height: 15,
                child:
                    CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 10),
              Text(
                'Reconnexion...',
                style:
                    TextStyle(
                  color: Colors.white,
                  fontWeight:
                      FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // ERROR SCREEN
  // ===========================================================================

  Widget _buildError() {
    return Scaffold(
      backgroundColor:
          AppColors.background,
      body: Center(
        child: Padding(
          padding:
              const EdgeInsets.all(30),
          child: Column(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                color:
                    AppColors.error,
                size: 58,
              ),
              const SizedBox(height: 18),
              Text(
                _error!,
                textAlign:
                    TextAlign.center,
                style:
                    const TextStyle(
                  color:
                      Colors.white70,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(
                    context,
                  );
                },
                child:
                    const Text('Retour'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==============================================================================
// VIDEO TILE
// ==============================================================================

class _VideoTile extends StatelessWidget {
  final Participant? participant;
  final String name;
  final bool isLocal;
  final bool active;
  final bool raised;
  final bool large;
  final bool camEnabled;

  const _VideoTile({
    required this.participant,
    required this.name,
    this.isLocal = false,
    this.active = false,
    this.raised = false,
    this.large = false,
    this.camEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final videoTrack =
        _findVideoTrack();

    final hasVideo =
        videoTrack != null &&
        !videoTrack.muted;

    return AnimatedContainer(
      duration:
          const Duration(
        milliseconds: 250,
      ),
      decoration:
          BoxDecoration(
        color: AppColors.surface,
        borderRadius:
            BorderRadius.circular(
          20,
        ),
        border:
            Border.all(
          color: active
              ? AppColors.primary
              : Colors.white
                  .withValues(
            alpha: 0.06,
          ),
          width: active ? 2 : 1,
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: AppColors.primary
                      .withValues(
                    alpha: 0.15,
                  ),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius:
            BorderRadius.circular(
          20,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasVideo)
              VideoTrackRenderer(
                videoTrack,
                fit: RTCVideoViewObjectFit
                    .RTCVideoViewObjectFitCover,
              )
            else
              _buildAvatarArea(),

            _buildGradient(),

            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow:
                          TextOverflow.ellipsis,
                      style:
                          GoogleFonts.poppins(
                        color:
                            Colors.white,
                        fontSize:
                            large ? 12 : 10,
                        fontWeight:
                            FontWeight.w700,
                      ),
                    ),
                  ),
                  if (raised)
                    const Padding(
                      padding:
                          EdgeInsets.only(
                        left: 7,
                      ),
                      child: Icon(
                        Icons.back_hand,
                        color:
                            Colors.orange,
                        size: 16,
                      ),
                    ),
                  if (participant != null &&
                      _isMuted())
                    const Padding(
                      padding:
                          EdgeInsets.only(
                        left: 7,
                      ),
                      child: Icon(
                        Icons.mic_off,
                        color:
                            Colors.white70,
                        size: 15,
                      ),
                    ),
                ],
              ),
            ),

            if (active)
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding:
                      const EdgeInsets
                          .symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration:
                      BoxDecoration(
                    color:
                        AppColors.primary,
                    borderRadius:
                        BorderRadius
                            .circular(
                      999,
                    ),
                  ),
                  child: const Text(
                    'PARLE',
                    style:
                        TextStyle(
                      color:
                          Colors.white,
                      fontSize: 8,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ).animate().fadeIn(
          duration:
              220.ms,
        );
  }

  TrackPublication<RemoteTrack>? _findVideoTrack() {
    final p = participant;

    if (p == null) return null;

    if (p is LocalParticipant) {
      for (final publication
          in p.videoTrackPublications.values) {
        final track = publication.track;

        if (track != null) {
          return publication;
        }
      }

      return null;
    }

    if (p is RemoteParticipant) {
      for (final publication
          in p.videoTrackPublications.values) {
        if (!publication.subscribed) {
          continue;
        }

        final track = publication.track;

        if (track != null) {
          return publication;
        }
      }
    }

    return null;
  }

  bool _isMuted() {
    final p = participant;

    if (p == null) return false;

    if (p is LocalParticipant) {
      return !p.isMicrophoneEnabled();
    }

    if (p is RemoteParticipant) {
      return p.audioTrackPublications.values
          .every(
        (publication) =>
            publication.muted ||
            publication.track == null,
      );
    }

    return false;
  }

  Widget _buildAvatarArea() {
    return Container(
      color:
          AppColors.background,
      alignment:
          Alignment.center,
      child: _Avatar(
        name: name,
        large: large,
      ),
    );
  }

  Widget _buildGradient() {
    return Positioned.fill(
      child: DecoratedBox(
        decoration:
            const BoxDecoration(
          gradient: LinearGradient(
            begin:
                Alignment.topCenter,
            end:
                Alignment.bottomCenter,
            stops: [
              0.55,
              1.0,
            ],
            colors: [
              Colors.transparent,
              Colors.black87,
            ],
          ),
        ),
      ),
    );
  }
}

// ==============================================================================
// AVATAR
// ==============================================================================

class _Avatar extends StatelessWidget {
  final String name;
  final bool large;

  const _Avatar({
    required this.name,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isEmpty
        ? '?'
        : name
            .trim()
            .characters
            .first
            .toUpperCase();

    return Container(
      width: large ? 80 : 55,
      height: large ? 80 : 55,
      decoration:
          const BoxDecoration(
        gradient:
            AppColors.primaryGradient,
        shape: BoxShape.circle,
      ),
      alignment:
          Alignment.center,
      child: Text(
        letter,
        style:
            TextStyle(
          color: Colors.white,
          fontWeight:
              FontWeight.bold,
          fontSize:
              large ? 30 : 20,
        ),
      ),
    );
  }
}

// ==============================================================================
// CIRCLE BUTTON
// ==============================================================================

class _CircleButton
    extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black45,
      shape:
          const CircleBorder(),
      child: InkWell(
        customBorder:
            const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.all(9),
          child: Icon(
            icon,
            color:
                Colors.white70,
            size: 19,
          ),
        ),
      ),
    );
  }
}

// ==============================================================================
// CONTROL BUTTON
// ==============================================================================

class _ControlButton
    extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool danger;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color iconColor = danger
        ? AppColors.error
        : active
            ? Colors.white
            : Colors.white60;

    return InkWell(
      borderRadius:
          BorderRadius.circular(
        15,
      ),
      onTap: onTap,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(
          horizontal: 7,
          vertical: 4,
        ),
        child: Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 42,
              decoration:
                  BoxDecoration(
                color: danger
                    ? AppColors.error
                        .withValues(
                      alpha: 0.12,
                    )
                    : Colors.white
                        .withValues(
                      alpha:
                          active
                              ? 0.08
                              : 0.04,
                    ),
                borderRadius:
                    BorderRadius.circular(
                  14,
                ),
              ),
              alignment:
                  Alignment.center,
              child: Icon(
                icon,
                color: iconColor,
                size: 22,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style:
                  const TextStyle(
                color:
                    Colors.white54,
                fontSize: 9,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==============================================================================
// BASE PANEL
// ==============================================================================

class _BasePanel
    extends StatelessWidget {
  final String title;
  final Widget child;
  final VoidCallback onClose;

  const _BasePanel({
    required this.title,
    required this.child,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: BackdropFilter(
        filter:
            ImageFilter.blur(
          sigmaX: 18,
          sigmaY: 18,
        ),
        child: Container(
          color:
              Colors.black.withValues(
            alpha: 0.92,
          ),
          child: Column(
            children: [
              AppBar(
                backgroundColor:
                    Colors.transparent,
                elevation: 0,
                title: Text(
                  title,
                  style:
                      GoogleFonts.poppins(
                    color:
                        Colors.white,
                    fontWeight:
                        FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                leading:
                    IconButton(
                  onPressed: onClose,
                  icon: const Icon(
                    Icons.close,
                    color:
                        Colors.white,
                  ),
                ),
              ),
              Expanded(
                child: child,
              ),
            ],
          ),
        ),
      ),
    )
        .animate()
        .slideY(
          begin: 1,
          end: 0,
          duration:
              280.ms,
          curve:
              Curves.easeOutCubic,
        );
  }
}

// ==============================================================================
// CHAT MESSAGE
// ==============================================================================

class _ChatMessage {
  final String sender;
  final String message;
  final bool isMe;

  const _ChatMessage({
    required this.sender,
    required this.message,
    required this.isMe,
  });
}

// ==============================================================================
// CHAT BUBBLE
// ==============================================================================

class _ChatBubble
    extends StatelessWidget {
  final _ChatMessage message;

  const _ChatBubble({
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.isMe
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: Container(
        margin:
            const EdgeInsets.only(
          bottom: 8,
        ),
        padding:
            const EdgeInsets.all(12),
        constraints:
            const BoxConstraints(
          maxWidth: 320,
        ),
        decoration:
            BoxDecoration(
          color: message.isMe
              ? AppColors.primary
              : Colors.white12,
          borderRadius:
              BorderRadius.circular(
            16,
          ),
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            if (!message.isMe)
              Text(
                message.sender,
                style:
                    const TextStyle(
                  color:
                      Colors.white54,
                  fontSize: 9,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
            if (!message.isMe)
              const SizedBox(height: 4),
            Text(
              message.message,
              style:
                  const TextStyle(
                color:
                    Colors.white,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
} 
