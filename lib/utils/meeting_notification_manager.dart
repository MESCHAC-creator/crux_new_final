import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';
import '../models/scheduled_meeting_model.dart';
import '../services/meeting_service.dart';
import '../services/notification_service.dart';
import 'logger.dart' as crux;

/// **MeetingNotificationManager** — Gère les transitions de statuts et notifications automatiques.
/// Implémente la Phase 6-7 de la roadmap avec notifications intelligentes et transitions auto.
class MeetingNotificationManager {
  static final MeetingNotificationManager _instance =
      MeetingNotificationManager._internal();

  factory MeetingNotificationManager() => _instance;
  MeetingNotificationManager._internal();

  final _firestore = FirebaseFirestore.instance;
  final _meetingService = MeetingService();
  final _notificationService = NotificationService();
  final _log = Logger();

  /// Map de timers pour chaque réunion (meetingId -> Timer).
  /// Permet de gérer les notifications et transitions.
  final Map<String, Timer> _meetingTimers = {};

  /// Démarre la surveillance des transitions de statut pour une réunion planifiée.
  /// Appelle automatiquement les notifications et met à jour les statuts.
  void startMonitoring(String meetingId) {
    if (_meetingTimers.containsKey(meetingId)) {
      crux.logger.w('Meeting $meetingId déjà en surveillance');
      return;
    }

    _log.i('🔄 Démarrage surveillance réunion: $meetingId');

    // Vérifier la réunion toutes les 30 secondes
    final timer = Timer.periodic(const Duration(seconds: 30), (_) async {
      await _checkAndNotify(meetingId);
    });

    _meetingTimers[meetingId] = timer;
  }

  /// Arrête la surveillance d'une réunion.
  void stopMonitoring(String meetingId) {
    _meetingTimers[meetingId]?.cancel();
    _meetingTimers.remove(meetingId);
    crux.logger.i('⏹️ Surveillance arrêtée: $meetingId');
  }

  /// Arrête toutes les surveillances.
  void stopAllMonitoring() {
    for (final timer in _meetingTimers.values) {
      timer.cancel();
    }
    _meetingTimers.clear();
    crux.logger.i('🛑 Toutes les surveillances arrêtées');
  }

  /// Vérifie le statut d'une réunion et envoie les notifications appropriées.
  Future<void> _checkAndNotify(String meetingId) async {
    try {
      final meeting = await _meetingService.getScheduledMeeting(meetingId);
      if (meeting == null) {
        crux.logger.w('Réunion introuvable: $meetingId');
        stopMonitoring(meetingId);
        return;
      }

      final now = DateTime.now();

      // ── Vérifier les transitions de statut ────────────────────────────
      if (meeting.status == ScheduledMeetingStatus.scheduled) {
        // Transition : scheduled → live
        if (now.isAfter(meeting.scheduledStart) &&
            now.isBefore(meeting.scheduledEnd)) {
          await _transitionToLive(meeting);
          return;
        }

        // Transition : scheduled → ended (si le temps de fin est passé)
        if (now.isAfter(meeting.scheduledEnd)) {
          await _transitionToEnded(meeting);
          return;
        }

        // ── Notifications avant le démarrage ─────────────────────────────
        final timeUntilStart = meeting.scheduledStart.difference(now).inMinutes;

        // Notification 1 heure avant
        if (meeting.notifyAtOneHour && timeUntilStart == 60) {
          await _sendNotification(meeting, 'start', minutesBefore: 60);
        }

        // Notification 15 minutes avant
        if (meeting.notifyAtFifteenMin && timeUntilStart == 15) {
          await _sendNotification(meeting, 'start', minutesBefore: 15);
        }

        // Notification 5 minutes avant
        if (meeting.notifyAtFiveMin && timeUntilStart == 5) {
          await _sendNotification(meeting, 'start', minutesBefore: 5);
        }
      } else if (meeting.status == ScheduledMeetingStatus.live) {
        // Vérifier si la réunion doit se terminer
        if (now.isAfter(meeting.scheduledEnd)) {
          await _transitionToEnded(meeting);
        }
      }
    } catch (e) {
      _log.e('Erreur dans _checkAndNotify: $e');
    }
  }

  /// Transition : scheduled → live
  Future<void> _transitionToLive(ScheduledMeetingModel meeting) async {
    try {
      await _meetingService.updateScheduledMeetingStatus(
        meeting.id,
        ScheduledMeetingStatus.live,
      );

      if (meeting.notifyAtStart) {
        await _sendNotification(meeting, 'live', minutesBefore: 0);
      }

      _log.i('✅ Réunion ${meeting.id} passée en LIVE');

      // Note: Future → Ajouter une logique pour rejoindre automatiquement l'hôte
    } catch (e) {
      _log.e('Erreur transition live: $e');
    }
  }

  /// Transition : live → ended ou scheduled → ended
  Future<void> _transitionToEnded(ScheduledMeetingModel meeting) async {
    try {
      await _meetingService.updateScheduledMeetingStatus(
        meeting.id,
        ScheduledMeetingStatus.ended,
      );

      _log.i('✅ Réunion ${meeting.id} TERMINÉE');

      // Arrêter la surveillance
      stopMonitoring(meeting.id);

      // Future: Sauvegarder l'historique, archiver les enregistrements, etc.
    } catch (e) {
      _log.e('Erreur transition ended: $e');
    }
  }

  /// Envoie une notification intelligente (locale ou distant).
  Future<void> _sendNotification(
    ScheduledMeetingModel meeting,
    String type, {
    required int minutesBefore,
  }) async {
    try {
      late String title;
      late String body;

      if (type == 'start') {
        title = 'Rappel réunion';
        if (minutesBefore == 0) {
          body = '${meeting.title} commence maintenant! 🚀';
        } else {
          body =
              '${meeting.title} dans $minutesBefore minutes. Prépare-toi! ⏰';
        }
      } else if (type == 'live') {
        title = 'Réunion en direct';
        body = '${meeting.title} a démarré. Rejoins-la maintenant! 📞';
      } else {
        title = 'Réunion terminée';
        body = '${meeting.title} est terminée. À bientôt! 👋';
      }

      // Envoyer notification locale
      await _notificationService.notifyDailyReminder(
        userToken: meeting.organizerId,
        message: '$title: $body',
      );

      _log.i('📬 Notification envoyée: $title');
    } catch (e) {
      _log.e('Erreur notification: $e');
    }
  }

  /// Lance le monitoring pour toutes les réunions planifiées d'un utilisateur.
  Future<void> startMonitoringForUser(String userId) async {
    try {
      final meetings = _firestore
          .collection('scheduled_meetings')
          .where('participants', arrayContains: userId)
          .where('status', isEqualTo: 'scheduled')
          .snapshots();

      await for (final snap in meetings) {
        for (final doc in snap.docs) {
          final meeting = ScheduledMeetingModel.fromJson(
            doc.data() as Map<String, dynamic>,
          );

          // Si la réunion est dans le futur, la surveiller
          if (DateTime.now().isBefore(meeting.scheduledEnd)) {
            startMonitoring(meeting.id);
          } else {
            // Sinon, passer directement à "ended"
            await _meetingService.updateScheduledMeetingStatus(
              meeting.id,
              ScheduledMeetingStatus.ended,
            );
          }
        }
      }

      crux.logger.i('✅ Monitoring démarré pour l\'utilisateur $userId');
    } catch (e) {
      _log.e('Erreur startMonitoringForUser: $e');
    }
  }

  /// Marque les réunions expirées (passées, jamais commencées) comme ended.
  /// À appeler au démarrage de l'app pour nettoyer l'état.
  Future<void> cleanupExpiredMeetings(String userId) async {
    try {
      final now = DateTime.now();
      final snap = await _firestore
          .collection('scheduled_meetings')
          .where('participants', arrayContains: userId)
          .where('status', isEqualTo: 'scheduled')
          .get();

      int updated = 0;
      for (final doc in snap.docs) {
        final meeting = ScheduledMeetingModel.fromJson(
          doc.data() as Map<String, dynamic>,
        );

        // Si la réunion est passée sa date de fin
        if (now.isAfter(meeting.scheduledEnd)) {
          await _meetingService.updateScheduledMeetingStatus(
            meeting.id,
            ScheduledMeetingStatus.ended,
          );
          updated++;
        }
      }

      if (updated > 0) {
        crux.logger.i('🧹 $updated réunions expirées marquées comme ended');
      }
    } catch (e) {
      _log.e('Erreur cleanupExpiredMeetings: $e');
    }
  }
}
