import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import '../theme/colors.dart';
import '../services/meeting_service.dart';
import '../models/meeting_model.dart';
import '../providers/locale_provider.dart';
import '../l10n/app_translations.dart';
import 'video_call_screen.dart';

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

  void _copyId() {
    final lang = context.read<LocaleProvider>().locale.languageCode;
    Clipboard.setData(ClipboardData(text: widget.meetingId));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppTranslations.t('id_copied', lang), style: GoogleFonts.poppins()),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _shareMeeting() {
    final lang = context.read<LocaleProvider>().locale.languageCode;
    final text = AppTranslations.t('share_meeting_msg', lang)
        .replaceAll('{name}', widget.meetingName)
        .replaceAll('{code}', widget.meetingId);
    final subject = AppTranslations.t('share_meeting_subject', lang)
        .replaceAll('{name}', widget.meetingName);
    Share.share(text, subject: subject);
  }

  void _endMeeting() {
    _meetingService.removeParticipant(widget.meetingId, widget.userId);
    if (widget.isHost) {
      _meetingService.updateMeetingStatus(widget.meetingId, MeetingStatus.ended);
    }
    Navigator.pop(context);
  }

  Future<void> _joinCall() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoCallScreen(
          meetingId: widget.meetingId,
          userId: widget.userId,
          userName: widget.userName,
          isHost: widget.isHost,
        ),
      ),
    );
    // When the call ends, also pop this lobby screen
    if (mounted) _endMeeting();
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LocaleProvider>().locale.languageCode;
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
                // Header
                Row(
                  children: [
                    IconButton(
                      onPressed: _endMeeting,
                      icon: const Icon(Icons.arrow_back_ios, color: Colors.white70),
                    ),
                    Expanded(
                      child: Text(
                        widget.meetingName,
                        style: GoogleFonts.poppins(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.isHost)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.primary, width: 1),
                        ),
                        child: Text(
                          AppTranslations.t('host', lang),
                          style: GoogleFonts.poppins(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _shareMeeting,
                      icon: const Icon(Icons.share_rounded, color: Colors.white70, size: 22),
                      tooltip: AppTranslations.t('share', lang),
                    ),
                  ],
                ),

                const Spacer(),

                // Info card
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
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
                            BoxShadow(color: AppColors.primary.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 8)),
                          ],
                        ),
                        child: const Icon(Icons.videocam, color: Colors.white, size: 44),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        AppTranslations.t('meeting_ready', lang),
                        style: GoogleFonts.poppins(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppTranslations.t('meeting_desc', lang),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(color: Colors.white60, fontSize: 13, height: 1.5),
                      ),
                      const SizedBox(height: 20),

                      // Meeting ID
                      GestureDetector(
                        onTap: _copyId,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
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
                                  color: Colors.white70, fontSize: 13,
                                  fontWeight: FontWeight.w600, letterSpacing: 1,
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

                // Join button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _joinCall,
                    icon: const Icon(Icons.videocam, size: 22),
                    label: Text(
                      AppTranslations.t('join_btn', lang),
                      style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 8,
                      shadowColor: AppColors.primary.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: _endMeeting,
                  icon: const Icon(Icons.exit_to_app, color: Colors.white38, size: 18),
                  label: Text(AppTranslations.t('leave', lang), style: GoogleFonts.poppins(color: Colors.white38, fontSize: 13)),
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
