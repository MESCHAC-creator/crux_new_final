import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/colors.dart';
import '../providers/theme_provider.dart';
import '../providers/locale_provider.dart';
import '../services/error_handler_service.dart';
import '../l10n/app_translations.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _errorHandler = ErrorHandlerService();
  bool _notificationsEnabled = true;
  String _videoQuality = 'Haute';

  @override
  void initState() {
    super.initState();
    _loadQuality();
  }

  Future<void> _loadQuality() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _videoQuality = prefs.getString('crux_video_quality') ?? 'Haute');
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final localeProvider = context.watch<LocaleProvider>();
    final isDark = themeProvider.isDark;
    final bgColor = isDark ? const Color(0xFF0F0F0F) : const Color(0xFFF5F3FF);
    final cardColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final textColor = isDark ? Colors.white : AppColors.textPrimary;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFE74C3C), Color(0xFF8E44AD)],
            ),
          ),
        ),
        title: Text(
          AppTranslations.t('settings', localeProvider.locale.languageCode),
          style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            _sectionTitle('Réunion', isDark),
            _card(
              cardColor: cardColor,
              child: Column(
                children: [
                  _settingTile(
                    icon: Icons.videocam_outlined,
                    title: 'Qualité vidéo',
                    trailing: Text(_videoQuality, style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textTertiary)),
                    onTap: () => _showQualityDialog(),
                    textColor: textColor,
                  ),
                  _divider(isDark),
                  _switchTile(
                    icon: Icons.mic_outlined,
                    title: 'Micro activé par défaut',
                    value: true,
                    onChanged: (_) => _errorHandler.showInfoSnackBar(context, '✅ Paramètre mis à jour'),
                    textColor: textColor,
                  ),
                  _divider(isDark),
                  _switchTile(
                    icon: Icons.videocam_outlined,
                    title: 'Caméra activée par défaut',
                    value: true,
                    onChanged: (_) => _errorHandler.showInfoSnackBar(context, '✅ Paramètre mis à jour'),
                    textColor: textColor,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            _sectionTitle('Apparence', isDark),
            _card(
              cardColor: cardColor,
              child: Column(
                children: [
                  _switchTile(
                    icon: Icons.dark_mode_outlined,
                    title: 'Mode sombre',
                    subtitle: isDark ? 'Activé' : 'Désactivé',
                    value: isDark,
                    onChanged: (val) {
                      context.read<ThemeProvider>().setDarkMode(val);
                      _errorHandler.showInfoSnackBar(context, val ? '🌙 Mode sombre activé' : '☀️ Mode clair activé');
                    },
                    textColor: textColor,
                    activeColor: AppColors.secondary,
                  ),
                  _divider(isDark),
                  _settingTile(
                    icon: Icons.language_outlined,
                    title: 'Langue',
                    trailing: Text(localeProvider.languageLabel, style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textTertiary)),
                    onTap: () => _showLanguageDialog(localeProvider),
                    textColor: textColor,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            _sectionTitle('Notifications', isDark),
            _card(
              cardColor: cardColor,
              child: _switchTile(
                icon: Icons.notifications_outlined,
                title: 'Notifications',
                subtitle: _notificationsEnabled ? 'Activées' : 'Désactivées',
                value: _notificationsEnabled,
                onChanged: (val) {
                  setState(() => _notificationsEnabled = val);
                  _errorHandler.showSuccessSnackBar(
                    context,
                    val ? '✅ Notifications activées' : '✅ Notifications désactivées',
                  );
                },
                textColor: textColor,
                activeColor: AppColors.success,
              ),
            ),
            const SizedBox(height: 20),

            _sectionTitle('À propos', isDark),
            _card(
              cardColor: cardColor,
              child: Column(
                children: [
                  _aboutRow('Version', '1.0.0', textColor),
                  _divider(isDark),
                  _aboutRow('Build', '1', textColor),
                  _divider(isDark),
                  _aboutRow('Développé par', 'CRUX Team', textColor),
                ],
              ),
            ),
            const SizedBox(height: 20),

            _sectionTitle(_legalTitle(localeProvider.locale.languageCode), isDark),
            _card(
              cardColor: cardColor,
              child: Column(
                children: [
                  _navTile(
                    icon: Icons.shield_outlined,
                    label: AppTranslations.t('privacy_policy', localeProvider.locale.languageCode),
                    textColor: textColor,
                    onTap: () => Navigator.pushNamed(context, '/privacy'),
                  ),
                  _divider(isDark),
                  _navTile(
                    icon: Icons.gavel,
                    label: AppTranslations.t('terms_of_use', localeProvider.locale.languageCode),
                    textColor: textColor,
                    onTap: () => Navigator.pushNamed(context, '/terms'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Support button
            _gradientButton(
              icon: Icons.headset_mic_outlined,
              label: 'Assistance',
              colors: const [Color(0xFF3498DB), Color(0xFF2980B9)],
              onTap: () => _errorHandler.showInfoSnackBar(context, '📧 support@crux.app'),
            ),
            const SizedBox(height: 12),
            _gradientButton(
              icon: Icons.share_outlined,
              label: 'Partager l\'app',
              colors: const [Color(0xFF8E44AD), Color(0xFF6C3483)],
              onTap: () => _errorHandler.showInfoSnackBar(context, '📱 Partagez CRUX avec vos contacts !'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.secondary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _card({required Color cardColor, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: child,
    );
  }

  Widget _divider(bool isDark) {
    return Divider(
      height: 1,
      indent: 56,
      color: isDark ? Colors.white.withOpacity(0.07) : Colors.grey.withOpacity(0.15),
    );
  }

  Widget _settingTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required Widget trailing,
    required VoidCallback onTap,
    required Color textColor,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
      title: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14, color: textColor)),
      subtitle: subtitle != null
          ? Text(subtitle, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textTertiary))
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          trailing,
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, color: AppColors.textTertiary, size: 18),
        ],
      ),
    );
  }

  Widget _switchTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required Function(bool) onChanged,
    required Color textColor,
    Color activeColor = AppColors.primary,
  }) {
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
      title: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14, color: textColor)),
      subtitle: subtitle != null
          ? Text(subtitle, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textTertiary))
          : null,
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: Colors.white,
        activeTrackColor: activeColor,
        inactiveThumbColor: Colors.white,
        inactiveTrackColor: Colors.grey.shade300,
      ),
    );
  }

  Widget _aboutRow(String label, String value, Color textColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14, color: textColor)),
          Text(value, style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textTertiary)),
        ],
      ),
    );
  }

  String _legalTitle(String lang) {
    switch (lang) {
      case 'en': return 'Legal';
      case 'es': return 'Legal';
      case 'de': return 'Rechtliches';
      default: return 'Légal';
    }
  }

  Widget _navTile({
    required IconData icon,
    required String label,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14, color: textColor))),
            const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _gradientButton({
    required IconData icon,
    required String label,
    required List<Color> colors,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: colors.first.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 5))],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Text(label, style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
          ],
        ),
      ),
    );
  }

  void _showQualityDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Qualité vidéo', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: ['Basse', 'Moyenne', 'Haute', 'Très haute'].map((q) {
              return RadioListTile<String>(
                title: Text(q, style: GoogleFonts.poppins()),
                value: q,
                groupValue: _videoQuality,
                activeColor: AppColors.primary,
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _videoQuality = val);
                    setDialogState(() {});
                    SharedPreferences.getInstance().then(
                        (p) => p.setString('crux_video_quality', val));
                    Navigator.pop(ctx);
                    _errorHandler.showSuccessSnackBar(context, '✅ Qualité: $val');
                  }
                },
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _showLanguageDialog(LocaleProvider localeProvider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Langue', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: LocaleProvider.languages.keys.map((lang) {
            return RadioListTile<String>(
              title: Text(lang, style: GoogleFonts.poppins()),
              value: lang,
              groupValue: localeProvider.languageLabel,
              activeColor: AppColors.secondary,
              onChanged: (val) {
                if (val != null) {
                  context.read<LocaleProvider>().setLanguage(val);
                  Navigator.pop(ctx);
                  _errorHandler.showSuccessSnackBar(context, '✅ Langue: $val');
                }
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}
