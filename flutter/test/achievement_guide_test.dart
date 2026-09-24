import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/models/achievement_guide.dart';
import 'package:loadout/screens/game/achievement_guide_screen.dart';

// The fixture is a slice of a REAL response from GET /games/:id/achievement-guide
// (Fallout: New Vegas: two phases, a tense/ordinal-normalized level ladder, a DLC
// ladder, LLM steps), with image URLs removed so no network plugin is needed.
Map<String, dynamic> loadFixture() =>
    jsonDecode(File('test/fixtures/guide_fnv_sample.json').readAsStringSync()) as Map<String, dynamic>;

Future<void> pumpView(WidgetTester tester, AchievementGuide guide) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(400, 1400);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: AchievementGuideView(guide: guide))),
  );
}

void main() {
  group('AchievementGuide model', () {
    test('parses a real response: order, phases, ladders, dlc', () {
      final guide = AchievementGuide.fromJson(loadFixture());

      expect(guide.nodes.map((n) => n.order).toList(), [1, 4, 47, 69]);
      expect(guide.phases.map((p) => p.key).toList(), ['base', 'dlc']);
      expect(guide.hasMultiplePhases, isTrue);

      final ladder = guide.nodes[1];
      expect(ladder.isLadder, isTrue);
      expect(ladder.name, 'New Kid → Up and Comer → The Boss', reason: 'named by the real achievements, not the shared description');
      expect(ladder.tiers.map((t) => t.label).toList(), ['10', '20', '30']);
      expect(ladder.tiers.first.trophies.first.name, 'New Kid');

      expect(guide.nodes[2].phase, 'dlc');
      expect(guide.nodes[3].phase, 'dlc');
      expect(guide.nodes[3].isLadder, isTrue);
    });

    test('LLM steps are hidden when low-confidence or merely restating the name', () {
      expect(visibleSteps(name: 'Boss', steps: ['Defeat it'], confidence: 'low'), isEmpty);
      expect(visibleSteps(name: 'Boss', steps: ['Complete Boss.'], confidence: 'high'), isEmpty);
      expect(visibleSteps(name: "Ain't That a Kick", steps: ["Complete Ain't That a Kick."], confidence: 'high'), isEmpty);
      expect(visibleSteps(name: 'Boss', steps: ['Defeat the boss', 'Loot the chest'], confidence: 'high'),
          ['Defeat the boss', 'Loot the chest']);
      expect(visibleSteps(name: 'Boss', steps: ['Defeat the boss'], confidence: null), ['Defeat the boss']);
    });

    test('steps that merely restate the description are dropped (tense-tolerant), useful ones kept', () {
      expect(visibleSteps(name: 'New Kid', description: 'Reached 10th level.', steps: ['Reach 10th level.'], confidence: 'high'), isEmpty);
      expect(visibleSteps(name: 'Zion', description: 'Arrive at Zion.', steps: ['Arrive at Zion.'], confidence: 'high'), isEmpty);
      expect(visibleSteps(name: 'Pest Control', description: 'Destroy all monster nests in Velen.',
          steps: ['Locate the nests on the map', 'Destroy them with bombs'], confidence: 'high'),
          ['Locate the nests on the map', 'Destroy them with bombs']);
    });

    test('the real fixture: redundant hints are filtered out at parse time', () {
      final guide = AchievementGuide.fromJson(loadFixture());
      final ladder = guide.nodes[1];
      for (final t in ladder.tiers) {
        for (final tr in t.trophies) {
          expect(tr.steps, isEmpty, reason: '${tr.name}: hint only repeated the description');
        }
      }
      expect(guide.nodes[2].steps, isEmpty, reason: '"Arrive at Zion." repeated the description');
    });

    test('parsing is defensive: missing/odd fields never throw', () {
      expect(AchievementGuide.fromJson({}).nodes, isEmpty);
      final g = AchievementGuide.fromJson({
        'nodes': [
          {'order': 2, 'id': 7, 'name': 'B', 'percent': '12.5', 'kind': 'ladder', 'suspectedCategory': 'nonsense'},
          {'order': 1, 'name': 'A'},
          'not a map',
        ],
      });
      expect(g.nodes.map((n) => n.name).toList(), ['A', 'B'], reason: 'sorted by order, junk skipped');
      expect(g.nodes[1].percent, 12.5, reason: 'numeric strings are accepted');
      expect(g.nodes[1].isLadder, isFalse, reason: 'a ladder with no tiers is just a trophy');
      expect(g.nodes[1].suspectedCategory, isNull, reason: 'only dlc/online are meaningful');
      expect(g.hasMultiplePhases, isFalse);
    });
  });

  group('AchievementGuideView', () {
    testWidgets('shows phase headers for Base game and DLC, with a DLC ownership hint', (tester) async {
      await pumpView(tester, AchievementGuide.fromJson(loadFixture()));

      expect(find.byKey(const Key('guide-phase-base')), findsOneWidget);
      expect(find.byKey(const Key('guide-phase-dlc')), findsOneWidget);
      expect(find.text('Base game'), findsOneWidget);
      expect(find.text('DLC'), findsOneWidget);
      expect(find.text('May require DLC or expansion content'), findsOneWidget);
      // The DLC header sits below the base-game nodes.
      expect(tester.getTopLeft(find.byKey(const Key('guide-phase-dlc'))).dy,
          greaterThan(tester.getTopLeft(find.byKey(const Key('guide-node-4'))).dy));
    });

    testWidgets('a single-phase guide has no headers', (tester) async {
      final json = loadFixture();
      json['nodes'] = (json['nodes'] as List).take(2).toList();
      json['phases'] = [(json['phases'] as List).first];
      await pumpView(tester, AchievementGuide.fromJson(json));

      expect(find.byKey(const Key('guide-phase-base')), findsNothing);
      expect(find.byKey(const Key('guide-node-1')), findsOneWidget);
    });

    testWidgets('every stop is labelled, and a ladder shows its tier count', (tester) async {
      await pumpView(tester, AchievementGuide.fromJson(loadFixture()));

      expect(find.text("Ain't That a Kick in the Head"), findsOneWidget);
      expect(find.text('New Kid → Up and Comer → The Boss'), findsOneWidget);
      expect(find.byIcon(Icons.layers), findsNWidgets(2), reason: 'both ladders carry a tier badge');
      expect(find.text('3'), findsNWidgets(2));
    });

    testWidgets('tapping a ladder opens its tiers in order, with why-here', (tester) async {
      await pumpView(tester, AchievementGuide.fromJson(loadFixture()));

      await tester.tap(find.byKey(const Key('guide-node-4')));
      await tester.pumpAndSettle();

      expect(find.text('Earn these in order'), findsOneWidget);
      final y10 = tester.getTopLeft(find.byKey(const Key('guide-tier-10'))).dy;
      final y20 = tester.getTopLeft(find.byKey(const Key('guide-tier-20'))).dy;
      final y30 = tester.getTopLeft(find.byKey(const Key('guide-tier-30'))).dy;
      expect(y10 < y20 && y20 < y30, isTrue, reason: 'tiers listed ascending');
      expect(find.text('New Kid'), findsOneWidget);
      expect(find.text('Up and Comer'), findsOneWidget);
      expect(find.text('The Boss'), findsOneWidget);
      expect(find.text('Step 4: New Kid → Up and Comer → The Boss'), findsOneWidget);
      expect(find.text('Why here?'), findsNothing);
      expect(find.textContaining('placed by'), findsNothing);
    });

    testWidgets('a DLC stop is tagged with its phase in the sheet', (tester) async {
      await pumpView(tester, AchievementGuide.fromJson(loadFixture()));

      await tester.tap(find.byKey(const Key('guide-node-47')));
      await tester.pumpAndSettle();

      expect(find.text('When We Remembered Zion'), findsWidgets);
      expect(find.text('DLC'), findsWidgets);
      expect(find.text('Why here?'), findsNothing);
    });

    testWidgets('steps render when confident and disappear when the model was not', (tester) async {
      final confident = loadFixture();
      final tiers = ((confident['nodes'] as List)[1] as Map)['tiers'] as List;
      ((tiers.first as Map)['trophies'] as List).first['steps'] = ['Level up by clearing quests', 'Check your perks'];
      await pumpView(tester, AchievementGuide.fromJson(confident));
      await tester.tap(find.byKey(const Key('guide-node-4')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('guide-steps')), findsOneWidget);
      expect(find.text('Level up by clearing quests'), findsOneWidget);
      expect(find.text('Check your perks'), findsOneWidget);

      final uncertain = loadFixture();
      for (final n in uncertain['nodes'] as List) {
        (n as Map)['confidence'] = 'low';
        if (n['tiers'] != null) {
          for (final t in n['tiers'] as List) {
            for (final tr in (t as Map)['trophies'] as List) {
              (tr as Map)['confidence'] = 'low';
            }
          }
        }
      }
      await tester.pumpWidget(const SizedBox());
      await pumpView(tester, AchievementGuide.fromJson(uncertain));
      await tester.tap(find.byKey(const Key('guide-node-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('guide-steps')), findsNothing);
    });

    testWidgets('hidden trophies get a badge and chip; a suspected category gets a soft note', (tester) async {
      final json = loadFixture();
      final first = (json['nodes'] as List).first as Map;
      first['hidden'] = true;
      first['suspectedCategory'] = 'online';
      await pumpView(tester, AchievementGuide.fromJson(json));

      expect(find.byKey(const Key('guide-hidden-badge')), findsOneWidget);
      await tester.tap(find.byKey(const Key('guide-node-1')));
      await tester.pumpAndSettle();
      expect(find.text('Hidden'), findsOneWidget);
      expect(find.byKey(const Key('guide-suspected-note')), findsOneWidget);
      expect(find.textContaining('online or multiplayer play'), findsOneWidget);
    });
  });
}
