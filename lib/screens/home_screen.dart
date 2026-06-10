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
import '../theme/colors.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/meeting_service.dart';
import '../services/error_handler_service.dart';
import '../services/user_service.dart';
import '../screens/meeting_screen.dart';
import '../providers/locale_provider.dart';
import '../l10n/app_translations.dart';

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
  bool _isCreating = false;
  bool _showPasscode = false;
  bool _obscurePasscode = true;
  String? _localPhotoPath;

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
    } catch (_) {}
  }

  String _displayName() {
    final fb = FirebaseAuth.instance.currentUser;
    if (fb?.displayName?.trim().isNotEmpty == true) return fb!.displayName!;
    if (fb?.email?.contains('@') == true) return fb!.email!.split('@')[0];
    return widget.user.name;
  }

  Future<void> _createMeeting() async {
    final lang = context.read<LocaleProvider>().locale.languageCode;
    final name = _meetingNameController.text.trim();
    if (name.isEmpty) {
      _errorHandler.showErrorDialog(context, '⚠️ ${AppTranslations.t('attention', lang)}',
          AppTranslations.t('meet_enter_name', lang));
      return;
    }

    final rawPasscode = _showPasscode ? _passcodeController.text.trim() : null;
    if (rawPasscode != null && rawPasscode.isNotEmpty) {
      if (rawPasscode.length < 4 || rawPasscode.length > 6) {
        _errorHandler.showErrorDialog(context, '⚠️ ${AppTranslations.t('attention', lang)}',
            AppTranslations.t('meet_code_range', lang));
        return;
      }
      if (!RegExp(r'^\d+$').hasMatch(rawPasscode)) {
        _errorHandler.showErrorDialog(context, '⚠️ ${AppTranslations.t('attention', lang)}',
            AppTranslations.t('meet_code_digits', lang));
        return;
      }
    }

    setState(() => _isCreating = true);
    try {
      final meetingId = await _meetingService.createMeeting(
        title: name,
        description: '',
        organizerName: _displayName(),
        organizerId: widget.user.uid,
        passcode: rawPasscode?.isNotEmpty == true ? rawPasscode : null,
      );
      _meetingNameController.clear();
      _passcodeController.clear();
      setState(() => _showPasscode = false);
      if (!mounted) return;
      Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MeetingScreen(
              meetingId: meetingId,
              meetingName: name,
              userId: widget.user.uid,
              userName: _displayName(),
              userEmail: widget.user.email,
              isHost: true,
            ),
          ));
    } catch (e) {
      if (mounted) {
        final lang = context.read<LocaleProvider>().locale.languageCode;
        _errorHandler.showErrorDialog(
            context,
            '❌ ${AppTranslations.t('error', lang)}',
            _errorHandler.getMeetingErrorMessageL(
                e.toString().replaceFirst('Exception: ', ''), lang));
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  Future<void> _joinById(String id) async {
    if (id.isEmpty) return;
    final cleanId = id.trim().toUpperCase();
    final lang = context.read<LocaleProvider>().locale.languageCode;

    final meeting = await _meetingService.getMeetingOnce(cleanId);
    if (!mounted) return;

    if (meeting == null) {
      _errorHandler.showErrorDialog(context, '🔍 ${AppTranslations.t('error', lang)}',
          AppTranslations.t('meet_not_found', lang));
      return;
    }

    if (meeting.passcode != null && meeting.passcode!.isNotEmpty) {
      final entered = await _showPasscodePrompt();
      if (!mounted) return;
      if (entered == null) return;
      if (entered != meeting.passcode) {
        if (mounted)
          _errorHandler.showErrorDialog(context, '🔒 ${AppTranslations.t('error', lang)}',
              AppTranslations.t('meet_wrong_code', lang));
        return;
      }
    }

    if (!mounted) return;
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
        ));
  }

  Future<String?> _showPasscodePrompt() async {
    final ctrl = TextEditingController();
    final lang = context.read<LocaleProvider>().locale.languageCode;
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.lock_outline, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Text(AppTranslations.t('passcode_title', lang),
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700, fontSize: 17, color: Colors.white)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(AppTranslations.t('passcode_protected', lang),
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.white70)),
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
                color: Colors.white, letterSpacing: 4, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.08),
              hintText: AppTranslations.t('passcode_hint', lang),
              hintStyle: GoogleFonts.poppins(color: Colors.white38, letterSpacing: 0),
              prefixIcon: const Icon(Icons.lock_outline, color: AppColors.primary),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white24),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primary, width: 2),
              ),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppTranslations.t('cancel', lang),
                style: GoogleFonts.poppins(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(AppTranslations.t('enter_btn', lang),
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: Colors.white)),
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
        title: Text(AppTranslations.t('logout', lang),
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text(AppTranslations.t('logout_confirm', lang),
            style: GoogleFonts.poppins(color: AppColors.textSecondary)),
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
                FirebaseFirestore.instance.collection('users').doc(uid).set(
                  {'status': 'offline', 'lastSeen': FieldValue.serverTimestamp()},
                  SetOptions(merge: true),
                ).catchError((_) {});
              }
              await _authService.signOut();
              if (mounted) Navigator.of(context).pushReplacementNamed('/login');
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: Text(AppTranslations.t('logout', lang),
                style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ── Zoom-style build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LocaleProvider>().locale.languageCode;
    final displayName = _displayName();

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: _buildTopBar(displayName, lang),
      body: _buildBody(lang),
      bottomNavigationBar: _buildBottomNav(lang),
    );
  }

  AppBar _buildTopBar(String displayName, String lang) {
    return AppBar(
      backgroundColor: const Color(0xFF0F0F1A),
      elevation: 0,
      titleSpacing: 0,
      leading: GestureDetector(
        onTap: () =>
            Navigator.pushNamed(context, '/profile').then((_) => _loadLocalPhoto()),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primary,
            backgroundImage:
                _localPhotoPath != null ? FileImage(File(_localPhotoPath!)) : null,
            child: _localPhotoPath == null
                ? Text(
                    displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14))
                : null,
          ),
        ),
      ),
      title: Text('CRUX',
          style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 24,
              letterSpacing: 2)),
      actions: [
        IconButton(
            icon: const Icon(Icons.search, color: Colors.white70, size: 22),
            onPressed: () => _showJoinDialog(lang)),
        IconButton(
            icon: const Icon(Icons.more_horiz, color: Colors.white70, size: 22),
            onPressed: () => _showMainMenu(lang)),
        IconButton(
            icon: const Icon(Icons.auto_awesome, color: Colors.white70, size: 22),
            onPressed: () {}),
      ],
    );
  }

  Widget _buildBody(String lang) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildQuickActions(lang),
        const SizedBox(height: 28),
        _buildTodaySection(lang),
      ]),
    );
  }

  Widget _buildQuickActions(String lang) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _QuickAction(
          icon: Icons.video_call,
          label: 'Nouvelle\nréunion',
          color: const Color(0xFFE53935),
          onTap: () => _showNewMeetingSheet(lang),
        ),
        _QuickAction(
          icon: Icons.add,
          label: 'Rejoindre',
          color: const Color(0xFF1976D2),
          onTap: () => _showJoinDialog(lang),
        ),
        _QuickAction(
          icon: Icons.calendar_today,
          label: 'Programmer',
          color: const Color(0xFF1976D2),
          onTap: () => _showScheduleDialog(lang),
        ),
        _QuickAction(
          icon: Icons.share,
          label: 'Partager',
          color: const Color(0xFF1976D2),
          onTap: _shareApp,
        ),
      ],
    );
  }

  Widget _buildTodaySection(String lang) {
    final now = DateTime.now();
    final weekdays = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    final months = [
      'jan', 'fév', 'mar', 'avr', 'mai', 'juin',
      'juil', 'août', 'sep', 'oct', 'nov', 'déc'
    ];
    final dayName = weekdays[now.weekday - 1];
    final monthName = months[now.month - 1];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(
          "Aujourd'hui • $dayName. ${now.day} $monthName",
          style: GoogleFonts.poppins(
              color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
        ),
        const Spacer(),
        IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white54, size: 18),
            onPressed: () => setState(() {})),
        IconButton(
            icon: const Icon(Icons.calendar_month_outlined, color: Colors.white54, size: 18),
            onPressed: () {}),
      ]),
      const SizedBox(height: 12),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 40),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(children: [
          const Icon(Icons.calendar_today_outlined, color: Colors.white24, size: 40),
          const SizedBox(height: 12),
          Text("Aucune réunion aujourd'hui",
              style: GoogleFonts.poppins(color: Colors.white38, fontSize: 13)),
          const SizedBox(height: 4),
          Text("Créez ou rejoignez une réunion",
              style: GoogleFonts.poppins(color: Colors.white24, fontSize: 11)),
        ]),
      ),
    ]);
  }

  Widget _buildBottomNav(String lang) {
    return BottomNavigationBar(
      backgroundColor: const Color(0xFF161622),
      selectedItemColor: AppColors.primary,
      unselectedItemColor: Colors.white38,
      selectedLabelStyle: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600),
      unselectedLabelStyle: GoogleFonts.poppins(fontSize: 10),
      type: BottomNavigationBarType.fixed,
      currentIndex: 0,
      onTap: (i) {
        if (i == 3) Navigator.pushNamed(context, '/profile').then((_) => _loadLocalPhoto());
        if (i == 4) _showMainMenu(lang);
      },
      items: const [
        BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Accueil'),
        BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            activeIcon: Icon(Icons.chat_bubble),
            label: 'Chat'),
        BottomNavigationBarItem(
            icon: Icon(Icons.video_camera_front_outlined),
            activeIcon: Icon(Icons.video_camera_front),
            label: 'Réunions'),
        BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profil'),
        BottomNavigationBarItem(icon: Icon(Icons.more_horiz), label: 'Plus'),
      ],
    );
  }

  // ── Action sheet helpers ──────────────────────────────────────────────────

  void _showNewMeetingSheet(String lang) {
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
            builder: (ctx2, setSheet) => Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white24, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              Text(AppTranslations.t('new_meeting', lang),
                  style: GoogleFonts.poppins(
                      color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              TextField(
                controller: _meetingNameController,
                style: GoogleFonts.poppins(color: Colors.white),
                autofocus: true,
                decoration: InputDecoration(
                  hintText: AppTranslations.t('meeting_name_hint', lang),
                  hintStyle: GoogleFonts.poppins(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.08),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                child: Row(children: [
                  Icon(
                      _showPasscode ? Icons.lock_outline : Icons.lock_open_outlined,
                      size: 14,
                      color: Colors.white54),
                  const SizedBox(width: 6),
                  Text(
                      _showPasscode
                          ? AppTranslations.t('remove_passcode', lang)
                          : AppTranslations.t('add_passcode', lang),
                      style: GoogleFonts.poppins(
                          color: Colors.white54,
                          fontSize: 12,
                          decoration: TextDecoration.underline,
                          decorationColor: Colors.white54)),
                ]),
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
                    fillColor: Colors.white.withValues(alpha: 0.08),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    suffixIcon: IconButton(
                        icon: Icon(
                            _obscurePasscode
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.white54,
                            size: 18),
                        onPressed: () {
                          setSheet(() => _obscurePasscode = !_obscurePasscode);
                          setState(() {});
                        }),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isCreating
                      ? null
                      : () {
                          Navigator.pop(context);
                          _createMeeting();
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE53935),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isCreating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(AppTranslations.t('start_meeting', lang),
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
            ]),
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
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text(AppTranslations.t('join_meeting', lang),
                style: GoogleFonts.poppins(
                    color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
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
                fillColor: Colors.white.withValues(alpha: 0.08),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                prefixIcon: const Icon(Icons.tag, color: Colors.white38, size: 18),
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
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(AppTranslations.t('join', lang),
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _showScheduleDialog(String lang) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Fonctionnalité de planification bientôt disponible',
          style: GoogleFonts.poppins()),
      backgroundColor: AppColors.primary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
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
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          ListTile(
              leading: const Icon(Icons.settings_outlined, color: Colors.white70),
              title: Text(AppTranslations.t('settings', lang),
                  style: GoogleFonts.poppins(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/settings');
              }),
          ListTile(
              leading: const Icon(Icons.logout, color: Colors.white70),
              title: Text(AppTranslations.t('logout', lang),
                  style: GoogleFonts.poppins(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _logout();
              }),
          ListTile(
              leading: const Icon(Icons.share, color: Colors.white70),
              title: Text(AppTranslations.t('share', lang),
                  style: GoogleFonts.poppins(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _shareApp();
              }),
        ]),
      ),
    );
  }

  void _shareApp() {
    final lang = context.read<LocaleProvider>().locale.languageCode;
    Share.share(AppTranslations.t('share_app_msg', lang));
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
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4))
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
            maxLines: 2,
          ),
        ]),
      ),
    );
  }
}
