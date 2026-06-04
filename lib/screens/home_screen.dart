import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/colors.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/meeting_service.dart';
import '../services/pro_service.dart';
import '../services/error_handler_service.dart';
import '../screens/meeting_screen.dart';
import '../screens/meeting_report_screen.dart';
import '../models/meeting_report_model.dart';
import '../services/user_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/locale_provider.dart';
import '../providers/color_provider.dart';
import '../l10n/app_translations.dart';

enum MeetingMode { standard, webinar, business, church, live, conference }

class HomeScreen extends StatefulWidget {
  final UserModel user;
  const HomeScreen({super.key, required this.user});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final _authService = AuthService();
  final _meetingService = MeetingService();
  final _proService = ProService();
  final _errorHandler = ErrorHandlerService();
  final _meetingNameController = TextEditingController();
  final _joinIdController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isCreating = false;
  bool _showPassword = false;
  bool _obscurePassword = true;
  bool _isPro = false;
  int _passwordAttempts = 0;
  DateTime? _passwordLockUntil;
  List<Map<String, dynamic>> _recentMeetings = [];
  String? _localPhotoPath;

  late AnimationController _headerAnim;
  late AnimationController _pulseAnim;
  late Animation<double> _headerFade;
  late Animation<Offset> _headerSlide;
  late Animation<double> _pulse;

  bool _isOnline = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _checkPro();
    _setupAnimations();
    _loadLocalPhoto();
    _syncProfileFromFirestore();
    _setOnlineStatus(true);
  }

  void _setupAnimations() {
    _headerAnim = AnimationController(
        duration: const Duration(milliseconds: 900), vsync: this);
    _pulseAnim = AnimationController(
        duration: const Duration(milliseconds: 2000), vsync: this)
      ..repeat(reverse: true);

    _headerFade = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _headerAnim, curve: Curves.easeOut));
    _headerSlide =
        Tween<Offset>(begin: const Offset(0, -0.3), end: Offset.zero).animate(
            CurvedAnimation(parent: _headerAnim, curve: Curves.easeOutCubic));
    _pulse = Tween<double>(begin: 1.0, end: 1.05)
        .animate(CurvedAnimation(parent: _pulseAnim, curve: Curves.easeInOut));

    _headerAnim.forward();
  }

  Future<void> _checkPro() async {
    final pro = await _proService.isPro(widget.user.uid);
    if (mounted) setState(() => _isPro = pro);
  }

  Future<void> _loadHistory() async {
    final history = await _meetingService.getRecentMeetings();
    if (mounted) setState(() => _recentMeetings = history);
  }

  Future<void> _loadLocalPhoto() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('crux_local_photo_path');
    // Verify the file still exists
    if (path != null && File(path).existsSync()) {
      if (mounted) setState(() => _localPhotoPath = path);
    } else {
      // Fallback: decode photo from Firestore if available
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final profile = await UserService.instance.getProfile(uid);
        final b64 = profile?['photoBase64'] as String?;
        if (b64 != null && b64.isNotEmpty && mounted) {
          // Write it locally for future fast access
          try {
            final bytes = UserService.decodePhoto(b64);
            if (bytes != null) {
              final dir = await getApplicationDocumentsDirectory();
              final dest = '${dir.path}/profile_photo.jpg';
              await File(dest).writeAsBytes(bytes);
              await prefs.setString('crux_local_photo_path', dest);
              if (mounted) setState(() => _localPhotoPath = dest);
            }
          } catch (_) {}
        }
      }
    }
  }

  /// Pull fresh name from Firestore and update Firebase Auth if it changed.
  Future<void> _syncProfileFromFirestore() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final profile = await UserService.instance.getProfile(uid);
      final firestoreName = profile?['name'] as String?;
      if (firestoreName != null &&
          firestoreName.isNotEmpty &&
          firestoreName != FirebaseAuth.instance.currentUser?.displayName) {
        await FirebaseAuth.instance.currentUser!.updateDisplayName(firestoreName);
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  static String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Returns the freshest display name available.
  String _freshUserName() {
    return FirebaseAuth.instance.currentUser?.displayName?.trim().isNotEmpty == true
        ? FirebaseAuth.instance.currentUser!.displayName!
        : widget.user.name;
  }

  @override
  void dispose() {
    _setOnlineStatus(false);
    _headerAnim.dispose();
    _pulseAnim.dispose();
    _meetingNameController.dispose();
    _joinIdController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _setOnlineStatus(bool online) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    FirebaseFirestore.instance.collection('users').doc(uid).set({
      'status': online ? 'online' : 'offline',
      'lastSeen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)).catchError((_) {});
    if (mounted) setState(() => _isOnline = online);
  }

  /// Returns the first name of the currently logged-in user.
  String _displayFirstName() {
    final fbUser = FirebaseAuth.instance.currentUser;
    final raw = fbUser?.displayName?.trim().isNotEmpty == true
        ? fbUser!.displayName!
        : (fbUser?.email?.contains('@') == true
            ? fbUser!.email!.split('@')[0]
            : widget.user.name);
    return raw.split(' ').first;
  }

  Future<void> _createMeeting({String description = ''}) async {
    final name = _meetingNameController.text.trim();
    if (name.isEmpty) {
      _errorHandler.showWarningSnackBar(context, '⚠️ Entrez le nom de la réunion');
      return;
    }
    if (name.length < 2) {
      _errorHandler.showWarningSnackBar(context, '⚠️ Le nom doit faire au moins 2 caractères');
      return;
    }
    if (name.length > 60) {
      _errorHandler.showWarningSnackBar(context, '⚠️ Le nom ne peut pas dépasser 60 caractères');
      return;
    }
    setState(() => _isCreating = true);
    final rawPassword = _showPassword ? _passwordController.text.trim() : null;
    if (rawPassword != null && rawPassword.length < 4) {
      _errorHandler.showWarningSnackBar(context, '⚠️ Le code d\'accès doit faire au moins 4 caractères');
      setState(() => _isCreating = false);
      return;
    }
    final password = rawPassword != null ? _hashPassword(rawPassword) : null;
    try {
      final meetingId = await _meetingService.createMeeting(
        title: name,
        description: description,
        organizerName: _freshUserName(),
        organizerId: widget.user.uid,
        password: password,
      );
      _meetingNameController.clear();
      _passwordController.clear();
      setState(() => _showPassword = false);
      // Don't reload history — it was just saved in createMeeting()
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MeetingScreen(
            meetingId: meetingId,
            meetingName: name,
            userId: widget.user.uid,
            userName: _freshUserName(),
            userEmail: widget.user.email,
            isHost: true,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        _errorHandler.showError(context,
            _errorHandler.getMeetingErrorMessage(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  Future<void> _joinById(String id) async {
    if (id.isEmpty) return;
    final cleanId = id.trim().toUpperCase();
    if (cleanId.length < 8 || cleanId.length > 32) {
      _errorHandler.showError(context, '🔍 L\'ID de réunion n\'est pas valide.');
      return;
    }

    // Check if meeting is locked or password-protected before navigating
    final meeting = await _meetingService.getMeetingOnce(cleanId);

    if (!mounted) return;

    if (meeting == null) {
      _errorHandler.showError(context, '🔍 Réunion introuvable. Vérifiez l\'ID saisi.');
      return;
    }

    if (meeting.isLocked) {
      _errorHandler.showWarningSnackBar(context,
          '🔒 Cette réunion est verrouillée par l\'hôte. Réessayez plus tard.');
      return;
    }

    if (meeting.password != null && meeting.password!.isNotEmpty) {
      // Brute-force lock
      if (_passwordLockUntil != null && DateTime.now().isBefore(_passwordLockUntil!)) {
        final remaining = _passwordLockUntil!.difference(DateTime.now()).inSeconds;
        _errorHandler.showError(context, '🔒 Trop de tentatives. Réessayez dans ${remaining}s.');
        return;
      }
      final entered = await _showPasswordPrompt();
      if (!mounted) return;
      if (entered == null) return;
      if (entered.isEmpty) {
        _errorHandler.showWarningSnackBar(context, '⚠️ Entrez le code d\'accès');
        return;
      }
      if (_hashPassword(entered) != meeting.password) {
        _passwordAttempts++;
        if (_passwordAttempts >= 5) {
          _passwordLockUntil = DateTime.now().add(const Duration(minutes: 2));
          _passwordAttempts = 0;
          _errorHandler.showError(context, '🔒 5 tentatives échouées. Réessayez dans 2 minutes.');
        } else {
          final remaining = 5 - _passwordAttempts;
          _errorHandler.showError(context, '🔑 Code incorrect. $remaining tentative(s) restante(s).');
        }
        return;
      }
      _passwordAttempts = 0; // reset on success
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MeetingScreen(
          meetingId: cleanId,
          meetingName: meeting?.title ?? 'Réunion',
          userId: widget.user.uid,
          userName: _freshUserName(),
          userEmail: widget.user.email,
          isHost: false,
        ),
      ),
    );
  }

  Future<String?> _showPasswordPrompt() async {
    final ctrl = TextEditingController();
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
          Text('Code d\'accès',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700, fontSize: 17, color: Colors.white)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Cette réunion est protégée par un code.',
              style: GoogleFonts.poppins(
                  fontSize: 13, color: Colors.white70)),
          const SizedBox(height: 16),
          TextField(
            controller: ctrl,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            style: GoogleFonts.poppins(color: Colors.white),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.08),
              hintText: 'Code d\'accès',
              hintStyle: GoogleFonts.poppins(color: Colors.white38),
              prefixIcon: const Icon(Icons.lock_outline, color: AppColors.primary),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 2),
              ),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Annuler',
                style: GoogleFonts.poppins(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Entrer',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showJoinDialog() {
    _joinIdController.clear();
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
          Text('Rejoindre',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700, fontSize: 18)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Entrez l\'ID de la réunion partagé par l\'hôte',
              style: GoogleFonts.poppins(
                  fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          TextField(
            controller: _joinIdController,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: 'ID de la réunion',
              hintStyle:
                  GoogleFonts.poppins(color: AppColors.textTertiary),
              prefixIcon:
                  const Icon(Icons.tag, color: AppColors.secondary),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                    color: AppColors.secondary, width: 2),
              ),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Annuler',
                style:
                    GoogleFonts.poppins(color: AppColors.textSecondary)),
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
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Rejoindre',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _logout() async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Déconnexion',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text('Voulez-vous vraiment vous déconnecter ?',
            style: GoogleFonts.poppins(color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _authService.signOut();
              if (mounted) {
                Navigator.of(context).pushReplacementNamed('/login');
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error),
            child: Text('Déconnecter',
                style: GoogleFonts.poppins(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lang = context.watch<LocaleProvider>().locale.languageCode;
    final cp = context.watch<ColorProvider>();
    final firstName = _displayFirstName();
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? AppTranslations.t('good_morning', lang)
        : hour < 18
            ? AppTranslations.t('good_afternoon', lang)
            : AppTranslations.t('good_evening', lang);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0A0F) : const Color(0xFFF0F2FF),
      body: Stack(
        children: [
          // Animated background orbs
          _AnimatedOrbs(isDark: isDark),

          // Main content
          SafeArea(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // ── Header ──────────────────────────────────
                SliverToBoxAdapter(
                  child: SlideTransition(
                    position: _headerSlide,
                    child: FadeTransition(
                      opacity: _headerFade,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$greeting,',
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      color: isDark ? Colors.white54 : Colors.black45,
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      Text(
                                        firstName,
                                        style: GoogleFonts.poppins(
                                          fontSize: 26,
                                          fontWeight: FontWeight.w800,
                                          color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      if (_isPro)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(colors: [Color(0xFFFFD700), Color(0xFFFFA500)]),
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Text('PRO', style: GoogleFonts.poppins(
                                            fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white,
                                          )),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            // Avatar → profile menu
                            PopupMenuButton<String>(
                              tooltip: 'Profil et déconnexion',
                              offset: const Offset(0, 52),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
                              onSelected: (val) {
                                if (val == 'profile') Navigator.pushNamed(context, '/profile').then((_) => _loadLocalPhoto());
                                if (val == 'logout') _logout();
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(value: 'profile', child: Row(children: [
                                  Icon(Icons.person_outline, color: cp.primary, size: 18),
                                  const SizedBox(width: 10),
                                  Text(AppTranslations.t('profile', lang),
                                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600,
                                          color: isDark ? Colors.white : Colors.black87)),
                                ])),
                                PopupMenuItem(value: 'logout', child: Row(children: [
                                  const Icon(Icons.logout, color: Colors.red, size: 18),
                                  const SizedBox(width: 10),
                                  Text(AppTranslations.t('logout', lang),
                                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.red)),
                                ])),
                              ],
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    width: 44, height: 44,
                                    decoration: BoxDecoration(
                                      gradient: cp.gradient,
                                      shape: BoxShape.circle,
                                      boxShadow: [BoxShadow(color: cp.primary.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4))],
                                    ),
                                    child: Center(
                                      child: _localPhotoPath != null && File(_localPhotoPath!).existsSync()
                                          ? ClipOval(child: Image.file(File(_localPhotoPath!), fit: BoxFit.cover, width: 44, height: 44))
                                          : FirebaseAuth.instance.currentUser?.photoURL != null
                                              ? ClipOval(child: Image.network(FirebaseAuth.instance.currentUser!.photoURL!, fit: BoxFit.cover, width: 44, height: 44,
                                                  errorBuilder: (_, __, ___) => Text(firstName.isNotEmpty ? firstName[0].toUpperCase() : 'U',
                                                      style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18))))
                                              : Text(firstName.isNotEmpty ? firstName[0].toUpperCase() : 'U',
                                                  style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
                                    ),
                                  ),
                                  if (_isOnline)
                                    Positioned(
                                      bottom: 0, right: 0,
                                      child: Container(
                                        width: 12, height: 12,
                                        decoration: BoxDecoration(
                                          color: Colors.green,
                                          shape: BoxShape.circle,
                                          border: Border.all(color: isDark ? const Color(0xFF12121E) : Colors.white, width: 2),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Tooltip(
                              message: 'Paramètres',
                              child: GestureDetector(
                                onTap: () => Navigator.pushNamed(context, '/settings'),
                                child: Container(
                                  width: 44, height: 44,
                                  decoration: BoxDecoration(
                                    color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(Icons.settings_outlined,
                                    color: isDark ? Colors.white70 : Colors.black54, size: 20),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                SliverToBoxAdapter(child: const SizedBox(height: 24)),

                // ── Two big action buttons ───────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    child: Row(
                      children: [
                        // NEW MEETING
                        Expanded(
                          child: Semantics(
                            label: 'Nouvelle réunion — créer une réunion vidéo',
                            button: true,
                            child: ScaleTransition(
                              scale: _pulse,
                              child: _BigActionButton(
                                icon: Icons.videocam_rounded,
                                label: AppTranslations.t('new_meeting', lang),
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFE74C3C), Color(0xFF9B59B6)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                onTap: _showCreateBottomSheet,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        // JOIN MEETING
                        Expanded(
                          child: Semantics(
                            label: 'Rejoindre une réunion existante',
                            button: true,
                            child: _BigActionButton(
                              icon: Icons.add_link_rounded,
                              label: AppTranslations.t('join_meeting', lang),
                              gradient: const LinearGradient(
                                colors: [Color(0xFF5B5FFF), Color(0xFF8E44AD)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              onTap: _showJoinDialog,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                SliverToBoxAdapter(child: const SizedBox(height: 28)),

                // ── Quick stats bar ──────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.12),
                        ),
                        boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 4))],
                      ),
                      child: Row(
                        children: [
                          _StatItem(label: AppTranslations.t('meetings', lang), value: '${_recentMeetings.length}', icon: Icons.videocam_outlined, color: const Color(0xFFE74C3C)),
                          _Divider(),
                          _StatItem(label: AppTranslations.t('status', lang), value: _isPro ? AppTranslations.t('pro_label', lang) : AppTranslations.t('free', lang), icon: Icons.workspace_premium_outlined, color: _isPro ? const Color(0xFFFFD700) : Colors.grey),
                          _Divider(),
                          _StatItem(label: AppTranslations.t('limit', lang), value: _isPro ? '∞' : '30min', icon: Icons.timer_outlined, color: const Color(0xFF5B5FFF)),
                        ],
                      ),
                    ),
                  ),
                ),

                SliverToBoxAdapter(child: const SizedBox(height: 28)),

                // ── Quick actions grid ───────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(AppTranslations.t('quick_actions', lang),
                          style: GoogleFonts.poppins(
                            fontSize: 16, fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                          )),
                        const SizedBox(height: 14),
                        Row(children: [
                          Expanded(child: _QuickAction(icon: Icons.link, label: AppTranslations.t('join', lang), color: const Color(0xFF5B5FFF), onTap: _showJoinDialog)),
                          const SizedBox(width: 10),
                          Expanded(child: _QuickAction(icon: Icons.share_outlined, label: AppTranslations.t('share', lang), color: const Color(0xFF27AE60),
                            onTap: () async {
                              const msg = '🎥 Rejoins-moi sur CRUX — la meilleure app de visioconférence !\n\nTélécharge ici : https://github.com/MESCHAC-creator/crux_new_final/releases\n\n📲 Gratuit · 30 min offertes · Disponible sur Android';
                              await Clipboard.setData(const ClipboardData(text: msg));
                              if (context.mounted) _errorHandler.showInfoSnackBar(context, AppTranslations.t('copied', lang));
                            })),
                          const SizedBox(width: 10),
                          Expanded(child: _QuickAction(icon: Icons.tune, label: AppTranslations.t('settings_short', lang), color: const Color(0xFF3498DB),
                            onTap: () => Navigator.pushNamed(context, '/settings'))),
                          const SizedBox(width: 10),
                          Expanded(child: _QuickAction(icon: Icons.person_outline, label: AppTranslations.t('profile', lang), color: const Color(0xFFF39C12),
                            onTap: () => Navigator.pushNamed(context, '/profile').then((_) => _loadLocalPhoto()))),
                        ]),
                      ],
                    ),
                  ),
                ),

                SliverToBoxAdapter(child: const SizedBox(height: 28)),

                // ── Pro banner (if not Pro) ──────────────────
                if (!_isPro)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: GestureDetector(
                        onTap: () async {
                          try {
                            await _proService.startPayment(userId: widget.user.uid, userName: widget.user.name);
                          } catch (_) {}
                        },
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFD700), Color(0xFFFFA500), Color(0xFFFF6B35)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [BoxShadow(color: const Color(0xFFFFD700).withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))],
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.workspace_premium, color: Colors.white, size: 36),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(AppTranslations.t('go_pro', lang), style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                                    Text(AppTranslations.t('go_pro_sub', lang), style: GoogleFonts.poppins(color: Colors.white.withValues(alpha: 0.85), fontSize: 12)),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                                child: Text(AppTranslations.t('activate', lang), style: GoogleFonts.poppins(color: const Color(0xFFFFA500), fontWeight: FontWeight.w800, fontSize: 13)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                if (!_isPro) SliverToBoxAdapter(child: const SizedBox(height: 28)),

                // ── Recent meetings ──────────────────────────
                if (_recentMeetings.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(AppTranslations.t('recent', lang),
                            style: GoogleFonts.poppins(
                              fontSize: 16, fontWeight: FontWeight.w800,
                              color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                            )),
                          TextButton(
                            onPressed: () async {
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.remove('crux_recent_meetings');
                              await _loadHistory();
                            },
                            child: Text(AppTranslations.t('clear_all', lang), style: GoogleFonts.poppins(fontSize: 12, color: Colors.red.shade400)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        final m = _recentMeetings[i];
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
                          child: _RecentMeetingTile(
                            title: m['title'] ?? 'Réunion',
                            meetingId: m['id'] ?? '',
                            timestamp: m['ts'] is int
                                ? DateTime.fromMillisecondsSinceEpoch(m['ts'] as int)
                                : DateTime.now(),
                            isDark: isDark,
                            onJoin: () => _joinById(m['id'] ?? ''),
                            onCopy: () {
                              Clipboard.setData(ClipboardData(text: m['id'] ?? ''));
                              _errorHandler.showInfoSnackBar(context, '📋 ID copié !');
                            },
                          ),
                        );
                      },
                      childCount: _recentMeetings.length,
                    ),
                  ),
                ],

                SliverToBoxAdapter(child: const SizedBox(height: 32)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateBottomSheet() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateMeetingSheet(
        nameController: _meetingNameController,
        passwordController: _passwordController,
        showPassword: _showPassword,
        obscurePassword: _obscurePassword,
        isCreating: _isCreating,
        onTogglePassword: () => setState(() => _showPassword = !_showPassword),
        onToggleObscure: () => setState(() => _obscurePassword = !_obscurePassword),
        onSubmit: (MeetingMode mode, String description) {
          // Prepend mode tag to the meeting name
          final tag = _modeTag(mode);
          if (tag.isNotEmpty && !_meetingNameController.text.startsWith('[')) {
            _meetingNameController.text = '$tag ${_meetingNameController.text}'.trim();
          }
          Navigator.pop(context);
          _createMeeting(description: description);
        },
      ),
    );
  }

  String _modeTag(MeetingMode mode) {
    switch (mode) {
      case MeetingMode.standard: return '';
      case MeetingMode.business: return '[Business]';
      case MeetingMode.webinar: return '[Webinaire]';
      case MeetingMode.church: return '[Église]';
      case MeetingMode.live: return '[Live]';
      case MeetingMode.conference: return '[Conférence]';
    }
  }
}

// ─────────────────────────────────────────────
//  ANIMATED BACKGROUND ORBS
// ─────────────────────────────────────────────
class _AnimatedOrbs extends StatefulWidget {
  final bool isDark;
  const _AnimatedOrbs({required this.isDark});
  @override
  State<_AnimatedOrbs> createState() => _AnimatedOrbsState();
}

class _AnimatedOrbsState extends State<_AnimatedOrbs> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(duration: const Duration(seconds: 8), vsync: this)..repeat();
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        return Stack(children: [
          Positioned(
            top: -60 + math.sin(t * 2 * math.pi) * 30,
            right: -40 + math.cos(t * 2 * math.pi) * 20,
            child: _Orb(size: 220, color: const Color(0xFFE74C3C), opacity: widget.isDark ? 0.12 : 0.08),
          ),
          Positioned(
            bottom: 100 + math.cos(t * 2 * math.pi) * 20,
            left: -60 + math.sin(t * 2 * math.pi) * 15,
            child: _Orb(size: 180, color: const Color(0xFF5B5FFF), opacity: widget.isDark ? 0.1 : 0.06),
          ),
          Positioned(
            top: 300 + math.sin((t + 0.5) * 2 * math.pi) * 20,
            right: 20 + math.cos((t + 0.3) * 2 * math.pi) * 15,
            child: _Orb(size: 120, color: const Color(0xFF9B59B6), opacity: widget.isDark ? 0.08 : 0.05),
          ),
        ]);
      },
    );
  }
}

class _Orb extends StatelessWidget {
  final double size;
  final Color color;
  final double opacity;
  const _Orb({required this.size, required this.color, required this.opacity});
  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(colors: [color.withValues(alpha: opacity), color.withValues(alpha: 0)]),
    ),
  );
}

// ─────────────────────────────────────────────
//  BIG ACTION BUTTON
// ─────────────────────────────────────────────
class _BigActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final LinearGradient gradient;
  final VoidCallback onTap;
  const _BigActionButton({required this.icon, required this.label, required this.gradient, required this.onTap});
  @override
  State<_BigActionButton> createState() => _BigActionButtonState();
}

class _BigActionButtonState extends State<_BigActionButton> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(duration: const Duration(milliseconds: 120), vsync: this);
    _scale = Tween<double>(begin: 1, end: 0.95).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) { HapticFeedback.lightImpact(); _ctrl.forward(); },
      onTapUp: (_) { _ctrl.reverse(); widget.onTap(); },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          height: 130,
          decoration: BoxDecoration(
            gradient: widget.gradient,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: widget.gradient.colors.first.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 8))],
          ),
          child: Stack(
            children: [
              // Background decoration circle
              Positioned(
                right: -20, bottom: -20,
                child: Container(
                  width: 100, height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(widget.icon, color: Colors.white, size: 26),
                    ),
                    const Spacer(),
                    Text(widget.label,
                      style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15, height: 1.2),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  STAT ITEM
// ─────────────────────────────────────────────
class _StatItem extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _StatItem({required this.label, required this.value, required this.icon, required this.color});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Semantics(
        label: '$value $label',
        child: Column(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(value, style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 15, color: isDark ? Colors.white : const Color(0xFF1A1A2E))),
          Text(label, style: GoogleFonts.poppins(fontSize: 10, color: isDark ? Colors.white38 : Colors.black38)),
        ]),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(width: 1, height: 40, color: isDark ? Colors.white12 : Colors.black12, margin: const EdgeInsets.symmetric(horizontal: 4));
  }
}

// ─────────────────────────────────────────────
//  QUICK ACTION CHIP
// ─────────────────────────────────────────────
class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickAction({required this.icon, required this.label, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () { HapticFeedback.selectionClick(); onTap(); },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.1)),
          boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12)],
        ),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 6),
          Text(label, style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.black54)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  CREATE MEETING BOTTOM SHEET
// ─────────────────────────────────────────────
class _CreateMeetingSheet extends StatefulWidget {
  final TextEditingController nameController;
  final TextEditingController passwordController;
  final bool showPassword, obscurePassword, isCreating;
  final VoidCallback onTogglePassword, onToggleObscure;
  final void Function(MeetingMode mode, String description) onSubmit;

  const _CreateMeetingSheet({
    required this.nameController, required this.passwordController,
    required this.showPassword, required this.obscurePassword,
    required this.isCreating, required this.onTogglePassword,
    required this.onToggleObscure, required this.onSubmit,
  });

  @override
  State<_CreateMeetingSheet> createState() => _CreateMeetingSheetState();
}

class _CreateMeetingSheetState extends State<_CreateMeetingSheet> {
  MeetingMode _selectedMode = MeetingMode.standard;
  final _descriptionController = TextEditingController();

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  static const _modes = [
    (MeetingMode.standard, Icons.videocam, 'Standard'),
    (MeetingMode.business, Icons.business_center, 'Business'),
    (MeetingMode.webinar, Icons.cast_for_education, 'Webinaire'),
    (MeetingMode.church, Icons.church, 'Église'),
    (MeetingMode.live, Icons.live_tv, 'Live'),
    (MeetingMode.conference, Icons.groups, 'Conférence'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF12121E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.videocam_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Text('Nouvelle réunion', style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w800, color: isDark ? Colors.white : const Color(0xFF1A1A2E))),
          ]),
          const SizedBox(height: 16),
          // ── Meeting mode selector ──
          Text('Type de réunion', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600,
              color: isDark ? Colors.white54 : Colors.black45)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _modes.map((entry) {
                final mode = entry.$1;
                final icon = entry.$2;
                final label = entry.$3;
                final selected = _selectedMode == mode;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () { HapticFeedback.selectionClick(); setState(() => _selectedMode = mode); },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: selected ? AppColors.primaryGradient : null,
                        color: selected ? null : (isDark ? Colors.white.withValues(alpha: 0.07) : Colors.grey.withValues(alpha: 0.08)),
                        borderRadius: BorderRadius.circular(20),
                        border: selected ? null : Border.all(
                          color: isDark ? Colors.white.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(icon, size: 14, color: selected ? Colors.white : (isDark ? Colors.white54 : Colors.black45)),
                        const SizedBox(width: 5),
                        Text(label, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600,
                            color: selected ? Colors.white : (isDark ? Colors.white54 : Colors.black45))),
                      ]),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: widget.nameController,
            autofocus: true,
            style: GoogleFonts.poppins(fontWeight: FontWeight.w500, color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              hintText: 'Nom de la réunion',
              hintStyle: GoogleFonts.poppins(color: Colors.grey),
              prefixIcon: const Icon(Icons.edit_outlined, size: 20),
              filled: true,
              fillColor: isDark ? Colors.white.withValues(alpha: 0.07) : Colors.grey.withValues(alpha: 0.08),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionController,
            maxLines: 3,
            style: GoogleFonts.poppins(fontSize: 13, color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              hintText: 'Agenda / Description (optionnel)',
              hintStyle: GoogleFonts.poppins(color: Colors.grey, fontSize: 13),
              prefixIcon: const Icon(Icons.subject_outlined, size: 20),
              filled: true,
              fillColor: isDark ? Colors.white.withValues(alpha: 0.07) : Colors.grey.withValues(alpha: 0.08),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: widget.onTogglePassword,
            child: Row(children: [
              Icon(widget.showPassword ? Icons.lock_outline : Icons.lock_open_outlined, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(widget.showPassword ? 'Supprimer le code d\'accès' : 'Ajouter un code d\'accès',
                style: GoogleFonts.poppins(fontSize: 13, color: AppColors.primary, decoration: TextDecoration.underline, decorationColor: AppColors.primary)),
            ]),
          ),
          if (widget.showPassword) ...[
            const SizedBox(height: 12),
            TextField(
              controller: widget.passwordController,
              obscureText: widget.obscurePassword,
              keyboardType: TextInputType.number,
              style: GoogleFonts.poppins(color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                hintText: 'Code d\'accès',
                hintStyle: GoogleFonts.poppins(color: Colors.grey),
                prefixIcon: const Icon(Icons.lock_outline, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(widget.obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                  onPressed: widget.onToggleObscure,
                ),
                filled: true,
                fillColor: isDark ? Colors.white.withValues(alpha: 0.07) : Colors.grey.withValues(alpha: 0.08),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity, height: 54,
            child: ElevatedButton(
              onPressed: widget.isCreating ? null : () => widget.onSubmit(_selectedMode, _descriptionController.text.trim()),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 8,
                shadowColor: AppColors.primary.withValues(alpha: 0.5),
              ),
              child: widget.isCreating
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.rocket_launch, size: 18),
                    const SizedBox(width: 8),
                    Text('Démarrer', style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 16)),
                  ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  RECENT MEETING TILE
// ─────────────────────────────────────────────
class _RecentMeetingTile extends StatelessWidget {
  final String title;
  final String meetingId;
  final DateTime timestamp;
  final bool isDark;
  final VoidCallback onJoin;
  final VoidCallback onCopy;

  const _RecentMeetingTile({
    required this.title,
    required this.meetingId,
    required this.timestamp,
    required this.isDark,
    required this.onJoin,
    required this.onCopy,
  });

  Future<void> _openReport(BuildContext context) async {
    final snap = await FirebaseFirestore.instance
        .collection('meeting_reports')
        .doc(meetingId)
        .get();
    if (!context.mounted) return;
    if (!snap.exists) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Aucun rapport disponible pour cette réunion.',
            style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.grey.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      return;
    }
    final report = MeetingReportModel.fromJson(snap.data()!);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MeetingReportScreen(report: report)),
    );
  }

  String _timeAgo() {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Il y a ${diff.inHours}h';
    if (diff.inDays == 1) return 'Hier';
    return 'Il y a ${diff.inDays} jours';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.grey.withValues(alpha: 0.15),
        ),
      ),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.videocam, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color:
                          isDark ? Colors.white : AppColors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              Text(
                '${meetingId.length > 10 ? meetingId.substring(0, 10) : meetingId}  •  ${_timeAgo()}',
                style: GoogleFonts.poppins(
                    fontSize: 11, color: AppColors.textTertiary),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.copy_outlined, size: 18),
          color: AppColors.textTertiary,
          onPressed: onCopy,
          tooltip: 'Copier l\'ID',
        ),
        IconButton(
          icon: const Icon(Icons.bar_chart_rounded, size: 18),
          color: AppColors.secondary,
          onPressed: () => _openReport(context),
          tooltip: 'Voir le rapport',
        ),
        GestureDetector(
          onTap: onJoin,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('Rejoindre',
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }
}

