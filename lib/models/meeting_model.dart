// lib/models/meeting_model.dart
//
// CORRECTIF PLANIFICATION
// -----------------------
// Avant : `startTime` était écrit en String ISO **locale** (sans offset) et
// relu avec `DateTime.parse()`. Deux conséquences :
//   1. tout document écrit en Timestamp (par le nouveau ScheduleService ou par
//      la console Firebase) faisait planter `fromJson` ;
//   2. `orderBy('startTime')` triait des chaînes, donc deux utilisateurs dans
//      des fuseaux différents ne voyaient pas le même ordre.
//
// Maintenant : écriture en Timestamp (instant absolu), lecture tolérante via
// `flexDate` (Timestamp | String ISO | int ms). Aucune migration nécessaire,
// les anciens documents restent lisibles.

import '../utils/date_flex.dart';

enum MeetingStatus { scheduled, ongoing, ended }

class MeetingModel {
  final String id;
  final String title;
  final String description;
  final String organizer;
  final String organizerId;
  final DateTime startTime;
  final DateTime endTime;
  final List<String> participants;
  final String channelName;
  final MeetingStatus status;
  final DateTime createdAt;
  final bool isRecording;
  final bool isLocked;
  final String? recordingUrl;
  final String? passcode; // PIN 4-6 chiffres optionnel défini par l'hôte
  final bool isLargeConference; // true → LiveKit SFU (1000+ participants)

  /// Co-hôtes (le service écrivait déjà ce champ sans qu'il soit modélisé).
  final List<String> coHosts;

  MeetingModel({
    required this.id,
    required this.title,
    required this.description,
    required this.organizer,
    required this.organizerId,
    required this.startTime,
    required this.endTime,
    required this.participants,
    required this.channelName,
    required this.status,
    required this.createdAt,
    this.isRecording = false,
    this.isLocked = false,
    this.recordingUrl,
    this.passcode,
    this.isLargeConference = false,
    this.coHosts = const [],
  });

  /// Durée planifiée de la réunion.
  Duration get duration => endTime.difference(startTime);

  /// True si la réunion démarre dans moins de 15 minutes (ou a déjà démarré
  /// mais n'est pas terminée) → utilisé pour activer le bouton « Rejoindre ».
  bool get isJoinable {
    if (status == MeetingStatus.ended) return false;
    if (status == MeetingStatus.ongoing) return true;
    final now = DateTime.now();
    return startTime.difference(now) <= const Duration(minutes: 15) &&
        now.isBefore(endTime.add(const Duration(hours: 1)));
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'organizer': organizer,
      'organizerId': organizerId,
      // ⬇️ Timestamp et non String : tri et fuseaux corrects.
      'startTime': flexStamp(startTime),
      'endTime': flexStamp(endTime),
      'participants': participants,
      'channelName': channelName,
      'status': status.name,
      'createdAt': flexStamp(createdAt),
      'isRecording': isRecording,
      'isLocked': isLocked,
      'recordingUrl': recordingUrl,
      if (passcode != null && passcode!.isNotEmpty) 'passcode': passcode,
      'isLargeConference': isLargeConference,
      'coHosts': coHosts,
    };
  }

  factory MeetingModel.fromJson(Map<String, dynamic> json) {
    final start = flexDate(json['startTime']);
    return MeetingModel(
      id: (json['id'] ?? '') as String,
      title: (json['title'] ?? '') as String,
      description: (json['description'] ?? '') as String,
      organizer: (json['organizer'] ?? '') as String,
      organizerId: (json['organizerId'] ?? '') as String,
      startTime: start,
      endTime: flexDate(
        json['endTime'],
        fallback: start.add(const Duration(hours: 1)),
      ),
      participants: List<String>.from(json['participants'] ?? const []),
      channelName: (json['channelName'] ?? '') as String,
      status: statusFromString(json['status'] as String?),
      createdAt: flexDate(json['createdAt'], fallback: start),
      isRecording: json['isRecording'] as bool? ?? false,
      isLocked: json['isLocked'] as bool? ?? false,
      recordingUrl: json['recordingUrl'] as String?,
      passcode: json['passcode'] as String?,
      isLargeConference: json['isLargeConference'] as bool? ?? false,
      coHosts: List<String>.from(json['coHosts'] ?? const []),
    );
  }

  /// Construit depuis un DocumentSnapshot en forçant l'id du document
  /// (certains anciens documents n'ont pas de champ `id`).
  factory MeetingModel.fromDoc(String docId, Map<String, dynamic> data) =>
      MeetingModel.fromJson({...data, 'id': data['id'] ?? docId});

  static MeetingStatus statusFromString(String? status) {
    switch (status) {
      case 'ongoing':
        return MeetingStatus.ongoing;
      case 'ended':
        return MeetingStatus.ended;
      default:
        return MeetingStatus.scheduled;
    }
  }

  MeetingModel copyWith({
    String? id,
    String? title,
    String? description,
    String? organizer,
    String? organizerId,
    DateTime? startTime,
    DateTime? endTime,
    List<String>? participants,
    String? channelName,
    MeetingStatus? status,
    DateTime? createdAt,
    bool? isRecording,
    bool? isLocked,
    String? recordingUrl,
    String? passcode,
    bool? isLargeConference,
    List<String>? coHosts,
  }) {
    return MeetingModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      organizer: organizer ?? this.organizer,
      organizerId: organizerId ?? this.organizerId,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      participants: participants ?? this.participants,
      channelName: channelName ?? this.channelName,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      isRecording: isRecording ?? this.isRecording,
      isLocked: isLocked ?? this.isLocked,
      recordingUrl: recordingUrl ?? this.recordingUrl,
      passcode: passcode ?? this.passcode,
      isLargeConference: isLargeConference ?? this.isLargeConference,
      coHosts: coHosts ?? this.coHosts,
    );
  }

  @override
  String toString() => 'MeetingModel(id: $id, title: $title, status: $status)';
}
