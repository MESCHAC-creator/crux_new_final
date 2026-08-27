import 'package:flutter/material.dart';

import 'large_conference_screen.dart';

class VideoCallScreen extends StatelessWidget {
  final String meetingId;
  final String meetingName;
  final String userId;
  final String userName;
  final String? userEmail;
  final bool isHost;

  const VideoCallScreen({
    super.key,
    required this.meetingId,
    required this.meetingName,
    required this.userId,
    required this.userName,
    this.userEmail,
    this.isHost = false,
  });

  @override
  Widget build(BuildContext context) {
    return LargeConferenceScreen(
      meetingId: meetingId,
      meetingName: meetingName,
      userId: userId,
      userName: userName,
      userEmail: userEmail,
      isHost: isHost,
    );
  }
}
