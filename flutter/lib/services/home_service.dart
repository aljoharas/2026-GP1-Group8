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
  // GET /home/recommended — ألعاب بتقييم عالي مش في مكتبة المستخدم
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
  // GET /home/popular — أعلى rawg_rating
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

  // GET FRIEND ACTIVITY
  // GET /home/friends-activity — نشاط الأصدقاء من activity_feed
  Future<Map<String, dynamic>> getFriendActivity() async {
    try {
      final token = await _getToken();
      if (token == null) return {'success': false, 'message': 'Not logged in'};

      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/home/friends-activity'),
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'activities': data['activities']};
      }
      return {'success': false, 'message': data['message']};
    } catch (e) {
      return {'success': false, 'message': 'Could not reach server'};
    }
  }
}
