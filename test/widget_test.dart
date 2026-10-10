import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koru/handoff.dart';
import 'package:koru/main.dart';
import 'package:koru/mascot/mascot.dart';
import 'package:koru/models.dart';
import 'package:koru/onboarding.dart';
import 'package:koru/screens/business.dart';
import 'package:koru/screens/chat.dart';
import 'package:koru/secrets.dart';
import 'package:koru/state.dart';
import 'package:koru/store.dart';
import 'package:koru/theme.dart';
import 'package:koru/widgets.dart';

import 'test_store.dart';

/// Widget level checks against a real store.
///
/// Two things about this file are load bearing:
///
///  * The store is opened in `setUp`, which runs in the real async zone.
///    Opening it inside `testWidgets` would hang forever, because a widget test
///    body executes inside a fake-async zone that never yields to the real event
///    loop, so real file and database work never completes. Anything that touches
///    the database from inside a test body therefore goes through
///    `tester.runAsync`.
///
///  * The mascot runs a permanent ticker, so the tree never goes quiet and
///    `pumpAndSettle` would hang until it timed out. Frames are stepped instead.
/// A keystore that refuses every write, standing in for a device where the
/// platform keystore is unavailable.
class _FailingKeyStore implements KeyStore {
  @override
  Future<String> readKey(String providerId) async => '';

  @override
  Future<bool> writeKey(String providerId, String value) async => false;

  @override
  Future<bool> clearKey(String providerId) async => false;
}

void main() {
  late ProfileStore store;

  setUpAll(initTestDatabase);

  setUp(() async {
    store = await openTestStore();
  });

  Future<void> pumpApp(WidgetTester tester, Widget child) async {
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
    await tester.pump();
  }

  /// Steps a fixed number of frames.
  Future<void> pumpFrames(
    WidgetTester tester, {
    int frames = 8,
    Duration step = const Duration(milliseconds: 40),
  }) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(step);
    }
  }

  /// Seeds the store from inside a widget test, where the fake clock is running.
  Future<void> seed(WidgetTester tester, Future<void> Function() body) async {
    await tester.runAsync(body);
  }

  group('MemoryKeyStore', () {
    test('round trips and clears', () async {
      final store = MemoryKeyStore();
      expect(await store.readKey('openrouter'), '');
      expect(await store.writeKey('openrouter', 'sk-or-v1-abc'), isTrue);
      expect(await store.readKey('openrouter'), 'sk-or-v1-abc');
      expect(await store.clearKey('openrouter'), isTrue);
      expect(await store.readKey('openrouter'), '');
    });

    test('keeps one key per provider', () async {
      // The point of making this a family: two providers coexisting used to be
      // impossible, because there was one slot.
      final store = MemoryKeyStore();
      await store.writeKey('anthropic', 'sk-ant-1');
      await store.writeKey('openai', 'sk-openai-1');
      expect(await store.readKey('anthropic'), 'sk-ant-1');
      expect(await store.readKey('openai'), 'sk-openai-1');
    });

    test('reports failure instead of pretending it saved', () async {
      // A key that failed to write used to be reported as saved, which is how a
      // dead key became "nothing responds".
      final store = _FailingKeyStore();
      expect(await store.writeKey('openai', 'sk-x'), isFalse);
    });
  });
  /// Onboarding is a tall form, and the default 800x600 test surface puts the
  /// help chips below the fold where they cannot be hit. This is roughly the
  /// shape of the phone the app runs on.
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  /// Taps a chip, scrolling it into view first.
  Future<void> tapChip(WidgetTester tester, String label) async {
    final finder = find.text(label);
    await tester.ensureVisible(finder);
    await pumpFrames(tester);
    await tester.tap(finder);
    await pumpFrames(tester);
  }

  /// Walks the first five steps of onboarding and leaves the user on the goals
  /// page, where Start and the help chips are.
  Future<void> advanceToGoals(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.text('Continue'));
      await pumpFrames(tester);
    }
    expect(find.text('Start'), findsOneWidget);
  }

  group('Onboarding', () {
    /// Walks the whole flow the way a person does. The regression this covers is
    /// real: the Start button used to do nothing, because RootGate held the
    /// onboarded flag in a field and never watched the provider onboarding set.
    testWidgets('Start on the last step lands you in the app', (tester) async {
      useTallSurface(tester);
      await pumpApp(tester, const RootGate());

      // Splash first: it holds for a minimum time, and it only starts once the
      // store read in initState resolves, so give both room.
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await pumpFrames(tester, frames: 12);
      expect(find.byType(OnboardingScreen), findsOneWidget);

      // intro
      await tester.tap(find.text('Continue'));
      await pumpFrames(tester);

      // nickname
      await tester.enterText(find.byType(TextField), 'kami');
      await pumpFrames(tester);
      await tester.tap(find.text('Continue'));
      await pumpFrames(tester);

      // stage
      await tester.tap(find.text('A few years in'));
      await pumpFrames(tester);
      await tester.tap(find.text('Continue'));
      await pumpFrames(tester);

      // work
      await tester.tap(find.text('Employee'));
      await pumpFrames(tester);
      await tester.tap(find.text('Continue'));
      await pumpFrames(tester);

      // measurements
      await tester.tap(find.text('Continue'));
      await pumpFrames(tester);

      // goals and help
      expect(find.text('Start'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'ship two more clients');
      await pumpFrames(tester);
      await tester.tap(find.text('Start'));
      await pumpFrames(tester, frames: 12);

      expect(find.byType(OnboardingScreen), findsNothing);
      expect(find.byType(HomeShell), findsOneWidget);

      // runAsync returns a nullable value, hence the bang.
      final saved = (await tester.runAsync(() async => <String, String?>{
            'onboarded': await store.get('onboarded'),
            'nickname': await store.get('nickname'),
            'stage': await store.get('stage'),
            'business': await store.get('business'),
            'goals': await store.get('goals'),
          }))!;
      expect(saved['onboarded'], '1');
      expect(saved['nickname'], 'kami');
      expect(saved['stage'], 'A few years in');
      expect(saved['business'], 'Employee');
      expect(saved['goals'], 'ship two more clients');
    });

    testWidgets('capacity defaults to five and can be changed', (tester) async {
      useTallSurface(tester);
      await pumpApp(tester, const OnboardingScreen());

      // Advance to the capacity step, which is the one before goals.
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.text('Continue'));
        await pumpFrames(tester);
      }
      expect(find.text('How many clients can you serve well?'), findsOneWidget);

      await tester.tap(find.text('8'));
      await pumpFrames(tester);

      await tester.tap(find.text('Continue'));
      await pumpFrames(tester);
      await tester.tap(find.text('Start'));
      await pumpFrames(tester, frames: 12);

      final capacity = await tester.runAsync(() => store.number('capacity'));
      expect(capacity, 8);
    });

    testWidgets('an untouched capacity is still written as the default',
        (tester) async {
      useTallSurface(tester);
      await pumpApp(tester, const OnboardingScreen());
      await advanceToGoals(tester);
      await tester.tap(find.text('Start'));
      await pumpFrames(tester, frames: 12);

      // A fresh install that skipped the choice still has something to measure
      // against, otherwise the meter silently does nothing.
      final capacity = await tester.runAsync(() => store.number('capacity'));
      expect(capacity, 5);
    });

    testWidgets('help topics are multi-select and all of them persist',
        (tester) async {
      useTallSurface(tester);
      await pumpApp(tester, const OnboardingScreen());
      await advanceToGoals(tester);

      await tapChip(tester, 'Finding clients');
      await tapChip(tester, 'Getting paid');
      await tapChip(tester, 'Pricing');

      // All three stay selected at once.
      expect(find.byType(ChoiceChip), findsNWidgets(5));
      expect(
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Finding clients')).selected,
        isTrue,
      );
      expect(
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Getting paid')).selected,
        isTrue,
      );
      expect(
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Pricing')).selected,
        isTrue,
      );
      expect(
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Staying organised')).selected,
        isFalse,
      );

      await tester.tap(find.text('Start'));
      await pumpFrames(tester, frames: 12);

      final focus = await tester.runAsync(() => store.get('help_focus'));
      expect(focus, 'Finding clients, Getting paid, Pricing');
    });

    testWidgets('tapping a help topic again deselects it', (tester) async {
      useTallSurface(tester);
      await pumpApp(tester, const OnboardingScreen());
      await advanceToGoals(tester);

      await tapChip(tester, 'Pricing');
      expect(
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Pricing')).selected,
        isTrue,
      );

      await tapChip(tester, 'Pricing');
      expect(
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Pricing')).selected,
        isFalse,
      );
    });

    testWidgets('All of it is a shortcut and clears the other picks',
        (tester) async {
      useTallSurface(tester);
      await pumpApp(tester, const OnboardingScreen());
      await advanceToGoals(tester);

      await tapChip(tester, 'Pricing');
      await tapChip(tester, 'All of it');

      expect(
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'All of it')).selected,
        isTrue,
      );
      expect(
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Pricing')).selected,
        isFalse,
      );

      // Picking something specific drops the shortcut.
      await tapChip(tester, 'Getting paid');
      expect(
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'All of it')).selected,
        isFalse,
      );
      expect(
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Getting paid')).selected,
        isTrue,
      );

      await tester.tap(find.text('Start'));
      await pumpFrames(tester, frames: 12);
      final focus = await tester.runAsync(() => store.get('help_focus'));
      expect(focus, 'Getting paid');
    });
  });

  group('HandoffCard', () {
    testWidgets('shows every resource with its number', (tester) async {
      await pumpApp(
        tester,
        const Scaffold(
          body: HandoffCard(
            plan: HandoffPlan(
              headline: 'Talk to someone right now',
              body: 'These lines are free.',
              urgent: true,
              resources: [
                Resource(name: 'Emergency', detail: 'Ambulance', number: '999'),
                Resource(name: 'Helpline', detail: 'Staffed', number: '800 4673'),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Talk to someone right now'), findsOneWidget);
      expect(find.text('999 - 24 hours'), findsOneWidget);
      expect(find.text('800 4673 - 24 hours'), findsOneWidget);
    });

    testWidgets('can be dismissed', (tester) async {
      var dismissed = false;
      await pumpApp(
        tester,
        Scaffold(
          body: HandoffCard(
            plan: const HandoffPlan(
              headline: 'x',
              body: 'y',
              resources: [Resource(name: 'a', detail: 'b', number: 'c')],
            ),
            onDismiss: () => dismissed = true,
          ),
        ),
      );

      await tester.tap(find.byTooltip('Dismiss'));
      expect(dismissed, isTrue);
    });

    testWidgets('is announced as a live region', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(
        tester,
        const Scaffold(
          body: HandoffCard(
            plan: HandoffPlan(
              headline: 'Step aside',
              body: 'Someone should decide this.',
              resources: [Resource(name: 'a', detail: 'b', number: 'c')],
            ),
          ),
        ),
      );

      expect(find.bySemanticsLabel(RegExp('Step aside')), findsOneWidget);
      handle.dispose();
    });
  });

  group('KoruMascot', () {
    testWidgets('renders and is labelled', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(
        tester,
        const Scaffold(body: Center(child: KoruMascot(size: 100))),
      );

      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('Koru')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('taps are forwarded', (tester) async {
      var taps = 0;
      await pumpApp(
        tester,
        Scaffold(
          body: Center(child: KoruMascot(size: 100, onTap: () => taps++)),
        ),
      );

      await tester.tap(find.byType(KoruMascot));
      expect(taps, 1);
    });

    testWidgets('carries a custom semantic label', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(
        tester,
        const Scaffold(
          body: Center(child: KoruMascot(size: 80, semanticLabel: 'Koru waving')),
        ),
      );
      expect(find.bySemanticsLabel('Koru waving'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the controller queues and drains intents', (tester) async {
      final controller = KoruMascotController();
      await pumpApp(
        tester,
        Scaffold(body: Center(child: KoruMascot(size: 80, controller: controller))),
      );

      expect(controller.pendingCount, 0);
      controller.cheer();
      controller.greet();
      expect(controller.pendingCount, 2);
      await pumpFrames(tester);
      expect(controller.pendingCount, 0, reason: 'only the newest intent should play');
    });
  });

  group('ChatScreen', () {
    testWidgets('opens with the mascot and suggestions', (tester) async {
      await pumpApp(tester, const ChatScreen());

      expect(find.byType(KoruMascot), findsWidgets);
      expect(find.text('How am I doing?'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('the empty state says the answer stays on the phone',
        (tester) async {
      await pumpApp(tester, const ChatScreen());
      expect(find.textContaining('answered here, on this phone'), findsOneWidget);
      expect(find.text('CLOUD MODEL'), findsNothing);
    });

    testWidgets('a blank question is not sent', (tester) async {
      await pumpApp(tester, const ChatScreen());

      await tester.enterText(find.byType(TextField), '    ');
      await tester.tap(find.byTooltip('Send'));
      await pumpFrames(tester);

      // Still in the empty state, so nothing was appended to the thread.
      expect(find.text('How am I doing?'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('a local question is answered from the records', (tester) async {
      await seed(tester, () async {
        await store.put('nickname', 'kami');
        await store.put('goals', 'two more clients');
        await store.completeOnboarding();
      });
      await pumpApp(tester, const ChatScreen());

      await tester.enterText(find.byType(TextField), 'what are my goals?');
      await tester.tap(find.byTooltip('Send'));
      await pumpFrames(tester);

      expect(find.textContaining('two more clients'), findsOneWidget);
      // The badge names the engine, so it says which one answered rather than
      // just claiming it was local.
      expect(find.text('FROM YOUR RECORDS'), findsWidgets);
    });

    testWidgets('a question needing a person shows the handoff card', (tester) async {
      await seed(tester, store.completeOnboarding);
      await pumpApp(tester, const ChatScreen());

      await tester.enterText(find.byType(TextField), 'i want to die');
      await tester.tap(find.byTooltip('Send'));
      await pumpFrames(tester);

      expect(find.byType(HandoffCard), findsOneWidget);
      expect(
        find.text('I am stepping aside on this one. Here is who to talk to.'),
        findsOneWidget,
      );
    });

    testWidgets('a cloud question without a key says so instead of guessing',
        (tester) async {
      // The cloud engine has to be selected first. With the built-in default,
      // faith questions are answered on device, which is the point of the
      // engine picker.
      await seed(tester, () async {
        await store.completeOnboarding();
        await store.put('engine', 'cloud');
      });
      await pumpApp(tester, const ChatScreen());

      await tester.enterText(find.byType(TextField), 'is this islam');
      await tester.tap(find.byTooltip('Send'));
      await pumpFrames(tester);

      expect(find.textContaining('key is set'), findsOneWidget);
    });

    testWidgets('the thread is written to the store', (tester) async {
      await seed(tester, store.completeOnboarding);
      await pumpApp(tester, const ChatScreen());

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.tap(find.byTooltip('Send'));
      await pumpFrames(tester);

      final roles = await tester.runAsync(() async {
        final records = await store.chat();
        return records.map((r) => r.role).toList();
      });
      expect(roles, containsAll(['user', 'koru']));
    });

    testWidgets('the conversation can be cleared', (tester) async {
      await seed(tester, store.completeOnboarding);
      await pumpApp(tester, const ChatScreen());

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.tap(find.byTooltip('Send'));
      await pumpFrames(tester);

      await tester.tap(find.byTooltip('Clear conversation'));
      await pumpFrames(tester);
      await tester.tap(find.text('Clear'));
      await pumpFrames(tester);

      expect(find.text('How am I doing?'), findsOneWidget);
      final remaining = await tester.runAsync(() async => (await store.chat()).length);
      expect(remaining, 0);
    });
  });

  group('BusinessScreen', () {
    /// Adds a client and returns it, from inside the fake clock.
    Future<Client> seedClient(
      WidgetTester tester, {
      required String name,
      double? amount,
      String status = 'delivered',
      String? due,
    }) async {
      late Client created;
      await seed(tester, () async {
        final id = await store.addClient(Client(
          name: name,
          status: status,
          amount: amount,
          due: due,
          created: '2026-01-01',
        ));
        created = Client(id: id, name: name, status: status, amount: amount, due: due);
      });
      return created;
    }

    Future<void> open(WidgetTester tester) async {
      await pumpApp(tester, const BusinessScreen());
      await pumpFrames(tester);
    }

    /// Scrolls a target into view, then taps it.
    ///
    /// The screen is a long list and the test surface is 800x600, so the pay
    /// button on a client row sits below the fold. Tapping blind would either
    /// miss or need warnIfMissed turned off, and that silence would also hide a
    /// button that had genuinely moved out of reach.
    /// Scrolls a target into view, then taps it.
    ///
    /// The screen is a long list and the test surface is 800x600, so the pay
    /// button on a client row is well below the fold. ensureVisible is not
    /// enough on its own: a ListView only builds what is near the viewport, so
    /// a target that has not been built yet cannot be made visible and the
    /// finder simply reports nothing. scrollUntilVisible drives the scroll
    /// until the widget exists, and is only used when it is missing, because a
    /// button inside a bottom sheet has no list to scroll.
    Future<void> tapVisible(WidgetTester tester, Finder finder) async {
      if (finder.evaluate().isEmpty) {
        final scrollable = find.byType(Scrollable);
        if (scrollable.evaluate().isNotEmpty) {
          await tester.scrollUntilVisible(finder, 150, scrollable: scrollable.first);
          await pumpFrames(tester);
        }
      }
      await tester.tap(finder);
      await pumpFrames(tester);
    }

    /// Back to the top, where the totals live.
    ///
    /// Tapping something near the bottom leaves the summary tiles scrolled out
    /// of the tree entirely, so an assertion about the header has to come back
    /// first. A ListView also builds lazily, so scrolling is the only way to
    /// bring those tiles back rather than a plain lookup.
    Future<void> scrollToTop(WidgetTester tester) async {
      for (var i = 0; i < 3; i++) {
        await tester.drag(find.byType(ListView).first, const Offset(0, 1200));
        await pumpFrames(tester);
      }
    }

    testWidgets('shows what is owed rather than counting statuses', (tester) async {
      await seedClient(tester, name: 'Bilal', amount: 2000);
      await open(tester);

      expect(find.text('2000'), findsWidgets);
      expect(find.text('AED, 1 to chase'), findsOneWidget);
    });

    testWidgets('a part payment leaves the client outstanding, not settled',
        (tester) async {
      final bilal = await seedClient(tester, name: 'Bilal', amount: 2000);
      await open(tester);

      await tapVisible(tester, find.text('Mark paid'));

      // Defaults to the balance, so the common case is one tap.
      expect(find.text('Payment from Bilal'), findsOneWidget);
      expect(find.widgetWithText(TextField, '2000'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, '2000'), '500');
      await tapVisible(tester, find.text('Record payment'));

      final payments = await tester.runAsync(() => store.payments(clientId: bilal.id));
      expect(payments!.single.amount, 500);

      // Still owed, so the client must not have been marked settled.
      expect(find.text('1500 AED OUTSTANDING'), findsOneWidget);
      expect(find.textContaining('still outstanding'), findsOneWidget);
    });

    testWidgets('settling the balance marks the client paid', (tester) async {
      final bilal = await seedClient(tester, name: 'Bilal', amount: 2000);
      await open(tester);

      await tapVisible(tester, find.text('Mark paid'));
      await tapVisible(tester, find.text('Record payment'));

      final client =
          await tester.runAsync(() async => (await store.clients()).single);
      expect(client!.status, 'paid');
      expect(await tester.runAsync(() => store.balanceFor(bilal)), 0);
      await scrollToTop(tester);
      expect(find.text('AED, all clear'), findsOneWidget);
    });

    testWidgets('the invoice survives a payment being recorded', (tester) async {
      // The old flow overwrote the invoiced amount with whatever was typed in,
      // so recording a part payment destroyed the original figure.
      final bilal = await seedClient(tester, name: 'Bilal', amount: 2000);
      await open(tester);

      await tapVisible(tester, find.text('Mark paid'));
      await tester.enterText(find.widgetWithText(TextField, '2000'), '500');
      await tapVisible(tester, find.text('Record payment'));

      final client =
          await tester.runAsync(() async => (await store.clients()).single);
      expect(client!.amount, 2000);
      expect(await tester.runAsync(() => store.balanceFor(bilal)), 1500);
    });

    testWidgets('an empty amount records nothing rather than inventing one',
        (tester) async {
      final bilal = await seedClient(tester, name: 'Bilal', amount: 2000);
      await open(tester);

      await tapVisible(tester, find.text('Mark paid'));
      await tester.enterText(find.widgetWithText(TextField, '2000'), '');
      await tapVisible(tester, find.text('Record payment'));

      expect(await tester.runAsync(() => store.payments(clientId: bilal.id)), isEmpty);
    });

    testWidgets('a recorded payment can be undone', (tester) async {
      await seedClient(tester, name: 'Bilal', amount: 2000);
      await open(tester);

      await tapVisible(tester, find.text('Mark paid'));
      await tester.enterText(find.widgetWithText(TextField, '2000'), '750');
      await tapVisible(tester, find.text('Record payment'));

      expect(find.text('750 AED  ·  Bilal'), findsOneWidget);

      await tapVisible(tester, find.byTooltip('Undo this payment'));

      expect(await tester.runAsync(() => store.payments()), isEmpty);
      await scrollToTop(tester);
      expect(find.text('2000'), findsWidgets);
      expect(find.text('AED, 1 to chase'), findsOneWidget);
    });

    testWidgets('deadlines can be added and ticked off', (tester) async {
      await seedClient(tester, name: 'Bilal', amount: 100);
      await open(tester);

      expect(find.text('Nothing scheduled'), findsOneWidget);

      await tapVisible(tester, find.text('Add'));
      await tester.enterText(find.widgetWithText(TextField, 'What'), 'Send invoice');
      await tapVisible(tester, find.text('Add deadline'));

      expect(find.textContaining('Send invoice'), findsWidgets);

      await tapVisible(tester, find.byTooltip('Mark Send invoice done'));

      expect(await tester.runAsync(() => store.deadlines()), isEmpty);
    });
  });

  group('shared widgets', () {
    testWidgets('KoruPill renders its label', (tester) async {
      await pumpApp(
        tester,
        const Scaffold(
          body: KoruPill(label: 'PAID', color: KoruColors.leaf, background: KoruColors.leafSoft),
        ),
      );
      expect(find.text('PAID'), findsOneWidget);
    });

    testWidgets('StatTile shows value and sub', (tester) async {
      await pumpApp(
        tester,
        const Scaffold(
          body: StatTile(
            label: 'OWED',
            value: '2,400',
            sub: 'across 3 clients',
            tint: KoruColors.leaf,
            tintBg: KoruColors.leafSoft,
          ),
        ),
      );
      expect(find.text('2,400'), findsOneWidget);
      expect(find.text('across 3 clients'), findsOneWidget);
    });

    testWidgets('EmptyHint can carry an action', (tester) async {
      await pumpApp(
        tester,
        Scaffold(
          body: EmptyHint(
            icon: Icons.folder_open_rounded,
            title: 'No clients yet',
            body: 'Add one to start.',
            action: FilledButton(onPressed: () {}, child: const Text('Add a client')),
          ),
        ),
      );
      expect(find.text('Add a client'), findsOneWidget);
    });
  });
}
