import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koru/attention_bridge.dart';
import 'package:koru/handoff.dart';
import 'package:koru/main.dart';
import 'package:koru/mascot/mascot.dart';
import 'package:koru/models.dart';
import 'package:koru/onboarding.dart';
import 'package:koru/screens/chat.dart';
import 'package:koru/screens/clients.dart';
import 'package:koru/screens/permissions_intro.dart';
import 'package:koru/screens/revenue.dart';
import 'package:koru/screens/tasks.dart';
import 'package:koru/secrets.dart';
import 'package:koru/state.dart';
import 'package:koru/store.dart';
import 'package:koru/theme.dart';
import 'package:koru/widgets.dart';
import 'package:koru/widgets/thinking_dots.dart';

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
          // What a phone that has granted nothing looks like, stated rather than
          // left to a plugin that has no platform behind it in a test. The gate
          // asks these before it will let anybody in, so an unanswerable channel
          // here is a loading screen that never resolves.
          healthProvider.overrideWith((ref) async =>
              const KoruHealth(notifications: false, batteryExempt: false)),
          calendarPermissionProvider.overrideWith((ref) async => false),
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
  /// page, where the help chips are.
  ///
  /// Start is not on this page any more: there is a review screen after it, so
  /// what used to be the last step is now the second to last.
  Future<void> advanceToGoals(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.text('Continue'));
      await pumpFrames(tester);
    }
    expect(find.text('How many clients can you serve well?').evaluate().isEmpty,
        isTrue,
        reason: 'should be on the goals page');
  }

  group('Onboarding', () {
    /// The review exists so a person can see what the assistant was told before
    /// it starts answering from it. Skipping a question used to be invisible:
    /// nothing was stored, and nothing said so either, which is the same silence
    /// that made the client screen read zero.
    testWidgets('the review names what was left unanswered', (tester) async {
      useTallSurface(tester);
      await pumpApp(tester, const OnboardingScreen());

      // Straight through, answering nothing.
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.text('Continue'));
        await pumpFrames(tester);
      }
      await tester.tap(find.text('Continue'));
      await pumpFrames(tester);

      expect(find.text('This is what Koru will know'), findsOneWidget);
      // The nickname, the stage and the goals were all skipped.
      expect(find.text('not set'), findsWidgets);
      // And it says so rather than pretending to have everything.
      expect(find.textContaining('are empty'), findsOneWidget);
    });

    testWidgets('an empty answer can be jumped back to', (tester) async {
      useTallSurface(tester);
      await pumpApp(tester, const OnboardingScreen());

      for (var i = 0; i < 6; i++) {
        await tester.tap(find.text('Continue'));
        await pumpFrames(tester);
      }
      expect(find.text('This is what Koru will know'), findsOneWidget);

      // The pencil beside a missing answer takes you back to that question.
      await tester.tap(find.byIcon(Icons.edit_outlined).first);
      await pumpFrames(tester);

      expect(find.text('This is what Koru will know'), findsNothing,
          reason: 'should have gone back to the question it came from');
    });

    /// Walks the whole flow the way a person does. The regression this covers is
    /// real: the Start button used to do nothing, because RootGate held the
    /// onboarded flag in a field and never watched the provider onboarding set.
    /// The regression that made the app unusable. The splash used to hold until
    /// the engine reported progress, which made the start screen hostage to work
    /// happening behind it: a system dialog for battery optimisation, a slow
    /// model copy, a health check that never answered. Any of those left the
    /// user on the splash with nothing to tap.
    ///
    /// So the splash now leaves on a plain timer that none of that can starve.
    testWidgets('the splash leaves on a timer whatever the engine is doing',
        (tester) async {
      useTallSurface(tester);
      await pumpApp(tester, const RootGate());

      // Put the engine into its slowest possible state: warming, and never
      // finishing. A splash that waited on this would hang forever.
      final container = ProviderScope.containerOf(
          tester.element(find.byType(RootGate)));
      container.read(chatProvider.notifier);
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      await pumpFrames(tester, frames: 12);

      expect(find.byType(SplashScreen), findsNothing,
          reason: 'the splash must not wait on the engine');
      expect(find.byType(OnboardingScreen), findsOneWidget);
    });

    testWidgets('Start on the last step lands you in the app', (tester) async {
      useTallSurface(tester);
      // No seeding needed. The permission explanation is only offered to somebody
      // who has finished onboarding, and this starts them before onboarding, so
      // it cannot be in the way. It used to seed asked_permissions='1' here to
      // keep the screen out of the way, which is the flag whose meaning this
      // change removed.
      await pumpApp(tester, const RootGate());

      // Splash first: it holds for a minimum time, and it only starts once the
      // store read in initState resolves, so give both room.
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
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
      await tester.enterText(find.byType(TextField), 'ship two more clients');
      await pumpFrames(tester);
      await tester.tap(find.text('Continue'));
      await pumpFrames(tester);

      // review, before anything is committed
      expect(find.text('Start'), findsOneWidget);
      // Everything was answered on the way through, so nothing is flagged.
      expect(find.text('not set'), findsNothing);
      await tester.tap(find.text('Start'));
      await pumpFrames(tester, frames: 12);

      // The permission explanation is owed the moment onboarding finishes, on the
      // first run and without a restart. It used not to be: the gate decided the
      // question at launch, answered "nothing to ask about" because onboarding
      // had not happened yet, and never asked again for the rest of the session.
      expect(find.byType(PermissionsIntroScreen), findsOneWidget);

      await tester.tap(find.text('Not now'));
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

      // Capacity, then goals, then the review screen where Start now lives.
      await tester.tap(find.text('Continue'));
      await pumpFrames(tester);
      await tester.tap(find.text('Continue'));
      await pumpFrames(tester);
      expect(find.text('This is what Koru will know'), findsOneWidget);
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
      await tester.tap(find.text('Continue'));
      await pumpFrames(tester);
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
      expect(find.byType(KoruSelectablePill), findsNWidgets(5));
      expect(
        tester.widget<KoruSelectablePill>(
                find.widgetWithText(KoruSelectablePill, 'Finding clients')).selected,
        isTrue,
      );
      expect(
        tester.widget<KoruSelectablePill>(
                find.widgetWithText(KoruSelectablePill, 'Getting paid')).selected,
        isTrue,
      );
      expect(
        tester.widget<KoruSelectablePill>(
                find.widgetWithText(KoruSelectablePill, 'Pricing')).selected,
        isTrue,
      );
      expect(
        tester.widget<KoruSelectablePill>(
                find.widgetWithText(KoruSelectablePill, 'Staying organised')).selected,
        isFalse,
      );

      await tester.tap(find.text('Continue'));
      await pumpFrames(tester);
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
        tester.widget<KoruSelectablePill>(
                find.widgetWithText(KoruSelectablePill, 'Pricing')).selected,
        isTrue,
      );

      await tapChip(tester, 'Pricing');
      expect(
        tester.widget<KoruSelectablePill>(
                find.widgetWithText(KoruSelectablePill, 'Pricing')).selected,
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
        tester.widget<KoruSelectablePill>(
                find.widgetWithText(KoruSelectablePill, 'All of it')).selected,
        isTrue,
      );
      expect(
        tester.widget<KoruSelectablePill>(
                find.widgetWithText(KoruSelectablePill, 'Pricing')).selected,
        isFalse,
      );

      // Picking something specific drops the shortcut.
      await tapChip(tester, 'Getting paid');
      expect(
        tester.widget<KoruSelectablePill>(
                find.widgetWithText(KoruSelectablePill, 'All of it')).selected,
        isFalse,
      );
      expect(
        tester.widget<KoruSelectablePill>(
                find.widgetWithText(KoruSelectablePill, 'Getting paid')).selected,
        isTrue,
      );

      await tester.tap(find.text('Continue'));
      await pumpFrames(tester);
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
      expect(find.textContaining('answered by the local model'), findsOneWidget);
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

    testWidgets('an unanswered question says the engine is not running, and offers '
        'to start it', (tester) async {
      // No model is serving in a widget test and there is no second engine to
      // answer instead, which is exactly the state the deleted built-in
      // assistant used to paper over with an answer out of the records. The
      // question asked for the profile; the profile must not be read back as if
      // a model had said it.
      await seed(tester, () async {
        await store.put('nickname', 'kami');
        await store.put('goals', 'two more clients');
        await store.completeOnboarding();
        await store.put('engine', 'onDevice');
      });
      await pumpApp(tester, const ChatScreen());

      await tester.enterText(find.byType(TextField), 'what are my goals?');
      await tester.tap(find.byTooltip('Send'));
      await pumpFrames(tester, frames: 20);

      expect(find.textContaining('cannot answer'), findsWidgets);
      expect(find.textContaining('two more clients'), findsNothing,
          reason: 'the answer must not be written out of the records');
      expect(find.text('Start the local model'), findsOneWidget);
      // Nothing on the reply claims a model produced the sentence above it.
      // Scoped to the badge, because the app bar above names the engine that is
      // selected, which is a different claim and a true one.
      expect(
        find.descendant(
          of: find.byType(KoruEngineBadge),
          matching: find.text('LOCAL MODEL'),
        ),
        findsNothing,
      );
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
      // The online engine has to be selected first, because the on-device one is
      // the default and is what answers when nothing else can. It used to answer
      // from the user's records with a bracketed note about the key underneath,
      // which is how a missing key looked like a working assistant.
      await seed(tester, () async {
        await store.completeOnboarding();
        await store.put('engine', 'cloud');
      });
      await pumpApp(tester, const ChatScreen());

      await tester.enterText(find.byType(TextField), 'is this islam');
      await tester.tap(find.byTooltip('Send'));
      await pumpFrames(tester, frames: 12);

      expect(find.textContaining('key is set'), findsWidgets);
      expect(find.textContaining('cannot answer'), findsWidgets);
      // And the fix is offered rather than described in a privacy policy.
      expect(find.text('Add a cloud key'), findsOneWidget);
    });

    testWidgets('the thread is written to the store', (tester) async {
      await seed(tester, store.completeOnboarding);
      await pumpApp(tester, const ChatScreen());

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.tap(find.byTooltip('Send'));
      // Enough frames for the engine path to finish saying it cannot answer.
      await pumpFrames(tester, frames: 20);

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
      // Enough frames for the engine path to finish saying it cannot answer.
      await pumpFrames(tester, frames: 20);

      await tester.tap(find.byTooltip('Clear conversation'));
      await pumpFrames(tester);
      await tester.tap(find.text('Clear'));
      await pumpFrames(tester);

      expect(find.text('How am I doing?'), findsOneWidget);
      final remaining = await tester.runAsync(() async => (await store.chat()).length);
      expect(remaining, 0);
    });
  });

  group('the client and money tabs', () {
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

    /// Opens one of the three tabs the old Business screen was split into.
    ///
    /// Which one is named per test rather than assumed, because the split is the
    /// point: a client's row and the money they owe are two different questions
    /// and the tests should be answering them somewhere that says so.
    Future<void> open(WidgetTester tester,
        {Widget screen = const ClientsScreen()}) async {
      await pumpApp(tester, screen);
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
    /// finder simply reports nothing, so scrollUntilVisible drives the list until
    /// the widget exists. A target that is already built only needs nudging into
    /// view, which is what ensureVisible does, and the two cases are kept apart
    /// because ensureVisible throws on a finder that matches nothing.
    Future<void> tapVisible(WidgetTester tester, Finder finder) async {
      if (finder.evaluate().isEmpty) {
        // Not built yet, so the list has to be driven until it exists.
        final scrollable = find.byType(Scrollable);
        if (scrollable.evaluate().isNotEmpty) {
          await tester.scrollUntilVisible(finder, 150, scrollable: scrollable.first);
          await pumpFrames(tester);
        }
      } else {
        // Built, but possibly straddling the edge of the viewport, where a tap
        // lands on whatever is painted over it instead.
        await tester.ensureVisible(finder);
        await pumpFrames(tester);
      }
      await tester.tap(finder);
      await pumpFrames(tester);
    }

    /// Drags the page until a target exists in the tree.
    ///
    /// A ListView only builds what is near the viewport, so a section further
    /// down is not in the tree at all and the finder reports nothing — which
    /// reads exactly like the row not being there.
    Future<void> reveal(WidgetTester tester, Finder finder) async {
      final list = find.byType(Scrollable);
      if (list.evaluate().isEmpty) return;
      for (var i = 0; i < 12 && finder.evaluate().isEmpty; i++) {
        await tester.drag(list.first, const Offset(0, -240));
        await pumpFrames(tester, frames: 2);
      }
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
      await open(tester, screen: const RevenueScreen());

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
      // The figure lives on the money tab now, which is where somebody asks the
      // "all clear" question.
      await open(tester, screen: const RevenueScreen());
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

      // Recorded on the client's row, listed in the ledger on the money tab.
      await open(tester, screen: const RevenueScreen());
      await reveal(tester, find.text('750 AED  ·  Bilal'));
      expect(find.text('750 AED  ·  Bilal'), findsOneWidget);

      await tapVisible(tester, find.byTooltip('Undo this payment'));

      expect(await tester.runAsync(() => store.payments()), isEmpty);
      await scrollToTop(tester);
      expect(find.text('2000'), findsWidgets);
      expect(find.text('AED, 1 to chase'), findsOneWidget);
    });

    testWidgets('deadlines can be added and ticked off', (tester) async {
      await seedClient(tester, name: 'Bilal', amount: 100);
      // A deadline is work with a date on it, so it is listed with the rest of
      // the work rather than inside a page about money.
      await open(tester, screen: const TasksScreen());

      expect(find.text('Nothing scheduled'), findsOneWidget);

      await tapVisible(tester, find.text('Add'));
      await tester.enterText(find.widgetWithText(TextField, 'What'), 'Send invoice');
      await tapVisible(tester, find.text('Add deadline'));

      expect(find.textContaining('Send invoice'), findsWidgets);

      await tapVisible(tester, find.byTooltip('Mark Send invoice done'));

      expect(await tester.runAsync(() => store.deadlines()), isEmpty);
    });
  });

  group('the waiting indicator', () {
    testWidgets('says what the model is doing, not just that something is',
        (tester) async {
      // The dots answered "is it working". They did not answer "is it working on
      // the right thing", and on this phone prefill takes seconds and decode
      // runs at four tokens a second, which feel identical as bouncing dots.
      await pumpApp(tester, const MaterialApp(
        home: Scaffold(body: KoruThinkingDots(activity: KoruActivity.reading)),
      ));
      expect(find.text('Reading your records'), findsOneWidget);
    });

    testWidgets('every phase has its own wording', (tester) async {
      final labels = <String, KoruActivity>{
        'Waking up': KoruActivity.waking,
        'Reading your records': KoruActivity.reading,
        'Writing an answer': KoruActivity.writing,
        'Working out what you meant': KoruActivity.thinking,
      };
      for (final entry in labels.entries) {
        await pumpApp(tester, MaterialApp(
          home: Scaffold(body: KoruThinkingDots(activity: entry.value)),
        ));
        expect(find.text(entry.key), findsOneWidget,
            reason: 'for ${entry.value}');
      }
    });

    testWidgets('it animates rather than sitting still', (tester) async {
      await pumpApp(tester, const MaterialApp(
        home: Scaffold(body: KoruThinkingDots()),
      ));
      // Repeated forever, because the whole point is that the screen is not
      // frozen while the model works.
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.hasRunningAnimations, isTrue);
    });
  });

  group('shared widgets', () {
    testWidgets('KoruPill renders its label', (tester) async {
      await pumpApp(
        tester,
        Scaffold(
          body: KoruPill(label: 'PAID', color: KoruColors.leaf, background: KoruColors.leafSoft),
        ),
      );
      expect(find.text('PAID'), findsOneWidget);
    });

    testWidgets('StatTile shows value and sub', (tester) async {
      await pumpApp(
        tester,
        Scaffold(
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
