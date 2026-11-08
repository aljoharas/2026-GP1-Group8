import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/models/archetype.dart';
import 'package:loadout/services/archetype_service.dart';
import 'package:loadout/widgets/archetype_card.dart';

/// The shape GET /users/me/archetype returns (a real response, 2026-11-07)
const mineJson = {
  'archetype': 'Competitor',
  'description': 'Online, competitive, and in it for the long sessions.',
  'scores': [
    {'archetype': 'Competitor', 'description': 'Online, competitive, and in it for the long sessions.', 'percent': 48},
    {'archetype': 'Devotee', 'description': 'One game you keep coming back to, over and over.', 'percent': 22},
    {'archetype': 'The Main', 'description': 'One online game has most of your hours.', 'percent': 18},
    {'archetype': 'Completionist', 'description': 'You finish what you start and chase the trophies.', 'percent': 7},
    {'archetype': 'Explorer', 'description': 'Always trying something new, across lots of genres.', 'percent': 3},
    {'archetype': 'Casual', 'description': 'You play when life gives you time.', 'percent': 2},
  ],
  'reasons': ['A typical game gets about 41 hours from you', 'You average about 168 hours in each month you play'],
  'games_played': 12,
  'model_version': '1.0.0',
};

const lockedJson = {'archetype': null, 'reason': 'not_enough_games', 'games_played': 3, 'min_games': 5};

const friendJson = {'archetype': 'Explorer', 'description': 'Always trying something new, across lots of genres.'};

Widget app(Widget child) => MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF0E0E12),
        body: Padding(padding: const EdgeInsets.all(18), child: child),
      ),
    );

void main() {
  group('Archetype.fromJson', () {
    test('parses the full mix, highest first', () {
      final a = Archetype.fromJson(mineJson);
      expect(a.name, 'Competitor');
      expect(a.topPercent, 48);
      expect(a.scores.map((s) => s.archetype), ['Competitor', 'Devotee', 'The Main', 'Completionist', 'Explorer', 'Casual']);
      expect(a.scores.fold<int>(0, (sum, s) => sum + s.percent), 100);
      expect(a.reasons, hasLength(2));
      expect(a.isLocked, isFalse);
    });

    test('sorts scores even when the server did not', () {
      final shuffled = Map<String, dynamic>.from(mineJson)
        ..['scores'] = (mineJson['scores'] as List).reversed.toList();
      expect(Archetype.fromJson(shuffled).scores.first.archetype, 'Competitor');
    });

    test('parses not enough games as locked', () {
      final a = Archetype.fromJson(lockedJson);
      expect(a.isLocked, isTrue);
      expect(a.gamesPlayed, 3);
      expect(a.minGames, 5);
    });

    test("a friend's view has no scores or reasons", () {
      final a = Archetype.fromJson(friendJson);
      expect(a.name, 'Explorer');
      expect(a.scores, isEmpty);
      expect(a.reasons, isEmpty);
      expect(a.topPercent, isNull);
    });
  });

  testWidgets('own card shows "<Archetype> · <top %>% match" and opens the full mix', (tester) async {
    await tester.pumpWidget(app(ArchetypeCard(archetype: Archetype.fromJson(mineJson))));
    expect(find.text('Competitor · 48% match'), findsOneWidget);
    expect(find.text('Online, competitive, and in it for the long sessions.'), findsOneWidget);
    expect(find.text('Tap to see your full mix'), findsOneWidget);

    await tester.tap(find.byType(ArchetypeCard));
    await tester.pumpAndSettle();
    expect(find.byType(ArchetypeMixSheet), findsOneWidget);
    for (final name in ['Competitor', 'Devotee', 'The Main', 'Completionist', 'Explorer', 'Casual']) {
      expect(find.descendant(of: find.byType(ArchetypeMixSheet), matching: find.text(name)), findsOneWidget);
    }
    for (final p in ['48%', '22%', '18%', '7%', '3%', '2%']) {
      expect(find.descendant(of: find.byType(ArchetypeMixSheet), matching: find.text(p)), findsOneWidget);
    }
    expect(find.text('A typical game gets about 41 hours from you'), findsOneWidget);
    expect(find.text('You average about 168 hours in each month you play'), findsOneWidget);
    expect(find.text('You play when life gives you time.'), findsOneWidget);
  });

  testWidgets('below 5 games the card asks for more logs and is not tappable', (tester) async {
    await tester.pumpWidget(app(ArchetypeCard(archetype: Archetype.fromJson(lockedJson))));
    expect(find.text('Log a few more games to unlock your archetype'), findsOneWidget);
    expect(find.text('3 of 5 games logged'), findsOneWidget);
    expect(find.text('Tap to see your full mix'), findsNothing);
    await tester.tap(find.byType(ArchetypeCard));
    await tester.pumpAndSettle();
    expect(find.byType(ArchetypeMixSheet), findsNothing);
  });

  testWidgets("a friend's card shows name and description only and never opens a mix", (tester) async {
    await tester.pumpWidget(app(ArchetypeCard(archetype: Archetype.fromJson(friendJson), friendView: true, username: 'sara')));
    expect(find.text('Explorer'), findsOneWidget);
    expect(find.text('Always trying something new, across lots of genres.'), findsOneWidget);
    expect(find.textContaining('% match'), findsNothing);
    expect(find.text('Tap to see your full mix'), findsNothing);
    await tester.tap(find.byType(ArchetypeCard));
    await tester.pumpAndSettle();
    expect(find.byType(ArchetypeMixSheet), findsNothing);
  });

  testWidgets("a friend's card ignores scores even if they were somehow present", (tester) async {
    await tester.pumpWidget(app(ArchetypeCard(archetype: Archetype.fromJson(mineJson), friendView: true)));
    expect(find.text('Competitor'), findsOneWidget);
    expect(find.textContaining('% match'), findsNothing);
  });

  testWidgets('loading shows placeholders, not text', (tester) async {
    await tester.pumpWidget(app(const ArchetypeCard(loading: true)));
    expect(find.text('PLAYER ARCHETYPE'), findsOneWidget);
    expect(find.textContaining('match'), findsNothing);
  });

  testWidgets('an error offers a retry', (tester) async {
    var retried = 0;
    await tester.pumpWidget(app(ArchetypeCard(error: archetypeErrorMessage(503), onRetry: () => retried++)));
    expect(find.text('Archetypes are taking a short break. Try again soon.'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(retried, 1);
  });

  test('error messages per status', () {
    expect(archetypeErrorMessage(503), contains('short break'));
    expect(archetypeErrorMessage(502), contains("Couldn't reach"));
    expect(archetypeErrorMessage(500), "Couldn't load the archetype.");
  });
}
