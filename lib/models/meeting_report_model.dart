import 'package:cloud_firestore/cloud_firestore.dart';

class MeetingReportModel {
  final String meetingId;
  final String title;
  final String hostName;
  final String hostId;
  final int durationSeconds;
  final List<String> participantNames;
  final int messageCount;
  final DateTime endedAt;

  const MeetingReportModel({
    required this.meetingId,
    required this.title,
    required this.hostName,
    required this.hostId,
    required this.durationSeconds,
    required this.participantNames,
    required this.messageCount,
    required this.endedAt,
  });

  Map<String, dynamic> toJson() => {
        'meetingId': meetingId,
        'title': title,
        'hostName': hostName,
        'hostId': hostId,
        'durationSeconds': durationSeconds,
        'participantNames': participantNames,
        'messageCount': messageCount,
        'endedAt': Timestamp.fromDate(endedAt),
      };

  factory MeetingReportModel.fromJson(Map<String, dynamic> json) =>
      MeetingReportModel(
        meetingId: json['meetingId'] ?? '',
        title: json['title'] ?? 'Réunion',
        hostName: json['hostName'] ?? '',
        hostId: json['hostId'] ?? '',
        durationSeconds: json['durationSeconds'] ?? 0,
        participantNames: List<String>.from(json['participantNames'] ?? []),
        messageCount: json['messageCount'] ?? 0,
        endedAt: (json['endedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );

  String get formattedDuration {
    final h = durationSeconds ~/ 3600;
    final m = (durationSeconds % 3600) ~/ 60;
    final s = durationSeconds % 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}min';
    if (m > 0) return '${m}min ${s.toString().padLeft(2, '0')}s';
    return '${s}s';
  }

  String get shareText {
    final buf = StringBuffer();
    buf.writeln('📊 RAPPORT DE RÉUNION CRUX');
    buf.writeln('════════════════════════');
    buf.writeln('📌 Titre : $title');
    buf.writeln('👤 Animateur : $hostName');
    buf.writeln('⏱️ Durée : $formattedDuration');
    buf.writeln('👥 Participants : ${participantNames.length}');
    buf.writeln('💬 Messages : $messageCount');
    buf.writeln('📅 Date : ${endedAt.day}/${endedAt.month}/${endedAt.year} ${endedAt.hour}:${endedAt.minute.toString().padLeft(2, '0')}');
    if (participantNames.isNotEmpty) {
      buf.writeln('');
      buf.writeln('Participants :');
      for (final n in participantNames) {
        buf.writeln('  • $n');
      }
    }
    buf.writeln('');
    buf.writeln('Généré par CRUX Premium Video Conference');
    return buf.toString();
  }
}
