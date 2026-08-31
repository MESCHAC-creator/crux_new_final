import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import '../utils/logger.dart' as crux;

/// Service d'enregistrement et de transcription de réunions.
///
/// Ce service permet d'enregistrer les réunions et de générer
/// des transcriptions automatiques avec sous-titres en temps réel.
class RecordingService {
  RecordingService._();

  static final RecordingService instance = RecordingService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final crux.Logger _logger = crux.logger;
  final Uuid _uuid = const Uuid();

  // Speech-to-Text et Text-to-Speech
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  final FlutterTts _textToSpeech = FlutterTts();

  // État de l'enregistrement
  bool _isRecording = false;
  bool _isTranscribing = false;
  MeetingRecording? _currentRecording;
  final List<TranscriptionSegment> _transcriptionSegments = [];

  // État de la transcription
  bool _liveCaptionsEnabled = false;
  String _currentTranscription = '';
  final StreamController<String> _transcriptionController = 
      StreamController<String>.broadcast();

  // Getters
  bool get isRecording => _isRecording;
  bool get isTranscribing => _isTranscribing;
  MeetingRecording? get currentRecording => _currentRecording;
  List<TranscriptionSegment> get transcriptionSegments => 
      List.unmodifiable(_transcriptionSegments);
  bool get liveCaptionsEnabled => _liveCaptionsEnabled;
  String get currentTranscription => _currentTranscription;
  Stream<String> get transcriptionStream => _transcriptionController.stream;

  /// Initialise le service
  Future<void> initialize() async {
    await _initSpeechToText();
    await _initTextToSpeech();
    _logger.i('RecordingService initialized');
  }

  /// Initialise le speech-to-text
  Future<void> _initSpeechToText() async {
    try {
      final available = await _speechToText.initialize();
      if (!available) {
        _logger.w('Speech-to-text not available on this device');
      }
    } catch (e) {
      _logger.e('Failed to initialize speech-to-text', error: e);
    }
  }

  /// Initialise le text-to-speech
  Future<void> _initTextToSpeech() async {
    try {
      await _textToSpeech.setLanguage('fr-FR');
      await _textToSpeech.setSpeechRate(0.5);
      await _textToSpeech.setVolume(1.0);
    } catch (e) {
      _logger.e('Failed to initialize text-to-speech', error: e);
    }
  }

  /// Démarre l'enregistrement d'une réunion
  Future<String> startRecording({
    required String meetingId,
    required String meetingName,
    RecordingType type = RecordingType.audioVideo,
  }) async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) throw Exception('User not authenticated');

      if (_isRecording) {
        throw Exception('Recording already in progress');
      }

      final recordingId = _uuid.v4();
      final now = DateTime.now();

      final recording = MeetingRecording(
        id: recordingId,
        meetingId: meetingId,
        meetingName: meetingName,
        recordedBy: userId,
        type: type,
        startedAt: now,
        status: RecordingStatus.recording,
        duration: Duration.zero,
        fileSize: 0,
      );

      _currentRecording = recording;
      _isRecording = true;

      await _saveRecording(recording);
      _logger.i('Started recording: $recordingId');

      // Démarrer la transcription si activée
      if (_liveCaptionsEnabled) {
        _startLiveTranscription();
      }

      return recordingId;
    } catch (e) {
      _logger.e('Failed to start recording', error: e);
      rethrow;
    }
  }

  /// Arrête l'enregistrement en cours
  Future<void> stopRecording() async {
    try {
      if (!_isRecording || _currentRecording == null) {
        throw Exception('No recording in progress');
      }

      final duration = DateTime.now().difference(_currentRecording!.startedAt);
      
      final updatedRecording = _currentRecording!.copyWith(
        status: RecordingStatus.processing,
        endedAt: DateTime.now(),
        duration: duration,
      );

      await _saveRecording(updatedRecording);
      _currentRecording = updatedRecording;
      _isRecording = false;

      // Arrêter la transcription
      if (_isTranscribing) {
        await _stopLiveTranscription();
      }

      _logger.i('Stopped recording: ${updatedRecording.id}');
    } catch (e) {
      _logger.e('Failed to stop recording', error: e);
      rethrow;
    }
  }

  /// Active/désactive les sous-titres en direct
  Future<void> setLiveCaptionsEnabled(bool enabled) async {
    _liveCaptionsEnabled = enabled;
    
    if (enabled && _isRecording && !_isTranscribing) {
      await _startLiveTranscription();
    } else if (!enabled && _isTranscribing) {
      await _stopLiveTranscription();
    }
    
    _logger.i('Live captions ${enabled ? "enabled" : "disabled"}');
  }

  /// Démarre la transcription en direct
  Future<void> _startLiveTranscription() async {
    try {
      final available = await _speechToText.initialize();
      if (!available) {
        _logger.w('Speech-to-text not available');
        return;
      }

      _isTranscribing = true;
      await _speechToText.listen(
        onResult: (result) {
          final recognizedWords = result.recognizedWords;
          if (result.finalResult) {
            final transcription = recognizedWords.join(' ');
            _addTranscriptionSegment(transcription);
            _transcriptionController.add(transcription);
          }
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        localeId: 'fr_FR',
      );

      _logger.i('Started live transcription');
    } catch (e) {
      _logger.e('Failed to start live transcription', error: e);
    }
  }

  /// Arrête la transcription en direct
  Future<void> _stopLiveTranscription() async {
    try {
      await _speechToText.stop();
      _isTranscribing = false;
      _logger.i('Stopped live transcription');
    } catch (e) {
      _logger.e('Failed to stop live transcription', error: e);
    }
  }

  /// Ajoute un segment de transcription
  void _addTranscriptionSegment(String text) {
    final segment = TranscriptionSegment(
      id: _uuid.v4(),
      text: text,
      timestamp: DateTime.now(),
      speaker: 'Unknown', // En production, identifier le speaker
    );

    _transcriptionSegments.add(segment);
    _currentTranscription = text;
  }

  /// Génère la transcription complète
  String generateFullTranscription() {
    return _transcriptionSegments
        .map((segment) => '[${segment.timestamp.toIso8601String()}] ${segment.speaker}: ${segment.text}')
        .join('\n');
  }

  /// Sauvegarde la transcription
  Future<void> saveTranscription(String recordingId) async {
    try {
      if (_currentRecording == null) {
        throw Exception('No recording in progress');
      }

      final transcription = generateFullTranscription();
      final transcriptionRef = _storage.ref()
          .child('recordings/$recordingId/transcription.txt');

      await transcriptionRef.putString(transcription);

      // Mettre à jour l'enregistrement
      final downloadUrl = await transcriptionRef.getDownloadURL();
      final updatedRecording = _currentRecording!.copyWith(
        transcriptionUrl: downloadUrl,
        transcription: transcription,
      );

      await _saveRecording(updatedRecording);
      _currentRecording = updatedRecording;

      _logger.i('Transcription saved for recording $recordingId');
    } catch (e) {
      _logger.e('Failed to save transcription', error: e);
      rethrow;
    }
  }

  /// Télécharge un fichier d'enregistrement
  Future<String> downloadRecording(String recordingId) async {
    try {
      final recordingDoc = await _firestore
          .collection('recordings')
          .doc(recordingId)
          .get();

      if (!recordingDoc.exists) {
        throw Exception('Recording not found');
      }

      final recording = MeetingRecording.fromJson(recordingDoc.data()!);
      return recording.fileUrl;
    } catch (e) {
      _logger.e('Failed to download recording', error: e);
      rethrow;
    }
  }

  /// Supprime un enregistrement
  Future<void> deleteRecording(String recordingId) async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) throw Exception('User not authenticated');

      final recordingDoc = await _firestore
          .collection('recordings')
          .doc(recordingId)
          .get();

      if (!recordingDoc.exists) {
        throw Exception('Recording not found');
      }

      final recording = MeetingRecording.fromJson(recordingDoc.data()!);

      // Vérifier les permissions
      if (recording.recordedBy != userId) {
        throw Exception('Permission denied');
      }

      // Supprimer le fichier de stockage
      if (recording.fileUrl.isNotEmpty) {
        try {
          final ref = _storage.refFromURL(recording.fileUrl);
          await ref.delete();
        } catch (e) {
          _logger.w('Failed to delete recording file', error: e);
        }
      }

      // Supprimer la transcription
      if (recording.transcriptionUrl.isNotEmpty) {
        try {
          final ref = _storage.refFromURL(recording.transcriptionUrl);
          await ref.delete();
        } catch (e) {
          _logger.w('Failed to delete transcription file', error: e);
        }
      }

      // Supprimer le document Firestore
      await _firestore.collection('recordings').doc(recordingId).delete();

      _logger.i('Deleted recording: $recordingId');
    } catch (e) {
      _logger.e('Failed to delete recording', error: e);
      rethrow;
    }
  }

  /// Obtient les enregistrements d'une réunion
  Future<List<MeetingRecording>> getMeetingRecordings(String meetingId) async {
    try {
      final snapshot = await _firestore
          .collection('recordings')
          .where('meetingId', isEqualTo: meetingId)
          .get();

      return snapshot.docs
          .map((doc) => MeetingRecording.fromJson(doc.data()))
          .toList();
    } catch (e) {
      _logger.e('Failed to get meeting recordings', error: e);
      return [];
    }
  }

  /// Sauvegarde un enregistrement
  Future<void> _saveRecording(MeetingRecording recording) async {
    try {
      await _firestore
          .collection('recordings')
          .doc(recording.id)
          .set(recording.toJson());
    } catch (e) {
      _logger.e('Failed to save recording', error: e);
      rethrow;
    }
  }

  /// Nettoie les ressources
  void dispose() {
    _transcriptionController.close();
    _speechToText.stop();
    _textToSpeech.stop();
    _logger.i('RecordingService disposed');
  }
}

/// Enregistrement de réunion
class MeetingRecording {
  final String id;
  final String meetingId;
  final String meetingName;
  final String recordedBy;
  final RecordingType type;
  final DateTime startedAt;
  final DateTime? endedAt;
  final RecordingStatus status;
  final Duration duration;
  final int fileSize;
  final String fileUrl;
  final String? transcriptionUrl;
  final String? transcription;

  MeetingRecording({
    required this.id,
    required this.meetingId,
    required this.meetingName,
    required this.recordedBy,
    required this.type,
    required this.startedAt,
    this.endedAt,
    required this.status,
    required this.duration,
    required this.fileSize,
    this.fileUrl = '',
    this.transcriptionUrl,
    this.transcription,
  });

  MeetingRecording copyWith({
    String? id,
    String? meetingId,
    String? meetingName,
    String? recordedBy,
    RecordingType? type,
    DateTime? startedAt,
    DateTime? endedAt,
    RecordingStatus? status,
    Duration? duration,
    int? fileSize,
    String? fileUrl,
    String? transcriptionUrl,
    String? transcription,
  }) {
    return MeetingRecording(
      id: id ?? this.id,
      meetingId: meetingId ?? this.meetingId,
      meetingName: meetingName ?? this.meetingName,
      recordedBy: recordedBy ?? this.recordedBy,
      type: type ?? this.type,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      status: status ?? this.status,
      duration: duration ?? this.duration,
      fileSize: fileSize ?? this.fileSize,
      fileUrl: fileUrl ?? this.fileUrl,
      transcriptionUrl: transcriptionUrl ?? this.transcriptionUrl,
      transcription: transcription ?? this.transcription,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'meetingId': meetingId,
      'meetingName': meetingName,
      'recordedBy': recordedBy,
      'type': type.toString().split('.').last,
      'startedAt': startedAt.toIso8601String(),
      'endedAt': endedAt?.toIso8601String(),
      'status': status.toString().split('.').last,
      'duration': duration.inSeconds,
      'fileSize': fileSize,
      'fileUrl': fileUrl,
      'transcriptionUrl': transcriptionUrl,
      'transcription': transcription,
    };
  }

  static MeetingRecording fromJson(Map<String, dynamic> json) {
    return MeetingRecording(
      id: json['id'] as String,
      meetingId: json['meetingId'] as String,
      meetingName: json['meetingName'] as String,
      recordedBy: json['recordedBy'] as String,
      type: RecordingType.values.firstWhere(
        (e) => e.toString() == 'RecordingType.${json['type']}',
        orElse: () => RecordingType.audioVideo,
      ),
      startedAt: DateTime.parse(json['startedAt'] as String),
      endedAt: json['endedAt'] != null 
          ? DateTime.parse(json['endedAt'] as String) 
          : null,
      status: RecordingStatus.values.firstWhere(
        (e) => e.toString() == 'RecordingStatus.${json['status']}',
        orElse: () => RecordingStatus.recording,
      ),
      duration: Duration(seconds: json['duration'] as int),
      fileSize: json['fileSize'] as int,
      fileUrl: json['fileUrl'] as String? ?? '',
      transcriptionUrl: json['transcriptionUrl'] as String?,
      transcription: json['transcription'] as String?,
    );
  }
}

/// Type d'enregistrement
enum RecordingType {
  audio,
  video,
  audioVideo,
}

/// Statut d'enregistrement
enum RecordingStatus {
  recording,
  processing,
  completed,
  failed,
}

/// Segment de transcription
class TranscriptionSegment {
  final String id;
  final String text;
  final DateTime timestamp;
  final String speaker;

  TranscriptionSegment({
    required this.id,
    required this.text,
    required this.timestamp,
    required this.speaker,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
      'speaker': speaker,
    };
  }

  static TranscriptionSegment fromJson(Map<String, dynamic> json) {
    return TranscriptionSegment(
      id: json['id'] as String,
      text: json['text'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      speaker: json['speaker'] as String,
    );
  }
}