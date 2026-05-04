import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/home_provider.dart';
import '../../screens/game/game_profile_screen.dart';  
import '../../screens/game/game_search_screen.dart';
import '../logGames/log_game_search_screen.dart';
import '../profile/user_profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const bg       = Color(0xFF0E0E12);
  static const surface  = Color(0xFF16161E);
  static const surface2 = Color(0xFF1E1E2A);
  static const accent   = Color(0xFF4ADE80);
  static const muted    = Color(0xFF6B6B80);
  static const border   = Color(0x12FFFFFF);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HomeProvider>().loadHomeData();
    });
  }

  void _showAllGames(String title, List<dynamic> games) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _GameGridScreen(title: title, games: games),
      ),
    );
  }

  void _sprint2(String label) {
    showModalBottomSheet(
      context: context,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: muted.withOpacity(0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Text('🚧', style: TextStyle(fontSize: 36)),
          const SizedBox(height: 12),
          Text('$label coming in GP2!',
              style: const TextStyle(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('This feature is on its way.',
              style: TextStyle(color: muted, fontSize: 13)),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth     = context.watch<AuthProvider>();
    final home     = context.watch<HomeProvider>();
    final username = auth.currentUser?['username'] as String? ?? 'Gamer';

    return Scaffold(
      backgroundColor: bg,
      body: Stack(children: [
        RefreshIndicator(
          color: accent,
          backgroundColor: surface,
          onRefresh: () => context.read<HomeProvider>().refresh(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics()),
            slivers: [
              SliverToBoxAdapter(child: SizedBox(height: MediaQuery.of(context).padding.top + 16)),
              SliverToBoxAdapter(child: _buildHeader(username)),
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
              SliverToBoxAdapter(
                  child: _buildSectionHeader('RECOMMENDED',
                      onSeeAll: () => _showAllGames('RECOMMENDED', home.recommendedGames))),
              const SliverToBoxAdapter(child: SizedBox(height: 14)),
              SliverToBoxAdapter(child: _buildRecommendedRow(home)),
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
              SliverToBoxAdapter(
                  child: _buildSectionHeader('POPULAR NOW',
                      onSeeAll: () => _showAllGames('POPULAR NOW', home.popularGames))),
              const SliverToBoxAdapter(child: SizedBox(height: 14)),
              SliverToBoxAdapter(child: _buildPopularRow(home)),
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
              SliverToBoxAdapter(
                  child: _buildSectionHeader('NEW FROM FRIENDS',
                      onSeeAll: () => _sprint2('See All'))),
              const SliverToBoxAdapter(child: SizedBox(height: 14)),
              SliverToBoxAdapter(child: _buildFriendsRow(home)),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
        Positioned(
            bottom: 0, left: 0, right: 0, child: _buildBottomNav()),
      ]),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader(String username) {
    final hour     = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning,' : hour < 18 ? 'Good afternoon,' : 'Good evening,';

    return Padding(
      padding: const EdgeInsets.only(left: 10, right: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Image.asset(
              'assets/images/loadout_logo.png',
              height: 38,
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
            ),
            const SizedBox(height: 10),
            Text(greeting, style: const TextStyle(color: muted, fontSize: 13)),
            const SizedBox(height: 2),
            Row(children: [
              Text(username,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              const Text('👾', style: TextStyle(fontSize: 16)),
            ]),
          ]),
          GestureDetector(
            onTap: () => _sprint2('Notifications'),
            child: Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: border),
              ),
              child: Stack(children: [
                const Center(child: Icon(Icons.notifications_outlined,
                    color: Colors.white, size: 20)),
                Positioned(
                  right: 10, top: 10,
                  child: Container(
                    width: 7, height: 7,
                    decoration: const BoxDecoration(
                        color: accent, shape: BoxShape.circle),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section Header ─────────────────────────────────────────────────────────

  Widget _buildSectionHeader(String title, {required VoidCallback onSeeAll}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1)),
          GestureDetector(
            onTap: onSeeAll,
            child: Row(children: const [
              Text('See all',
                  style: TextStyle(
                      color: muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w500)),
              SizedBox(width: 2),
              Icon(Icons.chevron_right, color: muted, size: 15),
            ]),
          ),
        ],
      ),
    );
  }

  // ── Recommended ────────────────────────────────────────────────────────────

  Widget _buildRecommendedRow(HomeProvider home) {
    if (home.isLoadingRecommended) {
      return const SizedBox(height: 130,
          child: Center(child: CircularProgressIndicator(color: accent)));
    }
    if (home.recommendedGames.isEmpty) {
      return const SizedBox(height: 80,
          child: Center(child: Text('No recommendations yet',
              style: TextStyle(color: muted, fontSize: 13))));
    }
    return SizedBox(
      height: 130,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(left: 20),
        itemCount: home.recommendedGames.length,
        itemBuilder: (_, i) => _buildGameCard(
            home.recommendedGames[i] as Map<String, dynamic>),
      ),
    );
  }

  // ── Popular ────────────────────────────────────────────────────────────────

  Widget _buildPopularRow(HomeProvider home) {
    if (home.isLoadingPopular) {
      return const SizedBox(height: 130,
          child: Center(child: CircularProgressIndicator(color: accent)));
    }
    if (home.popularGames.isEmpty) {
      return const SizedBox(height: 80,
          child: Center(child: Text('Nothing trending right now',
              style: TextStyle(color: muted, fontSize: 13))));
    }
    return SizedBox(
      height: 130,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(left: 20),
        itemCount: home.popularGames.length,
        itemBuilder: (_, i) => _buildGameCard(
            home.popularGames[i] as Map<String, dynamic>),
      ),
    );
  }

  Widget _buildGameCard(Map<String, dynamic> game) {
    final imageUrl = (game['cover_image'] ?? game['background_image']) as String?;
    final name = game['name'] as String? ?? '';
    return GestureDetector(
      onTap: () {
        final rawgId = game['rawg_id'] ?? game['id'];
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => GameProfileScreen(rawgId: rawgId, gameName: name),
        ));
      },
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
  }

  Widget _coverPlaceholder(String name) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [surface2, Color(0xFF0E0E12)],
        ),
      ),
      child: Center(
        child: Text(
          name,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: Colors.white70,
            letterSpacing: 0.3,
            height: 1.3,
          ),
        ),
      ),
    );
  }

  // ── Friends ────────────────────────────────────────────────────────────────

  Widget _buildFriendsRow(HomeProvider home) {
    if (home.isLoadingFriends) {
      return const SizedBox(height: 105,
          child: Center(child: CircularProgressIndicator(color: accent)));
    }
    if (home.friendActivities.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: surface, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          child: const Row(children: [
            Icon(Icons.people_outline, color: muted, size: 22),
            SizedBox(width: 12),
            Expanded(child: Text("Add friends to see what they're playing",
                style: TextStyle(color: muted, fontSize: 12))),
          ]),
        ),
      );
    }
    return SizedBox(
      height: 105,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: home.friendActivities.length,
        itemBuilder: (_, i) => _buildFriendCard(
            home.friendActivities[i] as Map<String, dynamic>, i),
      ),
    );
  }

  Widget _buildFriendCard(Map<String, dynamic> activity, int index) {
    final avatarColors = [
      const Color(0xFFE53935), const Color(0xFFFF8F00),
      const Color(0xFF1E88E5), const Color(0xFF43A047),
      const Color(0xFF8E24AA), const Color(0xFF00ACC1),
    ];
    final color    = avatarColors[index % avatarColors.length];
    final username = activity['username'] as String? ?? '';
    final gameName = activity['game_name'] as String?;
    final imageUrl = activity['cover_image'] as String?;
    final action   = HomeProvider.actionLabel(activity);
    final time     = HomeProvider.timeAgo(activity['created_at'] as String?);

    return Container(
      width: 195,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surface, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(10)),
          child: imageUrl != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                      imageUrl: imageUrl, fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _avatarFallback(username, color)),
                )
              : _avatarFallback(username, color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('@$username',
                  style: const TextStyle(color: accent, fontSize: 11,
                      fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(action, style: const TextStyle(color: muted, fontSize: 10)),
              if (gameName != null) ...[
                const SizedBox(height: 1),
                Text(gameName,
                    style: const TextStyle(color: Colors.white,
                        fontSize: 11, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 3),
              Text(time, style: const TextStyle(color: muted, fontSize: 9)),
            ],
          ),
        ),
      ]),
    );
  }

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
            child: CustomPaint(size: const Size(22, 22), painter: _HomePainter(true)),
            onTap: () {},
          ),
          _navBtn(
            child: CustomPaint(size: const Size(22, 22), painter: _SearchPainter(false)),
            onTap: () => Navigator.pushReplacement(context,
                MaterialPageRoute(builder: (_) => const GameSearchScreen())),
          ),
          GestureDetector(
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const LogGameSearchScreen())),
            child: Container(
              width: 46, height: 46,
              margin: const EdgeInsets.only(bottom: 4),
              decoration: const BoxDecoration(
                  color: Color(0xFFE8002D), shape: BoxShape.circle),
              child: CustomPaint(painter: _PlusPainter()),
            ),
          ),
          _navBtn(
            child: CustomPaint(size: const Size(22, 22), painter: _FriendsPainter(false)),
            onTap: () => _sprint2('Friends'),
          ),
          _navBtn(
            child: CustomPaint(size: const Size(22, 22), painter: _ProfilePainter(false)),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const UserProfileScreen())),
          ),
        ],
      ),
    );
  }

  Widget _navBtn({required Widget child, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: child),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _avatarFallback(String username, Color color) {
    return Container(
      color: color,
      child: Center(
        child: Text(
          username.isNotEmpty ? username[0].toUpperCase() : '?',
          style: const TextStyle(color: Colors.white,
              fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

}

// ── See All Grid Screen ───────────────────────────────────────────────────────

class _GameGridScreen extends StatelessWidget {
  final String title;
  final List<dynamic> games;

  const _GameGridScreen({required this.title, required this.games});

  static const bg       = Color(0xFF0E0E12);
  static const surface2 = Color(0xFF1E1E2A);
  static const muted    = Color(0xFF6B6B80);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: Colors.white,
        title: Text(title,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 1.1)),
        centerTitle: false,
        elevation: 0,
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 90 / 155,
        ),
        itemCount: games.length,
        itemBuilder: (_, i) {
          final game = games[i] as Map<String, dynamic>;
          final imageUrl = (game['cover_image'] ?? game['background_image']) as String?;
          final name = game['name'] as String? ?? '';
          final rawgId = game['rawg_id'] ?? game['id'];
          return GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => GameProfileScreen(rawgId: rawgId, gameName: name),
            )),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: double.infinity,
                      color: surface2,
                      child: imageUrl != null
                          ? CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => _placeholder(name),
                            )
                          : _placeholder(name),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _placeholder(String name) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [surface2, bg],
        ),
      ),
      child: Center(
        child: Text(name,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 10, fontWeight: FontWeight.w800,
                color: Colors.white70, letterSpacing: 0.3, height: 1.3)),
      ),
    );
  }
}

// ── Nav Painters ─────────────────────────

const _kText  = Color(0xFFF0F0F0);
const _kMuted = Color(0xFF6B6B80);

Paint _navPaint(bool active) => Paint()
  ..color = active ? _kText : _kMuted
  ..strokeWidth = 2.0
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..style = PaintingStyle.stroke;

class _HomePainter extends CustomPainter {
  final bool active;
  const _HomePainter(this.active);
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final path = Path()
      ..moveTo(3*s,9*s)  ..lineTo(12*s,2*s) ..lineTo(21*s,9*s)
      ..lineTo(21*s,20*s)
      ..arcToPoint(Offset(19*s,22*s), radius: Radius.circular(2*s))
      ..lineTo(5*s,22*s)
      ..arcToPoint(Offset(3*s,20*s), radius: Radius.circular(2*s))
      ..close();
    canvas.drawPath(path, _navPaint(active));
  }
  @override bool shouldRepaint(_HomePainter o) => o.active != active;
}

class _SearchPainter extends CustomPainter {
  final bool active;
  const _SearchPainter(this.active);
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final p = _navPaint(active);
    canvas.drawCircle(Offset(11*s,11*s), 8*s, p);
    canvas.drawLine(Offset(16.65*s,16.65*s), Offset(21*s,21*s), p);
  }
  @override bool shouldRepaint(_SearchPainter o) => o.active != active;
}

class _FriendsPainter extends CustomPainter {
  final bool active;
  const _FriendsPainter(this.active);
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final p = _navPaint(active);
    final body = Path()
      ..moveTo(17*s,21*s) ..lineTo(17*s,19*s)
      ..arcToPoint(Offset(13*s,15*s), radius: Radius.circular(4*s), clockwise: false)
      ..lineTo(5*s,15*s)
      ..arcToPoint(Offset(1*s,19*s), radius: Radius.circular(4*s), clockwise: false)
      ..lineTo(1*s,21*s);
    canvas.drawPath(body, p);
    canvas.drawCircle(Offset(9*s,7*s), 4*s, p);
    final body2 = Path()
      ..moveTo(23*s,21*s) ..lineTo(23*s,19*s)
      ..arcToPoint(Offset(20*s,15.13*s), radius: Radius.circular(4*s), clockwise: false);
    canvas.drawPath(body2, p);
    final head2 = Path()
      ..moveTo(16*s,3.13*s)
      ..arcToPoint(Offset(16*s,10.88*s), radius: Radius.circular(4*s));
    canvas.drawPath(head2, p);
  }
  @override bool shouldRepaint(_FriendsPainter o) => o.active != active;
}

class _ProfilePainter extends CustomPainter {
  final bool active;
  const _ProfilePainter(this.active);
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final p = _navPaint(active);
    final body = Path()
      ..moveTo(20*s,21*s) ..lineTo(20*s,19*s)
      ..arcToPoint(Offset(16*s,15*s), radius: Radius.circular(4*s), clockwise: false)
      ..lineTo(8*s,15*s)
      ..arcToPoint(Offset(4*s,19*s), radius: Radius.circular(4*s), clockwise: false)
      ..lineTo(4*s,21*s);
    canvas.drawPath(body, p);
    canvas.drawCircle(Offset(12*s,7*s), 4*s, p);
  }
  @override bool shouldRepaint(_ProfilePainter o) => o.active != active;
}

class _PlusPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final cx = size.width / 2;
    final cy = size.height / 2;
    canvas.drawLine(Offset(cx, cy-9), Offset(cx, cy+9), paint);
    canvas.drawLine(Offset(cx-9, cy), Offset(cx+9, cy), paint);
  }
  @override bool shouldRepaint(_PlusPainter o) => false;
}