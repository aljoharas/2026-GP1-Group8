// Screenshots of the Player Archetype card in each state and of the full mix
// sheet, on a large phone and on a small one with larger text.
// Regenerate with: flutter test --update-goldens test/archetype_golden_test.dart
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/models/archetype.dart';
import 'package:loadout/services/archetype_service.dart';
import 'package:loadout/widgets/archetype_card.dart';

import 'archetype_test.dart' show mineJson, lockedJson, friendJson;
import 'golden_fonts.dart';

const _screens = [
  (name: '390x844', size: Size(390, 844), textScale: 1.0),
  (name: '360x640_text130', size: Size(360, 640), textScale: 1.3),
];

/// The card where it sits on a profile: under the tabs, above Currently Playing
Widget _profile(Widget card, double textScale) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: ThemeData(fontFamily: 'Roboto', brightness: Brightness.dark),
  // On every route, so the bottom sheet gets the larger text too
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(
    backgroundColor: const Color(0xFF0E0E12),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.only(top: 12),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 8, 18, 16),
            child: Row(
              children: [
                Text(
                  'Overview',
                  style: TextStyle(
                    color: Color(0xFFF0F0F0),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(width: 24),
                Text(
                  'Journal',
                  style: TextStyle(color: Color(0xFF6B6B80), fontSize: 14),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: card,
          ),
          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: Text(
              'Currently Playing',
              style: TextStyle(
                color: Color(0xFFF0F0F0),
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    ),
  ),
);

void main() {
  setUpAll(loadGoldenFonts);

  final states = <String, Widget>{
    'card': ArchetypeCard(archetype: Archetype.fromJson(mineJson)),
    'locked': ArchetypeCard(archetype: Archetype.fromJson(lockedJson)),
    'friend': ArchetypeCard(
      archetype: Archetype.fromJson(friendJson),
      friendView: true,
      username: 'sara',
    ),
    'loading': const ArchetypeCard(loading: true),
    'error_503': ArchetypeCard(
      error: archetypeErrorMessage(503),
      onRetry: () {},
    ),
  };

  for (final screen in _screens) {
    for (final entry in states.entries) {
      testWidgets('archetype ${entry.key} ${screen.name}', (tester) async {
        tester.view.physicalSize = screen.size * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_profile(entry.value, screen.textScale));
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            'goldens/archetype_${entry.key}_${screen.name}.png',
          ),
        );
      });
    }

    testWidgets('archetype mix sheet ${screen.name}', (tester) async {
      tester.view.physicalSize = screen.size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _profile(
          ArchetypeCard(archetype: Archetype.fromJson(mineJson)),
          screen.textScale,
        ),
      );
      await tester.tap(find.byType(ArchetypeCard));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/archetype_sheet_${screen.name}.png'),
      );
    });
  }
}
