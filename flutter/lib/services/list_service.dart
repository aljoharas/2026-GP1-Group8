import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../core/constants.dart';

/// Talks to the /lists routes on the Node backend.
///
/// A list comes back as a plain map so it can be rendered without a model:
///   { id, name, emoji, is_public, created_at, games: [ { rawg_id, name, ... } ] }
class ListService {
  final FirebaseAuth _firebase = FirebaseAuth.instance;

  Future<String?> _getToken() async {
    final user = _firebase.currentUser;
    if (user == null) return null;
    return await user.getIdToken();
  }

  // GET ALL OF MY LISTS
  Future<Map<String, dynamic>> getLists() async {
    try {
      final token = await _getToken();
      if (token == null) return {'success': false, 'lists': []};

      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/lists'),
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {
          'success': true,
          'lists': List<Map<String, dynamic>>.from(data['lists'] ?? []),
        };
      }
      return {'success': false, 'lists': []};
    } catch (e) {
      return {'success': false, 'lists': []};
    }
  }

  // GET ANOTHER USER'S PUBLIC LISTS
  Future<Map<String, dynamic>> getPublicLists(String userId) async {
    try {
      final token = await _getToken();
      if (token == null) return {'success': false, 'lists': []};

      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/lists/user/$userId'),
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {
          'success': true,
          'lists': List<Map<String, dynamic>>.from(data['lists'] ?? []),
        };
      }
      return {'success': false, 'lists': []};
    } catch (e) {
      return {'success': false, 'lists': []};
    }
  }

  // CREATE A LIST
  Future<Map<String, dynamic>> createList({
    required String name,
    String emoji = '🎮',
    bool isPublic = false,
  }) async {
    try {
      final token = await _getToken();
      if (token == null) return {'success': false, 'message': 'Not logged in'};

      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/lists'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'name': name, 'emoji': emoji, 'isPublic': isPublic}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 201) {
        return {'success': true, 'list': data['list']};
      }
      return {'success': false, 'message': data['message'] ?? 'Could not create list'};
    } catch (e) {
      return {'success': false, 'message': 'Could not reach server'};
    }
  }

  // UPDATE A LIST — pass only what changed
  Future<Map<String, dynamic>> updateList(
    int listId, {
    String? name,
    String? emoji,
    bool? isPublic,
  }) async {
    try {
      final token = await _getToken();
      if (token == null) return {'success': false, 'message': 'Not logged in'};

      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (emoji != null) body['emoji'] = emoji;
      if (isPublic != null) body['isPublic'] = isPublic;

      final response = await http.patch(
        Uri.parse('${AppConstants.baseUrl}/lists/$listId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'list': data['list']};
      }
      return {'success': false, 'message': data['message'] ?? 'Could not update list'};
    } catch (e) {
      return {'success': false, 'message': 'Could not reach server'};
    }
  }

  // DELETE A LIST
  Future<Map<String, dynamic>> deleteList(int listId) async {
    try {
      final token = await _getToken();
      if (token == null) return {'success': false, 'message': 'Not logged in'};

      final response = await http.delete(
        Uri.parse('${AppConstants.baseUrl}/lists/$listId'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) return {'success': true};
      final data = jsonDecode(response.body);
      return {'success': false, 'message': data['message'] ?? 'Could not delete list'};
    } catch (e) {
      return {'success': false, 'message': 'Could not reach server'};
    }
  }

  // ADD A GAME TO A LIST
  Future<Map<String, dynamic>> addGame(int listId, int rawgId) async {
    try {
      final token = await _getToken();
      if (token == null) return {'success': false, 'message': 'Not logged in'};

      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/lists/$listId/games'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'rawgId': rawgId}),
      );

      if (response.statusCode == 200) return {'success': true};
      final data = jsonDecode(response.body);
      return {'success': false, 'message': data['message'] ?? 'Could not add game'};
    } catch (e) {
      return {'success': false, 'message': 'Could not reach server'};
    }
  }

  // REMOVE A GAME FROM A LIST
  Future<Map<String, dynamic>> removeGame(int listId, int rawgId) async {
    try {
      final token = await _getToken();
      if (token == null) return {'success': false, 'message': 'Not logged in'};

      final response = await http.delete(
        Uri.parse('${AppConstants.baseUrl}/lists/$listId/games/$rawgId'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) return {'success': true};
      final data = jsonDecode(response.body);
      return {'success': false, 'message': data['message'] ?? 'Could not remove game'};
    } catch (e) {
      return {'success': false, 'message': 'Could not reach server'};
    }
  }
}
