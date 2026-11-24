import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/models/archetype.dart';
import 'package:loadout/services/archetype_service.dart';
import 'package:loadout/widgets/archetype_card.dart';

const _desc = {
  'Competitor': 'Online, competitive, and in it for the long sessions.',
  'Devotee': 'One game you keep coming back to, over and over.',
  'The Main': 'One online game has most of your hours.',
  'Completionist': 'You see more of your games through than most players, and pick up trophies on the way.',
  'Explorer': 'Always trying something new, across lots of genres.',
  'Casual': 'You play when life gives you time.',
};

List<Map<String, Object>> _scores(List<(String, int)> s) =>
    [for (final (n, p) in s) {'archetype': n, 'description': _desc[n]!, 'percent': p}];

/// The shape GET /users/me/archetype returns with model 2.0.1: a clear Competitor
final mineJson = {
  'archetype': 'Competitor',
  'description': _desc['Competitor'],
  'family': 'Committed',
  'atypical': false,
  'blend': null,
  'scores': _scores([('Competitor', 48), ('Devotee', 22), ('The Main', 18), ('Completionist', 7), ('Explorer', 3), ('Casual', 2)]),
  'reasons': ['A typical game gets about 41 hours from you', 'You average about 168 hours in each month you play'],
  'games_played': 12,
  'model_version': '2.0.1',
};

/// Top two within 10 points: a blend
final blendJson = {
  ...mineJson,
  'scores': _scores([('Competitor', 35), ('Completionist', 25), ('The Main', 18), ('Devotee', 12), ('Explorer', 6), ('Casual', 4)]),
  'blend': {'primary': 'Competitor', 'secondary': 'Completionist'},
};

/// Far from every type: closest match only, no %, no blend
final atypicalJson = {
  ...mineJson,
  'archetype': 'Completionist',
  'description': _desc['Completionist'],
  'atypical': true,
  'scores': _scores([('Completionist', 81), ('Competitor', 7), ('The Main', 5), ('Devotee', 4), ('Explorer', 2), ('Casual', 1)]),
  'reasons': ["You've unlocked 88% of the trophies in your games", "You've finished 4 of your 5 games"],
  'games_played': 5,
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

  group('2.0.1 fields', () {
    test('parse family, blend and atypical', () {
      final a = Archetype.fromJson(mineJson);
      expect(a.family, 'Committed');
      expect(a.blend, isNull);
      expect(a.atypical, isFalse);
      final b = Archetype.fromJson(blendJson);
      expect(b.blend!.label, 'Competitor, with a touch of Completionist');
      expect(Archetype.fromJson(atypicalJson).atypical, isTrue);
    });

    test('a 1.0.0 response (no family, blend or atypical) still parses', () {
      final old = Map<String, dynamic>.from(mineJson)..remove('family')..remove('atypical')..remove('blend');
      final a = Archetype.fromJson(old);
      expect(a.family, isNull);
      expect(a.blend, isNull);
      expect(a.atypical, isFalse);
    });

    test('an atypical response never keeps a blend, even if one is sent', () {
      final both = {...atypicalJson, 'blend': {'primary': 'Completionist', 'secondary': 'Competitor'}};
      expect(Archetype.fromJson(both).blend, isNull);
    });
  });

  testWidgets('normal card: "<Archetype> · <top %>% match", description, family, tap hint', (tester) async {
    await tester.pumpWidget(app(ArchetypeCard(archetype: Archetype.fromJson(mineJson))));
    expect(find.text('Competitor · 48% match'), findsOneWidget);
    expect(find.text('Online, competitive, and in it for the long sessions.'), findsOneWidget);
    expect(find.text('Committed family'), findsOneWidget);
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

  testWidgets('the family label is hidden when family is null', (tester) async {
    final noFamily = Map<String, dynamic>.from(mineJson)..remove('family');
    await tester.pumpWidget(app(ArchetypeCard(archetype: Archetype.fromJson(noFamily))));
    expect(find.text('Competitor · 48% match'), findsOneWidget);
    expect(find.textContaining('family'), findsNothing);
  });

  testWidgets('blend card: "<primary>, with a touch of <secondary>", top %, primary description', (tester) async {
    await tester.pumpWidget(app(ArchetypeCard(archetype: Archetype.fromJson(blendJson))));
    expect(find.text('Competitor, with a touch of Completionist'), findsOneWidget);
    expect(find.text('35% Competitor'), findsOneWidget);
    expect(find.text('Online, competitive, and in it for the long sessions.'), findsOneWidget);
    expect(find.textContaining('· 35% match'), findsNothing);
    await tester.tap(find.byType(ArchetypeCard));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(ArchetypeMixSheet), matching: find.text('Competitor, with a touch of Completionist')),
        findsOneWidget);
  });

  testWidgets('atypical card: "Closest match", no %, no blend, the honesty line; sheet says none is close', (tester) async {
    await tester.pumpWidget(app(ArchetypeCard(archetype: Archetype.fromJson(atypicalJson))));
    expect(find.text('Closest match: Completionist'), findsOneWidget);
    expect(find.text("Your playstyle doesn't closely match any one type yet."), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    expect(find.textContaining('with a touch of'), findsNothing);
    expect(find.textContaining('family'), findsNothing);
    expect(find.text('Tap to see your full mix'), findsOneWidget);

    await tester.tap(find.byType(ArchetypeCard));
    await tester.pumpAndSettle();
    final sheet = find.byType(ArchetypeMixSheet);
    expect(find.descendant(of: sheet, matching: find.text('Closest match: Completionist')), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('These show how close you are to each type; none is a close match.')),
        findsOneWidget);
    // All six bars, highest first, and the reasons
    for (final p in ['81%', '7%', '5%', '4%', '2%', '1%']) {
      expect(find.descendant(of: sheet, matching: find.text(p)), findsOneWidget);
    }
    expect(find.text("You've unlocked 88% of the trophies in your games"), findsOneWidget);
  });

  testWidgets('the normal sheet has no "none is a close match" line', (tester) async {
    await tester.pumpWidget(app(ArchetypeCard(archetype: Archetype.fromJson(mineJson))));
    await tester.tap(find.byType(ArchetypeCard));
    await tester.pumpAndSettle();
    expect(find.textContaining('none is a close match'), findsNothing);
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

  testWidgets("a friend's card ignores scores, family, blend and atypical even if they were somehow present", (tester) async {
    for (final json in [mineJson, blendJson, atypicalJson]) {
      await tester.pumpWidget(app(ArchetypeCard(archetype: Archetype.fromJson(json), friendView: true)));
      expect(find.text(json['archetype'] as String), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      expect(find.textContaining('family'), findsNothing);
      expect(find.textContaining('with a touch of'), findsNothing);
      expect(find.textContaining('Closest match'), findsNothing);
      expect(find.textContaining('closely match'), findsNothing);
    }
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
