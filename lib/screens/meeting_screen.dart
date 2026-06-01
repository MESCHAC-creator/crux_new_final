import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../theme/colors.dart';
import '../services/meeting_service.dart';
import '../models/meeting_model.dart';

class MeetingScreen extends StatefulWidget {
  final String meetingId;
  final String meetingName;
  final String userId;
  final String userName;
  final String? userEmail;
  final bool isHost;

  const MeetingScreen({
    super.key,
    required this.meetingId,
    required this.meetingName,
    required this.userId,
    required this.userName,
    this.userEmail,
    this.isHost = false,
  });

  @override
  State<MeetingScreen> createState() => _MeetingScreenState();
}

class _MeetingScreenState extends State<MeetingScreen> {
  final _meetingService = MeetingService();
  bool _inMeeting = false;
  bool _isLoading = false;
  WebViewController? _webController;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      await _meetingService.addParticipant(widget.meetingId, widget.userId);
      if (widget.isHost) {
        await _meetingService.updateMeetingStatus(widget.meetingId, MeetingStatus.ongoing);
      }
    } catch (_) {}
  }

  void _startMeeting() {
    setState(() { _isLoading = true; });

    final roomName = 'CRUX-${widget.meetingId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')}';
    final encodedName = Uri.encodeComponent(widget.userName);

    // Build Jitsi Meet URL with config to hide toolbar branding and auto-join
    final meetUrl =
        'https://meet.jit.si/$roomName'
        '#userInfo.displayName="$encodedName"'
        '&config.startWithAudioMuted=false'
        '&config.startWithVideoMuted=false'
        '&config.prejoinPageEnabled=false'
        '&config.disableDeepLinking=true';

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => _isLoading = true),
        onPageFinished: (_) => setState(() => _isLoading = false),
        onWebResourceError: (_) => setState(() => _isLoading = false),
      ))
      ..loadRequest(Uri.parse(meetUrl));

    setState(() {
      _webController = controller;
      _inMeeting = true;
    });
  }

  void _copyId() {
    Clipboard.setData(ClipboardData(text: widget.meetingId));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('ID copié !', style: GoogleFonts.poppins()),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _endMeeting() {
    _meetingService.removeParticipant(widget.meetingId, widget.userId);
    if (widget.isHost) {
      _meetingService.updateMeetingStatus(widget.meetingId, MeetingStatus.ended);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_inMeeting && _webController != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              WebViewWidget(controller: _webController!),
              if (_isLoading)
                const Center(child: CircularProgressIndicator(color: Colors.white)),
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(24),
                  child: IconButton(
                    icon: const Icon(Icons.call_end, color: Colors.red),
                    tooltip: 'Quitter',
                    onPressed: _endMeeting,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A1A2E), Color(0xFF16213E), Color(0xFF0F3460)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: _endMeeting,
                      icon: const Icon(Icons.arrow_back_ios, color: Colors.white70),
                    ),
                    Expanded(
                      child: Text(
                        widget.meetingName,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.isHost)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.primary, width: 1),
                        ),
                        child: Text(
                          'HÔTE',
                          style: GoogleFonts.poppins(
                            color: AppColors.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(45),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.4),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.videocam, color: Colors.white, size: 44),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Réunion prête',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Appuyez sur "Rejoindre" pour démarrer la visioconférence directement dans l\'application.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          color: Colors.white60,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      GestureDetector(
                        onTap: _copyId,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withOpacity(0.15)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.tag, color: Colors.white54, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                widget.meetingId.length > 16
                                    ? widget.meetingId.substring(0, 16)
                                    : widget.meetingId,
                                style: GoogleFonts.poppins(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.copy, color: Colors.white38, size: 14),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _startMeeting,
                    icon: const Icon(Icons.videocam, size: 22),
                    label: Text(
                      'Rejoindre la réunion',
                      style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 8,
                      shadowColor: AppColors.primary.withOpacity(0.5),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: _endMeeting,
                  icon: const Icon(Icons.exit_to_app, color: Colors.white38, size: 18),
                  label: Text(
                    'Quitter sans rejoindre',
                    style: GoogleFonts.poppins(color: Colors.white38, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
