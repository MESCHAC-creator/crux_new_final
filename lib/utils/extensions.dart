import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// String Extensions
extension StringExtensions on String {
  /// Vérifier si c'est un email valide
  bool get isValidEmail {
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    return emailRegex.hasMatch(this);
  }

  /// Vérifier si c'est un numéro de téléphone valide
  bool get isValidPhoneNumber {
    final phoneRegex = RegExp(r'^[0-9]{10,}$');
    return phoneRegex.hasMatch(replaceAll(RegExp(r'\D'), ''));
  }

  /// Capitaliser le premier caractère
  String get capitalize {
    if (isEmpty) return '';
    return '${this[0].toUpperCase()}${substring(1)}';
  }

  /// Convertir en titre (chaque mot capitalisé)
  String get toTitleCase {
    return split(' ')
        .map((word) => word.capitalize)
        .join(' ');
  }

  /// Vérifier si c'est une URL valide
  bool get isValidUrl {
    final urlRegex = RegExp(
      r'^(https?|ftp):\/\/[^\s/$.?#].[^\s]*$',
      caseSensitive: false,
    );
    return urlRegex.hasMatch(this);
  }

  /// Obtenir les initiales (ex: "Jean Dupont" -> "JD")
  String get initials {
    final names = split(' ');
    return names.map((name) => name.isNotEmpty ? name[0] : '').join().toUpperCase();
  }
}

// DateTime Extensions
extension DateTimeExtensions on DateTime {
  /// Formater la date au format français
  String get formattedFr {
    return DateFormat('dd/MM/yyyy', 'fr_FR').format(this);
  }

  /// Formater l'heure au format HH:mm
  String get formattedTime {
    return DateFormat('HH:mm').format(this);
  }

  /// Formater la date et heure complète
  String get formattedFull {
    return DateFormat('dd/MM/yyyy HH:mm', 'fr_FR').format(this);
  }

  /// Vérifier si c'est aujourd'hui
  bool get isToday {
    final now = DateTime.now();
    return year == now.year && month == now.month && day == now.day;
  }

  /// Vérifier si c'est hier
  bool get isYesterday {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    return year == yesterday.year &&
        month == yesterday.month &&
        day == yesterday.day;
  }

  /// Vérifier si c'est cette semaine
  bool get isThisWeek {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 7));
    return isAfter(weekStart) && isBefore(weekEnd);
  }

  /// Obtenir la différence en texte lisible (ex: "Il y a 2 heures")
  String get timeAgo {
    final now = DateTime.now();
    final difference = now.difference(this);

    if (difference.inDays > 365) {
      return 'Il y a ${(difference.inDays / 365).floor()} an(s)';
    } else if (difference.inDays > 30) {
      return 'Il y a ${(difference.inDays / 30).floor()} mois';
    } else if (difference.inDays > 0) {
      return 'Il y a ${difference.inDays} jour(s)';
    } else if (difference.inHours > 0) {
      return 'Il y a ${difference.inHours} heure(s)';
    } else if (difference.inMinutes > 0) {
      return 'Il y a ${difference.inMinutes} minute(s)';
    } else {
      return 'À l\'instant';
    }
  }
}

// Duration Extensions
extension DurationExtensions on Duration {
  /// Formater la durée au format MM:SS ou HH:MM:SS
  String get formatted {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(inSeconds.remainder(60));
    if (inHours == 0) {
      return '$twoDigitMinutes:$twoDigitSeconds';
    }
    return '${twoDigits(inHours)}:$twoDigitMinutes:$twoDigitSeconds';
  }
}

// Num Extensions
extension NumExtensions on num {
  /// Arrondir à n décimales
  double toDecimal(int places) {
    final mod = 10.0 * places;
    return (this * mod).round() / mod;
  }

  /// Formater en devise euros
  String get formatEuro {
    return '€${toStringAsFixed(2)}';
  }

  /// Vérifier si c'est entre deux nombres
  bool isBetween(num a, num b) {
    return this >= a && this <= b;
  }
}

// BuildContext Extensions
extension BuildContextExtensions on BuildContext {
  /// Obtenir la taille de l'écran
  Size get screenSize => MediaQuery.of(this).size;

  /// Obtenir la largeur de l'écran
  double get screenWidth => MediaQuery.of(this).size.width;

  /// Obtenir la hauteur de l'écran
  double get screenHeight => MediaQuery.of(this).size.height;

  /// Vérifier si c'est en mode portrait
  bool get isPortrait => MediaQuery.of(this).orientation == Orientation.portrait;

  /// Vérifier si c'est en mode paysage
  bool get isLandscape => MediaQuery.of(this).orientation == Orientation.landscape;

  /// Vérifier si c'est un petit appareil
  bool get isSmallDevice => screenWidth < 600;

  /// Vérifier si c'est un grand appareil
  bool get isLargeDevice => screenWidth >= 600;

  /// Obtenir le padding du système
  EdgeInsets get systemPadding => MediaQuery.of(this).padding;

  /// Obtenir la hauteur du clavier
  double get keyboardHeight => MediaQuery.of(this).viewInsets.bottom;

  /// Vérifier si le clavier est visible
  bool get isKeyboardVisible => keyboardHeight > 0;
}

// List Extensions
extension ListExtensions<T> on List<T> {
  /// Obtenir l'élément au hasard
  T? get random => isEmpty ? null : this[DateTime.now().microsecond % length];

  /// Vérifier si la liste n'est pas vide
  bool get isNotEmpty => length > 0;

  /// Obtenir la première moitié
  List<T> get firstHalf => sublist(0, (length / 2).ceil());

  /// Obtenir la deuxième moitié
  List<T> get secondHalf => sublist((length / 2).ceil());
}

// Map Extensions
extension MapExtensions<K, V> on Map<K, V> {
  /// Vérifier si la clé existe
  bool containsKeyIgnoreCase(dynamic key) {
    if (key is! String) return containsKey(key);
    return keys.any((k) => k.toString().toLowerCase() == key.toLowerCase());
  }
}
