import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koru/models.dart';
import 'package:koru/screens/business.dart';
import 'package:koru/screens/chat.dart';
import 'package:koru/screens/projects.dart';
import 'package:koru/screens/settings.dart';
import 'package:koru/screens/today.dart';
import 'package:koru/secrets.dart';
import 'package:koru/state.dart';
import 'package:koru/store.dart';
import 'package:koru/theme.dart';
import 'package:koru/widgets.dart';

import 'test_store.dart';

/// Every screen the app can be on, on the narrowest phone it runs on.
///
/// A row of text that only fits at the width the tests happen to run at is the
/// cheapest kind of bug to ship and the most embarrassing one to find: nothing
/// throws, the screen simply draws a striped bar through itself. This was found
/// this way — the longest suggested question on the chat's opening screen was
/// 22 pixels too wide on a 320-point phone, and every test at the default width
/// passed.
void main() {
  late ProfileStore store;

  setUpAll(initTestDatabase);

  setUp(() async {
    store = await openTestStore();
  });

  Future<void> mount(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storeProvider.overrideWith((ref) async => store),
          cloudKeyProvider.overrideWith((ref, providerId) async => ''),
          secretsProvider.overrideWithValue(MemoryKeyStore()),
        ],
        child: MaterialApp(theme: buildKoruTheme(), home: child),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  for (final (name, screen) in <(String, Widget)>[
    ('Today', const TodayScreen()),
    ('Talk', const ChatScreen()),
    ('Business', const BusinessScreen()),
    ('Projects', const ProjectsScreen()),
    ('Settings', const SettingsScreen()),
  ]) {
    testWidgets('$name lays out on a 320 point phone', (tester) async {
      tester.view.physicalSize = const Size(320, 568) * 3;
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      // On the busiest states, not the empty ones: the longest labels on a
      // screen are the ones a new install never shows.
      await tester.runAsync(() async {
        await store.completeOnboarding();
        await store.put('engine', 'cloud');
        await store.addClient(const Client(
          name: 'A client with a long name indeed',
          amount: 2000,
          status: 'delivered',
          created: '2026-01-01',
        ));
      });
      await mount(tester, screen);

      expect(tester.takeException(), isNull, reason: '$name overflows at 320');
    });
  }

  testWidgets('the guide banner and a card of rows fit beside each other',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(store.completeOnboarding);
    await mount(
      tester,
      Scaffold(
        body: ListView(
          children: [
            const KoruGuideBanner(speech: 'Nothing is overdue this morning'),
            KoruCard(
              child: KoruRow(
                leading: KoruIconBadge(
                  icon: Icons.work_outline_rounded,
                  color: KoruColors.leaf,
                  background: KoruColors.leafSoft,
                ),
                title: 'A client with a long name indeed',
                subtitle: '2000 owed, due on a date that is quite far away',
                trailing: const Icon(Icons.chevron_right_rounded,
                    size: KoruSize.icon),
              ),
            ),
          ],
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}