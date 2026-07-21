import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../services/list_service.dart';
import '../game/game_profile_screen.dart';

/// Full-page view of a single list: its emoji, name and every game in it.
///
/// Pops back `true` when the list was changed here (a game removed), so the
/// profile knows to refetch instead of trusting its cached copy.
class ListDetailScreen extends StatefulWidget {
  final Map<String, dynamic> list;

  /// Other people's lists are read-only — no remove buttons.
  final bool canEdit;

  const ListDetailScreen({super.key, required this.list, this.canEdit = true});

  @override
  State<ListDetailScreen> createState() => _ListDetailScreenState();
}

class _ListDetailScreenState extends State<ListDetailScreen> {
  static const bg = Color(0xFF0E0E12);
  static const surface = Color(0xFF16161E);
  static const surface2 = Color(0xFF1E1E2A);
  static const kText = Color(0xFFF0F0F0);
  static const muted = Color(0xFF6B6B80);
  static const border = Color(0x12FFFFFF);

  late List<Map<String, dynamic>> _games;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _games = List<Map<String, dynamic>>.from(widget.list['games'] ?? []);
  }

  Future<void> _removeGame(int rawgId) async {
    final response =
        await ListService().removeGame(widget.list['id'] as int, rawgId);
    if (!mounted) return;
    if (response['success'] == true) {
      setState(() {
        _games.removeWhere((g) => g['rawg_id'] == rawgId);
        _changed = true;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(response['message'] ?? 'Could not remove game')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPublic = widget.list['is_public'] == true;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: bg,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: kText),
            onPressed: () => Navigator.pop(context, _changed),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            _header(isPublic),
            const SizedBox(height: 8),
            if (_games.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 40),
                child: Text(
                  'Empty for now — add games from a game\'s page.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: muted),
                ),
              )
            else
              // Same 3-up cover grid the games section uses, so a list reads
              // the same way as My Games.
              GridView.builder(
                padding: const EdgeInsets.all(16),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.65,
                ),
                itemCount: _games.length,
                itemBuilder: (_, i) => _gameTile(_games[i]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _header(bool isPublic) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: border),
              ),
              alignment: Alignment.center,
              child: Text(widget.list['emoji'] as String,
                  style: const TextStyle(fontSize: 44)),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    widget.list['name'] as String,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: kText),
                  ),
                ),
                if (isPublic) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.public, size: 16, color: muted),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _games.length == 1 ? '1 game' : '${_games.length} games',
              style: const TextStyle(fontSize: 13, color: muted),
            ),
          ],
        ),
      );

  Widget _gameTile(Map<String, dynamic> game) {
    final name = game['name'] as String;
    final rawgId = game['rawg_id'] as int;
    // Games in a list come straight from our DB, so they carry their own
    // artwork — no need to go through the name-resolution cache.
    final url = (game['cover_image'] ?? game['background_image']) as String?;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GameProfileScreen(rawgId: rawgId, gameName: name),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (url != null)
                    CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorWidget: (_, __, ___) => _placeholder(),
                    )
                  else
                    _placeholder(),
                  if (widget.canEdit)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () => _removeGame(rawgId),
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Color(0xCC0E0E12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close,
                              color: Colors.white, size: 14),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: kText,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.3)),
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [surface2, surface],
          ),
        ),
        child: const Center(
          child: Icon(Icons.sports_esports, color: muted, size: 22),
        ),
      );
}
