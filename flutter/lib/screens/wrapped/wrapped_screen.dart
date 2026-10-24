// Gaming Wrapped: the year's summary as full-screen cards in a horizontal
// PageView, with story-style chrome (progress segments, tap left/right to
// step). A card only animates once the user settles on its page.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/wrapped.dart';
import 'cards/featured_game_card.dart';
import 'cards/friends_hours_card.dart';
import 'cards/game_status_card.dart';
import 'cards/games_played_card.dart';
import 'cards/gaming_twin_card.dart';
import 'cards/player_type_card.dart';
import 'cards/rating_card.dart';
import 'cards/top_games_card.dart';
import 'cards/total_hours_card.dart';
import 'cards/trophies_card.dart';
import 'wrapped_card.dart';
import 'wrapped_copy.dart';

/// The cards to show, in order. A card whose data is null is left out.
List<Widget> buildWrappedCards(WrappedResponse data) {
  final topGames = data.topGames ?? const <WrappedGame>[];
  return [
    if (data.totalHours case final hours?) TotalHoursCard(hours: hours, year: data.year),
    if (data.gamesPlayed case final count?) GamesPlayedCard(count: count, covers: data.gamesPlayedCovers),
    if (topGames.isNotEmpty)
      FeaturedGameCard(eyebrow: kTopGameEyebrow, game: topGames.first, totalHours: data.totalHours),
    if (topGames.length >= 2) TopGamesCard(games: topGames),
    if (data.topOnlineGame case final game?)
      FeaturedGameCard(
        eyebrow: kTopOnlineGameEyebrow,
        game: game,
        totalHours: data.totalHours,
        palette: WrappedPalette.topOnline,
        icon: Icons.groups_rounded,
      ),
    if (data.trophiesEarned case final count?) TrophiesCard(count: count, trophies: data.trophies),
    if (data.playStyle case WrappedPlayStyle(:final type?) && final style) PlayerTypeCard(type: type, style: style),
    if (data.playStyle case final style? when style.total > 0) GameStatusCard(style: style),
    if (data.rating case final rating?) RatingCard(rating: rating),
    if (data.friendsHours case final stats?)
      if ((stats.me, stats.rival) case (final me?, final rival?)) FriendsHoursCard(stats: stats, me: me, rival: rival),
    if ((data.me, data.similarFriend) case (final me?, final friend?)) GamingTwinCard(me: me, friend: friend),
  ];
}

class WrappedScreen extends StatefulWidget {
  final WrappedResponse data;

  const WrappedScreen({super.key, required this.data});

  @override
  State<WrappedScreen> createState() => _WrappedScreenState();
}

class _WrappedScreenState extends State<WrappedScreen> {
  static const _stepDuration = Duration(milliseconds: 380);

  final _pageController = PageController();
  late List<Widget> _cards = buildWrappedCards(widget.data);
  final _precached = <int>{};
  int _settledPage = 0;

  /// The page the progress bar shows; moves as soon as a swipe crosses halfway.
  int _currentPage = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _precacheFrom(_settledPage);
  }

  @override
  void didUpdateWidget(WrappedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _cards = buildWrappedCards(widget.data);
      _precached.clear();
      _precacheFrom(_settledPage);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Precaches the images of [page] and the one after it.
  void _precacheFrom(int page) {
    for (final i in [page, page + 1]) {
      if (i >= _cards.length || !_precached.add(i)) continue;
      if (_cards[i] case WrappedCard(:final imageUrls)) {
        for (final url in imageUrls) {
          precacheWrappedImage(url, context);
        }
      }
    }
  }

  void _onPageChanged(int page) {
    setState(() => _currentPage = page);
    // Crossing halfway is early enough to start loading the next page.
    _precacheFrom(page);
  }

  bool _onScrollEnd(ScrollEndNotification notification) {
    if (notification.depth != 0) return false;
    final page = _pageController.page?.round() ?? _settledPage;
    if (page != _settledPage) setState(() => _settledPage = page);
    _precacheFrom(page);
    return false;
  }

  /// Tapping the left third goes back a card; anywhere else goes forward.
  void _onTapUp(TapUpDetails details) {
    final width = MediaQuery.sizeOf(context).width;
    final target = details.globalPosition.dx < width / 3 ? _currentPage - 1 : _currentPage + 1;
    if (target < 0 || target >= _cards.length) return;
    HapticFeedback.selectionClick();
    _pageController.animateToPage(target, duration: _stepDuration, curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapUp: _onTapUp,
              child: NotificationListener<ScrollEndNotification>(
                onNotification: _onScrollEnd,
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _cards.length,
                  onPageChanged: _onPageChanged,
                  itemBuilder: (context, i) => WrappedPageScope(active: i == _settledPage, child: _cards[i]),
                ),
              ),
            ),
            SafeArea(
              child: _StoryChrome(
                year: widget.data.year,
                count: _cards.length,
                current: _currentPage,
                onClose: Navigator.canPop(context) ? () => Navigator.maybePop(context) : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Progress segments, the Wrapped wordmark and the close button.
class _StoryChrome extends StatelessWidget {
  final int year;
  final int count;
  final int current;
  final VoidCallback? onClose;

  const _StoryChrome({required this.year, required this.count, required this.current, this.onClose});

  @override
  Widget build(BuildContext context) {
    final label = Theme.of(
      context,
    ).textTheme.labelMedium!.copyWith(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 2.2);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (count > 1)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  for (var i = 0; i < count; i++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          height: 3,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: i <= current ? 0.95 : 0.25),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Row(
            children: [
              const SizedBox(width: 4),
              const Icon(Icons.auto_awesome_rounded, size: 16, color: Colors.white),
              const SizedBox(width: 8),
              Text('WRAPPED $year', style: label),
              const Spacer(),
              if (onClose != null)
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded),
                  color: Colors.white,
                  onPressed: onClose,
                )
              else
                const SizedBox(height: 48),
            ],
          ),
        ],
      ),
    );
  }
}
