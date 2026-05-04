import 'package:flutter/material.dart';
import '../services/game_service.dart';

enum GameStatus { idle, loading, success, error }

class GameProvider extends ChangeNotifier {
  final GameService _gameService = GameService();

  GameStatus _searchStatus = GameStatus.idle;
  GameStatus _profileStatus = GameStatus.idle;
  GameStatus _achievementsStatus = GameStatus.idle;
  GameStatus _reviewsStatus = GameStatus.idle;
  List<dynamic> _searchResults = [];
  Map<String, dynamic>? _selectedGame;
  List<dynamic> _achievements = [];
  List<dynamic> _reviews = [];
  int? _userRating;
  double? _communityRating;
  int _communityRatingCount = 0;
  bool _isFavorite = false;
  String _errorMessage = '';

  GameStatus get searchStatus => _searchStatus;
  GameStatus get profileStatus => _profileStatus;
  GameStatus get achievementsStatus => _achievementsStatus;
  GameStatus get reviewsStatus => _reviewsStatus;
  List<dynamic> get searchResults => _searchResults;
  Map<String, dynamic>? get selectedGame => _selectedGame;
  List<dynamic> get achievements => _achievements;
  List<dynamic> get reviews => _reviews;
  int? get userRating => _userRating;
  double? get communityRating => _communityRating;
  int get communityRatingCount => _communityRatingCount;
  bool get isFavorite => _isFavorite;
  String get errorMessage => _errorMessage;
  bool get isSearching => _searchStatus == GameStatus.loading;
  bool get isLoadingProfile => _profileStatus == GameStatus.loading;
  bool get isLoadingAchievements => _achievementsStatus == GameStatus.loading;
  bool get isLoadingReviews => _reviewsStatus == GameStatus.loading;

  // SEARCH
  Future<void> searchGames(String query) async {
    if (query.trim().length < 2) {
      _searchResults = [];
      _setSearchStatus(GameStatus.idle);
      return;
    }
    _setSearchStatus(GameStatus.loading);
    final result = await _gameService.searchGames(query.trim());
    if (result['success']) {
      _searchResults = result['games'];
      _setSearchStatus(GameStatus.success);
    } else {
      _errorMessage = result['message'];
      _setSearchStatus(GameStatus.error);
    }
  }

  // GET SINGLE GAME PROFILE
  Future<void> getGame(int rawgId) async {
    _setProfileStatus(GameStatus.loading);
    final result = await _gameService.getGame(rawgId);
    if (result['success']) {
      _selectedGame = result['game'];
      _setProfileStatus(GameStatus.success);
    } else {
      _errorMessage = result['message'];
      _setProfileStatus(GameStatus.error);
    }
  }

  // GET GAME BY NAME — used by GameProfileScreen when rawgId is null
  Future<void> getGameByName(String name) async {
    _setProfileStatus(GameStatus.loading);
    final searchResult = await _gameService.searchGames(name);
    if (!searchResult['success']) {
      _errorMessage = searchResult['message'];
      _setProfileStatus(GameStatus.error);
      return;
    }
    final games = searchResult['games'] as List;
    if (games.isEmpty) {
      _errorMessage = 'Game not found';
      _setProfileStatus(GameStatus.error);
      return;
    }
    // Find exact name match first, else use first result
    Map<String, dynamic>? match;
    for (final g in games) {
      final game = g as Map<String, dynamic>;
      if ((game['name'] as String?)?.toLowerCase() == name.toLowerCase()) {
        match = game;
        break;
      }
    }
    match ??= games.first as Map<String, dynamic>;

    final rawgId = match['rawg_id'] ?? match['id'];
    final id = rawgId is int ? rawgId : int.tryParse(rawgId.toString());
    if (id == null) {
      _errorMessage = 'Could not resolve game ID';
      _setProfileStatus(GameStatus.error);
      return;
    }
    final profileResult = await _gameService.getGame(id);
    if (profileResult['success']) {
      _selectedGame = profileResult['game'];
      _setProfileStatus(GameStatus.success);
    } else {
      _errorMessage = profileResult['message'];
      _setProfileStatus(GameStatus.error);
    }
  }

  // SEARCH GAME FOR ID + IMAGE — used by user profile screen
  // Returns { 'rawgId': int, 'imageUrl': String? } or null
  Future<Map<String, dynamic>?> searchGameForId(String name) async {
    final result = await _gameService.searchGames(name);
    if (!result['success']) return null;
    final games = result['games'] as List;
    if (games.isEmpty) return null;

    // 1. Try exact match
    // 2. Try contains match
    // 3. Fall back to first result
    Map<String, dynamic>? match;
    final nameLower = name.toLowerCase();

    for (final g in games) {
      final game = g as Map<String, dynamic>;
      final gameName = (game['name'] as String?)?.toLowerCase() ?? '';
      if (gameName == nameLower) {
        match = game;
        break;
      }
    }
    if (match == null) {
      for (final g in games) {
        final game = g as Map<String, dynamic>;
        final gameName = (game['name'] as String?)?.toLowerCase() ?? '';
        if (gameName.contains(nameLower) || nameLower.contains(gameName)) {
          match = game;
          break;
        }
      }
    }
    match ??= games.first as Map<String, dynamic>;

    final rawgId = match['rawg_id'] ?? match['id'];
    final id = rawgId is int ? rawgId : int.tryParse(rawgId.toString());
    if (id == null) return null;

    return {'rawgId': id, 'imageUrl': match['background_image'] as String?};
  }

  // GET ACHIEVEMENTS
  Future<void> getAchievements(int rawgId) async {
    _achievements = [];
    _achievementsStatus = GameStatus.loading;
    notifyListeners();
    final result = await _gameService.getAchievements(rawgId);
    if (result['success']) {
      _achievements = result['achievements'] ?? [];
      _achievementsStatus = GameStatus.success;
    } else {
      _errorMessage = result['message'];
      _achievementsStatus = GameStatus.error;
    }
    notifyListeners();
  }

  // LOAD REVIEWS + USER RATING
  Future<void> loadReviews(int rawgId) async {
    _reviewsStatus = GameStatus.loading;
    notifyListeners();
    try {
      final result = await _gameService.getReviews(rawgId);
      if (result['success']) {
        _reviews = result['reviews'] ?? [];
        final r = result['userRating'];
        _userRating = r != null ? (r as num).toInt() : null;
        final cr = result['communityRating'];
        _communityRating = cr != null ? (cr as num).toDouble() : null;
        _communityRatingCount = (result['communityRatingCount'] as num?)?.toInt() ?? 0;
        _reviewsStatus = GameStatus.success;
      } else {
        _reviews = [];
        _communityRating = null;
        _communityRatingCount = 0;
        _reviewsStatus = GameStatus.error;
      }
    } catch (_) {
      _reviews = [];
      _communityRating = null;
      _communityRatingCount = 0;
      _reviewsStatus = GameStatus.error;
    }
    notifyListeners();
  }

  // RATE A GAME (rating 0 removes the existing rating)
  Future<bool> rateGame(int rawgId, int rating) async {
    final result = await _gameService.rateGame(rawgId, rating);
    if (result['success']) {
      _userRating = rating == 0 ? null : rating;
      notifyListeners();
      await loadReviews(rawgId);
      return true;
    }
    return false;
  }

  // SUBMIT A REVIEW
  Future<bool> submitReview(int rawgId, String text, int rating) async {
    final result = await _gameService.submitReview(rawgId, text, rating);
    if (result['success']) {
      _userRating = rating == 0 ? null : rating;
      notifyListeners();
      await loadReviews(rawgId);
      return true;
    }
    return false;
  }

  Future<void> loadFavoriteStatus(int rawgId) async {
    final result = await _gameService.getFavoriteStatus(rawgId);
    if (result['success']) {
      _isFavorite = result['isFavorite'] as bool;
      notifyListeners();
    }
  }

  Future<void> toggleFavorite(int rawgId) async {
    final result = await _gameService.toggleFavorite(rawgId);
    if (result['success']) {
      _isFavorite = result['isFavorite'] as bool;
      notifyListeners();
    }
  }

  void clearGame() {
    _selectedGame = null;
    _reviews = [];
    _userRating = null;
    _communityRating = null;
    _communityRatingCount = 0;
    _isFavorite = false;
    _profileStatus = GameStatus.idle;
    _reviewsStatus = GameStatus.idle;
    notifyListeners();
  }

  void clearSearch() {
    _searchResults = [];
    _setSearchStatus(GameStatus.idle);
  }

  void _setSearchStatus(GameStatus s) {
    _searchStatus = s;
    notifyListeners();
  }

  void _setProfileStatus(GameStatus s) {
    _profileStatus = s;
    notifyListeners();
  }
}
