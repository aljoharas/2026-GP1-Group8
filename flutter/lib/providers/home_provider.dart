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
  List<dynamic> _friendActivities  = [];

  String _errorMessage = '';

  // ── Getters ────────────────────────────────────────────────────────────────

  HomeStatus get recommendedStatus  => _recommendedStatus;
  HomeStatus get popularStatus      => _popularStatus;
  HomeStatus get friendsStatus      => _friendsStatus;

  List<dynamic> get recommendedGames  => _recommendedGames;
  List<dynamic> get popularGames      => _popularGames;
  List<dynamic> get friendActivities  => _friendActivities;

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
      _fetchFriendActivity(),
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

  Future<void> _fetchFriendActivity() async {
    final result = await _homeService.getFriendActivity();
    if (result['success']) {
      _friendActivities = result['activities'];
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

  // نوع النشاط → نص مقروء (من جدول activity_feed في السكيما)
  static String actionLabel(Map<String, dynamic> activity) {
    final type    = activity['type'] as String? ?? '';
    final payload = activity['payload'] as Map<String, dynamic>?;
    switch (type) {
      case 'status_changed':
        final s = payload?['new_status'] as String?;
        if (s == 'completed')    return 'just completed';
        if (s == 'playing')      return 'started playing';
        if (s == 'paused')       return 'paused';
        if (s == 'plan_to_play') return 'wants to play';
        return 'updated';
      case 'game_added':          return 'added to library';
      case 'game_rated':
        final r = payload?['rating'];
        return r != null ? 'rated $r ⭐' : 'rated';
      case 'achievement_unlocked': return 'unlocked an achievement in';
      case 'list_created':         return 'created a new list';
      default:                     return 'updated';
    }
  }

  static String timeAgo(String? createdAt) {
    if (createdAt == null) return '';
    try {
      final diff = DateTime.now().difference(DateTime.parse(createdAt));
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours   < 24) return '${diff.inHours}h ago';
      if (diff.inDays    < 7)  return '${diff.inDays}d ago';
      return '${(diff.inDays / 7).floor()}w ago';
    } catch (_) { return ''; }
  }
}