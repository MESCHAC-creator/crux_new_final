/// Énumération des types de réunion.
enum MeetingType { standard, largeConference, webinar }

/// Énumération des statuts de réunion planifiée.
enum ScheduledMeetingStatus { scheduled, live, ended, cancelled }

/// Énumération de la récurrence.
enum RecurrencePattern { none, daily, weekly, monthly, yearly, custom }

/// **ScheduledMeetingModel** — Modèle professionnel complet pour réunions planifiées.
/// 
/// Contient tous les champs demandés par la roadmap CRUX :
/// - Identification & métadonnées
/// - Dates/heures avec fuseau horaire
/// - Paramètres de sécurité
/// - Paramètres audio/vidéo
/// - Enregistrement
/// - Invitations
/// - Notifications
/// - Récurrence
/// - Statuts et transitions
/// - Données Enterprise (prêtes pour Phase 13)
class ScheduledMeetingModel {
  /// === IDENTIFICATION & MÉTADONNÉES ===
  final String id;
  final String title;
  final String description;
  final String organizerId;
  final String organizerName;
  final String organizerEmail;
  final DateTime createdAt;
  
  /// === PLANNING ===
  final DateTime scheduledStart;
  final DateTime scheduledEnd;
  final String timezone; // IANA format: "Europe/Paris", "America/New_York", etc.
  
  /// === RÉCURRENCE (Phase 11) ===
  final RecurrencePattern recurrence;
  final Map<String, dynamic> recurrenceConfig; // {"dayOfWeek": [1,3,5], "interval": 2, ...}
  final String? parentSeriesId; // Si c'est une occurrence d'une série
  final DateTime? recurrenceEndDate;
  
  /// === STATUTS & TRANSITIONS ===
  final ScheduledMeetingStatus status; // scheduled, live, ended, cancelled
  DateTime? actualStart;
  DateTime? actualEnd;
  String? cancellationReason;
  
  /// === SÉCURITÉ ===
  final String? passcode; // 4-6 digit PIN
  final bool waitingRoomEnabled;
  final bool allowBeforeHost; // Participants peuvent rejoindre avant l'hôte
  final bool disableGuests; // Interdire les invités non authentifiés
  
  /// === PARAMÈTRES AUDIO/VIDÉO ===
  final bool cameraEnabled;
  final bool microphoneEnabled;
  final bool screenShareEnabled;
  final bool chatEnabled;
  final bool reactionsEnabled;
  
  /// === ENREGISTREMENT (Phase 6) ===
  final bool recordAutomatically;
  final String recordingType; // "cloud", "local", "none"
  String? recordingUrl;
  
  /// === PARTICIPANTS & INVITATIONS ===
  final List<String> participants; // UIDs des participants confirmés
  final List<String> invitedEmails; // Emails invités
  final List<String> coHosts; // UIDs des co-hôtes
  
  /// === NOTIFICATIONS (Phase 6) ===
  final bool notifyAtOneHour;
  final bool notifyAtFifteenMin;
  final bool notifyAtFiveMin;
  final bool notifyAtStart;
  
  /// === LIENS & PARTAGE ===
  final String meetingLink;
  final String meetingCode;
  String? qrCodeUrl;
  
  /// === PARAMÈTRES AVANCÉS ===
  final MeetingType meetingType;
  final bool isLargeConference; // Détermine SFU (LiveKit) vs P2P
  final Map<String, dynamic> settings; // Flexible pour futures options
  
  /// === DONNÉES ENTERPRISE (Phase 13) ===
  String? organizationId;
  String? workspaceId;
  String? departmentId;
  List<String> allowedRoles; // ["admin", "organizer", "participant"]
  String? auditLogId;
  String? licenseId;

  ScheduledMeetingModel({
    required this.id,
    required this.title,
    required this.description,
    required this.organizerId,
    required this.organizerName,
    required this.organizerEmail,
    required this.createdAt,
    required this.scheduledStart,
    required this.scheduledEnd,
    required this.timezone,
    this.recurrence = RecurrencePattern.none,
    this.recurrenceConfig = const {},
    this.parentSeriesId,
    this.recurrenceEndDate,
    required this.status,
    this.actualStart,
    this.actualEnd,
    this.cancellationReason,
    this.passcode,
    this.waitingRoomEnabled = false,
    this.allowBeforeHost = false,
    this.disableGuests = false,
    this.cameraEnabled = true,
    this.microphoneEnabled = true,
    this.screenShareEnabled = true,
    this.chatEnabled = true,
    this.reactionsEnabled = true,
    this.recordAutomatically = false,
    this.recordingType = 'none',
    this.recordingUrl,
    required this.participants,
    this.invitedEmails = const [],
    this.coHosts = const [],
    this.notifyAtOneHour = true,
    this.notifyAtFifteenMin = true,
    this.notifyAtFiveMin = true,
    this.notifyAtStart = true,
    required this.meetingLink,
    required this.meetingCode,
    this.qrCodeUrl,
    this.meetingType = MeetingType.standard,
    this.isLargeConference = false,
    this.settings = const {},
    this.organizationId,
    this.workspaceId,
    this.departmentId,
    this.allowedRoles = const ['participant'],
    this.auditLogId,
    this.licenseId,
  });

  /// Convertir en JSON pour Firestore.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'organizerId': organizerId,
      'organizerName': organizerName,
      'organizerEmail': organizerEmail,
      'createdAt': createdAt.toIso8601String(),
      'scheduledStart': scheduledStart.toIso8601String(),
      'scheduledEnd': scheduledEnd.toIso8601String(),
      'timezone': timezone,
      'recurrence': recurrence.toString().split('.').last,
      'recurrenceConfig': recurrenceConfig,
      'parentSeriesId': parentSeriesId,
      'recurrenceEndDate': recurrenceEndDate?.toIso8601String(),
      'status': status.toString().split('.').last,
      'actualStart': actualStart?.toIso8601String(),
      'actualEnd': actualEnd?.toIso8601String(),
      'cancellationReason': cancellationReason,
      'passcode': passcode,
      'waitingRoomEnabled': waitingRoomEnabled,
      'allowBeforeHost': allowBeforeHost,
      'disableGuests': disableGuests,
      'cameraEnabled': cameraEnabled,
      'microphoneEnabled': microphoneEnabled,
      'screenShareEnabled': screenShareEnabled,
      'chatEnabled': chatEnabled,
      'reactionsEnabled': reactionsEnabled,
      'recordAutomatically': recordAutomatically,
      'recordingType': recordingType,
      'recordingUrl': recordingUrl,
      'participants': participants,
      'invitedEmails': invitedEmails,
      'coHosts': coHosts,
      'notifyAtOneHour': notifyAtOneHour,
      'notifyAtFifteenMin': notifyAtFifteenMin,
      'notifyAtFiveMin': notifyAtFiveMin,
      'notifyAtStart': notifyAtStart,
      'meetingLink': meetingLink,
      'meetingCode': meetingCode,
      'qrCodeUrl': qrCodeUrl,
      'meetingType': meetingType.toString().split('.').last,
      'isLargeConference': isLargeConference,
      'settings': settings,
      'organizationId': organizationId,
      'workspaceId': workspaceId,
      'departmentId': departmentId,
      'allowedRoles': allowedRoles,
      'auditLogId': auditLogId,
      'licenseId': licenseId,
    };
  }

  /// Construire depuis JSON (Firestore).
  factory ScheduledMeetingModel.fromJson(Map<String, dynamic> json) {
    return ScheduledMeetingModel(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      organizerId: json['organizerId'] ?? '',
      organizerName: json['organizerName'] ?? '',
      organizerEmail: json['organizerEmail'] ?? '',
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      scheduledStart: DateTime.parse(json['scheduledStart'] ?? DateTime.now().toIso8601String()),
      scheduledEnd: DateTime.parse(json['scheduledEnd'] ?? DateTime.now().add(const Duration(hours: 1)).toIso8601String()),
      timezone: json['timezone'] ?? 'UTC',
      recurrence: _parseRecurrence(json['recurrence']),
      recurrenceConfig: json['recurrenceConfig'] ?? {},
      parentSeriesId: json['parentSeriesId'],
      recurrenceEndDate: json['recurrenceEndDate'] != null ? DateTime.parse(json['recurrenceEndDate']) : null,
      status: _parseStatus(json['status']),
      actualStart: json['actualStart'] != null ? DateTime.parse(json['actualStart']) : null,
      actualEnd: json['actualEnd'] != null ? DateTime.parse(json['actualEnd']) : null,
      cancellationReason: json['cancellationReason'],
      passcode: json['passcode'],
      waitingRoomEnabled: json['waitingRoomEnabled'] ?? false,
      allowBeforeHost: json['allowBeforeHost'] ?? false,
      disableGuests: json['disableGuests'] ?? false,
      cameraEnabled: json['cameraEnabled'] ?? true,
      microphoneEnabled: json['microphoneEnabled'] ?? true,
      screenShareEnabled: json['screenShareEnabled'] ?? true,
      chatEnabled: json['chatEnabled'] ?? true,
      reactionsEnabled: json['reactionsEnabled'] ?? true,
      recordAutomatically: json['recordAutomatically'] ?? false,
      recordingType: json['recordingType'] ?? 'none',
      recordingUrl: json['recordingUrl'],
      participants: List<String>.from(json['participants'] ?? []),
      invitedEmails: List<String>.from(json['invitedEmails'] ?? []),
      coHosts: List<String>.from(json['coHosts'] ?? []),
      notifyAtOneHour: json['notifyAtOneHour'] ?? true,
      notifyAtFifteenMin: json['notifyAtFifteenMin'] ?? true,
      notifyAtFiveMin: json['notifyAtFiveMin'] ?? true,
      notifyAtStart: json['notifyAtStart'] ?? true,
      meetingLink: json['meetingLink'] ?? '',
      meetingCode: json['meetingCode'] ?? '',
      qrCodeUrl: json['qrCodeUrl'],
      meetingType: _parseMeetingType(json['meetingType']),
      isLargeConference: json['isLargeConference'] ?? false,
      settings: json['settings'] ?? {},
      organizationId: json['organizationId'],
      workspaceId: json['workspaceId'],
      departmentId: json['departmentId'],
      allowedRoles: List<String>.from(json['allowedRoles'] ?? ['participant']),
      auditLogId: json['auditLogId'],
      licenseId: json['licenseId'],
    );
  }

  static RecurrencePattern _parseRecurrence(String? value) {
    switch (value) {
      case 'daily':
        return RecurrencePattern.daily;
      case 'weekly':
        return RecurrencePattern.weekly;
      case 'monthly':
        return RecurrencePattern.monthly;
      case 'yearly':
        return RecurrencePattern.yearly;
      case 'custom':
        return RecurrencePattern.custom;
      default:
        return RecurrencePattern.none;
    }
  }

  static ScheduledMeetingStatus _parseStatus(String? value) {
    switch (value) {
      case 'live':
        return ScheduledMeetingStatus.live;
      case 'ended':
        return ScheduledMeetingStatus.ended;
      case 'cancelled':
        return ScheduledMeetingStatus.cancelled;
      default:
        return ScheduledMeetingStatus.scheduled;
    }
  }

  static MeetingType _parseMeetingType(String? value) {
    switch (value) {
      case 'largeConference':
        return MeetingType.largeConference;
      case 'webinar':
        return MeetingType.webinar;
      default:
        return MeetingType.standard;
    }
  }

  /// Copie avec paramètres optionnels.
  ScheduledMeetingModel copyWith({
    String? id,
    String? title,
    String? description,
    String? organizerId,
    String? organizerName,
    String? organizerEmail,
    DateTime? createdAt,
    DateTime? scheduledStart,
    DateTime? scheduledEnd,
    String? timezone,
    RecurrencePattern? recurrence,
    Map<String, dynamic>? recurrenceConfig,
    String? parentSeriesId,
    DateTime? recurrenceEndDate,
    ScheduledMeetingStatus? status,
    DateTime? actualStart,
    DateTime? actualEnd,
    String? cancellationReason,
    String? passcode,
    bool? waitingRoomEnabled,
    bool? allowBeforeHost,
    bool? disableGuests,
    bool? cameraEnabled,
    bool? microphoneEnabled,
    bool? screenShareEnabled,
    bool? chatEnabled,
    bool? reactionsEnabled,
    bool? recordAutomatically,
    String? recordingType,
    String? recordingUrl,
    List<String>? participants,
    List<String>? invitedEmails,
    List<String>? coHosts,
    bool? notifyAtOneHour,
    bool? notifyAtFifteenMin,
    bool? notifyAtFiveMin,
    bool? notifyAtStart,
    String? meetingLink,
    String? meetingCode,
    String? qrCodeUrl,
    MeetingType? meetingType,
    bool? isLargeConference,
    Map<String, dynamic>? settings,
    String? organizationId,
    String? workspaceId,
    String? departmentId,
    List<String>? allowedRoles,
    String? auditLogId,
    String? licenseId,
  }) {
    return ScheduledMeetingModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      organizerId: organizerId ?? this.organizerId,
      organizerName: organizerName ?? this.organizerName,
      organizerEmail: organizerEmail ?? this.organizerEmail,
      createdAt: createdAt ?? this.createdAt,
      scheduledStart: scheduledStart ?? this.scheduledStart,
      scheduledEnd: scheduledEnd ?? this.scheduledEnd,
      timezone: timezone ?? this.timezone,
      recurrence: recurrence ?? this.recurrence,
      recurrenceConfig: recurrenceConfig ?? this.recurrenceConfig,
      parentSeriesId: parentSeriesId ?? this.parentSeriesId,
      recurrenceEndDate: recurrenceEndDate ?? this.recurrenceEndDate,
      status: status ?? this.status,
      actualStart: actualStart ?? this.actualStart,
      actualEnd: actualEnd ?? this.actualEnd,
      cancellationReason: cancellationReason ?? this.cancellationReason,
      passcode: passcode ?? this.passcode,
      waitingRoomEnabled: waitingRoomEnabled ?? this.waitingRoomEnabled,
      allowBeforeHost: allowBeforeHost ?? this.allowBeforeHost,
      disableGuests: disableGuests ?? this.disableGuests,
      cameraEnabled: cameraEnabled ?? this.cameraEnabled,
      microphoneEnabled: microphoneEnabled ?? this.microphoneEnabled,
      screenShareEnabled: screenShareEnabled ?? this.screenShareEnabled,
      chatEnabled: chatEnabled ?? this.chatEnabled,
      reactionsEnabled: reactionsEnabled ?? this.reactionsEnabled,
      recordAutomatically: recordAutomatically ?? this.recordAutomatically,
      recordingType: recordingType ?? this.recordingType,
      recordingUrl: recordingUrl ?? this.recordingUrl,
      participants: participants ?? this.participants,
      invitedEmails: invitedEmails ?? this.invitedEmails,
      coHosts: coHosts ?? this.coHosts,
      notifyAtOneHour: notifyAtOneHour ?? this.notifyAtOneHour,
      notifyAtFifteenMin: notifyAtFifteenMin ?? this.notifyAtFifteenMin,
      notifyAtFiveMin: notifyAtFiveMin ?? this.notifyAtFiveMin,
      notifyAtStart: notifyAtStart ?? this.notifyAtStart,
      meetingLink: meetingLink ?? this.meetingLink,
      meetingCode: meetingCode ?? this.meetingCode,
      qrCodeUrl: qrCodeUrl ?? this.qrCodeUrl,
      meetingType: meetingType ?? this.meetingType,
      isLargeConference: isLargeConference ?? this.isLargeConference,
      settings: settings ?? this.settings,
      organizationId: organizationId ?? this.organizationId,
      workspaceId: workspaceId ?? this.workspaceId,
      departmentId: departmentId ?? this.departmentId,
      allowedRoles: allowedRoles ?? this.allowedRoles,
      auditLogId: auditLogId ?? this.auditLogId,
      licenseId: licenseId ?? this.licenseId,
    );
  }

  @override
  String toString() => 'ScheduledMeetingModel(id: $id, title: $title, status: $status)';
}
