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
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'organizer': organizer,
      'organizerId': organizerId,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      'participants': participants,
      'channelName': channelName,
      'status': status.toString().split('.').last,
      'createdAt': createdAt.toIso8601String(),
      'isRecording': isRecording,
      'isLocked': isLocked,
      'recordingUrl': recordingUrl,
    };
  }

  factory MeetingModel.fromJson(Map<String, dynamic> json) {
    return MeetingModel(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      organizer: json['organizer'] ?? '',
      organizerId: json['organizerId'] ?? '',
      startTime: DateTime.parse(json['startTime'] ?? DateTime.now().toIso8601String()),
      endTime: DateTime.parse(json['endTime'] ?? DateTime.now().toIso8601String()),
      participants: List<String>.from(json['participants'] ?? []),
      channelName: json['channelName'] ?? '',
      status: _statusFromString(json['status'] ?? 'scheduled'),
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      isRecording: json['isRecording'] ?? false,
      isLocked: json['isLocked'] ?? false,
      recordingUrl: json['recordingUrl'],
    );
  }

  static MeetingStatus _statusFromString(String status) {
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
    );
  }

  @override
  String toString() => 'MeetingModel(id: $id, title: $title, status: $status)';
}

enum MeetingStatus {
  scheduled,
  ongoing,
  ended,
}