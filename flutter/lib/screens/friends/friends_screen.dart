import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/activity_labels.dart';
import '../../core/nav_painters.dart';
import '../../providers/friends_provider.dart';
import '../game/game_profile_screen.dart';
import '../game/game_search_screen.dart';
import '../home/home_screen.dart';
import '../logGames/log_game_search_screen.dart';
import '../profile/public_profile_screen.dart';
import '../profile/user_profile_screen.dart';

/// The social hub: what friends have been doing, who your friends are, and
/// requests waiting on you. Reached from the Friends icon in the bottom nav.
class FriendsScreen extends StatefulWidget {
  /// Which tab to land on. The notifications screen deep-links to Requests.
  final int initialTab;

  const FriendsScreen({super.key, this.initialTab = 0});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen>
    with SingleTickerProviderStateMixin {
  static const bg = Color(0xFF0E0E12);
  static const surface = Color(0xFF16161E);
  static const surface2 = Color(0xFF1E1E2A);
  static const accent = Color(0xFF4ADE80);
  static const muted = Color(0xFF6B6B80);
  static const border = Color(0x12FFFFFF);

  late final TabController _tabs;
  final ScrollController _feedScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this, initialIndex: widget.initialTab);
    _feedScroll.addListener(_onFeedScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FriendsProvider>().loadAll();
    });
  }

  @override
  void dispose() {
    _feedScroll.removeListener(_onFeedScroll);
    _feedScroll.dispose();
    _tabs.dispose();
    super.dispose();
  }

  // Pull the next page once the user is within a screen's height of the end,
  // so the list keeps growing instead of hitting a visible stop.
  void _onFeedScroll() {
    if (!_feedScroll.hasClients) return;
    final remaining =
        _feedScroll.position.maxScrollExtent - _feedScroll.position.pixels;
    if (remaining < MediaQuery.of(context).size.height) {
      context.read<FriendsProvider>().loadMoreFeed();
    }
  }

  void _openProfile(String? userId, String? username, String? avatarUrl) {
    if (userId == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PublicProfileScreen(
          userId: userId,
          initialUsername: username,
          initialAvatarUrl: avatarUrl,
        ),
      ),
    ).then((_) {
      if (mounted) context.read<FriendsProvider>().loadAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final friends = context.watch<FriendsProvider>();

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('FRIENDS',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 1.1)),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_search_outlined, color: Colors.white),
            tooltip: 'Find people',
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                  builder: (_) => const GameSearchScreen(initialTab: 1)),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: TabBar(
            controller: _tabs,
            indicatorColor: accent,
            indicatorWeight: 2.5,
            labelColor: Colors.white,
            unselectedLabelColor: muted,
            labelStyle:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            tabs: [
              const Tab(text: 'Feed'),
              Tab(text: 'Friends (${friends.friendsCount})'),
              Tab(child: _requestsTabLabel(friends.pendingCount)),
            ],
          ),
        ),
      ),
      body: Stack(children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 76),
          child: TabBarView(
            controller: _tabs,
            children: [
              _buildFeedTab(friends),
              _buildFriendsTab(friends),
              _buildRequestsTab(friends),
            ],
          ),
        ),
        Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomNav()),
      ]),
    );
  }

  // A count badge only earns its space when something is actually waiting.
  Widget _requestsTabLabel(int pending) {
    if (pending == 0) return const Text('Requests');
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Text('Requests'),
      const SizedBox(width: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFE8002D),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text('$pending',
            style: const TextStyle(
                color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
      ),
    ]);
  }

  // ── Feed tab ───────────────────────────────────────────────────────────────

  Widget _buildFeedTab(FriendsProvider friends) {
    if (friends.isLoadingFeed && friends.feed.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: accent));
    }
    if (friends.feed.isEmpty) {
      return _emptyState(
        icon: Icons.people_outline,
        title: 'Your feed is quiet',
        subtitle: friends.friendsCount == 0
            ? 'Add friends to see the games they log, rate, and review.'
            : "Nothing new from your friends yet.",
        actionLabel: friends.friendsCount == 0 ? 'Find people' : null,
        onAction: () => Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const GameSearchScreen(initialTab: 1)),
        ),
      );
    }

    return RefreshIndicator(
      color: accent,
      backgroundColor: surface,
      onRefresh: friends.loadFeed,
      child: ListView.builder(
        controller: _feedScroll,
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        // One extra slot at the end holds the "loading more" spinner.
        itemCount: friends.feed.length + (friends.isLoadingMore ? 1 : 0),
        itemBuilder: (_, i) {
          if (i >= friends.feed.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator(color: accent)),
            );
          }
          return _buildActivityCard(friends.feed[i]);
        },
      ),
    );
  }

  Widget _buildActivityCard(Map<String, dynamic> activity) {
    final line = describeActivity(activity);
    final username = activity['username'] as String? ?? '';
    final coverImage = activity['cover_image'] as String?;
    final rawgId = activity['rawg_id'];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Cover art when the activity is about a game, the type's emoji when
        // it's about a list.
        GestureDetector(
          onTap: rawgId == null
              ? null
              : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GameProfileScreen(
                          rawgId: rawgId, gameName: line.subject ?? ''),
                    ),
                  ),
          child: Container(
            width: 52,
            height: 70,
            decoration: BoxDecoration(
              color: surface2,
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: coverImage != null
                ? CachedNetworkImage(
                    imageUrl: coverImage,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _emojiTile(line.emoji),
                  )
                : _emojiTile(line.emoji),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GestureDetector(
              onTap: () => _openProfile(
                activity['user_id'] as String?,
                username,
                activity['avatar_url'] as String?,
              ),
              child: Row(children: [
                _avatar(username, activity['avatar_url'] as String?, 20),
                const SizedBox(width: 7),
                Flexible(
                  child: Text('@$username',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 6),
                Text(timeAgo(activity['created_at'] as String?),
                    style: const TextStyle(color: muted, fontSize: 10)),
              ]),
            ),
            const SizedBox(height: 7),
            RichText(
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(children: [
                TextSpan(
                    text: line.verb,
                    style: const TextStyle(color: muted, fontSize: 12.5)),
                if (line.subject != null)
                  TextSpan(
                      text: ' ${line.subject}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700)),
              ]),
            ),
            if (line.rating != null) ...[
              const SizedBox(height: 5),
              Row(
                children: List.generate(
                  5,
                  (i) => Icon(
                    i < line.rating! ? Icons.star : Icons.star_border,
                    size: 13,
                    color: i < line.rating! ? const Color(0xFFFBBF24) : muted,
                  ),
                ),
              ),
            ],
            if (line.detail != null) ...[
              const SizedBox(height: 5),
              Text(line.detail!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: muted, fontSize: 11.5, height: 1.35)),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _emojiTile(String emoji) => Center(
      child: Text(emoji, style: const TextStyle(fontSize: 22)));

  // ── Friends tab ────────────────────────────────────────────────────────────

  Widget _buildFriendsTab(FriendsProvider friends) {
    if (friends.isLoadingFriends && friends.friends.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: accent));
    }
    if (friends.friends.isEmpty) {
      return _emptyState(
        icon: Icons.person_add_alt_1_outlined,
        title: 'No friends yet',
        subtitle: 'Search for someone by username to send them a request.',
        actionLabel: 'Find people',
        onAction: () => Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const GameSearchScreen(initialTab: 1)),
        ),
      );
    }

    return RefreshIndicator(
      color: accent,
      backgroundColor: surface,
      onRefresh: friends.loadFriends,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        itemCount: friends.friends.length,
        itemBuilder: (_, i) {
          final friend = friends.friends[i];
          return _userTile(
            user: friend,
            trailing: const Icon(Icons.chevron_right, color: muted, size: 20),
            onTap: () => _openProfile(
              friend['id'] as String?,
              friend['username'] as String?,
              friend['avatar_url'] as String?,
            ),
          );
        },
      ),
    );
  }

  // ── Requests tab ───────────────────────────────────────────────────────────

  Widget _buildRequestsTab(FriendsProvider friends) {
    if (friends.isLoadingRequests &&
        friends.incoming.isEmpty &&
        friends.outgoing.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: accent));
    }
    if (friends.incoming.isEmpty && friends.outgoing.isEmpty) {
      return _emptyState(
        icon: Icons.mark_email_read_outlined,
        title: 'No pending requests',
        subtitle: "Requests you send and receive will show up here.",
      );
    }

    return RefreshIndicator(
      color: accent,
      backgroundColor: surface,
      onRefresh: friends.loadRequests,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        children: [
          if (friends.incoming.isNotEmpty) ...[
            _sectionLabel('WAITING ON YOU'),
            const SizedBox(height: 10),
            ...friends.incoming.map((r) => _userTile(
                  user: r,
                  onTap: () => _openProfile(r['user_id'] as String?,
                      r['username'] as String?, r['avatar_url'] as String?),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    _smallButton(
                      label: 'Accept',
                      filled: true,
                      onTap: () => friends.acceptRequest(r['id'] as int),
                    ),
                    const SizedBox(width: 8),
                    _smallButton(
                      label: 'Decline',
                      filled: false,
                      onTap: () => friends.declineRequest(r['id'] as int),
                    ),
                  ]),
                )),
            const SizedBox(height: 22),
          ],
          if (friends.outgoing.isNotEmpty) ...[
            _sectionLabel('SENT'),
            const SizedBox(height: 10),
            ...friends.outgoing.map((r) => _userTile(
                  user: r,
                  onTap: () => _openProfile(r['user_id'] as String?,
                      r['username'] as String?, r['avatar_url'] as String?),
                  trailing: _smallButton(
                    label: 'Cancel',
                    filled: false,
                    onTap: () => friends.removeFriend(r['user_id'] as String),
                  ),
                )),
          ],
        ],
      ),
    );
  }

  // ── Shared pieces ──────────────────────────────────────────────────────────

  Widget _sectionLabel(String text) => Text(text,
      style: const TextStyle(
          color: muted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1));

  /// One row for a person: avatar, @username, bio, plus whatever action the
  /// calling tab needs on the right.
  Widget _userTile({
    required Map<String, dynamic> user,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    final username = user['username'] as String? ?? '';
    final bio = (user['bio'] as String?)?.trim();

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: Row(children: [
          _avatar(username, user['avatar_url'] as String?, 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('@$username',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700)),
                if (bio != null && bio.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(bio,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: muted, fontSize: 11.5)),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing],
        ]),
      ),
    );
  }

  Widget _avatar(String username, String? avatarUrl, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: surface2,
        ),
        clipBehavior: Clip.antiAlias,
        child: avatarUrl != null && avatarUrl.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: avatarUrl,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _initial(username, size),
              )
            : _initial(username, size),
      );

  Widget _initial(String username, double size) => Center(
        child: Text(
          username.isNotEmpty ? username[0].toUpperCase() : '?',
          style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.4,
              fontWeight: FontWeight.bold),
        ),
      );

  Widget _smallButton({
    required String label,
    required bool filled,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: filled ? accent : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: filled ? accent : border),
          ),
          child: Text(label,
              style: TextStyle(
                  color: filled ? bg : muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ),
      );

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: muted, size: 44),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 7),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: muted, fontSize: 12.5, height: 1.4)),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              GestureDetector(
                onTap: onAction,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(actionLabel,
                      style: const TextStyle(
                          color: bg, fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ]),
        ),
      );

  // ── Bottom Nav ─────────────────────────────────────────────────────────────

  Widget _buildBottomNav() {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.only(top: 12, bottom: bottomPad > 0 ? bottomPad : 14),
      decoration: const BoxDecoration(
        color: Color(0xF70E0E12),
        border: Border(top: BorderSide(color: border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _navBtn(
            child: CustomPaint(size: const Size(22, 22), painter: NavHomePainter(false)),
            onTap: () => Navigator.pushReplacement(context,
                MaterialPageRoute(builder: (_) => const HomeScreen())),
          ),
          _navBtn(
            child: CustomPaint(size: const Size(22, 22), painter: NavSearchPainter(false)),
            onTap: () => Navigator.pushReplacement(context,
                MaterialPageRoute(builder: (_) => const GameSearchScreen())),
          ),
          GestureDetector(
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const LogGameSearchScreen())),
            child: Container(
              width: 46,
              height: 46,
              margin: const EdgeInsets.only(bottom: 4),
              decoration:
                  const BoxDecoration(color: Color(0xFFE8002D), shape: BoxShape.circle),
              child: CustomPaint(painter: NavPlusPainter()),
            ),
          ),
          _navBtn(
            child: CustomPaint(size: const Size(22, 22), painter: NavFriendsPainter(true)),
            onTap: () {},
          ),
          _navBtn(
            child: CustomPaint(size: const Size(22, 22), painter: NavProfilePainter(false)),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const UserProfileScreen())),
          ),
        ],
      ),
    );
  }

  Widget _navBtn({required Widget child, required VoidCallback onTap}) =>
      GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: child),
      );
}
