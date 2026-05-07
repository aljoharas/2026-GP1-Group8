import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../core/constants.dart';

class AuthService {
  final FirebaseAuth _firebase = FirebaseAuth.instance;

  // ── Upload image via Node backend (which uploads to Cloudinary) ───────────
  Future<String?> uploadToCloudinary(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) return null;

      // Get Firebase token to authenticate with our backend
      final user = _firebase.currentUser;
      if (user == null) return null;
      final token = await user.getIdToken();

      final uri = Uri.parse('${AppConstants.baseUrl}/users/upload-avatar');

      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(await http.MultipartFile.fromPath(
          'avatar',
          imagePath,
          contentType: MediaType('image', 'jpeg'),
        ));

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return data['avatar_url'] as String?;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Check whether a username is available. Public endpoint — no auth needed.
  // Returns null if available, or an error message if not.
  Future<String?> _checkUsernameAvailable(String username) async {
    try {
      final response = await http.get(
        Uri.parse(
          '${AppConstants.baseUrl}/auth/check-username/${Uri.encodeComponent(username)}',
        ),
      );
      if (response.statusCode != 200) {
        return 'Could not verify username. Try again.';
      }
      final data = jsonDecode(response.body);
      if (data['available'] == true) return null;
      return data['message'] as String? ?? 'Username already taken';
    } catch (_) {
      return 'Could not reach server. Check your connection.';
    }
  }

  // REGISTER
  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String username,
    String? profileImagePath,
    String? bio,
  }) async {
    try {
      // Step 0: Check username before touching Firebase, so a taken username
      // doesn't leave the email locked in Firebase if anything later fails.
      final usernameError = await _checkUsernameAvailable(username);
      if (usernameError != null) {
        return {'success': false, 'message': usernameError};
      }

      // Step 1: Create user in Firebase
      final credential = await _firebase.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Step 2: Get token to send to our Node backend
      final token = await credential.user!.getIdToken();

      // Step 3: Upload profile picture via backend if provided
      String? avatarUrl;
      if (profileImagePath != null) {
        avatarUrl = await uploadToCloudinary(profileImagePath);
      }

      // Step 4: Save user to our PostgreSQL database via Node
      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/auth/register'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'username': username,
          if (bio != null && bio.isNotEmpty) 'bio': bio,
          if (avatarUrl != null) 'avatar_url': avatarUrl,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        return {'success': true, 'user': data['user']};
      }

      // Backend rejected (e.g. username taken) — roll back Firebase account so email isn't locked.
      await credential.user?.delete();
      return {'success': false, 'message': data['message']};
    } on FirebaseAuthException catch (e) {
      return {'success': false, 'message': _readableError(e.code)};
    } catch (e) {
      try {
        await _firebase.currentUser?.delete();
      } catch (_) {}
      return {'success': false, 'message': 'Something went wrong. Try again.'};
    }
  }

  // LOGIN
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _firebase.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final token = await credential.user!.getIdToken();

      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/auth/login'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'user': data['user']};
      }
      return {'success': false, 'message': data['message']};
    } on FirebaseAuthException catch (e) {
      return {'success': false, 'message': _readableError(e.code)};
    } catch (e) {
      return {'success': false, 'message': 'Something went wrong. Try again.'};
    }
  }

  // LOGOUT
  Future<void> logout() async {
    await _firebase.signOut();
  }

  // UPDATE PROFILE
  Future<Map<String, dynamic>> updateProfile({
    required String username,
    required String bio,
    required String token,
    String? avatarUrl,
  }) async {
    try {
      final response = await http.patch(
        Uri.parse('${AppConstants.baseUrl}/users/me'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'username': username,
          'bio': bio,
          if (avatarUrl != null) 'avatar_url': avatarUrl,
        }),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'user': data['user']};
      }
      return {'success': false, 'message': data['message']};
    } catch (e) {
      return {'success': false, 'message': 'Could not reach server'};
    }
  }

  // FORGOT PASSWORD
  Future<Map<String, dynamic>> sendPasswordReset(String email) async {
    try {
      await _firebase.sendPasswordResetEmail(email: email);
      return {'success': true};
    } on FirebaseAuthException catch (e) {
      return {'success': false, 'message': _readableError(e.code)};
    } catch (e) {
      return {'success': false, 'message': 'Something went wrong. Try again.'};
    }
  }

  String _readableError(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'email-already-in-use':
        return 'This email is already registered.';
      case 'invalid-email':
        return 'Please enter a valid email.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      default:
        return 'Authentication failed. Please try again.';
    }
  }
}