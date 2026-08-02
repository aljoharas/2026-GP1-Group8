import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/friends_provider.dart';
import '../../services/friend_service.dart';
import '../../services/list_service.dart';
import '../game/game_profile_screen.dart';

/// Another user's profile, opened from user search, the friends list, or a
/// feed card. Carries the Add Friend button.
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
  static const muted = Color(0xFF6B6B80);
  static const border = Color(0x12FFFFFF);

  final FriendService _service = FriendService();

  Map<String, dynamic>? _user;
  List<Map<String, dynamic>> _games = [];
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

    // Games and lists are secondary — fetch them together after the header
    // data is known to exist, so a 404 on the user skips both.
    final results = await Future.wait([
      _service.getUserGames(widget.userId),
      ListService().getPublicLists(widget.userId),
    ]);

    if (!mounted) return;
    setState(() {
      _user = profile['user'] as Map<String, dynamic>;
      _friendStatus = profile['friendStatus'] as String;
      _requestId = profile['requestId'] as int?;
      _games = results[0] as List<Map<String, dynamic>>;
      _lists = List<Map<String, dynamic>>.from(
        (results[1] as Map<String, dynamic>)['lists'] ?? [],
      );
      _isLoading = false;
    });
  }

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
            child: const Text('Remove', style: TextStyle(color: Color(0xFFE8002D))),
          ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final username = _user?['username'] as String? ?? widget.initialUsername ?? '';

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          username.isEmpty ? 'Profile' : '@$username',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: accent))
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: muted)))
              : RefreshIndicator(
                  color: accent,
                  backgroundColor: surface,
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics()),
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                    children: [
                      _buildHeader(username),
                      const SizedBox(height: 20),
                      _buildFriendButton(),
                      const SizedBox(height: 24),
                      _buildStats(),
                      const SizedBox(height: 28),
                      if (_games.isNotEmpty) ...[
                        _sectionTitle('RECENTLY PLAYED'),
                        const SizedBox(height: 12),
                        _buildGamesRow(),
                        const SizedBox(height: 28),
                      ],
                      if (_lists.isNotEmpty) ...[
                        _sectionTitle('PUBLIC LISTS'),
                        const SizedBox(height: 12),
                        ..._lists.map(_buildListCard),
                      ],
                      if (_games.isEmpty && _lists.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: Center(
                            child: Text('Nothing to show here yet',
                                style: TextStyle(color: muted, fontSize: 13)),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildHeader(String username) {
    final bio = _user?['bio'] as String?;
    final avatarUrl = _user?['avatar_url'] as String? ?? widget.initialAvatarUrl;

    return Column(children: [
      Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: surface2,
          border: Border.all(color: border, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: avatarUrl != null && avatarUrl.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: avatarUrl,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _avatarFallback(username),
              )
            : _avatarFallback(username),
      ),
      const SizedBox(height: 14),
      Text('@$username',
          style: const TextStyle(
              color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700)),
      if (bio != null && bio.trim().isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(bio,
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted, fontSize: 13, height: 1.4)),
      ],
    ]);
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

    if (_friendStatus == 'self') {
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: double.infinity,
      child: GestureDetector(
        onTap: _isBusy ? null : _onFriendButtonTapped,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: filled ? accent : surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: filled ? accent : border),
          ),
          child: _isBusy
              ? const SizedBox(
                  height: 18,
                  child: Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    ),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 17, color: filled ? bg : Colors.white),
                    const SizedBox(width: 8),
                    Text(label,
                        style: TextStyle(
                            color: filled ? bg : Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildStats() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _stat('${_user?['games_count'] ?? 0}', 'Games'),
          _divider(),
          _stat('${_user?['friends_count'] ?? 0}', 'Friends'),
          _divider(),
          _stat('${_user?['public_lists_count'] ?? 0}', 'Lists'),
        ],
      ),
    );
  }

  Widget _divider() => Container(width: 1, height: 28, color: border);

  Widget _stat(String value, String label) => Column(children: [
        Text(value,
            style: const TextStyle(
                color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Text(label, style: const TextStyle(color: muted, fontSize: 11)),
      ]);

  Widget _sectionTitle(String text) => Text(text,
      style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1));

  Widget _buildGamesRow() {
    return SizedBox(
      height: 130,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _games.length,
        itemBuilder: (_, i) {
          final game = _games[i];
          final imageUrl =
              (game['cover_image'] ?? game['background_image']) as String?;
          final name = game['name'] as String? ?? '';
          return GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GameProfileScreen(
                    rawgId: game['rawg_id'], gameName: name),
              ),
            ),
            child: Container(
              width: 90,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: surface2,
                borderRadius: BorderRadius.circular(10),
              ),
              clipBehavior: Clip.antiAlias,
              child: imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _coverFallback(name),
                    )
                  : _coverFallback(name),
            ),
          );
        },
      ),
    );
  }

  Widget _coverFallback(String name) => Center(
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Text(name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.white70,
                  height: 1.3)),
        ),
      );

  Widget _buildListCard(Map<String, dynamic> list) {
    final games = List<dynamic>.from(list['games'] ?? []);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(children: [
        Text(list['emoji'] as String? ?? '🎮', style: const TextStyle(fontSize: 22)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(list['name'] as String? ?? '',
                style: const TextStyle(
                    color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 3),
            Text('${games.length} ${games.length == 1 ? 'game' : 'games'}',
                style: const TextStyle(color: muted, fontSize: 11)),
          ]),
        ),
      ]),
    );
  }
}
