import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import '../utils/logger.dart' as crux;

/// Service de partage de fichiers dans le chat.
///
/// Ce service permet aux participants de partager des fichiers
/// (images, documents, etc.) dans le chat de la réunion.
class FileSharingService {
  FileSharingService._();

  static final FileSharingService instance = FileSharingService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final crux.Logger _logger = crux.logger;
  final Uuid _uuid = const Uuid();

  // Configuration
  static const int maxFileSize = 50 * 1024 * 1024; // 50 MB
  static const List<String> allowedImageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp'];
  static const List<String> allowedDocumentExtensions = ['.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.txt'];

  // État
  final List<SharedFile> _sharedFiles = [];
  final StreamController<List<SharedFile>> _filesController = 
      StreamController<List<SharedFile>>.broadcast();

  // Getters
  List<SharedFile> get sharedFiles => List.unmodifiable(_sharedFiles);
  Stream<List<SharedFile>> get filesStream => _filesController.stream;

  /// Initialise le service
  Future<void> initialize() async {
    await _loadSharedFiles();
    _logger.i('FileSharingService initialized');
  }

  /// Charge les fichiers partagés
  Future<void> _loadSharedFiles() async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) return;

      // En production, charger depuis Firestore
      // Pour l'instant, initialiser vide
      _sharedFiles.clear();
      _filesController.add(_sharedFiles);
    } catch (e) {
      _logger.e('Failed to load shared files', error: e);
    }
  }

  /// Sélectionne et partage un fichier
  Future<String?> shareFile({
    required String meetingId,
    required FileType fileType,
  }) async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) throw Exception('User not authenticated');

      FilePickerResult? result;
      
      switch (fileType) {
        case FileType.image:
          result = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: allowedImageExtensions,
          );
          break;
        case FileType.custom:
          result = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: [...allowedImageExtensions, ...allowedDocumentExtensions],
          );
          break;
        default:
          result = await FilePicker.platform.pickFiles();
      }

      if (result == null || result.files.isEmpty) {
        return null;
      }

      final file = result.files.first;
      if (file.path == null) {
        throw Exception('File path not available');
      }

      // Vérifier la taille du fichier
      final fileSize = File(file.path!).lengthSync();
      if (fileSize > maxFileSize) {
        throw Exception('File size exceeds maximum limit of 50MB');
      }

      // Uploader le fichier
      final fileUrl = await _uploadFile(
        meetingId: meetingId,
        filePath: file.path!,
        fileName: file.name,
      );

      // Créer l'entrée de fichier partagé
      final sharedFile = SharedFile(
        id: _uuid.v4(),
        meetingId: meetingId,
        sharedBy: userId,
        fileName: file.name,
        fileUrl: fileUrl,
        fileSize: fileSize,
        fileType: _getFileType(file.name),
        sharedAt: DateTime.now(),
      );

      await _saveSharedFile(sharedFile);
      _sharedFiles.add(sharedFile);
      _filesController.add(List.from(_sharedFiles));

      _logger.i('Shared file: ${file.name}');
      return fileUrl;
    } catch (e) {
      _logger.e('Failed to share file', error: e);
      rethrow;
    }
  }

  /// Sélectionne et partage une image
  Future<String?> shareImage({
    required String meetingId,
    required ImageSource source,
  }) async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) throw Exception('User not authenticated');

      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: source);

      if (pickedFile == null) {
        return null;
      }

      // Vérifier la taille du fichier
      final fileSize = File(pickedFile.path).lengthSync();
      if (fileSize > maxFileSize) {
        throw Exception('Image size exceeds maximum limit of 50MB');
      }

      // Uploader l'image
      final fileUrl = await _uploadFile(
        meetingId: meetingId,
        filePath: pickedFile.path,
        fileName: path.basename(pickedFile.path),
      );

      // Créer l'entrée de fichier partagé
      final sharedFile = SharedFile(
        id: _uuid.v4(),
        meetingId: meetingId,
        sharedBy: userId,
        fileName: path.basename(pickedFile.path),
        fileUrl: fileUrl,
        fileSize: fileSize,
        fileType: SharedFileType.image,
        sharedAt: DateTime.now(),
      );

      await _saveSharedFile(sharedFile);
      _sharedFiles.add(sharedFile);
      _filesController.add(List.from(_sharedFiles));

      _logger.i('Shared image: ${pickedFile.path}');
      return fileUrl;
    } catch (e) {
      _logger.e('Failed to share image', error: e);
      rethrow;
    }
  }

  /// Uploader un fichier vers Firebase Storage
  Future<String> _uploadFile({
    required String meetingId,
    required String filePath,
    required String fileName,
  }) async {
    try {
      final file = File(filePath);
      final extension = path.extension(fileName);
      final uniqueFileName = '${_uuid.v4()}$extension';
      final storagePath = 'meetings/$meetingId/files/$uniqueFileName';

      final ref = _storage.ref().child(storagePath);
      final uploadTask = ref.putFile(file);

      // Écouter la progression
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        final progress = (snapshot.bytesTransferred / snapshot.totalBytes) * 100;
        _logger.d('Upload progress: $progress%');
      });

      // Attendre la fin de l'upload
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      _logger.i('File uploaded successfully: $storagePath');
      return downloadUrl;
    } catch (e) {
      _logger.e('Failed to upload file', error: e);
      rethrow;
    }
  }

  /// Télécharge un fichier partagé
  Future<String> downloadFile(String fileId) async {
    try {
      final sharedFile = _sharedFiles.firstWhere(
        (f) => f.id == fileId,
        orElse: () => throw Exception('File not found'),
      );

      // Retourner l'URL de téléchargement
      return sharedFile.fileUrl;
    } catch (e) {
      _logger.e('Failed to download file', error: e);
      rethrow;
    }
  }

  /// Supprime un fichier partagé
  Future<void> deleteFile(String fileId) async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) throw Exception('User not authenticated');

      final sharedFile = _sharedFiles.firstWhere(
        (f) => f.id == fileId,
        orElse: () => throw Exception('File not found'),
      );

      // Vérifier que l'utilisateur est le propriétaire
      if (sharedFile.sharedBy != userId) {
        throw Exception('Permission denied');
      }

      // Supprimer de Firebase Storage
      try {
        final ref = _storage.refFromURL(sharedFile.fileUrl);
        await ref.delete();
      } catch (e) {
        _logger.w('Failed to delete file from storage', error: e);
      }

      // Supprimer de Firestore
      await _firestore.collection('shared_files').doc(fileId).delete();

      // Supprimer de la liste locale
      _sharedFiles.removeWhere((f) => f.id == fileId);
      _filesController.add(List.from(_sharedFiles));

      _logger.i('Deleted file: $fileId');
    } catch (e) {
      _logger.e('Failed to delete file', error: e);
      rethrow;
    }
  }

  /// Obtient les fichiers d'une réunion
  List<SharedFile> getMeetingFiles(String meetingId) {
    return _sharedFiles.where((f) => f.meetingId == meetingId).toList();
  }

  /// Formate la taille du fichier
  String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Détermine le type de fichier
  SharedFileType _getFileType(String fileName) {
    final extension = path.extension(fileName).toLowerCase();
    
    if (allowedImageExtensions.contains(extension)) {
      return SharedFileType.image;
    }
    
    if (allowedDocumentExtensions.contains(extension)) {
      return SharedFileType.document;
    }
    
    return SharedFileType.other;
  }

  /// Sauvegarde un fichier partagé
  Future<void> _saveSharedFile(SharedFile file) async {
    try {
      await _firestore.collection('shared_files').doc(file.id).set(file.toJson());
    } catch (e) {
      _logger.e('Failed to save shared file', error: e);
      rethrow;
    }
  }

  /// Nettoie les ressources
  void dispose() {
    _filesController.close();
    _logger.i('FileSharingService disposed');
  }
}

/// Fichier partagé
class SharedFile {
  final String id;
  final String meetingId;
  final String sharedBy;
  final String fileName;
  final String fileUrl;
  final int fileSize;
  final SharedFileType fileType;
  final DateTime sharedAt;

  SharedFile({
    required this.id,
    required this.meetingId,
    required this.sharedBy,
    required this.fileName,
    required this.fileUrl,
    required this.fileSize,
    required this.fileType,
    required this.sharedAt,
  });

  String get formattedSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    if (fileSize < 1024 * 1024 * 1024) return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'meetingId': meetingId,
      'sharedBy': sharedBy,
      'fileName': fileName,
      'fileUrl': fileUrl,
      'fileSize': fileSize,
      'fileType': fileType.toString().split('.').last,
      'sharedAt': sharedAt.toIso8601String(),
    };
  }

  static SharedFile fromJson(Map<String, dynamic> json) {
    return SharedFile(
      id: json['id'] as String,
      meetingId: json['meetingId'] as String,
      sharedBy: json['sharedBy'] as String,
      fileName: json['fileName'] as String,
      fileUrl: json['fileUrl'] as String,
      fileSize: json['fileSize'] as int,
      fileType: SharedFileType.values.firstWhere(
        (e) => e.toString() == 'SharedFileType.${json['fileType']}',
        orElse: () => SharedFileType.other,
      ),
      sharedAt: DateTime.parse(json['sharedAt'] as String),
    );
  }
}

/// Type de fichier partagé
enum SharedFileType {
  image,
  document,
  other,
}