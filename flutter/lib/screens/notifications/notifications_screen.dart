import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/activity_labels.dart';
import '../../providers/friends_provider.dart';
import '../../providers/notifications_provider.dart';
import '../profile/public_profile_screen.dart';

/// Opened from the bell in the home header. Friend requests are answered here,
/// which is the path the app funnels people down after someone taps Add friend.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const bg = Color(0xFF0E0E12);
  static const surface = Color(0xFF16161E);
  static const surface2 = Color(0xFF1E1E2A);
  static const accent = Color(0xFF4ADE80);
  static const muted = Color(0xFF6B6B80);
  static const border = Color(0x12FFFFFF);

  /// Request ids currently mid-flight, so a double tap can't fire twice.
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationsProvider>().loadNotifications();
    });
  }

  Future<void> _respond(
    Map<String, dynamic> notification,
    bool accept,
  ) async {
    final friendshipId = notification['friendship_id'] as int?;
    if (friendshipId == null || _busy.contains(friendshipId)) return;

    setState(() => _busy.add(friendshipId));

    final friends = context.read<FriendsProvider>();
    final result = accept
        ? await friends.acceptRequest(friendshipId)
        : await friends.declineRequest(friendshipId);

    if (!mounted) return;

    final notifications = context.read<NotificationsProvider>();
    // Accepting leaves an "X accepted your request" trail for the other person,
    // but on this side the request row itself is spent — mark it read and
    // refetch so friendship_status reflects what just happened.
    await notifications.markRead(notification['id'] as int);
    await notifications.reloadAfterFriendAction();

    if (!mounted) return;
    setState(() => _busy.remove(friendshipId));

    if (result['success'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Something went wrong'),
          backgroundColor: surface2,
        ),
      );
    }
  }

  void _openProfile(Map<String, dynamic> notification) {
    final actorId = notification['actor_id'] as String?;
    if (actorId == null) return;

    context.read<NotificationsProvider>().markRead(notification['id'] as int);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PublicProfileScreen(
          userId: actorId,
          initialUsername: notification['actor_username'] as String?,
          initialAvatarUrl: notification['actor_avatar_url'] as String?,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notifications = context.watch<NotificationsProvider>();

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('NOTIFICATIONS',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 1.1)),
        actions: [
          if (notifications.hasUnread)
            TextButton(
              onPressed: notifications.markAllRead,
              child: const Text('Mark all read',
                  style: TextStyle(color: accent, fontSize: 12.5)),
            ),
        ],
      ),
      body: notifications.isLoading && notifications.notifications.isEmpty
          ? const Center(child: CircularProgressIndicator(color: accent))
          : notifications.notifications.isEmpty
              ? _emptyState(notifications)
              : RefreshIndicator(
                  color: accent,
                  backgroundColor: surface,
                  onRefresh: notifications.loadNotifications,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics()),
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                    itemCount: notifications.notifications.length,
                    itemBuilder: (_, i) =>
                        _buildTile(notifications.notifications[i]),
                  ),
                ),
    );
  }

  Widget _emptyState(NotificationsProvider provider) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.notifications_none, color: muted, size: 44),
            const SizedBox(height: 16),
            const Text('Nothing new',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 7),
            Text(
              provider.status == NotificationsStatus.error
                  ? provider.errorMessage
                  : "Friend requests and replies will show up here.",
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted, fontSize: 12.5, height: 1.4),
            ),
          ]),
        ),
      );

  Widget _buildTile(Map<String, dynamic> notification) {
    final type = notification['type'] as String? ?? '';
    final username = notification['actor_username'] as String? ?? 'Someone';
    final isRead = notification['is_read'] == true;
    final friendshipStatus = notification['friendship_status'] as String?;
    final friendshipId = notification['friendship_id'] as int?;

    // Only a request that is still pending gets buttons. Anything else — already
    // accepted, declined, or the friendship deleted — renders as plain history.
    final isActionable = type == 'friend_request' &&
        friendshipStatus == 'pending' &&
        friendshipId != null;

    final message = switch (type) {
      'friend_request' => isActionable
          ? 'wants to be your friend'
          : friendshipStatus == 'accepted'
              ? "is now your friend"
              : 'sent you a friend request',
      'friend_accepted' => 'accepted your friend request',
      _ => 'sent you a notification',
    };

    return Dismissible(
      key: ValueKey(notification['id']),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFE8002D).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline, color: Color(0xFFE8002D)),
      ),
      onDismissed: (_) =>
          context.read<NotificationsProvider>().delete(notification['id'] as int),
      child: GestureDetector(
        onTap: () => _openProfile(notification),
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            // Unread rows get a faint green wash so the new ones stand out
            // without needing a separate section.
            color: isRead ? surface : const Color(0xFF15211A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isRead ? border : accent.withValues(alpha: 0.25)),
          ),
          child: Column(children: [
            Row(children: [
              _avatar(username, notification['actor_avatar_url'] as String?),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(children: [
                        TextSpan(
                            text: '@$username',
                            style: const TextStyle(
                                color: accent,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                        TextSpan(
                            text: ' $message',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13, height: 1.35)),
                      ]),
                    ),
                    const SizedBox(height: 4),
                    Text(timeAgo(notification['created_at'] as String?),
                        style: const TextStyle(color: muted, fontSize: 10.5)),
                  ],
                ),
              ),
              if (!isRead && !isActionable)
                Container(
                  width: 8,
                  height: 8,
                  decoration:
                      const BoxDecoration(color: accent, shape: BoxShape.circle),
                ),
            ]),
            if (isActionable) ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: _actionButton(
                    label: 'Accept',
                    filled: true,
                    busy: _busy.contains(friendshipId),
                    onTap: () => _respond(notification, true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _actionButton(
                    label: 'Decline',
                    filled: false,
                    busy: _busy.contains(friendshipId),
                    onTap: () => _respond(notification, false),
                  ),
                ),
              ]),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _avatar(String username, String? avatarUrl) => Container(
        width: 42,
        height: 42,
        decoration: const BoxDecoration(shape: BoxShape.circle, color: surface2),
        clipBehavior: Clip.antiAlias,
        child: avatarUrl != null && avatarUrl.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: avatarUrl,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _initial(username),
              )
            : _initial(username),
      );

  Widget _initial(String username) => Center(
        child: Text(
          username.isNotEmpty ? username[0].toUpperCase() : '?',
          style: const TextStyle(
              color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
        ),
      );

  Widget _actionButton({
    required String label,
    required bool filled,
    required bool busy,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: busy ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: filled ? accent : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: filled ? accent : border),
          ),
          child: Center(
            child: busy
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: filled ? bg : muted),
                  )
                : Text(label,
                    style: TextStyle(
                        color: filled ? bg : Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
          ),
        ),
      );
}
