import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/game_provider.dart';
import '../../providers/logged_games_provider.dart';
import '../logGames/log_game_detail_screen.dart';
import 'achievements_screen.dart';

class GameProfileScreen extends StatefulWidget {
  final int rawgId;
  final String gameName;

  const GameProfileScreen({
    super.key,
    required this.rawgId,
    required this.gameName,
  });

  @override
  State<GameProfileScreen> createState() => _GameProfileScreenState();
}

class _GameProfileScreenState extends State<GameProfileScreen> {
  bool _descriptionExpanded = false;

  static const bg = Color(0xFF0E0E12);
  static const surface = Color(0xFF16161E);
  static const surface2 = Color(0xFF1E1E2A);
  static const accent = Color(0xFF4ADE80);
  static const accent2 = Color(0xFFA78BFA);
  static const gold = Color(0xFFFBBF24);
  static const muted = Color(0xFF6B6B80);
  static const danger = Color(0xFFF87171);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GameProvider>().getGame(widget.rawgId).then((_) {
        if (mounted) context.read<GameProvider>().loadReviews(widget.rawgId);
        if (mounted) context.read<GameProvider>().loadFavoriteStatus(widget.rawgId);
        if (mounted) context.read<GameProvider>().getAchievements(widget.rawgId);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.watch<GameProvider>();

    if (gp.isLoadingProfile) {
      return const Scaffold(
        backgroundColor: bg,
        body: Center(child: CircularProgressIndicator(color: accent)),
      );
    }

    if (gp.selectedGame == null) {
      return Scaffold(
        backgroundColor: bg,
        body: Center(
          child: Text(gp.errorMessage, style: const TextStyle(color: muted)),
        ),
      );
    }

    return Scaffold(backgroundColor: bg, body: _buildBody(gp.selectedGame!));
  }

  Future<void> _refresh() async {
    final gp = context.read<GameProvider>();
    await gp.getGame(widget.rawgId);
    if (mounted) {
      await Future.wait([
        gp.loadReviews(widget.rawgId),
        gp.loadFavoriteStatus(widget.rawgId),
        gp.getAchievements(widget.rawgId),
      ]);
    }
  }

  Widget _buildBody(Map<String, dynamic> game) {
    return RefreshIndicator(
      color: accent,
      backgroundColor: surface,
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        slivers: [
        _buildHero(game),
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTitleBlock(game),
              _buildRatingRow(game),
              _buildActionStrip(game),
              _buildAbout(game),
              _buildDetails(game),
              _buildTrophies(),
              _buildReviews(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ],
    ),
    );
  }

  // ── Hero ──────────────────────────────────────────────────

  Widget _buildHero(Map<String, dynamic> game) {
    return SliverAppBar(
      expandedHeight: 290,
      pinned: true,
      backgroundColor: bg,
      automaticallyImplyLeading: false,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Game cover
            game['background_image'] != null
                ? CachedNetworkImage(
                    imageUrl: game['background_image'],
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _heroBg(),
                  )
                : _heroBg(),

            // Gradient overlay — dark at top and bottom
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x40000000),
                    Colors.transparent,
                    Color(0x99000000),
                    bg,
                  ],
                  stops: [0.0, 0.35, 0.7, 1.0],
                ),
              ),
            ),

            // Back button
            Positioned(
              top: 48,
              left: 18,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.45),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
              ),
            ),

            // Platform chips
            Positioned(bottom: 48, left: 18, child: _buildPlatformChips(game)),
          ],
        ),
      ),
    );
  }

  Widget _heroBg() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1040), Color(0xFF3B1F6B), Color(0xFF0D0520)],
        ),
      ),
      child: const Center(
        child: Icon(Icons.sports_esports, color: Colors.white24, size: 72),
      ),
    );
  }

  Widget _buildPlatformChips(Map<String, dynamic> game) {
    final platforms = (game['platforms'] as List? ?? []).take(3).toList();
    return Wrap(
      spacing: 6,
      children: platforms.map((p) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white24),
          ),
          child: Text(
            p.toString().toUpperCase(),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Title Block ───────────────────────────────────────────

  Widget _buildTitleBlock(Map<String, dynamic> game) {
    final genres = game['genres'] as List? ?? [];
    final devs = game['developers'] as List? ?? [];
    final released = game['released_at']?.toString();
    final playtime = game['playtime_hrs'];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (genres.isNotEmpty)
            Text(
              genres.first.toString().toUpperCase(),
              style: const TextStyle(
                color: accent2,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            game['name'] ?? widget.gameName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (devs.isNotEmpty)
                Text(
                  devs.first.toString(),
                  style: const TextStyle(color: muted, fontSize: 11),
                ),
              if (devs.isNotEmpty && released != null) _dot(),
              if (released != null)
                Text(
                  released.substring(0, 4),
                  style: const TextStyle(color: muted, fontSize: 11),
                ),
              if (playtime != null) ...[
                _dot(),
                Text(
                  '⏱ ~$playtime hrs',
                  style: const TextStyle(color: muted, fontSize: 11),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _dot() => Container(
    width: 3,
    height: 3,
    decoration: const BoxDecoration(color: muted, shape: BoxShape.circle),
  );

  // ── Rating Row ────────────────────────────────────────────

  Widget _buildRatingRow(Map<String, dynamic> game) {
    final metacritic = game['metacritic_score'] as int?;
    final gp = context.watch<GameProvider>();
    final communityRating = gp.communityRating;
    final ratingCount = gp.communityRatingCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStars(communityRating ?? 0, size: 22),
              const SizedBox(height: 3),
              Text(
                ratingCount > 0
                    ? '$ratingCount ${ratingCount == 1 ? 'rating' : 'ratings'}'
                    : 'No ratings yet',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ],
          ),
          // ── Metacritic score ──
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              metacritic != null
                  ? RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: '$metacritic',
                            style: TextStyle(
                              color: _metacriticColor(metacritic),
                              fontSize: 36,
                              fontWeight: FontWeight.w700,
                              height: 1,
                            ),
                          ),
                          const TextSpan(
                            text: '/100',
                            style: TextStyle(color: muted, fontSize: 16),
                          ),
                        ],
                      ),
                    )
                  : const Text(
                      'N/A',
                      style: TextStyle(
                        color: muted,
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
              const Text(
                'Metacritic',
                style: TextStyle(color: muted, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _metacriticColor(int score) {
    if (score >= 75) return const Color(0xFF4ADE80); // green
    if (score >= 50) return const Color(0xFFFBBF24); // yellow
    return const Color(0xFFF87171); // red
  }

  Widget _buildStars(double rating, {double size = 18}) {
    return Row(
      children: List.generate(5, (i) {
        IconData icon;
        if (i < rating.floor()) {
          icon = Icons.star;
        } else if (i < rating) {
          icon = Icons.star_half;
        } else {
          icon = Icons.star_outline;
        }
        return Icon(icon, color: gold, size: size);
      }),
    );
  }

  // ── Action Strip ──────────────────────────────────────────

  Widget _buildActionStrip(Map<String, dynamic> game) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 0, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _actionBtn(Icons.edit_outlined, 'Log', isPrimary: true, onTap: () {
              final logGame = {
                ...game,
                'rawg_id': game['rawg_id'] ?? game['id'],
                'released': game['released'] ?? game['released_at'],
              };
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LogGameDetailScreen(game: logGame),
                ),
              );
            }),
            const SizedBox(width: 8),
            _heartBtn(),
            const SizedBox(width: 8),
            _rateBtn(game),
            const SizedBox(width: 8),
            _actionBtn(Icons.list_outlined, 'Add to List'),
            const SizedBox(width: 20),
          ],
        ),
      ),
    );
  }

  void _guardLogged(Map<String, dynamic> game, VoidCallback onLogged) {
    final rawgId = (game['rawg_id'] ?? game['id']) as int;
    final lp = context.read<LoggedGamesProvider>();
    final isLogged = lp.games.any((g) => g.rawgId == rawgId);

    if (isLogged) {
      onLogged();
      return;
    }

    final logGame = {
      ...game,
      'rawg_id': rawgId,
      'released': game['released'] ?? game['released_at'],
    };

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Log this game first',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          "You haven't logged this game as played. Log it to keep track, or continue anyway.",
          style: TextStyle(color: Color(0xFF9090A0), fontSize: 13, height: 1.5),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => LogGameDetailScreen(game: logGame)),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Log Game', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                Navigator.pop(ctx);
                onLogged();
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Color(0xFF3A3A4A)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Continue Without Logging', style: TextStyle(fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }

  void _showRatingSheet(Map<String, dynamic> game) {
    final rawgId = (game['rawg_id'] ?? game['id']) as int;
    final gp = context.read<GameProvider>();
    int selected = gp.userRating ?? 0;

    final ownReview = gp.reviews.cast<Map<String, dynamic>>()
        .firstWhere((r) => r['is_own'] == true, orElse: () => {});
    final existingReviewText = ownReview['review_text'] as String? ?? '';
    final hadReview = existingReviewText.isNotEmpty;
    final reviewController = TextEditingController(text: existingReviewText);

    showModalBottomSheet(
      context: context,
      backgroundColor: surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(ctx).viewInsets.bottom + 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 36, height: 4,
                decoration: BoxDecoration(color: muted, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              Text(game['name'] ?? '', textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text('Rate & Review', style: TextStyle(color: muted, fontSize: 13)),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) => GestureDetector(
                  onTap: () => setSheet(() => selected = (selected == i + 1) ? 0 : i + 1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      i < selected ? Icons.star : Icons.star_outline,
                      color: gold, size: 40,
                    ),
                  ),
                )),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: reviewController,
                maxLines: 3,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Write a review (optional)',
                  hintStyle: const TextStyle(color: muted, fontSize: 14),
                  filled: true,
                  fillColor: surface2,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (selected == 0 && gp.userRating == null) ? null : () async {
                    final ratingToSave = selected;
                    final reviewText = reviewController.text.trim();
                    final isDeletingReview = hadReview && reviewText.isEmpty;
                    Navigator.pop(ctx);
                    final bool ok;
                    if (ratingToSave == 0) {
                      if (hadReview) await gp.submitReview(rawgId, '', 0);
                      ok = await gp.rateGame(rawgId, 0);
                    } else if (reviewText.isNotEmpty || hadReview) {
                      ok = await gp.submitReview(rawgId, reviewText, ratingToSave);
                    } else {
                      ok = await gp.rateGame(rawgId, ratingToSave);
                    }
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(ok
                          ? (ratingToSave == 0 ? 'Rating removed!' : isDeletingReview ? 'Review removed!' : reviewText.isNotEmpty ? 'Review submitted!' : 'Rating saved!')
                          : 'Could not save'),
                        backgroundColor: ok ? const Color(0xFF2E7D32) : danger,
                        duration: const Duration(seconds: 2),
                      ));
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: (selected == 0 && gp.userRating != null) ? danger : accent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    (selected == 0 && gp.userRating != null) ? 'Remove Rating' : 'Save',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heartBtn() {
    final gp = context.watch<GameProvider>();
    final fav = gp.isFavorite;
    return GestureDetector(
      onTap: () {
        final gp = context.read<GameProvider>();
        if (gp.isFavorite) {
          gp.toggleFavorite(widget.rawgId);
        } else {
          _guardLogged(
            gp.selectedGame ?? {},
            () => gp.toggleFavorite(widget.rawgId),
          );
        }
      },
      child: Container(
        width: 72,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: fav ? const Color(0x1FF87171) : surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: fav ? const Color(0x4DF87171) : const Color(0x12FFFFFF),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(fav ? Icons.favorite : Icons.favorite_border,
                color: fav ? const Color(0xFFF87171) : muted, size: 20),
            const SizedBox(height: 5),
            Text('Favorite',
                style: TextStyle(
                  color: fav ? const Color(0xFFF87171) : muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                )),
          ],
        ),
      ),
    );
  }

  Widget _rateBtn(Map<String, dynamic> game) {
    final gp = context.watch<GameProvider>();
    final hasRated = gp.userRating != null;
    return GestureDetector(
      onTap: () {
        if (gp.userRating != null) {
          _showRatingSheet(game);
        } else {
          _guardLogged(game, () => _showRatingSheet(game));
        }
      },
      child: Container(
        width: 72,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: hasRated ? const Color(0x1FFBBF24) : surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasRated ? const Color(0x4DFBBF24) : const Color(0x12FFFFFF),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasRated ? Icons.star : Icons.star_outline,
              color: hasRated ? gold : muted,
              size: 20,
            ),
            const SizedBox(height: 5),
            Text(
              'Rate',
              style: TextStyle(
                color: hasRated ? gold : muted,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label,
      {bool isPrimary = false, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap ??
          () {
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
                      color: muted.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Text('🚧', style: TextStyle(fontSize: 36)),
                  const SizedBox(height: 12),
                  Text('$label coming in GP2!',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  const Text('This feature is on its way.',
                      style: TextStyle(color: muted, fontSize: 13)),
                  const SizedBox(height: 24),
                ]),
              ),
            );
          },
      child: Container(
        width: 72,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isPrimary ? const Color(0x1F4ADE80) : surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isPrimary
                ? const Color(0x4D4ADE80)
                : const Color(0x12FFFFFF),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isPrimary ? accent : muted, size: 20),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                color: isPrimary ? accent : muted,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ── About ─────────────────────────────────────────────────

  Widget _buildAbout(Map<String, dynamic> game) {
    final desc =
        game['description'] ?? game['summary'] ?? 'No description available.';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('About'),
          const SizedBox(height: 10),
          Text(
            desc,
            style: const TextStyle(
              color: Color(0xB3F0F0F5),
              fontSize: 13,
              height: 1.7,
              fontWeight: FontWeight.w300,
            ),
            maxLines: _descriptionExpanded ? null : 4,
            overflow: _descriptionExpanded ? null : TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () =>
                setState(() => _descriptionExpanded = !_descriptionExpanded),
            child: Text(
              _descriptionExpanded ? 'Show less ‹' : 'Read more ›',
              style: const TextStyle(
                color: accent,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Details Grid ──────────────────────────────────────────

  Widget _buildDetails(Map<String, dynamic> game) {
    final devs = (game['developers'] as List? ?? []);
    final released = game['released_at']?.toString();
    final playtime = game['playtime_hrs'];
    final esrb = game['esrb_rating'];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Details'),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 2.6,
            children: [
              _detailCell(
                'Developer',
                devs.isNotEmpty ? devs.first.toString() : 'Unknown',
              ),
              _detailCell(
                'Release',
                released != null ? released.substring(0, 10) : 'Unknown',
              ),
              _detailCell(
                'Avg Playtime',
                playtime != null ? '~$playtime hours' : 'Unknown',
              ),
              _detailCell('Rating', esrb ?? 'Not rated'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailCell(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x12FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: muted,
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ── Trophies ──────────────────────────────────────────────

  Widget _buildTrophies() {
    final gp = context.watch<GameProvider>();

    if (gp.isLoadingAchievements) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 24, 20, 0),
        child: Center(child: CircularProgressIndicator(color: accent, strokeWidth: 2)),
      );
    }

    final achievements = gp.achievements;
    if (achievements.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Trophies'),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x12FFFFFF)),
              ),
              child: const Center(
                child: Text(
                  'No achievements found for this game',
                  style: TextStyle(color: muted, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final preview = achievements.take(3).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Row(
              children: [
                Expanded(child: _sectionTitle('Trophies')),
                if (achievements.length > 3)
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AchievementsScreen(
                          gameName: widget.gameName,
                          achievements: achievements,
                        ),
                      ),
                    ),
                    child: const Text(
                      'See all',
                      style: TextStyle(color: accent, fontSize: 13),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ...preview.map((a) => _achievementCard(a)),
                const SizedBox(width: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _achievementCard(Map<String, dynamic> a) {
    final percent = double.tryParse(a['percent']?.toString() ?? '') ?? 100.0;
    final Color bgColor;
    final Color borderColor;
    if (percent < 10) {
      bgColor = const Color(0x26FBBF24);
      borderColor = const Color(0x4DFBBF24);
    } else if (percent < 30) {
      bgColor = const Color(0x2694A3B8);
      borderColor = const Color(0x4094A3B8);
    } else {
      bgColor = const Color(0x26B4783C);
      borderColor = const Color(0x4DB4783C);
    }

    final imageUrl = a['image'] as String?;

    final iconWidget = Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: imageUrl != null && imageUrl.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) =>
                    const Center(child: Text('🏆', style: TextStyle(fontSize: 16))),
              )
            : const Center(child: Text('🏆', style: TextStyle(fontSize: 16))),
      ),
    );

    return _trophyCardRaw(
      iconWidget: iconWidget,
      name: a['name'] ?? '',
      desc: a['description'] ?? '',
    );
  }

  Widget _trophyCardRaw({
    required Widget iconWidget,
    required String name,
    required String desc,
  }) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x12FFFFFF)),
      ),
      child: Row(
        children: [
          iconWidget,
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  desc,
                  style: const TextStyle(color: muted, fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Reviews ───────────────────────────────────────────────

  Widget _buildReviews() {
    final gp = context.watch<GameProvider>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('User Reviews'),
          const SizedBox(height: 10),
          if (gp.isLoadingReviews)
            const Center(child: Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: CircularProgressIndicator(color: accent, strokeWidth: 2),
            ))
          else if (gp.reviewsStatus == GameStatus.error)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Column(
                  children: [
                    const Text('Could not load reviews', style: TextStyle(color: muted, fontSize: 13)),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => gp.loadReviews(widget.rawgId),
                      child: const Text('Retry', style: TextStyle(color: accent, fontSize: 13)),
                    ),
                  ],
                ),
              ),
            )
          else if (gp.reviews.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'No reviews yet. Be the first to leave a review!',
                  style: TextStyle(color: muted, fontSize: 13),
                ),
              ),
            )
          else ...[
            ...gp.reviews.map((r) => _reviewCard(r as Map<String, dynamic>)),
          ],
        ],
      ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return '';
    }
  }

  Widget _reviewCard(Map<String, dynamic> r) {
    final username = r['username'] as String? ?? 'Unknown';
    final avatarUrl = r['avatar_url'] as String?;
    final rating = (r['user_rating'] as num?)?.toInt() ?? 0;
    final text = r['review_text'] as String? ?? '';
    final date = _formatDate(r['updated_at'] as String?);
    final isOwn = r['is_own'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOwn ? const Color(0x334ADE80) : const Color(0x12FFFFFF),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: surface2,
                      border: Border.all(color: const Color(0x12FFFFFF)),
                    ),
                    child: avatarUrl != null
                        ? ClipOval(child: CachedNetworkImage(
                            imageUrl: avatarUrl,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => _avatarInitial(username),
                          ))
                        : _avatarInitial(username),
                  ),
                  const SizedBox(width: 9),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '@$username',
                        style: const TextStyle(
                          color: accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(date, style: const TextStyle(color: muted, fontSize: 10)),
                    ],
                  ),
                ],
              ),
              Row(
                children: List.generate(5, (i) => Icon(
                  i < rating ? Icons.star : Icons.star_outline,
                  color: gold, size: 12,
                )),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xB3F0F0F5),
              fontSize: 12,
              height: 1.65,
              fontWeight: FontWeight.w300,
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarInitial(String username) {
    return Center(
      child: Text(
        username.isNotEmpty ? username[0].toUpperCase() : '?',
        style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }

  // ── Section Title ─────────────────────────────────────────

  Widget _sectionTitle(String title) {
    return Row(
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(child: Divider(color: Color(0x12FFFFFF))),
      ],
    );
  }
}
