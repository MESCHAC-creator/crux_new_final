import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';

/// Service de gestion des salles de sous-groupes (breakout rooms).
///
/// Ce service permet de créer et gérer des salles de sous-groupes
/// pour les grandes réunions, permettant aux participants de travailler
/// en petits groupes.
class BreakoutRoomsService {
  BreakoutRoomsService._();

  static final BreakoutRoomsService instance = BreakoutRoomsService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _logger = Logger();

  // État des salles de sous-groupes
  bool _breakoutRoomsEnabled = false;
  int _numberOfRooms = 4;
  int _durationMinutes = 10;
  Timer? _breakoutTimer;

  // Getters
  bool get breakoutRoomsEnabled => _breakoutRoomsEnabled;
  int get numberOfRooms => _numberOfRooms;
  int get durationMinutes => _durationMinutes;

  /// Initialise le service de salles de sous-groupes
  Future<void> initialize() async {
    _logger.i('BreakoutRoomsService initialized');
  }

  /// Active les salles de sous-groupes
  Future<void> enableBreakoutRooms({
    required String meetingId,
    required int numberOfRooms,
    required int durationMinutes,
  }) async {
    try {
      _numberOfRooms = numberOfRooms;
      _durationMinutes = durationMinutes;
      _breakoutRoomsEnabled = true;

      // Créer les salles dans Firestore
      for (int i = 0; i < numberOfRooms; i++) {
        await _firestore
            .collection('meetings')
            .doc(meetingId)
            .collection('breakout_rooms')
            .add({
              'roomId': 'room_$i',
              'roomName': 'Salle ${i + 1}',
              'participants': [],
              'createdAt': FieldValue.serverTimestamp(),
              'isActive': true,
            });
      }

      // Démarrer le timer
      _startBreakoutTimer(meetingId);

      _logger.i(
        'Breakout rooms enabled: $numberOfRooms rooms for $durationMinutes minutes',
      );
    } catch (e) {
      _logger.e('Error enabling breakout rooms', error: e);
      rethrow;
    }
  }

  /// Désactive les salles de sous-groupes
  Future<void> disableBreakoutRooms(String meetingId) async {
    try {
      _breakoutRoomsEnabled = false;
      _breakoutTimer?.cancel();
      _breakoutTimer = null;

      // Désactiver toutes les salles
      final rooms =
          await _firestore
              .collection('meetings')
              .doc(meetingId)
              .collection('breakout_rooms')
              .where('isActive', isEqualTo: true)
              .get();

      for (var doc in rooms.docs) {
        await doc.reference.update({'isActive': false});
      }

      _logger.i('Breakout rooms disabled');
    } catch (e) {
      _logger.e('Error disabling breakout rooms', error: e);
      rethrow;
    }
  }

  /// Assigne un participant à une salle spécifique
  Future<void> assignParticipantToRoom({
    required String meetingId,
    required String roomId,
    required String participantId,
    required String participantName,
  }) async {
    try {
      await _firestore
          .collection('meetings')
          .doc(meetingId)
          .collection('breakout_rooms')
          .where('roomId', isEqualTo: roomId)
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get()
          .then((snapshot) async {
            if (snapshot.docs.isNotEmpty) {
              await snapshot.docs.first.reference.update({
                'participants': FieldValue.arrayUnion([participantId]),
              });
              _logger.i('Participant $participantId assigned to room $roomId');
            }
          });
    } catch (e) {
      _logger.e('Error assigning participant to room', error: e);
      rethrow;
    }
  }

  /// Obtient les salles de sous-groupes actives
  Stream<QuerySnapshot> getActiveBreakoutRooms(String meetingId) {
    return _firestore
        .collection('meetings')
        .doc(meetingId)
        .collection('breakout_rooms')
        .where('isActive', isEqualTo: true)
        .snapshots();
  }

  /// Déplace un participant vers une autre salle
  Future<void> moveParticipantToRoom({
    required String meetingId,
    required String currentRoomId,
    required String newRoomId,
    required String participantId,
  }) async {
    try {
      // Retirer de la salle actuelle
      await _firestore
          .collection('meetings')
          .doc(meetingId)
          .collection('breakout_rooms')
          .where('roomId', isEqualTo: currentRoomId)
          .limit(1)
          .get()
          .then((snapshot) async {
            if (snapshot.docs.isNotEmpty) {
              await snapshot.docs.first.reference.update({
                'participants': FieldValue.arrayRemove([participantId]),
              });
            }
          });

      // Ajouter à la nouvelle salle
      await assignParticipantToRoom(
        meetingId: meetingId,
        roomId: newRoomId,
        participantId: participantId,
        participantName: '',
      );

      _logger.i(
        'Participant $participantId moved from $currentRoomId to $newRoomId',
      );
    } catch (e) {
      _logger.e('Error moving participant between rooms', error: e);
      rethrow;
    }
  }

  /// Broadcast un message à toutes les salles
  Future<void> broadcastToAllRooms({
    required String meetingId,
    required String message,
  }) async {
    try {
      final rooms =
          await _firestore
              .collection('meetings')
              .doc(meetingId)
              .collection('breakout_rooms')
              .where('isActive', isEqualTo: true)
              .get();

      for (var doc in rooms.docs) {
        await doc.reference.update({
          'broadcastMessage': message,
          'broadcastTimestamp': FieldValue.serverTimestamp(),
        });
      }

      _logger.i('Broadcast message sent to ${rooms.docs.length} rooms');
    } catch (e) {
      _logger.e('Error broadcasting to rooms', error: e);
      rethrow;
    }
  }

  /// Démarre le timer pour les salles de sous-groupes
  void _startBreakoutTimer(String meetingId) {
    _breakoutTimer?.cancel();
    _breakoutTimer = Timer(Duration(minutes: _durationMinutes), () {
      disableBreakoutRooms(meetingId);
    });
  }

  void dispose() {
    _breakoutTimer?.cancel();
  }
}
