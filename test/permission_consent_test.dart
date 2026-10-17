import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koru/attention_bridge.dart';
import 'package:koru/calendar_bridge.dart';
import 'package:koru/main.dart';
import 'package:koru/onboarding.dart';
import 'package:koru/permission_consent.dart';
import 'package:koru/screens/permissions_intro.dart';
import 'package:koru/screens/settings.dart';
import 'package:koru/screens/settings_permissions.dart';
import 'package:koru/secrets.dart';
import 'package:koru/state.dart';
import 'package:koru/store.dart';
import 'package:koru/theme.dart';

import 'test_store.dart';

/// Who gets the permission explanation, and who does not.
///
/// The bug this file exists for was not subtle in the code and total in the app:
/// the gate read a stored "asked" flag that the previous release had already set
/// to '1' for every user who was onboarded when it shipped, before any
/// explanation existed to see. So the screen could never appear for an upgrading
/// install, and the reported symptom was "permissions don't ask".
///
/// The second half of that bug was in the screen itself. Its page counter was
/// `final`, and the controller it advanced was never attached to a PageView, so
/// "Next" threw and the branch that raises the permissions was unreachable — the
/// only way out requested nothing. Both halves are covered here, because fixing
/// only the gate would have left a screen that could not ask.
/// A phone that has granted nothing and refuses nothing.
///
/// The real bridge reaches a platform channel, which resolves to "nothing" in a
/// test. Stated here rather than left to that, so the flow under test is the one
/// a fresh install actually takes.
class _NoHealth extends HealthBridge {
  const _NoHealth();

  @override
  Future<KoruHealth> check() async =>
      const KoruHealth(notifications: false, batteryExempt: false);

  @override
  Future<bool> requestNotifications() async => false;

  @override
  Future<bool> requestBatteryExempt() async => false;

  @override
  Future<bool> openAutostartSettings() async => false;
}

/// A calendar with no platform behind it. Never contacted by a test.
class _NoCalendar extends CalendarBridge {
  const _NoCalendar();

  @override
  Future<bool> get hasPermission async => false;

  @override
  Future<bool> requestPermission() async => false;
}

void main() {
  late ProfileStore store;

  setUpAll(initTestDatabase);

  setUp(() async {
    store = await openTestStore();
  });

  /// Nothing granted, which is what a fresh install and most upgrades look like.
  const nothing = KoruHealth(notifications: false, batteryExempt: false);

  /// Everything granted, and nothing left to say.
  const everything =
      KoruHealth(notifications: true, batteryExempt: true, autostart: true);

  PermissionConsent decide(
    Map<String, String> values, {
    KoruHealth health = nothing,
    bool calendar = false,
  }) =>
      PermissionConsent.fromStore(
        values,
        health: health,
        calendarGranted: calendar,
      );

  group('the decision', () {
    test('an upgrade that was "asked" by the old flag is still offered consent',
        () {
      // The regression, stated as directly as it can be. This is the exact
      // state every user who installed the previous release is in.
      final consent = decide({legacyAskedPermissionsKey: '1'});

      expect(consent.outcome, ConsentOutcome.notAsked);
      expect(consent.shouldOffer, isTrue);
    });

    test('the old flag is read, and left alone, but never suppresses the screen',
        () {
      // Migrating by deleting would break an older build still reading it, so
      // the value has to stay readable. Reading it is fine; obeying it is not.
      final consent = decide({legacyAskedPermissionsKey: '1'});

      expect(consent.shouldOffer, isTrue,
          reason: 'the old flag meant "a snackbar appeared", not "this was seen"');
    });

    test('an upgrade that already has everything is not bothered', () {
      // Not asked, but nothing to ask about. Showing a screen with nothing to
      // say is worse than showing none.
      final consent = decide(
        {legacyAskedPermissionsKey: '1'},
        health: everything,
        calendar: true,
      );

      expect(consent.shouldOffer, isFalse);
    });

    test('an explicit decline is not asked again on any later launch', () {
      // The nagging case. There is no launch count here and there does not need
      // to be one: a recorded decline answers the question for good.
      for (final (health, calendar) in [
        (nothing, false),
        (everything, true),
      ]) {
        final consent = decide(
          {permissionConsentKey: 'declined'},
          health: health,
          calendar: calendar,
        );
        expect(consent.shouldOffer, isFalse,
            reason: 'a decline is not undone by anything not being granted');
      }
    });

    test('a recorded grant is not asked again either', () {
      // Re-asking somebody who already agreed teaches people to dismiss
      // dialogs without reading them, which costs the permission that mattered.
      final consent = decide(
        {permissionConsentKey: 'granted', legacyAskedPermissionsKey: '1'},
        health: nothing,
      );

      expect(consent.shouldOffer, isFalse);
    });

    test('a decline that coexists with the old flag is still a decline', () {
      // Otherwise the migration would resurrect the screen for somebody who had
      // already answered it, every single launch.
      final consent = decide({
        legacyAskedPermissionsKey: '1',
        permissionConsentKey: 'declined',
      });

      expect(consent.shouldOffer, isFalse);
    });

    test('missing notifications alone are enough', () {
      expect(
        decide(
          {},
          health: const KoruHealth(
              notifications: false, batteryExempt: true, autostart: true),
          calendar: true,
        ).shouldOffer,
        isTrue,
      );
    });

    test('a missing calendar alone is enough', () {
      expect(decide({}, health: everything, calendar: false).shouldOffer, isTrue);
    });

    test('a phone that cannot be told to restart itself counts', () {
      // Third page of the explanation is about exactly these two settings, so a
      // person who was sent to that screen and came back with it off has still
      // not had the whole thing.
      final consent = decide(
        {},
        health: const KoruHealth(
            notifications: true, batteryExempt: true, autostart: false),
        calendar: true,
      );

      expect(consent.shouldOffer, isTrue);
    });

    test('a phone with no autostart setting is not treated as failing one', () {
      // Null means "does not apply". Counting that as a problem would put every
      // Pixel through a screen about a setting it does not have.
      final consent = decide(
        {},
        health: const KoruHealth(
            notifications: true, batteryExempt: true, autostart: null),
        calendar: true,
      );

      expect(consent.shouldOffer, isFalse);
    });

    test('a value from some future version degrades to not-asked', () {
      // Safer than honouring an outcome this build has never heard of: the only
      // state a wrong guess can be recovered from is the one that offers the
      // screen.
      expect(PermissionConsent.parseOutcome('surprised'), ConsentOutcome.notAsked);
      expect(PermissionConsent.parseOutcome(null), ConsentOutcome.notAsked);
      expect(PermissionConsent.parseOutcome(''), ConsentOutcome.notAsked);
    });

    test('the outcome round trips through the value it is stored as', () {
      for (final outcome in ConsentOutcome.values) {
        expect(PermissionConsent.parseOutcome(outcome.name), outcome);
      }
    });
  });

  group('the gate, end to end', () {
    /// Stands up the app with the two permission providers answering directly.
    ///
    /// Both are overridden because the subject of these tests is what the app
    /// does with an answer, and the real ones cannot answer in a test at all:
    /// the calendar plugin has no platform to call, and a call that never
    /// completes inside a fake-async zone leaves the gate waiting forever. Which
    /// is honest — it means nothing here depends on a plugin being present.
    Future<void> pumpApp(
      WidgetTester tester,
      Widget child, {
      KoruHealth health = nothing,
      bool calendar = false,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storeProvider.overrideWith((ref) async => store),
            cloudKeyProvider.overrideWith((ref, providerId) async => ''),
            secretsProvider.overrideWithValue(MemoryKeyStore()),
            healthProvider.overrideWith((ref) async => health),
            calendarPermissionProvider.overrideWith((ref) async => calendar),
            // The request path reads the bridges directly rather than the
            // providers, so both have to be replaced too. Without this the tap
            // waits on a calendar plugin that has no platform behind it, and the
            // answer is never recorded — a test-only hang that looks exactly like
            // the bug this file is about.
            healthBridgeProvider.overrideWithValue(const _NoHealth()),
            calendarBridgeProvider.overrideWithValue(const _NoCalendar()),
          ],
          child: MaterialApp(theme: buildKoruTheme(), home: child),
        ),
      );
      await tester.pump();
    }

    Future<void> pumpFrames(
      WidgetTester tester, {
      int frames = 10,
      Duration step = const Duration(milliseconds: 40),
    }) async {
      for (var i = 0; i < frames; i++) {
        await tester.pump(step);
      }
    }

    /// Onboarding is a tall form and the default 800x600 test surface puts
    /// things below the fold. This is roughly the shape of the phone.
    void useTallSurface(WidgetTester tester) {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    }

    /// Seeds the store from inside a widget test, where the fake clock is running.
    Future<void> seed(WidgetTester tester, Future<void> Function() body) async {
      await tester.runAsync(body);
    }

    /// Reads a stored value, for the same reason [seed] exists: a widget test
    /// body runs in a fake-async zone that a real database read cannot finish in.
    Future<String?> stored(WidgetTester tester, String key) async {
      String? value;
      await tester.runAsync(() async => value = await store.get(key));
      return value;
    }

    /// Pumps until [finder] is gone, or gives up.
    ///
    /// For the tail of a flow that ends in a handful of awaited writes. Bounded
    /// rather than `pumpAndSettle`, because the mascot ticks forever.
    Future<void> pumpUntilGone(
      WidgetTester tester,
      Finder finder, {
      int frames = 30,
    }) async {
      for (var i = 0; i < frames; i++) {
        if (finder.evaluate().isEmpty) return;
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    /// Past the splash and onto whatever [RootGate] wants to show.
    ///
    /// The splash holds for five seconds on a plain timer, and the frames after
    /// that are its fade plus the reads behind the startup gate: the store, and
    /// then whichever permissions the gate needs to know about. Bounded loop
    /// rather than `pumpAndSettle`, because the mascot ticks forever and would
    /// never settle — and bounded rather than a fixed count, so this keeps
    /// working if a read grows a frame and fails by being a hang instead.
    Future<void> pastSplash(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      for (var i = 0; i < 30; i++) {
        if (find.byType(SplashScreen).evaluate().isEmpty) break;
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    /// An install carried over from the release before the explanation existed.
    Future<void> seedUpgradingUser(WidgetTester tester) async {
      await seed(tester, () async {
        await store.put('onboarded', '1');
        await store.put(legacyAskedPermissionsKey, '1');
      });
    }

    testWidgets('an upgrading user with nothing granted sees the screen',
        (tester) async {
      useTallSurface(tester);
      await seedUpgradingUser(tester);
      await pumpApp(tester, const RootGate());

      await pastSplash(tester);

      // The whole bug in one assertion: this user carries asked_permissions='1'
      // and has been sent here anyway, because they have never actually seen it.
      expect(find.byType(PermissionsIntroScreen), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);
    });

    testWidgets('a genuine first run reaches it too, with no restart',
        (tester) async {
      // The bug behind "I have to close the app and start again then i see the
      // permission screen". A fresh install is not the upgrading user above: it
      // has no flags at all, which means the gate answers "nothing to ask about"
      // at launch because onboarding has not finished yet — and it never asks
      // again, so the explanation is unreachable for the whole session. Only the
      // second launch asks the question with onboarding already behind it, which
      // is exactly what the report describes.
      useTallSurface(tester);
      // Nothing seeded: no onboarded, no asked_permissions, no consent. This is
      // the store of an app installed five seconds ago.
      await pumpApp(tester, const RootGate());

      await pastSplash(tester);

      expect(find.byType(OnboardingScreen), findsOneWidget,
          reason: 'a fresh install starts at onboarding, not at the app');

      // Walk onboarding the way a person does: straight through, answering
      // nothing. Every field is optional and the last button is the one that
      // commits.
      for (var i = 0; i < 6; i++) {
        await tester.tap(find.text('Continue'));
        await pumpFrames(tester);
      }
      await tester.tap(find.text('Start'));
      await pumpFrames(tester, frames: 20);

      // No restart, no second launch, no relaunch of the engine: the screen the
      // report says only appears after one of those.
      expect(find.byType(PermissionsIntroScreen), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);
      expect(await stored(tester, 'onboarded'), '1',
          reason: 'onboarding really did finish; this is not a stuck form');

      // And it is a real screen, not a flash: answering it gets into the app and
      // records the answer.
      await tester.tap(find.text('Not now'));
      await pumpUntilGone(tester, find.byType(PermissionsIntroScreen));
      await pumpFrames(tester, frames: 12);

      expect(await stored(tester, permissionConsentKey), 'declined');
      expect(find.byType(HomeShell), findsOneWidget);
    });

    testWidgets('the screen can actually be finished and asks for something',
        (tester) async {
      // The half of the bug that lived in the screen. Its page counter was
      // `final` and the controller it paged was attached to nothing, so "Next"
      // threw, the last page was unreachable, and the only way out requested no
      // permissions at all.
      useTallSurface(tester);
      await seedUpgradingUser(tester);
      await pumpApp(tester, const RootGate());
      await pastSplash(tester);

      expect(find.text('Reminders'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await pumpFrames(tester);
      expect(find.text('Calendar'), findsOneWidget,
          reason: 'page two must be reachable, and must be the calendar');

      await tester.tap(find.text('Next'));
      await pumpFrames(tester);
      expect(find.text('Staying awake'), findsOneWidget);
      expect(find.text('Turn on what I need'), findsOneWidget,
          reason: 'the last page has to offer the request rather than another Next');

      await tester.tap(find.text('Turn on what I need'));
      await pumpUntilGone(tester, find.byType(PermissionsIntroScreen));

      // Recorded as what it was: the person let the prompts be raised.
      expect(await stored(tester, permissionConsentKey), 'granted');
      expect(find.byType(PermissionsIntroScreen), findsNothing);
    });

    testWidgets('declining is recorded as a decline, and does not come back',
        (tester) async {
      useTallSurface(tester);
      await seedUpgradingUser(tester);
      await pumpApp(tester, const RootGate());
      await pastSplash(tester);

      await tester.tap(find.text('Not now'));
      await pumpUntilGone(tester, find.byType(PermissionsIntroScreen));
      await pumpFrames(tester, frames: 12);

      // Not the same value as a grant. One bit could not tell these apart, and
      // that is the mistake the old flag was made of.
      expect(await stored(tester, permissionConsentKey), 'declined');
      expect(find.byType(HomeShell), findsOneWidget);

      // The next launch. Same store, same person, and the screen is gone: a
      // refusal answered with a fresh dialog is not respect, it is persistence.
      await pumpApp(tester, const RootGate());
      await pastSplash(tester);

      expect(find.byType(PermissionsIntroScreen), findsNothing);
      expect(find.byType(HomeShell), findsOneWidget);
    });

    test('the two keys are separate, so the old one is never overwritten', () {
      // Nothing in this file writes or removes asked_permissions. Deleting a key
      // that older builds still read is how a downgrade silently changes what an
      // install does, and reusing it is how the original bug comes back.
      expect(legacyAskedPermissionsKey, isNot(permissionConsentKey));
    });
  });

  group('reachable from Settings', () {
    Future<void> pumpSettings(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storeProvider.overrideWith((ref) async => store),
            cloudKeyProvider.overrideWith((ref, providerId) async => ''),
            secretsProvider.overrideWithValue(MemoryKeyStore()),
            healthProvider.overrideWith((ref) async =>
                const KoruHealth(notifications: true, batteryExempt: true)),
            calendarPermissionProvider.overrideWith((ref) async => true),
          ],
          child: MaterialApp(theme: buildKoruTheme(), home: const SettingsScreen()),
        ),
      );
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
    }

    testWidgets('permissions are one row away and ask again on demand',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await pumpSettings(tester);

      final row = find.text('Permissions');
      await tester.ensureVisible(row);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tap(row);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }

      expect(find.byType(PermissionsSettingsScreen), findsOneWidget);

      // Present even with everything already granted. Somebody who has just
      // revoked a permission in system settings is exactly the person who needs
      // this, and would not know to go looking for it — so the button cannot be
      // conditional on something being missing.
      // Scrolled to rather than merely looked for: the buttons are at the
      // bottom of a long list and a ListView builds lazily, so before the scroll
      // they are not in the tree at all.
      final ask = find.text('Ask for what Koru needs');
      await tester.scrollUntilVisible(ask, 200, maxScrolls: 30);
      expect(ask, findsOneWidget);
      expect(find.text('Read what Koru needs, and why'), findsOneWidget);
    });
  });
}