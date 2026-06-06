import '../l10n/app_translations.dart';

class InputValidator {
  // Meeting & chat validation
  static String? validateMeetingName(String value, String lang) {
    value = value.trim();
    if (value.isEmpty) return AppTranslations.t('val_name_required', lang);
    if (value.length < 2) return AppTranslations.t('val_min_2', lang);
    if (value.length > 60) return AppTranslations.t('val_max_60', lang);
    if (_containsMaliciousPatterns(value)) return AppTranslations.t('val_invalid_chars', lang);
    return null;
  }

  static String? validatePassword(String value, String lang) {
    if (value.isEmpty) return AppTranslations.t('val_pwd_required', lang);
    if (value.length < 4) return AppTranslations.t('val_min_6', lang);
    if (value.length > 128) return AppTranslations.t('val_too_long', lang);
    return null;
  }

  static String? validateChatMessage(String value, String lang) {
    if (value.trim().isEmpty) return AppTranslations.t('val_msg_empty', lang);
    if (value.length > 5000) return AppTranslations.t('val_msg_too_long', lang);
    return null;
  }

  static String? validateUserName(String value, String lang) {
    value = value.trim();
    if (value.isEmpty) return AppTranslations.t('val_name_required', lang);
    if (value.length > 50) return AppTranslations.t('val_max_50', lang);
    if (_containsMaliciousPatterns(value)) return AppTranslations.t('val_invalid_chars', lang);
    return null;
  }

  static String? validateDescription(String value, String lang) {
    if (value.length > 500) return AppTranslations.t('val_max_500', lang);
    return null;
  }

  // Helper to detect XSS/injection patterns
  static bool _containsMaliciousPatterns(String value) {
    final dangerous = [
      '<script', '</script>',
      'onclick=', 'onerror=', 'onload=',
      'javascript:', 'data:',
      '<iframe', '<img',
      '; DROP', 'UNION SELECT',
    ];
    final lower = value.toLowerCase();
    return dangerous.any((p) => lower.contains(p));
  }

  static String sanitize(String value) {
    return value
        .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
