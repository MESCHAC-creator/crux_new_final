import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:logger/logger.dart';
import '../models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final _googleSignIn = GoogleSignIn();
  final _logger = Logger();

  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserModel?> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
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
      _logger.e('❌ Firebase Auth signUp: ${e.code}');
      // Re-throw raw FirebaseAuthException so screens can distinguish codes
      throw FirebaseAuthException(code: e.code, message: e.message);
    } catch (e) {
      _logger.e('❌ Erreur inscription: $e');
      throw FirebaseAuthException(code: 'network-request-failed');
    }
  }

  Future<UserModel?> signIn({
    required String email,
    required String password,
  }) async {
    try {
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
      _logger.e('❌ Firebase Auth signIn: ${e.code}');
      throw FirebaseAuthException(code: e.code, message: e.message);
    } catch (e) {
      _logger.e('❌ Erreur connexion: $e');
      throw FirebaseAuthException(code: 'network-request-failed');
    }
  }

  Future<void> signOut() async {
    try {
      _logger.i('👋 Déconnexion en cours...');
      await _googleSignIn.signOut().then((_) {}, onError: (_) {});
      await _auth.signOut();
      _logger.i('✅ Déconnecté avec succès');
    } catch (e) {
      _logger.e('❌ Erreur déconnexion: $e');
      // Don't throw — sign out should always succeed locally
    }
  }

  Future<void> resetPassword(String email) async {
    try {
      _logger.i('🔄 Réinitialisation du mot de passe: $email');
      await _auth.sendPasswordResetEmail(email: email.trim());
      _logger.i('✅ Email de réinitialisation envoyé');
    } on FirebaseAuthException catch (e) {
      _logger.e('❌ Firebase Auth resetPassword: ${e.code}');
      throw FirebaseAuthException(code: e.code, message: e.message);
    } catch (e) {
      _logger.e('❌ Erreur réinitialisation: $e');
      throw FirebaseAuthException(code: 'network-request-failed');
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
      _logger.e('❌ Firebase Auth Google: ${e.code}');
      throw FirebaseAuthException(code: e.code, message: e.message);
    } catch (e) {
      _logger.e('❌ Erreur Google Sign-In: $e');
      if (e.toString().contains('cancelled') || e.toString().contains('canceled')) {
        throw FirebaseAuthException(code: 'popup-closed-by-user');
      }
      throw FirebaseAuthException(code: 'network-request-failed');
    }
  }
}
