import 'package:flutter/material.dart';
import '../services/notification_service.dart';

enum NotificationsStatus { idle, loading, success, error }

/// Backs the bell in the home header and the notifications screen.
///
/// The unread count is kept separate from the list so the home screen can show
/// the dot without paying for the full list on every load.
class NotificationsProvider extends ChangeNotifier {
  final NotificationService _service = NotificationService();

  NotificationsStatus _status = NotificationsStatus.idle;
  List<Map<String, dynamic>> _notifications = [];
  int _unreadCount = 0;
  String _errorMessage = '';

  NotificationsStatus get status => _status;
  List<Map<String, dynamic>> get notifications => _notifications;
  int get unreadCount => _unreadCount;
  bool get hasUnread => _unreadCount > 0;
  bool get isLoading => _status == NotificationsStatus.loading;
  String get errorMessage => _errorMessage;

  Future<void> loadNotifications() async {
    _status = NotificationsStatus.loading;
    notifyListeners();

    final result = await _service.getNotifications();
    if (result['success'] == true) {
      _notifications = List<Map<String, dynamic>>.from(result['notifications']);
      _unreadCount = _notifications.where((n) => n['is_read'] != true).length;
      _status = NotificationsStatus.success;
    } else {
      _errorMessage = result['message'] ?? 'Could not load notifications';
      _status = NotificationsStatus.error;
    }
    notifyListeners();
  }

  /// Cheap enough to call on every home screen load — it's a COUNT on an index.
  Future<void> refreshUnreadCount() async {
    _unreadCount = await _service.getUnreadCount();
    notifyListeners();
  }

  Future<void> markRead(int id) async {
    final index = _notifications.indexWhere((n) => n['id'] == id);
    if (index == -1 || _notifications[index]['is_read'] == true) return;

    _notifications[index] = {..._notifications[index], 'is_read': true};
    if (_unreadCount > 0) _unreadCount--;
    notifyListeners();

    // A failed write only means the dot comes back on next load, which is
    // better than blocking the tap on a round trip.
    await _service.markRead(id);
  }

  Future<void> markAllRead() async {
    _notifications = [
      for (final n in _notifications) {...n, 'is_read': true},
    ];
    _unreadCount = 0;
    notifyListeners();

    await _service.markAllRead();
  }

  Future<void> delete(int id) async {
    final removed = _notifications.firstWhere(
      (n) => n['id'] == id,
      orElse: () => const {},
    );
    _notifications.removeWhere((n) => n['id'] == id);
    if (removed['is_read'] != true && _unreadCount > 0) _unreadCount--;
    notifyListeners();

    await _service.deleteNotification(id);
  }

  /// Called after accepting or declining from the notifications screen: the
  /// friendship row changed, so friendship_status on these rows is now stale.
  Future<void> reloadAfterFriendAction() => loadNotifications();
}
