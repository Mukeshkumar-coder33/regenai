import 'package:flutter/material.dart';
import '../../../core/storage/session_storage.dart';
import '../data/auth_service.dart';
import '../data/user_model.dart';

/// Authentication State Controller
///
/// Uses ChangeNotifier to manage user session, authentication progress,
/// error handling, and logout operations across the app.
class AuthController extends ChangeNotifier {
  final AuthService _authService;

  UserModel? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;

  AuthController({AuthService? authService})
      : _authService = authService ?? AuthService();

  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _currentUser != null;

  /// Authenticate with username and password
  Future<bool> login({
    required String username,
    required String password,
    String portal = 'company',
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await _authService.login(
        username: username,
        password: password,
        portal: portal,
      );
      _currentUser = user;
      _isLoading = false;
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'An unexpected error occurred: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Check stored session on startup
  Future<bool> checkExistingSession() async {
    _isLoading = true;
    notifyListeners();

    try {
      final savedUser = await SessionStorage.getUserSession();
      if (savedUser != null && savedUser.token.isNotEmpty) {
        _currentUser = savedUser;
        _isLoading = false;
        notifyListeners();
        return true;
      }
    } catch (_) {
      await SessionStorage.clearSession();
    }

    _currentUser = null;
    _isLoading = false;
    notifyListeners();
    return false;
  }

  /// Sign out and purge local credentials
  Future<void> logout() async {
    await SessionStorage.clearSession();
    _currentUser = null;
    _errorMessage = null;
    notifyListeners();
  }

  /// Switch from Super Admin to EMS Company mode
  Future<bool> switchToEms() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await _authService.switchToEms();
      _currentUser = user;
      _isLoading = false;
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Switch failed: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Switch from Company mode to Super Admin mode
  Future<bool> switchToSuperAdmin() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await _authService.switchToSuperAdmin();
      _currentUser = user;
      _isLoading = false;
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Switch failed: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Clear any error message
  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }
}

