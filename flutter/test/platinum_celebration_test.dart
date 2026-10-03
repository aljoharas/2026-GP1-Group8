import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/providers/logged_games_provider.dart';
import 'package:loadout/services/platinum_seen_store.dart';
import 'package:loadout/widgets/platinum_celebration.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('celebration shows the Platinum message and closes', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showPlatinumCelebration(context, gameName: 'Hades', trophyName: 'Platinum'),
          child: const Text('go'),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 1000));

    expect(find.byKey(const Key('platinum-celebration')), findsOneWidget);
    expect(find.text('PLATINUM UNLOCKED'), findsOneWidget);
    expect(find.textContaining('every achievement in Hades'), findsOneWidget);

    await tester.tap(find.text('Awesome!'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('platinum-celebration')), findsNothing);
  });

  test('the guide celebrates a Platinum only once per game', () async {
    SharedPreferences.setMockInitialValues({});
    const store = PlatinumSeenStore();
    expect(await store.markCelebrated(3328), isTrue);
    expect(await store.markCelebrated(3328), isFalse);
    expect(await store.markCelebrated(4200), isTrue, reason: 'other games are tracked separately');
  });

  test('logged games carry the Platinum name from the backend', () {
    final g = LoggedGame.fromJson({'id': 1, 'name': 'Hades', 'rawg_id': 1, 'platinum_name': 'Platinum'});
    expect(g.platinumName, 'Platinum');
    expect(LoggedGame.fromJson({'id': 2, 'name': 'X'}).platinumName, isNull);
  });
}
