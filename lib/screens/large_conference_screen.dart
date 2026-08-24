import 'dart:async';
import 'dart:convert';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webrtc_interface/webrtc_interface.dart' as rtc;

import '../utils/logger.dart' as crux;
import '../config/app_config.dart';
import '../services/livekit_service.dart';
import '../services/meeting_service.dart';
import '../services/error_handler_service.dart';
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
  State<LargeConferenceScreen> createState() =>
      _LargeConferenceScreenState();
}

class _LargeConferenceScreenState extends State<LargeConferenceScreen>
    with WidgetsBindingObserver {
  // ===========================================================================
  // SERVICES
  // ===========================================================================

  final ErrorHandlerService _errorHandler = ErrorHandlerService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ===========================================================================
  // LIVEKIT
  // ===========================================================================

  Room? _room;
  EventsListener<RoomEvent>? _roomEventsListener;

  int _reconnectAttempts = 0;
  bool _isReconnecting = false;

  // ===========================================================================
  // AUDIO / VIDEO
  // ===========================================================================

  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _micOn = true;
  bool _camOn = true;

  // ===========================================================================
  // PARTICIPANTS
  // ===========================================================================

  List<RemoteParticipant> _remoteParticipants = [];

  String? _activeSpeakerId;
  String? _organizerId;

  final List<String> _raisedHands = [];

  // ===========================================================================
  // UI
  // ===========================================================================

  bool _loading = true;
  String? _error;

  bool _showChat = false;
  bool _showParticipants = false;
  bool _showNotes = false;
  bool _voiceAssistant = false;

  // ===========================================================================
  // PRO / TIMER
  // ===========================================================================

  Timer? _callTimer;

  int _secondsElapsed = 0;

  bool _isPro = false;
  bool _paywallShown = false;

  // ===========================================================================
  // TRANSCRIPTION
  // ===========================================================================

  String _currentTranscription = '';

  // ===========================================================================
  // CONTROLLERS
  // ===========================================================================

  late final TextEditingController _noteController;
  late final TextEditingController _chatController;

  // ===========================================================================
  // FIRESTORE
  // ===========================================================================

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _presenceSubscription;

  // ===========================================================================
  // INIT
  // ===========================================================================

  @override
  void initState() {
    super.initState();

    _noteController = TextEditingController();
    _chatController = TextEditingController();

    WidgetsBinding.instance.addObserver(this);

    _initializeConference();
  }

  // ===========================================================================
  // INITIALIZATION
  // ===========================================================================

  Future<void> _initializeConference() async {
    try {
      crux.logger.i('Conference initialization started');

      await _checkPro();
      await _loadPreferences();
      await _registerPresence();
      await _connectToRoom();
      await _listenRoomEvents();

      _startCallTimer();

      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = null;
      });

      crux.logger.i('Conference initialization complete');
    } catch (e, st) {
      crux.logger.e(
        'Conference initialization failed',
        error: e,
        stackTrace: st,
      );

      _showMeetingError(e.toString());
    }
  }

  // ===========================================================================
  // PRO
  // ===========================================================================

  Future<void> _checkPro() async {
    try {
      crux.logger.i('Checking Pro status');

      final pro = await ProService().checkProStatus(widget.userId);

      if (!mounted) return;

      setState(() {
        _isPro = pro;
      });

      crux.logger.i('Pro status: $_isPro');
    } catch (e) {
      crux.logger.w(
        'Pro status check failed, assuming free',
        error: e,
      );

      if (!mounted) return;

      setState(() {
        _isPro = false;
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
        _micOn = prefs.getBool('crux_mic_default') ?? true;
        _camOn = prefs.getBool('crux_cam_default') ?? true;
      });

      crux.logger.i(
        'Preferences loaded: mic=$_micOn cam=$_camOn',
      );
    } catch (e) {
      crux.logger.w(
        'Could not load preferences',
        error: e,
      );
    }
  }

  // ===========================================================================
  // FIRESTORE PRESENCE
  // ===========================================================================

  Future<void> _registerPresence() async {
    try {
      crux.logger.i('Registering presence');

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

      crux.logger.i('Presence registered');
    } catch (e, st) {
      crux.logger.e(
        'Presence registration failed',
        error: e,
        stackTrace: st,
      );

      rethrow;
    }
  }

  // ===========================================================================
  // CONNECT LIVEKIT
  // ===========================================================================

  Future<void> _connectToRoom() async {
    try {
      crux.logger.i('Connecting to LiveKit');

      final token = await LiveKitService.instance.fetchToken(
        room: widget.meetingId,
        identity: widget.userId,
        name: widget.userName,
        isHost: widget.isHost,
      );

      if (token == null || token.isEmpty) {
        throw Exception(
          'LiveKit token server unavailable. '
          'Please try again.',
        );
      }

      // Nettoyage d'une ancienne room avant reconnexion.
      if (_room != null) {
        try {
          await _room!.disconnect();
        } catch (_) {}

        try {
          _room!.dispose();
        } catch (_) {}

        _room = null;
      }

      _room = Room(
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          defaultVideoPublishOptions: VideoPublishOptions(
            simulcast: true,
          ),
        ),
      );

      // -----------------------------------------------------------------------
      // ORGANIZER
      // -----------------------------------------------------------------------

      try {
        final doc = await _db
            .collection('meetings')
            .doc(widget.meetingId)
            .get();

        if (doc.exists) {
          _organizerId = doc.data()?['organizerId'] as String?;
        }
      } catch (e) {
        crux.logger.w(
          'Could not load organizer ID',
          error: e,
        );
      }

      // -----------------------------------------------------------------------
      // CONNECT
      // -----------------------------------------------------------------------

      await _room!
          .connect(
            AppConfig.livekitWssUrl,
            token,
          )
          .timeout(
            AppConfig.roomConnectionTimeout,
            onTimeout: () {
              throw TimeoutException(
                'LiveKit room connection timeout',
              );
            },
          );

      // -----------------------------------------------------------------------
      // MICRO
      // -----------------------------------------------------------------------

      final localParticipant = _room!.localParticipant;

      if (localParticipant != null) {
        await localParticipant.setMicrophoneEnabled(_micOn);
        await localParticipant.setCameraEnabled(_camOn);
      }

      _refreshParticipants();

      _reconnectAttempts = 0;

      crux.logger.i(
        'Connected to LiveKit. '
        'Participants: ${_remoteParticipants.length}',
      );
    } catch (e, st) {
      crux.logger.e(
        'Room connection failed',
        error: e,
        stackTrace: st,
      );

      rethrow;
    }
  }

  // ===========================================================================
  // LIVEKIT EVENTS
  // ===========================================================================

  Future<void> _listenRoomEvents() async {
    if (_room == null) {
      throw Exception('LiveKit room not initialized');
    }

    try {
      _roomEventsListener?.dispose();

      _roomEventsListener = _room!.createListener()
        ..on<RoomConnectedEvent>((_) {
          crux.logger.i('LiveKit room connected');

          _refreshParticipants();
        })
        ..on<RoomDisconnectedEvent>((_) {
          crux.logger.w(
            'LiveKit room disconnected',
          );

          if (mounted && !_isReconnecting) {
            _attemptReconnection();
          }
        })
        ..on<RoomReconnectingEvent>((_) {
          crux.logger.w(
            'LiveKit reconnecting',
          );

          if (mounted) {
            setState(() {
              _isReconnecting = true;
            });
          }
        })
        ..on<RoomReconnectedEvent>((_) {
          crux.logger.i(
            'LiveKit reconnected',
          );

          _isReconnecting = false;
          _reconnectAttempts = 0;

          _refreshParticipants();

          if (mounted) {
            setState(() {
              _error = null;
            });
          }
        })
        ..on<ParticipantConnectedEvent>((event) {
          final participant = event.participant;

          crux.logger.i(
            'Participant joined: ${participant.name}',
          );

          _announce(
            '${participant.name.isNotEmpty ? participant.name : 'A participant'} '
            'joined the meeting.',
          );

          _refreshParticipants();
        })
        ..on<ParticipantDisconnectedEvent>((event) {
          final participant = event.participant;

          crux.logger.i(
            'Participant left: ${participant.name}',
          );

          _announce(
            '${participant.name.isNotEmpty ? participant.name : 'A participant'} '
            'left the meeting.',
          );

          _refreshParticipants();
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
        ..on<DataReceivedEvent>((event) {
          _handleDataReceived(event);
        })
        ..on<TrackSubscribedEvent>((_) {
          _refreshParticipants();
        })
        ..on<TrackUnsubscribedEvent>((_) {
          _refreshParticipants();
        })
        ..on<LocalTrackPublishedEvent>((_) {
          _refreshParticipants();
        })
        ..on<LocalTrackUnpublishedEvent>((_) {
          _refreshParticipants();
        });

      crux.logger.i(
        'LiveKit event listeners initialized',
      );
    } catch (e, st) {
      crux.logger.e(
        'Event listener setup failed',
        error: e,
        stackTrace: st,
      );

      rethrow;
    }
  }

  // ===========================================================================
  // DATA RECEIVED
  // ===========================================================================

  void _handleDataReceived(DataReceivedEvent event) {
    try {
      final text = utf8.decode(event.data);

      final decoded = jsonDecode(text);

      if (decoded is! Map<String, dynamic>) {
        return;
      }

      final type = decoded['type'];

      if (type == 'mute_all') {
        final senderIdentity =
            event.participant?.identity;

        if (senderIdentity == _organizerId) {
          if (_micOn) {
            _toggleMic();

            _announce(
              'The organizer muted your microphone.',
            );
          }
        }
      }

      if (type == 'raise_hand') {
        final identity =
            decoded['identity'] as String?;

        if (identity != null &&
            !_raisedHands.contains(identity)) {
          if (mounted) {
            setState(() {
              _raisedHands.add(identity);
            });
          }
        }
      }

      if (type == 'lower_hand') {
        final identity =
            decoded['identity'] as String?;

        if (identity != null) {
          if (mounted) {
            setState(() {
              _raisedHands.remove(identity);
            });
          }
        }
      }
    } catch (e) {
      crux.logger.w(
        'Could not parse LiveKit data',
        error: e,
      );
    }
  }

  // ===========================================================================
  // PARTICIPANTS
  // ===========================================================================

  void _refreshParticipants() {
    final room = _room;

    if (!mounted || room == null) {
      return;
    }

    setState(() {
      _remoteParticipants =
          room.remoteParticipants.values.toList();
    });

    crux.logger.i(
      'Participants refreshed: ${_remoteParticipants.length}',
    );
  }

  // ===========================================================================
  // TIMER
  // ===========================================================================

  void _startCallTimer() {
    _callTimer?.cancel();

    _callTimer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        setState(() {
          _secondsElapsed++;
        });

        if (_isPro) {
          return;
        }

        final limitSeconds =
            AppConfig.freeMeetingDurationMinutes * 60;

        final warningSeconds =
            limitSeconds - 300;

        if (_secondsElapsed == warningSeconds &&
            warningSeconds > 0) {
          _announce(
            'Attention. Your free call will end in five minutes. '
            'Upgrade to CRUX Pro for unlimited calls.',
          );
        }

        if (_secondsElapsed >= limitSeconds) {
          timer.cancel();

          if (!_paywallShown) {
            _paywallShown = true;
            _showPaywall();
          }
        }
      },
    );
  }

  // ===========================================================================
  // RECONNECTION
  // ===========================================================================

  Future<void> _attemptReconnection() async {
    if (_isReconnecting) {
      return;
    }

    if (_reconnectAttempts >=
        AppConfig.maxReconnectAttempts) {
      _isReconnecting = false;

      _showMeetingError(
        'Lost connection to the meeting. '
        'Tap Retry to reconnect or Leave to exit.',
      );

      return;
    }

    _isReconnecting = true;

    _reconnectAttempts++;

    crux.logger.i(
      'Reconnection attempt '
      '$_reconnectAttempts/'
      '${AppConfig.maxReconnectAttempts}',
    );

    try {
      await Future.delayed(
        AppConfig.reconnectDelay,
      );

      if (!mounted) {
        _isReconnecting = false;
        return;
      }

      await _connectToRoom();
      await _listenRoomEvents();

      if (!mounted) {
        _isReconnecting = false;
        return;
      }

      setState(() {
        _error = null;
        _loading = false;
      });

      _isReconnecting = false;
    } catch (e, st) {
      crux.logger.e(
        'Reconnection attempt failed',
        error: e,
        stackTrace: st,
      );

      _isReconnecting = false;

      if (_reconnectAttempts <
          AppConfig.maxReconnectAttempts) {
        await _attemptReconnection();
      } else {
        _showMeetingError(
          'Unable to reconnect to the meeting.',
        );
      }
    }
  }

  // ===========================================================================
  // MICRO
  // ===========================================================================

  Future<void> _toggleMic() async {
    final participant = _room?.localParticipant;

    if (participant == null) {
      return;
    }

    final newState = !_micOn;

    try {
      await participant.setMicrophoneEnabled(
        newState,
      );

      if (!mounted) return;

      setState(() {
        _micOn = newState;
      });

      final prefs =
          await SharedPreferences.getInstance();

      await prefs.setBool(
        'crux_mic_default',
        newState,
      );
    } catch (e) {
      crux.logger.e(
        'Could not toggle microphone',
        error: e,
      );
    }
  }

  // ===========================================================================
  // CAMERA
  // ===========================================================================

  Future<void> _toggleCam() async {
    final participant = _room?.localParticipant;

    if (participant == null) {
      return;
    }

    final newState = !_camOn;

    try {
      await participant.setCameraEnabled(
        newState,
      );

      if (!mounted) return;

      setState(() {
        _camOn = newState;
      });

      final prefs =
          await SharedPreferences.getInstance();

      await prefs.setBool(
        'crux_cam_default',
        newState,
      );
    } catch (e) {
      crux.logger.e(
        'Could not toggle camera',
        error: e,
      );
    }
  }

  // ===========================================================================
  // TTS
  // ===========================================================================

  Future<void> _announce(String text) async {
    if (!_voiceAssistant) {
      return;
    }

    try {
      await _tts.setLanguage('en-US');
      await _tts.setPitch(1.0);
      await _tts.speak(text);
    } catch (e) {
      crux.logger.w(
        'TTS error',
        error: e,
      );
    }
  }

  // ===========================================================================
  // ERROR HANDLING
  // ===========================================================================

  void _showMeetingError(String errorMsg) {
    String friendlyMsg = errorMsg;

    try {
      final lang =
          context.read<LocaleProvider>()
              .locale
              .languageCode;

      friendlyMsg =
          _errorHandler.getMeetingErrorMessageL(
        errorMsg,
        lang,
      );
    } catch (e) {
      crux.logger.w(
        'Could not localize meeting error',
        error: e,
      );
    }

    if (mounted) {
      setState(() {
        _loading = false;
        _error = friendlyMsg;
      });
    }

    crux.logger.e(
      'Meeting error',
      error: friendlyMsg,
    );
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
            'Time limit reached',
            style: TextStyle(
              color: Colors.white,
            ),
          ),
          content: const Text(
            'Your 30-minute free call limit has been reached. '
            'Upgrade to CRUX Pro for unlimited calls.',
            style: TextStyle(
              color: Colors.white70,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _leave();
              },
              child: const Text('Leave'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(ctx).pop();

                try {
                  await ProService().startPayment(
                    userId: widget.userId,
                    userName: widget.userName,
                  );
                } catch (e) {
                  crux.logger.e(
                    'Payment initialization failed',
                    error: e,
                  );
                }
              },
              child: const Text('Upgrade'),
            ),
          ],
        );
      },
    );
  }

  // ===========================================================================
  // FORMAT TIME
  // ===========================================================================

  String _formatElapsedDuration() {
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
  // INVITE LINK
  // ===========================================================================

  String get _joinUrl {
    return 'https://crux-3c6be.web.app/'
        'join/${widget.meetingId}';
  }

  Future<void> _copyInviteLink() async {
    await Clipboard.setData(
      ClipboardData(
        text: _joinUrl,
      ),
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Meeting link copied.',
        ),
      ),
    );
  }

  // ===========================================================================
  // LEAVE
  // ===========================================================================

  Future<void> _confirmLeave() async {
    if (!mounted) return;

    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text(
            'Leave meeting?',
            style: TextStyle(
              color: Colors.white,
            ),
          ),
          content: const Text(
            'Are you sure you want to leave?',
            style: TextStyle(
              color: Colors.white70,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop(false);
              },
              child: const Text('Stay'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop(true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
              ),
              child: const Text('Leave'),
            ),
          ],
        );
      },
    );

    if (leave == true) {
      await _leave();
    }
  }

  Future<void> _leave() async {
    crux.logger.i('Leaving meeting');

    _callTimer?.cancel();

    try {
      await MeetingService().saveMeetingHistoryForUser(
        meetingId: widget.meetingId,
        userId: widget.userId,
        title: widget.meetingName,
        durationSeconds: _secondsElapsed,
        endMeeting: widget.isHost,
      );
    } catch (e) {
      crux.logger.e(
        'Could not save meeting history',
        error: e,
      );
    }

    try {
      await MeetingService().removePresence(
        widget.meetingId,
        widget.userId,
      );
    } catch (e) {
      crux.logger.e(
        'Could not remove presence',
        error: e,
      );
    }

    try {
      await _room?.disconnect();
    } catch (e) {
      crux.logger.w(
        'Could not disconnect LiveKit room',
        error: e,
      );
    }

    if (!mounted) return;

    Navigator.of(context).pop();
  }

  // ===========================================================================
  // LIFECYCLE
  // ===========================================================================

  @override
  void didChangeAppLifecycleState(
    AppLifecycleState state,
  ) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      if (_room != null &&
          _room!.connectionState ==
              ConnectionState.disconnected &&
          !_isReconnecting) {
        _attemptReconnection();
      }
    }
  }

  @override
  void dispose() {
    crux.logger.i(
      'Cleaning up conference resources',
    );

    _callTimer?.cancel();

    _roomEventsListener?.dispose();
    _roomEventsListener = null;

    try {
      _room?.disconnect();
    } catch (_) {}

    try {
      _room?.dispose();
    } catch (_) {}

    _room = null;

    _tts.stop();
    _speech.stop();

    _noteController.dispose();
    _chatController.dispose();

    _presenceSubscription?.cancel();

    WidgetsBinding.instance.removeObserver(this);

    super.dispose();

    crux.logger.i(
      'Conference resources disposed',
    );
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _buildErrorScreen();
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: _loading
          ? _buildLoading()
          : Stack(
              children: [
                _buildVideoGrid(),
                _buildTopBar(),
                _buildSubtitleOverlay(),
                _buildBottomBar(),

                if (_showChat)
                  _buildChatPanel(),

                if (_showParticipants)
                  _buildParticipantsPanel(),

                if (_showNotes)
                  _buildNotesPanel(),

                if (_isReconnecting)
                  _buildReconnectingOverlay(),
              ],
            ),
    );
  }

  // ===========================================================================
  // ERROR SCREEN
  // ===========================================================================

  Widget _buildErrorScreen() {
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
              const SizedBox(height: 16),
              Text(
                _error ?? 'An error occurred.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment:
                    MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: _leave,
                    child: const Text('Back'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () {
                      if (_isReconnecting) {
                        return;
                      }

                      setState(() {
                        _error = null;
                        _loading = true;
                      });

                      _attemptReconnection();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          AppColors.primary,
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ],
          ),
        ),
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
            'Preparing your meeting...',
            style: GoogleFonts.poppins(
              color: Colors.white54,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // RECONNECTING OVERLAY
  // ===========================================================================

  Widget _buildReconnectingOverlay() {
    return Positioned(
      top: 100,
      left: 20,
      right: 20,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius:
                BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white10,
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              ),
              SizedBox(width: 10),
              Text(
                'Reconnecting...',
                style: TextStyle(
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // VIDEO GRID
  // ===========================================================================

  Widget _buildVideoGrid() {
    final local = _room?.localParticipant;

    final List<Participant> all = [
      if (local != null) local,
      ..._remoteParticipants,
    ];

    final visible = all
        .take(
          AppConfig.livekitVisibleTileCap,
        )
        .toList();

    if (visible.isEmpty) {
      return Center(
        child: _buildAvatar(
          widget.userName,
          large: true,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
      ),
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(
          0,
          90,
          0,
          110,
        ),
        gridDelegate:
            const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.8,
        ),
        itemCount: visible.length,
        itemBuilder: (_, index) {
          return _buildParticipantTile(
            visible[index],
          );
        },
      ),
    );
  }

  // ===========================================================================
  // PARTICIPANT TILE
  // ===========================================================================

  Widget _buildParticipantTile(
    Participant participant,
  ) {
    final isSpeaking =
        _activeSpeakerId == participant.identity;

    VideoTrack? videoTrack;
    bool isScreenShare = false;

    for (final publication
        in participant.videoTrackPublications) {
      final track = publication.track;

      if (track is VideoTrack &&
          !publication.muted) {
        videoTrack = track;

        isScreenShare =
            publication.source ==
                TrackSource.screenShareVideo;

        break;
      }
    }

    final hasVideo = videoTrack != null;

    final displayName =
        participant.name.isNotEmpty
            ? participant.name
            : 'Guest';

    return AnimatedContainer(
      duration:
          const Duration(milliseconds: 400),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius:
            BorderRadius.circular(24),
        border: Border.all(
          color: isSpeaking
              ? AppColors.primary
              : Colors.white.withValues(
                  alpha: 0.05,
                ),
          width: 2,
        ),
        boxShadow: isSpeaking
            ? [
                BoxShadow(
                  color:
                      AppColors.primary.withValues(
                    alpha: 0.3,
                  ),
                  blurRadius: 15,
                ),
              ]
            : const [],
      ),
      child: ClipRRect(
        borderRadius:
            BorderRadius.circular(24),
        child: Stack(
          children: [
            Positioned.fill(
              child: hasVideo
                  ? VideoTrackRenderer(
                      videoTrack!,
                      fit: isScreenShare
                          ? rtc
                              .RTCVideoViewObjectFit
                              .RTCVideoViewObjectFitContain
                          : rtc
                              .RTCVideoViewObjectFit
                              .RTCVideoViewObjectFitCover,
                    )
                  : Center(
                      child: _buildAvatar(
                        displayName,
                        large: true,
                      ),
                    ),
            ),

            // ---------------------------------------------------------------
            // NAME
            // ---------------------------------------------------------------

            Positioned(
              bottom: 12,
              left: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius:
                      BorderRadius.circular(8),
                ),
                child: Text(
                  displayName,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight:
                        FontWeight.w600,
                  ),
                ),
              ),
            ),

            // ---------------------------------------------------------------
            // RAISED HAND
            // ---------------------------------------------------------------

            if (_raisedHands.contains(
              participant.identity,
            ))
              const Positioned(
                top: 12,
                right: 12,
                child: Icon(
                  Icons.back_hand,
                  color: Colors.orange,
                  size: 20,
                ),
              ),

            // ---------------------------------------------------------------
            // SCREEN SHARE
            // ---------------------------------------------------------------

            if (isScreenShare)
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(
                      alpha: 0.8,
                    ),
                    borderRadius:
                        BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize:
                        MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.screen_share,
                        color: Colors.white,
                        size: 12,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'SCREEN',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(
          duration: 400.ms,
        )
        .scale(
          begin: const Offset(
            0.9,
            0.9,
          ),
        );
  }

  // ===========================================================================
  // AVATAR
  // ===========================================================================

  Widget _buildAvatar(
    String name, {
    bool large = false,
  }) {
    return Container(
      width: large ? 60 : 32,
      height: large ? 60 : 32,
      decoration: const BoxDecoration(
        gradient:
            AppColors.primaryGradient,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          name.isNotEmpty
              ? name[0].toUpperCase()
              : '?',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: large ? 24 : 14,
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // SUBTITLE
  // ===========================================================================

  Widget _buildSubtitleOverlay() {
    if (_currentTranscription.isEmpty) {
      return const SizedBox();
    }

    return Positioned(
      bottom: 110,
      left: 30,
      right: 30,
      child: ClipRRect(
        borderRadius:
            BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 10,
            sigmaY: 10,
          ),
          child: Container(
            padding:
                const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius:
                  BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white10,
              ),
            ),
            child: Text(
              _currentTranscription,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
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
          20,
          16,
          20,
          16,
        ),
        decoration:
            const BoxDecoration(
          gradient: LinearGradient(
            begin:
                Alignment.topCenter,
            end:
                Alignment.bottomCenter,
            colors: [
              Colors.black87,
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          child: Row(
            children: [
              Flexible(
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
                        fontWeight:
                            FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      'ID: ${widget.meetingId}',
                      maxLines: 1,
                      overflow:
                          TextOverflow.ellipsis,
                      style:
                          GoogleFonts.poppins(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // TIMER

              Container(
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration:
                    BoxDecoration(
                  color: Colors.black45,
                  borderRadius:
                      BorderRadius.circular(
                    999,
                  ),
                  border: Border.all(
                    color: Colors.white10,
                  ),
                ),
                child: Text(
                  _formatElapsedDuration(),
                  style:
                      GoogleFonts.poppins(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight:
                        FontWeight.w700,
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // LINK

              IconButton(
                tooltip: 'Copy meeting link',
                icon: const Icon(
                  Icons.link,
                  color: Colors.white70,
                  size: 20,
                ),
                onPressed:
                    _copyInviteLink,
              ),

              const SizedBox(width: 4),

              // VOICE ASSISTANT

              IconButton(
                tooltip:
                    'Voice assistant',
                icon: Icon(
                  _voiceAssistant
                      ? Icons.volume_up
                      : Icons.volume_off,
                  color:
                      Colors.white70,
                  size: 20,
                ),
                onPressed: () {
                  setState(() {
                    _voiceAssistant =
                        !_voiceAssistant;
                  });
                },
              ),

              const SizedBox(width: 8),

              // LEAVE

              GestureDetector(
                onTap: _confirmLeave,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration:
                      BoxDecoration(
                    color:
                        AppColors.error
                            .withValues(
                      alpha: 0.2,
                    ),
                    borderRadius:
                        BorderRadius.circular(
                      12,
                    ),
                    border: Border.all(
                      color:
                          AppColors.error
                              .withValues(
                        alpha: 0.5,
                      ),
                    ),
                  ),
                  child: const Text(
                    'Leave',
                    style: TextStyle(
                      color:
                          AppColors.error,
                      fontWeight:
                          FontWeight.bold,
                      fontSize: 12,
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

  // ===========================================================================
  // BOTTOM BAR
  // ===========================================================================

  Widget _buildBottomBar() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding:
            const EdgeInsets.fromLTRB(
          16,
          12,
          16,
          32,
        ),
        decoration:
            const BoxDecoration(
          color: AppColors.surface,
          borderRadius:
              BorderRadius.vertical(
            top: Radius.circular(32),
          ),
        ),
        child: Row(
          mainAxisAlignment:
              MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              tooltip: 'Microphone',
              icon: Icon(
                _micOn
                    ? Icons.mic
                    : Icons.mic_off,
                color: _micOn
                    ? Colors.white70
                    : AppColors.error,
                size: 26,
              ),
              onPressed: _toggleMic,
            ),

            IconButton(
              tooltip: 'Camera',
              icon: Icon(
                _camOn
                    ? Icons.videocam
                    : Icons.videocam_off,
                color: _camOn
                    ? Colors.white70
                    : AppColors.error,
                size: 26,
              ),
              onPressed: _toggleCam,
            ),

            IconButton(
              tooltip: 'Chat',
              icon: const Icon(
                Icons.chat_bubble_outline,
                color: Colors.white70,
                size: 26,
              ),
              onPressed: () {
                setState(() {
                  _showChat = true;
                });
              },
            ),

            IconButton(
              tooltip: 'Notes',
              icon: const Icon(
                Icons.note_alt_outlined,
                color: Colors.white70,
                size: 26,
              ),
              onPressed: () {
                setState(() {
                  _showNotes = true;
                });
              },
            ),

            IconButton(
              tooltip: 'Participants',
              icon: const Icon(
                Icons.people_outline,
                color: Colors.white70,
                size: 26,
              ),
              onPressed: () {
                setState(() {
                  _showParticipants =
                      true;
                });
              },
            ),

            IconButton(
              tooltip: 'More',
              icon: const Icon(
                Icons.more_horiz,
                color: Colors.white70,
                size: 26,
              ),
              onPressed:
                  _showMoreOptions,
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // MORE OPTIONS
  // ===========================================================================

  void _showMoreOptions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor:
          AppColors.surface,
      shape:
          const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.all(20),
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                const Text(
                  'Meeting options',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),

                ListTile(
                  leading: const Icon(
                    Icons.pan_tool_outlined,
                    color: Colors.white70,
                  ),
                  title: const Text(
                    'Raise hand',
                    style: TextStyle(
                      color: Colors.white,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _toggleRaiseHand();
                  },
                ),

                ListTile(
                  leading: const Icon(
                    Icons.copy,
                    color: Colors.white70,
                  ),
                  title: const Text(
                    'Copy invitation link',
                    style: TextStyle(
                      color: Colors.white,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _copyInviteLink();
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
  // RAISE HAND
  // ===========================================================================

  Future<void> _toggleRaiseHand() async {
    final identity = widget.userId;

    final raised =
        _raisedHands.contains(identity);

    try {
      final payload = jsonEncode({
        'type':
            raised ? 'lower_hand' : 'raise_hand',
        'identity': identity,
      });

      final data =
          utf8.encode(payload);

      await _room?.localParticipant
          ?.publishData(
            data,
          );

      if (!mounted) return;

      setState(() {
        if (raised) {
          _raisedHands.remove(identity);
        } else {
          _raisedHands.add(identity);
        }
      });
    } catch (e) {
      crux.logger.w(
        'Could not toggle raised hand',
        error: e,
      );
    }
  }

  // ===========================================================================
  // CHAT PANEL
  // ===========================================================================

  Widget _buildChatPanel() {
    return Positioned(
      top: 70,
      right: 12,
      bottom: 110,
      width: 330,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius:
              BorderRadius.circular(24),
          border: Border.all(
            color: Colors.white10,
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black45,
              blurRadius: 20,
            ),
          ],
        ),
        child: Column(
          children: [
            _buildPanelHeader(
              title: 'Chat',
              icon: Icons.chat_bubble_outline,
              onClose: () {
                setState(() {
                  _showChat = false;
                });
              },
            ),

            const Expanded(
              child: Center(
                child: Text(
                  'No messages yet.',
                  style: TextStyle(
                    color: Colors.white54,
                  ),
                ),
              ),
            ),

            Padding(
              padding:
                  const EdgeInsets.all(12),
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
                      decoration:
                          InputDecoration(
                        hintText:
                            'Write a message...',
                        hintStyle:
                            const TextStyle(
                          color:
                              Colors.white38,
                        ),
                        filled: true,
                        fillColor:
                            Colors.black26,
                        border:
                            OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(
                            14,
                          ),
                          borderSide:
                              BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed:
                        _sendChatMessage,
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
      ),
    );
  }

  // ===========================================================================
  // CHAT SEND
  // ===========================================================================

  Future<void> _sendChatMessage() async {
    final text =
        _chatController.text.trim();

    if (text.isEmpty) {
      return;
    }

    try {
      final payload = jsonEncode({
        'type': 'chat',
        'senderId': widget.userId,
        'senderName': widget.userName,
        'message': text,
        'timestamp':
            DateTime.now()
                .millisecondsSinceEpoch,
      });

      await _room?.localParticipant
          ?.publishData(
            utf8.encode(payload),
          );

      _chatController.clear();
    } catch (e) {
      crux.logger.w(
        'Could not send chat message',
        error: e,
      );
    }
  }

  // ===========================================================================
  // PARTICIPANTS PANEL
  // ===========================================================================

  Widget _buildParticipantsPanel() {
    return Positioned(
      top: 70,
      right: 12,
      bottom: 110,
      width: 330,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius:
              BorderRadius.circular(24),
          border: Border.all(
            color: Colors.white10,
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black45,
              blurRadius: 20,
            ),
          ],
        ),
        child: Column(
          children: [
            _buildPanelHeader(
              title:
                  'Participants (${_remoteParticipants.length + 1})',
              icon: Icons.people_outline,
              onClose: () {
                setState(() {
                  _showParticipants =
                      false;
                });
              },
            ),

            Expanded(
              child: ListView.builder(
                itemCount:
                    _remoteParticipants.length +
                        1,
                itemBuilder:
                    (_, index) {
                  if (index == 0) {
                    return _buildParticipantListTile(
                      widget.userName,
                      widget.userId,
                      isLocal: true,
                    );
                  }

                  final participant =
                      _remoteParticipants[
                          index - 1];

                  return _buildParticipantListTile(
                    participant.name
                            .isNotEmpty
                        ? participant.name
                        : 'Guest',
                    participant.identity,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParticipantListTile(
    String name,
    String identity, {
    bool isLocal = false,
  }) {
    return ListTile(
      leading: _buildAvatar(
        name,
        large: false,
      ),
      title: Text(
        name,
        style: const TextStyle(
          color: Colors.white,
        ),
      ),
      subtitle: Text(
        isLocal ? 'You' : 'Participant',
        style: const TextStyle(
          color: Colors.white38,
        ),
      ),
      trailing:
          _raisedHands.contains(identity)
              ? const Icon(
                  Icons.back_hand,
                  color: Colors.orange,
                )
              : null,
    );
  }

  // ===========================================================================
  // NOTES PANEL
  // ===========================================================================

  Widget _buildNotesPanel() {
    return Positioned(
      top: 70,
      right: 12,
      bottom: 110,
      width: 330,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius:
              BorderRadius.circular(24),
          border: Border.all(
            color: Colors.white10,
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black45,
              blurRadius: 20,
            ),
          ],
        ),
        child: Column(
          children: [
            _buildPanelHeader(
              title: 'Notes',
              icon: Icons.note_alt_outlined,
              onClose: () {
                setState(() {
                  _showNotes = false;
                });
              },
            ),

            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.all(16),
                child: TextField(
                  controller:
                      _noteController,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  textAlignVertical:
                      TextAlignVertical.top,
                  style:
                      const TextStyle(
                    color: Colors.white,
                  ),
                  decoration:
                      InputDecoration(
                    hintText:
                        'Write your notes...',
                    hintStyle:
                        const TextStyle(
                      color: Colors.white38,
                    ),
                    filled: true,
                    fillColor:
                        Colors.black26,
                    border:
                        OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(
                        16,
                      ),
                      borderSide:
                          BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),

            Padding(
              padding:
                  const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed:
                      _saveNotes,
                  icon: const Icon(
                    Icons.save_outlined,
                  ),
                  label:
                      const Text('Save notes'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // SAVE NOTES
  // ===========================================================================

  Future<void> _saveNotes() async {
    final notes =
        _noteController.text.trim();

    if (notes.isEmpty) {
      return;
    }

    try {
      await _db
          .collection('meetings')
          .doc(widget.meetingId)
          .collection('notes')
          .doc(widget.userId)
          .set({
        'userId': widget.userId,
        'userName': widget.userName,
        'content': notes,
        'updatedAt':
            FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content:
              Text('Notes saved.'),
        ),
      );
    } catch (e) {
      crux.logger.e(
        'Could not save notes',
        error: e,
      );
    }
  }

  // ===========================================================================
  // PANEL HEADER
  // ===========================================================================

  Widget _buildPanelHeader({
    required String title,
    required IconData icon,
    required VoidCallback onClose,
  }) {
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(
        16,
        16,
        8,
        12,
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: Colors.white70,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight:
                    FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: const Icon(
              Icons.close,
              color: Colors.white54,
            ),
          ),
        ],
      ),
    );
  }
}
