import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/models/archetype.dart';
import 'package:loadout/services/archetype_service.dart';
import 'package:loadout/widgets/archetype_badge.dart';
import 'package:loadout/widgets/archetype_emblem.dart';

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

  // ── Badge ──────────────────────────────────────────────────────────────────

  Finder badge() => find.byKey(const ValueKey('archetype-badge'));
  Iterable<ArchetypeEmblem> emblems(WidgetTester t) => t.widgetList<ArchetypeEmblem>(find.byType(ArchetypeEmblem));

  testWidgets('normal badge: one 22px emblem, tooltip and screen-reader label with the match %', (tester) async {
    await tester.pumpWidget(app(ArchetypeBadge(archetype: Archetype.fromJson(mineJson))));
    final e = emblems(tester).single;
    expect((e.archetype, e.size, e.faded), ('Competitor', 22.0, false));
    expect(find.bySemanticsLabel('Archetype: Competitor, 48% match. Double-tap for details'), findsOneWidget);
    expect(find.byType(Tooltip), findsOneWidget);
    expect(tester.widget<Tooltip>(find.byType(Tooltip)).message, 'Competitor · 48% match');
  });

  testWidgets('the tooltip shows on long-press', (tester) async {
    await tester.pumpWidget(app(ArchetypeBadge(archetype: Archetype.fromJson(mineJson))));
    await tester.longPress(badge());
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Competitor · 48% match'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('blend badge: primary 22px + secondary 16px at 75%, 3px apart', (tester) async {
    await tester.pumpWidget(app(ArchetypeBadge(archetype: Archetype.fromJson(blendJson))));
    final e = emblems(tester).toList();
    expect([for (final x in e) (x.archetype, x.size, x.opacity)],
        [('Competitor', 22.0, 1.0), ('Completionist', 16.0, 0.75)]);
    final gap = tester.getTopLeft(find.byType(ArchetypeEmblem).at(1)).dx - tester.getTopRight(find.byType(ArchetypeEmblem).at(0)).dx;
    expect(gap, 3);
    expect(archetypeBadgeTooltip(Archetype.fromJson(blendJson)), 'Competitor, with a touch of Completionist · 35% match');
  });

  testWidgets('closest-match badge: faded emblem in a dashed container', (tester) async {
    final a = Archetype.fromJson(atypicalJson);
    await tester.pumpWidget(app(ArchetypeBadge(archetype: a)));
    expect(emblems(tester).single.faded, isTrue);
    final visual = tester.widget<Container>(find.byKey(const ValueKey('archetype-badge-visual')));
    expect((visual.decoration as BoxDecoration).color, const Color(0xFF16161E));
    expect((visual.decoration as BoxDecoration).border, isNull, reason: 'the dashed border is painted, not a solid one');
    expect(archetypeBadgeTooltip(a), 'Closest match: Completionist');
    expect(find.bySemanticsLabel('Closest match: Completionist. Double-tap for details'), findsOneWidget);
  });

  testWidgets('locked badge on your own profile: lock and 3/5; hidden on a friend\'s', (tester) async {
    final a = Archetype.fromJson(lockedJson);
    await tester.pumpWidget(app(ArchetypeBadge(archetype: a)));
    expect(find.text('3/5'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.bySemanticsLabel('Archetype locked: log 2 more games'), findsOneWidget);
    await tester.pumpWidget(app(ArchetypeBadge(archetype: a, friendView: true)));
    expect(badge(), findsNothing);
    expect(find.text('3/5'), findsNothing);
  });

  testWidgets('loading shows a 32×30 skeleton; an error hides the badge', (tester) async {
    await tester.pumpWidget(app(const ArchetypeBadge(loading: true)));
    expect(find.byType(ArchetypeEmblem), findsNothing);
    expect(find.byWidgetPredicate((w) => w is SizedBox && w.width == 32 && w.height == 30), findsOneWidget);
    await tester.pumpWidget(app(ArchetypeBadge(archetype: Archetype.fromJson(mineJson), error: 'boom')));
    expect(badge(), findsNothing);
    expect(find.byType(ArchetypeEmblem), findsNothing);
  });

  testWidgets('the tap target is at least 44×44 while the badge itself stays small', (tester) async {
    for (final json in [mineJson, blendJson, atypicalJson, lockedJson]) {
      await tester.pumpWidget(app(Row(children: [ArchetypeBadge(archetype: Archetype.fromJson(json))])));
      final hit = tester.getSize(badge());
      expect(hit.width, greaterThanOrEqualTo(44));
      expect(hit.height, greaterThanOrEqualTo(44));
      expect(tester.getSize(find.byKey(const ValueKey('archetype-badge-visual'))).height, lessThan(44));
    }
  });

  testWidgets("a friend's badge never shows a % in its tooltip or label", (tester) async {
    await tester.pumpWidget(app(ArchetypeBadge(archetype: Archetype.fromJson(friendJson), friendView: true)));
    expect(tester.widget<Tooltip>(find.byType(Tooltip)).message, 'Explorer');
    expect(find.bySemanticsLabel('Archetype: Explorer. Double-tap for details'), findsOneWidget);
  });

  // ── Details sheet ──────────────────────────────────────────────────────────

  Future<void> openSheet(WidgetTester tester, Map<String, dynamic> json, {bool friendView = false}) async {
    await tester.pumpWidget(app(ArchetypeBadge(archetype: Archetype.fromJson(json), friendView: friendView)));
    await tester.tap(badge());
    await tester.pumpAndSettle();
    expect(find.byType(ArchetypeDetailsSheet), findsOneWidget);
  }

  Finder inSheet(Finder f) => find.descendant(of: find.byType(ArchetypeDetailsSheet), matching: f);

  testWidgets('normal sheet: 56px emblem, name, family, the match % and the description; full mix collapsed', (tester) async {
    await openSheet(tester, mineJson);
    expect(tester.widget<ArchetypeEmblem>(inSheet(find.byType(ArchetypeEmblem)).first).size, 56);
    expect(inSheet(find.text('Competitor')), findsOneWidget);
    expect(inSheet(find.text('Committed player')), findsOneWidget);
    expect(inSheet(find.text('48% match')), findsOneWidget);
    expect(inSheet(find.text('Online, competitive, and in it for the long sessions.')), findsOneWidget);
    expect(inSheet(find.text('See your full mix')), findsOneWidget);
    expect(inSheet(find.text('22%')), findsNothing, reason: 'the full mix starts collapsed');
  });

  testWidgets('"See your full mix" expands to six bars (highest first) and the two reasons', (tester) async {
    await openSheet(tester, mineJson);
    await tester.tap(inSheet(find.text('See your full mix')));
    await tester.pumpAndSettle();
    final percents = ['48%', '22%', '18%', '7%', '3%', '2%'];
    for (final p in percents) {
      expect(inSheet(find.text(p)), findsOneWidget);
    }
    final ys = [for (final p in percents) tester.getTopLeft(inSheet(find.text(p))).dy];
    expect(ys, [...ys]..sort());
    expect(find.text('A typical game gets about 41 hours from you'), findsOneWidget);
    expect(find.text('You average about 168 hours in each month you play'), findsOneWidget);
  });

  testWidgets('blend sheet: the blend title, both percentages, both descriptions with the primary first', (tester) async {
    await openSheet(tester, blendJson);
    expect(inSheet(find.text('Competitor, with a touch of Completionist')), findsOneWidget);
    expect(inSheet(find.text('Competitor 35% · Completionist 25%')), findsOneWidget);
    final primary = inSheet(find.textContaining('Online, competitive', findRichText: true));
    final secondary = inSheet(find.textContaining('You see more of your games', findRichText: true));
    expect(primary, findsOneWidget);
    expect(secondary, findsOneWidget);
    expect(tester.getTopLeft(primary).dy, lessThan(tester.getTopLeft(secondary).dy));
  });

  testWidgets('closest-match sheet: title, its %, description and the honesty line', (tester) async {
    await openSheet(tester, atypicalJson);
    expect(inSheet(find.text('Closest match: Completionist')), findsOneWidget);
    expect(inSheet(find.text('81% closest type')), findsOneWidget);
    expect(inSheet(find.text("Your playstyle doesn't closely match any one type yet.")), findsOneWidget);
    expect(tester.widget<ArchetypeEmblem>(inSheet(find.byType(ArchetypeEmblem)).first).faded, isTrue);
  });

  testWidgets('locked sheet: games left and 3/5 progress, no mix', (tester) async {
    await openSheet(tester, lockedJson);
    expect(inSheet(find.text('Log 2 more games to unlock your archetype')), findsOneWidget);
    expect(inSheet(find.text('3/5 games logged')), findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(inSheet(find.byType(LinearProgressIndicator))).value, closeTo(0.6, 1e-9));
    expect(inSheet(find.text('See your full mix')), findsNothing);
  });

  testWidgets("friend sheet: emblem, name, family and description only, never a percentage", (tester) async {
    final friend = {...friendJson, 'family': 'Light'};
    await openSheet(tester, friend, friendView: true);
    expect(inSheet(find.text('Explorer')), findsOneWidget);
    expect(inSheet(find.text('Light player')), findsOneWidget);
    expect(inSheet(find.text('Always trying something new, across lots of genres.')), findsOneWidget);
    expect(inSheet(find.textContaining('%')), findsNothing);
    expect(inSheet(find.text('See your full mix')), findsNothing);
    // Even a full own payload shown in friend view leaks nothing
    Navigator.of(tester.element(find.byType(ArchetypeDetailsSheet))).pop();
    await tester.pumpAndSettle();
    await openSheet(tester, mineJson, friendView: true);
    expect(inSheet(find.textContaining('%')), findsNothing);
    expect(inSheet(find.text('See your full mix')), findsNothing);
  });

  test('family labels', () {
    expect(familyLabel('Light'), 'Light player');
    expect(familyLabel('One-game'), 'One-game player');
    expect(familyLabel(null), isNull);
    expect(archetypeColour('Explorer'), kLightFamily);
    expect(archetypeColour('Competitor'), kCommittedFamily);
    expect(archetypeColour('The Main'), kOneGameFamily);
  });

  test('every emblem path parses', () {
    expect(archetypeIconPaths.keys.toSet(), archetypeFamily.keys.toSet());
    // Path.getBounds() includes arc control points, so sample the drawn outline instead
    for (final entry in archetypeIconPaths.entries) {
      for (final metric in parseSvgPath(entry.value).computeMetrics()) {
        for (double t = 0; t <= metric.length; t += 0.25) {
          final pos = metric.getTangentForOffset(t)!.position;
          expect(pos.dx, inInclusiveRange(0, 24), reason: entry.key);
          expect(pos.dy, inInclusiveRange(0, 24), reason: entry.key);
        }
      }
    }
    expect(() => parseSvgPath('M3 12a9 9'), throwsFormatException);
    expect(() => parseSvgPath('Q1 2 3 4'), throwsFormatException);
    final hex = parseSvgPath('M12 1.4l9.2 5.3v10.6L12 22.6l-9.2-5.3V6.7z');
    final b = hex.getBounds();
    expect(b.left, closeTo(2.8, 1e-6));
    expect(b.right, closeTo(21.2, 1e-6));
    expect(b.top, closeTo(1.4, 1e-6));
    expect(b.bottom, closeTo(22.6, 1e-6));
    final circle = parseSvgPath('M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0').getBounds();
    expect(circle.width, closeTo(18, 0.05));
    expect(circle.height, closeTo(18, 0.05));
  });

  test('error messages per status', () {
    expect(archetypeErrorMessage(503), contains('short break'));
    expect(archetypeErrorMessage(502), contains("Couldn't reach"));
    expect(archetypeErrorMessage(500), "Couldn't load the archetype.");
  });
}
