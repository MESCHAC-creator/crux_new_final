import 'package:hive_flutter/hive_flutter.dart';
import 'package:logger/logger.dart';
import '../models/user_model.dart';
import '../models/meeting_model.dart';

class LocalDatabase {
  static final LocalDatabase _instance = LocalDatabase._internal();
  final _logger = Logger();

  late Box<String> _userBox;
  late Box<String> _meetingsBox;
  late Box<String> _preferencesBox;

  factory LocalDatabase() {
    return _instance;
  }

  LocalDatabase._internal();

  Future<void> initialize() async {
    try {
      await Hive.initFlutter();

      _userBox = await Hive.openBox<String>('users');
      _meetingsBox = await Hive.openBox<String>('meetings');
      _preferencesBox = await Hive.openBox<String>('preferences');

      _logger.i('✅ Base de données locale initialisée');
    } catch (e) {
      _logger.e('❌ Erreur initialisation DB: $e');
      rethrow;
    }
  }

  // User methods
  Future<void> saveUser(UserModel user) async {
    try {
      await _userBox.put(user.uid, user.toString());
      _logger.i('✅ Utilisateur sauvegardé: ${user.uid}');
    } catch (e) {
      _logger.e('❌ Erreur sauvegarde utilisateur: $e');
    }
  }

  UserModel? getUser(String uid) {
    try {
      final data = _userBox.get(uid);
      if (data != null) {
        _logger.i('✅ Utilisateur récupéré: $uid');
        return UserModel(
          uid: uid,
          email: '',
          name: data,
        );
      }
      return null;
    } catch (e) {
      _logger.e('❌ Erreur récupération utilisateur: $e');
      return null;
    }
  }

  // Meeting methods
  Future<void> saveMeeting(MeetingModel meeting) async {
    try {
      await _meetingsBox.put(meeting.id, meeting.toString());
      _logger.i('✅ Réunion sauvegardée: ${meeting.id}');
    } catch (e) {
      _logger.e('❌ Erreur sauvegarde réunion: $e');
    }
  }

  List<MeetingModel> getAllMeetings() {
    try {
      final meetings = <MeetingModel>[];
      for (var entry in _meetingsBox.values) {
        meetings.add(MeetingModel(
          id: '',
          title: entry,
          description: '',
          organizer: '',
          organizerId: '',
          startTime: DateTime.now(),
          endTime: DateTime.now(),
          participants: [],
          channelName: '',
          status: MeetingStatus.scheduled,
          createdAt: DateTime.now(),
        ));
      }
      _logger.i('✅ ${meetings.length} réunions récupérées');
      return meetings;
    } catch (e) {
      _logger.e('❌ Erreur récupération réunions: $e');
      return [];
    }
  }

  // Preferences methods
  Future<void> setPreference(String key, String value) async {
    try {
      await _preferencesBox.put(key, value);
      _logger.i('✅ Préférence sauvegardée: $key');
    } catch (e) {
      _logger.e('❌ Erreur sauvegarde préférence: $e');
    }
  }

  String? getPreference(String key) {
    try {
      return _preferencesBox.get(key);
    } catch (e) {
      _logger.e('❌ Erreur récupération préférence: $e');
      return null;
    }
  }

  // Clear methods
  Future<void> clearAll() async {
    try {
      await Future.wait([
        _userBox.clear(),
        _meetingsBox.clear(),
        _preferencesBox.clear(),
      ]);
      _logger.i('✅ Base de données vidée');
    } catch (e) {
      _logger.e('❌ Erreur vidage DB: $e');
    }
  }

  Future<void> close() async {
    try {
      await Hive.close();
      _logger.i('✅ Base de données fermée');
    } catch (e) {
      _logger.e('❌ Erreur fermeture DB: $e');
    }
  }
}