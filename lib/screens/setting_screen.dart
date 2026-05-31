import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/colors.dart';
import '../services/error_handler_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _errorHandler = ErrorHandlerService();

  bool _notificationsEnabled = true;
  bool _darkModeEnabled = false;
  String _selectedLanguage = 'Français';
  String _videoQuality = 'Haute';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.whiteBg,
      appBar: AppBar(
        backgroundColor: AppColors.whiteBg,
        elevation: 1,
        title: Text(
          'Paramètres',
          style: GoogleFonts.poppins(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Paramètres de réunion
            _buildSectionTitle('Réunion'),
            _buildSettingTile(
              icon: Icons.videocam,
              title: 'Qualité vidéo',
              value: _videoQuality,
              onTap: () => _showQualityDialog(),
            ),
            _buildSwitchTile(
              icon: Icons.mic,
              title: 'Micro activé par défaut',
              value: true,
              onChanged: (_) => _errorHandler.showInfoSnackBar(
                context,
                '✅ Paramètre mis à jour',
              ),
            ),
            _buildSwitchTile(
              icon: Icons.videocam,
              title: 'Caméra activée par défaut',
              value: true,
              onChanged: (_) => _errorHandler.showInfoSnackBar(
                context,
                '✅ Paramètre mis à jour',
              ),
            ),
            const SizedBox(height: 24),

            // Paramètres généraux
            _buildSectionTitle('Général'),
            _buildSettingTile(
              icon: Icons.language,
              title: 'Langue',
              value: _selectedLanguage,
              onTap: () => _showLanguageDialog(),
            ),
            _buildSwitchTile(
              icon: Icons.notifications,
              title: 'Notifications',
              value: _notificationsEnabled,
              onChanged: (value) {
                setState(() => _notificationsEnabled = value);
                _errorHandler.showSuccessSnackBar(
                  context,
                  value ? '✅ Notifications activées' : '✅ Notifications désactivées',
                );
              },
            ),
            _buildSwitchTile(
              icon: Icons.dark_mode,
              title: 'Mode sombre',
              value: _darkModeEnabled,
              onChanged: (value) {
                setState(() => _darkModeEnabled = value);
                _errorHandler.showInfoSnackBar(
                  context,
                  value ? '🌙 Mode sombre activé' : '☀️ Mode clair activé',
                );
              },
            ),
            const SizedBox(height: 24),

            // À propos
            _buildSectionTitle('À propos'),
            _buildAboutTile('Version', '1.0.0'),
            _buildAboutTile('Build', '1'),
            _buildAboutTile('Développé par', 'CRUX Team'),
            const SizedBox(height: 24),

            // Actions
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () => _errorHandler.showInfoSnackBar(
                  context,
                  '📧 Email: support@crux.app',
                ),
                icon: const Icon(Icons.help_outline),
                label: Text(
                  'Assistance',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.info,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () => _errorHandler.showInfoSnackBar(
                  context,
                  '📱 Suivez-nous sur les réseaux sociaux',
                ),
                icon: const Icon(Icons.share),
                label: Text(
                  'Partager l\'app',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 12),
      child: Text(
        title,
        style: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.lightBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(
          title,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.textSecondary),
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required bool value,
    required Function(bool) onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.lightBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(
          title,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        trailing: Switch(
          value: value,
          onChanged: onChanged,
          activeColor: AppColors.primary,
        ),
      ),
    );
  }

  Widget _buildAboutTile(String title, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.lightBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  void _showQualityDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.whiteBg,
        title: Text(
          'Qualité vidéo',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: ['Basse', 'Moyenne', 'Haute', 'Très haute']
              .map((quality) => RadioListTile<String>(
            title: Text(quality),
            value: quality,
            groupValue: _videoQuality,
            onChanged: (value) {
              setState(() => _videoQuality = value!);
              Navigator.pop(ctx);
              _errorHandler.showSuccessSnackBar(
                context,
                '✅ Qualité vidéo: $value',
              );
            },
          ))
              .toList(),
        ),
      ),
    );
  }

  void _showLanguageDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.whiteBg,
        title: Text(
          'Langue',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: ['Français', 'English', 'Español', 'Deutsch']
              .map((lang) => RadioListTile<String>(
            title: Text(lang),
            value: lang,
            groupValue: _selectedLanguage,
            onChanged: (value) {
              setState(() => _selectedLanguage = value!);
              Navigator.pop(ctx);
              _errorHandler.showSuccessSnackBar(
                context,
                '✅ Langue: $value',
              );
            },
          ))
              .toList(),
        ),
      ),
    );
  }
}