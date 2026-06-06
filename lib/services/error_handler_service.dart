import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import '../theme/colors.dart';
import '../l10n/app_translations.dart';

class ErrorHandlerService {
  static final ErrorHandlerService _instance = ErrorHandlerService._internal();
  final _logger = Logger();

  factory ErrorHandlerService() => _instance;
  ErrorHandlerService._internal();

  // ── Dialogs ────────────────────────────────────────────────────────────────

  void showErrorDialog(BuildContext context, String title, String message) {
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.whiteBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: const Icon(Icons.error_outline, color: AppColors.error, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: GoogleFonts.poppins(
              color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 17))),
        ]),
        content: Text(message, style: GoogleFonts.poppins(
            color: AppColors.textSecondary, fontSize: 14, height: 1.5)),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('OK', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void showInfoDialog(BuildContext context, String title, String message) {
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.whiteBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: AppColors.info.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: const Icon(Icons.info_outline, color: AppColors.info, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: GoogleFonts.poppins(
              color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 17))),
        ]),
        content: Text(message, style: GoogleFonts.poppins(
            color: AppColors.textSecondary, fontSize: 14, height: 1.5)),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.info,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('OK', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ── Snackbars ──────────────────────────────────────────────────────────────

  void showError(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.error_outline, color: Colors.white, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: GoogleFonts.poppins(
            color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500))),
      ]),
      backgroundColor: AppColors.error,
      duration: const Duration(seconds: 4),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void showSuccessSnackBar(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: GoogleFonts.poppins(
            color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500))),
      ]),
      backgroundColor: AppColors.success,
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void showWarningSnackBar(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: GoogleFonts.poppins(
            color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500))),
      ]),
      backgroundColor: const Color(0xFFF59E0B),
      duration: const Duration(seconds: 4),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void showInfoSnackBar(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.info_outline, color: Colors.white, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: GoogleFonts.poppins(
            color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500))),
      ]),
      backgroundColor: AppColors.info,
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ── Firebase error mapping ─────────────────────────────────────────────────

  /// Returns a user-friendly message for any Firebase Auth error code.
  String getFirebaseErrorMessage(String code) {
    switch (code) {
      // ── Authentication errors ──
      case 'wrong-password':
      case 'invalid-credential':
      case 'INVALID_LOGIN_CREDENTIALS':
        return 'Mot de passe incorrect. Vérifiez et réessayez.';
      case 'user-not-found':
        return 'Aucun compte trouvé avec cette adresse email.';
      case 'invalid-email':
        return 'Format d\'email invalide. Exemple : nom@domaine.com';
      case 'email-already-in-use':
        return 'Cette adresse email est déjà utilisée par un autre compte.';
      case 'weak-password':
        return 'Mot de passe trop faible. Utilisez au moins 6 caractères.';
      case 'user-disabled':
        return 'Ce compte a été désactivé. Contactez le support.';
      case 'too-many-requests':
        return 'Trop de tentatives échouées. Réessayez dans quelques minutes.';
      case 'operation-not-allowed':
        return 'Cette méthode de connexion n\'est pas activée.';

      // ── Network errors ──
      case 'network-request-failed':
        return 'Pas de connexion Internet. Vérifiez votre réseau et réessayez.';

      // ── Account linking ──
      case 'account-exists-with-different-credential':
        return 'Un compte existe déjà avec cet email via une autre méthode de connexion.';
      case 'credential-already-in-use':
        return 'Ces identifiants sont déjà associés à un autre compte.';
      case 'provider-already-linked':
        return 'Ce fournisseur est déjà lié à votre compte.';
      case 'no-such-provider':
        return 'Fournisseur de connexion introuvable.';

      // ── Session errors ──
      case 'requires-recent-login':
        return 'Session expirée. Déconnectez-vous et reconnectez-vous pour effectuer cette action.';
      case 'user-token-expired':
        return 'Votre session a expiré. Reconnectez-vous.';

      // ── Password reset ──
      case 'expired-action-code':
        return 'Le lien a expiré. Demandez un nouveau lien de réinitialisation.';
      case 'invalid-action-code':
        return 'Lien invalide ou déjà utilisé. Demandez un nouveau lien.';
      case 'missing-email':
        return 'Entrez votre adresse email.';

      // ── Verification ──
      case 'invalid-verification-code':
        return 'Code de vérification invalide.';
      case 'invalid-verification-id':
        return 'Session de vérification invalide. Réessayez.';

      // ── Google Sign-In ──
      case 'popup-closed-by-user':
      case 'cancelled-popup-request':
        return 'Connexion annulée.';

      // ── Quota ──
      case 'quota-exceeded':
        return 'Limite du service atteinte. Réessayez plus tard.';

      // ── Default ──
      default:
        if (code.contains('network')) {
          return 'Problème de connexion réseau. Vérifiez Internet.';
        }
        return 'Une erreur est survenue. Réessayez.';
    }
  }

  /// Converts any exception/error string into a clean user-friendly message.
  String cleanErrorMessage(String raw) {
    final msg = raw.replaceAll('Exception: ', '').trim();

    // Firebase error codes embedded in message
    if (msg.contains('wrong-password') || msg.contains('invalid-credential') ||
        msg.contains('INVALID_LOGIN_CREDENTIALS')) {
      return 'Mot de passe incorrect. Vérifiez et réessayez.';
    }
    if (msg.contains('user-not-found')) {
      return 'Aucun compte trouvé avec cette adresse email.';
    }
    if (msg.contains('email-already-in-use')) {
      return 'Cette adresse email est déjà utilisée.';
    }
    if (msg.contains('weak-password')) {
      return 'Mot de passe trop faible (minimum 6 caractères).';
    }
    if (msg.contains('invalid-email')) {
      return 'Format d\'email invalide.';
    }
    if (msg.contains('too-many-requests')) {
      return 'Trop de tentatives. Attendez quelques minutes.';
    }
    if (msg.contains('network') || msg.contains('Network')) {
      return 'Pas de connexion Internet. Vérifiez votre réseau.';
    }
    if (msg.contains('user-disabled')) {
      return 'Ce compte est désactivé. Contactez le support.';
    }
    if (msg.contains('requires-recent-login')) {
      return 'Session expirée. Reconnectez-vous pour continuer.';
    }
    if (msg.contains('account-exists-with-different-credential')) {
      return 'Ce compte existe déjà avec une autre méthode de connexion.';
    }
    if (msg.contains('permission-denied')) {
      return 'Accès refusé. Vous n\'avez pas les droits nécessaires.';
    }
    if (msg.contains('not-found')) {
      return 'Données introuvables.';
    }
    if (msg.contains('cancelled') || msg.contains('canceled')) {
      return 'Opération annulée.';
    }

    // If message is already clean and readable, return as-is (max 120 chars)
    if (msg.length < 120 && !msg.contains('[') && !msg.contains('{')) {
      return msg;
    }
    return 'Une erreur est survenue. Réessayez.';
  }

  /// Maps meeting-specific errors to user-friendly messages.
  String getMeetingErrorMessage(String raw) {
    if (raw.contains('verrouillée') || raw.contains('locked')) {
      return '🔒 Cette réunion est verrouillée par l\'hôte.';
    }
    if (raw.contains('mot de passe') || raw.contains('password') || raw.contains('incorrect')) {
      return '🔑 Code d\'accès incorrect. Vérifiez et réessayez.';
    }
    if (raw.contains('introuvable') || raw.contains('not-found') || raw.contains('n\'existe pas')) {
      return '🔍 Réunion introuvable. Vérifiez l\'ID saisi.';
    }
    if (raw.contains('network') || raw.contains('réseau')) {
      return '📡 Pas de connexion Internet.';
    }
    return cleanErrorMessage(raw);
  }

  /// Returns a user-friendly translated message for any Firebase Auth error code.
  String getFirebaseErrorMessageL(String code, String lang) {
    switch (code) {
      case 'wrong-password':
      case 'invalid-credential':
      case 'INVALID_LOGIN_CREDENTIALS':
        return AppTranslations.t('auth_wrong_pwd', lang);
      case 'user-not-found':
        return AppTranslations.t('auth_no_account', lang);
      case 'invalid-email':
        return AppTranslations.t('auth_invalid_email_fmt', lang);
      case 'email-already-in-use':
        return AppTranslations.t('auth_email_used', lang);
      case 'weak-password':
        return AppTranslations.t('auth_weak_pwd', lang);
      case 'user-disabled':
        return AppTranslations.t('auth_disabled', lang);
      case 'too-many-requests':
        return AppTranslations.t('auth_too_many', lang);
      case 'operation-not-allowed':
        return AppTranslations.t('auth_not_allowed', lang);
      case 'network-request-failed':
        return AppTranslations.t('auth_no_network', lang);
      case 'account-exists-with-different-credential':
        return AppTranslations.t('auth_other_method', lang);
      case 'requires-recent-login':
      case 'user-token-expired':
        return AppTranslations.t('auth_session_expired', lang);
      case 'expired-action-code':
        return AppTranslations.t('auth_link_expired', lang);
      case 'invalid-action-code':
        return AppTranslations.t('auth_link_invalid', lang);
      case 'popup-closed-by-user':
      case 'cancelled-popup-request':
        return AppTranslations.t('auth_cancelled', lang);
      case 'quota-exceeded':
        return AppTranslations.t('auth_limit', lang);
      default:
        if (code.contains('network')) return AppTranslations.t('auth_network_issue', lang);
        return AppTranslations.t('auth_unknown', lang);
    }
  }

  /// Converts any exception/error string into a clean translated user-friendly message.
  String cleanErrorMessageL(String raw, String lang) {
    final msg = raw.replaceAll('Exception: ', '').trim();
    if (msg.contains('wrong-password') || msg.contains('invalid-credential') ||
        msg.contains('INVALID_LOGIN_CREDENTIALS') || msg.contains('incorrect')) {
      return AppTranslations.t('auth_wrong_pwd', lang);
    }
    if (msg.contains('user-not-found')) return AppTranslations.t('auth_no_account', lang);
    if (msg.contains('email-already-in-use')) return AppTranslations.t('auth_email_used', lang);
    if (msg.contains('weak-password')) return AppTranslations.t('auth_weak_pwd', lang);
    if (msg.contains('invalid-email')) return AppTranslations.t('auth_invalid_email_fmt', lang);
    if (msg.contains('too-many-requests')) return AppTranslations.t('auth_too_many', lang);
    if (msg.contains('network') || msg.contains('Network')) return AppTranslations.t('auth_no_network', lang);
    if (msg.contains('user-disabled')) return AppTranslations.t('auth_disabled', lang);
    if (msg.contains('requires-recent-login')) return AppTranslations.t('auth_session_expired', lang);
    if (msg.contains('account-exists-with-different-credential')) return AppTranslations.t('auth_other_method', lang);
    if (msg.contains('permission-denied')) return AppTranslations.t('auth_unknown', lang);
    if (msg.contains('cancelled') || msg.contains('canceled')) return AppTranslations.t('auth_cancelled', lang);
    if (msg.length < 120 && !msg.contains('[') && !msg.contains('{')) return msg;
    return AppTranslations.t('auth_unknown', lang);
  }

  /// Translated meeting error message.
  String getMeetingErrorMessageL(String raw, String lang) {
    if (raw.contains('verrouillée') || raw.contains('locked')) {
      return AppTranslations.t('meet_locked', lang);
    }
    if (raw.contains('mot de passe') || raw.contains('password') || raw.contains('incorrect')) {
      return AppTranslations.t('meet_wrong_code', lang);
    }
    if (raw.contains('introuvable') || raw.contains('not-found') || raw.contains('n\'existe pas')) {
      return AppTranslations.t('meet_not_found', lang);
    }
    if (raw.contains('network') || raw.contains('réseau')) {
      return AppTranslations.t('meet_no_network', lang);
    }
    return cleanErrorMessageL(raw, lang);
  }

  void logError(String source, String error) {
    _logger.e('[$source] ❌ $error');
  }
}
