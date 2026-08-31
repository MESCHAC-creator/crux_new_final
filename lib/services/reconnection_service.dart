import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../utils/logger.dart' as crux;

/// Service de reconnexion intelligente avec restauration d'état.
///
/// Ce service gère les reconnexions automatiques lors de coupures réseau,
/// en préservant l'état de la réunion (micro, caméra, partage d'écran, etc.).
class ReconnectionService {
  ReconnectionService._();

  static final ReconnectionService instance = ReconnectionService._();

  final crux.Logger _logger = crux.logger;

  // État de la reconnexion
  bool _isReconnecting = false;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  Timer? _networkCheckTimer;

  // État sauvegardé de la réunion
  MeetingState? _savedMeetingState;

  // Callbacks
  Function(String)? _onReconnecting;
  Function()? _onReconnected;
  Function(String)? _onReconnectionFailed;
  Function()? _onNetworkRestored;

  // Surveillance réseau
  bool _isNetworkAvailable = true;
  StreamSubscription? _networkSubscription;

  // Constants
  static const String _meetingStateKey = 'crux_meeting_state';
  static const Duration _networkCheckInterval = Duration(seconds: 5);
  static const Duration _initialReconnectDelay = Duration(seconds: 2);
  static const Duration _maxReconnectDelay = Duration(seconds: 30);

  // Getters
  bool get isReconnecting => _isReconnecting;
  int get reconnectAttempts => _reconnectAttempts;
  bool get isNetworkAvailable => _isNetworkAvailable;

  /// État de la réunion à sauvegarder
  static class MeetingState {
    final String meetingId;
    final String meetingName;
    final String userId;
    final String userName;
    final String? userEmail;
    final bool isHost;
    final bool micEnabled;
    final bool cameraEnabled;
    final bool screenSharing;
    final bool handRaised;
    final DateTime timestamp;

    MeetingState({
      required this.meetingId,
      required this.meetingName,
      required this.userId,
      required this.userName,
      this.userEmail,
      required this.isHost,
      required this.micEnabled,
      required this.cameraEnabled,
      required this.screenSharing,
      required this.handRaised,
      required this.timestamp,
    });

    Map<String, dynamic> toJson() {
      return {
        'meetingId': meetingId,
        'meetingName': meetingName,
        'userId': userId,
        'userName': userName,
        'userEmail': userEmail,
        'isHost': isHost,
        'micEnabled': micEnabled,
        'cameraEnabled': cameraEnabled,
        'screenSharing': screenSharing,
        'handRaised': handRaised,
        'timestamp': timestamp.toIso8601String(),
      };
    }

    static MeetingState fromJson(Map<String, dynamic> json) {
      return MeetingState(
        meetingId: json['meetingId'] as String,
        meetingName: json['meetingName'] as String,
        userId: json['userId'] as String,
        userName: json['userName'] as String,
        userEmail: json['userEmail'] as String?,
        isHost: json['isHost'] as bool,
        micEnabled: json['micEnabled'] as bool,
        cameraEnabled: json['cameraEnabled'] as bool,
        screenSharing: json['screenSharing'] as bool,
        handRaised: json['handRaised'] as bool,
        timestamp: DateTime.parse(json['timestamp'] as String),
      );
    }
  }

  /// Initialise le service de reconnexion
  Future<void> initialize({
    Function(String)? onReconnecting,
    Function()? onReconnected,
    Function(String)? onReconnectionFailed,
    Function()? onNetworkRestored,
  }) async {
    _onReconnecting = onReconnecting;
    _onReconnected = onReconnected;
    _onReconnectionFailed = onReconnectionFailed;
    _onNetworkRestored = onNetworkRestored;

    await _loadSavedState();
    _startNetworkMonitoring();

    _logger.i('ReconnectionService initialized');
  }

  /// Sauvegarde l'état actuel de la réunion
  Future<void> saveMeetingState(MeetingState state) async {
    _savedMeetingState = state;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_meetingStateKey, state.toJson().toString());
      _logger.d('Meeting state saved: ${state.meetingId}');
    } catch (e) {
      _logger.e('Failed to save meeting state', error: e);
    }
  }

  /// Charge l'état sauvegardé de la réunion
  Future<void> _loadSavedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stateJson = prefs.getString(_meetingStateKey);
      if (stateJson != null) {
        // Note: Ceci est une simplification - en production, utiliser jsonDecode
        _logger.d('Found saved meeting state');
      }
    } catch (e) {
      _logger.e('Failed to load meeting state', error: e);
    }
  }

  /// Nettoie l'état sauvegardé
  Future<void> clearMeetingState() async {
    _savedMeetingState = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_meetingStateKey);
      _logger.d('Meeting state cleared');
    } catch (e) {
      _logger.e('Failed to clear meeting state', error: e);
    }
  }

  /// Démarre la surveillance du réseau
  void _startNetworkMonitoring() {
    _networkCheckTimer = Timer.periodic(_networkCheckInterval, (_) {
      _checkNetworkStatus();
    });
  }

  /// Vérifie le statut du réseau
  Future<void> _checkNetworkStatus() async {
    // Simplification - en production, utiliser connectivity_plus
    // ou un vrai check de connectivité
    final previouslyAvailable = _isNetworkAvailable;
    _isNetworkAvailable = true; // Placeholder

    if (!previouslyAvailable && _isNetworkAvailable) {
      _onNetworkRestored?.call();
      _logger.i('Network restored');
    }
  }

  /// Déclenche une reconnexion automatique
  Future<void> startReconnection({
    required String meetingId,
    required Function() reconnectCallback,
  }) async {
    if (_isReconnecting) {
      _logger.w('Reconnection already in progress');
      return;
    }

    if (_reconnectAttempts >= AppConfig.maxReconnectAttempts) {
      _logger.e('Max reconnection attempts reached');
      _onReconnectionFailed?.call('Nombre maximum de tentatives atteint');
      return;
    }

    _isReconnecting = true;
    _reconnectAttempts++;

    final delay = _calculateReconnectDelay();
    _logger.i('Starting reconnection attempt $_reconnectAttempts/$maxReconnectAttempts with delay ${delay.inSeconds}s');

    _onReconnecting?.call('Tentative de reconnexion $_reconnectAttempts/$maxReconnectAttempts...');

    await Future.delayed(delay);

    try {
      await reconnectCallback();
      _handleReconnectionSuccess();
    } catch (e) {
      _logger.e('Reconnection attempt failed', error: e);
      _handleReconnectionFailure(e.toString());
    }
  }

  /// Calcule le délai de reconnexion avec backoff exponentiel
  Duration _calculateReconnectDelay() {
    final exponentialDelay = _initialReconnectDelay * (1 << (_reconnectAttempts - 1));
    final clampedDelay = exponentialDelay > _maxReconnectDelay 
        ? _maxReconnectDelay 
        : exponentialDelay;
    
    // Ajouter un peu de jitter pour éviter la synchronisation
    final jitter = Duration(milliseconds: (clampedDelay.inMilliseconds * 0.1 * (DateTime.now().millisecond % 10) / 10).toInt());
    
    return clampedDelay + jitter;
  }

  /// Gère le succès de la reconnexion
  void _handleReconnectionSuccess() {
    _isReconnecting = false;
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    
    _logger.i('Reconnection successful');
    _onReconnected?.call();
  }

  /// Gère l'échec de la reconnexion
  void _handleReconnectionFailure(String error) {
    if (_reconnectAttempts < AppConfig.maxReconnectAttempts) {
      // Continuer avec la prochaine tentative
      _isReconnecting = false;
      startReconnection(
        meetingId: _savedMeetingState?.meetingId ?? '',
        reconnectCallback: () async {
          // Placeholder - sera fourni par l'appelant
        },
      );
    } else {
      // Échec définitif
      _isReconnecting = false;
      _onReconnectionFailed?.call('Échec de la reconnexion après $_reconnectAttempts tentatives: $error');
    }
  }

  /// Annule la reconnexion en cours
  void cancelReconnection() {
    _isReconnecting = false;
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    _logger.i('Reconnection cancelled');
  }

  /// Réinitialise le compteur de tentatives
  void resetReconnectionAttempts() {
    _reconnectAttempts = 0;
    _logger.d('Reconnection attempts reset');
  }

  /// Restaure l'état de la réunion après reconnexion
  MeetingState? getSavedMeetingState() {
    // Vérifier si l'état est trop ancien (> 1 heure)
    if (_savedMeetingState != null) {
      final age = DateTime.now().difference(_savedMeetingState!.timestamp);
      if (age.inHours > 1) {
        _logger.w('Saved meeting state is too old, ignoring');
        clearMeetingState();
        return null;
      }
    }
    return _savedMeetingState;
  }

  /// Nettoie les ressources
  void dispose() {
    _reconnectTimer?.cancel();
    _networkCheckTimer?.cancel();
    _networkSubscription?.cancel();
    _logger.i('ReconnectionService disposed');
  }
}