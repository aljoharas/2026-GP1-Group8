import 'package:flutter/material.dart';
import '../services/friend_service.dart';

enum FriendsStatus { idle, loading, success, error }

/// Owns the three Friends tabs: the activity feed, the friends list, and
/// pending requests. Each loads independently so one failing endpoint doesn't
/// blank the whole screen.
class FriendsProvider extends ChangeNotifier {
  final FriendService _service = FriendService();

  static const _pageSize = 30;

  FriendsStatus _feedStatus = FriendsStatus.idle;
  FriendsStatus _friendsStatus = FriendsStatus.idle;
  FriendsStatus _requestsStatus = FriendsStatus.idle;

  List<Map<String, dynamic>> _feed = [];
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _incoming = [];
  List<Map<String, dynamic>> _outgoing = [];

  bool _hasMoreFeed = false;
  bool _isLoadingMore = false;
  String _errorMessage = '';

  // ── Getters ────────────────────────────────────────────────────────────────

  FriendsStatus get feedStatus => _feedStatus;
  FriendsStatus get friendsStatus => _friendsStatus;
  FriendsStatus get requestsStatus => _requestsStatus;

  List<Map<String, dynamic>> get feed => _feed;
  List<Map<String, dynamic>> get friends => _friends;
  List<Map<String, dynamic>> get incoming => _incoming;
  List<Map<String, dynamic>> get outgoing => _outgoing;

  bool get isLoadingFeed => _feedStatus == FriendsStatus.loading;
  bool get isLoadingFriends => _friendsStatus == FriendsStatus.loading;
  bool get isLoadingRequests => _requestsStatus == FriendsStatus.loading;
  bool get hasMoreFeed => _hasMoreFeed;
  bool get isLoadingMore => _isLoadingMore;

  int get friendsCount => _friends.length;
  int get pendingCount => _incoming.length;
  String get errorMessage => _errorMessage;

  // ── Loading ────────────────────────────────────────────────────────────────

  Future<void> loadAll() async {
    await Future.wait([loadFeed(), loadFriends(), loadRequests()]);
  }

  Future<void> refresh() => loadAll();

  Future<void> loadFeed() async {
    _feedStatus = FriendsStatus.loading;
    notifyListeners();

    final result = await _service.getFeed(limit: _pageSize, offset: 0);
    if (result['success'] == true) {
      _feed = List<Map<String, dynamic>>.from(result['activities']);
      _hasMoreFeed = result['hasMore'] == true;
      _feedStatus = FriendsStatus.success;
    } else {
      _errorMessage = result['message'] ?? 'Could not load the feed';
      _feedStatus = FriendsStatus.error;
    }
    notifyListeners();
  }

  /// Appends the next page. Guarded so a fast scroll can't fire two
  /// overlapping requests and duplicate rows in the list.
  Future<void> loadMoreFeed() async {
    if (_isLoadingMore || !_hasMoreFeed) return;

    _isLoadingMore = true;
    notifyListeners();

    final result = await _service.getFeed(limit: _pageSize, offset: _feed.length);
    if (result['success'] == true) {
      _feed.addAll(List<Map<String, dynamic>>.from(result['activities']));
      _hasMoreFeed = result['hasMore'] == true;
    }
    _isLoadingMore = false;
    notifyListeners();
  }

  Future<void> loadFriends() async {
    _friendsStatus = FriendsStatus.loading;
    notifyListeners();

    final result = await _service.getFriends();
    if (result['success'] == true) {
      _friends = List<Map<String, dynamic>>.from(result['friends']);
      _friendsStatus = FriendsStatus.success;
    } else {
      _friendsStatus = FriendsStatus.error;
    }
    notifyListeners();
  }

  Future<void> loadRequests() async {
    _requestsStatus = FriendsStatus.loading;
    notifyListeners();

    final result = await _service.getRequests();
    if (result['success'] == true) {
      _incoming = List<Map<String, dynamic>>.from(result['incoming']);
      _outgoing = List<Map<String, dynamic>>.from(result['outgoing']);
      _requestsStatus = FriendsStatus.success;
    } else {
      _requestsStatus = FriendsStatus.error;
    }
    notifyListeners();
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> sendRequest(String userId) async {
    final result = await _service.sendRequest(userId);
    if (result['success'] == true) await loadRequests();
    return result;
  }

  /// Accepting adds a friend and clears the request, so the feed is refetched
  /// too — their history becomes visible the moment the request is accepted.
  Future<Map<String, dynamic>> acceptRequest(int requestId) async {
    // Drop it locally first so the row disappears on tap instead of after the
    // round trip. loadRequests() below is the source of truth either way.
    _incoming.removeWhere((r) => r['id'] == requestId);
    notifyListeners();

    final result = await _service.acceptRequest(requestId);
    if (result['success'] == true) {
      await Future.wait([loadFriends(), loadRequests(), loadFeed()]);
    } else {
      await loadRequests();
    }
    return result;
  }

  Future<Map<String, dynamic>> declineRequest(int requestId) async {
    _incoming.removeWhere((r) => r['id'] == requestId);
    notifyListeners();

    final result = await _service.declineRequest(requestId);
    await loadRequests();
    return result;
  }

  Future<Map<String, dynamic>> removeFriend(String userId) async {
    final result = await _service.removeFriend(userId);
    if (result['success'] == true) {
      await Future.wait([loadFriends(), loadRequests(), loadFeed()]);
    }
    return result;
  }
}
