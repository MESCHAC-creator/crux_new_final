import 'package:livekit_client/livekit_client.dart';

enum ParticipantDisplayMode {
  speaker,
  tile,
  hidden,
  minimized,
}

class ParticipantDisplayState {
  final Participant participant;
  final ParticipantDisplayMode mode;
  final bool isAudioActive;
  final bool isVideoEnabled;
  final bool isScreenSharing;
  final bool hasHandRaised;
  final double audioLevel;
  final DateTime? lastActiveTime;

  ParticipantDisplayState({
    required this.participant,
    this.mode = ParticipantDisplayMode.tile,
    this.isAudioActive = false,
    this.isVideoEnabled = true,
    this.isScreenSharing = false,
    this.hasHandRaised = false,
    this.audioLevel = 0.0,
    this.lastActiveTime,
  });

  ParticipantDisplayState copyWith({
    Participant? participant,
    ParticipantDisplayMode? mode,
    bool? isAudioActive,
    bool? isVideoEnabled,
    bool? isScreenSharing,
    bool? hasHandRaised,
    double? audioLevel,
    DateTime? lastActiveTime,
  }) {
    return ParticipantDisplayState(
      participant: participant ?? this.participant,
      mode: mode ?? this.mode,
      isAudioActive: isAudioActive ?? this.isAudioActive,
      isVideoEnabled: isVideoEnabled ?? this.isVideoEnabled,
      isScreenSharing: isScreenSharing ?? this.isScreenSharing,
      hasHandRaised: hasHandRaised ?? this.hasHandRaised,
      audioLevel: audioLevel ?? this.audioLevel,
      lastActiveTime: lastActiveTime ?? this.lastActiveTime,
    );
  }

  String get participantId => participant.sid;
  String get displayName =>
      participant.name.isEmpty ? 'Anonymous' : participant.name;
  String get initials {
    final name = displayName;
    if (name.isEmpty) return '?';
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  bool get isVisible => mode != ParticipantDisplayMode.hidden;
  bool get isSpeaking => audioLevel > 0.3;
  bool get isInactive {
    if (lastActiveTime == null) return false;
    return DateTime.now().difference(lastActiveTime!) > const Duration(minutes: 5);
  }

  Duration get activeDuration {
    if (lastActiveTime == null) return Duration.zero;
    return DateTime.now().difference(lastActiveTime!);
  }
}