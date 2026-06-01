import 'package:jitsi_meet_flutter_sdk/jitsi_meet_flutter_sdk.dart';
import 'package:logger/logger.dart';

class JitsiService {
  static final JitsiService _instance = JitsiService._internal();
  factory JitsiService() => _instance;
  JitsiService._internal();

  final _logger = Logger();
  final _jitsi = JitsiMeet();

  static const String _serverUrl = 'https://meet.jit.si';

  Future<void> joinMeeting({
    required String meetingId,
    required String displayName,
    String? email,
    bool startWithAudioMuted = false,
    bool startWithVideoMuted = false,
  }) async {
    _logger.i('📞 Rejoindre réunion Jitsi: $meetingId');

    final options = JitsiMeetConferenceOptions(
      serverURL: _serverUrl,
      room: meetingId,
      configOverrides: {
        'startWithAudioMuted': startWithAudioMuted,
        'startWithVideoMuted': startWithVideoMuted,
        'subject': meetingId,
        'prejoinPageEnabled': false,
        'disableDeepLinking': true,
      },
      featureFlags: {
        'unsaferoomwarning.enabled': false,
        'welcomepage.enabled': false,
        'invite.enabled': false,
        'call-integration.enabled': false,
        'pip.enabled': true,
      },
      userInfo: JitsiMeetUserInfo(
        displayName: displayName,
        email: email,
      ),
    );

    final listener = JitsiMeetEventListener(
      conferenceJoined: (url) => _logger.i('✅ Conférence rejointe: $url'),
      conferenceTerminated: (url, error) => _logger.i('👋 Conférence terminée: $url'),
      conferenceWillJoin: (url) => _logger.i('🔗 Connexion: $url'),
    );

    await _jitsi.join(options, listener);
    _logger.i('✅ Jitsi lancé');
  }

  Future<void> hangUp() async {
    try {
      await _jitsi.hangUp();
      _logger.i('📴 Appel raccroché');
    } catch (e) {
      _logger.w('⚠️ hangUp: $e');
    }
  }

  Future<void> setAudioMuted(bool muted) async {
    try {
      await _jitsi.setAudioMuted(muted);
    } catch (e) {
      _logger.w('⚠️ setAudioMuted: $e');
    }
  }

  Future<void> setVideoMuted(bool muted) async {
    try {
      await _jitsi.setVideoMuted(muted);
    } catch (e) {
      _logger.w('⚠️ setVideoMuted: $e');
    }
  }
}
