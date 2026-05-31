class Validators {
  static String? validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return '⚠️ Email obligatoire';
    }
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    if (!emailRegex.hasMatch(value)) {
      return '⚠️ Email invalide';
    }
    return null;
  }

  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return '⚠️ Mot de passe obligatoire';
    }
    if (value.length < 6) {
      return '⚠️ Minimum 6 caractères';
    }
    return null;
  }

  static String? validateName(String? value) {
    if (value == null || value.isEmpty) {
      return '⚠️ Nom obligatoire';
    }
    if (value.length < 2) {
      return '⚠️ Minimum 2 caractères';
    }
    return null;
  }

  static String? validateMeetingName(String? value) {
    if (value == null || value.isEmpty) {
      return '⚠️ Nom de réunion obligatoire';
    }
    if (value.length < 3) {
      return '⚠️ Minimum 3 caractères';
    }
    if (value.length > 100) {
      return '⚠️ Maximum 100 caractères';
    }
    return null;
  }

  static String? validatePhoneNumber(String? value) {
    if (value == null || value.isEmpty) {
      return '⚠️ Numéro obligatoire';
    }
    final phoneRegex = RegExp(r'^[0-9]{10,}$');
    if (!phoneRegex.hasMatch(value.replaceAll(RegExp(r'\D'), ''))) {
      return '⚠️ Numéro invalide';
    }
    return null;
  }
}
