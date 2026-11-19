import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/models/wrapped.dart';
import 'package:loadout/screens/wrapped/cards/total_hours_card.dart';
import 'package:loadout/screens/wrapped/wrapped_export.dart';
import 'package:loadout/screens/wrapped/wrapped_screen.dart';

import 'wrapped_sample.dart';

/// Hosts [child] in an app and hands back a context below its Overlay.
Future<BuildContext> _host(WidgetTester tester, {Widget? child, double textScale = 1.0}) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(colorScheme: const ColorScheme.dark(primary: Color(0xFF4ADE80))),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: Builder(
              builder: (context) {
                captured = context;
                return child ?? const SizedBox();
              },
            ),
          ),
        ),
      ),
    ),
  );
  return captured;
}

/// Runs a capture to completion: pumps frames (fake time) and lets the real
/// async work of toImage / PNG encoding progress in between.
Future<Uint8List> _capture(WidgetTester tester, BuildContext context, Widget card) async {
  Uint8List? result;
  Object? error;
  captureWrappedCard(context, card).then((bytes) => result = bytes, onError: (Object e) => error = e);
  for (var i = 0; i < 400 && result == null && error == null; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
  }
  if (error != null) throw error!;
  expect(result, isNotNull, reason: 'capture did not finish');
  return result!;
}

/// Width and height from a PNG's IHDR chunk.
(int, int) _pngSize(Uint8List bytes) {
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  expect(bytes.sublist(0, 8), signature, reason: 'not a PNG');
  final data = ByteData.sublistView(bytes);
  return (data.getUint32(16), data.getUint32(20));
}

void main() {
  test('export size is 9:16 at 1080x1920', () {
    expect(kWrappedExportLogicalSize * kWrappedExportPixelRatio, kWrappedExportPixelSize);
    expect(kWrappedExportLogicalSize.aspectRatio, closeTo(9 / 16, 1e-9));
  });

  testWidgets('captures a simple card as a 1080x1920 PNG', (tester) async {
    final context = await _host(tester);
    final png = await _capture(tester, context, const TotalHoursCard(hours: 96, year: 2026));
    expect(_pngSize(png), (1080, 1920));
    // The off-screen entry is gone after the next frame.
    await tester.pump();
    expect(find.byType(TotalHoursCard), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the export ignores the device text size', (tester) async {
    final context = await _host(tester, textScale: 2.0);
    final png = await _capture(tester, context, const TotalHoursCard(hours: 1204.5, year: 2026));
    expect(_pngSize(png), (1080, 1920));
    expect(tester.takeException(), isNull);
  });

  for (final (name, json) in [('sample', sampleWrappedJson), ('stress', stressWrappedJson)]) {
    testWidgets('every $name card exports without layout errors', (tester) async {
      final context = await _host(tester, textScale: 1.3);
      final cards = buildWrappedCards(WrappedResponse.fromJson(json()));
      for (final (i, card) in cards.indexed) {
        final png = await _capture(tester, context, card);
        expect(_pngSize(png), (1080, 1920), reason: 'card $i');
        expect(tester.takeException(), isNull, reason: 'card $i (${card.runtimeType})');
      }
    });
  }

  testWidgets('WrappedScreen shows the export button, and tapping it does not change page', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 844), disableAnimations: true),
          child: WrappedScreen(data: WrappedResponse.fromJson(sampleWrappedJson())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final button = find.byType(WrappedExportButton);
    expect(button, findsOneWidget);
    expect(tester.widget<WrappedExportButton>(button).current, 0);

    await tester.tap(find.byTooltip('Save or share'));
    await tester.pumpAndSettle();
    expect(find.text('Save to gallery'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.textContaining('Save all cards'), findsOneWidget);

    // Close the sheet; still on the first card.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(tester.widget<WrappedExportButton>(button).current, 0);
  });
}
