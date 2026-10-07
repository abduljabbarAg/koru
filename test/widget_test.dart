import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koru/handoff.dart';
import 'package:koru/main.dart';
import 'package:koru/mascot/mascot.dart';
import 'package:koru/onboarding.dart';
import 'package:koru/screens/chat.dart';
import 'package:koru/screens/knowledge.dart';
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
          cloudKeyProvider.overrideWith((ref) async => ''),
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
      expect(await store.readKey(), '');
      await store.writeKey('sk-or-v1-abc');
      expect(await store.readKey(), 'sk-or-v1-abc');
      await store.clearKey();
      expect(await store.readKey(), '');
    });
  });

  group('Onboarding', () {
    /// Walks the whole flow the way a person does. The regression this covers is
    /// real: the Start button used to do nothing, because RootGate held the
    /// onboarded flag in a field and never watched the provider onboarding set.
    testWidgets('Start on the last step lands you in the app', (tester) async {
      await pumpApp(tester, const RootGate());

      // Splash first: it holds for a minimum time on purpose.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1700));
      await pumpFrames(tester);
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
      await tester.tap(find.text('Early career'));
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

      final saved = await tester.runAsync(() async => <String, String?>{
            'onboarded': await store.get('onboarded'),
            'nickname': await store.get('nickname'),
            'stage': await store.get('stage'),
            'business': await store.get('business'),
            'goals': await store.get('goals'),
          });
      expect(saved['onboarded'], '1');
      expect(saved['nickname'], 'kami');
      expect(saved['stage'], 'Early career');
      expect(saved['business'], 'Employee');
      expect(saved['goals'], 'ship two more clients');
    });

    testWidgets('help topics are multi-select and all of them persist',
        (tester) async {
      await pumpApp(tester, const OnboardingScreen());

      for (var i = 0; i < 5; i++) {
        await tester.tap(find.text('Continue'));
        await pumpFrames(tester);
      }
      expect(find.text('Start'), findsOneWidget);

      await tester.tap(find.text('Career'));
      await pumpFrames(tester);
      await tester.tap(find.text('Fitness'));
      await pumpFrames(tester);
      await tester.tap(find.text('Learning'));
      await pumpFrames(tester);

      // All three stay selected at once.
      expect(find.byType(ChoiceChip), findsNWidgets(5));
      expect(
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Career')).selected,
        isTrue,
      );
      expect(
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Fitness')).selected,
        isTrue,
      );
      expect(
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Learning')).selected,
        isTrue,
      );
      expect(
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Business growth')).selected,
        isFalse,
      );

      await tester.tap(find.text('Start'));
      await pumpFrames(tester, frames: 12);

      final focus = await tester.runAsync(() => store.get('help_focus'));
      expect(focus, 'Career, Fitness, Learning');
    });

    testWidgets('tapping a help topic again deselects it', (tester) async {
      await pumpApp(tester, const OnboardingScreen());

      for (var i = 0; i < 5; i++) {
        await tester.tap(find.text('Continue'));
        await pumpFrames(tester);
      }

      await tester.tap(find.text('Career'));
      await pumpFrames(tester);
      expect(
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Career')).selected,
        isTrue,
      );

      await tester.tap(find.text('Career'));
      await pumpFrames(tester);
      expect(
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Career')).selected,
        isFalse,
      );
    });

    testWidgets('All of it is a shortcut and clears the other picks',
        (tester) async {
      await pumpApp(tester, const OnboardingScreen());

      for (var i = 0; i < 5; i++) {
        await tester.tap(find.text('Continue'));
        await pumpFrames(tester);
      }

      await tester.tap(find.text('Career'));
      await pumpFrames(tester);
      await tester.tap(find.text('All of it'));
      await pumpFrames(tester);

      expect(
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'All of it')).selected,
        isTrue,
      );
      expect(
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Career')).selected,
        isFalse,
      );

      // Picking something specific drops the shortcut.
      await tester.tap(find.text('Fitness'));
      await pumpFrames(tester);
      expect(
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'All of it')).selected,
        isFalse,
      );
      expect(
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Fitness')).selected,
        isTrue,
      );

      await tester.tap(find.text('Start'));
      await pumpFrames(tester, frames: 12);
      final focus = await tester.runAsync(() => store.get('help_focus'));
      expect(focus, 'Fitness');
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
      expect(find.text('ON DEVICE'), findsWidgets);
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
      await seed(tester, store.completeOnboarding);
      await pumpApp(tester, const ChatScreen());

      await tester.enterText(find.byType(TextField), 'is this islam');
      await tester.tap(find.byTooltip('Send'));
      await pumpFrames(tester);

      expect(find.textContaining('do not have a cloud key'), findsOneWidget);
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

  group('KnowledgeScreen', () {
    testWidgets('shows an empty state that can start a topic', (tester) async {
      await pumpApp(tester, const KnowledgeScreen());

      expect(find.text('Nothing on the list'), findsOneWidget);
      expect(find.text('Add a topic'), findsOneWidget);
    });

    testWidgets('adding a topic shows progress', (tester) async {
      await pumpApp(tester, const KnowledgeScreen());

      await tester.tap(find.text('Add a topic'));
      await pumpFrames(tester);

      await tester.enterText(find.widgetWithText(TextField, 'Topic'), 'Rust');
      await tester.tap(find.text('Add topic'));
      await pumpFrames(tester);

      expect(find.text('Rust'), findsOneWidget);
      // Once on the topic's pill, once on the average tile.
      expect(find.text('0%'), findsNWidgets(2));
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
            label: 'BMI',
            value: '22.4',
            sub: 'from weight + height',
            tint: KoruColors.leaf,
            tintBg: KoruColors.leafSoft,
          ),
        ),
      );
      expect(find.text('22.4'), findsOneWidget);
      expect(find.text('from weight + height'), findsOneWidget);
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
