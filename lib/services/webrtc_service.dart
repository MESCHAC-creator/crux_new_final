import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';
import '../utils/constants.dart';

class WebRTCService {
  static final WebRTCService _instance = WebRTCService._internal();
  factory WebRTCService() => _instance;
  WebRTCService._internal();

  final _logger = Logger();
  final _db = FirebaseFirestore.instance;

  RTCPeerConnection? _pc;
  MediaStream? _localStream;

  final localRenderer = RTCVideoRenderer();
  final remoteRenderer = RTCVideoRenderer();

  final ValueNotifier<bool> isMuted = ValueNotifier(false);
  final ValueNotifier<bool> isCameraOff = ValueNotifier(false);
  final ValueNotifier<bool> isConnected = ValueNotifier(false);
  final ValueNotifier<int> remoteUserCount = ValueNotifier(0);
  final ValueNotifier<String?> connectionError = ValueNotifier(null);

  StreamSubscription? _sessionSub;
  StreamSubscription? _remoteCandidatesSub;
  Timer? _connectionTimer;

  bool _renderersInitialized = false;
  bool _isHost = false;

  static const Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
        ]
      },
    ],
    'sdpSemantics': 'unified-plan',
  };

  Future<void> initialize() async {
    if (_renderersInitialized) return;
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    _renderersInitialized = true;
    _logger.i('✅ WebRTC renderers initialisés');
  }

  Future<void> joinMeeting({
    required String meetingId,
    required String userId,
    required bool isHost,
  }) async {
    _isHost = isHost;
    connectionError.value = null;
    _logger.i('📞 Rejoindre réunion: $meetingId (host: $isHost)');

    await _getLocalStream();

    if (_localStream == null) {
      throw Exception('Impossible d\'accéder à la caméra/microphone');
    }

    await _createPeerConnection(meetingId);

    // Timeout si pas de connexion après 30s
    _connectionTimer = Timer(AppConstants.webrtcConnectTimeout, () {
      if (!isConnected.value) {
        _logger.w('⚠️ Timeout connexion WebRTC');
        connectionError.value = 'Connexion impossible — vérifiez votre réseau';
      }
    });

    if (isHost) {
      await _createOffer(meetingId);
    } else {
      await _waitAndAnswer(meetingId);
    }
  }

  Future<void> _getLocalStream() async {
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {
          'facingMode': 'user',
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
        },
      });
      localRenderer.srcObject = _localStream;
      _logger.i('✅ Stream local (vidéo + audio)');
    } catch (e) {
      _logger.w('⚠️ Caméra indisponible, essai audio seul: $e');
      try {
        _localStream = await navigator.mediaDevices.getUserMedia({
          'audio': true,
          'video': false,
        });
        localRenderer.srcObject = _localStream;
        _logger.i('✅ Stream local (audio uniquement)');
      } catch (e2) {
        _logger.e('❌ Impossible d\'accéder aux médias: $e2');
        _localStream = null;
      }
    }
  }

  Future<void> _createPeerConnection(String meetingId) async {
    _pc = await createPeerConnection(_iceConfig);

    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await _pc!.addTrack(track, _localStream!);
      }
    }

    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams.first;
        remoteUserCount.value = 1;
        isConnected.value = true;
        connectionError.value = null;
        _connectionTimer?.cancel();
        _logger.i('✅ Stream distant reçu');
      }
    };

    _pc!.onIceConnectionState = (state) {
      _logger.i('ICE state: $state');
      switch (state) {
        case RTCIceConnectionState.RTCIceConnectionStateConnected:
        case RTCIceConnectionState.RTCIceConnectionStateCompleted:
          isConnected.value = true;
          connectionError.value = null;
          _connectionTimer?.cancel();
          break;
        case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
          isConnected.value = false;
          remoteUserCount.value = 0;
          connectionError.value = 'Participant déconnecté';
          break;
        case RTCIceConnectionState.RTCIceConnectionStateFailed:
          isConnected.value = false;
          remoteUserCount.value = 0;
          connectionError.value = 'Échec de la connexion WebRTC';
          break;
        default:
          break;
      }
    };
  }

  Future<void> _createOffer(String meetingId) async {
    final docRef = _sessionDoc(meetingId);

    await docRef.set({'createdAt': FieldValue.serverTimestamp()});

    _pc!.onIceCandidate = (candidate) {
      docRef.collection('offerCandidates').add(candidate.toMap());
    };

    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);

    await docRef.set({
      'offer': {'type': offer.type, 'sdp': offer.sdp},
      'createdAt': FieldValue.serverTimestamp(),
    });

    _logger.i('📤 Offer envoyé');

    _sessionSub = docRef.snapshots().listen((snap) async {
      final data = snap.data();
      if (data?['answer'] != null &&
          _pc?.signalingState == RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
        try {
          final answer = RTCSessionDescription(
            data!['answer']['sdp'] as String,
            data['answer']['type'] as String,
          );
          await _pc!.setRemoteDescription(answer);
          _logger.i('✅ Answer appliqué');
          _sessionSub?.cancel();
        } catch (e) {
          _logger.e('❌ Erreur setRemoteDescription: $e');
        }
      }
    });

    _remoteCandidatesSub = docRef.collection('answerCandidates').snapshots().listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          _addIceCandidate(change.doc.data()!);
        }
      }
    });
  }

  Future<void> _waitAndAnswer(String meetingId) async {
    final docRef = _sessionDoc(meetingId);

    _pc!.onIceCandidate = (candidate) {
      docRef.collection('answerCandidates').add(candidate.toMap());
    };

    _sessionSub = docRef.snapshots().listen((snap) async {
      final data = snap.data();
      if (data?['offer'] != null &&
          _pc?.signalingState == RTCSignalingState.RTCSignalingStateStable) {
        try {
          _logger.i('📥 Offer reçu, création answer...');
          final offer = RTCSessionDescription(
            data!['offer']['sdp'] as String,
            data['offer']['type'] as String,
          );
          await _pc!.setRemoteDescription(offer);

          final answer = await _pc!.createAnswer();
          await _pc!.setLocalDescription(answer);

          await docRef.update({
            'answer': {'type': answer.type, 'sdp': answer.sdp},
          });
          _logger.i('✅ Answer envoyé');
          _sessionSub?.cancel();
        } catch (e) {
          _logger.e('❌ Erreur answer: $e');
        }
      }
    });

    _remoteCandidatesSub = docRef.collection('offerCandidates').snapshots().listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          _addIceCandidate(change.doc.data()!);
        }
      }
    });
  }

  void _addIceCandidate(Map<String, dynamic> data) {
    try {
      _pc?.addCandidate(RTCIceCandidate(
        data['candidate'] as String?,
        data['sdpMid'] as String?,
        data['sdpMLineIndex'] as int?,
      ));
    } catch (e) {
      _logger.w('⚠️ ICE candidate ignoré: $e');
    }
  }

  DocumentReference<Map<String, dynamic>> _sessionDoc(String meetingId) {
    return _db.collection('meetings').doc(meetingId).collection('webrtc').doc('session');
  }

  Future<void> muteAudio(bool muted) async {
    for (final track in _localStream?.getAudioTracks() ?? []) {
      track.enabled = !muted;
    }
    isMuted.value = muted;
  }

  Future<void> muteVideo(bool muted) async {
    for (final track in _localStream?.getVideoTracks() ?? []) {
      track.enabled = !muted;
    }
    isCameraOff.value = muted;
  }

  Future<void> switchCamera() async {
    final track = _localStream?.getVideoTracks().firstOrNull;
    if (track != null) {
      await Helper.switchCamera(track);
    }
  }

  Future<void> enableSpeakerphone(bool enable) async {
    await Helper.setSpeakerphoneOn(enable);
  }

  Future<void> leaveMeeting(String meetingId) async {
    _connectionTimer?.cancel();
    _sessionSub?.cancel();
    _remoteCandidatesSub?.cancel();
    _connectionTimer = null;
    _sessionSub = null;
    _remoteCandidatesSub = null;

    for (final track in _localStream?.getTracks() ?? []) {
      track.stop();
    }
    await _localStream?.dispose();
    await _pc?.close();

    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;

    isMuted.value = false;
    isCameraOff.value = false;
    isConnected.value = false;
    remoteUserCount.value = 0;
    connectionError.value = null;
    _localStream = null;
    _pc = null;

    if (_isHost && meetingId.isNotEmpty) {
      try {
        await _sessionDoc(meetingId).delete();
      } catch (e) {
        _logger.w('⚠️ Nettoyage Firestore: $e');
      }
    }

    _logger.i('👋 Réunion quittée');
  }

  Future<void> dispose() async {
    await leaveMeeting('');
    if (_renderersInitialized) {
      await localRenderer.dispose();
      await remoteRenderer.dispose();
      _renderersInitialized = false;
    }
  }
}
