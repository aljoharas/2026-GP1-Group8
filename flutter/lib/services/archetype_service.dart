import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../core/constants.dart';
import '../models/archetype.dart';

class ArchetypeService {
  final FirebaseAuth _firebase = FirebaseAuth.instance;

  Future<String?> _getToken() async {
    final user = _firebase.currentUser;
    if (user == null) return null;
    return await user.getIdToken();
  }

  // GET MY ARCHETYPE — GET /users/me/archetype
  // The server takes the uid from the token; the app never sends one.
  Future<Map<String, dynamic>> getMine() => _get('/users/me/archetype');

  // GET A FRIEND'S ARCHETYPE — GET /users/:id/archetype (name + description only)
  Future<Map<String, dynamic>> getForUser(String userId) =>
      _get('/users/${Uri.encodeComponent(userId)}/archetype');

  Future<Map<String, dynamic>> _get(String path) async {
    try {
      final token = await _getToken();
      if (token == null) return {'success': false, 'message': 'Not logged in'};

      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}$path'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        return {'success': true, 'archetype': Archetype.fromJson(jsonDecode(response.body))};
      }
      return {'success': false, 'statusCode': response.statusCode, 'message': archetypeErrorMessage(response.statusCode)};
    } catch (e) {
      return {'success': false, 'message': 'Could not reach server'};
    }
  }
}

/// What to tell the user for a failed request. 503 means the model isn't
/// loaded on the server (temporary); 502 that the archetype service is down.
String archetypeErrorMessage(int? statusCode) => switch (statusCode) {
      503 => "Archetypes are taking a short break. Try again soon.",
      502 => "Couldn't reach the archetype service. Try again soon.",
      403 => 'Only friends can see this.',
      _ => "Couldn't load the archetype.",
    };
