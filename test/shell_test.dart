import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koru/attention.dart';
import 'package:koru/deep_link.dart';
import 'package:koru/main.dart';
import 'package:koru/models.dart';
import 'package:koru/screens/chat.dart';
import 'package:koru/screens/clients.dart';
import 'package:koru/screens/revenue.dart';
import 'package:koru/screens/settings.dart';
import 'package:koru/screens/shell_actions.dart';
import 'package:koru/screens/tasks.dart';
import 'package:koru/screens/today.dart';
import 'package:koru/secrets.dart';
import 'package:koru/state.dart';
import 'package:koru/store.dart';
import 'package:koru/theme.dart';

import 'test_store.dart';

/// The shape of the app: what is in the bar, what is not, and where a tap on a
/// notification lands.
///
/// The bar used to be Today, Talk, Business, Projects, Settings, and half of it
/// was chrome — two of the five tabs were places to change the app rather than
/// to do anything with it, and the work itself was split across two tabs that
/// were never both on screen. Every rule below is a rule about that.
void main() {
  late ProfileStore store;

  setUpAll(initTestDatabase);

  setUp(() async {
    store = await openTestStore();
  });

  Future<void> pump(WidgetTester tester, {int frames = 10}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  /// Mounts the whole app, optionally holding a link that a notification tap
  /// would have left behind.
  Future<ProviderContainer> boot(
    WidgetTester tester, {
    KoruDeepLink? link,
  }) async {
    final container = ProviderContainer(
      overrides: [
        storeProvider.overrideWith((ref) async => store),
        cloudKeyProvider.overrideWith((ref, providerId) async => ''),
        secretsProvider.overrideWithValue(MemoryKeyStore()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildKoruTheme(), home: const HomeShell()),
      ),
    );
    await pump(tester);
    // Written after the shell exists, which is the cold start this time: the
    // shell reads whatever is waiting on its first frame.
    if (link != null) container.read(pendingLinkProvider.notifier).state = link;
    await pump(tester);
    return container;
  }

  group('the tab bar', () {
    testWidgets('is Today, Tasks, Clients, Revenue, in that order',
        (tester) async {
      await boot(tester);

      expect(
        KoruAppTabs.values.map((t) => t.label),
        ['Today', 'Tasks', 'Clients', 'Revenue'],
      );
      final bar = find.byType(KoruTabBar);
      for (final tab in KoruAppTabs.values) {
        expect(
          find.descendant(of: bar, matching: find.text(tab.label)),
          findsOneWidget,
          reason: '${tab.label} is in the bar',
        );
      }
    });

    testWidgets('Settings is not a tab, and is still reachable from a header',
        (tester) async {
      await boot(tester);

      // Not in the bar. The word appears nowhere along the bottom of the
      // screen, and there is no tab button with that tooltip.
      expect(find.byTooltip('Settings'), findsOneWidget,
          reason: 'one Settings control, in a header');
      expect(find.byType(SettingsScreen), findsNothing);

      // From the header of the first screen, which is the one somebody always
      // has a route back to.
      expect(find.descendant(
        of: find.byType(AppBar).first,
        matching: find.byTooltip('Settings'),
      ), findsOneWidget);

      await tester.tap(find.byTooltip('Settings'));
      await pump(tester);
      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    testWidgets('Talk is reachable without being a fifth tab', (tester) async {
      await boot(tester);

      expect(find.byType(ChatScreen), findsNothing);
      await tester.tap(find.byTooltip('Talk to Koru').first);
      await pump(tester);

      expect(find.byType(ChatScreen), findsOneWidget);
      // Pushed, not swapped in, so the queue is still underneath. A pushed
      // opaque route takes the lower one offstage, which a finder skips unless
      // it is told not to.
      expect(find.byType(HomeShell, skipOffstage: false), findsOneWidget);
    });

    testWidgets('each tab shows its own screen', (tester) async {
      await boot(tester);

      await tester.tap(find.descendant(
          of: find.byType(KoruTabBar),
          matching: find.text('Tasks'),
        ));
      await pump(tester);
      expect(find.byType(TasksScreen), findsOneWidget);

      await tester.tap(find.descendant(
          of: find.byType(KoruTabBar),
          matching: find.text('Clients'),
        ));
      await pump(tester);
      expect(find.byType(ClientsScreen), findsOneWidget);

      await tester.tap(find.descendant(
          of: find.byType(KoruTabBar),
          matching: find.text('Revenue'),
        ));
      await pump(tester);
      expect(find.byType(RevenueScreen), findsOneWidget);

      await tester.tap(find.descendant(
          of: find.byType(KoruTabBar),
          matching: find.text('Today'),
        ));
      await pump(tester);
      expect(find.byType(TodayScreen), findsOneWidget);
    });
  });

  group('where a notification lands', () {
    testWidgets('a client opens that client, from the clients tab', (tester) async {
      final id = await store.addClient(
          const Client(name: 'Acme', amount: 100, created: '2026-01-01'));
      await boot(
        tester,
        link: KoruDeepLink(
          kind: AttentionKind.overdueMoney,
          target: AttentionTarget.client,
          id: id,
        ),
      );

      expect(find.text('Acme'), findsWidgets);
      // The client screen itself is pushed over the tab, so the tab underneath
      // is offstage rather than gone.
      expect(find.byType(ClientsScreen, skipOffstage: false), findsOneWidget);
    });

    testWidgets('a deadline and an entry land on the morning, not on a balance',
        (tester) async {
      await boot(
        tester,
        link: const KoruDeepLink(
          kind: AttentionKind.dueToday,
          target: AttentionTarget.deadline,
        ),
      );
      expect(find.byType(TodayScreen), findsOneWidget);

      await tester.tap(find.descendant(
          of: find.byType(KoruTabBar),
          matching: find.text('Tasks'),
        ));
      await pump(tester);
      await tester.tap(find.descendant(
          of: find.byType(KoruTabBar),
          matching: find.text('Today'),
        ));
      await pump(tester);

      await store.addDeadline(
          const Deadline(title: 'Send invoice', due: '2026-10-20'));
      await boot(
        tester,
        link: const KoruDeepLink(
          kind: AttentionKind.eventToday,
          target: AttentionTarget.event,
        ),
      );
      expect(find.byType(TodayScreen), findsOneWidget);
    });

    testWidgets('a task lands on the task list', (tester) async {
      await boot(
        tester,
        link: const KoruDeepLink(
          kind: AttentionKind.task,
          target: AttentionTarget.task,
        ),
      );

      expect(find.byType(TasksScreen), findsOneWidget);
      expect(find.text('What needs doing'), findsOneWidget);
    });

    testWidgets('a project lands on the work tab', (tester) async {
      await boot(
        tester,
        link: const KoruDeepLink(
          kind: AttentionKind.stalledProject,
          target: AttentionTarget.project,
        ),
      );

      expect(find.byType(TasksScreen), findsOneWidget);
    });

    test('every link target maps to a real tab, and the chat is still one of them',
        () {
      for (final target in AttentionTarget.values) {
        expect(KoruAppTabs.tabFor(target), isA<KoruAppTabs>(),
            reason: '$target has somewhere to land');
      }
      // Spot-checked rather than left to the loop above, because the loop cannot
      // say whether the answer is the right one.
      expect(KoruAppTabs.tabFor(AttentionTarget.client), KoruAppTabs.clients);
      expect(KoruAppTabs.tabFor(AttentionTarget.task), KoruAppTabs.tasks);
      expect(KoruAppTabs.tabFor(AttentionTarget.deadline), KoruAppTabs.today);
      expect(KoruAppTabs.tabFor(AttentionTarget.event), KoruAppTabs.today);
      expect(KoruAppTabs.tabFor(AttentionTarget.project), KoruAppTabs.tasks);
      expect(KoruAppTabs.tabFor(AttentionTarget.chat), KoruAppTabs.today);
      // And the slots are the ones the bar actually draws.
      expect(
        [for (final t in KoruAppTabs.values) t.slot],
        [0, 1, 2, 3],
      );
    });
  });
}