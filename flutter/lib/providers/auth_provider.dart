import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';

enum AuthStatus { idle, loading, success, error }

enum UserStatus { online, offline, doNotDisturb }

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  AuthStatus _status = AuthStatus.idle;
  String _errorMessage = '';
  Map<String, dynamic>? currentUser;
  UserStatus userStatus = UserStatus.online;

  AuthStatus get status => _status;
  String get errorMessage => _errorMessage;
  bool get isLoading => _status == AuthStatus.loading;

  Future<bool> login(String email, String password) async {
    _set(AuthStatus.loading);
    final result = await _authService.login(email: email, password: password);
    if (result['success'] == true) {
      currentUser = result['user'];
      _set(AuthStatus.success);
      return true;
    }
    _errorMessage = result['message'];
    _set(AuthStatus.error);
    return false;
  }

  Future<bool> register(
    String email,
    String password,
    String username, {
    String? profileImagePath,
    String? bio,
  }) async {
    _set(AuthStatus.loading);
    final result = await _authService.register(
      email: email,
      password: password,
      username: username,
      profileImagePath: profileImagePath,
      bio: bio,
    );
    if (result['success'] == true) {
      currentUser = result['user'];
      _set(AuthStatus.success);
      return true;
    }
    _errorMessage = result['message'];
    _set(AuthStatus.error);
    return false;
  }

  // Get Firebase token
  Future<String?> getFirebaseToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return await user.getIdToken();
  }

  // Update profile (username + bio + optional avatar)
  // Returns null on success, or an error message string on failure.
  Future<String?> updateProfile({
    required String username,
    required String bio,
    required String token,
    String? avatarUrl,
  }) async {
    try {
      final response = await _authService.updateProfile(
        username: username,
        bio: bio,
        token: token,
        avatarUrl: avatarUrl,
      );
      if (response['success'] == true) {
        currentUser = response['user'];
        notifyListeners();
        return null;
      }
      return response['message'] as String? ?? 'Failed to update profile';
    } catch (_) {
      return 'Failed to update profile';
    }
  }

  // Forgot password
  Future<bool> sendPasswordReset(String email) async {
    _set(AuthStatus.loading);
    final result = await _authService.sendPasswordReset(email);
    if (result['success'] == true) {
      _set(AuthStatus.idle);
      return true;
    }
    _errorMessage = result['message'];
    _set(AuthStatus.error);
    return false;
  }

  Future<void> logout() async {
    await _authService.logout();
    currentUser = null;
    _set(AuthStatus.idle);
  }

  void setUserStatus(UserStatus s) {
    userStatus = s;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = '';
    _set(AuthStatus.idle);
  }

  void _set(AuthStatus s) {
    _status = s;
    notifyListeners();
  }
}