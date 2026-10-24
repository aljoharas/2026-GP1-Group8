// Screenshots of every Wrapped card at its final frame, with the real
// story chrome on top, on a large phone and on a small one with larger text.
// Regenerate with: flutter test --update-goldens test/wrapped_golden_test.dart
//
// Fonts come from the Flutter SDK (Roboto, Material Icons), so text renders
// as glyphs rather than test boxes. Goldens were made on macOS; other
// platforms rasterise text slightly differently, so run them with
// `--exclude-tags golden` there.
@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/models/wrapped.dart';
import 'package:loadout/screens/wrapped/cards/player_type_card.dart';
import 'package:loadout/screens/wrapped/wrapped_card.dart';
import 'package:loadout/screens/wrapped/wrapped_screen.dart';

import 'wrapped_sample.dart';

const _cards = [
  '01_total_hours',
  '02_games_played',
  '03_top_game',
  '04_top_games',
  '05_top_online_game',
  '06_trophies',
  '07_player_type',
  '08_game_status',
  '09_rating',
  '10_friends_hours',
  '11_gaming_twin',
];

const _screens = [
  (name: '390x844', size: Size(390, 844), textScale: 1.0, padding: EdgeInsets.only(top: 47, bottom: 34)),
  (name: '360x640_text130', size: Size(360, 640), textScale: 1.3, padding: EdgeInsets.only(top: 24)),
];

/// The Flutter SDK's root, from the env or from the test runner's location
/// (`bin/cache/artifacts/engine/<platform>/flutter_tester`).
String? _flutterRoot() {
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null) return env;
  var dir = File(Platform.resolvedExecutable).parent;
  while (dir.parent.path != dir.path) {
    if (File('${dir.path}/bin/flutter').existsSync()) return dir.path;
    dir = dir.parent;
  }
  return null;
}

Future<void> _loadFonts() async {
  final root = _flutterRoot();
  if (root == null) throw StateError('Could not find the Flutter SDK to load fonts from');
  final fonts = Directory('$root/bin/cache/artifacts/material_fonts');
  Future<void> load(String family, Iterable<File> files) async {
    final loader = FontLoader(family);
    for (final file in files) {
      loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    }
    await loader.load();
  }

  final files = fonts.listSync().whereType<File>().toList();
  await load('Roboto', files.where((f) => RegExp(r'/Roboto-[A-Za-z]+\.ttf$').hasMatch(f.path)));
  await load('MaterialIcons', files.where((f) => f.path.endsWith('MaterialIcons-Regular.otf')));
  // The username tags ask for monospace; any mono face will do here.
  final mono = File('/System/Library/Fonts/Supplemental/Courier New Bold.ttf');
  if (mono.existsSync()) await load('monospace', [mono]);
}

const _dataSets = [(name: '', json: sampleWrappedJson), (name: '_stress', json: stressWrappedJson)];

void main() {
  setUpAll(_loadFonts);

  for (final data in _dataSets) {
    for (final screen in _screens) {
      testWidgets('all cards${data.name} at ${screen.name}', (tester) async {
        tester.view
          ..physicalSize = screen.size * 2
          ..devicePixelRatio = 2
          ..padding = FakeViewPadding(top: screen.padding.top * 2, bottom: screen.padding.bottom * 2);
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              scaffoldBackgroundColor: const Color(0xFF0E0E12),
              colorScheme: const ColorScheme.dark(primary: Color(0xFF4ADE80)),
            ),
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(disableAnimations: true, textScaler: TextScaler.linear(screen.textScale)),
                child: WrappedScreen(data: WrappedResponse.fromJson(data.json())),
              ),
            ),
          ),
        );
        // Let asset lookups (the trophy and player-type art) finish.
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pumpAndSettle();

        for (final (i, card) in _cards.indexed) {
          if (i > 0) {
            // Tap the right side to step forward, like a user would.
            await tester.tapAt(Offset(screen.size.width * 0.85, screen.size.height * 0.5));
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull, reason: card);
          await expectLater(
            find.byType(WrappedScreen),
            matchesGoldenFile('goldens/card_$card${data.name}_${screen.name}.png'),
          );
        }
      });
    }
  }

  testWidgets('every player type reason fits two lines on a small phone at 1.3x text, in real fonts', (tester) async {
    tester.view
      ..physicalSize = const Size(360, 640) * 2
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    for (final type in PlayerType.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 640),
              textScaler: TextScaler.linear(1.3),
              disableAnimations: true,
            ),
            child: PlayerTypeCard(type: type, style: const WrappedPlayStyle(finished: 1, paused: 1, playing: 1)),
          ),
        ),
      );
      await tester.pump();
      // The supporting line only allows a third line when two don't fit.
      final line = tester.widget<Text>(
        find.descendant(of: find.byType(WrappedSupportingLine), matching: find.byType(Text)),
      );
      expect(line.maxLines, 2, reason: type.key);
    }
  });
}
