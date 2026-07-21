import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../core/constants.dart';

class GameService {
  final FirebaseAuth _firebase = FirebaseAuth.instance;

  // Get the current user's Firebase token
  // This is sent with every request so Node can verify who's asking
  Future<String?> _getToken() async {
    final user = _firebase.currentUser;
    if (user == null) return null;
    return await user.getIdToken();
  }

  // SEARCH GAMES
  // Calls GET /games/search?q=query on  Node backend
  // Node checks your DB first, then RAWG if not found
  Future<Map<String, dynamic>> searchGames(String query) async {
    try {
      final token = await _getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not logged in'};
      }

      final response = await http.get(
        Uri.parse(
          '${AppConstants.baseUrl}/games/search?q=${Uri.encodeComponent(query)}',
        ),
        headers: {
          'Authorization': 'Bearer $token',
        },
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

  // GET ACHIEVEMENTS FOR A GAME
  // Calls GET /games/:id/achievements on Node backend
  // Node should proxy: GET https://api.rawg.io/api/games/{rawgId}/achievements?key={KEY}
  Future<Map<String, dynamic>> getAchievements(int rawgId) async {
    try {
      final token = await _getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not logged in'};
      }

      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/games/$rawgId/achievements'),
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'achievements': data['achievements']};
      }
      return {'success': false, 'message': data['message'] ?? 'Failed to load achievements'};
    } catch (e) {
      return {'success': false, 'message': 'Could not reach server'};
    }
  }

  // LOG A GAME
  // Calls POST /users/me/games
  Future<Map<String, dynamic>> logGame({
    required int rawgId,
    double? hoursPlayed,
    String? comment,
    List<String> achievements = const [],
    bool isFinished = false,
    bool isPaused = false,
    DateTime? loggedAt,
    String? platformName,
  }) async {
    try {
      final token = await _getToken();
      if (token == null) return {'success': false, 'message': 'Not logged in'};

      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/users/me/games'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'rawg_id': rawgId,
          if (hoursPlayed != null) 'hours_played': hoursPlayed,
          if (comment != null && comment.isNotEmpty) 'comment': comment,
          'achievements': achievements,
          'is_finished': isFinished,
          'is_paused': isPaused,
          'logged_at': (loggedAt ?? DateTime.now()).toIso8601String(),
          if (platformName != null) 'platform_name': platformName,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 201) return {'success': true};
      return {'success': false, 'message': data['message']};
    } catch (e) {
      return {'success': false, 'message': 'Could not reach server'};
    }
  }

  // GET MY LOGGED GAMES
  // Calls GET /users/me/games
  Future<Map<String, dynamic>> getLoggedGames() async {
    try {
      final token = await _getToken();
      if (token == null) return {'success': false, 'message': 'Not logged in'};

      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/users/me/games'),
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

  // RATE A GAME (1–5 stars)
  Future<Map<String, dynamic>> rateGame(int rawgId, int rating) async {
    try {
      final token = await _getToken();
      if (token == null) return {'success': false, 'message': 'Not logged in'};

      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/games/$rawgId/rate'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'rating': rating}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) return {'success': true};
      return {'success': false, 'message': data['message']};
    } catch (e) {
      return {'success': false, 'message': 'Could not reach server'};
    }
  }

  // SUBMIT A REVIEW
  Future<Map<String, dynamic>> submitReview(int rawgId, String text, int rating) async {
    try {
      final token = await _getToken();
      if (token == null) return {'success': false, 'message': 'Not logged in'};

      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/games/$rawgId/review'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'text': text, 'rating': rating}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) return {'success': true};
      return {'success': false, 'message': data['message']};
    } catch (e) {
      return {'success': false, 'message': 'Could not reach server'};
    }
  }

  // GET REVIEWS FOR A GAME
  Future<Map<String, dynamic>> getReviews(int rawgId) async {
    try {
      final token = await _getToken();
      if (token == null) return {'success': false, 'message': 'Not logged in'};

      final response = await http
          .get(
            Uri.parse('${AppConstants.baseUrl}/games/$rawgId/reviews'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {
          'success': true,
          'reviews': data['reviews'],
          'userRating': data['userRating'],
          'communityRating': data['communityRating'],
          'communityRatingCount': data['communityRatingCount'],
        };
      }
      return {'success': false, 'message': data['message']};
    } catch (e) {
      return {'success': false, 'message': 'Could not reach server'};
    }
  }

  // GET ALL FAVORITES
  Future<Map<String, dynamic>> getFavorites() async {
    try {
      final token = await _getToken();
      if (token == null) return {'success': false, 'favorites': []};
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/users/me/favorites'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'favorites': data['favorites']};
      }
      return {'success': false, 'favorites': []};
    } catch (e) {
      return {'success': false, 'favorites': []};
    }
  }

  // GET FAVORITE STATUS
  Future<Map<String, dynamic>> getFavoriteStatus(int rawgId) async {
    try {
      final token = await _getToken();
      if (token == null) return {'success': false, 'isFavorite': false};
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/games/$rawgId/favorite'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'isFavorite': data['isFavorite'] == true};
      }
      return {'success': false, 'isFavorite': false};
    } catch (e) {
      return {'success': false, 'isFavorite': false};
    }
  }

  // TOGGLE FAVORITE
  Future<Map<String, dynamic>> toggleFavorite(int rawgId) async {
    try {
      final token = await _getToken();
      if (token == null) return {'success': false};
      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/games/$rawgId/favorite'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'isFavorite': data['isFavorite'] == true};
      }
      return {'success': false};
    } catch (e) {
      return {'success': false};
    }
  }

  // UPDATE ACHIEVEMENTS FOR A SINGLE LOG ENTRY
  Future<Map<String, dynamic>> updateEntryAchievements(int entryId, List<String> achievements) async {
    try {
      final token = await _getToken();
      if (token == null) return {'success': false};
      final response = await http.patch(
        Uri.parse('${AppConstants.baseUrl}/users/me/games/entries/$entryId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'achievements': achievements}),
      );
      if (response.statusCode == 200) return {'success': true};
      return {'success': false};
    } catch (e) {
      return {'success': false};
    }
  }

  // REMOVE GAME FROM LIBRARY (deletes all logs for this game)
  Future<Map<String, dynamic>> removeGame({required int rawgId}) async {
    try {
      final token = await _getToken();
      if (token == null) return {'success': false, 'message': 'Not logged in'};

      final response = await http.delete(
        Uri.parse('${AppConstants.baseUrl}/users/me/games/$rawgId'),
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) return {'success': true, 'deleted': data['deleted']};
      return {'success': false, 'message': data['message']};
    } catch (e) {
      return {'success': false, 'message': 'Could not reach server'};
    }
  }

  // GET SINGLE GAME
  // Calls GET /games/:id on Node backend
  Future<Map<String, dynamic>> getGame(int rawgId) async {
    try {
      final token = await _getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not logged in'};
      }

      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/games/$rawgId'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'game': data['game']};
      }
      return {'success': false, 'message': data['message']};

    } catch (e) {
      return {'success': false, 'message': 'Could not reach server'};
    }
  }

  // GET FRIENDS COUNT
  Future<int> getFriendsCount() async {
    try {
      final token = await _getToken();
      if (token == null) return 0;
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/users/me/friends-count'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['count'] as int? ?? 0;
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }
}