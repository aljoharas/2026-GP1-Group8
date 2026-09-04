import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/sticky_tab_bar.dart';
import '../../providers/friends_provider.dart';
import '../../providers/logged_games_provider.dart';
import '../../services/friend_service.dart';
import '../../services/list_service.dart';
import '../game/game_profile_screen.dart';
import 'list_detail_screen.dart';

/// Another user's profile, opened from user search, the friends list, or a
/// feed card.
///
/// Laid out to match your own profile (UserProfileScreen): the same header
/// shape, the same Overview / Journal tabs, and the same section cards. The
/// differences are only the ones that have to exist — an Add Friend button
/// where Edit Profile sits, public lists instead of all lists, and nothing
/// that edits or deletes, since none of this belongs to the viewer.
///
/// [initialUsername] and [initialAvatarUrl] are optional: the caller usually
/// already has them from the row that was tapped, so passing them lets the
/// header render immediately instead of flashing a spinner.
class PublicProfileScreen extends StatefulWidget {
  final String userId;
  final String? initialUsername;
  final String? initialAvatarUrl;

  const PublicProfileScreen({
    super.key,
    required this.userId,
    this.initialUsername,
    this.initialAvatarUrl,
  });

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  static const bg = Color(0xFF0E0E12);
  static const surface = Color(0xFF16161E);
  static const surface2 = Color(0xFF1E1E2A);
  static const accent = Color(0xFF4ADE80);
  static const gold = Color(0xFFF5C842);
  static const kText = Color(0xFFF0F0F0);
  static const muted = Color(0xFF6B6B80);
  static const border = Color(0x12FFFFFF);
  static const danger = Color(0xFFE8002D);
  // The Paused badge amber, same as on your own profile.
  static const paused = Color(0xFFFBBF24);

  final FriendService _service = FriendService();

  /// Journal cards this viewer has expanded, keyed the same way your own
  /// journal keys them: rawg id, or the name when there is no id.
  final Set<String> _expandedJournalGames = {};

  Map<String, dynamic>? _user;
  List<LoggedGame> _games = [];
  List<Map<String, dynamic>> _favorites = [];
  List<Map<String, dynamic>> _lists = [];
  String _friendStatus = 'none';
  int? _requestId;

  bool _isLoading = true;
  bool _isBusy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await _service.getUserProfile(widget.userId);

    if (!mounted) return;
    if (profile['success'] != true) {
      setState(() {
        _isLoading = false;
        _error = profile['message'] ?? 'Could not load this profile';
      });
      return;
    }

    // Games, favourites and lists are secondary — fetched together after the
    // header data is known to exist, so a 404 on the user skips all three.
    final results = await Future.wait([
      _service.getUserGames(widget.userId),
      _service.getUserFavorites(widget.userId),
      ListService().getPublicLists(widget.userId),
    ]);

    if (!mounted) return;
    setState(() {
      _user = profile['user'] as Map<String, dynamic>;
      _friendStatus = profile['friendStatus'] as String;
      _requestId = profile['requestId'] as int?;
      // The rows come back in the same shape as /users/me/games, so the same
      // model parses them and every grouping below matches your own profile.
      _games = (results[0] as List<Map<String, dynamic>>)
          .map(LoggedGame.fromJson)
          .toList();
      _favorites = results[1] as List<Map<String, dynamic>>;
      _lists = List<Map<String, dynamic>>.from(
        (results[2] as Map<String, dynamic>)['lists'] ?? [],
      );
      _isLoading = false;
    });
  }

  // ── Derived views of their library ────────────────────────────────────────
  //
  // Mirrors LoggedGamesProvider: one card per game keyed on the newest entry,
  // because an older unfinished log would otherwise keep a game in Currently
  // Playing after it was re-logged as finished.

  Map<Object, LoggedGame> get _latestByGame {
    final Map<Object, LoggedGame> latest = {};
    for (final g in _games) {
      final key = g.rawgId ?? g.name as Object;
      if (!latest.containsKey(key) ||
          g.loggedAt.isAfter(latest[key]!.loggedAt)) {
        latest[key] = g;
      }
    }
    return latest;
  }

  List<LoggedGame> get _myGames => _latestByGame.values.toList()
    ..sort((a, b) => b.loggedAt.compareTo(a.loggedAt));

  List<LoggedGame> get _currentlyPlaying => _latestByGame.values
      .where((g) => !g.isFinished && !g.isPaused)
      .toList()
    ..sort((a, b) => b.loggedAt.compareTo(a.loggedAt));

  int get _distinctGameCount => _latestByGame.length;

  // ── Friend actions ─────────────────────────────────────────────────────────

  Future<void> _onFriendButtonTapped() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);

    final friends = context.read<FriendsProvider>();
    late Map<String, dynamic> result;

    switch (_friendStatus) {
      case 'none':
        result = await friends.sendRequest(widget.userId);
        break;
      case 'pending_incoming':
        // They asked first — the button accepts instead of sending a second
        // request that the backend would reject as a duplicate.
        if (_requestId == null) return;
        result = await friends.acceptRequest(_requestId!);
        break;
      case 'pending_outgoing':
        result = await friends.removeFriend(widget.userId);
        break;
      case 'friends':
        final confirmed = await _confirmUnfriend();
        if (confirmed != true) {
          if (mounted) setState(() => _isBusy = false);
          return;
        }
        result = await friends.removeFriend(widget.userId);
        break;
      default:
        setState(() => _isBusy = false);
        return;
    }

    if (!mounted) return;
    setState(() {
      _isBusy = false;
      if (result['success'] == true) {
        _friendStatus = result['status'] as String? ?? _friendStatus;
      }
    });

    if (result['success'] != true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Something went wrong'),
          backgroundColor: surface2,
        ),
      );
    }

    // The status the button now shows came from an optimistic guess about what
    // the server did; re-reading it keeps the two in step.
    final fresh = await _service.getStatus(widget.userId);
    if (mounted) setState(() => _friendStatus = fresh);
  }

  Future<bool?> _confirmUnfriend() {
    final name = _user?['username'] ?? 'this user';
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        title: const Text('Remove friend?',
            style: TextStyle(color: Colors.white, fontSize: 17)),
        content: Text(
          "You'll stop seeing @$name's activity in your feed.",
          style: const TextStyle(color: muted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: danger)),
          ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final username =
        _user?['username'] as String? ?? widget.initialUsername ?? '';
    final topPad = MediaQuery.of(context).padding.top;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: bg,
        appBar: _plainAppBar(username),
        body: const Center(child: CircularProgressIndicator(color: accent)),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: bg,
        appBar: _plainAppBar(username),
        body: Center(
            child: Text(_error!, style: const TextStyle(color: muted))),
      );
    }

    return Scaffold(
      backgroundColor: bg,
      body: DefaultTabController(
        length: 2,
        child: RefreshIndicator(
          color: accent,
          backgroundColor: surface,
          onRefresh: _load,
          // Depth 2 is the TabBarView's inner list; without this the header's
          // own scroll would also trigger a refresh.
          notificationPredicate: (n) => n.depth == 2,
          child: NestedScrollView(
            headerSliverBuilder: (ctx, _) => [
              SliverToBoxAdapter(
                child: _buildProfileHeader(username, topPad),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: StickyTabBar(
                  TabBar(
                    indicatorColor: accent,
                    indicatorSize: TabBarIndicatorSize.label,
                    labelColor: kText,
                    unselectedLabelColor: muted,
                    labelStyle: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700),
                    unselectedLabelStyle: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500),
                    tabs: const [
                      Tab(text: 'Overview'),
                      Tab(text: 'Journal'),
                    ],
                  ),
                ),
              ),
            ],
            body: TabBarView(
              children: [
                _buildOverviewTab(username),
                _buildJournalTab(username),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Only for the loading and error states — once the profile is up, the back
  /// arrow lives in the header so the layout matches your own profile.
  PreferredSizeWidget _plainAppBar(String username) => AppBar(
        backgroundColor: bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          username.isEmpty ? 'Profile' : '@$username',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      );

  // ── Profile Header (shared above both tabs) ───────────────────────────────
  Widget _buildProfileHeader(String username, double topPad) {
    final bio = _user?['bio'] as String? ?? '';
    final avatarUrl =
        _user?['avatar_url'] as String? ?? widget.initialAvatarUrl;

    return Padding(
      padding:
          EdgeInsets.only(top: topPad, left: 18, right: 18, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          // Top bar: back arrow, where your own profile has its dots menu.
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.arrow_back_ios_new,
                      color: Colors.white70, size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Avatar row + friend button, sitting where Edit Profile sits.
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: border, width: 2),
                ),
                child: ClipOval(
                  child: avatarUrl != null && avatarUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: avatarUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: surface2,
                            child: const Icon(Icons.person_outline,
                                size: 36, color: muted),
                          ),
                          errorWidget: (_, __, ___) =>
                              _avatarFallback(username),
                        )
                      : _avatarFallback(username),
                ),
              ),
              _buildFriendButton(),
            ],
          ),
          const SizedBox(height: 12),
          Text(username,
              style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: kText,
                  letterSpacing: -0.5)),
          const SizedBox(height: 2),
          Text('@${username.toLowerCase().replaceAll(' ', '_')}',
              style: const TextStyle(fontSize: 12, color: muted)),
          if (bio.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(bio,
                style: const TextStyle(
                    color: Color(0xCCF0F0F0), fontSize: 13, height: 1.5)),
          ],
          const SizedBox(height: 16),
          _buildFriendsRow(),
          const SizedBox(height: 20),
          _buildStatsGrid(),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _avatarFallback(String username) => Container(
        color: surface2,
        child: Center(
          child: Text(
            username.isNotEmpty ? username[0].toUpperCase() : '?',
            style: const TextStyle(
                color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
          ),
        ),
      );

  Widget _buildFriendButton() {
    // Colour carries the meaning: green invites an action, grey means the ball
    // is in the other person's court or you're already connected.
    final (label, icon, filled) = switch (_friendStatus) {
      'friends' => ('Friends', Icons.check, false),
      'pending_outgoing' => ('Request sent', Icons.schedule, false),
      'pending_incoming' => ('Accept request', Icons.person_add_alt_1, true),
      'self' => ('This is you', Icons.person, false),
      _ => ('Add friend', Icons.person_add_alt_1, true),
    };

    if (_friendStatus == 'self') return const SizedBox.shrink();

    return GestureDetector(
      onTap: _isBusy ? null : _onFriendButtonTapped,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: filled ? accent : surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: filled ? accent : border),
        ),
        child: _isBusy
            ? const SizedBox(
                height: 17,
                width: 60,
                child: Center(
                  child: SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  ),
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 15, color: filled ? bg : kText),
                  const SizedBox(width: 6),
                  Text(label,
                      style: TextStyle(
                          color: filled ? bg : kText,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ],
              ),
      ),
    );
  }

  // ── Friends Row ───────────────────────────────────────────────────────────
  Widget _buildFriendsRow() {
    return Column(
      children: [
        Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_user?['friends_count'] ?? 0}',
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: kText)),
                const SizedBox(height: 2),
                const Text('Friends',
                    style: TextStyle(fontSize: 12, color: muted)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Divider(color: border, height: 1),
      ],
    );
  }

  // ── Stats ─────────────────────────────────────────────────────────────────
  Widget _buildStatsGrid() {
    final totalHours =
        _games.fold<double>(0, (sum, g) => sum + (g.hoursPlayed ?? 0));

    // Trophies are counted per game, not per entry, so replaying a game and
    // re-listing the same trophy doesn't inflate the number.
    final Map<Object, Set<String>> trophiesByGame = {};
    for (final g in _games) {
      final key = g.rawgId ?? g.name;
      trophiesByGame.putIfAbsent(key, () => {}).addAll(g.achievements);
    }
    final totalTrophies =
        trophiesByGame.values.fold<int>(0, (sum, s) => sum + s.length);

    final hoursStr = totalHours == 0
        ? '0'
        : totalHours >= 1000
            ? '${(totalHours / 1000).toStringAsFixed(1)}K'
            : totalHours % 1 == 0
                ? totalHours.toInt().toString()
                : totalHours.toStringAsFixed(1);

    return Row(
      children: [
        Expanded(child: _statCard(hoursStr, 'HOURS PLAYED')),
        const SizedBox(width: 10),
        Expanded(child: _statCard('$_distinctGameCount', 'GAMES PLAYED')),
        const SizedBox(width: 10),
        Expanded(child: _statCard('$totalTrophies', 'TROPHIES')),
      ],
    );
  }

  Widget _statCard(String val, String label) => Container(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border),
        ),
        child: Column(
          children: [
            Text(val,
                style: const TextStyle(
                    fontSize: 21, fontWeight: FontWeight.w800, color: kText)),
            const SizedBox(height: 3),
            Text(label,
                style: const TextStyle(
                    fontSize: 9, color: muted, letterSpacing: 0.4)),
          ],
        ),
      );

  // ── Overview Tab ──────────────────────────────────────────────────────────
  Widget _buildOverviewTab(String username) {
    final playing = _currentlyPlaying;
    final games = _myGames;

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 32),
      children: [
        _sectionHeader(
          'Currently Playing',
          onSeeAll: playing.isEmpty
              ? null
              : () => _openGamesGrid('Currently Playing', playing),
        ),
        if (playing.isEmpty)
          _sectionEmpty('Nothing in progress right now')
        else
          _buildCurrentlyPlayingScroll(playing),
        const SizedBox(height: 24),
        _sectionHeader(
          'Games',
          onSeeAll: games.isEmpty ? null : () => _openGamesGrid('Games', games),
        ),
        if (games.isEmpty)
          _sectionEmpty("@$username hasn't logged a game yet")
        else
          _buildGamesScroll(games),
        const SizedBox(height: 24),
        _sectionHeader('Favorite Games'),
        _buildFavoritesScroll(username),
        const SizedBox(height: 24),
        _sectionHeader('Public Lists'),
        const SizedBox(height: 8),
        if (_lists.isEmpty)
          _sectionEmpty('No public lists yet')
        else
          ..._lists.map(
            (list) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
              child: _buildListCard(list),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ── Journal Tab ───────────────────────────────────────────────────────────
  Widget _buildJournalTab(String username) {
    if (_games.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: border),
              ),
              child: const Icon(Icons.menu_book_outlined,
                  color: muted, size: 34),
            ),
            const SizedBox(height: 16),
            const Text('No entries yet',
                style: TextStyle(
                    color: kText, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text("@$username hasn't logged a game yet",
                style: const TextStyle(color: muted, fontSize: 13)),
          ],
        ),
      );
    }

    // Group by rawgId (null keys grouped by name), newest game first — the
    // same grouping your own journal uses.
    final Map<String, List<LoggedGame>> grouped = {};
    final List<String> order = [];
    for (final g in _games) {
      final key = g.rawgId?.toString() ?? g.name;
      if (!grouped.containsKey(key)) {
        grouped[key] = [];
        order.add(key);
      }
      grouped[key]!.add(g);
    }
    order.sort((a, b) {
      final aLatest = grouped[a]!
          .map((e) => e.loggedAt)
          .reduce((x, y) => x.isAfter(y) ? x : y);
      final bLatest = grouped[b]!
          .map((e) => e.loggedAt)
          .reduce((x, y) => x.isAfter(y) ? x : y);
      return bLatest.compareTo(aLatest);
    });

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 32),
      itemCount: order.length,
      itemBuilder: (ctx, i) {
        final key = order[i];
        final entries = grouped[key]!;
        final rep =
            entries.reduce((a, b) => a.loggedAt.isAfter(b.loggedAt) ? a : b);
        final isExpanded = _expandedJournalGames.contains(key);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
          child: Container(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border),
            ),
            child: Column(
              children: [
                GestureDetector(
                  onTap: () => setState(() {
                    isExpanded
                        ? _expandedJournalGames.remove(key)
                        : _expandedJournalGames.add(key);
                  }),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 44,
                            height: 58,
                            child: rep.displayImage != null
                                ? CachedNetworkImage(
                                    imageUrl: rep.displayImage!,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) =>
                                        _journalThumb(),
                                  )
                                : _journalThumb(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(rep.name,
                                  style: const TextStyle(
                                      color: kText,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 4),
                              Text(
                                '${entries.length} ${entries.length == 1 ? "entry" : "entries"}',
                                style: const TextStyle(
                                    color: muted, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        AnimatedRotation(
                          turns: isExpanded ? 0.25 : 0,
                          duration: const Duration(milliseconds: 250),
                          child: Icon(Icons.chevron_right,
                              color: isExpanded ? accent : muted),
                        ),
                      ],
                    ),
                  ),
                ),
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 250),
                  crossFadeState: isExpanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  firstChild: const SizedBox.shrink(),
                  secondChild: Column(
                    children: [
                      const Divider(color: border, height: 1),
                      ...entries.map(_buildJournalEntry),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _journalThumb() => Container(
        color: surface2,
        child: const Icon(Icons.sports_esports, color: muted, size: 20),
      );

  /// Same entry row as your own journal, minus the tap-to-remove on trophies —
  /// these are someone else's.
  Widget _buildJournalEntry(LoggedGame entry) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final d = entry.loggedAt;
    final dateStr = '${months[d.month - 1]} ${d.day}, ${d.year}';

    return GestureDetector(
      onTap: () => _openGame(entry.rawgId, entry.name),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: border))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.calendar_today_outlined,
                    color: muted, size: 12),
                const SizedBox(width: 4),
                Text(dateStr,
                    style: const TextStyle(color: muted, fontSize: 11)),
                if (entry.hoursPlayed != null) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.access_time, color: muted, size: 12),
                  const SizedBox(width: 4),
                  Text(
                    '${entry.hoursPlayed!.toStringAsFixed(entry.hoursPlayed! % 1 == 0 ? 0 : 1)} hrs',
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                ],
                if (entry.achievements.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.military_tech_outlined,
                      color: muted, size: 12),
                  const SizedBox(width: 4),
                  Text('${entry.achievements.length}',
                      style: const TextStyle(color: muted, fontSize: 11)),
                ],
                if (entry.platform != null) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.videogame_asset_outlined,
                      color: muted, size: 12),
                  const SizedBox(width: 4),
                  Text(entry.platform!,
                      style: const TextStyle(color: muted, fontSize: 11)),
                ],
              ],
            ),
            if (entry.comment != null && entry.comment!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(entry.comment!,
                  style: const TextStyle(
                      color: Color(0xCCF0F0F0), fontSize: 12, height: 1.4),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis),
            ],
            if (entry.achievements.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: entry.achievements
                    .map((a) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: gold.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border:
                                Border.all(color: gold.withValues(alpha: 0.3)),
                          ),
                          child: Text(a,
                              style: const TextStyle(
                                  color: gold,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Shared pieces ─────────────────────────────────────────────────────────

  void _openGame(int? rawgId, String name) {
    if (rawgId == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GameProfileScreen(rawgId: rawgId, gameName: name),
      ),
    );
  }

  void _openGamesGrid(String title, List<LoggedGame> games) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PublicGamesGridScreen(title: title, games: games),
      ),
    );
  }

  Widget _sectionHeader(String title, {VoidCallback? onSeeAll}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700, color: kText)),
            const Spacer(),
            if (onSeeAll != null)
              GestureDetector(
                onTap: onSeeAll,
                behavior: HitTestBehavior.opaque,
                child: const Text('See All',
                    style: TextStyle(fontSize: 13, color: muted)),
              ),
          ],
        ),
      );

  Widget _sectionEmpty(String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Text(text, style: const TextStyle(color: muted, fontSize: 13)),
      );

  Widget _buildCurrentlyPlayingScroll(List<LoggedGame> games) => SizedBox(
        height: 130,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(left: 18, top: 12),
          itemCount: games.length,
          itemBuilder: (_, i) {
            final g = games[i];
            return GestureDetector(
              onTap: () => _openGame(g.rawgId, g.name),
              child: Container(
                width: 90,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10), color: surface2),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: _cover(g),
                ),
              ),
            );
          },
        ),
      );

  /// The Games row carries the Paused badge below the poster, exactly as your
  /// own My Games row does — which is why it is 25px taller than the one above.
  Widget _buildGamesScroll(List<LoggedGame> games) => SizedBox(
        height: 155,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(left: 18, top: 12),
          itemCount: games.length,
          itemBuilder: (_, i) {
            final g = games[i];
            return GestureDetector(
              onTap: () => _openGame(g.rawgId, g.name),
              child: SizedBox(
                width: 90,
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 90,
                          height: 120,
                          child: ColoredBox(color: surface2, child: _cover(g)),
                        ),
                      ),
                      SizedBox(
                        height: 22,
                        child: g.isPaused ? _pausedBadge() : null,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );

  Widget _pausedBadge() => Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: paused.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: paused.withValues(alpha: 0.4)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.pause, color: paused, size: 9),
              SizedBox(width: 3),
              Text('Paused',
                  style: TextStyle(
                      color: paused,
                      fontSize: 9,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      );

  Widget _cover(LoggedGame g) => g.displayImage != null
      ? CachedNetworkImage(
          imageUrl: g.displayImage!,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorWidget: (_, __, ___) => _coverPlaceholder(g.name),
        )
      : _coverPlaceholder(g.name);

  Widget _buildFavoritesScroll(String username) {
    if (_favorites.isEmpty) {
      return _sectionEmpty("@$username hasn't hearted a game yet");
    }
    return SizedBox(
      height: 130,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(left: 18, top: 12),
        itemCount: _favorites.length,
        itemBuilder: (_, i) {
          final g = _favorites[i];
          final name = g['name'] as String? ?? '';
          final imageUrl =
              (g['cover_image'] ?? g['background_image']) as String?;
          final rawgId = g['rawg_id'];
          return GestureDetector(
            onTap: () => _openGame(
              rawgId is int ? rawgId : int.tryParse(rawgId?.toString() ?? ''),
              name,
            ),
            child: Container(
              width: 90,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: surface2,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _coverPlaceholder(name),
                      )
                    : _coverPlaceholder(name),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _coverPlaceholder(String name) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [surface2, surface],
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Text(name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: kText,
                    letterSpacing: 0.3,
                    height: 1.3),
                maxLines: 3,
                overflow: TextOverflow.ellipsis),
          ),
        ),
      );

  // ── List Card ─────────────────────────────────────────────────────────────
  //
  // Same card as your own lists, minus the edit/delete menu. Tapping opens the
  // list read-only; its games came down with the list, so there is nothing
  // further to fetch.
  Widget _buildListCard(Map<String, dynamic> list) {
    final games = List<Map<String, dynamic>>.from(list['games'] ?? []);
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ListDetailScreen(list: list, canEdit: false),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Text(list['emoji'] as String? ?? '🎮',
                style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(list['name'] as String? ?? '',
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: kText),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.public, size: 13, color: muted),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(games.length == 1 ? '1 game' : '${games.length} games',
                      style: const TextStyle(fontSize: 12, color: muted)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: muted),
          ],
        ),
      ),
    );
  }
}

/// "See All" for one of the public profile's game rows: the same 3-up cover
/// grid your own See All screens use, without the delete affordances.
class _PublicGamesGridScreen extends StatelessWidget {
  final String title;
  final List<LoggedGame> games;

  const _PublicGamesGridScreen({required this.title, required this.games});

  static const bg = Color(0xFF0E0E12);
  static const surface = Color(0xFF16161E);
  static const surface2 = Color(0xFF1E1E2A);
  static const kText = Color(0xFFF0F0F0);
  static const muted = Color(0xFF6B6B80);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(title,
            style: const TextStyle(
                color: kText, fontSize: 17, fontWeight: FontWeight.w700)),
        centerTitle: true,
      ),
      body: games.isEmpty
          ? const Center(
              child: Text('No games yet',
                  style: TextStyle(color: muted, fontSize: 14)))
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.65,
              ),
              itemCount: games.length,
              itemBuilder: (_, i) {
                final g = games[i];
                return GestureDetector(
                  onTap: g.rawgId == null
                      ? null
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => GameProfileScreen(
                                  rawgId: g.rawgId!, gameName: g.name),
                            ),
                          ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: ColoredBox(
                      color: surface2,
                      child: g.displayImage != null
                          ? CachedNetworkImage(
                              imageUrl: g.displayImage!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                              errorWidget: (_, __, ___) => _placeholder(g.name),
                            )
                          : _placeholder(g.name),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _placeholder(String name) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [surface2, surface],
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Text(name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: kText,
                    height: 1.3),
                maxLines: 4,
                overflow: TextOverflow.ellipsis),
          ),
        ),
      );
}
