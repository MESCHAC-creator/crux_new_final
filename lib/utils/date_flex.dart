// lib/utils/date_flex.dart
//
// Lecture/écriture de dates Firestore tolérante aux formats hétérogènes.
//
// Historique du projet : selon la version du code qui a écrit le document,
// une date peut se trouver en base sous quatre formes différentes :
//   - Timestamp          (format natif Firestore, celui qu'on écrit maintenant)
//   - String ISO 8601    (ancien MeetingModel / ScheduledMeetingModel)
//   - int millisecondes  (imports/scripts)
//   - DateTime           (cache local avant sérialisation)
//
// `DateTime.parse(json['startTime'])` plantait donc dès qu'un document
// contenait un Timestamp. Toutes les lectures passent maintenant par
// [flexDate] / [flexDateOrNull].

import 'package:cloud_firestore/cloud_firestore.dart';

/// Parse une valeur Firestore en DateTime **local**, ou null si illisible.
DateTime? flexDateOrNull(dynamic value) {
  if (value == null) return null;

  if (value is Timestamp) return value.toDate().toLocal();
  if (value is DateTime) return value.toLocal();

  if (value is int) {
    // Heuristique : < 10^11 => secondes, sinon millisecondes.
    final ms = value.abs() < 100000000000 ? value * 1000 : value;
    return DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
  }

  if (value is double) {
    return DateTime.fromMillisecondsSinceEpoch(value.round()).toLocal();
  }

  if (value is String) {
    final raw = value.trim();
    if (raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) return parsed.toLocal();
    final asInt = int.tryParse(raw);
    if (asInt != null) return flexDateOrNull(asInt);
    return null;
  }

  // Map { _seconds, _nanoseconds } produit par certains exports JSON.
  if (value is Map) {
    final seconds = value['_seconds'] ?? value['seconds'];
    if (seconds is int) {
      return DateTime.fromMillisecondsSinceEpoch(seconds * 1000).toLocal();
    }
  }

  return null;
}

/// Comme [flexDateOrNull] mais avec une valeur de repli obligatoire.
DateTime flexDate(dynamic value, {DateTime? fallback}) =>
    flexDateOrNull(value) ?? fallback ?? DateTime.now();

/// Valeur à écrire en base pour une date : toujours un [Timestamp].
///
/// Firestore stocke un instant absolu : plus aucune ambiguïté de fuseau,
/// contrairement à `DateTime(...).toIso8601String()` qui perdait l'offset.
Timestamp flexStamp(DateTime date) => Timestamp.fromDate(date.toUtc());

/// Version nullable pour les champs optionnels (`actualStart`, `actualEnd`…).
Timestamp? flexStampOrNull(DateTime? date) =>
    date == null ? null : flexStamp(date);

/// Sérialisation de secours pour les documents qui doivent rester en String
/// ISO (miroir `scheduled_meetings`) : toujours en UTC, avec le suffixe `Z`,
/// pour que le tri lexicographique corresponde au tri chronologique.
String flexIsoUtc(DateTime date) => date.toUtc().toIso8601String();
