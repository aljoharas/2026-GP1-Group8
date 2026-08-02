import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../core/constants.dart';

class HomeService {
  final FirebaseAuth _firebase = FirebaseAuth.instance;

  Future<String?> _getToken() async {
    final user = _firebase.currentUser;
    if (user == null) return null;
    return await user.getIdToken();
  }

  // GET RECOMMENDED GAMES
  // GET /home/recommended 
  Future<Map<String, dynamic>> getRecommended() async {
    try {
      final token = await _getToken();
      if (token == null) return {'success': false, 'message': 'Not logged in'};

      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/home/recommended'),
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'games': data['games']};
      }
      return {'success': false, 'message': data['message']};
    } catch (e) {
      return {'success': false, 'message': 'Could not reach server'};
    }
  }

  // GET POPULAR GAMES
  // GET /home/popular 
  Future<Map<String, dynamic>> getPopular() async {
    try {
      final token = await _getToken();
      if (token == null) return {'success': false, 'message': 'Not logged in'};

      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/home/popular'),
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'games': data['games']};
      }
      return {'success': false, 'message': data['message']};
    } catch (e) {
      return {'success': false, 'message': 'Could not reach server'};
    }
  }

  // GET WHAT FRIENDS ARE PLAYING
  // GET /home/friends-activity
  //
  // Returns game rows in the same shape as /popular and /recommended, with the
  // friend who is playing each one attached (friend_username, friend_avatar_url).
  // The chronological feed lives on the Friends screen instead.
  Future<Map<String, dynamic>> getFriendGames() async {
    try {
      final token = await _getToken();
      if (token == null) return {'success': false, 'message': 'Not logged in'};

      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/home/friends-activity'),
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'games': data['games'] ?? []};
      }
      return {'success': false, 'message': data['message']};
    } catch (e) {
      return {'success': false, 'message': 'Could not reach server'};
    }
  }
}
