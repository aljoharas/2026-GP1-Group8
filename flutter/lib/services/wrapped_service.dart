import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../core/constants.dart';
import '../models/wrapped.dart';

class WrappedService {
  final FirebaseAuth _firebase = FirebaseAuth.instance;

  Future<String?> _getToken() async {
    final user = _firebase.currentUser;
    if (user == null) return null;
    return await user.getIdToken();
  }

  // GET GAMING WRAPPED
  // GET /users/me/wrapped?year=2026 (year defaults to the current one)
  Future<Map<String, dynamic>> getWrapped({int? year}) async {
    try {
      final token = await _getToken();
      if (token == null) return {'success': false, 'message': 'Not logged in'};

      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/users/me/wrapped')
            .replace(queryParameters: year == null ? null : {'year': '$year'}),
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'wrapped': WrappedResponse.fromJson(data)};
      }
      return {'success': false, 'message': data['message'] ?? data['detail'] ?? 'Could not load Wrapped'};
    } catch (e) {
      return {'success': false, 'message': 'Could not reach server'};
    }
  }
}
