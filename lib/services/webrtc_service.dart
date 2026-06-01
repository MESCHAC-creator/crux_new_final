import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';

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

  StreamSubscription? _sessionSub;
  StreamSubscription? _remoteCandidatesSub;

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
    _logger.i('📞 Rejoindre réunion: $meetingId (host: $isHost)');

    await _getLocalStream();
    await _createPeerConnection(meetingId);

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
      _logger.i('✅ Stream local obtenu');
    } catch (e) {
      _logger.e('❌ Erreur stream local: $e');
      // Fallback: audio only if camera unavailable
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });
      localRenderer.srcObject = _localStream;
    }
  }

  Future<void> _createPeerConnection(String meetingId) async {
    _pc = await createPeerConnection(_iceConfig);

    for (final track in _localStream!.getTracks()) {
      await _pc!.addTrack(track, _localStream!);
    }

    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams.first;
        remoteUserCount.value = 1;
        isConnected.value = true;
        _logger.i('✅ Stream distant reçu');
      }
    };

    _pc!.onIceConnectionState = (state) {
      _logger.i('ICE: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        isConnected.value = true;
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        isConnected.value = false;
        remoteUserCount.value = 0;
      }
    };
  }

  Future<void> _createOffer(String meetingId) async {
    final docRef = _sessionDoc(meetingId);

    // Clear previous session data
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

    _logger.i('📤 Offer créé et envoyé');

    // Listen for answer
    _sessionSub = docRef.snapshots().listen((snap) async {
      final data = snap.data();
      if (data?['answer'] != null &&
          _pc?.signalingState == RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
        final answer = RTCSessionDescription(
          data!['answer']['sdp'] as String,
          data['answer']['type'] as String,
        );
        await _pc!.setRemoteDescription(answer);
        _logger.i('✅ Answer reçu et appliqué');
      }
    });

    // Listen for remote ICE candidates
    _remoteCandidatesSub = docRef.collection('answerCandidates').snapshots().listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final d = change.doc.data()!;
          _pc!.addCandidate(RTCIceCandidate(
            d['candidate'] as String?,
            d['sdpMid'] as String?,
            d['sdpMLineIndex'] as int?,
          ));
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
      }
    });

    // Listen for remote ICE candidates (from host)
    _remoteCandidatesSub = docRef.collection('offerCandidates').snapshots().listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final d = change.doc.data()!;
          _pc!.addCandidate(RTCIceCandidate(
            d['candidate'] as String?,
            d['sdpMid'] as String?,
            d['sdpMLineIndex'] as int?,
          ));
        }
      }
    });
  }

  DocumentReference<Map<String, dynamic>> _sessionDoc(String meetingId) {
    return _db.collection('meetings').doc(meetingId).collection('webrtc').doc('session');
  }

  Future<void> muteAudio(bool muted) async {
    for (final track in _localStream?.getAudioTracks() ?? []) {
      track.enabled = !muted;
    }
    isMuted.value = muted;
    _logger.i(muted ? '🔇 Micro désactivé' : '🎤 Micro activé');
  }

  Future<void> muteVideo(bool muted) async {
    for (final track in _localStream?.getVideoTracks() ?? []) {
      track.enabled = !muted;
    }
    isCameraOff.value = muted;
    _logger.i(muted ? '📷 Caméra désactivée' : '📹 Caméra activée');
  }

  Future<void> switchCamera() async {
    final track = _localStream?.getVideoTracks().firstOrNull;
    if (track != null) {
      await Helper.switchCamera(track);
      _logger.i('🔄 Caméra basculée');
    }
  }

  Future<void> enableSpeakerphone(bool enable) async {
    await Helper.setSpeakerphoneOn(enable);
    _logger.i(enable ? '🔊 Haut-parleur activé' : '🔇 Haut-parleur désactivé');
  }

  Future<void> leaveMeeting(String meetingId) async {
    _sessionSub?.cancel();
    _remoteCandidatesSub?.cancel();
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
    _localStream = null;
    _pc = null;

    // Remove participant data from Firestore if host cleans up
    if (_isHost) {
      try {
        await _sessionDoc(meetingId).delete();
      } catch (_) {}
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
