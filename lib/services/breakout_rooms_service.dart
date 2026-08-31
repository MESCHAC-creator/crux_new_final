import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import '../utils/logger.dart' as crux;

/// Service de gestion des salles de sous-groupes (breakout rooms).
///
/// Ce service permet de créer et gérer des salles de discussion séparées
/// au sein d'une réunion principale, similaire à Zoom.
class BreakoutRoomsService {
  BreakoutRoomsService._();

  static final BreakoutRoomsService instance = BreakoutRoomsService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final crux.Logger _logger = crux.logger;
  final Uuid _uuid = const Uuid();

  // État des salles
  BreakoutRoomsState? _currentState;
  final StreamController<BreakoutRoomsState> _stateController = 
      StreamController<BreakoutRoomsState>.broadcast();

  // Getters
  BreakoutRoomsState? get currentState => _currentState;
  Stream<BreakoutRoomsState> get stateStream => _stateController.stream;
  bool get isBreakoutActive => _currentState?.isActive ?? false;

  /// Initialise le service
  Future<void> initialize() async {
    await _loadCurrentState();
    _logger.i('BreakoutRoomsService initialized');
  }

  /// Charge l'état actuel des salles
  Future<void> _loadCurrentState() async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) return;

      // En production, charger depuis Firestore
      // Pour l'instant, initialiser à null
      _currentState = null;
    } catch (e) {
      _logger.e('Failed to load breakout rooms state', error: e);
    }
  }

  /// Crée des salles de sous-groupes
  Future<String> createBreakoutRooms({
    required String mainMeetingId,
    required int numberOfRooms,
    required bool autoAssign,
    required int durationMinutes,
    String? customName,
  }) async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) throw Exception('User not authenticated');

      final breakoutId = _uuid.v4();
      final now = DateTime.now();

      final rooms = <BreakoutRoom>[];
      for (int i = 0; i < numberOfRooms; i++) {
        rooms.add(BreakoutRoom(
          id: _uuid.v4(),
          name: customName != null 
              ? '$customName ${i + 1}' 
              : 'Salle ${i + 1}',
          participantIds: [],
          maxParticipants: 10,
        ));
      }

      final state = BreakoutRoomsState(
        id: breakoutId,
        mainMeetingId: mainMeetingId,
        createdBy: userId,
        createdAt: now,
        endTime: now.add(Duration(minutes: durationMinutes)),
        isActive: true,
        rooms: rooms,
        autoAssign: autoAssign,
        allowParticipantsToSwitch: true,
        countdownEnabled: true,
      );

      await _saveState(state);
      _currentState = state;
      _stateController.add(state);

      _logger.i('Created $numberOfRooms breakout rooms for meeting $mainMeetingId');
      return breakoutId;
    } catch (e) {
      _logger.e('Failed to create breakout rooms', error: e);
      rethrow;
    }
  }

  /// Assigne un participant à une salle spécifique
  Future<void> assignParticipantToRoom({
    required String participantId,
    required String roomId,
  }) async {
    try {
      if (_currentState == null || !_currentState!.isActive) {
        throw Exception('Breakout rooms not active');
      }

      final updatedRooms = _currentState!.rooms.map((room) {
        if (room.id == roomId) {
          return BreakoutRoom(
            id: room.id,
            name: room.name,
            participantIds: [...room.participantIds, participantId],
            maxParticipants: room.maxParticipants,
          );
        }
        return room;
      }).toList();

      final updatedState = _currentState!.copyWith(rooms: updatedRooms);
      await _saveState(updatedState);
      _currentState = updatedState;
      _stateController.add(updatedState);

      _logger.i('Assigned participant $participantId to room $roomId');
    } catch (e) {
      _logger.e('Failed to assign participant to room', error: e);
      rethrow;
    }
  }

  /// Assigne automatiquement les participants aux salles
  Future<void> autoAssignParticipants(List<String> participantIds) async {
    try {
      if (_currentState == null || !_currentState!.isActive) {
        throw Exception('Breakout rooms not active');
      }

      final rooms = _currentState!.rooms;
      final assignments = <String, String>{}; // participantId -> roomId

      // Distribution équitable
      for (int i = 0; i < participantIds.length; i++) {
        final roomIndex = i % rooms.length;
        assignments[participantIds[i]] = rooms[roomIndex].id;
      }

      // Mettre à jour les salles
      final updatedRooms = rooms.map((room) {
        final roomParticipants = assignments.entries
            .where((entry) => entry.value == room.id)
            .map((entry) => entry.key)
            .toList();

        return BreakoutRoom(
          id: room.id,
          name: room.name,
          participantIds: roomParticipants,
          maxParticipants: room.maxParticipants,
        );
      }).toList();

      final updatedState = _currentState!.copyWith(rooms: updatedRooms);
      await _saveState(updatedState);
      _currentState = updatedState;
      _stateController.add(updatedState);

      _logger.i('Auto-assigned ${participantIds.length} participants to ${rooms.length} rooms');
    } catch (e) {
      _logger.e('Failed to auto-assign participants', error: e);
      rethrow;
    }
  }

  /// Déplace un participant vers une autre salle
  Future<void> moveParticipantToRoom({
    required String participantId,
    required String newRoomId,
  }) async {
    try {
      if (_currentState == null || !_currentState!.isActive) {
        throw Exception('Breakout rooms not active');
      }

      // Retirer de l'ancienne salle
      final updatedRooms = _currentState!.rooms.map((room) {
        final updatedParticipants = room.participantIds
            .where((id) => id != participantId)
            .toList();

        return BreakoutRoom(
          id: room.id,
          name: room.name,
          participantIds: updatedParticipants,
          maxParticipants: room.maxParticipants,
        );
      }).toList();

      // Ajouter à la nouvelle salle
      final finalRooms = updatedRooms.map((room) {
        if (room.id == newRoomId) {
          return BreakoutRoom(
            id: room.id,
            name: room.name,
            participantIds: [...room.participantIds, participantId],
            maxParticipants: room.maxParticipants,
          );
        }
        return room;
      }).toList();

      final updatedState = _currentState!.copyWith(rooms: finalRooms);
      await _saveState(updatedState);
      _currentState = updatedState;
      _stateController.add(updatedState);

      _logger.i('Moved participant $participantId to room $newRoomId');
    } catch (e) {
      _logger.e('Failed to move participant to room', error: e);
      rethrow;
    }
  }

  /// Invite tous les participants à revenir à la réunion principale
  Future<void> broadcastReturnToMain() async {
    try {
      if (_currentState == null || !_currentState!.isActive) {
        throw Exception('Breakout rooms not active');
      }

      final updatedState = _currentState!.copyWith(
        countdownEnabled: true,
        countdownSeconds: 60,
      );

      await _saveState(updatedState);
      _currentState = updatedState;
      _stateController.add(updatedState);

      _logger.i('Broadcasted return to main meeting');
    } catch (e) {
      _logger.e('Failed to broadcast return to main', error: e);
      rethrow;
    }
  }

  /// Termine les salles de sous-groupes
  Future<void> closeBreakoutRooms() async {
    try {
      if (_currentState == null) return;

      final updatedState = _currentState!.copyWith(
        isActive: false,
        endedAt: DateTime.now(),
      );

      await _saveState(updatedState);
      _currentState = updatedState;
      _stateController.add(updatedState);

      _logger.i('Closed breakout rooms');
    } catch (e) {
      _logger.e('Failed to close breakout rooms', error: e);
      rethrow;
    }
  }

  /// Sauvegarde l'état dans Firestore
  Future<void> _saveState(BreakoutRoomsState state) async {
    try {
      await _firestore
          .collection('breakout_rooms')
          .doc(state.id)
          .set(state.toJson());
    } catch (e) {
      _logger.e('Failed to save breakout rooms state', error: e);
      rethrow;
    }
  }

  /// Obtient la salle d'un participant
  BreakoutRoom? getParticipantRoom(String participantId) {
    if (_currentState == null) return null;

    for (final room in _currentState!.rooms) {
      if (room.participantIds.contains(participantId)) {
        return room;
      }
    }
    return null;
  }

  /// Obtient le nombre de participants par salle
  Map<String, int> getRoomParticipantCounts() {
    if (_currentState == null) return {};

    return {
      for (final room in _currentState!.rooms)
        room.id: room.participantIds.length,
    };
  }

  /// Vérifie si le temps est écoulé
  bool isTimeElapsed() {
    if (_currentState == null) return false;
    return DateTime.now().isAfter(_currentState!.endTime);
  }

  /// Obtient le temps restant
  Duration getRemainingTime() {
    if (_currentState == null) return Duration.zero;
    final remaining = _currentState!.endTime.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Nettoie les ressources
  void dispose() {
    _stateController.close();
    _logger.i('BreakoutRoomsService disposed');
  }
}

/// État des salles de sous-groupes
class BreakoutRoomsState {
  final String id;
  final String mainMeetingId;
  final String createdBy;
  final DateTime createdAt;
  final DateTime endTime;
  final DateTime? endedAt;
  final bool isActive;
  final List<BreakoutRoom> rooms;
  final bool autoAssign;
  final bool allowParticipantsToSwitch;
  final bool countdownEnabled;
  final int countdownSeconds;

  BreakoutRoomsState({
    required this.id,
    required this.mainMeetingId,
    required this.createdBy,
    required this.createdAt,
    required this.endTime,
    this.endedAt,
    required this.isActive,
    required this.rooms,
    required this.autoAssign,
    required this.allowParticipantsToSwitch,
    required this.countdownEnabled,
    this.countdownSeconds = 60,
  });

  BreakoutRoomsState copyWith({
    String? id,
    String? mainMeetingId,
    String? createdBy,
    DateTime? createdAt,
    DateTime? endTime,
    DateTime? endedAt,
    bool? isActive,
    List<BreakoutRoom>? rooms,
    bool? autoAssign,
    bool? allowParticipantsToSwitch,
    bool? countdownEnabled,
    int? countdownSeconds,
  }) {
    return BreakoutRoomsState(
      id: id ?? this.id,
      mainMeetingId: mainMeetingId ?? this.mainMeetingId,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      endTime: endTime ?? this.endTime,
      endedAt: endedAt ?? this.endedAt,
      isActive: isActive ?? this.isActive,
      rooms: rooms ?? this.rooms,
      autoAssign: autoAssign ?? this.autoAssign,
      allowParticipantsToSwitch: allowParticipantsToSwitch ?? this.allowParticipantsToSwitch,
      countdownEnabled: countdownEnabled ?? this.countdownEnabled,
      countdownSeconds: countdownSeconds ?? this.countdownSeconds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'mainMeetingId': mainMeetingId,
      'createdBy': createdBy,
      'createdAt': createdAt.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      'endedAt': endedAt?.toIso8601String(),
      'isActive': isActive,
      'rooms': rooms.map((r) => r.toJson()).toList(),
      'autoAssign': autoAssign,
      'allowParticipantsToSwitch': allowParticipantsToSwitch,
      'countdownEnabled': countdownEnabled,
      'countdownSeconds': countdownSeconds,
    };
  }

  static BreakoutRoomsState fromJson(Map<String, dynamic> json) {
    return BreakoutRoomsState(
      id: json['id'] as String,
      mainMeetingId: json['mainMeetingId'] as String,
      createdBy: json['createdBy'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      endTime: DateTime.parse(json['endTime'] as String),
      endedAt: json['endedAt'] != null 
          ? DateTime.parse(json['endedAt'] as String) 
          : null,
      isActive: json['isActive'] as bool,
      rooms: (json['rooms'] as List)
          .map((r) => BreakoutRoom.fromJson(r as Map<String, dynamic>))
          .toList(),
      autoAssign: json['autoAssign'] as bool,
      allowParticipantsToSwitch: json['allowParticipantsToSwitch'] as bool,
      countdownEnabled: json['countdownEnabled'] as bool,
      countdownSeconds: json['countdownSeconds'] as int? ?? 60,
    );
  }
}

/// Salle de sous-groupe
class BreakoutRoom {
  final String id;
  final String name;
  final List<String> participantIds;
  final int maxParticipants;

  BreakoutRoom({
    required this.id,
    required this.name,
    required this.participantIds,
    required this.maxParticipants,
  });

  bool get isFull => participantIds.length >= maxParticipants;
  int get availableSlots => maxParticipants - participantIds.length;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'participantIds': participantIds,
      'maxParticipants': maxParticipants,
    };
  }

  static BreakoutRoom fromJson(Map<String, dynamic> json) {
    return BreakoutRoom(
      id: json['id'] as String,
      name: json['name'] as String,
      participantIds: (json['participantIds'] as List).cast<String>(),
      maxParticipants: json['maxParticipants'] as int,
    );
  }
}