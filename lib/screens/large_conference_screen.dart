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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../config/app_config.dart';
import '../services/livekit_service.dart';
import '../services/meeting_service.dart';
import '../services/note_service.dart';
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
  // LARGE WEBINAR CONFIGURATION
  // ===========================================================================

  /// Nombre maximum de vidéos rendues simultanément.
  ///
  /// IMPORTANT :
  /// La room peut contenir des milliers de participants.
  /// L'interface ne doit jamais essayer de construire des milliers de vidéos.
  static const int _maxVisibleVideos = 10;

  /// Capacité cible de ce mode webinaire.
  ///
  /// Cette valeur est uniquement une indication UI.
  /// Elle ne configure pas la capacité réelle de LiveKit.
  static const int _targetParticipants = 10000;

  // ===========================================================================
  // SERVICES
  // ===========================================================================

  final FirebaseFirestore _db = FirebaseFirestore.instance;

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

  List<RemoteParticipant> _remoteParticipants =
      <RemoteParticipant>[];

  String? _activeSpeakerId;

  String? _organizerId;

  final Set<String> _raisedHands = <String>{};

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

  bool _voiceAssistant = false;

  bool _liveCaptions = false;

  bool _handRaised = false;

  // ===========================================================================
  // CAPTIONS
  // ===========================================================================

  String _currentTranscription = '';

  // ===========================================================================
  // TIMER
  // ===========================================================================

  Timer? _callTimer;

  int _secondsElapsed = 0;

  bool _isPro = false;

  bool _paywallShown = false;

  // ===========================================================================
  // FIRESTORE
  // ===========================================================================

  StreamSubscription<QuerySnapshot>?
      _presenceSubscription;

  StreamSubscription<QuerySnapshot>?
      _chatSubscription;

  // ===========================================================================
  // CONTROLLERS
  // ===========================================================================

  late final TextEditingController _chatController;

  late final TextEditingController _noteController;

  final List<_ChatMessage> _chatMessages =
      <_ChatMessage>[];

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

    _chatSubscription?.cancel();

    _roomListener?.dispose();

    _room?.disconnect();

    _tts.stop();

    _speech.stop();

    _chatController.dispose();

    _noteController.dispose();

    super.dispose();
  }

  // ===========================================================================
  // INITIALIZATION
  // ===========================================================================

  Future<void> _initialize() async {
    try {
      await _loadPreferences();

      await _checkPro();

      await _loadOrganizer();

      await _registerPresence();

      await _connect();

      _listenPresence();

      _listenChat();

      _startTimer();

      if (!mounted) return;

      setState(() {
        _loading = false;
      });
    } catch (e, stackTrace) {
      crux.logger.e(
        'Large conference initialization failed',
        error: e,
        stackTrace: stackTrace,
      );

      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = e.toString();
      });
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
        _micOn =
            prefs.getBool('crux_mic_default') ?? true;

        _camOn =
            prefs.getBool('crux_cam_default') ?? true;
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
      final value = await ProService().checkProStatus(
        widget.userId,
      );

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

      _organizerId =
          data['organizerId']?.toString();
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
  // CHAT
  // ===========================================================================

  void _listenChat() {
    _chatSubscription = _db
        .collection(AppConfig.meetingsCollection)
        .doc(widget.meetingId)
        .collection('chat')
        .orderBy(
          'timestamp',
          descending: false,
        )
        .limit(AppConfig.maxLocalChatMessages)
        .snapshots()
        .listen(
      (snapshot) {
        if (!mounted) return;

        final messages = <_ChatMessage>[];

        for (final doc in snapshot.docs) {
          final data = doc.data();

          messages.add(
            _ChatMessage(
              senderId:
                  data['senderId']?.toString() ?? '',
              sender:
                  data['sender']?.toString() ??
                      'Anonyme',
              message:
                  data['message']?.toString() ??
                      data['text']?.toString() ??
                      '',
              timestamp:
                  data['timestamp'] is Timestamp
                      ? (data['timestamp'] as Timestamp)
                          .toDate()
                      : null,
              isPrivate:
                  data['isPrivate'] == true,
            ),
          );
        }

        setState(() {
          _chatMessages
            ..clear()
            ..addAll(messages);
        });
      },
    );
  }

  Future<void> _sendChat() async {
    final text = _chatController.text.trim();

    if (text.isEmpty) return;

    _chatController.clear();

    try {
      await _db
          .collection(AppConfig.meetingsCollection)
          .doc(widget.meetingId)
          .collection('chat')
          .add({
        'senderId': widget.userId,
        'sender': widget.userName,
        'message': text,
        'text': text,
        'timestamp': FieldValue.serverTimestamp(),
        'isPrivate': false,
      });

      await _sendData({
        'type': 'chat',
        'senderId': widget.userId,
        'sender': widget.userName,
        'message': text,
      });
    } catch (e) {
      crux.logger.w(
        'Chat send failed',
        error: e,
      );
    }
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
          'LiveKit n’est pas configuré. '
          'Vérifiez LIVEKIT_WSS_URL et '
          'LIVEKIT_TOKEN_SERVER_URL.',
        );
      }

      final token =
          await LiveKitService.instance.fetchToken(
        room: widget.meetingId,
        identity: widget.userId,
        name: widget.userName,
        isHost: widget.isHost,
      );

      if (token == null || token.isEmpty) {
        throw Exception(
          'Le serveur LiveKit n’a pas retourné '
          'de token valide.',
        );
      }

      await _disposeRoom();

      final room = Room(
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          defaultVideoPublishOptions:
              VideoPublishOptions(
            simulcast: true,
          ),
        ),
      );

      _room = room;

      _roomListener = room.createListener();

      _setupRoomEvents(_roomListener!);

      await room
          .connect(
            AppConfig.livekitWssUrl,
            token,
          )
          .timeout(
        AppConfig.roomConnectionTimeout,
        onTimeout: () {
          throw TimeoutException(
            'Connexion LiveKit expirée.',
          );
        },
      );

      final local = room.localParticipant;

      if (local != null) {
        await local.setMicrophoneEnabled(_micOn);

        await local.setCameraEnabled(_camOn);
      }

      _refreshParticipants();

      _reconnectAttempts = 0;

      if (mounted) {
        setState(() {
          _isReconnecting = false;
        });
      }
    } finally {
      _isConnecting = false;
    }
  }

  Future<void> _disposeRoom() async {
    _roomListener?.dispose();

    _roomListener = null;

    final oldRoom = _room;

    _room = null;

    if (oldRoom != null) {
      try {
        await oldRoom.disconnect();
      } catch (e) {
        crux.logger.w(
          'LiveKit disconnect failed',
          error: e,
        );
      }
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
      ..on<RoomDisconnectedEvent>((_) {
        if (!mounted) return;

        unawaited(_attemptReconnect());
      })
      ..on<ParticipantConnectedEvent>(
        (event) {
          _refreshParticipants();

          if (_voiceAssistant) {
            final name =
                event.participant.name.trim().isNotEmpty
                    ? event.participant.name
                    : 'Un participant';

            _announce('$name a rejoint.');
          }
        },
      )
      ..on<ParticipantDisconnectedEvent>(
        (event) {
          _refreshParticipants();

          if (_voiceAssistant) {
            final name =
                event.participant.name.trim().isNotEmpty
                    ? event.participant.name
                    : 'Un participant';

            _announce('$name a quitté.');
          }
        },
      )
      ..on<ActiveSpeakersChangedEvent>(
        (event) {
          if (!mounted) return;

          if (event.speakers.isEmpty) {
            setState(() {
              _activeSpeakerId = null;
            });

            return;
          }

          setState(() {
            _activeSpeakerId =
                event.speakers.first.identity;
          });
        },
      )
      ..on<ParticipantMetadataUpdatedEvent>(
        (_) {
          _refreshParticipants();
        },
      )
      ..on<TrackSubscribedEvent>(
        (_) {
          _refreshParticipants();
        },
      )
      ..on<TrackUnsubscribedEvent>(
        (_) {
          _refreshParticipants();
        },
      )
      ..on<TrackPublishedEvent>(
        (_) {
          _refreshParticipants();
        },
      )
      ..on<TrackUnpublishedEvent>(
        (_) {
          _refreshParticipants();
        },
      )
      ..on<DataReceivedEvent>(
        _handleDataReceived,
      );
  }

  // ===========================================================================
  // PARTICIPANTS
  // ===========================================================================

  void _refreshParticipants() {
    final room = _room;

    if (!mounted || room == null) {
      return;
    }

    final participants =
        room.remoteParticipants.values.toList();

    setState(() {
      _remoteParticipants = participants;
    });
  }

  /// Retourne uniquement les participants affichés.
  ///
  /// Même avec 5 000 participants dans la room,
  /// l'interface ne construit que 10 tuiles vidéo.
  List<RemoteParticipant> get _visibleParticipants {
    final participants =
        List<RemoteParticipant>.from(
      _remoteParticipants,
    );

    participants.sort(
      (a, b) {
        final aActive =
            a.identity == _activeSpeakerId;

        final bActive =
            b.identity == _activeSpeakerId;

        if (aActive && !bActive) {
          return -1;
        }

        if (!aActive && bActive) {
          return 1;
        }

        final aVideo = _hasVideo(a);

        final bVideo = _hasVideo(b);

        if (aVideo && !bVideo) {
          return -1;
        }

        if (!aVideo && bVideo) {
          return 1;
        }

        return a.name
            .toLowerCase()
            .compareTo(
              b.name.toLowerCase(),
            );
      },
    );

    // 1 vidéo locale + 9 vidéos distantes = 10 maximum.
    return participants
        .take(_maxVisibleVideos - 1)
        .toList();
  }

  bool _hasVideo(
    RemoteParticipant participant,
  ) {
    for (final publication
        in participant.videoTrackPublications) {
      if (publication.subscribed &&
          !publication.muted &&
          publication.track != null) {
        return true;
      }
    }

    return false;
  }

  // ===========================================================================
  // LIVEKIT DATA
  // ===========================================================================

  void _handleDataReceived(
    DataReceivedEvent event,
  ) {
    try {
      final text = utf8.decode(event.data);

      final decoded = jsonDecode(text);

      if (decoded is! Map<String, dynamic>) {
        return;
      }

      final type = decoded['type']?.toString();

      if (type == 'mute_all') {
        final sender =
            event.participant?.identity;

        if (sender == _organizerId && _micOn) {
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

        if (identity == null) {
          return;
        }

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

        if (identity == null) {
          return;
        }

        if (mounted) {
          setState(() {
            _raisedHands.remove(identity);
          });
        }

        return;
      }
    } catch (e) {
      crux.logger.w(
        'LiveKit data decoding failed',
        error: e,
      );
    }
  }

  Future<void> _sendData(
    Map<String, dynamic> payload,
  ) async {
    final room = _room;

    if (room == null) return;

    final local = room.localParticipant;

    if (local == null) return;

    try {
      final data = utf8.encode(
        jsonEncode(payload),
      );

      await local.publishData(
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
  // MICROPHONE
  // ===========================================================================

  Future<void> _toggleMic() async {
    final next = !_micOn;

    try {
      final local = _room?.localParticipant;

      if (local == null) return;

      await local.setMicrophoneEnabled(next);

      if (!mounted) return;

      setState(() {
        _micOn = next;
      });
    } catch (e) {
      crux.logger.w(
        'Microphone toggle failed',
        error: e,
      );
    }
  }

  // ===========================================================================
  // CAMERA
  // ===========================================================================

  Future<void> _toggleCamera() async {
    final next = !_camOn;

    try {
      final local = _room?.localParticipant;

      if (local == null) return;

      await local.setCameraEnabled(next);

      if (!mounted) return;

      setState(() {
        _camOn = next;
      });
    } catch (e) {
      crux.logger.w(
        'Camera toggle failed',
        error: e,
      );
    }
  }

  // ===========================================================================
  // SCREEN SHARE
  // ===========================================================================

  Future<void> _toggleScreenShare() async {
    final local = _room?.localParticipant;

    if (local == null) return;

    final next = !_screenSharing;

    try {
      await local.setScreenShareEnabled(next);

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
  // RAISE HAND
  // ===========================================================================

  Future<void> _toggleRaiseHand() async {
    final next = !_handRaised;

    try {
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

      await _sendData({
        'type': next
            ? 'raise_hand'
            : 'lower_hand',
        'identity': widget.userId,
      });

      if (!mounted) return;

      setState(() {
        _handRaised = next;
      });

      if (next) {
        _announce(
          'Vous avez levé la main.',
        );
      }
    } catch (e) {
      crux.logger.w(
        'Raise hand failed',
        error: e,
      );
    }
  }

  // ===========================================================================
  // MUTE ALL
  // ===========================================================================

  Future<void> _muteAllOthers() async {
    if (!widget.isHost &&
        widget.userId != _organizerId) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text(
            'Muter tout le monde ?',
            style: TextStyle(
              color: Colors.white,
            ),
          ),
          content: const Text(
            'Cette action demandera aux autres participants de couper leur microphone.',
            style: TextStyle(
              color: Colors.white70,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, false),
              child: const Text(
                'Annuler',
              ),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.pop(context, true),
              child: const Text(
                'Muter',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    await _sendData({
      'type': 'mute_all',
      'identity': widget.userId,
    });
  }

  // ===========================================================================
  // CAPTIONS
  // ===========================================================================

  Future<void> _toggleCaptions() async {
    if (_liveCaptions) {
      try {
        await _speech.stop();
      } catch (e) {
        crux.logger.w(
          'Speech recognition stop failed',
          error: e,
        );
      }

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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'La reconnaissance vocale n’est pas disponible sur cet appareil.',
              ),
            ),
          );
        }

        return;
      }

      if (!mounted) return;

      setState(() {
        _liveCaptions = true;
      });

      await _speech.listen(
        listenOptions:
            const stt.SpeechListenOptions(
          localeId: 'fr_FR',
          partialResults: true,
          cancelOnError: false,
        ),
        onResult: (result) {
          if (!mounted) return;

          setState(() {
            _currentTranscription =
                result.recognizedWords;
          });
        },
      );
    } catch (e, stackTrace) {
      crux.logger.w(
        'Speech recognition failed',
        error: e,
        stackTrace: stackTrace,
      );

      if (mounted) {
        setState(() {
          _liveCaptions = false;
          _currentTranscription = '';
        });
      }
    }
  }

  // ===========================================================================
  // VOICE ASSISTANT
  // ===========================================================================

  Future<void> _announce(String text) async {
    if (!_voiceAssistant) {
      return;
    }

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
            AppConfig.freeMeetingDurationMinutes * 60;

        if (_secondsElapsed == limit - 300) {
          _announce(
            'Attention, votre appel gratuit se terminera dans 5 minutes.',
          );
        }

        if (_secondsElapsed >= limit &&
            !_paywallShown) {
          _paywallShown = true;

          _showPaywall();
        }
      },
    );
  }

  String _formatElapsedDuration() {
    final hours = _secondsElapsed ~/ 3600;

    final minutes =
        (_secondsElapsed % 3600) ~/ 60;

    final seconds = _secondsElapsed % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  // ===========================================================================
  // PAYWALL
  // ===========================================================================

  void _showPaywall() {
    if (!mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text(
            'Temps écoulé',
            style: TextStyle(
              color: Colors.white,
            ),
          ),
          content: const Text(
            'La limite de la réunion gratuite est atteinte.',
            style: TextStyle(
              color: Colors.white70,
            ),
          ),
          actions: [
            TextButton(
              onPressed: _leave,
              child: const Text(
                'Quitter',
              ),
            ),
            ElevatedButton(
              onPressed: () {
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
  // RECONNECT
  // ===========================================================================

  Future<void> _attemptReconnect() async {
    if (!mounted || _isConnecting) {
      return;
    }

    if (_reconnectAttempts >=
        AppConfig.maxReconnectAttempts) {
      setState(() {
        _isReconnecting = false;
        _error =
            'La connexion à la conférence a été interrompue.';
      });

      return;
    }

    _reconnectAttempts++;

    setState(() {
      _isReconnecting = true;
    });

    await Future<void>.delayed(
      AppConfig.reconnectDelay,
    );

    if (!mounted) return;

    try {
      await _connect();

      if (!mounted) return;

      setState(() {
        _isReconnecting = false;
      });
    } catch (e) {
      crux.logger.w(
        'Reconnect attempt failed',
        error: e,
      );

      if (mounted) {
        unawaited(
          _attemptReconnect(),
        );
      }
    }
  }

  // ===========================================================================
  // LEAVE
  // ===========================================================================

  Future<void> _confirmLeave() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text(
            'Quitter la réunion ?',
            style: TextStyle(
              color: Colors.white,
            ),
          ),
          content: const Text(
            'Voulez-vous quitter cette conférence ?',
            style: TextStyle(
              color: Colors.white70,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, false),
              child: const Text(
                'Rester',
              ),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.pop(context, true),
              child: const Text(
                'Quitter',
              ),
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
    } catch (e) {
      crux.logger.w(
        'Meeting cleanup failed',
        error: e,
      );
    }

    await _disposeRoom();

    if (!mounted) return;

    Navigator.of(context).pop();
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _buildError();
    }

    if (_loading) {
      return _buildLoading();
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: _buildConference(),
          ),

          _buildTopBar(),

          if (_currentTranscription.isNotEmpty)
            _buildCaptions(),

          _buildBottomBar(),

          if (_showChat)
            _buildChatPanel(),

          if (_showParticipants)
            _buildParticipantsPanel(),

          if (_showNotes)
            _buildNotesPanel(),

          if (_isReconnecting)
            _buildReconnectBanner(),
        ],
      ),
    );
  }

  // ===========================================================================
  // LOADING
  // ===========================================================================

  Widget _buildLoading() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 2,
            ),
            const SizedBox(
              height: 20,
            ),
            Text(
              'Connexion au webinaire...',
              style: GoogleFonts.poppins(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
            const SizedBox(
              height: 8,
            ),
            Text(
              'Jusqu’à $_targetParticipants participants',
              style: GoogleFonts.poppins(
                color: Colors.white38,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // ERROR
  // ===========================================================================

  Widget _buildError() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                color: AppColors.error,
                size: 64,
              ),
              const SizedBox(
                height: 20,
              ),
              Text(
                _error ?? 'Erreur inconnue',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                ),
              ),
              const SizedBox(
                height: 24,
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _error = null;
                    _loading = true;
                  });

                  _initialize();
                },
                child: const Text(
                  'Réessayer',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // CONFERENCE
  // ===========================================================================

  Widget _buildConference() {
    final visible = _visibleParticipants;

    final tiles = <Widget>[
      _VideoTile(
        participant: _room?.localParticipant,
        isLocal: true,
        userName: widget.userName,
        active:
            widget.userId == _activeSpeakerId,
      ),
      ...visible.map(
        (participant) {
          return _VideoTile(
            participant: participant,
            isLocal: false,
            userName: participant.name,
            active:
                participant.identity ==
                    _activeSpeakerId,
          );
        },
      ),
    ];

    final count = tiles.length;

    final columns = switch (count) {
      0 || 1 => 1,
      2 || 3 || 4 => 2,
      _ => 3,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        12,
        90,
        12,
        110,
      ),
      child: GridView.builder(
        physics:
            const BouncingScrollPhysics(),
        gridDelegate:
            SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 16 / 10,
        ),
        itemCount: tiles.length,
        itemBuilder: (_, index) {
          return tiles[index];
        },
      ),
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
        padding: const EdgeInsets.fromLTRB(
          16,
          12,
          16,
          16,
        ),
        decoration: const BoxDecoration(
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
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight:
                            FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(
                      height: 2,
                    ),
                    Text(
                      'Webinaire • '
                      '$_participantCountLabel',
                      style: GoogleFonts.poppins(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              _TopPill(
                icon: Icons.timer_outlined,
                text: _formatElapsedDuration(),
              ),
              const SizedBox(
                width: 8,
              ),
              _TopPill(
                icon: Icons.people_outline,
                text: _participantCount
                    .toString(),
              ),
              const SizedBox(
                width: 8,
              ),
              IconButton(
                tooltip: 'Quitter',
                onPressed: _confirmLeave,
                icon: const Icon(
                  Icons.close,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _participantCountLabel {
    if (_participantCount >= 1000) {
      final value =
          _participantCount / 1000;

      return '${value.toStringAsFixed(1)}K participants';
    }

    return '$_participantCount participants';
  }

  int get _participantCount {
    final room = _room;

    if (room == null) {
      return _remoteParticipants.length + 1;
    }

    return room.remoteParticipants.length + 1;
  }

  // ===========================================================================
  // CAPTIONS
  // ===========================================================================

  Widget _buildCaptions() {
    return Positioned(
      left: 24,
      right: 24,
      bottom: 115,
      child: ClipRRect(
        borderRadius:
            BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 12,
            sigmaY: 12,
          ),
          child: Container(
            padding: const EdgeInsets.all(14),
            color: Colors.black.withValues(
              alpha: 0.65,
            ),
            child: Text(
              _currentTranscription,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // BOTTOM BAR
  // ===========================================================================

  Widget _buildBottomBar() {
    return Positioned(
      left: 12,
      right: 12,
      bottom: 12,
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(
              alpha: 0.96,
            ),
            borderRadius:
                BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white10,
            ),
          ),
          child: Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceEvenly,
            children: [
              _ControlButton(
                icon: _micOn
                    ? Icons.mic
                    : Icons.mic_off,
                active: _micOn,
                onTap: _toggleMic,
              ),
              _ControlButton(
                icon: _camOn
                    ? Icons.videocam
                    : Icons.videocam_off,
                active: _camOn,
                onTap: _toggleCamera,
              ),
              _ControlButton(
                icon:
                    Icons.screen_share_outlined,
                active: _screenSharing,
                onTap: _toggleScreenShare,
              ),
              _ControlButton(
                icon:
                    Icons.chat_bubble_outline,
                onTap: () {
                  setState(() {
                    _showChat = true;
                  });
                },
              ),
              _ControlButton(
                icon: Icons.people_outline,
                onTap: () {
                  setState(() {
                    _showParticipants = true;
                  });
                },
              ),
              _ControlButton(
                icon:
                    Icons.back_hand_outlined,
                active: _handRaised,
                onTap: _toggleRaiseHand,
              ),
              _ControlButton(
                icon:
                    Icons.closed_caption_outlined,
                active: _liveCaptions,
                onTap: _toggleCaptions,
              ),
              _ControlButton(
                icon: Icons.note_alt_outlined,
                onTap: () {
                  setState(() {
                    _showNotes = true;
                  });
                },
              ),
              _ControlButton(
                icon: Icons.more_horiz,
                onTap: _showMoreOptions,
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
    return _Panel(
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
                        color: Colors.white38,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding:
                        const EdgeInsets.all(16),
                    itemCount:
                        _chatMessages.length,
                    itemBuilder: (_, index) {
                      final message =
                          _chatMessages[index];

                      return _ChatBubble(
                        message: message,
                        isMe:
                            message.senderId ==
                                widget.userId,
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
                    style: const TextStyle(
                      color: Colors.white,
                    ),
                    decoration:
                        InputDecoration(
                      hintText:
                          'Écrire un message...',
                      hintStyle:
                          const TextStyle(
                        color: Colors.white38,
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
                            BorderRadius.circular(
                          24,
                        ),
                        borderSide:
                            BorderSide.none,
                      ),
                    ),
                    onSubmitted:
                        (_) => _sendChat(),
                  ),
                ),
                IconButton(
                  onPressed: _sendChat,
                  icon: const Icon(
                    Icons.send,
                    color: AppColors.primary,
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
    final participants =
        <RemoteParticipant>[
      ..._remoteParticipants,
    ];

    return _Panel(
      title:
          'Participants ($_participantCount)',
      onClose: () {
        setState(() {
          _showParticipants = false;
        });
      },
      child: Column(
        children: [
          if (widget.isHost ||
              widget.userId == _organizerId)
            Padding(
              padding:
                  const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child:
                    ElevatedButton.icon(
                  onPressed:
                      _muteAllOthers,
                  icon:
                      const Icon(Icons.mic_off),
                  label: const Text(
                    'Muter tous les autres',
                  ),
                ),
              ),
            ),
          Expanded(
            child: participants.isEmpty
                ? const Center(
                    child: Text(
                      'Aucun participant distant',
                      style: TextStyle(
                        color: Colors.white38,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount:
                        participants.length,
                    itemBuilder: (_, index) {
                      final p =
                          participants[index];

                      final raised =
                          _raisedHands.contains(
                        p.identity,
                      );

                      return ListTile(
                        leading: _Avatar(
                          name: p.name,
                        ),
                        title: Text(
                          p.name.isNotEmpty
                              ? p.name
                              : 'Participant',
                          style:
                              const TextStyle(
                            color: Colors.white,
                          ),
                        ),
                        subtitle: Text(
                          p.identity,
                          style:
                              const TextStyle(
                            color:
                                Colors.white38,
                            fontSize: 10,
                          ),
                        ),
                        trailing: raised
                            ? const Icon(
                                Icons.back_hand,
                                color:
                                    Colors.orange,
                              )
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // NOTES
  // ===========================================================================

  Widget _buildNotesPanel() {
    return _Panel(
      title: 'Notes de réunion',
      onClose: () async {
        await NoteService.instance
            .saveMeetingNote(
          userId: widget.userId,
          meetingId: widget.meetingId,
          meetingName: widget.meetingName,
          content: _noteController.text,
        );

        if (!mounted) return;

        setState(() {
          _showNotes = false;
        });
      },
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: TextField(
          controller: _noteController,
          maxLines: null,
          expands: true,
          textAlignVertical:
              TextAlignVertical.top,
          style: const TextStyle(
            color: Colors.white,
            height: 1.5,
          ),
          decoration:
              const InputDecoration(
            hintText:
                'Écrivez vos notes...',
            hintStyle: TextStyle(
              color: Colors.white24,
            ),
            border: InputBorder.none,
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // MORE OPTIONS
  // ===========================================================================

  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding:
              const EdgeInsets.symmetric(
            vertical: 16,
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.closed_caption_outlined,
                    color: Colors.white,
                  ),
                  title: const Text(
                    'Sous-titres en direct',
                    style: TextStyle(
                      color: Colors.white,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);

                    _toggleCaptions();
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.screen_share_outlined,
                    color: Colors.white,
                  ),
                  title: Text(
                    _screenSharing
                        ? 'Arrêter le partage'
                        : 'Partager l’écran',
                    style: const TextStyle(
                      color: Colors.white,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);

                    _toggleScreenShare();
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.volume_up_outlined,
                    color: Colors.white,
                  ),
                  title: Text(
                    _voiceAssistant
                        ? 'Désactiver l’assistant vocal'
                        : 'Activer l’assistant vocal',
                    style: const TextStyle(
                      color: Colors.white,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);

                    setState(() {
                      _voiceAssistant =
                          !_voiceAssistant;
                    });
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.copy_outlined,
                    color: Colors.white,
                  ),
                  title: const Text(
                    'Copier le lien',
                    style: TextStyle(
                      color: Colors.white,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);

                    _copyMeetingLink();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ===========================================================================
  // LINK
  // ===========================================================================

  Future<void> _copyMeetingLink() async {
    final link = AppConfig.webJoinLink(
      widget.meetingId,
    );

    await Clipboard.setData(
      ClipboardData(text: link),
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Lien copié.'),
      ),
    );
  }

  // ===========================================================================
  // RECONNECT BANNER
  // ===========================================================================

  Widget _buildReconnectBanner() {
    return Positioned(
      top: 80,
      left: 20,
      right: 20,
      child: Container(
        padding:
            const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
        decoration:
            BoxDecoration(
          color: Colors.orange.withValues(
            alpha: 0.92,
          ),
          borderRadius:
              BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            const SizedBox(
              width: 10,
            ),
            const Expanded(
              child: Text(
                'Reconnexion à la conférence...',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// VIDEO TILE
// =============================================================================

class _VideoTile extends StatelessWidget {
  final Participant? participant;

  final bool isLocal;

  final String userName;

  final bool active;

  const _VideoTile({
    required this.participant,
    required this.isLocal,
    required this.userName,
    required this.active,
  });

  VideoTrack? _findVideoTrack() {
    final p = participant;

    if (p == null) {
      return null;
    }

    if (p is LocalParticipant) {
      for (final publication
          in p.videoTrackPublications) {
        final track = publication.track;

        if (track is VideoTrack &&
            !publication.muted) {
          return track;
        }
      }

      return null;
    }

    if (p is RemoteParticipant) {
      for (final publication
          in p.videoTrackPublications) {
        if (!publication.subscribed ||
            publication.muted) {
          continue;
        }

        final track = publication.track;

        if (track is VideoTrack) {
          return track;
        }
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final track = _findVideoTrack();

    return AnimatedContainer(
      duration:
          const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius:
            BorderRadius.circular(20),
        border: Border.all(
          color: active
              ? AppColors.primary
              : Colors.white10,
          width: active ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (track != null)
            VideoTrackRenderer(
              track,
              fit: VideoViewFit.cover,
              mirrorMode: isLocal
                  ? VideoViewMirrorMode.mirror
                  : VideoViewMirrorMode.auto,
            )
          else
            Container(
              color: AppColors.surface,
              alignment: Alignment.center,
              child: _Avatar(
                name: userName,
                large: true,
              ),
            ),
          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(
                        alpha: 0.55,
                      ),
                      borderRadius:
                          BorderRadius.circular(9),
                    ),
                    child: Text(
                      isLocal
                          ? '$userName (vous)'
                          : (userName.isEmpty
                              ? 'Participant'
                              : userName),
                      maxLines: 1,
                      overflow:
                          TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight:
                            FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                if (active) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.all(6),
                    decoration:
                        const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.graphic_eq,
                      size: 13,
                      color: Colors.white,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 250.ms);
  }
}

// =============================================================================
// PANEL
// =============================================================================

class _Panel extends StatelessWidget {
  final String title;

  final Widget child;

  final VoidCallback onClose;

  const _Panel({
    required this.title,
    required this.child,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 18,
            sigmaY: 18,
          ),
          child: Container(
            color: Colors.black.withValues(
              alpha: 0.90,
            ),
            child: Column(
              children: [
                SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: onClose,
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          title,
                          style:
                              GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight:
                                FontWeight.w700,
                            fontSize: 17,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: child,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// CHAT MESSAGE
// =============================================================================

class _ChatMessage {
  final String senderId;

  final String sender;

  final String message;

  final DateTime? timestamp;

  final bool isPrivate;

  const _ChatMessage({
    required this.senderId,
    required this.sender,
    required this.message,
    required this.timestamp,
    required this.isPrivate,
  });
}

// =============================================================================
// CHAT BUBBLE
// =============================================================================

class _ChatBubble extends StatelessWidget {
  final _ChatMessage message;

  final bool isMe;

  const _ChatBubble({
    required this.message,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final time = message.timestamp == null
        ? ''
        : '${message.timestamp!.hour.toString().padLeft(2, '0')}:'
            '${message.timestamp!.minute.toString().padLeft(2, '0')}';

    return Align(
      alignment: isMe
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: Container(
        constraints:
            const BoxConstraints(
          maxWidth: 340,
        ),
        margin:
            const EdgeInsets.symmetric(
          vertical: 4,
        ),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMe
              ? AppColors.primary
              : Colors.white10,
          borderRadius:
              BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Text(
                message.sender,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  fontWeight:
                      FontWeight.w700,
                ),
              ),
            Text(
              message.message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
              ),
            ),
            if (time.isNotEmpty)
              Align(
                alignment:
                    Alignment.centerRight,
                child: Text(
                  time,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 9,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// TOP PILL
// =============================================================================

class _TopPill extends StatelessWidget {
  final IconData icon;

  final String text;

  const _TopPill({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius:
            BorderRadius.circular(999),
        border: Border.all(
          color: Colors.white10,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: Colors.white70,
          ),
          const SizedBox(
            width: 5,
          ),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// CONTROL BUTTON
// =============================================================================

class _ControlButton extends StatelessWidget {
  final IconData icon;

  final bool active;

  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active
          ? Colors.white10
          : Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            icon,
            color: active
                ? Colors.white
                : Colors.white60,
            size: 22,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// AVATAR
// =============================================================================

class _Avatar extends StatelessWidget {
  final String name;

  final bool large;

  const _Avatar({
    required this.name,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final size = large ? 72.0 : 42.0;

    final initial = name.trim().isEmpty
        ? '?'
        : name
            .trim()
            .characters
            .first
            .toUpperCase();

    return Container(
      width: size,
      height: size,
      decoration:
          const BoxDecoration(
        gradient:
            AppColors.primaryGradient,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: large ? 28 : 17,
        ),
      ),
    );
  }
}
