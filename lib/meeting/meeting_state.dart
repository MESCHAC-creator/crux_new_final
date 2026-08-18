import 'package:livekit_client/livekit_client.dart';

/// UI Model pour un participant.
class ParticipantUi {
  final String sid;
  final String name;
  final bool isSpeaking;
  final bool isMuted;
  final VideoTrack? videoTrack;
  final bool isLocal;

  const ParticipantUi({
    required this.sid,
    required this.name,
    this.isSpeaking = false,
    this.isMuted = true,
    this.videoTrack,
    this.isLocal = false,
  });
}

/// Santé de l'appel.
class CallHealth {
  final int rttMs;
  final int jitterMs;
  final double packetLossPercent;

  const CallHealth({
    this.rttMs = 0,
    this.jitterMs = 0,
    this.packetLossPercent = 0.0,
  });

  CallHealthLevel get level {
    if (packetLossPercent > 5 || rttMs > 300) return CallHealthLevel.poor;
    if (packetLossPercent > 2 || rttMs > 150) return CallHealthLevel.fair;
    return CallHealthLevel.good;
  }
}

enum CallHealthLevel { good, fair, poor }

/// État global de la réunion.
class MeetingUiState {
  final List<ParticipantUi> participants;
  final ParticipantUi? screenShare;
  final int elapsedSeconds;
  final bool micEnabled;
  final bool cameraEnabled;
  final bool handRaised;
  final String roomUrl;
  final CallHealth health;

  const MeetingUiState({
    this.participants = const [],
    this.screenShare,
    this.elapsedSeconds = 0,
    this.micEnabled = true,
    this.cameraEnabled = true,
    this.handRaised = false,
    this.roomUrl = '',
    this.health = const CallHealth(),
  });
}

/// Message de chat.
class ChatMessage {
  final String id;
  final String senderSid;
  final String senderName;
  final String body;
  final int timestampMs;
  final String? recipientSid; // null = groupe
  final bool fromMe;

  const ChatMessage({
    required this.id,
    required this.senderSid,
    required this.senderName,
    required this.body,
    required this.timestampMs,
    this.recipientSid,
    this.fromMe = false,
  });

  bool get isPrivate => recipientSid != null;
}