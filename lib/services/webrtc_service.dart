import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:logger/logger.dart';

/// WebRTC peer-to-peer video call using Firestore as signaling channel.
///
/// Room structure in Firestore:
///   webrtc_rooms/{roomId}
///     offer            : {type, sdp}
///     answer           : {type, sdp}
///     offerCandidates  : subcollection
///     answerCandidates : subcollection
class WebRTCService {
  static final WebRTCService _instance = WebRTCService._internal();
  factory WebRTCService() => _instance;
  WebRTCService._internal();

  final _db = FirebaseFirestore.instance;
  final _log = Logger();

  static const _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
  };

  RTCPeerConnection? _pc;
  MediaStream? _localStream;

  // Exposed so the UI can render them
  MediaStream? get localStream => _localStream;
  MediaStream? remoteStream;

  // Callbacks the screen listens to
  void Function(MediaStream)? onRemoteStream;
  void Function()? onCallEnded;

  bool _isCaller = false;

  /// Opens the camera/mic and returns the local stream.
  Future<MediaStream> openMedia() async {
    _localStream = await navigator.mediaDevices.getUserMedia({
      'video': {'facingMode': 'user'},
      'audio': true,
    });
    return _localStream!;
  }

  /// Caller side — creates a room and sends the WebRTC offer.
  Future<void> createRoom(String roomId) async {
    _isCaller = true;
    final roomRef = _db.collection('webrtc_rooms').doc(roomId);
    await roomRef.set({'status': 'waiting', 'createdAt': FieldValue.serverTimestamp()});

    _pc = await _buildPeerConnection(
      onIceCandidate: (c) {
        roomRef.collection('offerCandidates').add(c.toMap());
      },
    );

    _localStream?.getTracks().forEach((t) => _pc!.addTrack(t, _localStream!));

    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    await roomRef.update({'offer': {'type': offer.type, 'sdp': offer.sdp}});

    _log.i('🔵 Room created: $roomId');

    // Listen for the callee's answer
    roomRef.snapshots().listen((snap) async {
      final data = snap.data();
      if (data == null) return;
      final answer = data['answer'];
      if (answer != null && _pc!.signalingState != RTCSignalingState.RTCSignalingStateStable) {
        await _pc!.setRemoteDescription(
          RTCSessionDescription(answer['sdp'], answer['type']),
        );
      }
      if (data['status'] == 'ended') onCallEnded?.call();
    });

    // Receive callee ICE candidates
    roomRef.collection('answerCandidates').snapshots().listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          _pc!.addCandidate(_mapToCandidate(change.doc.data()!));
        }
      }
    });
  }

  /// Callee side — joins a room and sends the WebRTC answer.
  Future<bool> joinRoom(String roomId) async {
    _isCaller = false;
    final roomRef = _db.collection('webrtc_rooms').doc(roomId);
    final snap = await roomRef.get();
    if (!snap.exists || snap.data()?['offer'] == null) return false;

    _pc = await _buildPeerConnection(
      onIceCandidate: (c) {
        roomRef.collection('answerCandidates').add(c.toMap());
      },
    );

    _localStream?.getTracks().forEach((t) => _pc!.addTrack(t, _localStream!));

    final offer = snap.data()!['offer'];
    await _pc!.setRemoteDescription(RTCSessionDescription(offer['sdp'], offer['type']));

    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);
    await roomRef.update({
      'answer': {'type': answer.type, 'sdp': answer.sdp},
      'status': 'ongoing',
    });

    _log.i('🟢 Joined room: $roomId');

    // Receive caller ICE candidates
    roomRef.collection('offerCandidates').snapshots().listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          _pc!.addCandidate(_mapToCandidate(change.doc.data()!));
        }
      }
    });

    // Listen for end signal
    roomRef.snapshots().listen((s) {
      if (s.data()?['status'] == 'ended') onCallEnded?.call();
    });

    return true;
  }

  Future<RTCPeerConnection> _buildPeerConnection({
    required void Function(RTCIceCandidate) onIceCandidate,
  }) async {
    final pc = await createPeerConnection(_iceServers);

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate != null) onIceCandidate(candidate);
    };

    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        remoteStream = event.streams[0];
        onRemoteStream?.call(event.streams[0]);
      }
    };

    pc.onConnectionState = (state) {
      _log.i('🔗 Connection: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        onCallEnded?.call();
      }
    };

    return pc;
  }

  RTCIceCandidate _mapToCandidate(Map<String, dynamic> m) =>
      RTCIceCandidate(m['candidate'], m['sdpMid'], m['sdpMLineIndex']);

  Future<void> toggleMic() async {
    final track = _localStream?.getAudioTracks().firstOrNull;
    if (track != null) track.enabled = !track.enabled;
  }

  Future<void> toggleCamera() async {
    final track = _localStream?.getVideoTracks().firstOrNull;
    if (track != null) track.enabled = !track.enabled;
  }

  Future<void> switchCamera() async {
    final track = _localStream?.getVideoTracks().firstOrNull;
    if (track != null) await Helper.switchCamera(track);
  }

  Future<void> hangUp(String roomId) async {
    try {
      await _db.collection('webrtc_rooms').doc(roomId).update({'status': 'ended'});
    } catch (_) {}
    await _dispose();
  }

  Future<void> _dispose() async {
    _localStream?.getTracks().forEach((t) => t.stop());
    await _localStream?.dispose();
    await _pc?.close();
    _localStream = null;
    _pc = null;
    remoteStream = null;
  }
}
