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
import 'package:webrtc_interface/webrtc_interface.dart' as rtc;

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
  bool _isConnecting = false;

  // ===========================================================================
  // AUDIO / VIDEO
  // ===========================================================================

  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _micOn = true;
  bool _camOn = true;
  bool _screenSharing = false;

  // ===========================================================================
  // PARTICIPANTS
  // ===========================================================================

  List<RemoteParticipant> _remoteParticipants = [];

  String? _activeSpeakerId;
  String? _organizerId;

  // ===========================================================================
  // UI
  // ===========================================================================

  bool _loading = true;
  String? _error;

  bool _showChat = false;
  bool _showParticipants = false;
  bool _showNotes = false;
  bool _voiceAssistant = false;

  final List<String> _raisedHands = [];

  // ===========================================================================
  // TIMER / PRO
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

  StreamSubscription? _presenceSubscription;

  // ===========================================================================
  // CHAT LOCAL
  // ===========================================================================

  final List<_ChatMessage> _chatMessages = [];

  // ===========================================================================
  // LIFECYCLE
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
      crux.logger.i('📋 Conference initialization started');

      await _checkPro();
      await _loadPreferences();
      await _registerPresence();
      await _connectToRoom();
      await _listenRoomEvents();

      _startCallTimer();

      if (mounted) {
        setState(() {
          _loading = false;
          _error = null;
        });
      }

      crux.logger.i('✅ Conference initialization complete');
    } catch (e, st) {
      crux.logger.e(
        '❌ Conference initialization failed',
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
      crux.logger.i('🔍 Checking Pro status...');

      final pro = await ProService().checkProStatus(widget.userId);

      if (!mounted) return;

      setState(() {
        _isPro = pro;
      });

      crux.logger.i('✅ Pro status: $_isPro');
    } catch (e) {
      crux.logger.w(
        '⚠️ Pro status check failed - assuming free',
        error: e,
      );

      if (mounted) {
        setState(() {
          _isPro = false;
        });
      }
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
        '✅ Preferences loaded: mic=$_micOn cam=$_camOn',
      );
    } catch (e) {
      crux.logger.w(
        '⚠️ Could not load preferences',
        error: e,
      );
    }
  }

  // ===========================================================================
  // PRESENCE
  // ===========================================================================

  Future<void> _registerPresence() async {
    try {
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

      crux.logger.i('✅ Presence registered');
    } catch (e, st) {
      crux.logger.e(
        '❌ Presence registration failed',
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
    if (_isConnecting) return;

    _isConnecting = true;

    try {
      crux.logger.i(
        '🔌 Connecting to LiveKit room ${widget.meetingId}...',
      );

      if (!AppConfig.isLiveKitConfigured) {
        throw Exception(
          'LiveKit is not configured. '
          'Check LIVEKIT_WSS_URL and LIVEKIT_TOKEN_SERVER_URL.',
        );
      }

      // -----------------------------------------------------------------------
      // TOKEN
      // -----------------------------------------------------------------------

      final token = await LiveKitService.instance.fetchToken(
        room: widget.meetingId,
        identity: widget.userId,
        name: widget.userName,
        isHost: widget.isHost,
      );

      if (token == null || token.isEmpty) {
        throw Exception(
          'Unable to obtain LiveKit participant token.',
        );
      }

      // -----------------------------------------------------------------------
      // CLEAN PREVIOUS ROOM
      // -----------------------------------------------------------------------

      await _disposeRoom();

      // -----------------------------------------------------------------------
      // CREATE ROOM
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
      // ORGANIZER
      // -----------------------------------------------------------------------

      try {
        final doc = await _db
            .collection(AppConfig.meetingsCollection)
            .doc(widget.meetingId)
            .get();

        if (doc.exists) {
          final data = doc.data();

          if (data != null) {
            _organizerId = data['organizerId']?.toString();
          }
        }
      } catch (e) {
        crux.logger.w(
          '⚠️ Could not load organizer ID',
          error: e,
        );
      }

      // -----------------------------------------------------------------------
      // CONNECT
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
                'LiveKit room connection timeout',
              );
            },
          );

      // -----------------------------------------------------------------------
      // LOCAL MEDIA
      // -----------------------------------------------------------------------

      final localParticipant = room.localParticipant;

      if (localParticipant != null) {
        await localParticipant.setCameraEnabled(_camOn);
        await localParticipant.setMicrophoneEnabled(_micOn);
      }

      // -----------------------------------------------------------------------
      // PARTICIPANTS
      // -----------------------------------------------------------------------

      if (mounted) {
        setState(() {
          _remoteParticipants =
              room.remoteParticipants.values.toList();
        });
      }

      _reconnectAttempts = 0;

      crux.logger.i(
        '✅ Connected to LiveKit. '
        'Participants: ${_remoteParticipants.length}',
      );
    } finally {
      _isConnecting = false;
    }
  }

  // ===========================================================================
  // ROOM EVENTS
  // ===========================================================================

  Future<void> _listenRoomEvents() async {
    final room = _room;

    if (room == null) {
      throw Exception('LiveKit room is not initialized.');
    }

    await _roomEventsListener?.dispose();

    final listener = room.createListener();

    _roomEventsListener = listener;

    listener
      ..on<RoomConnectedEvent>((_) {
        crux.logger.i('✅ Room connected');
        _refreshParticipants();
      })
      ..on<RoomDisconnectedEvent>((_) {
        crux.logger.w('⚠️ Room disconnected');

        if (mounted && !_loading) {
          _attemptReconnection();
        }
      })
      ..on<RoomReconnectingEvent>((_) {
        crux.logger.w('🔄 Room reconnecting...');
      })
      ..on<RoomReconnectedEvent>((_) {
        crux.logger.i('✅ Room reconnected');

        _reconnectAttempts = 0;
        _refreshParticipants();
      })
      ..on<ParticipantConnectedEvent>((event) {
        final participant = event.participant;

        crux.logger.i(
          '👤 Participant joined: ${participant.name}',
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
          '👤 Participant left: ${participant.name}',
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
            _activeSpeakerId = event.speakers.first.identity;
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

    crux.logger.i('✅ LiveKit event listeners initialized');
  }

  // ===========================================================================
  // LIVEKIT DATA
  // ===========================================================================

  void _handleDataReceived(DataReceivedEvent event) {
    try {
      final text = utf8.decode(event.data);
      final decoded = jsonDecode(text);

      if (decoded is! Map<String, dynamic>) return;

      final type = decoded['type']?.toString();

      // -----------------------------------------------------------------------
      // MUTE ALL
      // -----------------------------------------------------------------------

      if (type == 'mute_all') {
        final senderIdentity = event.participant?.identity;

        if (senderIdentity == _organizerId) {
          if (_micOn) {
            _toggleMic();

            _announce(
              'The organizer muted your microphone.',
            );
          }
        }
      }

      // -----------------------------------------------------------------------
      // RAISE HAND
      // -----------------------------------------------------------------------

      if (type == 'raise_hand') {
        final identity =
            decoded['identity']?.toString();

        if (identity == null || identity.isEmpty) return;

        if (mounted && !_raisedHands.contains(identity)) {
          setState(() {
            _raisedHands.add(identity);
          });
        }
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
      }

      // -----------------------------------------------------------------------
      // CHAT
      // -----------------------------------------------------------------------

      if (type == 'chat') {
        final sender =
            decoded['sender']?.toString() ?? 'Participant';

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
        '⚠️ Could not parse LiveKit data',
        error: e,
      );
    }
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

        if (_isPro) return;

        final limitSeconds =
            AppConfig.freeMeetingDurationMinutes * 60;

        final warningSeconds = limitSeconds - 300;

        if (_secondsElapsed == warningSeconds &&
            warningSeconds > 0) {
          _announce(
            'Attention. Your free meeting will end in five minutes.',
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
    if (!mounted) return;

    if (_reconnectAttempts >=
        AppConfig.maxReconnectAttempts) {
      _showMeetingError(
        'Lost connection to the meeting. '
        'Please retry or leave the meeting.',
      );
      return;
    }

    _reconnectAttempts++;

    crux.logger.i(
      '🔄 Reconnection attempt '
      '$_reconnectAttempts/${AppConfig.maxReconnectAttempts}',
    );

    await Future.delayed(
      AppConfig.reconnectDelay,
    );

    if (!mounted) return;

    try {
      await _connectToRoom();
      await _listenRoomEvents();

      if (mounted) {
        setState(() {
          _error = null;
          _loading = false;
        });
      }

      _reconnectAttempts = 0;
    } catch (e, st) {
      crux.logger.e(
        '❌ Reconnection failed',
        error: e,
        stackTrace: st,
      );

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
  // MICROPHONE
  // ===========================================================================

  Future<void> _toggleMic() async {
    final participant = _room?.localParticipant;

    if (participant == null) return;

    final newValue = !_micOn;

    try {
      await participant.setMicrophoneEnabled(newValue);

      if (mounted) {
        setState(() {
          _micOn = newValue;
        });
      }
    } catch (e) {
      crux.logger.e(
        '❌ Failed to toggle microphone',
        error: e,
      );
    }
  }

  // ===========================================================================
  // CAMERA
  // ===========================================================================

  Future<void> _toggleCam() async {
    final participant = _room?.localParticipant;

    if (participant == null) return;

    final newValue = !_camOn;

    try {
      await participant.setCameraEnabled(newValue);

      if (mounted) {
        setState(() {
          _camOn = newValue;
        });
      }
    } catch (e) {
      crux.logger.e(
        '❌ Failed to toggle camera',
        error: e,
      );
    }
  }

  // ===========================================================================
  // SCREEN SHARE
  // ===========================================================================

  Future<void> _toggleScreenShare() async {
    final participant = _room?.localParticipant;

    if (participant == null) return;

    try {
      final newValue = !_screenSharing;

      await participant.setScreenShareEnabled(
        newValue,
      );

      if (mounted) {
        setState(() {
          _screenSharing = newValue;
        });
      }
    } catch (e) {
      crux.logger.e(
        '❌ Screen sharing failed',
        error: e,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Screen sharing is not available on this device.',
            ),
          ),
        );
      }
    }
  }

  // ===========================================================================
  // TTS
  // ===========================================================================

  Future<void> _announce(String text) async {
    if (!_voiceAssistant) return;

    try {
      await _tts.setLanguage('en-US');
      await _tts.setPitch(1.0);
      await _tts.speak(text);
    } catch (e) {
      crux.logger.w(
        '⚠️ TTS error',
        error: e,
      );
    }
  }

  // ===========================================================================
  // ERROR
  // ===========================================================================

  void _showMeetingError(String errorMsg) {
    if (!mounted) return;

    String friendlyMsg;

    try {
      final lang =
          context.read<LocaleProvider>().locale.languageCode;

      friendlyMsg =
          _errorHandler.getMeetingErrorMessageL(
        errorMsg,
        lang,
      );
    } catch (_) {
      friendlyMsg = errorMsg;
    }

    setState(() {
      _loading = false;
      _error = friendlyMsg;
    });

    crux.logger.e(
      '🚨 Meeting Error',
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
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text(
            'Time limit reached',
            style: TextStyle(
              color: Colors.white,
            ),
          ),
          content: const Text(
            'Your free meeting time has ended. '
            'Upgrade to CRUX Pro for longer meetings.',
            style: TextStyle(
              color: Colors.white70,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _leave();
              },
              child: const Text('Leave'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();

                try {
                  await ProService().startPayment(
                    userId: widget.userId,
                    userName: widget.userName,
                  );
                } catch (e) {
                  crux.logger.e(
                    'Payment error',
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
  // INVITE
  // ===========================================================================

  String get _joinUrl =>
      AppConfig.webJoinLink(widget.meetingId);

  Future<void> _copyInviteLink() async {
    await Clipboard.setData(
      ClipboardData(text: _joinUrl),
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Meeting link copied.'),
      ),
    );
  }

  // ===========================================================================
  // CHAT
  // ===========================================================================

  Future<void> _sendChatMessage() async {
    final message =
        _chatController.text.trim();

    if (message.isEmpty) return;

    _chatController.clear();

    if (mounted) {
      setState(() {
        _chatMessages.add(
          _ChatMessage(
            sender: widget.userName,
            message: message,
            isMe: true,
          ),
        );
      });
    }

    // Les données LiveKit sont envoyées à tous les participants.
    final participant =
        _room?.localParticipant;

    if (participant == null) return;

    try {
      final data = utf8.encode(
        jsonEncode({
          'type': 'chat',
          'sender': widget.userName,
          'senderId': widget.userId,
          'message': message,
        }),
      );

      await participant.publishData(
        data,
        reliable: true,
      );
    } catch (e) {
      crux.logger.e(
        '❌ Failed to send chat message',
        error: e,
      );
    }
  }

  // ===========================================================================
  // RAISE HAND
  // ===========================================================================

  Future<void> _toggleRaiseHand() async {
    final participant =
        _room?.localParticipant;

    if (participant == null) return;

    final isRaised =
        _raisedHands.contains(widget.userId);

    try {
      final data = utf8.encode(
        jsonEncode({
          'type':
              isRaised ? 'lower_hand' : 'raise_hand',
          'identity': widget.userId,
        }),
      );

      await participant.publishData(
        data,
        reliable: true,
      );

      if (mounted) {
        setState(() {
          if (isRaised) {
            _raisedHands.remove(widget.userId);
          } else {
            _raisedHands.add(widget.userId);
          }
        });
      }
    } catch (e) {
      crux.logger.e(
        '❌ Raise hand error',
        error: e,
      );
    }
  }

  // ===========================================================================
  // NOTES
  // ===========================================================================

  void _saveNotes() {
    FocusScope.of(context).unfocus();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Notes saved locally.'),
      ),
    );
  }

  // ===========================================================================
  // LEAVE
  // ===========================================================================

  Future<void> _confirmLeave() async {
    final leave =
        await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
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
                Navigator.of(dialogContext)
                    .pop(false);
              },
              child: const Text('Stay'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext)
                    .pop(true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    AppColors.error,
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
    crux.logger.i(
      '👋 Leaving meeting...',
    );

    try {
      await MeetingService()
          .saveMeetingHistoryForUser(
        meetingId: widget.meetingId,
        userId: widget.userId,
        title: widget.meetingName,
        durationSeconds: _secondsElapsed,
        endMeeting: widget.isHost,
      );
    } catch (e) {
      crux.logger.w(
        'Could not save meeting history',
        error: e,
      );
    }

    try {
      await MeetingService()
          .removePresence(
        widget.meetingId,
        widget.userId,
      );
    } catch (e) {
      crux.logger.w(
        'Could not remove presence',
        error: e,
      );
    }

    await _disposeRoom();

    if (!mounted) return;

    Navigator.of(context).pop();
  }

  // ===========================================================================
  // ROOM DISPOSE
  // ===========================================================================

  Future<void> _disposeRoom() async {
    try {
      await _roomEventsListener?.dispose();
    } catch (_) {}

    _roomEventsListener = null;

    final room = _room;
    _room = null;

    if (room != null) {
      try {
        await room.disconnect();
      } catch (e) {
        crux.logger.w(
          'Room disconnect warning',
          error: e,
        );
      }

      try {
        room.dispose();
      } catch (e) {
        crux.logger.w(
          'Room dispose warning',
          error: e,
        );
      }
    }
  }

  // ===========================================================================
  // DISPOSE
  // ===========================================================================

  @override
  void dispose() {
    crux.logger.i(
      '🧹 Cleaning up conference resources...',
    );

    _callTimer?.cancel();

    _presenceSubscription?.cancel();

    _tts.stop();
    _speech.stop();

    _noteController.dispose();
    _chatController.dispose();

    _roomEventsListener?.dispose();

    final room = _room;

    if (room != null) {
      room.disconnect().then((_) {
        try {
          room.dispose();
        } catch (_) {}
      });
    }

    _room = null;
    _roomEventsListener = null;

    WidgetsBinding.instance.removeObserver(this);

    crux.logger.i(
      '✅ Conference resources disposed',
    );

    super.dispose();
  }

  // ===========================================================================
  // APP LIFECYCLE
  // ===========================================================================

  @override
  void didChangeAppLifecycleState(
    AppLifecycleState state,
  ) {
    if (state == AppLifecycleState.resumed) {
      if (_room != null &&
          !_loading &&
          _error == null) {
        _refreshParticipants();
      }
    }
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
              const SizedBox(height: 20),
              Text(
                _error ?? 'Unknown error',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment:
                    MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: const Text('Back'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _error = null;
                        _loading = true;
                      });

                      _attemptReconnection();
                    },
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
  // VIDEO GRID
  // ===========================================================================

  Widget _buildVideoGrid() {
    final local = _room?.localParticipant;

    final List<Participant> participants = [
      if (local != null) local,
      ..._remoteParticipants,
    ];

    final visible = participants
        .take(
          AppConfig.livekitVisibleTileCap,
        )
        .toList();

    if (visible.isEmpty) {
      return Center(
        child: Text(
          'Waiting for participants...',
          style: GoogleFonts.poppins(
            color: Colors.white54,
          ),
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
        _activeSpeakerId ==
        participant.identity;

    VideoTrack? videoTrack;
    bool isScreenShare = false;
    bool hasVideo = false;

    for (final publication
        in participant.videoTrackPublications) {
      final track = publication.track;

      if (track is VideoTrack &&
          !publication.muted) {
        videoTrack = track;
        isScreenShare =
            publication.source ==
            TrackSource.screenShareVideo;
        hasVideo = true;
        break;
      }
    }

    final displayName =
        participant.name.isNotEmpty
            ? participant.name
            : 'Guest';

    return AnimatedContainer(
      duration:
          const Duration(milliseconds: 300),
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
                      AppColors.primary
                          .withValues(alpha: 0.3),
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

            // NAME
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
                  color: Colors.black54,
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

            // RAISED HAND
            if (_raisedHands
                .contains(participant.identity))
              const Positioned(
                top: 12,
                right: 12,
                child: Icon(
                  Icons.back_hand,
                  color: Colors.orange,
                  size: 20,
                ),
              ),

            // SCREEN SHARE
            if (isScreenShare)
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red
                        .withValues(alpha: 0.8),
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
      decoration:
          const BoxDecoration(
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
            fontWeight:
                FontWeight.bold,
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

              const SizedBox(width: 8),

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

              IconButton(
                tooltip:
                    'Voice assistant',
                icon: Icon(
                  _voiceAssistant
                      ? Icons.volume_up
                      : Icons.volume_off,
                  color: Colors.white70,
                  size: 20,
                ),
                onPressed: () {
                  setState(() {
                    _voiceAssistant =
                        !_voiceAssistant;
                  });
                },
              ),

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
                    color: AppColors.error
                        .withValues(
                      alpha: 0.2,
                    ),
                    borderRadius:
                        BorderRadius.circular(
                      12,
                    ),
                    border: Border.all(
                      color: AppColors.error
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
            _controlButton(
              icon: _micOn
                  ? Icons.mic
                  : Icons.mic_off,
              color: _micOn
                  ? Colors.white70
                  : AppColors.error,
              onPressed: _toggleMic,
            ),

            _controlButton(
              icon: _camOn
                  ? Icons.videocam
                  : Icons.videocam_off,
              color: _camOn
                  ? Colors.white70
                  : AppColors.error,
              onPressed: _toggleCam,
            ),

            _controlButton(
              icon: _screenSharing
                  ? Icons.stop_screen_share
                  : Icons.screen_share,
              color: _screenSharing
                  ? AppColors.primary
                  : Colors.white70,
              onPressed:
                  _toggleScreenShare,
            ),

            _controlButton(
              icon:
                  Icons.chat_bubble_outline,
              onPressed: () {
                setState(() {
                  _showChat = true;
                });
              },
            ),

            _controlButton(
              icon:
                  Icons.note_alt_outlined,
              onPressed: () {
                setState(() {
                  _showNotes = true;
                });
              },
            ),

            _controlButton(
              icon:
                  Icons.people_outline,
              onPressed: () {
                setState(() {
                  _showParticipants = true;
                });
              },
            ),

            _controlButton(
              icon: _raisedHands
                      .contains(widget.userId)
                  ? Icons.back_hand
                  : Icons.pan_tool_outlined,
              color: _raisedHands
                      .contains(widget.userId)
                  ? Colors.orange
                  : Colors.white70,
              onPressed:
                  _toggleRaiseHand,
            ),
          ],
        ),
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required VoidCallback onPressed,
    Color color = Colors.white70,
  }) {
    return IconButton(
      icon: Icon(
        icon,
        color: color,
        size: 25,
      ),
      onPressed: onPressed,
    );
  }

  // ===========================================================================
  // CHAT PANEL
  // ===========================================================================

  Widget _buildChatPanel() {
    return Positioned(
      top: 70,
      bottom: 100,
      right: 12,
      width: 340,
      child: _panel(
        title: 'Chat',
        icon: Icons.chat_bubble_outline,
        onClose: () {
          setState(() {
            _showChat = false;
          });
        },
        child: Column(
          children: [
            Expanded(
              child: _chatMessages.isEmpty
                  ? Center(
                      child: Text(
                        'No messages yet',
                        style:
                            GoogleFonts.poppins(
                          color:
                              Colors.white38,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding:
                          const EdgeInsets.all(
                        12,
                      ),
                      itemCount:
                          _chatMessages.length,
                      itemBuilder:
                          (_, index) {
                        final message =
                            _chatMessages[
                                index];

                        return Align(
                          alignment:
                              message.isMe
                                  ? Alignment
                                      .centerRight
                                  : Alignment
                                      .centerLeft,
                          child: Container(
                            margin:
                                const EdgeInsets
                                    .only(
                              bottom: 8,
                            ),
                            padding:
                                const EdgeInsets
                                    .symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration:
                                BoxDecoration(
                              color: message
                                      .isMe
                                  ? AppColors
                                      .primary
                                  : Colors.white10,
                              borderRadius:
                                  BorderRadius
                                      .circular(
                                14,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment
                                      .start,
                              children: [
                                Text(
                                  message
                                      .sender,
                                  style:
                                      const TextStyle(
                                    color: Colors
                                        .white54,
                                    fontSize: 9,
                                  ),
                                ),
                                const SizedBox(
                                  height: 3,
                                ),
                                Text(
                                  message
                                      .message,
                                  style:
                                      const TextStyle(
                                    color: Colors
                                        .white,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Row(
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
                        const InputDecoration(
                      hintText:
                          'Write a message...',
                      hintStyle:
                          TextStyle(
                        color:
                            Colors.white38,
                      ),
                      border:
                          InputBorder.none,
                    ),
                    onSubmitted: (_) =>
                        _sendChatMessage(),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.send,
                    color:
                        AppColors.primary,
                  ),
                  onPressed:
                      _sendChatMessage,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // PARTICIPANTS PANEL
  // ===========================================================================

  Widget _buildParticipantsPanel() {
    final local =
        _room?.localParticipant;

    final count =
        1 + _remoteParticipants.length;

    return Positioned(
      top: 70,
      bottom: 100,
      right: 12,
      width: 340,
      child: _panel(
        title: 'Participants ($count)',
        icon: Icons.people_outline,
        onClose: () {
          setState(() {
            _showParticipants = false;
          });
        },
        child: ListView(
          children: [
            if (local != null)
              _participantListTile(
                local,
                isLocal: true,
              ),
            ..._remoteParticipants.map(
              (participant) =>
                  _participantListTile(
                participant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _participantListTile(
    Participant participant, {
    bool isLocal = false,
  }) {
    final name =
        participant.name.isNotEmpty
            ? participant.name
            : 'Guest';

    return ListTile(
      leading: _buildAvatar(name),
      title: Text(
        name,
        style: const TextStyle(
          color: Colors.white,
        ),
      ),
      subtitle: Text(
        isLocal
            ? 'You'
            : participant.identity,
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 10,
        ),
      ),
      trailing:
          _raisedHands.contains(
        participant.identity,
      )
              ? const Icon(
                  Icons.back_hand,
                  color: Colors.orange,
                  size: 20,
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
      bottom: 100,
      right: 12,
      width: 340,
      child: _panel(
        title: 'Meeting notes',
        icon: Icons.note_alt_outlined,
        onClose: () {
          setState(() {
            _showNotes = false;
          });
        },
        child: Column(
          children: [
            Expanded(
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
                  fontSize: 13,
                ),
                decoration:
                    const InputDecoration(
                  hintText:
                      'Write your notes here...',
                  hintStyle:
                      TextStyle(
                    color: Colors.white38,
                  ),
                  border:
                      InputBorder.none,
                ),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saveNotes,
                icon: const Icon(
                  Icons.save_outlined,
                ),
                label:
                    const Text('Save notes'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // GENERIC PANEL
  // ===========================================================================

  Widget _panel({
    required String title,
    required IconData icon,
    required VoidCallback onClose,
    required Widget child,
  }) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding:
            const EdgeInsets.all(16),
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
              blurRadius: 30,
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  color: Colors.white70,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style:
                        GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight:
                          FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close,
                    color:
                        Colors.white54,
                  ),
                  onPressed: onClose,
                ),
              ],
            ),
            const Divider(
              color: Colors.white10,
            ),
            Expanded(
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// CHAT MODEL
// =============================================================================

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
