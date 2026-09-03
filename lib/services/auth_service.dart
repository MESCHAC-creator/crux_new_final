import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:logger/logger.dart';
import '../models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: [
    'email',
    'https://www.googleapis.com/auth/userinfo.profile',
  ]);
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
      _logger.i('📝 Sign up: $email');

      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final user = userCredential.user;
      if (user == null) throw Exception('User creation failed');

      await user.updateDisplayName(name.trim());
      await user.reload();

      _logger.i('✅ Sign up successful');

      return UserModel(
        uid: user.uid,
        email: email.trim(),
        name: name.trim(),
      );
    } on FirebaseAuthException catch (e) {
      _logger.e('❌ Auth error: ${e.code} — ${e.message}');
      rethrow;
    } catch (e) {
      _logger.e('❌ Sign up failed: $e');
      rethrow;
    }
  }

  Future<UserModel?> signIn({
    required String email,
    required String password,
  }) async {
    try {
      _logger.i('🔑 Sign in: $email');

      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('Délai de connexion dépassé. Vérifiez votre connexion internet.');
        },
      );

      final user = userCredential.user;
      if (user == null) throw Exception('Sign in failed');

      _logger.i('✅ Sign in successful');

      return UserModel(
        uid: user.uid,
        email: user.email ?? '',
        name: user.displayName ?? 'User',
      );
    } on FirebaseAuthException catch (e) {
      _logger.e('❌ Auth error: ${e.code} — ${e.message}');
      rethrow;
    } catch (e) {
      _logger.e('❌ Sign in failed: $e');
      rethrow;
    }
  }

  Future<UserModel?> signInWithGoogle() async {
    try {
      _logger.i('🔑 Google Sign In...');

      final googleUser = await _googleSignIn.signIn().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Délai Google Sign-In dépassé. Vérifiez votre connexion internet.');
        },
      );
      if (googleUser == null) {
        _logger.w('⚠️ Google sign in cancelled');
        return null;
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('Délai authentification dépassé. Vérifiez votre connexion internet.');
        },
      );
      final user = userCredential.user;

      if (user == null) throw Exception('Google sign in failed');

      _logger.i('✅ Google sign in successful');

      return UserModel(
        uid: user.uid,
        email: user.email ?? '',
        name: user.displayName ?? googleUser.displayName ?? 'User',
      );
    } on FirebaseAuthException catch (e) {
      _logger.e('❌ Google auth error: ${e.code} — ${e.message}');
      rethrow;
    } catch (e) {
      _logger.e('❌ Google sign in failed: $e');
      rethrow;
    }
  }

  Future<void> resetPassword(String email) async {
    try {
      _logger.i('🔄 Password reset: $email');
      await _auth.sendPasswordResetEmail(email: email.trim());
      _logger.i('✅ Password reset email sent');
    } on FirebaseAuthException catch (e) {
      _logger.e('❌ Reset error: ${e.code}');
      rethrow;
    } catch (e) {
      _logger.e('❌ Password reset failed: $e');
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      _logger.i('👋 Signing out...');
      await Future.wait([
        _googleSignIn.signOut().then((_) => null, onError: (_) => null),
        _auth.signOut(),
      ]);
      _logger.i('✅ Sign out successful');
    } catch (e) {
      _logger.e('⚠️ Sign out error: $e');
      // Local sign out should always succeed
    }
  }
}
