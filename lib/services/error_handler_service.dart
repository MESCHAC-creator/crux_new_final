import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import '../theme/colors.dart';

class ErrorHandlerService {
  static final ErrorHandlerService _instance = ErrorHandlerService._internal();
  final _logger = Logger();

  factory ErrorHandlerService() {
    return _instance;
  }

  ErrorHandlerService._internal();

  void showErrorDialog(BuildContext context, String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.whiteBg,
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'OK',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void showSuccessSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: AppColors.success, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 8,
      ),
    );
  }

  void showInfoSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline, color: AppColors.info, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.info,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void showWarningSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.warning,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void logError(String source, String error) {
    _logger.e('[$source] ❌ $error');
  }

  String getFirebaseErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
        return '❌ Utilisateur non trouvé';
      case 'wrong-password':
        return '❌ Mot de passe incorrect';
      case 'email-already-in-use':
        return '❌ Cet email est déjà utilisé';
      case 'weak-password':
        return '❌ Mot de passe trop faible (min 6 caractères)';
      case 'network-request-failed':
        return '❌ Erreur réseau - Vérifiez votre connexion Internet';
      case 'invalid-email':
        return '❌ Email invalide';
      case 'user-disabled':
        return '❌ Compte désactivé';
      case 'too-many-requests':
        return '⏱️ Trop de tentatives - Attendez quelques minutes';
      default:
        return '❌ Erreur: $code';
    }
  }

  String getAgoraErrorMessage(int errorCode) {
    switch (errorCode) {
      case 101:
        return '❌ App ID Agora invalide';
      case 103:
        return '❌ Token invalide ou expiré';
      case 109:
        return '❌ Impossible de rejoindre le canal';
      case 119:
        return '⏱️ Délai d\'attente dépassé';
      case 160:
        return '📷 Permission caméra requise';
      case 161:
        return '🎤 Permission microphone requise';
      default:
        return '❌ Erreur Agora: $errorCode';
    }
  }
}