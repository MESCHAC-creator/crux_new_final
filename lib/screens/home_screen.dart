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
      _errorHandler.showErrorDialog(context, '⚠️ ${AppTranslations.t('attention', lang)}', AppTranslations.t('meet_enter_name', lang));
      return;
    }

    final rawPasscode = _showPasscode ? _passcodeController.text.trim() : null;
    if (rawPasscode != null && rawPasscode.isNotEmpty) {
      if (rawPasscode.length < 4 || rawPasscode.length > 6) {
        _errorHandler.showErrorDialog(context, '⚠️ ${AppTranslations.t('attention', lang)}', AppTranslations.t('meet_code_range', lang));
        return;
      }
      if (!RegExp(r'^\d+$').hasMatch(rawPasscode)) {
        _errorHandler.showErrorDialog(context, '⚠️ ${AppTranslations.t('attention', lang)}', AppTranslations.t('meet_code_digits', lang));
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
      Navigator.push(context, MaterialPageRoute(
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
        _errorHandler.showErrorDialog(context, '❌ ${AppTranslations.t('error', lang)}', _errorHandler.getMeetingErrorMessageL(e.toString().replaceFirst('Exception: ', ''), lang));
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
      _errorHandler.showErrorDialog(context, '🔍 ${AppTranslations.t('error', lang)}', AppTranslations.t('meet_not_found', lang));
      return;
    }

    if (meeting.passcode != null && meeting.passcode!.isNotEmpty) {
      final entered = await _showPasscodePrompt();
      if (!mounted) return;
      if (entered == null) return;
      if (entered != meeting.passcode) {
        if (mounted) _errorHandler.showErrorDialog(context, '🔒 ${AppTranslations.t('error', lang)}', AppTranslations.t('meet_wrong_code', lang));
        return;
      }
    }

    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(
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
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17, color: Colors.white)),
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
            style: GoogleFonts.poppins(color: Colors.white, letterSpacing: 4, fontWeight: FontWeight.w700),
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

  void _showJoinDialog() {
    _joinIdController.clear();
    final lang = context.read<LocaleProvider>().locale.languageCode;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.link, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Text(AppTranslations.t('join', lang),
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 18)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(AppTranslations.t('join_hint', lang),
              style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          TextField(
            controller: _joinIdController,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: AppTranslations.t('meeting_id', lang),
              hintStyle: GoogleFonts.poppins(color: AppColors.textTertiary),
              prefixIcon: const Icon(Icons.tag, color: AppColors.secondary),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.secondary, width: 2),
              ),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppTranslations.t('cancel', lang),
                style: GoogleFonts.poppins(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              final id = _joinIdController.text.trim().toUpperCase();
              if (id.isEmpty) return;
              Navigator.pop(ctx);
              await _joinById(id);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.secondary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(AppTranslations.t('join', lang),
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
              // Mark offline before signing out
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lang = context.watch<LocaleProvider>().locale.languageCode;
    final bgColor = isDark ? const Color(0xFF0F0F0F) : const Color(0xFFF5F3FF);
    final fieldFill = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.white.withValues(alpha: 0.15);
    final displayName = _displayName();

    return Scaffold(
      backgroundColor: bgColor,
      body: CustomScrollView(
        slivers: [
          // ── App bar with gradient + profile photo ──────────────
          SliverAppBar(
            expandedHeight: 160,
            floating: false,
            pinned: true,
            backgroundColor: Colors.transparent,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFE74C3C), Color(0xFF8E44AD)],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Profile photo + name
                            Row(children: [
                              GestureDetector(
                                onTap: () => Navigator.pushNamed(context, '/profile')
                                    .then((_) => _loadLocalPhoto()),
                                child: Container(
                                  width: 46, height: 46,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                    color: Colors.white24,
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: _localPhotoPath != null
                                      ? Image.file(File(_localPhotoPath!), fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => _avatarLetter(displayName))
                                      : _avatarLetter(displayName),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'CRUX',
                                style: GoogleFonts.poppins(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 2,
                                ),
                              ),
                            ]),
                            // Actions
                            Row(children: [
                              IconButton(
                                icon: const Icon(Icons.settings_outlined, color: Colors.white70),
                                onPressed: () => Navigator.pushNamed(context, '/settings'),
                              ),
                              IconButton(
                                icon: const Icon(Icons.logout, color: Colors.white70),
                                onPressed: _logout,
                              ),
                            ]),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${AppTranslations.t('hello', lang)}, ${displayName.split(' ').first} 👋',
                          style: GoogleFonts.poppins(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          AppTranslations.t('ready_meeting', lang),
                          style: GoogleFonts.poppins(fontSize: 12, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),

                  // ── Create meeting card ─────────────────────────
                  Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFE74C3C), Color(0xFF9B59B6), Color(0xFF8E44AD)],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFE74C3C).withValues(alpha: 0.35),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.video_call, color: Colors.white, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            AppTranslations.t('new_meeting', lang),
                            style: GoogleFonts.poppins(
                              fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white,
                            ),
                          ),
                        ]),
                        const SizedBox(height: 16),

                        // Meeting name field
                        TextField(
                          controller: _meetingNameController,
                          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w500),
                          decoration: InputDecoration(
                            hintText: AppTranslations.t('meeting_name_hint', lang),
                            hintStyle: GoogleFonts.poppins(color: Colors.white54),
                            prefixIcon: const Icon(Icons.edit, color: Colors.white60, size: 20),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.15),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: Colors.white, width: 2),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Toggle passcode
                        GestureDetector(
                          onTap: () => setState(() {
                            _showPasscode = !_showPasscode;
                            if (!_showPasscode) _passcodeController.clear();
                          }),
                          child: Row(children: [
                            Icon(
                              _showPasscode ? Icons.lock_outline : Icons.lock_open_outlined,
                              size: 15, color: Colors.white70,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _showPasscode
                                  ? AppTranslations.t('remove_passcode', lang)
                                  : AppTranslations.t('add_passcode', lang),
                              style: GoogleFonts.poppins(
                                fontSize: 12, color: Colors.white70,
                                decoration: TextDecoration.underline,
                                decorationColor: Colors.white70,
                              ),
                            ),
                          ]),
                        ),

                        // Passcode field (conditional)
                        if (_showPasscode) ...[
                          const SizedBox(height: 10),
                          TextField(
                            controller: _passcodeController,
                            obscureText: _obscurePasscode,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(6),
                            ],
                            style: GoogleFonts.poppins(
                                color: Colors.white, fontWeight: FontWeight.w600, letterSpacing: 4),
                            decoration: InputDecoration(
                              hintText: AppTranslations.t('passcode_hint', lang),
                              hintStyle: GoogleFonts.poppins(color: Colors.white38, letterSpacing: 0),
                              prefixIcon: const Icon(Icons.lock_outline, color: Colors.white60, size: 20),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePasscode
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: Colors.white54, size: 18,
                                ),
                                onPressed: () => setState(() => _obscurePasscode = !_obscurePasscode),
                              ),
                              filled: true,
                              fillColor: fieldFill,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: Colors.white, width: 2),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(AppTranslations.t('passcode_digits', lang),
                              style: GoogleFonts.poppins(fontSize: 10, color: Colors.white38)),
                        ],

                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isCreating ? null : _createMeeting,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFFE74C3C),
                              disabledBackgroundColor: Colors.white60,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: _isCreating
                                ? const SizedBox(
                                    width: 22, height: 22,
                                    child: CircularProgressIndicator(
                                        color: Color(0xFFE74C3C), strokeWidth: 2.5),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.rocket_launch, size: 18),
                                      const SizedBox(width: 8),
                                      Text(
                                        AppTranslations.t('start_meeting', lang),
                                        style: GoogleFonts.poppins(
                                            fontWeight: FontWeight.w700, fontSize: 15),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ── Quick actions ───────────────────────────────
                  Text(
                    AppTranslations.t('quick_actions', lang),
                    style: GoogleFonts.poppins(
                      fontSize: 17, fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 14),

                  Row(children: [
                    Expanded(child: _ActionCard(
                      icon: Icons.group_add,
                      title: AppTranslations.t('join', lang),
                      subtitle: AppTranslations.t('via_id', lang),
                      gradientColors: const [Color(0xFF8E44AD), Color(0xFF6C3483)],
                      onTap: _showJoinDialog,
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: _ActionCard(
                      icon: Icons.person_outline,
                      title: AppTranslations.t('profile', lang),
                      subtitle: AppTranslations.t('my_account', lang),
                      gradientColors: const [Color(0xFFF39C12), Color(0xFFD68910)],
                      onTap: () => Navigator.pushNamed(context, '/profile')
                          .then((_) => _loadLocalPhoto()),
                    )),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: _ActionCard(
                      icon: Icons.tune,
                      title: AppTranslations.t('settings_short', lang),
                      subtitle: AppTranslations.t('preferences', lang),
                      gradientColors: const [Color(0xFF3498DB), Color(0xFF2980B9)],
                      onTap: () => Navigator.pushNamed(context, '/settings'),
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: _ActionCard(
                      icon: Icons.share,
                      title: AppTranslations.t('share', lang),
                      subtitle: AppTranslations.t('invite', lang),
                      gradientColors: const [Color(0xFF27AE60), Color(0xFF1E8449)],
                      onTap: () {
                        Share.share(AppTranslations.t('share_app_msg', lang));
                      },
                    )),
                  ]),

                  const SizedBox(height: 28),

                  // ── Info banner ─────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : const Color(0xFFEDE7F6),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.secondary.withValues(alpha: 0.3)),
                    ),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.secondary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.info_outline, color: AppColors.secondary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          AppTranslations.t('meeting_info', lang),
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: isDark ? Colors.white70 : AppColors.textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarLetter(String name) {
    return Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : 'U',
        style: GoogleFonts.poppins(
            color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> gradientColors;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradientColors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.grey.withValues(alpha: 0.15),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: GoogleFonts.poppins(
                fontSize: 14, fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : AppColors.textPrimary,
              )),
              Text(subtitle, style: GoogleFonts.poppins(
                fontSize: 11, color: AppColors.textTertiary,
              )),
            ],
          ),
        ]),
      ),
    );
  }
}
