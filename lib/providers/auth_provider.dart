import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';

class CruxAuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  final _logger = Logger();

  UserModel? _currentUser;
  bool _isLoading = false;
  String? _error;
  bool _isLoggedIn = false;
  StreamSubscription? _authSub;

  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isLoggedIn => _isLoggedIn;

  CruxAuthProvider() {
    _authSub = _authService.authStateChanges.listen((user) {
      if (user != null) {
        _currentUser = UserModel(
          uid: user.uid,
          email: user.email ?? '',
          name: user.displayName ?? 'Utilisateur',
        );
        _isLoggedIn = true;
      } else {
        _currentUser = null;
        _isLoggedIn = false;
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<bool> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      _setLoading(true);
      _clearError();
      final user = await _authService.signUp(email: email, password: password, name: name);
      if (user != null) {
        _currentUser = user;
        _isLoggedIn = true;
        _logger.i('✅ Inscription réussie');
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      _setError('Erreur inscription: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> signIn({required String email, required String password}) async {
    try {
      _setLoading(true);
      _clearError();
      final user = await _authService.signIn(email: email, password: password);
      if (user != null) {
        _currentUser = user;
        _isLoggedIn = true;
        _logger.i('✅ Connexion réussie');
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      _setError('Erreur connexion: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> signOut() async {
    try {
      _setLoading(true);
      _clearError();
      await _authService.signOut();
      _currentUser = null;
      _isLoggedIn = false;
      _logger.i('✅ Déconnexion réussie');
      notifyListeners();
    } catch (e) {
      _setError('Erreur déconnexion: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> resetPassword(String email) async {
    try {
      _setLoading(true);
      _clearError();
      await _authService.resetPassword(email);
      notifyListeners();
      return true;
    } catch (e) {
      _setError('Erreur réinitialisation: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setError(String error) {
    _error = error;
    notifyListeners();
  }

  void _clearError() => _error = null;
}
