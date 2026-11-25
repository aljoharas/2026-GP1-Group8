// The Endgame play-style card (card 7) with each personality's illustration,
// rendered in the real story screen so the chrome is in the shot.
// Regenerate with:
//   flutter test --update-goldens test/endgame_personality_art_test.dart
//
// The SVGs ask for "Inter", which the app doesn't bundle, so on a device the
// text falls back to the platform font, the same font the card title uses.
// Here that fallback is Roboto (as on Android), registered under "Inter".
@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/models/wrapped.dart';
import 'package:loadout/screens/wrapped/cards/player_type_card.dart';
import 'package:loadout/screens/wrapped/wrapped_card.dart';
import 'package:loadout/screens/wrapped/wrapped_screen.dart';

import 'golden_fonts.dart';
import 'wrapped_sample.dart';

const _screens = [
  (name: '390x844', size: Size(390, 844), textScale: 1.0, padding: EdgeInsets.only(top: 47, bottom: 34)),
  (name: '360x640_text130', size: Size(360, 640), textScale: 1.3, padding: EdgeInsets.only(top: 24)),
];

Future<void> _loadFonts() async {
  await loadGoldenFonts();
  final roboto = Directory('${Platform.environment['FLUTTER_ROOT'] ?? _sdkRoot()}/bin/cache/artifacts/material_fonts')
      .listSync()
      .whereType<File>()
      .where((f) => RegExp(r'/Roboto-[A-Za-z]+\.ttf$').hasMatch(f.path));
  final inter = FontLoader('Inter');
  for (final file in roboto) {
    inter.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
  }
  await inter.load();
}

String _sdkRoot() {
  var dir = File(Platform.resolvedExecutable).parent;
  while (!File('${dir.path}/bin/flutter').existsSync()) {
    dir = dir.parent;
  }
  return dir.path;
}

Future<void> _openCard(WidgetTester tester, PlayerType type, ({String name, Size size, double textScale, EdgeInsets padding}) screen) async {
  tester.view
    ..physicalSize = screen.size * 2
    ..devicePixelRatio = 2
    ..padding = FakeViewPadding(top: screen.padding.top * 2, bottom: screen.padding.bottom * 2);
  addTearDown(tester.view.reset);

  final json = sampleWrappedJson();
  json['play_style'] = {...json['play_style'] as Map<String, dynamic>, 'personality': type.key};

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
          child: WrappedScreen(data: WrappedResponse.fromJson(json)),
        ),
      ),
    ),
  );
  // Step forward like a user until the play-style card is showing.
  for (var i = 0; i < 20 && find.byType(PlayerTypeCard).evaluate().isEmpty; i++) {
    if (i > 0) await tester.tapAt(Offset(screen.size.width * 0.85, screen.size.height * 0.5));
    await tester.pumpAndSettle();
  }
  expect(find.byType(PlayerTypeCard), findsOneWidget);
  // Let asset lookups (the type photo check, then the SVG) finish.
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
  }
}

void main() {
  setUpAll(_loadFonts);

  for (final type in PlayerType.values) {
    testWidgets('card 7 illustration: ${type.key}', (tester) async {
      await _openCard(tester, type, _screens.first);
      expect(tester.takeException(), isNull);

      final art = find.byType(SvgPicture);
      expect(art, findsOneWidget);
      expect(tester.widget<SvgPicture>(art).bytesLoader.toString(), contains('assets/endgame/${type.key}.svg'));
      expect(tester.getSize(art), const Size(200, 200));

      await expectLater(
        find.byType(WrappedScreen),
        matchesGoldenFile('goldens/endgame_personality_art/${type.key}.png'),
      );
    });

    testWidgets('card 7 illustration stays clear of the text on a small phone at 1.3x: ${type.key}', (tester) async {
      await _openCard(tester, type, _screens.last);
      expect(tester.takeException(), isNull);

      final art = tester.getRect(find.byType(SvgPicture));
      final headline = tester.getRect(find.byType(WrappedHeadline));
      final reason = tester.getRect(find.byType(WrappedSupportingLine));
      expect(art.bottom, lessThanOrEqualTo(headline.top), reason: 'art overlaps the title');
      expect(art.overlaps(reason), isFalse, reason: 'art overlaps the description');
      expect(Rect.fromLTWH(0, 0, 360, 640).contains(reason.bottomRight - const Offset(1, 1)), isTrue,
          reason: 'description is off the card');
    });
  }
}
