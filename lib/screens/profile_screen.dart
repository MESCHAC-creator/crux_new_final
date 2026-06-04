import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/theme_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/color_provider.dart';
import '../l10n/app_translations.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with SingleTickerProviderStateMixin {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  final _picker = ImagePicker();

  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  bool _isUpdatingPhoto = false;
  bool _isSavingName = false;
  int _meetingsHosted = 0;
  String? _localPhotoPath; // local file path for profile photo

  static const _photoKey = 'crux_local_photo_path';

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(duration: const Duration(milliseconds: 700), vsync: this);
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
    _loadAll();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_photoKey);
    final uid = _auth.currentUser?.uid;
    if (mounted) setState(() => _localPhotoPath = path);

    if (uid == null) return;
    try {
      final snap = await _db.collection('meetings')
          .where('organizerId', isEqualTo: uid)
          .get();
      if (mounted) setState(() => _meetingsHosted = snap.docs.length);
    } catch (_) {}
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 85, maxWidth: 600);
      if (picked == null) return;
      setState(() => _isUpdatingPhoto = true);

      // Copy to app documents directory for persistence
      final appDir = await _getAppDocDir();
      final dest = '$appDir/profile_photo.jpg';
      await File(picked.path).copy(dest);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_photoKey, dest);

      if (mounted) {
        setState(() {
          _localPhotoPath = dest;
          _isUpdatingPhoto = false;
        });
        _snack('✅ Photo mise à jour !');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUpdatingPhoto = false);
        _snack('❌ Impossible de charger la photo');
      }
    }
  }

  Future<String> _getAppDocDir() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  Future<void> _removePhoto() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_photoKey);
    if (_localPhotoPath != null) {
      try { await File(_localPhotoPath!).delete(); } catch (_) {}
    }
    if (mounted) {
      setState(() => _localPhotoPath = null);
      _snack('✅ Photo supprimée');
    }
  }

  void _showPhotoOptions(String lang) {
    final isDark = context.read<ThemeProvider>().isDark;
    final cp = context.read<ColorProvider>();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            color: isDark ? Colors.black.withValues(alpha: 0.85) : Colors.white.withValues(alpha: 0.95),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              Text(AppTranslations.t('change_photo', lang),
                  style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : Colors.black87)),
              const SizedBox(height: 16),
              _BottomSheetTile(
                icon: Icons.photo_library_outlined,
                label: AppTranslations.t('photo_gallery', lang),
                color: cp.primary,
                isDark: isDark,
                onTap: () { Navigator.pop(context); _pickPhoto(ImageSource.gallery); },
              ),
              _BottomSheetTile(
                icon: Icons.camera_alt_outlined,
                label: AppTranslations.t('photo_camera', lang),
                color: cp.secondary,
                isDark: isDark,
                onTap: () { Navigator.pop(context); _pickPhoto(ImageSource.camera); },
              ),
              if (_localPhotoPath != null)
                _BottomSheetTile(
                  icon: Icons.delete_outline,
                  label: AppTranslations.t('remove_photo', lang),
                  color: Colors.red,
                  isDark: isDark,
                  onTap: () { Navigator.pop(context); _removePhoto(); },
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _showEditNameDialog(String lang, bool isDark, ColorProvider cp) async {
    final ctrl = TextEditingController(text: _auth.currentUser?.displayName ?? '');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(AppTranslations.t('change_name', lang),
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black87)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: GoogleFonts.poppins(color: isDark ? Colors.white : Colors.black87),
          decoration: InputDecoration(
            hintText: AppTranslations.t('enter_new_name', lang),
            hintStyle: GoogleFonts.poppins(color: isDark ? Colors.white38 : Colors.black38),
            prefixIcon: Icon(Icons.person_outline, color: cp.primary),
            filled: true,
            fillColor: isDark ? const Color(0xFF252540) : const Color(0xFFF0EFF8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: cp.primary, width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppTranslations.t('cancel', lang),
                style: GoogleFonts.poppins(color: isDark ? Colors.white54 : Colors.black45)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: cp.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: Text(AppTranslations.t('save', lang),
                style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final newName = ctrl.text.trim();
    if (newName.isEmpty || newName == _auth.currentUser?.displayName) return;
    setState(() => _isSavingName = true);
    try {
      await _auth.currentUser!.updateDisplayName(newName);
      if (mounted) {
        setState(() => _isSavingName = false);
        _snack(AppTranslations.t('name_updated', lang));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSavingName = false);
        _snack('❌ $e');
      }
    }
  }

  Future<void> _showChangePasswordDialog(String lang, bool isDark, ColorProvider cp) async {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    bool obscure1 = true, obscure2 = true;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(AppTranslations.t('change_password', lang),
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black87)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: currentCtrl,
              obscureText: obscure1,
              style: GoogleFonts.poppins(color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                labelText: AppTranslations.t('current_password', lang),
                labelStyle: GoogleFonts.poppins(color: isDark ? Colors.white54 : Colors.black45),
                prefixIcon: Icon(Icons.lock_outline, color: cp.primary),
                suffixIcon: IconButton(
                  icon: Icon(obscure1 ? Icons.visibility_off : Icons.visibility,
                      color: isDark ? Colors.white38 : Colors.black38, size: 20),
                  onPressed: () => setS(() => obscure1 = !obscure1),
                ),
                filled: true,
                fillColor: isDark ? const Color(0xFF252540) : const Color(0xFFF0EFF8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: cp.primary, width: 2)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newCtrl,
              obscureText: obscure2,
              style: GoogleFonts.poppins(color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                labelText: AppTranslations.t('new_password', lang),
                labelStyle: GoogleFonts.poppins(color: isDark ? Colors.white54 : Colors.black45),
                prefixIcon: Icon(Icons.lock_reset, color: cp.secondary),
                suffixIcon: IconButton(
                  icon: Icon(obscure2 ? Icons.visibility_off : Icons.visibility,
                      color: isDark ? Colors.white38 : Colors.black38, size: 20),
                  onPressed: () => setS(() => obscure2 = !obscure2),
                ),
                filled: true,
                fillColor: isDark ? const Color(0xFF252540) : const Color(0xFFF0EFF8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: cp.secondary, width: 2)),
              ),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppTranslations.t('cancel', lang),
                  style: GoogleFonts.poppins(color: isDark ? Colors.white54 : Colors.black45)),
            ),
            ElevatedButton(
              onPressed: () async {
                final cur = currentCtrl.text.trim();
                final nw = newCtrl.text.trim();
                Navigator.pop(ctx);
                await _changePassword(cur, nw, lang);
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: cp.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: Text(AppTranslations.t('save', lang),
                  style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changePassword(String current, String newPass, String lang) async {
    if (current.isEmpty || newPass.isEmpty) {
      _snack('⚠️ Remplissez les deux champs');
      return;
    }
    if (newPass.length < 6) {
      _snack('⚠️ Le nouveau mot de passe doit faire au moins 6 caractères');
      return;
    }
    try {
      final user = _auth.currentUser!;
      final cred = EmailAuthProvider.credential(email: user.email!, password: current);
      await user.reauthenticateWithCredential(cred);
      await user.updatePassword(newPass);
      if (mounted) _snack(AppTranslations.t('password_updated', lang));
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        final msg = e.code == 'wrong-password' || e.code == 'invalid-credential'
            ? '❌ Mot de passe actuel incorrect'
            : '❌ ${e.message}';
        _snack(msg);
      }
    } catch (e) {
      if (mounted) _snack('❌ Erreur: $e');
    }
  }

  Future<void> _confirmDeleteAccount(String lang, bool isDark, ColorProvider cp) async {
    // Ask for password re-auth first if email provider
    final hasEmail = _auth.currentUser?.providerData.any((p) => p.providerId == 'password') ?? false;
    String? reAuthPassword;
    if (hasEmail) {
      final ctrl = TextEditingController();
      reAuthPassword = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Confirmer votre identité',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black87)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Entrez votre mot de passe pour confirmer la suppression',
                style: GoogleFonts.poppins(fontSize: 13, color: isDark ? Colors.white60 : Colors.black54)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              obscureText: true,
              autofocus: true,
              style: GoogleFonts.poppins(color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                labelText: AppTranslations.t('password', lang),
                labelStyle: GoogleFonts.poppins(color: isDark ? Colors.white54 : Colors.black45),
                prefixIcon: const Icon(Icons.lock_outline, color: Colors.red),
                filled: true,
                fillColor: isDark ? const Color(0xFF252540) : const Color(0xFFF0EFF8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.red, width: 2)),
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppTranslations.t('cancel', lang),
                style: GoogleFonts.poppins(color: isDark ? Colors.white54 : Colors.black45))),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: Text('Confirmer', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
      if (reAuthPassword == null || !mounted) return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Container(padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: const Icon(Icons.warning_outlined, color: Colors.red, size: 22)),
          const SizedBox(width: 12),
          Text(AppTranslations.t('delete_account', lang),
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: Colors.red)),
        ]),
        content: Text(AppTranslations.t('delete_confirm', lang),
            style: GoogleFonts.poppins(color: isDark ? Colors.white70 : Colors.black54, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppTranslations.t('cancel', lang),
              style: GoogleFonts.poppins(color: isDark ? Colors.white54 : Colors.black45))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: Text(AppTranslations.t('delete_account', lang),
                style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final user = _auth.currentUser!;
      if (hasEmail && reAuthPassword != null) {
        final cred = EmailAuthProvider.credential(email: user.email!, password: reAuthPassword);
        await user.reauthenticateWithCredential(cred);
      }
      await _db.collection('users').doc(user.uid).delete();
      await user.delete();
      if (mounted) Navigator.of(context).pushReplacementNamed('/login');
    } on FirebaseAuthException catch (e) {
      if (mounted) _snack('❌ ${e.message}');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Widget _buildAvatar(ColorProvider cp) {
    final user = _auth.currentUser;
    final initials = (user?.displayName?.isNotEmpty == true)
        ? user!.displayName!.split(' ').take(2).map((w) => w[0].toUpperCase()).join()
        : (user?.email?[0].toUpperCase() ?? 'U');

    Widget photo;
    if (_isUpdatingPhoto) {
      photo = Container(
        color: Colors.white.withValues(alpha: 0.2),
        child: const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)),
      );
    } else if (_localPhotoPath != null && File(_localPhotoPath!).existsSync()) {
      photo = Image.file(File(_localPhotoPath!), fit: BoxFit.cover);
    } else {
      photo = Container(
        decoration: BoxDecoration(gradient: cp.gradient),
        child: Center(child: Text(initials,
            style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 32))),
      );
    }

    return Stack(children: [
      GestureDetector(
        onTap: () => _showPhotoOptions(context.read<LocaleProvider>().locale.languageCode),
        child: Container(
          width: 90, height: 90,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 16)],
          ),
          child: ClipOval(child: photo),
        ),
      ),
      Positioned(
        right: 0, bottom: 0,
        child: GestureDetector(
          onTap: () => _showPhotoOptions(context.read<LocaleProvider>().locale.languageCode),
          child: Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: Colors.white, shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 6)],
            ),
            child: Icon(Icons.camera_alt, size: 16, color: cp.primary),
          ),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final localeProvider = context.watch<LocaleProvider>();
    final cp = context.watch<ColorProvider>();
    final isDark = themeProvider.isDark;
    final lang = localeProvider.locale.languageCode;
    final user = _auth.currentUser;
    final createdAt = user?.metadata.creationTime;
    final hasEmailProvider = user?.providerData.any((p) => p.providerId == 'password') ?? false;
    final hasGoogleProvider = user?.providerData.any((p) => p.providerId == 'google.com') ?? false;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0A14) : const Color(0xFFF0F2FF),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverAppBar(
              expandedHeight: 200,
              pinned: true,
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: Padding(
                padding: const EdgeInsets.all(8),
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                ),
              ),
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: BoxDecoration(gradient: cp.gradient),
                  child: SafeArea(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 8),
                        _buildAvatar(cp),
                        const SizedBox(height: 10),
                        Text(user?.displayName ?? user?.email?.split('@')[0] ?? 'User',
                            style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
                        Text(user?.email ?? '',
                            style: GoogleFonts.poppins(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
                      ],
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
                    // ── Stats ──
                    _SectionLabel(AppTranslations.t('account_stats', lang), cp.primary),
                    _GlassCard(isDark: isDark, child: Row(children: [
                      Expanded(child: _StatCard(
                        label: AppTranslations.t('meetings_hosted', lang),
                        value: '$_meetingsHosted',
                        icon: Icons.video_camera_front_outlined,
                        color: cp.primary, isDark: isDark,
                      )),
                      Container(width: 1, height: 60, color: isDark ? Colors.white12 : Colors.black12),
                      Expanded(child: _StatCard(
                        label: AppTranslations.t('member_since', lang),
                        value: createdAt != null
                            ? '${createdAt.day}/${createdAt.month}/${createdAt.year}'
                            : '—',
                        icon: Icons.calendar_today_outlined,
                        color: cp.secondary, isDark: isDark,
                      )),
                    ])),

                    const SizedBox(height: 24),

                    // ── Personal Info ──
                    _SectionLabel(AppTranslations.t('profile_info', lang), cp.primary),
                    _GlassCard(isDark: isDark, child: Column(children: [
                      _ProfileTile(
                        icon: Icons.person_outline, iconColor: cp.primary,
                        title: AppTranslations.t('display_name', lang),
                        subtitle: user?.displayName ?? '—',
                        isDark: isDark,
                        trailing: _isSavingName
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : Icon(Icons.edit_outlined, color: cp.primary, size: 20),
                        onTap: () => _showEditNameDialog(lang, isDark, cp),
                      ),
                      _ProfileDivider(isDark: isDark),
                      _ProfileTile(
                        icon: Icons.email_outlined, iconColor: const Color(0xFF0EA5E9),
                        title: AppTranslations.t('email', lang),
                        subtitle: user?.email ?? '—',
                        isDark: isDark, trailing: const SizedBox(),
                      ),
                    ])),

                    const SizedBox(height: 24),

                    // ── Sign-in methods ──
                    _SectionLabel(AppTranslations.t('sign_in_methods', lang), cp.primary),
                    _GlassCard(isDark: isDark, child: Column(children: [
                      if (hasEmailProvider) ...[
                        _ProfileTile(
                          icon: Icons.lock_outline, iconColor: const Color(0xFF6366F1),
                          title: AppTranslations.t('email_password', lang),
                          subtitle: user?.email ?? '',
                          isDark: isDark,
                          trailing: _Badge('Actif', Colors.green),
                        ),
                        if (hasGoogleProvider) _ProfileDivider(isDark: isDark),
                      ],
                      if (hasGoogleProvider)
                        _ProfileTile(
                          icon: Icons.g_mobiledata, iconColor: const Color(0xFF4285F4),
                          title: AppTranslations.t('google_account', lang),
                          subtitle: user?.email ?? '',
                          isDark: isDark,
                          trailing: _Badge('Google', const Color(0xFF4285F4)),
                        ),
                    ])),

                    const SizedBox(height: 24),

                    // ── Security (only for email/password accounts) ──
                    if (hasEmailProvider) ...[
                      _SectionLabel(AppTranslations.t('account_security', lang), cp.primary),
                      _GlassCard(isDark: isDark, child: _ProfileTile(
                        icon: Icons.lock_reset, iconColor: const Color(0xFFF59E0B),
                        title: AppTranslations.t('change_password', lang),
                        isDark: isDark,
                        trailing: Icon(Icons.chevron_right, color: isDark ? Colors.white30 : Colors.black26, size: 20),
                        onTap: () => _showChangePasswordDialog(lang, isDark, cp),
                      )),
                      const SizedBox(height: 24),
                    ],

                    // ── Danger Zone ──
                    _SectionLabel('Zone dangereuse', Colors.red),
                    _GlassCard(isDark: isDark, child: _ProfileTile(
                      icon: Icons.delete_forever_outlined, iconColor: Colors.red,
                      title: AppTranslations.t('delete_account', lang),
                      isDark: isDark,
                      trailing: Icon(Icons.chevron_right, color: Colors.red.withValues(alpha: 0.5), size: 20),
                      onTap: () => _confirmDeleteAccount(lang, isDark, cp),
                    )),

                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Reusable widgets ──────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  final Color color;
  const _SectionLabel(this.text, this.color);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10, left: 4),
    child: Text(text, style: GoogleFonts.poppins(
        fontSize: 12, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.8)),
  );
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  final bool isDark;
  const _GlassCard({required this.child, required this.isDark});
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.07) : Colors.white.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.6)),
        ),
        child: child,
      ),
    ),
  );
}

class _ProfileTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget trailing;
  final bool isDark;
  final VoidCallback? onTap;
  const _ProfileTile({required this.icon, required this.iconColor, required this.title,
      this.subtitle, required this.trailing, required this.isDark, this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap != null ? () { HapticFeedback.selectionClick(); onTap!(); } : null,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        Container(width: 38, height: 38,
          decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: iconColor, size: 20)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14,
              color: isDark ? Colors.white : Colors.black87)),
          if (subtitle != null && subtitle!.isNotEmpty)
            Text(subtitle!, style: GoogleFonts.poppins(fontSize: 12, color: isDark ? Colors.white54 : Colors.black45)),
        ])),
        trailing,
      ]),
    ),
  );
}

class _ProfileDivider extends StatelessWidget {
  final bool isDark;
  const _ProfileDivider({required this.isDark});
  @override
  Widget build(BuildContext context) => Divider(
    height: 1, thickness: 0.5, indent: 68,
    color: isDark ? Colors.white12 : Colors.black12,
  );
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  final bool isDark;
  const _StatCard({required this.label, required this.value, required this.icon, required this.color, required this.isDark});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: color, size: 26),
      const SizedBox(height: 6),
      Text(value, style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 20, color: isDark ? Colors.white : Colors.black87)),
      const SizedBox(height: 2),
      Text(label, textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 10, color: isDark ? Colors.white54 : Colors.black45)),
    ]),
  );
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
    child: Text(label, style: GoogleFonts.poppins(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
  );
}

class _BottomSheetTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;
  const _BottomSheetTile({required this.icon, required this.label, required this.color, required this.isDark, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 14),
        Text(label, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15,
            color: isDark ? Colors.white : Colors.black87)),
      ]),
    ),
  );
}
