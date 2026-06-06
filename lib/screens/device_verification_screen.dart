import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/device_verification_service.dart';
import '../theme/colors.dart';
import '../providers/locale_provider.dart';
import '../l10n/app_translations.dart';

class DeviceVerificationScreen extends StatefulWidget {
  final VoidCallback onVerified;

  const DeviceVerificationScreen({required this.onVerified, super.key});

  @override
  State<DeviceVerificationScreen> createState() => _DeviceVerificationScreenState();
}

class _DeviceVerificationScreenState extends State<DeviceVerificationScreen> {
  late Future<(bool, String)> _verificationFuture;

  @override
  void initState() {
    super.initState();
    _verificationFuture = DeviceVerificationService.instance.verifyDeviceSecurity();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0C1A),
      body: Center(
        child: FutureBuilder<(bool, String)>(
          future: _verificationFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Color(0xFFB71C1C)),
                  const SizedBox(height: 20),
                  Text(
                    '🔒 Vérification sécurité device...',
                    style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14),
                  ),
                ],
              );
            }

            if (snapshot.hasError) {
              return _buildError('Erreur vérification: ${snapshot.error}');
            }

            final (isSecure, reason) = snapshot.data!;

            if (!isSecure) {
              return _buildError(reason);
            }

            // Verification passed — callback to proceed
            WidgetsBinding.instance.addPostFrameCallback((_) {
              widget.onVerified();
            });

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 56),
                const SizedBox(height: 16),
                Text(
                  '✅ Appareil vérifié',
                  style: GoogleFonts.poppins(
                    color: Colors.green,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildError(String message) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.security, color: Colors.red, size: 56),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14, height: 1.6),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => setState(() {
              _verificationFuture = DeviceVerificationService.instance.verifyDeviceSecurity();
            }),
            icon: const Icon(Icons.refresh),
            label: Builder(builder: (ctx2) { final l = Provider.of<LocaleProvider>(ctx2, listen: false).locale.languageCode; return Text(AppTranslations.t('retry', l), style: GoogleFonts.poppins()); }),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          ),
        ],
      ),
    );
  }
}
