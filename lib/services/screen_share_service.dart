import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:logger/logger.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Service pour gérer le partage d'écran dans les réunions WebRTC
class ScreenShareService {
  static final ScreenShareService _instance = ScreenShareService._internal();
  factory ScreenShareService() => _instance;
  ScreenShareService._internal();

  final _log = Logger();
  final _db = FirebaseFirestore.instance;
  
  static const _screenChannel = MethodChannel('com.example.crux/screen_share');
  
  MediaStream? _screenStream;
  bool _isSharing = false;
  RTCPeerConnection? _pc;
  String? _meetingId;
  String? _userId;

  bool get isSharing => _isSharing;
  MediaStream? get screenStream => _screenStream;

  /// Initialise le service avec les paramètres de la réunion
  void initialize(RTCPeerConnection? pc, String meetingId, String userId) {
    _pc = pc;
    _meetingId = meetingId;
    _userId = userId;
    _log.i('🎬 ScreenShareService initialisé pour la réunion: $meetingId');
  }

  /// Démarre le partage d'écran avec vérification des permissions
  Future<bool> startScreenShare() async {
    try {
      if (_isSharing) {
        _log.w('⚠️ Le partage d\'écran est déjà actif');
        return false;
      }

      if (_pc == null || _meetingId == null || _userId == null) {
        _log.e('❌ Service non initialisé correctement');
        throw Exception('Service not initialized');
      }

      // Vérifier les permissions
      if (Platform.isAndroid) {
        final status = await Permission.mediaLibrary.request();
        if (!status.isGranted) {
          _log.w('⚠️ Permission écran refusée');
          throw PermissionException('Media library permission denied');
        }
      }

      _log.i('📱 Demande de capture d\'écran en cours...');
      
      // Obtenir le flux d'écran
      _screenStream = await navigator.mediaDevices.getDisplayMedia({
        'video': {
          'cursor': 'always',  // Afficher le curseur
        },
        'audio': false,  // Pas d'audio du système
      });

      if (_screenStream == null || _screenStream!.getVideoTracks().isEmpty) {
        _log.e('❌ Impossible d\'obtenir le flux d\'écran');
        throw Exception('Failed to get screen stream');
      }

      // Remplacer la piste vidéo dans le peer connection
      final videoTrack = _screenStream!.getVideoTracks().first;
      final sender = _pc!.getSenders()
          .firstWhere((s) => s.track?.kind == 'video', orElse: () => null as dynamic);

      if (sender != null) {
        await sender.replaceTrack(videoTrack);
        _log.i('✅ Piste vidéo remplacée par l\'écran');
      } else {
        await _pc!.addTrack(videoTrack, _screenStream!);
        _log.i('✅ Piste d\'écran ajoutée au peer connection');
      }

      // Écouter la fin du partage d'écran
      _screenStream!.getVideoTracks().first.onEnded = () async {
        _log.i('🛑 Partage d\'écran terminé par l\'utilisateur');
        await stopScreenShare();
      };

      _isSharing = true;
      
      // Enregistrer dans Firestore
      await _updateScreenShareStatus(true);
      
      // Afficher la notification native
      await _showScreenShareNotification();

      _log.i('✅ Partage d\'écran démarré avec succès');
      return true;

    } on PermissionException catch (e) {
      _log.e('❌ Erreur permission: $e');
      return false;
    } catch (e) {
      _log.e('❌ Erreur lors du démarrage du partage d\'écran: $e');
      _isSharing = false;
      return false;
    }
  }

  /// Arrête le partage d'écran
  Future<bool> stopScreenShare() async {
    try {
      if (!_isSharing) {
        _log.w('⚠️ Aucun partage d\'écran en cours');
        return false;
      }

      _log.i('🛑 Arrêt du partage d\'écran...');

      // Arrêter tous les tracks
      if (_screenStream != null) {
        for (final track in _screenStream!.getTracks()) {
          await track.stop();
        }
        await _screenStream!.dispose();
        _screenStream = null;
      }

      _isSharing = false;

      // Mettre à jour Firestore
      await _updateScreenShareStatus(false);

      // Masquer la notification native
      await _hideScreenShareNotification();

      _log.i('✅ Partage d\'écran arrêté');
      return true;

    } catch (e) {
      _log.e('❌ Erreur lors de l\'arrêt du partage d\'écran: $e');
      return false;
    }
  }

  /// Met à jour le statut du partage d'écran dans Firestore
  Future<void> _updateScreenShareStatus(bool isSharing) async {
    try {
      if (_meetingId == null || _userId == null) return;

      await _db.collection('meetings')
          .doc(_meetingId)
          .collection('presence')
          .doc(_userId)
          .update({
        'isScreenSharing': isSharing,
        'screenShareStartedAt': isSharing ? FieldValue.serverTimestamp() : null,
      }).catchError((e) {
        _log.w('⚠️ Erreur mise à jour Firestore: $e');
      });
    } catch (e) {
      _log.e('❌ Erreur _updateScreenShareStatus: $e');
    }
  }

  /// Affiche une notification pour le partage d'écran
  Future<void> _showScreenShareNotification() async {
    try {
      await _screenChannel.invokeMethod('showScreenShareNotification', {
        'meetingId': _meetingId,
        'userId': _userId,
      });
    } catch (e) {
      _log.w('⚠️ Erreur notification native: $e');
    }
  }

  /// Masque la notification du partage d'écran
  Future<void> _hideScreenShareNotification() async {
    try {
      await _screenChannel.invokeMethod('hideScreenShareNotification');
    } catch (e) {
      _log.w('⚠️ Erreur masquage notification: $e');
    }
  }

  /// Obtient la liste des utilisateurs partageant leur écran
  Future<List<Map<String, dynamic>>> getScreenSharers(String meetingId) async {
    try {
      final snapshot = await _db
          .collection('meetings')
          .doc(meetingId)
          .collection('presence')
          .where('isScreenSharing', isEqualTo: true)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'userId': doc.id,
          'name': data['displayName'] ?? 'Utilisateur',
          'isScreenSharing': true,
          'startedAt': data['screenShareStartedAt'],
        };
      }).toList();
    } catch (e) {
      _log.e('❌ Erreur getScreenSharers: $e');
      return [];
    }
  }

  /// Stream pour écouter les changements du partage d'écran
  Stream<List<Map<String, dynamic>>> listenScreenSharers(String meetingId) {
    return _db
        .collection('meetings')
        .doc(meetingId)
        .collection('presence')
        .where('isScreenSharing', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'userId': doc.id,
          'name': data['displayName'] ?? 'Utilisateur',
          'isScreenSharing': true,
          'startedAt': data['screenShareStartedAt'],
        };
      }).toList();
    }).handleError((e) {
      _log.e('❌ Erreur listenScreenSharers: $e');
      return <Map<String, dynamic>>[];
    });
  }

  /// Nettoie les ressources
  Future<void> dispose() async {
    if (_isSharing) {
      await stopScreenShare();
    }
    _pc = null;
    _meetingId = null;
    _userId = null;
    _log.i('🧹 ScreenShareService nettoyé');
  }
}

/// Exception personnalisée pour les permissions
class PermissionException implements Exception {
  final String message;
  PermissionException(this.message);
  @override
  String toString() => message;
}
