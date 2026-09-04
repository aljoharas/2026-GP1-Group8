import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/logged_games_provider.dart';
import '../game/game_profile_screen.dart';

class MyGamesScreen extends StatelessWidget {
  const MyGamesScreen({super.key});

  static const bg = Color(0xFF0E0E12);
  static const surface = Color(0xFF16161E);
  static const surface2 = Color(0xFF1E1E2A);
  static const accent = Color(0xFFE8002D);
  // Confirming that something worked is green; red stays on the action that
  // does the deleting, not on the receipt for it.
  static const successGreen = Color(0xFF4ADE80);
  static const muted = Color(0xFF6B6B80);
  static const kText = Color(0xFFF0F0F0);
  static const border = Color(0x12FFFFFF);

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  Widget build(BuildContext context) {
    final lp = context.watch<LoggedGamesProvider>();
    final games = lp.games;
    final byDate = lp.sortOrder == MyGamesSortOrder.date;

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
        centerTitle: true,
        title: const Text(
          'My Games',
          style: TextStyle(
            color: kText,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        // Sort toggle in the AppBar bottom area
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
            child: _SortToggle(
              byDate: byDate,
              onDate: () =>
                  context.read<LoggedGamesProvider>().setSortOrder(
                    MyGamesSortOrder.date,
                  ),
              onName: () =>
                  context.read<LoggedGamesProvider>().setSortOrder(
                    MyGamesSortOrder.name,
                  ),
            ),
          ),
        ),
      ),
      body: games.isEmpty
          ? _buildEmpty()
          : byDate
              ? _buildDiaryList(context, games)
              : _buildNameList(context, games),
    );
  }

  // ── Empty State ───────────────────────────────────────────────────────────

  Widget _buildEmpty() {
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
            child: const Icon(Icons.videogame_asset_outlined,
                color: muted, size: 34),
          ),
          const SizedBox(height: 16),
          const Text(
            'No games logged yet',
            style: TextStyle(
                color: kText, fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tap the + button to log your first game',
            style: TextStyle(color: muted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ── Remove helpers ────────────────────────────────────────────────────────

  void _showGameOptions(BuildContext context, LoggedGame game) {
    if (game.rawgId == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: muted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Text(
                game.name,
                style: const TextStyle(
                  color: kText,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 8),
            const Divider(color: border),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: accent),
              title: const Text(
                'Remove from library',
                style: TextStyle(color: accent, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Deletes all logs for this game',
                style: TextStyle(color: muted, fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _confirmAndRemove(context, game);
              },
            ),
            ListTile(
              leading: const Icon(Icons.close, color: muted),
              title: const Text('Cancel', style: TextStyle(color: muted)),
              onTap: () => Navigator.pop(ctx),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirmAndRemove(BuildContext context, LoggedGame game) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Remove game?',
          style: TextStyle(color: kText, fontSize: 17, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'All logs for "${game.name}" will be permanently deleted.',
          style: const TextStyle(color: muted, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: muted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<LoggedGamesProvider>().removeGame(game.rawgId!);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  // Green is bright enough that the default white content
                  // text is hard to read on it; the app already pairs its
                  // greens with black.
                  content: Text('"${game.name}" removed from your library',
                      style: const TextStyle(
                          color: Colors.black, fontWeight: FontWeight.w600)),
                  backgroundColor: successGreen,
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 3),
                ),
              );
            },
            child: const Text(
              'Remove',
              style: TextStyle(color: accent, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  // ── Diary / By-Date List ──────────────────────────────────────────────────

  Widget _buildDiaryList(BuildContext context, List<LoggedGame> games) {
    // Group by month-year string
    final groups = <String, List<LoggedGame>>{};
    final groupOrder = <String>[];
    for (final g in games) {
      final key =
          '${_months[g.loggedAt.month - 1].toUpperCase()} ${g.loggedAt.year}';
      if (!groups.containsKey(key)) {
        groups[key] = [];
        groupOrder.add(key);
      }
      groups[key]!.add(g);
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: groupOrder.length,
      itemBuilder: (_, i) {
        final key = groupOrder[i];
        final entries = groups[key]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Month/Year header
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 8),
              child: Text(
                key,
                style: const TextStyle(
                  color: muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const Divider(height: 1, color: border),
            ...entries.map(
              (game) => _DiaryRow(
                game: game,
                onMoreTap: () => _showGameOptions(context, game),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── By-Name List ──────────────────────────────────────────────────────────

  Widget _buildNameList(BuildContext context, List<LoggedGame> games) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: games.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: border),
      itemBuilder: (_, i) => _NameRow(
        game: games[i],
        onMoreTap: () => _showGameOptions(context, games[i]),
      ),
    );
  }
}

// ── Sort Toggle ───────────────────────────────────────────────────────────────

class _SortToggle extends StatelessWidget {
  final bool byDate;
  final VoidCallback onDate;
  final VoidCallback onName;

  const _SortToggle({
    required this.byDate,
    required this.onDate,
    required this.onName,
  });

  static const surface = Color(0xFF16161E);
  static const accent = Color(0xFFE8002D);
  static const muted = Color(0xFF6B6B80);
  static const border = Color(0x12FFFFFF);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          _tab('By Date', byDate, onDate),
          _tab('By Name', !byDate, onName),
        ],
      ),
    );
  }

  Widget _tab(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: active ? accent : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : muted,
              fontSize: 13,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Diary Row (by date) ───────────────────────────────────────────────────────

class _DiaryRow extends StatelessWidget {
  final LoggedGame game;
  final VoidCallback? onMoreTap;
  const _DiaryRow({required this.game, this.onMoreTap});

  static const surface2 = Color(0xFF1E1E2A);
  static const muted = Color(0xFF6B6B80);
  static const kText = Color(0xFFF0F0F0);

  void _goToGame(BuildContext context) {
    final rawgId = game.rawgId;
    if (rawgId == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GameProfileScreen(rawgId: rawgId, gameName: game.name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _goToGame(context),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Day number column
            SizedBox(
              width: 36,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${game.loggedAt.day}',
                    style: const TextStyle(
                      color: muted,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            // Game thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 50,
                height: 66,
                child: game.displayImage != null
                    ? Image.network(
                        game.displayImage!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _thumb(),
                      )
                    : _thumb(),
              ),
            ),
            const SizedBox(width: 14),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    game.name,
                    style: const TextStyle(
                      color: kText,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (game.hoursPlayed != null) ...[
                        const Icon(Icons.access_time,
                            color: muted, size: 11),
                        const SizedBox(width: 3),
                        Text(
                          '${game.hoursPlayed!.toStringAsFixed(game.hoursPlayed! % 1 == 0 ? 0 : 1)} hrs',
                          style: const TextStyle(color: muted, fontSize: 11),
                        ),
                      ],
                      if (game.achievements.isNotEmpty) ...[
                        if (game.hoursPlayed != null)
                          const SizedBox(width: 8),
                        const Icon(Icons.military_tech_outlined,
                            color: muted, size: 11),
                        const SizedBox(width: 3),
                        Text(
                          '${game.achievements.length} achieved',
                          style: const TextStyle(color: muted, fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                  if (game.comment != null && game.comment!.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      game.comment!,
                      style: const TextStyle(
                        color: Color(0x99F0F0F0),
                        fontSize: 12,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            GestureDetector(
              onTap: onMoreTap,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.more_vert, color: muted, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumb() => Container(
        color: surface2,
        child: const Icon(Icons.sports_esports, color: muted, size: 20),
      );
}

// ── Name Row (by name) ────────────────────────────────────────────────────────

class _NameRow extends StatelessWidget {
  final LoggedGame game;
  final VoidCallback? onMoreTap;
  const _NameRow({required this.game, this.onMoreTap});

  static const surface2 = Color(0xFF1E1E2A);
  static const muted = Color(0xFF6B6B80);
  static const kText = Color(0xFFF0F0F0);

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  void _goToGame(BuildContext context) {
    final rawgId = game.rawgId;
    if (rawgId == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GameProfileScreen(rawgId: rawgId, gameName: game.name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = game.loggedAt;
    final dateStr =
        '${_months[d.month - 1]} ${d.day}, ${d.year}';

    return GestureDetector(
      onTap: () => _goToGame(context),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 44,
                height: 58,
                child: game.displayImage != null
                    ? Image.network(
                        game.displayImage!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _thumb(),
                      )
                    : _thumb(),
              ),
            ),
            const SizedBox(width: 14),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    game.name,
                    style: const TextStyle(
                      color: kText,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    dateStr,
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                  if (game.hoursPlayed != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${game.hoursPlayed!.toStringAsFixed(game.hoursPlayed! % 1 == 0 ? 0 : 1)} hrs played',
                      style: const TextStyle(color: muted, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
            GestureDetector(
              onTap: onMoreTap,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.more_vert, color: muted, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumb() => Container(
        color: surface2,
        child: const Icon(Icons.sports_esports, color: muted, size: 20),
      );
}
