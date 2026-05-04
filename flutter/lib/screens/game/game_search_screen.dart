import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/game_provider.dart';
import 'game_profile_screen.dart';
import '../logGames/log_game_search_screen.dart';
import '../profile/user_profile_screen.dart';
import '../home/home_screen.dart';

class GameSearchScreen extends StatefulWidget {
  const GameSearchScreen({super.key});

  @override
  State<GameSearchScreen> createState() => _GameSearchScreenState();
}

class _GameSearchScreenState extends State<GameSearchScreen> {
  final _searchCtrl = TextEditingController();

  static const bg      = Color(0xFF0E0E12);
  static const surface = Color(0xFF16161E);
  static const surface2= Color(0xFF1E1E2A);
  static const accent  = Color(0xFF4ADE80);
  static const muted   = Color(0xFF6B6B80);
  static const border  = Color(0x12FFFFFF);

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (_searchCtrl.text == value) {
        context.read<GameProvider>().searchGames(value);
      }
    });
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
          Text(
            '$label coming in GP2!',
            style: const TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
          ),
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
    final games = context.watch<GameProvider>();

    return Scaffold(
      backgroundColor: bg,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Search Games',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: _onSearchChanged,
                  autofocus: false,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search for a game...',
                    hintStyle: const TextStyle(color: muted),
                    prefixIcon: const Icon(Icons.search, color: muted),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: muted),
                            onPressed: () {
                              _searchCtrl.clear();
                              context.read<GameProvider>().clearSearch();
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: accent, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                ),
              ),

              // Results — extra bottom padding so content isn't behind nav bar
              Expanded(
                child: _buildResults(games),
              ),

              // Space for nav bar
              const SizedBox(height: 80),
            ],
          ),

          // Bottom nav pinned to bottom
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: _buildBottomNav(),
          ),
        ],
      ),
    );
  }

  // ── Results ───────────────────────────────────────────────────────────────
  Widget _buildResults(GameProvider games) {
    if (games.isSearching) {
      return const Center(child: CircularProgressIndicator(color: accent));
    }
    if (games.searchStatus == GameStatus.error) {
      return Center(
        child: Text(games.errorMessage, style: const TextStyle(color: muted)),
      );
    }
    if (games.searchResults.isEmpty && games.searchStatus == GameStatus.idle) {
      return const Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.sports_esports, color: muted, size: 48),
          SizedBox(height: 12),
          Text('Search for any game', style: TextStyle(color: muted, fontSize: 15)),
        ]),
      );
    }
    if (games.searchResults.isEmpty && games.searchStatus == GameStatus.success) {
      return const Center(
        child: Text('No games found', style: TextStyle(color: muted, fontSize: 15)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: games.searchResults.length,
      itemBuilder: (context, index) {
        return _buildGameTile(games.searchResults[index]);
      },
    );
  }

  Widget _buildGameTile(Map<String, dynamic> game) {
    return GestureDetector(
      onTap: () {
        final rawgId = game['rawg_id'] ?? game['id'];
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => GameProfileScreen(
            rawgId: rawgId,
            gameName: game['name'],
          ),
        ));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: (game['cover_image'] ?? game['background_image']) != null
                ? Image.network(
                    game['cover_image'] ?? game['background_image'],
                    width: 70, height: 90, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _placeholder(),
                  )
                : _placeholder(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                game['name'] ?? '',
                style: const TextStyle(color: Colors.white, fontSize: 14,
                    fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              if (game['rating'] != null)
                Row(children: [
                  const Icon(Icons.star, color: Color(0xFFFBBF24), size: 13),
                  const SizedBox(width: 3),
                  Text('${game['rating']}',
                      style: const TextStyle(color: muted, fontSize: 12)),
                ]),
              const SizedBox(height: 4),
              if (game['released'] != null)
                Text(
                  game['released'].toString().substring(0, 4),
                  style: const TextStyle(color: muted, fontSize: 11),
                ),
            ]),
          ),
          const Icon(Icons.chevron_right, color: muted),
        ]),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      width: 70, height: 90,
      decoration: BoxDecoration(
        color: surface2, borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.sports_esports, color: muted, size: 28),
    );
  }

  // ── Bottom Nav ────────────────────────────────────────────────────────────
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
        // Home
_navBtn(
  child: CustomPaint(size: const Size(22,22), painter: _HomePainter(false)),
  onTap: () => Navigator.pushReplacement(context,
      MaterialPageRoute(builder: (_) => const HomeScreen())),
),
          // Search — active (already here)
          _navBtn(
            child: CustomPaint(size: const Size(22,22), painter: _SearchPainter(true)),
            onTap: () {},
          ),
          // Add — log a game
          GestureDetector(
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const LogGameSearchScreen())),
            child: Container(
              width: 46, height: 46,
              margin: const EdgeInsets.only(bottom: 4),
              decoration: const BoxDecoration(
                color: Color(0xFFE8002D), shape: BoxShape.circle,
              ),
              child: CustomPaint(painter: _PlusPainter()),
            ),
          ),
          // Friends — sprint 2
          _navBtn(
            child: CustomPaint(size: const Size(22,22), painter: _FriendsPainter(false)),
            onTap: () => _sprint2('Friends'),
          ),
          // Profile — goes to UserProfileScreen
          _navBtn(
            child: CustomPaint(size: const Size(22,22), painter: _ProfilePainter(false)),
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => const UserProfileScreen(),
            )),
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
        child: child,
      ),
    );
  }
}

// ── Nav painters ──────────────────────────────────────────────────────────────
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
      ..moveTo(3*s,9*s) ..lineTo(12*s,2*s) ..lineTo(21*s,9*s)
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
      ..arcToPoint(Offset(16*s,10.88*s), radius: Radius.circular(4*s), clockwise: true);
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