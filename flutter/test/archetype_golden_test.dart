// Screenshots of the Player Archetype emblem badge next to the @handle, in each
// state, and of the details sheet, on a large phone and on a small one with
// larger text.
// Regenerate with: flutter test --update-goldens test/archetype_golden_test.dart
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/models/archetype.dart';
import 'package:loadout/widgets/archetype_badge.dart';

import 'archetype_test.dart' show mineJson, blendJson, atypicalJson, lockedJson, friendJson;
import 'golden_fonts.dart';

const _screens = [
  (name: '390x844', size: Size(390, 844), textScale: 1.0),
  (name: '360x640_text130', size: Size(360, 640), textScale: 1.3),
];

const _text = Color(0xFFF0F0F0);
const _muted = Color(0xFF6B6B80);

/// The profile header as the app lays it out: avatar, display name, then the
/// @handle with the archetype badge just after it, then the bio
Widget _profile(Widget badge, double textScale, {String name = 'Sara Ahmed'}) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Roboto', brightness: Brightness.dark),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        backgroundColor: const Color(0xFF0E0E12),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
            children: [
              const CircleAvatar(radius: 34, backgroundColor: Color(0xFF26263A),
                  child: Icon(Icons.person, color: _muted, size: 34)),
              const SizedBox(height: 12),
              Text(name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: _text, letterSpacing: -0.5)),
              const SizedBox(height: 2),
              Row(children: [
                Flexible(
                  child: Text('@${name.toLowerCase().replaceAll(' ', '_')}',
                      overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: _muted)),
                ),
                const SizedBox(width: 6),
                badge,
              ]),
              const SizedBox(height: 10),
              const Text('Mostly racing games, the occasional RPG.',
                  style: TextStyle(color: Color(0xCCF0F0F0), fontSize: 13, height: 1.5)),
              const SizedBox(height: 24),
              const Text('Currently Playing', style: TextStyle(color: _text, fontSize: 17, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );

void main() {
  setUpAll(loadGoldenFonts);

  final badges = <String, Widget>{
    'normal': ArchetypeBadge(archetype: Archetype.fromJson(mineJson)),
    'blend': ArchetypeBadge(archetype: Archetype.fromJson(blendJson)),
    'closest': ArchetypeBadge(archetype: Archetype.fromJson(atypicalJson)),
    'locked': ArchetypeBadge(archetype: Archetype.fromJson(lockedJson)),
    'loading': const ArchetypeBadge(loading: true),
    'friend': ArchetypeBadge(archetype: Archetype.fromJson({...friendJson, 'family': 'Light'}), friendView: true),
  };

  final sheets = <String, ({Map<String, dynamic> json, bool friend, bool expand})>{
    'normal': (json: mineJson, friend: false, expand: false),
    'blend': (json: blendJson, friend: false, expand: false),
    'closest': (json: atypicalJson, friend: false, expand: false),
    'friend': (json: {...friendJson, 'family': 'Light'}, friend: true, expand: false),
    'locked': (json: lockedJson, friend: false, expand: false),
    'full_mix': (json: mineJson, friend: false, expand: true),
  };

  for (final screen in _screens) {
    void setView(WidgetTester tester) {
      tester.view.physicalSize = screen.size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
    }

    for (final entry in badges.entries) {
      testWidgets('archetype badge ${entry.key} ${screen.name}', (tester) async {
        setView(tester);
        await tester.pumpWidget(_profile(entry.value, screen.textScale));
        await expectLater(find.byType(MaterialApp),
            matchesGoldenFile('goldens/archetype_badge_${entry.key}_${screen.name}.png'));
      });
    }

    for (final entry in sheets.entries) {
      testWidgets('archetype sheet ${entry.key} ${screen.name}', (tester) async {
        setView(tester);
        final v = entry.value;
        await tester.pumpWidget(_profile(
            ArchetypeBadge(archetype: Archetype.fromJson(v.json), friendView: v.friend), screen.textScale));
        await tester.tap(find.byKey(const ValueKey('archetype-badge')));
        await tester.pumpAndSettle();
        if (v.expand) {
          await tester.tap(find.text('See your full mix'));
          await tester.pumpAndSettle();
        }
        await expectLater(find.byType(MaterialApp),
            matchesGoldenFile('goldens/archetype_sheet_${entry.key}_${screen.name}.png'));
      });
    }
  }
}
