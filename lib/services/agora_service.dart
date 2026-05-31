import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import '../config/agora_config.dart';
import 'error_handler_service.dart';

class AgoraService {
  static final AgoraService _instance = AgoraService._internal();
  late RtcEngine _engine;
  final _logger = Logger();
  final _errorHandler = ErrorHandlerService();

  bool _isInitialized = false;
  final ValueNotifier<List<int>> remoteUsers = ValueNotifier([]);
  final ValueNotifier<bool> isMuted = ValueNotifier(false);
  final ValueNotifier<bool> isCameraOff = ValueNotifier(false);

  factory AgoraService() {
    return _instance;
  }

  AgoraService._internal();

  bool get isInitialized => _isInitialized;

  Future<void> initialize(String appId) async {
    try {
      _logger.i('🚀 Initialisation Agora avec App ID: $appId');

      if (appId == 'YOUR_AGORA_APP_ID') {
        throw Exception(
          '⚠️ App ID Agora non configuré! Allez dans lib/config/agora_config.dart et remplacez YOUR_AGORA_APP_ID par votre vrai App ID depuis https://console.agora.io',
        );
      }

      _engine = createAgoraRtcEngine();

      await _engine.initialize(RtcEngineContext(
        appId: appId,
        logConfig: const LogConfig(
          level: LogLevel.logLevelInfo,
        ),
      ));

      _setupEventHandlers();
      _isInitialized = true;

      _logger.i('✅ Agora initialisé avec succès');
    } catch (e) {
      _logger.e('❌ Erreur initialisation Agora: $e');
      _errorHandler.logError('AgoraService', 'initialize: $e');
      throw Exception('❌ Impossible d\'initialiser Agora: $e');
    }
  }

  void _setupEventHandlers() {
    _engine.registerEventHandler(
      RtcEngineEventHandler(
        onError: (err, msg) {
          _logger.e('❌ Erreur Agora: $err - $msg');
          _errorHandler.logError('Agora', '[$err] $msg');
        },
        onJoinChannelSuccess: (connection, elapsed) {
          _logger.i('✅ Connecté au canal: ${connection.channelId}');
        },
        onLeaveChannel: (connection, stats) {
          _logger.i('👋 Déconnecté du canal: ${connection.channelId}');
          remoteUsers.value = [];
        },
        onUserJoined: (connection, remoteUid, elapsed) {
          _logger.i('👤 Utilisateur connecté: $remoteUid');
          final users = remoteUsers.value;
          if (!users.contains(remoteUid)) {
            users.add(remoteUid);
            remoteUsers.value = [...users];
          }
        },
        onUserOffline: (connection, remoteUid, reason) {
          _logger.i('👤 Utilisateur déconnecté: $remoteUid');
          final users = remoteUsers.value;
          users.remove(remoteUid);
          remoteUsers.value = [...users];
        },
        onTokenPrivilegeWillExpire: (connection, token) {
          _logger.w('⚠️ Token expirera bientôt');
        },
        onAudioMuted: (connection, remoteUid, muted) {
          _logger.i(muted ? '🔇 Audio muted: $remoteUid' : '🎤 Audio unmuted: $remoteUid');
        },
        onVideoStateChanged: (connection, remoteUid, state, reason, elapsed) {
          _logger.i('📹 État vidéo changé: $remoteUid - State: $state');
        },
      ),
    );
  }

  Future<void> joinChannel({
    required String token,
    required String channelName,
    required int uid,
  }) async {
    try {
      _logger.i('📞 Rejoindre canal: $channelName (UID: $uid)');

      await _engine.setChannelProfile(ChannelProfileType.channelProfileCommunication);
      await _engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);

      await _engine.joinChannel(
        token: token,
        channelId: channelName,
        uid: uid,
        options: const ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          autoSubscribeAudio: true,
          autoSubscribeVideo: true,
          publishMicrophoneTrack: true,
          publishCameraTrack: true,
        ),
      );

      _logger.i('✅ Connecté au canal avec succès');
    } catch (e) {
      _logger.e('❌ Erreur connexion: $e');
      _errorHandler.logError('AgoraService', 'joinChannel: $e');
      throw Exception('❌ Impossible de rejoindre le canal: $e');
    }
  }

  Future<void> leaveChannel() async {
    try {
      _logger.i('👋 Quitter le canal...');
      await _engine.leaveChannel();
      isMuted.value = false;
      isCameraOff.value = false;
      _logger.i('✅ Déconnecté');
    } catch (e) {
      _logger.e('❌ Erreur déconnexion: $e');
      _errorHandler.logError('AgoraService', 'leaveChannel: $e');
    }
  }

  Future<void> muteAudio(bool muted) async {
    try {
      await _engine.muteLocalAudioStream(muted);
      isMuted.value = muted;
      _logger.i(muted ? '🔇 Microphone désactivé' : '🎤 Microphone activé');
    } catch (e) {
      _logger.e('❌ Erreur micro: $e');
      _errorHandler.logError('AgoraService', 'muteAudio: $e');
    }
  }

  Future<void> muteVideo(bool muted) async {
    try {
      await _engine.muteLocalVideoStream(muted);
      isCameraOff.value = muted;
      _logger.i(muted ? '❌ Caméra désactivée' : '📹 Caméra activée');
    } catch (e) {
      _logger.e('❌ Erreur caméra: $e');
      _errorHandler.logError('AgoraService', 'muteVideo: $e');
    }
  }

  Future<void> switchCamera() async {
    try {
      await _engine.switchCamera();
      _logger.i('🔄 Caméra basculée');
    } catch (e) {
      _logger.e('❌ Erreur basculement: $e');
      _errorHandler.logError('AgoraService', 'switchCamera: $e');
    }
  }

  Future<void> enableSpeakerphone(bool enable) async {
    try {
      await _engine.setEnableSpeakerphone(enable);
      _logger.i(enable ? '🔊 Haut-parleur activé' : '🔇 Haut-parleur désactivé');
    } catch (e) {
      _logger.e('❌ Erreur haut-parleur: $e');
      _errorHandler.logError('AgoraService', 'enableSpeakerphone: $e');
    }
  }

  Future<void> setVideoQuality(String quality) async {
    try {
      Map qualitySettings = {
        'low': AgoraVideoQuality.lowQuality,
        'medium': AgoraVideoQuality.mediumQuality,
        'high': AgoraVideoQuality.highQuality,
        'ultra': AgoraVideoQuality.ultraHighQuality,
      }[quality] ?? AgoraVideoQuality.highQuality;

      await _engine.setVideoEncoderConfiguration(
        VideoEncoderConfiguration(
          dimensions: VideoDimensions(
            width: qualitySettings['width'],
            height: qualitySettings['height'],
          ),
          frameRate: qualitySettings['frameRate'],
          bitrate: qualitySettings['bitrate'],
        ),
      );

      _logger.i('✅ Qualité vidéo: $quality');
    } catch (e) {
      _logger.e('❌ Erreur qualité: $e');
      _errorHandler.logError('AgoraService', 'setVideoQuality: $e');
    }
  }

  Future<void> enableAudioVolumeIndication() async {
    try {
      await _engine.enableAudioVolumeIndication(
        interval: 100,
        smooth: 3,
        reportVad: true,
      );
      _logger.i('✅ Volume indication activé');
    } catch (e) {
      _logger.e('❌ Erreur volume: $e');
    }
  }

  Future<void> release() async {
    try {
      _logger.i('🛑 Arrêt Agora...');
      await _engine.leaveChannel();
      await _engine.release();
      _isInitialized = false;
      remoteUsers.value = [];
      _logger.i('✅ Agora arrêté');
    } catch (e) {
      _logger.e('❌ Erreur arrêt: $e');
    }
  }
}