import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../core/constants.dart';

/// Talks to the /notifications routes on the Node backend.
///
/// A notification row carries actor_username / actor_avatar_url inline, and for
/// friend requests also friendship_id + friendship_status read from the live
/// friendships row — so a request accepted elsewhere stops showing buttons.
class NotificationService {
  final FirebaseAuth _firebase = FirebaseAuth.instance;

  Future<String?> _getToken() async {
    final user = _firebase.currentUser;
    if (user == null) return null;
    return await user.getIdToken();
  }

  // GET /notifications
  Future<Map<String, dynamic>> getNotifications() async {
    try {
      final token = await _getToken();
      if (token == null) return {'success': false, 'notifications': []};

      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/notifications'),
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {
          'success': true,
          'notifications': List<Map<String, dynamic>>.from(data['notifications'] ?? []),
        };
      }
      return {'success': false, 'notifications': []};
    } catch (e) {
      return {
        'success': false,
        'notifications': [],
        'message': 'Could not reach server',
      };
    }
  }

  // GET /notifications/unread-count
  Future<int> getUnreadCount() async {
    try {
      final token = await _getToken();
      if (token == null) return 0;

      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/notifications/unread-count'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body)['count'] as int? ?? 0;
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }

  // POST /notifications/:id/read
  Future<bool> markRead(int id) async => _post('/notifications/$id/read');

  // POST /notifications/read-all
  Future<bool> markAllRead() async => _post('/notifications/read-all');

  Future<bool> _post(String path) async {
    try {
      final token = await _getToken();
      if (token == null) return false;

      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}$path'),
        headers: {'Authorization': 'Bearer $token'},
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // DELETE /notifications/:id
  Future<bool> deleteNotification(int id) async {
    try {
      final token = await _getToken();
      if (token == null) return false;

      final response = await http.delete(
        Uri.parse('${AppConstants.baseUrl}/notifications/$id'),
        headers: {'Authorization': 'Bearer $token'},
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
