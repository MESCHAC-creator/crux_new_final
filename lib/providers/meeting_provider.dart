import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import '../models/meeting_model.dart';
import '../services/meeting_service.dart';
import '../services/error_handler_service.dart';

class MeetingProvider extends ChangeNotifier {
  final MeetingService _meetingService = MeetingService();
  final _logger = Logger();
  final _errorHandler = ErrorHandlerService();

  List<MeetingModel> _meetings = [];
  MeetingModel? _currentMeeting;
  bool _isLoading = false;
  String? _error;

  // Getters
  List<MeetingModel> get meetings => _meetings;
  MeetingModel? get currentMeeting => _currentMeeting;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Créer une réunion
  Future<String?> createMeeting({
    required String title,
    required String description,
    required String organizerName,
    required String organizerId,
  }) async {
    try {
      _setLoading(true);
      _clearError();

      final meetingId = await _meetingService.createMeeting(
        title: title,
        description: description,
        organizerName: organizerName,
        organizerId: organizerId,
      );

      _logger.i('✅ Réunion créée: $meetingId');
      notifyListeners();
      return meetingId;
    } catch (e) {
      _setError('Erreur création réunion: $e');
      _logger.e('❌ Erreur: $e');
      return null;
    } finally {
      _setLoading(false);
    }
  }

  // Obtenir une réunion
  Future<void> getMeeting(String meetingId) async {
    try {
      _setLoading(true);
      _clearError();

      _meetingService.getMeeting(meetingId).listen((meeting) {
        _currentMeeting = meeting;
        _logger.i('📋 Réunion obtenue: $meetingId');
        notifyListeners();
      });
    } catch (e) {
      _setError('Erreur récupération: $e');
      _logger.e('❌ Erreur: $e');
    } finally {
      _setLoading(false);
    }
  }

  // Mettre à jour le statut
  Future<void> updateMeetingStatus(
      String meetingId,
      MeetingStatus status,
      ) async {
    try {
      await _meetingService.updateMeetingStatus(meetingId, status);
      _logger.i('✅ Statut mis à jour: ${status.toString().split('.').last}');
      notifyListeners();
    } catch (e) {
      _setError('Erreur mise à jour: $e');
      _logger.e('❌ Erreur: $e');
    }
  }

  // Ajouter un participant
  Future<void> addParticipant(String meetingId, String userId) async {
    try {
      await _meetingService.addParticipant(meetingId, userId);
      _logger.i('✅ Participant ajouté: $userId');
      notifyListeners();
    } catch (e) {
      _setError('Erreur ajout participant: $e');
      _logger.e('❌ Erreur: $e');
    }
  }

  // Supprimer un participant
  Future<void> removeParticipant(String meetingId, String userId) async {
    try {
      await _meetingService.removeParticipant(meetingId, userId);
      _logger.i('✅ Participant supprimé: $userId');
      notifyListeners();
    } catch (e) {
      _setError('Erreur suppression participant: $e');
      _logger.e('❌ Erreur: $e');
    }
  }

  // Helpers privés
  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setError(String error) {
    _error = error;
    _logger.e('❌ $error');
    notifyListeners();
  }

  void _clearError() {
    _error = null;
  }

  void clearMeeting() {
    _currentMeeting = null;
    notifyListeners();
  }
}