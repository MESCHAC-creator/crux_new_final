import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../wallpaper/wallpaper_config.dart';
import '../wallpaper/app_background.dart';
import '../video/virtual_background_controller.dart';
import '../video/background_panel.dart';
import 'meeting_state.dart';
import 'meeting_header.dart';
import 'call_controls_bar.dart';
import 'participant_tile.dart';
import 'chat_panel.dart';

/// Écran principal de réunion CRUX.
/// Grille adaptative + overlay des participants pendant le partage d'écran.
class CruxMeetingScreen extends StatefulWidget {
  final String meetingId;
  final String meetingName;
  final String userId;
  final String userName;
  final String? userEmail;
  final bool isHost;
  final WallpaperConfig wallpaper;

  const CruxMeetingScreen({
    super.key,
    required this.meetingId,
    required this.meetingName,
    required this.userId,
    required this.userName,
    this.userEmail,
    this.isHost = false,
    required this.wallpaper,
  });

  @override
  State<CruxMeetingScreen> createState() => _CruxMeetingScreenState();
}

class _CruxMeetingScreenState extends State<CruxMeetingScreen> {
  final List<ChatMessage> _messages = [];
  final int _elapsedSeconds = 0;
  bool _micOn = true;
  bool _camOn = true;
  bool _showChat = false;
  final List<ParticipantUi> _participants = [];
  ParticipantUi? _screenShare;
  final CallHealth _health = const CallHealth();

  @override
  void initState() {
    super.initState();
    _initRoom();
  }

  Future<void> _initRoom() async {
    // TODO: Connecter à LiveKit via LiveKitService
    // Ceci est un stub pour l'intégration
  }

  void _toggleMic() => setState(() => _micOn = !_micOn);
  void _toggleCamera() => setState(() => _camOn = !_camOn);

  void _sendMessage(String body, String? recipientSid) {
    setState(() {
      _messages.add(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        senderSid: widget.userId,
        senderName: widget.userName,
        body: body,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        recipientSid: recipientSid,
        fromMe: true,
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    final bgController = context.watch<VirtualBackgroundController>();

    return AppBackground(
      config: widget.wallpaper,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                MeetingHeader(
                  elapsedSeconds: _elapsedSeconds,
                  roomUrl:
                      'https://crux-3c6be.web.app/join/${widget.meetingId}',
                  health: _health,
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _screenShare != null
                      ? _ScreenShareLayout(
                          screenShare: _screenShare!,
                          participants: _participants,
                        )
                      : _GridLayout(participants: _participants),
                ),
                const SizedBox(height: 8),
                BackgroundPanel(controller: bgController),
                const SizedBox(height: 8),
                CallControlsBar(
                  micEnabled: _micOn,
                  cameraEnabled: _camOn,
                  onToggleMic: _toggleMic,
                  onToggleCamera: _toggleCamera,
                  onShareScreen: () {},
                  onOpenChat: () => setState(() => _showChat = !_showChat),
                  onLeave: () => Navigator.pop(context),
                  secondaryActions: [
                    SecondaryAction(
                      icon: Icons.wallpaper,
                      label: 'Fond d\'écran',
                      description: 'Choisir une image et régler le flou',
                      onClick: () => Navigator.pushNamed(context, '/wallpaper'),
                    ),
                    SecondaryAction(
                      icon: Icons.pan_tool,
                      label: 'Lever la main',
                      description: 'Signaler que vous voulez parler',
                      onClick: () {},
                    ),
                    SecondaryAction(
                      icon: Icons.closed_caption,
                      label: 'Sous-titres',
                      description: 'Transcription en direct',
                      onClick: () {},
                    ),
                    SecondaryAction(
                      icon: Icons.poll,
                      label: 'Sondage',
                      description: 'Lancer un vote rapide',
                      onClick: () {},
                    ),
                    SecondaryAction(
                      icon: Icons.meeting_room,
                      label: 'Salles de groupe',
                      description: 'Répartir les participants',
                      onClick: () {},
                    ),
                  ],
                ),
                if (_showChat) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 250,
                    child: ChatPanel(
                      messages: _messages,
                      participants: _participants,
                      onSend: _sendMessage,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GridLayout extends StatelessWidget {
  final List<ParticipantUi> participants;

  const _GridLayout({required this.participants});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        childAspectRatio: 4 / 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: participants.length,
      itemBuilder: (context, index) =>
          ParticipantTile(participant: participants[index]),
    );
  }
}

class _ScreenShareLayout extends StatelessWidget {
  final ParticipantUi screenShare;
  final List<ParticipantUi> participants;

  const _ScreenShareLayout({
    required this.screenShare,
    required this.participants,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Contenu partagé en grand
        ParticipantTile(participant: screenShare),
        // Les visages restent visibles — Meet ne le permet pas
        Positioned(
          bottom: 8,
          left: 8,
          right: 8,
          child: SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: participants.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: SizedBox(
                  width: 120,
                  child: ParticipantTile(participant: participants[index]),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
