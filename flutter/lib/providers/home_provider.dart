import 'package:flutter/material.dart';
import '../services/home_service.dart';

enum HomeStatus { idle, loading, success, error }

class HomeProvider extends ChangeNotifier {
  final HomeService _homeService = HomeService();

  HomeStatus _recommendedStatus = HomeStatus.idle;
  HomeStatus _popularStatus     = HomeStatus.idle;
  HomeStatus _friendsStatus     = HomeStatus.idle;

  List<dynamic> _recommendedGames  = [];
  List<dynamic> _popularGames      = [];
  List<dynamic> _friendGames       = [];

  String _errorMessage = '';

  // ── Getters ────────────────────────────────────────────────────────────────

  HomeStatus get recommendedStatus  => _recommendedStatus;
  HomeStatus get popularStatus      => _popularStatus;
  HomeStatus get friendsStatus      => _friendsStatus;

  List<dynamic> get recommendedGames  => _recommendedGames;
  List<dynamic> get popularGames      => _popularGames;

  /// Games friends are currently playing — same row shape as the other two
  /// lists, plus friend_username / friend_avatar_url for attribution.
  List<dynamic> get friendGames       => _friendGames;

  String get errorMessage => _errorMessage;

  bool get isLoadingRecommended => _recommendedStatus == HomeStatus.loading;
  bool get isLoadingPopular     => _popularStatus     == HomeStatus.loading;
  bool get isLoadingFriends     => _friendsStatus     == HomeStatus.loading;
  bool get isLoadingAll =>
      isLoadingRecommended || isLoadingPopular || isLoadingFriends;

  // ── Load All ───────────────────────────────────────────────────────────────

  Future<void> loadHomeData() async {
    _setAll(HomeStatus.loading);
    await Future.wait([
      _fetchRecommended(),
      _fetchPopular(),
      _fetchFriendGames(),
    ]);
  }

  Future<void> refresh() async => loadHomeData();

  // ── Fetchers ───────────────────────────────────────────────────────────────

  Future<void> _fetchRecommended() async {
    final result = await _homeService.getRecommended();
    if (result['success']) {
      _recommendedGames = result['games'];
      _recommendedStatus = HomeStatus.success;
    } else {
      _errorMessage = result['message'];
      _recommendedStatus = HomeStatus.error;
    }
    notifyListeners();
  }

  Future<void> _fetchPopular() async {
    final result = await _homeService.getPopular();
    if (result['success']) {
      _popularGames = result['games'];
      _popularStatus = HomeStatus.success;
    } else {
      _errorMessage = result['message'];
      _popularStatus = HomeStatus.error;
    }
    notifyListeners();
  }

  Future<void> _fetchFriendGames() async {
    final result = await _homeService.getFriendGames();
    if (result['success']) {
      _friendGames = result['games'];
      _friendsStatus = HomeStatus.success;
    } else {
      _errorMessage = result['message'];
      _friendsStatus = HomeStatus.error;
    }
    notifyListeners();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _setAll(HomeStatus s) {
    _recommendedStatus = s;
    _popularStatus     = s;
    _friendsStatus     = s;
    notifyListeners();
  }

}