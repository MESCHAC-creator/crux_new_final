import 'package:url_launcher/url_launcher.dart';
import 'package:logger/logger.dart';

class MeetingLaunchService {
  static final MeetingLaunchService _instance = MeetingLaunchService._internal();
  factory MeetingLaunchService() => _instance;
  MeetingLaunchService._internal();

  final _logger = Logger();

  // Opens meet.jit.si in the device browser — works on all Android devices, no native SDK needed.
  Future<void> joinMeeting({
    required String meetingId,
    required String displayName,
    String? email,
  }) async {
    final roomName = 'CRUX-${meetingId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')}';
    final encodedName = Uri.encodeComponent(displayName);
    final uri = Uri.parse(
      'https://meet.jit.si/$roomName#userInfo.displayName="$encodedName"&config.startWithAudioMuted=false&config.startWithVideoMuted=false',
    );

    _logger.i('🎥 Launching meeting: $uri');

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      throw Exception('Impossible d\'ouvrir le navigateur pour la réunion');
    }
  }
}
