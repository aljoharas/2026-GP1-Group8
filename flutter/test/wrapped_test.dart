import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/models/wrapped.dart';
import 'package:loadout/screens/wrapped/cards/featured_game_card.dart';
import 'package:loadout/screens/wrapped/cards/friends_hours_card.dart';
import 'package:loadout/screens/wrapped/cards/game_status_card.dart';
import 'package:loadout/screens/wrapped/cards/games_played_card.dart';
import 'package:loadout/screens/wrapped/cards/gaming_twin_card.dart';
import 'package:loadout/screens/wrapped/cards/player_type_card.dart';
import 'package:loadout/screens/wrapped/cards/rating_card.dart';
import 'package:loadout/screens/wrapped/cards/top_games_card.dart';
import 'package:loadout/screens/wrapped/cards/total_hours_card.dart';
import 'package:loadout/screens/wrapped/cards/trophies_card.dart';
import 'package:loadout/screens/wrapped/wrapped_card.dart';
import 'package:loadout/screens/wrapped/wrapped_copy.dart';
import 'package:loadout/screens/wrapped/wrapped_screen.dart';

import 'wrapped_sample.dart';

Map<String, dynamic> _game(int id, String name, num hours) => {
  'game_id': id,
  'name': name,
  'cover_image': null,
  'background_image': null,
  'hours': hours,
};

Widget _app(Widget child, {bool disableAnimations = false}) => MaterialApp(
  theme: ThemeData(colorScheme: const ColorScheme.dark(primary: Color(0xFF4ADE80))),
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: disableAnimations),
      child: child,
    ),
  ),
);

void main() {
  group('formatHours', () {
    test('whole numbers have no decimal', () => expect(formatHours(96), '96 hours'));
    test('fractions show one decimal', () => expect(formatHours(41.5), '41.5 hours'));
    test('one hour is singular', () => expect(formatHours(1), '1 hour'));
    test('rounds to tenths first', () => expect(formatHours(95.96), '96 hours'));
    test('groups thousands', () => expect(formatHours(1204.5), '1,204.5 hours'));
  });

  group('WrappedResponse.fromJson', () {
    test('parses every card', () {
      final data = WrappedResponse.fromJson({
        'year': 2026,
        'is_partial': true,
        'total_hours': 214.5,
        'games_played': 18,
        'games_played_covers': ['https://a', '', null],
        'top_games': [_game(1, 'Elden Ring', 96)],
        'top_online_game': _game(7, 'Valorant', 41.5),
      });
      expect(data.year, 2026);
      expect(data.isPartial, isTrue);
      expect(data.totalHours, 214.5);
      expect(data.gamesPlayed, 18);
      expect(data.gamesPlayedCovers, ['https://a']);
      expect(data.topGames!.single.hours, 96.0);
      expect(data.topOnlineGame!.name, 'Valorant');
    });

    test('tolerates missing and null fields', () {
      final data = WrappedResponse.fromJson({'year': 2026, 'games_played': 0, 'total_hours': null});
      expect(data.totalHours, isNull);
      expect(data.gamesPlayedCovers, isEmpty);
      expect(data.topGames, isNull);
      expect(data.topOnlineGame, isNull);
    });
  });

  group('buildWrappedCards', () {
    test('includes every card when all data is present', () {
      final cards = buildWrappedCards(
        WrappedResponse.fromJson({
          'year': 2026,
          'total_hours': 10,
          'games_played': 3,
          'top_games': [_game(1, 'A', 5), _game(2, 'B', 3)],
          'top_online_game': _game(3, 'C', 2),
        }),
      );
      expect(cards.map((c) => c.runtimeType), [
        TotalHoursCard,
        GamesPlayedCard,
        FeaturedGameCard,
        TopGamesCard,
        FeaturedGameCard,
      ]);
    });

    test('skips null cards and a one-game podium', () {
      final cards = buildWrappedCards(
        WrappedResponse.fromJson({
          'year': 2026,
          'games_played': 1,
          'top_games': [_game(1, 'A', 5)],
        }),
      );
      expect(cards.map((c) => c.runtimeType), [GamesPlayedCard, FeaturedGameCard]);
    });
  });

  testWidgets('total hours card counts up while the clock slows', (tester) async {
    await tester.pumpWidget(_app(const TotalHoursCard(hours: 214.5, year: 2026)));
    expect(find.text('214.5 HOURS'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('TIME PLAYED'), findsOneWidget);
    expect(find.text('214.5 HOURS'), findsOneWidget);
    expect(find.textContaining("That's 8 full days of gaming in 2026."), findsOneWidget);
  });

  testWidgets('reduced motion shows the final state at once', (tester) async {
    await tester.pumpWidget(_app(const GamesPlayedCard(count: 1), disableAnimations: true));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
    expect(find.text(' GAME'), findsOneWidget);
    expect(find.textContaining('One world, fully explored.'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('a card waits until its page is active', (tester) async {
    await tester.pumpWidget(_app(const WrappedPageScope(active: false, child: TotalHoursCard(hours: 1, year: 2026))));
    await tester.pump(const Duration(seconds: 5));
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.text('1 HOUR'), findsNothing);
  });

  testWidgets('podium shows ranks, names and hours', (tester) async {
    final games = [
      WrappedGame.fromJson(_game(1, 'Elden Ring', 96)),
      WrappedGame.fromJson(_game(2, 'Hades', 41.5)),
      WrappedGame.fromJson(_game(3, 'Celeste', 1)),
    ];
    await tester.pumpWidget(_app(TopGamesCard(games: games), disableAnimations: true));
    await tester.pump();
    for (final text in ['TOP 3', '#1', '#2', '#3', 'Elden Ring', '96 hours', '41.5 hours', '1 hour']) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
  });

  group('cards 6–11', () {
    List<Type> types(Map<String, dynamic> json) =>
        buildWrappedCards(WrappedResponse.fromJson(json)).map((c) => c.runtimeType).toList();

    test('parse from the response', () {
      final data = WrappedResponse.fromJson(sampleWrappedJson());
      expect(data.me!.username, 'Aljohara');
      expect(data.trophiesEarned, 14);
      expect(data.trophies.first.name, 'Lord of the Frenzied Flame');
      expect(data.playStyle!.type, PlayerType.theCloser);
      expect(data.playStyle!.total, 14);
      expect(data.rating!.raterType, RaterType.toughCritic);
      expect(data.rating!.breakdown[7], 3);
      expect(data.friendsHours!.leaderboard, hasLength(5));
      expect(data.similarFriend!.sharedGenres, ['RPG', 'Adventure']);
    });

    test('come after card 5 in order', () {
      expect(types(sampleWrappedJson()), [
        TotalHoursCard,
        GamesPlayedCard,
        FeaturedGameCard,
        TopGamesCard,
        FeaturedGameCard,
        TrophiesCard,
        PlayerTypeCard,
        GameStatusCard,
        RatingCard,
        FriendsHoursCard,
        GamingTwinCard,
      ]);
    });

    test('trophies skip when trophies_earned is null', () {
      expect(types({...sampleWrappedJson(), 'trophies_earned': null}), isNot(contains(TrophiesCard)));
    });

    test('trophies show with a count but no list', () {
      final cards = buildWrappedCards(WrappedResponse.fromJson({...sampleWrappedJson(), 'trophies': []}));
      expect(cards.whereType<TrophiesCard>().single.trophies, isEmpty);
    });

    test('player type and game status skip when play_style is null', () {
      final shown = types({...sampleWrappedJson(), 'play_style': null});
      expect(shown, isNot(contains(PlayerTypeCard)));
      expect(shown, isNot(contains(GameStatusCard)));
    });

    test('an unknown player type keeps the game status card', () {
      final shown = types({
        ...sampleWrappedJson(),
        'play_style': {'personality': 'speedrunner', 'finished': 1, 'paused': 1, 'playing': 1},
      });
      expect(shown, isNot(contains(PlayerTypeCard)));
      expect(shown, contains(GameStatusCard));
    });

    test('rating skips when null', () {
      expect(types({...sampleWrappedJson(), 'rating': null}), isNot(contains(RatingCard)));
    });

    test("friends' hours skip when null or without a rival", () {
      expect(types({...sampleWrappedJson(), 'friends_hours': null}), isNot(contains(FriendsHoursCard)));
      expect(
        types({
          ...sampleWrappedJson(),
          'friends_hours': {
            'user_rank': 1,
            'friends_beaten': 0,
            'friends_counted': 0,
            'leaderboard': [leaderboardEntry('u1', 'Aljohara', 10, 1, me: true)],
          },
        }),
        isNot(contains(FriendsHoursCard)),
      );
    });

    test('gaming twin skips without similar_friend or me', () {
      expect(types({...sampleWrappedJson(), 'similar_friend': null}), isNot(contains(GamingTwinCard)));
      expect(types({...sampleWrappedJson(), 'me': null}), isNot(contains(GamingTwinCard)));
    });
  });

  group('player type copy', () {
    final expected = {
      PlayerType.creditsChaser: ('CREDITS CHASER', 'Once you start a game, you see it all the way to the credits.'),
      PlayerType.foreverInProgress: (
        'FOREVER IN PROGRESS',
        "No rush to reach the ending. For you, it's all about the journey.",
      ),
      PlayerType.theCloser: ('THE CLOSER', 'You like to finish what you start. Your stories reach their ending.'),
      PlayerType.theJuggler: ('THE JUGGLER', "Why stick to one? You'd rather juggle a few games at once."),
      PlayerType.saveAndQuit: ('SAVE & QUIT', "You play at your own pace, pausing and coming back when you're ready."),
    };
    for (final MapEntry(key: type, value: (name, reason)) in expected.entries) {
      test(type.key, () {
        expect(playerTypeName(type), name);
        expect(playerTypeReason(type), reason);
      });
    }

    test('reasons describe the habit without counts', () {
      for (final type in PlayerType.values) {
        expect(playerTypeReason(type), isNot(matches(RegExp(r'\d'))), reason: type.key);
      }
    });

    test('never says play style or personality', () {
      final all = [
        kPlayerTypeEyebrow,
        for (final type in PlayerType.values) ...[playerTypeName(type), playerTypeReason(type)],
      ].join(' ').toLowerCase();
      expect(all, isNot(contains('play style')));
      expect(all, isNot(contains('personality')));
    });

    test('lights the matching status bar', () {
      expect(highlightedBar(PlayerType.theCloser), StatusBar.completed);
      expect(highlightedBar(PlayerType.creditsChaser), StatusBar.completed);
      expect(highlightedBar(PlayerType.theJuggler), StatusBar.playing);
      expect(highlightedBar(PlayerType.saveAndQuit), StatusBar.paused);
      expect(highlightedBar(PlayerType.foreverInProgress), isNull);
    });
  });

  group('rating copy', () {
    WrappedRating rating(RaterType? type, double? gap) =>
        WrappedRating(ratedGames: 11, average: 7.4, raterType: type, averageGap: gap);

    test('tough critic', () {
      final r = rating(RaterType.toughCritic, -0.8);
      expect(ratingHeadline(r), 'TOUGH CRITIC');
      expect(ratingEyebrow(r), 'YOUR RATINGS');
      expect(ratingLine(r), 'You rate games 0.8★ lower than other players, on average.');
    });

    test('generous critic', () {
      final r = rating(RaterType.generousCritic, 1.25);
      expect(ratingHeadline(r), 'GENEROUS CRITIC');
      expect(ratingLine(r), 'You rate games 1.3★ higher than other players, on average.');
    });

    test('fair judge', () {
      final r = rating(RaterType.fairJudge, 0.2);
      expect(ratingHeadline(r), 'FAIR JUDGE');
      expect(ratingLine(r), 'Your scores land within half a star of other players.');
    });

    test('no rater type', () {
      final r = rating(null, null);
      expect(ratingHeadline(r), 'YOUR RATINGS');
      expect(ratingEyebrow(r), '11 GAMES RATED');
      expect(ratingLine(r), isNull);
    });

    test('breakdown buckets two scores per star', () {
      final r = WrappedRating.fromJson(sampleWrappedJson()['rating'] as Map<String, dynamic>);
      // 1★ = 1+2, 2★ = 3+4, 3★ = 5+6, 4★ = 7+8, 5★ = 9+10
      expect(r.starCounts, [0, 1, 3, 5, 2]);
      expect(r.averageStars, closeTo(3.7, 1e-9));
    });

    test('breakdown tolerates missing scores', () {
      expect(
        WrappedRating.fromJson({
          'rated_games': 1,
          'average': 10,
          'breakdown': {'10': 1},
        }).starCounts,
        [0, 0, 0, 0, 1],
      );
      expect(WrappedRating.fromJson({'rated_games': 0, 'average': 0}).starCounts, [0, 0, 0, 0, 0]);
    });
  });

  group("friends' hours", () {
    WrappedFriendsHours board(List<Map<String, dynamic>> entries) => WrappedFriendsHours.fromJson({
      'user_rank': 1,
      'friends_beaten': 0,
      'friends_counted': entries.length - 1,
      'leaderboard': entries,
    });

    test('rival is the leader when the user is not #1', () {
      final stats = board([
        leaderboardEntry('u2', 'Sara', 240.5, 1),
        leaderboardEntry('u1', 'Me', 214.5, 2, me: true),
        leaderboardEntry('u4', 'Reem', 120, 3),
      ]);
      expect(stats.rival!.user.username, 'Sara');
      expect(stats.me!.user.username, 'Me');
    });

    test('rival is the runner-up when the user is #1', () {
      final stats = board([
        leaderboardEntry('u1', 'Me', 300, 1, me: true),
        leaderboardEntry('u4', 'Reem', 120, 3),
        leaderboardEntry('u2', 'Sara', 240.5, 2),
      ]);
      expect(stats.rival!.user.username, 'Sara');
    });

    const sara = WrappedUser(userId: 'u2', username: 'Sara');

    test('win', () {
      final outcome = hoursOutcome(250, 240.5);
      expect(outcome, HoursOutcome.win);
      expect(friendsHoursHeadline(outcome, sara), 'YOU WIN');
      expect(friendsHoursLine(outcome, sara, 250, 240.5), 'You out-played Sara by 9.5 hours.');
    });

    test('loss', () {
      final outcome = hoursOutcome(214.5, 240.5);
      expect(outcome, HoursOutcome.loss);
      expect(friendsHoursHeadline(outcome, sara), 'SARA WINS');
      expect(friendsHoursLine(outcome, sara, 214.5, 240.5), 'Sara out-played you by 26 hours.');
    });

    test('tie', () {
      final outcome = hoursOutcome(120, 120);
      expect(outcome, HoursOutcome.tie);
      expect(friendsHoursHeadline(outcome, sara), 'DEAD HEAT');
      expect(friendsHoursLine(outcome, sara, 120, 120), 'You and Sara both played 120 hours.');
    });

    test('rank counts the user among friends', () {
      expect(yourRankValue(const WrappedFriendsHours(userRank: 2, friendsBeaten: 3, friendsCounted: 4)), '#2 of 5');
    });

    test('hourglass fills: leader full, any hours at least 6%', () {
      final (mine, rivals) = hourglassFills(214.5, 240.5);
      expect(mine, closeTo(0.892, 0.001));
      expect(rivals, 1.0);
      expect(hourglassFills(500, 1), (1.0, 0.06));
      expect(hourglassFills(0, 10), (0.0, 1.0));
      expect(hourglassFills(0, 0), (0.0, 0.0));
    });
  });

  group('reduced motion jumps to the final frame', () {
    final data = WrappedResponse.fromJson(sampleWrappedJson());
    final finals = <String, (Widget, List<String>)>{
      'trophies': (TrophiesCard(count: 14, trophies: data.trophies), ['14 EARNED', 'Lord of the Frenzied Flame']),
      'player type': (
        PlayerTypeCard(type: PlayerType.theCloser, style: data.playStyle!),
        ['THE CLOSER', 'You like to finish what you start. Your stories reach their ending.'],
      ),
      'game status': (GameStatusCard(style: data.playStyle!), ['14 GAMES', '9', '3', '2']),
      'rating': (RatingCard(rating: data.rating!), ['TOUGH CRITIC', '3.7', 'average across 11 games']),
      "friends' hours": (
        FriendsHoursCard(stats: data.friendsHours!, me: data.friendsHours!.me!, rival: data.friendsHours!.rival!),
        ['SARA WINS', '214.5 hours', '240.5 hours', '#2 of 5'],
      ),
      'gaming twin': (GamingTwinCard(me: data.me!, friend: data.similarFriend!), ['NORA', '87%', 'RPG · Adventure']),
    };
    for (final MapEntry(key: name, value: (card, texts)) in finals.entries) {
      testWidgets(name, (tester) async {
        await tester.pumpWidget(_app(card, disableAnimations: true));
        await tester.pump();
        for (final text in texts) {
          expect(find.text(text), findsWidgets, reason: text);
        }
        expect(tester.hasRunningAnimations, isFalse);
      });
    }
  });

  testWidgets('the trophy list scrolls vertically without turning the page', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844) * 2
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    // Without cards 1–5, so the trophies card is the first page.
    final json = {
      ...sampleWrappedJson(),
      'total_hours': null,
      'games_played': null,
      'top_games': null,
      'top_online_game': null,
    };
    await tester.pumpWidget(_app(WrappedScreen(data: WrappedResponse.fromJson(json)), disableAnimations: true));
    await tester.pumpAndSettle();

    final list = find.byType(ListView);
    final scrollable = find.descendant(of: list, matching: find.byType(Scrollable));
    await tester.drag(list, const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(tester.state<ScrollableState>(scrollable).position.pixels, greaterThan(0), reason: 'the list scrolled');
    expect(find.byType(TrophiesCard), findsOneWidget, reason: 'still on the trophies page');

    await tester.drag(list, const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('THE CLOSER'), findsOneWidget, reason: 'a horizontal swipe on the list turns the page');
  });

  testWidgets('rating hides the breakdown when the server sends none', (tester) async {
    const rating = WrappedRating(ratedGames: 4, average: 7, raterType: RaterType.fairJudge, averageGap: 0.1);
    await tester.pumpWidget(_app(const RatingCard(rating: rating), disableAnimations: true));
    await tester.pump();
    expect(find.text('3.5'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  group('cards 1–5 copy', () {
    test('total hours headline counts with the final decimals and unit', () {
      expect(totalHoursHeadline(214.5, 214.5), '214.5 HOURS');
      expect(totalHoursHeadline(100, 214.5), '100.0 HOURS');
      expect(totalHoursHeadline(1, 1), '1 HOUR');
    });

    test('total hours line shows days from 48 hours', () {
      expect(totalHoursLine(214.5, 2026), "That's 8 full days of gaming in 2026.");
      expect(totalHoursLine(48, 2026), "That's 2 full days of gaming in 2026.");
      expect(totalHoursLine(47.9, 2026), 'Every hour you logged in 2026.');
    });

    test('games played line', () {
      expect(gamesPlayedUnit(1), 'GAME');
      expect(gamesPlayedUnit(18), 'GAMES');
      expect(gamesPlayedLine(1), 'One world, fully explored.');
      expect(gamesPlayedLine(18), '18 different worlds explored this year.');
    });

    test('share of year is hidden without a total', () {
      expect(shareOfYear(96, 214.5), '45%');
      expect(shareOfYear(96, null), isNull);
      expect(shareOfYear(96, 0), isNull);
    });

    test('top games headline', () => expect(topGamesHeadline(2), 'TOP 2'));
  });

  testWidgets('featured game shows hours and share of the year', (tester) async {
    final game = WrappedGame.fromJson(_game(1, 'Elden Ring', 96));
    await tester.pumpWidget(
      _app(FeaturedGameCard(eyebrow: kTopGameEyebrow, game: game, totalHours: 214.5), disableAnimations: true),
    );
    await tester.pump();
    for (final text in ['YOUR #1 GAME', 'ELDEN RING', 'HOURS PLAYED', '96', 'OF YOUR YEAR', '45%']) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
  });

  testWidgets('featured game hides the share without a total', (tester) async {
    final game = WrappedGame.fromJson(_game(1, 'Elden Ring', 96));
    await tester.pumpWidget(
      _app(FeaturedGameCard(eyebrow: kTopOnlineGameEyebrow, game: game), disableAnimations: true),
    );
    await tester.pump();
    expect(find.text('YOUR TOP ONLINE GAME'), findsOneWidget);
    expect(find.text('OF YOUR YEAR'), findsNothing);
  });
}
