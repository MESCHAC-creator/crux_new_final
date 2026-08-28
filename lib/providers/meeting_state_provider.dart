import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'meeting/entities/speaker_state.dart';
import 'meeting/entities/live_feed_config.dart';
import 'meeting/entities/participant_display.dart';
import 'meeting/conference_layout_controller.dart';

class MeetingStateProvider extends ChangeNotifier {
  final ConferenceLayoutController _layoutController;
  
  // Local media state
  bool _isMicEnabled = true;
  bool _isCameraEnabled = true;
  bool _isScreenSharing = false;
  bool _isHandRaised = false;
  
  // Network stats
  double _fps = 60.0;
  int _latency = 0;
  double _bandwidth = 0.0;
  double _jitter = 0.0;
  
  // Meeting info
  String? _meetingId;
  String? _meetingName;
  Room? _room;
  
  MeetingStateProvider() : _layoutController = ConferenceLayoutController() {
    _layoutController.initialize();
  }

  // Getters
  ConferenceLayoutController get layoutController => _layoutController;
  SpeakerState get speakerState => _layoutController.speakerState;
  LiveFeedConfig get feedConfig => _layoutController.feedConfig;
  SpeakerQueue get speakerQueue => _layoutController.speakerQueue;
  Map<String, ParticipantDisplayState> get participantStates => 
    _layoutController.participantStates;
    
  bool get isMicEnabled => _isMicEnabled;
  bool get isCameraEnabled => _isCameraEnabled;
  bool get isScreenSharing => _isScreenSharing;
  bool get isHandRaised => _isHandRaised;
  
  double get fps => _fps;
  int get latency => _latency;
  double get bandwidth => _bandwidth;
  double get jitter => _jitter;
  
  String? get meetingId => _meetingId;
  String? get meetingName => _meetingName;
  Room? get room => _room;
  
  int get participantCount => _layoutController.participantCount;
  List<ParticipantDisplayState> get activeParticipants => 
    _layoutController.activeParticipants;

  // Initialize meeting
  void initializeMeeting({
    required String meetingId,
    required String meetingName,
    Room? room,
  }) {
    _meetingId = meetingId;
    _meetingName = meetingName;
    _room = room;
    notifyListeners();
  }

  // Media controls
  void toggleMic() {
    _isMicEnabled = !_isMicEnabled;
    notifyListeners();
  }

  void setMicEnabled(bool enabled) {
    _isMicEnabled = enabled;
    notifyListeners();
  }

  void toggleCamera() {
    _isCameraEnabled = !_isCameraEnabled;
    notifyListeners();
  }

  void setCameraEnabled(bool enabled) {
    _isCameraEnabled = enabled;
    notifyListeners();
  }

  void toggleScreenShare() {
    _isScreenSharing = !_isScreenSharing;
    if (_isScreenSharing) {
      _layoutController.setSpeakerMode(SpeakerMode.screenshare);
    } else {
      _layoutController.autoAdjustLayout();
    }
    notifyListeners();
  }

  void toggleHandRaise() {
    _isHandRaised = !_isHandRaised;
    if (_room != null) {
      final localParticipant = _room!.localParticipant;
      if (localParticipant != null) {
        _layoutController.handleHandRaise(localParticipant.sid, _isHandRaised);
      }
    }
    notifyListeners();
  }

  // Layout controls
  void setSpeakerMode(SpeakerMode mode) {
    _layoutController.setSpeakerMode(mode);
    notifyListeners();
  }

  void pinParticipant(String participantId) {
    _layoutController.pinParticipant(participantId);
    notifyListeners();
  }

  void unpinParticipant() {
    _layoutController.unpinParticipant();
    notifyListeners();
  }

  void setFeedConfig(LiveFeedConfig config) {
    _layoutController.setFeedConfig(config);
    notifyListeners();
  }

  // Participant management
  void updateParticipant(Participant participant) {
    _layoutController.updateParticipant(participant);
  }

  void removeParticipant(String participantId) {
    _layoutController.removeParticipant(participantId);
  }

  void updateAudioLevel(String participantId, double level) {
    _layoutController.updateAudioLevel(participantId, level);
  }

  void updateParticipantMode(String participantId, ParticipantDisplayMode mode) {
    _layoutController.updateParticipantMode(participantId, mode);
  }

  // Network stats
  void updateNetworkStats({
    double? fps,
    int? latency,
    double? bandwidth,
    double? jitter,
  }) {
    if (fps != null) _fps = fps;
    if (latency != null) _latency = latency;
    if (bandwidth != null) _bandwidth = bandwidth;
    if (jitter != null) _jitter = jitter;
    notifyListeners();
  }

  // Auto layout adjustment
  void autoAdjustLayout() {
    _layoutController.autoAdjustLayout();
    notifyListeners();
  }

  // Cleanup
  void dispose() {
    _layoutController.dispose();
    super.dispose();
  }
}