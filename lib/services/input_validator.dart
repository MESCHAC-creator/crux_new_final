class InputValidator {
  // Meeting & chat validation
  static String? validateMeetingName(String value) {
    value = value.trim();
    if (value.isEmpty) return 'Le nom est requis';
    if (value.length < 2) return 'Minimum 2 caractères';
    if (value.length > 60) return 'Maximum 60 caractères';
    if (_containsMaliciousPatterns(value)) return 'Caractères non autorisés';
    return null;
  }

  static String? validatePassword(String value) {
    if (value.isEmpty) return 'Le mot de passe est requis';
    if (value.length < 4) return 'Minimum 4 caractères';
    if (value.length > 128) return 'Trop long';
    return null;
  }

  static String? validateChatMessage(String value) {
    if (value.trim().isEmpty) return 'Message vide';
    if (value.length > 5000) return 'Message trop long (max 5000)';
    return null;
  }

  static String? validateUserName(String value) {
    value = value.trim();
    if (value.isEmpty) return 'Le nom est requis';
    if (value.length > 50) return 'Maximum 50 caractères';
    if (_containsMaliciousPatterns(value)) return 'Caractères non autorisés';
    return null;
  }

  static String? validateDescription(String value) {
    if (value.length > 500) return 'Maximum 500 caractères';
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
    // Remove control characters and excessive whitespace
    return value
        .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '') // Control chars
        .replaceAll(RegExp(r'\s+'), ' ') // Collapse whitespace
        .trim();
  }
}
