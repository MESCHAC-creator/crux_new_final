import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/colors.dart';
import '../providers/theme_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/color_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/error_handler_service.dart';
import '../services/pro_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  final _errorHandler = ErrorHandlerService();
  final _proService = ProService();
  bool _notificationsEnabled = true;
  bool _micDefault = true;
  bool _camDefault = true;
  bool _isPro = false;
  String _videoQuality = 'HD (720p)';
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(duration: const Duration(milliseconds: 600), vsync: this);
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
    _load();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _videoQuality = prefs.getString('crux_video_quality') ?? 'HD (720p)';
      _micDefault = prefs.getBool('crux_mic_default') ?? true;
      _camDefault = prefs.getBool('crux_cam_default') ?? true;
      _notificationsEnabled = prefs.getBool('crux_notifications') ?? true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final localeProvider = context.watch<LocaleProvider>();
    final colorProvider = context.watch<ColorProvider>();
    final isDark = themeProvider.isDark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [const Color(0xFF0A0A14), const Color(0xFF0F0F1E), const Color(0xFF0A0A14)]
                : [const Color(0xFFF0F2FF), const Color(0xFFE8EEFF), const Color(0xFFF0F2FF)],
          ),
        ),
        child: FadeTransition(
          opacity: _fadeAnim,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ── Glass App Bar ──────────────────────────────
              SliverAppBar(
                expandedHeight: 120,
                pinned: true,
                backgroundColor: Colors.transparent,
                elevation: 0,
                flexibleSpace: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: FlexibleSpaceBar(
                      background: Container(
                        decoration: BoxDecoration(
                          gradient: colorProvider.gradient,
                        ),
                        child: SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                            child: Align(
                              alignment: Alignment.bottomLeft,
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Text('Paramètres',
                                  style: GoogleFonts.poppins(
                                    fontSize: 28, fontWeight: FontWeight.w800,
                                    color: Colors.white, letterSpacing: -0.5,
                                  )),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                leading: Padding(
                  padding: const EdgeInsets.all(8),
                  child: _GlassButton(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // ── COULEUR D'ACCENT ─────────────────────────────
                      _SectionLabel('Couleur de l\'application', colorProvider.primary),
                      _GlassCard(
                        isDark: isDark,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Container(
                                  width: 40, height: 40,
                                  decoration: BoxDecoration(
                                    gradient: colorProvider.gradient,
                                    shape: BoxShape.circle,
                                    boxShadow: [BoxShadow(color: colorProvider.primary.withValues(alpha: 0.4), blurRadius: 12)],
                                  ),
                                  child: const Icon(Icons.palette_outlined, color: Colors.white, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('Thème actuel', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: isDark ? Colors.white : Colors.black87)),
                                  Text(colorProvider.name, style: GoogleFonts.poppins(fontSize: 12, color: isDark ? Colors.white54 : Colors.black45)),
                                ]),
                              ]),
                              const SizedBox(height: 16),
                              // Color orbs grid
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: List.generate(ColorProvider.palette.length, (i) {
                                  final opt = ColorProvider.palette[i];
                                  final selected = colorProvider.selectedIndex == i;
                                  return GestureDetector(
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      colorProvider.setColor(i);
                                    },
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 250),
                                      width: 52, height: 52,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(colors: [opt.start, opt.end], begin: Alignment.topLeft, end: Alignment.bottomRight),
                                        shape: BoxShape.circle,
                                        border: selected ? Border.all(color: Colors.white, width: 3) : null,
                                        boxShadow: [
                                          BoxShadow(
                                            color: opt.start.withValues(alpha: selected ? 0.6 : 0.25),
                                            blurRadius: selected ? 16 : 6,
                                            spreadRadius: selected ? 2 : 0,
                                          ),
                                        ],
                                      ),
                                      child: selected
                                          ? const Icon(Icons.check, color: Colors.white, size: 22)
                                          : null,
                                    ),
                                  );
                                }),
                              ),
                              const SizedBox(height: 8),
                              // Color names
                              Wrap(
                                spacing: 10,
                                runSpacing: 6,
                                children: List.generate(ColorProvider.palette.length, (i) {
                                  final opt = ColorProvider.palette[i];
                                  final selected = colorProvider.selectedIndex == i;
                                  return AnimatedContainer(
                                    duration: const Duration(milliseconds: 250),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: selected ? colorProvider.primary.withValues(alpha: 0.15) : Colors.transparent,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(opt.name,
                                      style: GoogleFonts.poppins(
                                        fontSize: 10, fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                                        color: selected ? colorProvider.primary : (isDark ? Colors.white38 : Colors.black38),
                                      )),
                                  );
                                }),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // ── APPARENCE ────────────────────────────────────
                      _SectionLabel('Apparence', colorProvider.primary),
                      _GlassCard(
                        isDark: isDark,
                        child: Column(children: [
                          _GlassTile(
                            icon: isDark ? Icons.dark_mode : Icons.light_mode_outlined,
                            iconColor: isDark ? const Color(0xFF6366F1) : const Color(0xFFF59E0B),
                            title: 'Mode sombre',
                            subtitle: isDark ? 'Activé' : 'Désactivé',
                            isDark: isDark,
                            trailing: _GlassSwitch(
                              value: isDark,
                              activeColor: colorProvider.primary,
                              onChanged: (val) {
                                HapticFeedback.selectionClick();
                                context.read<ThemeProvider>().setDarkMode(val);
                              },
                            ),
                          ),
                          _GlassDivider(isDark: isDark),
                          _GlassTile(
                            icon: Icons.language_outlined,
                            iconColor: const Color(0xFF10B981),
                            title: 'Langue',
                            subtitle: localeProvider.languageLabel,
                            isDark: isDark,
                            trailing: Icon(Icons.chevron_right, color: isDark ? Colors.white30 : Colors.black26, size: 20),
                            onTap: () => _showLanguageDialog(localeProvider, colorProvider),
                          ),
                        ]),
                      ),

                      const SizedBox(height: 24),

                      // ── RÉUNION ──────────────────────────────────────
                      _SectionLabel('Réunion', colorProvider.primary),
                      _GlassCard(
                        isDark: isDark,
                        child: Column(children: [
                          _GlassTile(
                            icon: Icons.hd_outlined,
                            iconColor: const Color(0xFF0EA5E9),
                            title: 'Qualité vidéo',
                            subtitle: _videoQuality,
                            isDark: isDark,
                            trailing: Icon(Icons.chevron_right, color: isDark ? Colors.white30 : Colors.black26, size: 20),
                            onTap: () => _showQualityDialog(colorProvider),
                          ),
                          _GlassDivider(isDark: isDark),
                          _GlassTile(
                            icon: Icons.mic_outlined,
                            iconColor: const Color(0xFF27AE60),
                            title: 'Micro activé par défaut',
                            isDark: isDark,
                            trailing: _GlassSwitch(
                              value: _micDefault,
                              activeColor: colorProvider.primary,
                              onChanged: (val) async {
                                HapticFeedback.selectionClick();
                                setState(() => _micDefault = val);
                                final p = await SharedPreferences.getInstance();
                                p.setBool('crux_mic_default', val);
                              },
                            ),
                          ),
                          _GlassDivider(isDark: isDark),
                          _GlassTile(
                            icon: Icons.videocam_outlined,
                            iconColor: colorProvider.primary,
                            title: 'Caméra activée par défaut',
                            isDark: isDark,
                            trailing: _GlassSwitch(
                              value: _camDefault,
                              activeColor: colorProvider.primary,
                              onChanged: (val) async {
                                HapticFeedback.selectionClick();
                                setState(() => _camDefault = val);
                                final p = await SharedPreferences.getInstance();
                                p.setBool('crux_cam_default', val);
                              },
                            ),
                          ),
                        ]),
                      ),

                      const SizedBox(height: 24),

                      // ── NOTIFICATIONS ────────────────────────────────
                      _SectionLabel('Notifications', colorProvider.primary),
                      _GlassCard(
                        isDark: isDark,
                        child: _GlassTile(
                          icon: Icons.notifications_outlined,
                          iconColor: const Color(0xFFF59E0B),
                          title: 'Notifications push',
                          subtitle: _notificationsEnabled ? 'Activées' : 'Désactivées',
                          isDark: isDark,
                          trailing: _GlassSwitch(
                            value: _notificationsEnabled,
                            activeColor: colorProvider.primary,
                            onChanged: (val) async {
                              HapticFeedback.selectionClick();
                              setState(() => _notificationsEnabled = val);
                              final p = await SharedPreferences.getInstance();
                              p.setBool('crux_notifications', val);
                            },
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // ── ABONNEMENT ───────────────────────────────────
                      _SectionLabel('Abonnement', colorProvider.primary),
                      GestureDetector(
                        onTap: () async {
                          final uid = (await SharedPreferences.getInstance()).getString('crux_uid') ?? '';
                          if (_isPro) {
                            _errorHandler.showInfoSnackBar(context, '✅ Vous êtes déjà Crux Pro !');
                          } else {
                            try {
                              await _proService.startPayment(userId: uid, userName: 'Utilisateur');
                            } catch (_) {}
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFD700), Color(0xFFFFA500), Color(0xFFFF6B35)],
                              begin: Alignment.topLeft, end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [BoxShadow(color: const Color(0xFFFFD700).withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 8))],
                          ),
                          child: Row(children: [
                            const Icon(Icons.workspace_premium, color: Colors.white, size: 32),
                            const SizedBox(width: 14),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(_isPro ? 'Crux Pro Actif ✓' : 'Passer à Crux Pro',
                                style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                              Text(_isPro ? 'Réunions illimitées actives' : '25 000 FCFA/mois · Réunions illimitées',
                                style: GoogleFonts.poppins(color: Colors.white.withValues(alpha: 0.85), fontSize: 12)),
                            ])),
                            if (!_isPro)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                                child: Text('Activer', style: GoogleFonts.poppins(color: const Color(0xFFFFA500), fontWeight: FontWeight.w800, fontSize: 13)),
                              ),
                          ]),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // ── LÉGAL ────────────────────────────────────────
                      _SectionLabel('Légal & Support', colorProvider.primary),
                      _GlassCard(
                        isDark: isDark,
                        child: Column(children: [
                          _GlassTile(
                            icon: Icons.shield_outlined,
                            iconColor: const Color(0xFF6366F1),
                            title: 'Politique de confidentialité',
                            isDark: isDark,
                            trailing: Icon(Icons.chevron_right, color: isDark ? Colors.white30 : Colors.black26, size: 20),
                            onTap: () => Navigator.pushNamed(context, '/privacy'),
                          ),
                          _GlassDivider(isDark: isDark),
                          _GlassTile(
                            icon: Icons.gavel_outlined,
                            iconColor: const Color(0xFFEF4444),
                            title: 'Conditions d\'utilisation',
                            isDark: isDark,
                            trailing: Icon(Icons.chevron_right, color: isDark ? Colors.white30 : Colors.black26, size: 20),
                            onTap: () => Navigator.pushNamed(context, '/terms'),
                          ),
                          _GlassDivider(isDark: isDark),
                          _GlassTile(
                            icon: Icons.headset_mic_outlined,
                            iconColor: const Color(0xFF0EA5E9),
                            title: 'Assistance',
                            subtitle: 'kouakouchristevann@gmail.com',
                            isDark: isDark,
                            trailing: Icon(Icons.chevron_right, color: isDark ? Colors.white30 : Colors.black26, size: 20),
                            onTap: () async {
                              final uri = Uri(scheme: 'mailto', path: 'kouakouchristevann@gmail.com', query: 'subject=Support CRUX');
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri);
                              }
                            },
                          ),
                        ]),
                      ),

                      const SizedBox(height: 24),

                      // ── À PROPOS ─────────────────────────────────────
                      _GlassCard(
                        isDark: isDark,
                        child: Column(children: [
                          _GlassTile(icon: Icons.info_outline, iconColor: Colors.grey, title: 'Version', subtitle: '1.0.0', isDark: isDark, trailing: const SizedBox()),
                          _GlassDivider(isDark: isDark),
                          _GlassTile(icon: Icons.build_outlined, iconColor: Colors.grey, title: 'Build', subtitle: '1', isDark: isDark, trailing: const SizedBox()),
                          _GlassDivider(isDark: isDark),
                          _GlassTile(icon: Icons.business_outlined, iconColor: colorProvider.primary, title: 'Développé par', subtitle: 'CRUX Team', isDark: isDark, trailing: const SizedBox()),
                        ]),
                      ),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showQualityDialog(ColorProvider cp) {
    final qualities = ['Basse (360p)', 'Moyenne (480p)', 'HD (720p)', 'Full HD (1080p)'];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        final isDark = context.read<ThemeProvider>().isDark;
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              color: isDark ? Colors.black.withValues(alpha: 0.8) : Colors.white.withValues(alpha: 0.92),
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 20),
                  Text('Qualité vidéo', style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.black87)),
                  const SizedBox(height: 16),
                  ...qualities.map((q) => GestureDetector(
                    onTap: () async {
                      HapticFeedback.selectionClick();
                      setState(() => _videoQuality = q);
                      final p = await SharedPreferences.getInstance();
                      await p.setString('crux_video_quality', q);
                      if (mounted) Navigator.pop(context);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _videoQuality == q ? cp.primary.withValues(alpha: 0.15) : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _videoQuality == q ? cp.primary : Colors.transparent, width: 2),
                      ),
                      child: Row(children: [
                        Icon(Icons.hd_outlined, color: _videoQuality == q ? cp.primary : Colors.grey, size: 22),
                        const SizedBox(width: 12),
                        Text(q, style: GoogleFonts.poppins(fontWeight: _videoQuality == q ? FontWeight.w700 : FontWeight.w500, color: _videoQuality == q ? cp.primary : (isDark ? Colors.white70 : Colors.black54))),
                        const Spacer(),
                        if (_videoQuality == q) Icon(Icons.check_circle, color: cp.primary, size: 20),
                      ]),
                    ),
                  )),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showLanguageDialog(LocaleProvider lp, ColorProvider cp) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        final isDark = context.read<ThemeProvider>().isDark;
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              color: isDark ? Colors.black.withValues(alpha: 0.8) : Colors.white.withValues(alpha: 0.92),
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 20),
                  Text('Langue', style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.black87)),
                  const SizedBox(height: 16),
                  ...LocaleProvider.languages.keys.map((lang) => GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      context.read<LocaleProvider>().setLanguage(lang);
                      Navigator.pop(context);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: lp.languageLabel == lang ? cp.primary.withValues(alpha: 0.15) : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: lp.languageLabel == lang ? cp.primary : Colors.transparent, width: 2),
                      ),
                      child: Row(children: [
                        Text(lang, style: GoogleFonts.poppins(fontWeight: lp.languageLabel == lang ? FontWeight.w700 : FontWeight.w500, color: lp.languageLabel == lang ? cp.primary : (isDark ? Colors.white70 : Colors.black54))),
                        const Spacer(),
                        if (lp.languageLabel == lang) Icon(Icons.check_circle, color: cp.primary, size: 20),
                      ]),
                    ),
                  )),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
//  GLASS COMPONENTS
// ─────────────────────────────────────────────

class _GlassCard extends StatelessWidget {
  final bool isDark;
  final Widget child;
  const _GlassCard({required this.isDark, required this.child});
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.8), width: 1),
            boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, 4))],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _GlassTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final bool isDark;
  final Widget trailing;
  final VoidCallback? onTap;

  const _GlassTile({
    required this.icon, required this.iconColor, required this.title,
    required this.isDark, required this.trailing,
    this.subtitle, this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap != null ? () { HapticFeedback.selectionClick(); onTap!(); } : null,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14, color: isDark ? Colors.white : Colors.black87)),
            if (subtitle != null)
              Text(subtitle!, style: GoogleFonts.poppins(fontSize: 12, color: isDark ? Colors.white38 : Colors.black38)),
          ])),
          trailing,
        ]),
      ),
    );
  }
}

class _GlassDivider extends StatelessWidget {
  final bool isDark;
  const _GlassDivider({required this.isDark});
  @override
  Widget build(BuildContext context) => Divider(
    height: 1, indent: 68,
    color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06),
  );
}

class _GlassSwitch extends StatelessWidget {
  final bool value;
  final Color activeColor;
  final Function(bool) onChanged;
  const _GlassSwitch({required this.value, required this.activeColor, required this.onChanged});
  @override
  Widget build(BuildContext context) => Switch(
    value: value, onChanged: onChanged,
    activeColor: Colors.white, activeTrackColor: activeColor,
    inactiveThumbColor: Colors.white, inactiveTrackColor: Colors.grey.shade300,
  );
}

class _GlassButton extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;
  const _GlassButton({required this.onTap, required this.child});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: child,
        ),
      ),
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final Color color;
  const _SectionLabel(this.text, this.color);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10, left: 4),
    child: Text(text.toUpperCase(),
      style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: color, letterSpacing: 1.2)),
  );
}
