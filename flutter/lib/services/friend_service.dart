import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../core/constants.dart';

/// Talks to the /friends routes, plus /users/search on the Node backend.
///
/// Friend status is one of: 'none', 'pending_outgoing', 'pending_incoming',
/// 'friends', 'self'. The Add Friend button renders straight off that string.
class FriendService {
  final FirebaseAuth _firebase = FirebaseAuth.instance;

  Future<String?> _getToken() async {
    final user = _firebase.currentUser;
    if (user == null) return null;
    return await user.getIdToken();
  }

  // SEARCH USERS — GET /users/search?q=
  Future<Map<String, dynamic>> searchUsers(String query) async {
    try {
      final token = await _getToken();
      if (token == null) return {'success': false, 'users': []};

      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/users/search?q=${Uri.encodeQueryComponent(query)}'),
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {
          'success': true,
          'users': List<Map<String, dynamic>>.from(data['users'] ?? []),
        };
      }
      return {'success': false, 'users': [], 'message': data['message']};
    } catch (e) {
      return {'success': false, 'users': [], 'message': 'Could not reach server'};
    }
  }

  // GET MY FRIENDS — GET /friends
  Future<Map<String, dynamic>> getFriends() async {
    try {
      final token = await _getToken();
      if (token == null) return {'success': false, 'friends': []};

      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/friends'),
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {
          'success': true,
          'friends': List<Map<String, dynamic>>.from(data['friends'] ?? []),
        };
      }
      return {'success': false, 'friends': []};
    } catch (e) {
      return {'success': false, 'friends': []};
    }
  }

  // GET PENDING REQUESTS — GET /friends/requests
  // Returns both directions so the Requests tab can show "waiting on you" and
  // "waiting on them" without a second call.
  Future<Map<String, dynamic>> getRequests() async {
    try {
      final token = await _getToken();
      if (token == null) return {'success': false, 'incoming': [], 'outgoing': []};

      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/friends/requests'),
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {
          'success': true,
          'incoming': List<Map<String, dynamic>>.from(data['incoming'] ?? []),
          'outgoing': List<Map<String, dynamic>>.from(data['outgoing'] ?? []),
        };
      }
      return {'success': false, 'incoming': [], 'outgoing': []};
    } catch (e) {
      return {'success': false, 'incoming': [], 'outgoing': []};
    }
  }

  // GET THE FEED — GET /friends/feed
  Future<Map<String, dynamic>> getFeed({int limit = 30, int offset = 0}) async {
    try {
      final token = await _getToken();
      if (token == null) return {'success': false, 'activities': [], 'hasMore': false};

      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/friends/feed?limit=$limit&offset=$offset'),
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {
          'success': true,
          'activities': List<Map<String, dynamic>>.from(data['activities'] ?? []),
          'hasMore': data['hasMore'] == true,
        };
      }
      return {'success': false, 'activities': [], 'hasMore': false};
    } catch (e) {
      return {
        'success': false,
        'activities': [],
        'hasMore': false,
        'message': 'Could not reach server',
      };
    }
  }

  // FRIEND STATUS WITH ONE USER — GET /friends/status/:userId
  Future<String> getStatus(String userId) async {
    try {
      final token = await _getToken();
      if (token == null) return 'none';

      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/friends/status/$userId'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body)['status'] as String? ?? 'none';
      }
      return 'none';
    } catch (e) {
      return 'none';
    }
  }

  // SEND A REQUEST — POST /friends/requests
  Future<Map<String, dynamic>> sendRequest(String userId) async {
    try {
      final token = await _getToken();
      if (token == null) return {'success': false, 'message': 'Not logged in'};

      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/friends/requests'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'userId': userId}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 201) {
        return {'success': true, 'status': 'pending_outgoing'};
      }
      return {'success': false, 'message': data['message'] ?? 'Could not send request'};
    } catch (e) {
      return {'success': false, 'message': 'Could not reach server'};
    }
  }

  // ACCEPT — POST /friends/requests/:id/accept
  Future<Map<String, dynamic>> acceptRequest(int requestId) async =>
      _postRequestAction(requestId, 'accept', 'friends');

  // DECLINE — POST /friends/requests/:id/decline
  Future<Map<String, dynamic>> declineRequest(int requestId) async =>
      _postRequestAction(requestId, 'decline', 'none');

  Future<Map<String, dynamic>> _postRequestAction(
    int requestId,
    String action,
    String resultingStatus,
  ) async {
    try {
      final token = await _getToken();
      if (token == null) return {'success': false, 'message': 'Not logged in'};

      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/friends/requests/$requestId/$action'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        return {'success': true, 'status': resultingStatus};
      }
      final data = jsonDecode(response.body);
      return {'success': false, 'message': data['message'] ?? 'Something went wrong'};
    } catch (e) {
      return {'success': false, 'message': 'Could not reach server'};
    }
  }

  // UNFRIEND, OR CANCEL A REQUEST YOU SENT — DELETE /friends/:userId
  Future<Map<String, dynamic>> removeFriend(String userId) async {
    try {
      final token = await _getToken();
      if (token == null) return {'success': false, 'message': 'Not logged in'};

      final response = await http.delete(
        Uri.parse('${AppConstants.baseUrl}/friends/$userId'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        return {'success': true, 'status': 'none'};
      }
      final data = jsonDecode(response.body);
      return {'success': false, 'message': data['message'] ?? 'Something went wrong'};
    } catch (e) {
      return {'success': false, 'message': 'Could not reach server'};
    }
  }

  // ANOTHER USER'S PROFILE — GET /users/:id
  // Comes back with friendStatus attached so the profile screen doesn't have to
  // make a second call just to decide what the button says.
  Future<Map<String, dynamic>> getUserProfile(String userId) async {
    try {
      final token = await _getToken();
      if (token == null) return {'success': false};

      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/users/$userId'),
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {
          'success': true,
          'user': Map<String, dynamic>.from(data['user']),
          'friendStatus': data['friendStatus'] as String? ?? 'none',
          'requestId': data['requestId'],
        };
      }
      return {'success': false, 'message': data['message'] ?? 'User not found'};
    } catch (e) {
      return {'success': false, 'message': 'Could not reach server'};
    }
  }

  // ANOTHER USER'S LOGGED GAMES — GET /users/:id/games
  Future<List<Map<String, dynamic>>> getUserGames(String userId) async {
    try {
      final token = await _getToken();
      if (token == null) return [];

      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/users/$userId/games'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['games'] ?? []);
      }
      return [];
    } catch (e) {
      return [];
    }
  }
}
