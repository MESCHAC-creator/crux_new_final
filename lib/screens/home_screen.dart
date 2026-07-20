import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/crux.logger.dart' as crux;
import '../theme/colors.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/meeting_service.dart';
import '../services/error_handler_service.dart';
import '../services/user_service.dart';
import '../screens/meeting_screen.dart';
import '../providers/locale_provider.dart';
import '../l10n/app_translations.dart';
import 'large_conference_screen.dart';

class HomeScreen extends StatefulWidget {
  final UserModel user;
  const HomeScreen({super.key, required this.user});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _authService = AuthService();
  final _meetingService = MeetingService();
  final _errorHandler = ErrorHandlerService();
  final _meetingNameController = TextEditingController();
  final _joinIdController = TextEditingController();
  final _passcodeController = TextEditingController();
  final _schedTitleController = TextEditingController();
  final _schedDescController = TextEditingController();
  final _schedPasscodeController = TextEditingController();
  bool _showPasscode = false;
  bool _obscurePasscode = true;
  bool _isLargeConference = false; // true → LiveKit SFU (1000+ participants)
  String? _localPhotoPath;
  int _currentTab = 0;

  @override
  void initState() {
    super.initState();
    _loadLocalPhoto();
  }

  @override
  void dispose() {
    _meetingNameController.dispose();
    _joinIdController.dispose();
    _passcodeController.dispose();
    _schedTitleController.dispose();
    _schedDescController.dispose();
    _schedPasscodeController.dispose();
    super.dispose();
  }

  Future<void> _loadLocalPhoto() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('crux_local_photo_path');
    if (path != null && File(path).existsSync()) {
      if (mounted) setState(() => _localPhotoPath = path);
      return;
    }
    // Fallback: try to load from Firestore
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final profile = await UserService.instance.getProfile(uid);
      final b64 = profile?['photoBase64'] as String?;
      if (b64 != null && b64.isNotEmpty && mounted) {
        final bytes = UserService.decodePhoto(b64);
        if (bytes != null) {
          final dir = await getApplicationDocumentsDirectory();
          final dest = '${dir.path}/profile_photo.jpg';
          await File(dest).writeAsBytes(bytes);
          await prefs.setString('crux_local_photo_path', dest);
          if (mounted) setState(() => _localPhotoPath = dest);
        }
      }
    } catch (e) {
      crux.logger.e('_loadLocalPhoto error', error: e);
    }
  }

  String _displayName() {
    try {
      final fb = FirebaseAuth.instance.currentUser;
      if (fb?.displayName?.trim().isNotEmpty == true) return fb!.displayName!;
      if (fb?.email?.isNotEmpty == true && fb!.email!.contains('@')) return fb.email!.split('@')[0];
      return widget.user?.name ?? 'Utilisateur';
    } catch (e) {
      crux.logger.e('_displayName error', error: e);
      return 'Utilisateur';
    }
  }

  Future<void> _createMeeting() async {
    final lang = context.read<LocaleProvider>().locale.languageCode;
    final name = _meetingNameController.text.trim();
    if (name.isEmpty) {
      _errorHandler.showErrorDialog(
        context,
        '⚠️ ${AppTranslations.t('attention', lang)}',
        AppTranslations.t('meet_enter_name', lang),
      );
      return;
    }

    final rawPasscode = _showPasscode ? _passcodeController.text.trim() : null;
    if (rawPasscode != null && rawPasscode.isNotEmpty) {
      if (rawPasscode.length < 4 || rawPasscode.length > 6) {
        _errorHandler.showErrorDialog(
          context,
          '⚠️ ${AppTranslations.t('attention', lang)}',
          AppTranslations.t('meet_code_range', lang),
        );
        return;
      }
      if (!RegExp(r'^\d+$').hasMatch(rawPasscode)) {
        _errorHandler.showErrorDialog(
          context,
          '⚠️ ${AppTranslations.t('attention', lang)}',
          AppTranslations.t('meet_code_digits', lang),
        );
        return;
      }
    }

    try {
      final meetingId = await _meetingService.createMeeting(
        title: name,
        description: '',
        organizerName: _displayName(),
        organizerId: widget.user.uid,
        passcode: rawPasscode?.isNotEmpty == true ? rawPasscode : null,
        isLargeConference: true, // Forcé à true pour SFU
      );
      _meetingNameController.clear();
      _passcodeController.clear();
      setState(() {
        _showPasscode = false;
        _isLargeConference = false;
      });
      if (!mounted) return;
      Navigator.pop(context); // fermer le sheet
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LargeConferenceScreen(
            meetingId: meetingId,
            meetingName: name,
            userId: widget.user.uid,
            userName: _displayName(),
            userEmail: widget.user.email,
            isHost: true,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        final lang = context.read<LocaleProvider>().locale.languageCode;
        _errorHandler.showErrorDialog(
          context,
          '❌ ${AppTranslations.t('error', lang)}',
          _errorHandler.getMeetingErrorMessageL(
            e.toString().replaceFirst('Exception: ', ''),
            lang,
          ),
        );
      }
    } finally {}
  }

  Future<void> _joinById(String id) async {
    if (id.isEmpty) return;
    // Accept both raw codes and full deep-link URLs (crux://join/CODE)
    String raw = id.trim();
    if (raw.startsWith('crux://join/')) {
      raw = raw.substring('crux://join/'.length);
    } else if (raw.contains('/join/')) {
      raw = raw.split('/join/').last;
    }
    final cleanId = raw
        .toUpperCase()
        .split('?')
        .first; // strip any query params
    final lang = context.read<LocaleProvider>().locale.languageCode;

    final meeting = await _meetingService.getMeetingOnce(cleanId);
    if (!mounted) return;

    if (meeting == null) {
      _errorHandler.showErrorDialog(
        context,
        '🔍 ${AppTranslations.t('error', lang)}',
        AppTranslations.t('meet_not_found', lang),
      );
      return;
    }

    if (meeting.passcode != null && meeting.passcode!.isNotEmpty) {
      final entered = await _showPasscodePrompt();
      if (!mounted) return;
      if (entered == null) return;
      if (entered != meeting.passcode) {
        if (mounted) {
          _errorHandler.showErrorDialog(
            context,
            '🔒 ${AppTranslations.t('error', lang)}',
            AppTranslations.t('meet_wrong_code', lang),
          );
        }
        return;
      }
    }

    if (!mounted) return;
    if (meeting.isLargeConference) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LargeConferenceScreen(
            meetingId: cleanId,
            meetingName: meeting.title,
            userId: widget.user.uid,
            userName: _displayName(),
            userEmail: widget.user.email,
            isHost: false,
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MeetingScreen(
            meetingId: cleanId,
            meetingName: meeting.title,
            userId: widget.user.uid,
            userName: _displayName(),
            userEmail: widget.user.email,
            isHost: false,
          ),
        ),
      );
    }
  }

  Future<String?> _showPasscodePrompt() async {
    final ctrl = TextEditingController();
    final lang = context.read<LocaleProvider>().locale.languageCode;
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.lock_outline,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              AppTranslations.t('passcode_title', lang),
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 17,
                color: Colors.white,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppTranslations.t('passcode_protected', lang),
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              style: GoogleFonts.poppins(
                color: Colors.white,
                letterSpacing: 4,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white.withOpacity(0.08),
                hintText: AppTranslations.t('passcode_hint', lang),
                hintStyle: GoogleFonts.poppins(
                  color: Colors.white38,
                  letterSpacing: 0,
                ),
                prefixIcon: const Icon(
                  Icons.lock_outline,
                  color: AppColors.primary,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppColors.primary,
                    width: 2,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              AppTranslations.t('cancel', lang),
              style: GoogleFonts.poppins(color: Colors.white38),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              AppTranslations.t('enter_btn', lang),
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _logout() {
    final lang = context.read<LocaleProvider>().locale.languageCode;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          AppTranslations.t('logout', lang),
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
        content: Text(
          AppTranslations.t('logout_confirm', lang),
          style: GoogleFonts.poppins(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppTranslations.t('cancel', lang)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid != null) {
                FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .set({
                      'status': 'offline',
                      'lastSeen': FieldValue.serverTimestamp(),
                    }, SetOptions(merge: true))
                    .catchError((_) {});
              }
              await _authService.signOut();
              if (mounted) Navigator.of(context).pushReplacementNamed('/login');
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: Text(
              AppTranslations.t('logout', lang),
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Bonjour';
    if (h < 18) return 'Bon après-midi';
    return 'Bonsoir';
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LocaleProvider>().locale.languageCode;
    final displayName = _displayName();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildTopBar(displayName, lang),
      body: IndexedStack(
        index: _currentTab,
        children: [
          _buildHomeTab(lang),
          _buildChatTab(),
          _buildMeetingsTab(lang),
          const SizedBox.shrink(), // Profil → push
          const SizedBox.shrink(), // Plus → sheet
        ],
      ),
      bottomNavigationBar: _buildBottomNav(lang),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────

  AppBar _buildTopBar(String displayName, String lang) {
    final titles = ['CRUX', 'Chat', 'Réunions', 'CRUX', 'CRUX'];
    return AppBar(
      backgroundColor: const Color(0xFF0A0E1A),
      elevation: 0,
      titleSpacing: 0,
      leading: GestureDetector(
        onTap: () => Navigator.pushNamed(
          context,
          '/profile',
        ).then((_) => _loadLocalPhoto()),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primary,
            backgroundImage: _localPhotoPath != null
                ? FileImage(File(_localPhotoPath!))
                : null,
            child: _localPhotoPath == null
                ? Text(
                    displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                    style: const TextStyle(
                      color: Colors.black, // Dark text on Electric Cyan
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  )
                : null,
          ),
        ),
      ),
      title: Text(
        titles[_currentTab],
        style: GoogleFonts.spaceGrotesk(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 20,
          letterSpacing: _currentTab == 0 ? 1.5 : 0.5,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.search, color: Colors.white54, size: 22),
          onPressed: () => _showJoinDialog(lang),
        ),
        IconButton(
          icon: const Icon(Icons.more_horiz, color: Colors.white54, size: 22),
          onPressed: () => _showMainMenu(lang),
        ),
      ],
    );
  }

  // ── Bottom nav ─────────────────────────────────────────────────────────────

  Widget _buildBottomNav(String lang) {
    return BottomNavigationBar(
      backgroundColor: const Color(0xFF12121E),
      selectedItemColor: const Color(0xFFE53935),
      unselectedItemColor: Colors.white30,
      selectedLabelStyle: GoogleFonts.poppins(
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelStyle: GoogleFonts.poppins(fontSize: 10),
      type: BottomNavigationBarType.fixed,
      currentIndex: _currentTab.clamp(0, 2), // max 3 real tabs
      onTap: (i) {
        if (i == 3) {
          Navigator.pushNamed(
            context,
            '/profile',
          ).then((_) => _loadLocalPhoto());
        } else if (i == 4) {
          _showMainMenu(lang);
        } else {
          setState(() => _currentTab = i);
        }
      },
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined),
          activeIcon: Icon(Icons.home),
          label: 'Accueil',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.chat_bubble_outline),
          activeIcon: Icon(Icons.chat_bubble),
          label: 'Chat',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.video_camera_front_outlined),
          activeIcon: Icon(Icons.video_camera_front),
          label: 'Réunions',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person_outline),
          activeIcon: Icon(Icons.person),
          label: 'Profil',
        ),
        BottomNavigationBarItem(icon: Icon(Icons.more_horiz), label: 'Plus'),
      ],
    );
  }

  // ── Onglet 0 : Accueil ─────────────────────────────────────────────────────

  Widget _buildHomeTab(String lang) {
    final displayName = _displayName();
    return RefreshIndicator(
      onRefresh: () async {
        setState(() {});
        await _loadLocalPhoto();
      },
      color: AppColors.primary,
      backgroundColor: const Color(0xFF1A1A2E),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Salutation ──
            _buildGreetingHeader(displayName),
            const SizedBox(height: 24),
            // ── Bento Grid layout (Actions rapides & IA) ──
            _buildBentoGrid(lang),
            const SizedBox(height: 28),
            // ── Réunions récentes ──
            _buildRecentMeetings(lang),
          ],
        ),
      ),
    );
  }

  Widget _buildGreetingHeader(String displayName) {
    final firstName = displayName.split(' ').first;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_greeting()}, $firstName 👋',
                style: GoogleFonts.spaceGrotesk(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Prêt pour votre prochaine réunion ?',
                style: GoogleFonts.interTight(color: const Color(0xFF8A8FA3), fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBentoGrid(String lang) {
    return Column(
      children: [
        // AI Banner Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF121624),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.12), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00E5FF).withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF00E5FF),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFF00E5FF),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "CO-PILOTE IA ACTIF",
                    style: GoogleFonts.spaceGrotesk(
                      color: const Color(0xFF00E5FF),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                "Résumés intelligents & Actions",
                style: GoogleFonts.spaceGrotesk(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "L'IA analyse vos réunions en temps réel pour générer des comptes-rendus structurés et des actions assignées automatiquement.",
                style: GoogleFonts.interTight(
                  color: const Color(0xFF8A8FA3),
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Row of main action cards (Bento Grid)
        Row(
          children: [
            // Left block - New Meeting (Large)
            Expanded(
              flex: 11,
              child: GestureDetector(
                onTap: () => _showNewMeetingSheet(lang),
                child: Container(
                  height: 130,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF00E5FF), Color(0xFF7C5CFF)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00E5FF).withOpacity(0.2),
                        blurRadius: 15,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Icon(
                        Icons.add_to_queue_rounded,
                        color: Colors.black,
                        size: 30,
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Nouvelle réunion",
                            style: GoogleFonts.spaceGrotesk(
                              color: Colors.black,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            "Instantanée ou SFU",
                            style: GoogleFonts.interTight(
                              color: Colors.black.withOpacity(0.65),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Right blocks - Join & Schedule (Stacked)
            Expanded(
              flex: 10,
              child: Column(
                children: [
                  // Join
                  GestureDetector(
                    onTap: () => _showJoinDialog(lang),
                    child: Container(
                      height: 59,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF121624),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.04)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00E5FF).withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.login_rounded,
                              color: Color(0xFF00E5FF),
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            "Rejoindre",
                            style: GoogleFonts.spaceGrotesk(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Schedule
                  GestureDetector(
                    onTap: () => _showScheduleDialog(lang),
                    child: Container(
                      height: 59,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF121624),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.04)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7C5CFF).withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.calendar_month_outlined,
                              color: Color(0xFF7C5CFF),
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            "Planifier",
                            style: GoogleFonts.spaceGrotesk(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // AI Notes preview card (asymmetric footer)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF121624),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.03)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C5CFF).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.psychology, color: Color(0xFF7C5CFF), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Résumé IA de la dernière réunion",
                      style: GoogleFonts.spaceGrotesk(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "\"Sujet: Alignement Technique. Actions: Mettre à jour l'app Android.\"",
                      style: GoogleFonts.interTight(
                        color: const Color(0xFF8A8FA3).withOpacity(0.8),
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 12),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRecentMeetings(String lang) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(lang),
        const SizedBox(height: 12),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('meetings')
              .where('organizerId', isEqualTo: uid)
              .orderBy('createdAt', descending: true)
              .limit(5)
              .snapshots(),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFFE53935),
                  ),
                ),
              );
            }
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) return _buildEmptyState();
            return Column(
              children: docs.map((doc) {
                final d = doc.data() as Map<String, dynamic>;
                return _MeetingCard(
                  data: d,
                  onJoin: () {
                    final id = d['id'] as String? ?? doc.id;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MeetingScreen(
                          meetingId: id,
                          meetingName: d['title'] as String? ?? 'Réunion',
                          userId: uid,
                          userName: _displayName(),
                          userEmail: widget.user.email,
                          isHost: d['organizerId'] == uid,
                        ),
                      ),
                    );
                  },
                  onShare: () {
                    final id = d['id'] as String? ?? doc.id;
                    _shareMeetingLink(id, d['title'] as String? ?? 'Réunion');
                  },
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String lang) {
    final now = DateTime.now();
    final weekdays = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    final months = [
      'jan',
      'fév',
      'mar',
      'avr',
      'mai',
      'juin',
      'juil',
      'août',
      'sep',
      'oct',
      'nov',
      'déc',
    ];
    return Row(
      children: [
        Text(
          "Aujourd'hui • ${weekdays[now.weekday - 1]}. ${now.day} ${months[now.month - 1]}",
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: () => setState(() {}),
          child: const Icon(Icons.refresh, color: Colors.white30, size: 18),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40),
      decoration: BoxDecoration(
        color: const Color(0xFF12121E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.calendar_today_outlined,
            color: Colors.white12,
            size: 40,
          ),
          const SizedBox(height: 12),
          Text(
            "Aucune réunion récente",
            style: GoogleFonts.poppins(color: Colors.white30, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            "Créez ou rejoignez une réunion",
            style: GoogleFonts.poppins(color: Colors.white12, fontSize: 11),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () {
              final lang = context.read<LocaleProvider>().locale.languageCode;
              _showNewMeetingSheet(lang);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFC62828),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Nouvelle réunion',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Onglet 1 : Chat (placeholder) ─────────────────────────────────────────

  Widget _buildChatTab() {
    return RefreshIndicator(
      onRefresh: () async => setState(() {}),
      color: AppColors.primary,
      backgroundColor: const Color(0xFF1A1A2E),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.2),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.chat_bubble_outline,
                  color: Colors.white12,
                  size: 60,
                ),
                const SizedBox(height: 16),
                Text(
                  'Chat bientôt disponible',
                  style: GoogleFonts.poppins(color: Colors.white30, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  'Échangez avec vos participants\ndans les réunions',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(color: Colors.white12, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Onglet 2 : Réunions (StreamBuilder complet) ────────────────────────────

  Widget _buildMeetingsTab(String lang) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return RefreshIndicator(
      onRefresh: () async => setState(() {}),
      color: AppColors.primary,
      backgroundColor: const Color(0xFF1A1A2E),
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('meetings')
            .where('organizerId', isEqualTo: uid)
            .orderBy('createdAt', descending: true)
            .limit(20)
            .snapshots(),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFFE53935),
              ),
            );
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.video_camera_front_outlined,
                        color: Colors.white12,
                        size: 60,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Aucune réunion',
                        style: GoogleFonts.poppins(
                          color: Colors.white30,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Vos réunions créées apparaîtront ici',
                        style: GoogleFonts.poppins(
                          color: Colors.white12,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }
          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final d = docs[i].data() as Map<String, dynamic>;
              return _MeetingCard(
                data: d,
                onJoin: () {
                  final id = d['id'] as String? ?? docs[i].id;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MeetingScreen(
                        meetingId: id,
                        meetingName: d['title'] as String? ?? 'Réunion',
                        userId: uid,
                        userName: _displayName(),
                        userEmail: widget.user.email,
                        isHost: d['organizerId'] == uid,
                      ),
                    ),
                  );
                },
                onShare: () {
                  final id = d['id'] as String? ?? docs[i].id;
                  _shareMeetingLink(id, d['title'] as String? ?? 'Réunion');
                },
              );
            },
          );
        },
      ),
    );
  }

  // ── Action sheet helpers ──────────────────────────────────────────────────

  void _showNewMeetingSheet(String lang) {
    bool sheetCreating = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A2E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: StatefulBuilder(
            builder: (ctx2, setSheet) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  AppTranslations.t('new_meeting', lang),
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _meetingNameController,
                  style: GoogleFonts.poppins(color: Colors.white),
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: AppTranslations.t('meeting_name_hint', lang),
                    hintStyle: GoogleFonts.poppins(color: Colors.white38),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.08),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () {
                    setSheet(() {
                      _showPasscode = !_showPasscode;
                      if (!_showPasscode) _passcodeController.clear();
                    });
                    setState(() {});
                  },
                  child: Row(
                    children: [
                      Icon(
                        _showPasscode
                            ? Icons.lock_outline
                            : Icons.lock_open_outlined,
                        size: 14,
                        color: Colors.white54,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _showPasscode
                            ? AppTranslations.t('remove_passcode', lang)
                            : AppTranslations.t('add_passcode', lang),
                        style: GoogleFonts.poppins(
                          color: Colors.white54,
                          fontSize: 12,
                          decoration: TextDecoration.underline,
                          decorationColor: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_showPasscode) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _passcodeController,
                    keyboardType: TextInputType.number,
                    obscureText: _obscurePasscode,
                    style: GoogleFonts.poppins(color: Colors.white),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    decoration: InputDecoration(
                      hintText: 'Code (4-6 chiffres)',
                      hintStyle: GoogleFonts.poppins(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.08),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePasscode
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: Colors.white54,
                          size: 18,
                        ),
                        onPressed: () {
                          setSheet(() => _obscurePasscode = !_obscurePasscode);
                          setState(() {});
                        },
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                // ── Meeting type: Standard vs Large Conference ──
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setSheet(() => _isLargeConference = false);
                            setState(() {});
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                              color: !_isLargeConference
                                  ? const Color(0xFFE53935)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.people_outline,
                                  size: 14,
                                  color: !_isLargeConference
                                      ? Colors.white
                                      : Colors.white38,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'Standard (≤6)',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: !_isLargeConference
                                        ? Colors.white
                                        : Colors.white38,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setSheet(() => _isLargeConference = true);
                            setState(() {});
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                              color: _isLargeConference
                                  ? const Color(0xFF1565C0)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.groups_outlined,
                                  size: 14,
                                  color: _isLargeConference
                                      ? Colors.white
                                      : Colors.white38,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'Grande (1000+)',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: _isLargeConference
                                        ? Colors.white
                                        : Colors.white38,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isLargeConference)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Powered by LiveKit — jusqu\'à 1000+ participants',
                      style: GoogleFonts.poppins(
                        color: Colors.blue.shade300,
                        fontSize: 11,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: sheetCreating
                        ? null
                        : () async {
                            setSheet(() => sheetCreating = true);
                            try {
                              await _createMeeting();
                            } finally {
                              if (mounted)
                                setSheet(() => sheetCreating = false);
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE53935),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: sheetCreating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            AppTranslations.t('start_meeting', lang),
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showJoinDialog(String lang) {
    _joinIdController.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A2E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                AppTranslations.t('join_meeting', lang),
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _joinIdController,
                style: GoogleFonts.poppins(color: Colors.white),
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: AppTranslations.t('meeting_id', lang),
                  hintStyle: GoogleFonts.poppins(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.08),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  prefixIcon: const Icon(
                    Icons.tag,
                    color: Colors.white38,
                    size: 18,
                  ),
                ),
                onSubmitted: (_) {
                  Navigator.pop(ctx);
                  _joinById(_joinIdController.text);
                  _joinIdController.clear();
                },
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _joinById(_joinIdController.text);
                    _joinIdController.clear();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1976D2),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    AppTranslations.t('join', lang),
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showScheduleDialog(String lang) {
    _schedTitleController.clear();
    _schedDescController.clear();
    _schedPasscodeController.clear();

    // Default: tomorrow at current time rounded to next 30 min
    final now = DateTime.now();
    var initial = DateTime(
      now.year,
      now.month,
      now.day + 1,
      now.hour,
      now.minute >= 30 ? 0 : 30,
      0,
    );
    if (now.minute >= 30) {
      initial = initial.add(const Duration(hours: 1));
    }
    DateTime selectedDateTime = initial;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A2E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Planifier une réunion',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Title
                  TextField(
                    controller: _schedTitleController,
                    style: GoogleFonts.poppins(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Titre de la réunion',
                      hintStyle: GoogleFonts.poppins(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.08),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      prefixIcon: const Icon(
                        Icons.title,
                        color: Colors.white38,
                        size: 18,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Description
                  TextField(
                    controller: _schedDescController,
                    style: GoogleFonts.poppins(color: Colors.white),
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: "Description (optionnel)",
                      hintStyle: GoogleFonts.poppins(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.08),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      prefixIcon: const Icon(
                        Icons.notes,
                        color: Colors.white38,
                        size: 18,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Date & time picker button
                  GestureDetector(
                    onTap: () async {
                      final date = await showDatePicker(
                        context: ctx,
                        initialDate: selectedDateTime,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        builder: (context, child) => Theme(
                          data: ThemeData.dark().copyWith(
                            colorScheme: const ColorScheme.dark(
                              primary: AppColors.primary,
                              surface: Color(0xFF1A1A2E),
                            ),
                          ),
                          child: child!,
                        ),
                      );
                      if (date == null) return;
                      if (!ctx.mounted) return;
                      final time = await showTimePicker(
                        context: ctx,
                        initialTime: TimeOfDay.fromDateTime(selectedDateTime),
                        builder: (context, child) => Theme(
                          data: ThemeData.dark().copyWith(
                            colorScheme: const ColorScheme.dark(
                              primary: AppColors.primary,
                              surface: Color(0xFF1A1A2E),
                            ),
                          ),
                          child: child!,
                        ),
                      );
                      if (time == null) return;
                      setSheetState(() {
                        selectedDateTime = DateTime(
                          date.year,
                          date.month,
                          date.day,
                          time.hour,
                          time.minute,
                        );
                      });
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.calendar_today,
                            color: AppColors.primary,
                            size: 18,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _formatScheduleDate(selectedDateTime),
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            color: Colors.white38,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Passcode (optional)
                  TextField(
                    controller: _schedPasscodeController,
                    style: GoogleFonts.poppins(color: Colors.white),
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: 'Code d\'accès (optionnel, 4-6 chiffres)',
                      hintStyle: GoogleFonts.poppins(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.08),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      prefixIcon: const Icon(
                        Icons.lock_outline,
                        color: Colors.white38,
                        size: 18,
                      ),
                    ),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  const SizedBox(height: 20),

                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: const BorderSide(color: Colors.white24),
                            ),
                          ),
                          child: Text(
                            'Annuler',
                            style: GoogleFonts.poppins(
                              color: Colors.white54,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            await _scheduleMeeting(selectedDateTime, lang);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'Planifier',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatScheduleDate(DateTime dt) {
    const months = [
      'Jan',
      'Fév',
      'Mar',
      'Avr',
      'Mai',
      'Jun',
      'Jul',
      'Aoû',
      'Sep',
      'Oct',
      'Nov',
      'Déc',
    ];
    const days = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    final dayName = days[dt.weekday - 1];
    final monthName = months[dt.month - 1];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$dayName ${dt.day} $monthName ${dt.year} à $h:$m';
  }

  Future<void> _scheduleMeeting(DateTime scheduledTime, String lang) async {
    final title = _schedTitleController.text.trim();
    if (title.isEmpty) {
      _errorHandler.showErrorDialog(
        context,
        '⚠️ Attention',
        'Veuillez saisir un titre pour la réunion.',
      );
      return;
    }
    if (scheduledTime.isBefore(DateTime.now())) {
      _errorHandler.showErrorDialog(
        context,
        '⚠️ Attention',
        'La date doit être dans le futur.',
      );
      return;
    }
    final rawPasscode = _schedPasscodeController.text.trim();
    if (rawPasscode.isNotEmpty &&
        (rawPasscode.length < 4 || rawPasscode.length > 6)) {
      _errorHandler.showErrorDialog(
        context,
        '⚠️ Attention',
        'Le code d\'accès doit contenir 4 à 6 chiffres.',
      );
      return;
    }

    try {
      final meetingId = await _meetingService.scheduleMeeting(
        title: title,
        description: _schedDescController.text.trim(),
        organizerName: _displayName(),
        organizerId: widget.user.uid,
        startTime: scheduledTime,
        passcode: rawPasscode.isNotEmpty ? rawPasscode : null,
      );

      if (!mounted) return;
      // Show success with share option
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 24),
              const SizedBox(width: 10),
              Text(
                'Réunion planifiée !',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _formatScheduleDate(scheduledTime),
                style: GoogleFonts.poppins(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.tag, color: AppColors.primary, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      meetingId,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _shareMeetingLink(meetingId, title);
              },
              child: Text(
                'Partager',
                style: GoogleFonts.poppins(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                'OK',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        _errorHandler.showErrorDialog(
          context,
          '❌ Erreur',
          'Impossible de planifier la réunion : $e',
        );
      }
    }
  }

  void _showMainMenu(String lang) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(
                Icons.settings_outlined,
                color: Colors.white70,
              ),
              title: Text(
                AppTranslations.t('settings', lang),
                style: GoogleFonts.poppins(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/settings');
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.white70),
              title: Text(
                AppTranslations.t('logout', lang),
                style: GoogleFonts.poppins(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _logout();
              },
            ),
            ListTile(
              leading: const Icon(Icons.share, color: Colors.white70),
              title: Text(
                AppTranslations.t('share', lang),
                style: GoogleFonts.poppins(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _shareApp();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _shareApp() {
    final lang = context.read<LocaleProvider>().locale.languageCode;
    Share.share(AppTranslations.t('share_app_msg', lang));
  }

  void _shareMeetingLink(String meetingId, String title) {
    // Web link works in any browser; deep link opens the app if installed
    const host = 'https://crux-3c6be.web.app';
    final webLink = '$host/join/$meetingId';
    Share.share(
      'Rejoins ma réunion "$title" sur CRUX !\n\n'
      '🌐 Lien (navigateur) : $webLink\n'
      '📱 Code de réunion   : $meetingId\n\n'
      'Aucun compte requis.',
      subject: 'Invitation CRUX — "$title"',
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _MeetingCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onJoin;
  final VoidCallback? onShare;

  const _MeetingCard({required this.data, required this.onJoin, this.onShare});

  @override
  Widget build(BuildContext context) {
    final title = data['title'] as String? ?? 'Réunion';
    final status = data['status'] as String? ?? 'scheduled';
    final id = data['id'] as String? ?? '';
    final ts = data['createdAt'];
    final createdAt = ts is Timestamp ? ts.toDate() : null;

    final isOngoing = status == 'ongoing';
    final statusColor = isOngoing ? const Color(0xFF2E7D32) : Colors.white24;
    final statusLabel = isOngoing
        ? 'En cours'
        : (status == 'ended' ? 'Terminée' : 'Programmée');

    String dateStr = '';
    if (createdAt != null) {
      final months = [
        'jan',
        'fév',
        'mar',
        'avr',
        'mai',
        'juin',
        'juil',
        'août',
        'sep',
        'oct',
        'nov',
        'déc',
      ];
      dateStr =
          '${createdAt.day} ${months[createdAt.month - 1]} · ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF12121E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isOngoing
              ? const Color(0xFF2E7D32).withOpacity(0.4)
              : Colors.white.withOpacity(0.05),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isOngoing
                  ? const Color(0xFF2E7D32).withOpacity(0.15)
                  : Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isOngoing ? Icons.videocam : Icons.videocam_off_outlined,
              color: isOngoing ? const Color(0xFF4CAF50) : Colors.white24,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        statusLabel,
                        style: GoogleFonts.poppins(
                          color: statusColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (dateStr.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(
                        dateStr,
                        style: GoogleFonts.poppins(
                          color: Colors.white24,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
                if (id.isNotEmpty)
                  Text(
                    id,
                    style: GoogleFonts.poppins(
                      color: Colors.white12,
                      fontSize: 9,
                      letterSpacing: 1,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Share button
          if (onShare != null)
            IconButton(
              onPressed: onShare,
              icon: const Icon(Icons.share, color: Colors.white38, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: 'Partager le lien',
            ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onJoin,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isOngoing
                    ? const Color(0xFF2E7D32)
                    : const Color(0xFF1565C0),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isOngoing ? 'Rejoindre' : 'Ouvrir',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }
}
