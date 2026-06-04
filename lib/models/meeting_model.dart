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
  final String? password; // optional PIN set by host
  final List<String> coHosts;
  final int muteAllCount;
  final String? offeringLink; // Lien de paiement pour offrandes (mode Église)
  final bool isScheduled; // true = réunion future programmée
  final DateTime? scheduledAt; // date/heure planifiée
  final bool waitingRoom; // salle d'attente activée
  final int? maxParticipants; // limite de participants (null = illimité)
  final String? meetingMode; // standard, business, church, live

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
    this.password,
    this.coHosts = const [],
    this.muteAllCount = 0,
    this.offeringLink,
    this.isScheduled = false,
    this.scheduledAt,
    this.waitingRoom = false,
    this.maxParticipants,
    this.meetingMode,
  });

  Map<String, dynamic> toJson() => {
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
        if (password != null) 'password': password,
        'coHosts': coHosts,
        'muteAllCount': muteAllCount,
        if (offeringLink != null) 'offeringLink': offeringLink,
        'isScheduled': isScheduled,
        if (scheduledAt != null) 'scheduledAt': scheduledAt!.toIso8601String(),
        'waitingRoom': waitingRoom,
        if (maxParticipants != null) 'maxParticipants': maxParticipants,
        if (meetingMode != null) 'meetingMode': meetingMode,
      };

  factory MeetingModel.fromJson(Map<String, dynamic> json) => MeetingModel(
        id: json['id'] ?? '',
        title: json['title'] ?? '',
        description: json['description'] ?? '',
        organizer: json['organizer'] ?? '',
        organizerId: json['organizerId'] ?? '',
        startTime: DateTime.parse(
            json['startTime'] ?? DateTime.now().toIso8601String()),
        endTime:
            DateTime.parse(json['endTime'] ?? DateTime.now().toIso8601String()),
        participants: List<String>.from(json['participants'] ?? []),
        channelName: json['channelName'] ?? '',
        status: _statusFromString(json['status'] ?? 'scheduled'),
        createdAt: DateTime.parse(
            json['createdAt'] ?? DateTime.now().toIso8601String()),
        isRecording: json['isRecording'] ?? false,
        isLocked: json['isLocked'] ?? false,
        recordingUrl: json['recordingUrl'],
        password: json['password'],
        coHosts: List<String>.from(json['coHosts'] ?? []),
        muteAllCount: (json['muteAllCount'] ?? 0) as int,
        offeringLink: json['offeringLink'] as String?,
        isScheduled: json['isScheduled'] ?? false,
        scheduledAt: json['scheduledAt'] != null ? DateTime.parse(json['scheduledAt']) : null,
        waitingRoom: json['waitingRoom'] ?? false,
        maxParticipants: json['maxParticipants'] as int?,
        meetingMode: json['meetingMode'] as String?,
      );

  static MeetingStatus _statusFromString(String s) {
    switch (s) {
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
    String? password,
    List<String>? coHosts,
    int? muteAllCount,
    String? offeringLink,
    bool? isScheduled,
    DateTime? scheduledAt,
    bool? waitingRoom,
    int? maxParticipants,
    String? meetingMode,
  }) =>
      MeetingModel(
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
        password: password ?? this.password,
        coHosts: coHosts ?? this.coHosts,
        muteAllCount: muteAllCount ?? this.muteAllCount,
        offeringLink: offeringLink ?? this.offeringLink,
        isScheduled: isScheduled ?? this.isScheduled,
        scheduledAt: scheduledAt ?? this.scheduledAt,
        waitingRoom: waitingRoom ?? this.waitingRoom,
        maxParticipants: maxParticipants ?? this.maxParticipants,
        meetingMode: meetingMode ?? this.meetingMode,
      );

  @override
  String toString() => 'MeetingModel(id: $id, title: $title, status: $status)';
}

enum MeetingStatus { scheduled, ongoing, ended }
