import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koru/handoff.dart';
import 'package:koru/mascot/mascot.dart';
import 'package:koru/screens/chat.dart';
import 'package:koru/screens/knowledge.dart';
import 'package:koru/secrets.dart';
import 'package:koru/state.dart';
import 'package:koru/store.dart';
import 'package:koru/theme.dart';
import 'package:koru/widgets.dart';

import 'test_store.dart';

/// Widget level checks, running against a real SQLite store so the flow under
/// test is the flow a user gets.
Future<void> pumpApp(
  WidgetTester tester,
  Widget child, {
  ProfileStore? store,
  List<Override> extra = const [],
}) async {
  final s = store ?? await openTestStore();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storeProvider.overrideWith((ref) async => s),
        cloudKeyProvider.overrideWith((ref) async => ''),
        secretsProvider.overrideWithValue(const MemoryKeyStore()),
        ...extra,
      ],
      child: MaterialApp(theme: buildKoruTheme(), home: child),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(initTestDatabase);

  group('MemoryKeyStore', () {
    test('round trips and clears', () async {
      const store = MemoryKeyStore();
      expect(await store.readKey(), '');
      await store.writeKey('sk-or-v1-abc');
      expect(await store.readKey(), 'sk-or-v1-abc');
      await store.clearKey();
      expect(await store.readKey(), '');
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
      expect(find.text('999'), findsOneWidget);
      expect(find.text('800 4673'), findsOneWidget);
      expect(find.textContaining('24 hours'), findsNWidgets(2));
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
      expect(find.bySemanticsLabel('Koru, your helper'), findsOneWidget);
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
      await tester.pump();
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
      await tester.pump();
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

    testWidgets('the greeting is labelled as on-device', (tester) async {
      await pumpApp(tester, const ChatScreen());
      expect(find.text('ON DEVICE'), findsOneWidget);
      expect(find.text('CLOUD MODEL'), findsNothing);
    });

    testWidgets('a blank question is not sent', (tester) async {
      await pumpApp(tester, const ChatScreen());

      await tester.enterText(find.byType(TextField), '    ');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();

      expect(find.textContaining('I am here, and I run on this phone'), findsOneWidget);
    });

    testWidgets('a local question is answered from the records', (tester) async {
      final store = await openTestStore();
      await store.put('nickname', 'kami');
      await store.put('goals', 'two more clients');
      await store.completeOnboarding();

      await pumpApp(tester, const ChatScreen(), store: store);

      await tester.enterText(find.byType(TextField), 'what are my goals?');
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();

      expect(find.textContaining('two more clients'), findsOneWidget);
      expect(find.text('ON DEVICE'), findsWidgets);
    });

    testWidgets('a question needing a person shows the handoff card', (tester) async {
      final store = await openTestStore();
      await store.completeOnboarding();
      await pumpApp(tester, const ChatScreen(), store: store);

      await tester.enterText(find.byType(TextField), 'i want to die');
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();

      expect(find.byType(HandoffCard), findsOneWidget);
      expect(find.text('I am stepping aside on this one. Here is who to talk to.'),
          findsOneWidget);
    });

    testWidgets('a cloud question without a key says so instead of guessing',
        (tester) async {
      final store = await openTestStore();
      await store.completeOnboarding();
      await pumpApp(tester, const ChatScreen(), store: store);

      await tester.enterText(find.byType(TextField), 'is this islam');
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();

      expect(find.textContaining('do not have a cloud key'), findsOneWidget);
    });

    testWidgets('the thread is written to the store', (tester) async {
      final store = await openTestStore();
      await store.completeOnboarding();
      await pumpApp(tester, const ChatScreen(), store: store);

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();

      final records = await store.chat();
      expect(records.map((r) => r.role), containsAll(['user', 'koru']));
    });

    testWidgets('the conversation can be cleared', (tester) async {
      final store = await openTestStore();
      await store.completeOnboarding();
      await pumpApp(tester, const ChatScreen(), store: store);

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Clear conversation'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      expect(find.text('How am I doing?'), findsOneWidget);
      expect(await store.chat(), isEmpty);
    });
  });

  group('KnowledgeScreen', () {
    testWidgets('shows an empty state that can start a topic', (tester) async {
      await pumpApp(tester, const KnowledgeScreen());

      expect(find.text('Nothing on the list'), findsOneWidget);
      expect(find.text('Add a topic'), findsOneWidget);
    });

    testWidgets('adding a topic shows progress', (tester) async {
      final store = await openTestStore();
      await pumpApp(tester, const KnowledgeScreen(), store: store);

      await tester.tap(find.text('Add a topic'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Topic'), 'Rust');
      await tester.tap(find.text('Add topic'));
      await tester.pumpAndSettle();

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
