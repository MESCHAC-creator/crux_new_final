import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:logger/logger.dart';
import '../models/user_model.dart';
import 'error_handler_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final _googleSignIn = GoogleSignIn();
  final _logger = Logger();
  final _errorHandler = ErrorHandlerService();

  static final AuthService _instance = AuthService._internal();

  factory AuthService() {
    return _instance;
  }

  AuthService._internal();

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserModel?> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      if (email.isEmpty || password.isEmpty || name.isEmpty) {
        throw Exception('⚠️ Tous les champs sont obligatoires');
      }

      if (!email.contains('@')) {
        throw Exception('⚠️ Email invalide');
      }

      if (password.length < 6) {
        throw Exception('⚠️ Mot de passe: minimum 6 caractères');
      }

      if (name.length < 2) {
        throw Exception('⚠️ Nom: minimum 2 caractères');
      }

      _logger.i('📝 Inscription en cours: $email');

      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      await userCredential.user?.updateDisplayName(name.trim());
      await userCredential.user?.reload();

      _logger.i('✅ Inscription réussie');

      return UserModel(
        uid: userCredential.user!.uid,
        email: email.trim(),
        name: name.trim(),
      );
    } on FirebaseAuthException catch (e) {
      final errorMsg = _errorHandler.getFirebaseErrorMessage(e.code);
      _logger.e('❌ Firebase Auth: ${e.code}');
      throw Exception(errorMsg);
    } catch (e) {
      _logger.e('❌ Erreur inscription: $e');
      throw Exception('❌ Erreur d\'inscription: $e');
    }
  }

  Future<UserModel?> signIn({
    required String email,
    required String password,
  }) async {
    try {
      if (email.isEmpty || password.isEmpty) {
        throw Exception('⚠️ Email et mot de passe obligatoires');
      }

      _logger.i('🔑 Connexion en cours: $email');

      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      _logger.i('✅ Connexion réussie');

      return UserModel(
        uid: userCredential.user!.uid,
        email: userCredential.user!.email ?? '',
        name: userCredential.user!.displayName ?? 'Utilisateur',
      );
    } on FirebaseAuthException catch (e) {
      final errorMsg = _errorHandler.getFirebaseErrorMessage(e.code);
      _logger.e('❌ Firebase Auth: ${e.code}');
      throw Exception(errorMsg);
    } catch (e) {
      _logger.e('❌ Erreur connexion: $e');
      throw Exception('❌ Erreur de connexion: $e');
    }
  }

  Future<void> signOut() async {
    try {
      _logger.i('👋 Déconnexion en cours...');
      await _auth.signOut();
      _logger.i('✅ Déconnecté avec succès');
    } catch (e) {
      _logger.e('❌ Erreur déconnexion: $e');
      throw Exception('❌ Erreur de déconnexion: $e');
    }
  }

  Future<void> resetPassword(String email) async {
    try {
      if (email.isEmpty) {
        throw Exception('⚠️ Email obligatoire');
      }

      _logger.i('🔄 Réinitialisation du mot de passe: $email');
      await _auth.sendPasswordResetEmail(email: email.trim());
      _logger.i('✅ Email de réinitialisation envoyé');
    } on FirebaseAuthException catch (e) {
      final errorMsg = _errorHandler.getFirebaseErrorMessage(e.code);
      _logger.e('❌ Firebase Auth: ${e.code}');
      throw Exception(errorMsg);
    } catch (e) {
      _logger.e('❌ Erreur réinitialisation: $e');
      throw Exception('❌ Erreur: $e');
    }
  }

  bool get isLoggedIn => _auth.currentUser != null;

  Future<UserModel?> signInWithGoogle() async {
    try {
      _logger.i('🔑 Connexion Google en cours...');
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null; // User cancelled

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user!;
      _logger.i('✅ Connexion Google réussie: ${user.email}');

      return UserModel(
        uid: user.uid,
        email: user.email ?? '',
        name: user.displayName ?? googleUser.displayName ?? 'Utilisateur',
      );
    } on FirebaseAuthException catch (e) {
      final errorMsg = _errorHandler.getFirebaseErrorMessage(e.code);
      _logger.e('❌ Firebase Auth Google: ${e.code}');
      throw Exception(errorMsg);
    } catch (e) {
      _logger.e('❌ Erreur Google Sign-In: $e');
      throw Exception('❌ Erreur de connexion Google: $e');
    }
  }
}