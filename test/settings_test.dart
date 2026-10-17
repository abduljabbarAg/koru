import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koru/screens/legal.dart';
import 'package:koru/screens/settings.dart';
import 'package:koru/screens/settings_calendar.dart';
import 'package:koru/screens/settings_cloud.dart';
import 'package:koru/screens/settings_context.dart';
import 'package:koru/screens/settings_data.dart';
import 'package:koru/screens/settings_engine.dart';
import 'package:koru/screens/settings_money.dart';
import 'package:koru/screens/settings_privacy.dart';
import 'package:koru/secrets.dart';
import 'package:koru/state.dart';
import 'package:koru/store.dart';

import 'test_store.dart';

/// The Settings index and every page it pushes.
///
/// Driven the way a person drives them: find the row, tap it, look at what the
/// page says, go back. The old single-screen Settings could not fail this way,
/// because it had nothing to push. The whole point of the split is that each
/// section is reachable on its own, and a push that goes nowhere is the one
/// break this file is here to catch.
void main() {
  late ProfileStore store;

  setUpAll(initTestDatabase);

  setUp(() async {
    store = await openTestStore();
  });

  /// Steps frames so provider futures resolve. Not pumpAndSettle: the guide
  /// banner can mount the mascot, whose ticker never goes quiet.
  Future<void> pump(WidgetTester tester, {int frames = 6}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> mount(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storeProvider.overrideWith((ref) async => store),
          cloudKeyProvider.overrideWith((ref, providerId) async => ''),
          secretsProvider.overrideWithValue(MemoryKeyStore()),
        ],
        child: MaterialApp(home: child),
      ),
    );
    await pump(tester);
  }

  /// Drags the screen until a target exists in the tree.
  ///
  /// A ListView only builds what is near the viewport, so the legal group at
  /// the bottom of the index is not in the tree at all until it is scrolled
  /// to, which reads exactly like a group that was never added.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    final list = find.byType(Scrollable);
    if (list.evaluate().isEmpty) return;
    for (var i = 0; i < 15 && finder.evaluate().isEmpty; i++) {
      await tester.drag(list.first, const Offset(0, -240));
      await pump(tester, frames: 1);
    }
  }

  /// Opens the row named [title], checks [page] is what came up, then goes back
  /// and checks the index is what is left.
  Future<void> open(
    WidgetTester tester, {
    required String title,
    required Widget page,
  }) async {
    final tile = find.text(title);
    await reveal(tester, tile);
    expect(tile, findsOneWidget, reason: '"$title" is a row on the index');

    await tester.ensureVisible(tile);
    await pump(tester, frames: 1);
    await tester.tap(tile);

    // Step frames until the page is there rather than guessing a count: the
    // push transition is 300ms, and a fixed count that is too short reads as a
    // push that never happened.
    for (var i = 0; i < 20 && find.byType(page.runtimeType).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(find.byType(page.runtimeType), findsOneWidget,
        reason: 'tapping "$title" pushes its page');

    await tester.tap(find.byTooltip('Back'));
    for (var i = 0; i < 20 && find.byType(page.runtimeType).evaluate().isNotEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(find.byType(page.runtimeType), findsNothing,
        reason: 'the back button returns to the index');
    expect(find.byType(page.runtimeType), findsNothing,
        reason: 'the back button returns to the index');
  }

  group('the settings index', () {
    testWidgets('groups the sections under their own labels', (tester) async {
      await mount(tester, const SettingsScreen());

      for (final group in [
        'WHAT ANSWERS YOU',
        'WHAT LEAVES THIS PHONE',
        'PHONE PERMISSIONS',
        'MONEY',
        'CALENDAR & CAPACITY',
        'DATA',
        'ABOUT & LEGAL',
      ]) {
        final label = find.text(group);
        await reveal(tester, label);
        expect(label, findsOneWidget, reason: '$group is on the index');
      }
    });

    testWidgets('every section pushes a page of its own and comes back',
        (tester) async {
      await mount(tester, const SettingsScreen());

      for (final (title, page) in <(String, Widget)>[
        ('Your context', const ContextSettingsScreen()),
        ('Who answers', const EngineSettingsScreen()),
        ('What leaves this phone', const PrivacySettingsScreen()),
        ('Cloud provider', const CloudSettingsScreen()),
        ('Currency', const CurrencySettingsScreen()),
        ('Calendar', const CalendarSettingsScreen()),
        ('Capacity', const CapacitySettingsScreen()),
        ('Data', const DataSettingsScreen()),
        ('About Koru', const AboutScreen()),
        ('Privacy Policy', const PrivacyPolicyScreen()),
        ('Terms & Conditions', const TermsScreen()),
        ('Data policy', const DataPolicyScreen()),
      ]) {
        await open(tester, title: title, page: page);
      }
    });

    testWidgets('the privacy page links through to the full policy',
        (tester) async {
      await mount(tester, const SettingsScreen());
      await open(
        tester,
        title: 'What leaves this phone',
        page: const PrivacySettingsScreen(),
      );

      final tile = find.text('What leaves this phone');
      await reveal(tester, tile);
      await tester.ensureVisible(tile);
      await pump(tester, frames: 1);
      await tester.tap(tile);
      await pump(tester, frames: 6);

      final link = find.text('Read the full privacy policy');
      await reveal(tester, link);
      await tester.ensureVisible(link);
      await pump(tester, frames: 1);
      await tester.tap(link);
      for (var i = 0; i < 20 && find.byType(PrivacyPolicyScreen).evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      expect(find.byType(PrivacyPolicyScreen), findsOneWidget);
      // The document itself, not just its frame.
      expect(find.textContaining('no analytics, no advertising'), findsOneWidget);
    });
  });
}
