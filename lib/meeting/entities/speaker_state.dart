import 'package:livekit_client/livekit_client.dart';

enum SpeakerMode {
  single,
  dual,
  screenshare,
  gallery,
}

class SpeakerState {
  final Participant? currentSpeaker;
  final Participant? secondarySpeaker;
  final DateTime? speakerTimestamp;
  final SpeakerMode mode;
  final bool isPinned;
  final String? pinnedParticipantId;

  const SpeakerState({
    this.currentSpeaker,
    this.secondarySpeaker,
    this.speakerTimestamp,
    this.mode = SpeakerMode.single,
    this.isPinned = false,
    this.pinnedParticipantId,
  });

  SpeakerState copyWith({
    Participant? currentSpeaker,
    Participant? secondarySpeaker,
    DateTime? speakerTimestamp,
    SpeakerMode? mode,
    bool? isPinned,
    String? pinnedParticipantId,
  }) {
    return SpeakerState(
      currentSpeaker: currentSpeaker ?? this.currentSpeaker,
      secondarySpeaker: secondarySpeaker ?? this.secondarySpeaker,
      speakerTimestamp: speakerTimestamp ?? this.speakerTimestamp,
      mode: mode ?? this.mode,
      isPinned: isPinned ?? this.isPinned,
      pinnedParticipantId: pinnedParticipantId ?? this.pinnedParticipantId,
    );
  }

  bool get hasSpeaker => currentSpeaker != null;
  bool get isDualSpeaker => mode == SpeakerMode.dual && secondarySpeaker != null;
  bool get isScreenshareMode => mode == SpeakerMode.screenshare;
  
  Duration get speakerAge {
    if (speakerTimestamp == null) return Duration.zero;
    return DateTime.now().difference(speakerTimestamp!);
  }
}

class SpeakerQueue {
  final List<Participant> queue;
  final int maxSize;

  SpeakerQueue({this.maxSize = 5}) : queue = [];

  void add(Participant participant) {
    if (queue.contains(participant)) {
      queue.remove(participant);
    }
    queue.insert(0, participant);
    if (queue.length > maxSize) {
      queue.removeLast();
    }
  }

  void remove(Participant participant) {
    queue.remove(participant);
  }

  Participant? get nextSpeaker {
    if (queue.isEmpty) return null;
    return queue.first;
  }

  List<Participant> get recentSpeakers => List.unmodifiable(queue);
}