import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koru/models.dart';
import 'package:koru/screens/client_detail.dart';
import 'package:koru/screens/tasks.dart';
import 'package:koru/screens/today.dart';
import 'package:koru/secrets.dart';
import 'package:koru/state.dart';
import 'package:koru/store.dart';
import 'package:koru/theme.dart';

import 'test_store.dart';

/// The two screens somebody opens to get something done, driven the way a person
/// drives them: type, tap the tick, read what is on screen, then confirm against
/// the database.
void main() {
  late ProfileStore store;

  setUpAll(initTestDatabase);

  setUp(() async {
    store = await openTestStore();
  });

  Future<void> pump(WidgetTester tester, {int frames = 8}) async {
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
        child: MaterialApp(theme: buildKoruTheme(), home: child),
      ),
    );
    await pump(tester);
  }

  /// A date relative to today, in the form the store speaks.
  String inDays(int days) {
    final d = DateTime.now().add(Duration(days: days));
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  /// Writes straight to the store, from the real async zone, which is where a
  /// widget test body cannot go.
  Future<Task> seedTask(
    String title, {
    int? dueIn,
    int? clientId,
    int? projectId,
    TaskPriority priority = TaskPriority.normal,
    bool done = false,
  }) async {
    final record = Task(
      title: title,
      due: dueIn == null ? null : inDays(dueIn),
      clientId: clientId,
      projectId: projectId,
      priority: priority,
      done: done,
      completedAt: done ? DateTime.now().toIso8601String() : null,
      created: DateTime.now().toIso8601String(),
    );
    await store.addTask(record);
    return Task(
      title: record.title,
      due: record.due,
      clientId: record.clientId,
      projectId: record.projectId,
      priority: record.priority,
      done: record.done,
      completedAt: record.completedAt,
      created: record.created,
    );
  }

  group('the task list', () {
    testWidgets('work with no client and no project can be added from the list',
        (tester) async {
      await mount(tester, const TasksScreen());

      // A first run says what belongs here, rather than showing an empty card.
      expect(find.text('Nothing outstanding'), findsOneWidget);

      await tester.tap(find.widgetWithText(FloatingActionButton, 'Task'));
      await pump(tester);
      await tester.enterText(find.byType(TextField).first, 'Renew the domain');
      await pump(tester);
      // The sheet scrolls, and its save button is below the fold on a short
      // screen. Tapping it blind would be a tap on whatever is painted there.
      await tester.ensureVisible(find.text('Add task'));
      await pump(tester);
      await tester.tap(find.text('Add task'));
      await pump(tester, frames: 12);

      expect(find.text('Renew the domain'), findsOneWidget);

      final task = (await tester.runAsync(() => store.tasks()))!.single;
      expect(task.title, 'Renew the domain');
      // The case the whole table was added for: a chore with no client and no
      // project, which had nowhere to live before.
      expect(task.clientId, isNull);
      expect(task.projectId, isNull);
      expect(task.priority, TaskPriority.normal);
    });

    testWidgets('a task is ticked off from the list, without opening anything',
        (tester) async {
      await seedTask('Chase the deposit');
      await mount(tester, const TasksScreen());

      // No project exists, so this cannot have gone anywhere to be ticked off.
      expect(await tester.runAsync(() => store.projects()), isEmpty);
      expect(find.text('PENDING (1)'), findsOneWidget);

      await tester.tap(find.byTooltip('Mark Chase the deposit done'));
      await pump(tester);

      final after = (await tester.runAsync(() => store.tasks()))!.single;
      expect(after.done, isTrue);
      // The moment moves with the flag, so the archive can say when.
      expect(after.completedAt, isNotNull);
      expect(find.text('PENDING (0)'), findsOneWidget);
      expect(find.text('DONE (1)'), findsOneWidget);
    });

    testWidgets('a finished task can be put back on the list', (tester) async {
      await seedTask('Chase the deposit', done: true);
      await mount(tester, const TasksScreen());

      await tester.ensureVisible(find.text('DONE (1)'));
      await pump(tester);
      expect(find.text('DONE (1)'), findsOneWidget);

      await tester.tap(find.byTooltip('Put Chase the deposit back on the list'));
      await pump(tester, frames: 12);

      final after = (await tester.runAsync(() => store.tasks()))!.single;
      expect(after.done, isFalse);
      expect(after.completedAt, isNull);

      // Back to the top, where the pending list is: the archive is below it and
      // a ListView only builds what is near the viewport.
      for (var i = 0; i < 3; i++) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, 900));
        await pump(tester, frames: 2);
      }
      expect(find.text('PENDING (1)'), findsOneWidget);
    });

    testWidgets('a finished task keeps its row rather than disappearing',
        (tester) async {
      await seedTask('Shipped the invoice', done: true);
      await mount(tester, const TasksScreen());

      // Archived, not deleted: a week of work has to leave a trace or the list
      // cannot answer what actually got done.
      expect(find.text('Shipped the invoice'), findsOneWidget);
      expect(find.textContaining('Done'), findsWidgets);
    });

    testWidgets('the list is ordered by what is late, then by priority',
        (tester) async {
      await seedTask('undated chore', priority: TaskPriority.high);
      await seedTask('two days late', dueIn: -2, priority: TaskPriority.low);
      await seedTask('due in a week', dueIn: 7);
      await mount(tester, const TasksScreen());

      double topOf(String text) => tester.getTopLeft(find.text(text)).dy;

      // The most overdue is first whatever its priority, then the high-priority
      // one with no date, then the dated one further out.
      expect(topOf('two days late'), lessThan(topOf('undated chore')));
      expect(topOf('undated chore'), lessThan(topOf('due in a week')));
    });

    testWidgets('priority says itself on the row', (tester) async {
      await seedTask('the urgent one', priority: TaskPriority.high);
      await mount(tester, const TasksScreen());

      expect(find.text('HIGH'), findsOneWidget);
      // Nothing is drawn for the middle, which is what most rows are.
      expect(find.text('NORMAL'), findsNothing);
    });
  });

  /// Drags the screen until a target exists in the tree.
  ///
  /// Today's sections are one long list, so the notices sit below the fold on a
  /// test-sized screen and a lazy list never builds what it cannot show, which
  /// reads exactly like the section not existing.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    final list = find.byType(Scrollable);
    if (list.evaluate().isEmpty) return;
    for (var i = 0; i < 15 && finder.evaluate().isEmpty; i++) {
      await tester.drag(list.first, const Offset(0, -240));
      await pump(tester, frames: 2);
    }
  }

  group('the morning queue', () {
    testWidgets('separates the work from the notices', (tester) async {
      final clientId = (await tester.runAsync(() => store.addClient(Client(
            name: 'Acme',
            status: 'delivered',
            amount: 2000,
            due: inDays(-4),
            created: '2026-01-01',
          ))))!;
      await seedTask('Send the revised quote', dueIn: 0, clientId: clientId);
      await mount(tester, const TodayScreen());

      // The work is its own list, and the row does not carry the client: the
      // client is who the work is for, not who is doing it.
      expect(find.text('DO THIS NEXT'), findsOneWidget);
      expect(find.text('Send the revised quote'), findsOneWidget);
      expect(find.text('Due today'), findsOneWidget);
      expect(find.text('Acme  ·  Due today'), findsNothing);
      expect(find.text('Done for today'), findsNothing);

      // Money sits under Notices rather than mixed into the work.
      await reveal(tester, find.text('Acme owes you'));
      expect(find.text('NOTICES'), findsOneWidget);
      expect(find.text('Acme owes you'), findsOneWidget);
      expect(find.textContaining('2000 AED'), findsOneWidget);
      expect(find.textContaining('overdue by 4 days'), findsOneWidget);
    });

    testWidgets('a morning of only notices says there is no work', (tester) async {
      await tester.runAsync(() => store.addClient(Client(
            name: 'Acme',
            status: 'delivered',
            amount: 2000,
            due: inDays(-4),
            created: '2026-01-01',
          )));
      await mount(tester, const TodayScreen());

      // Not the all-clear: a late invoice is not a clear day.
      expect(find.text('Done for today'), findsNothing);
      expect(find.text('Nothing of your own waiting'), findsOneWidget);

      await reveal(tester, find.text('NOTICES'));
      expect(find.text('NOTICES'), findsOneWidget);
      expect(find.text('Acme owes you'), findsOneWidget);
    });

    testWidgets('Show me dismisses the morning card and the work stays',
        (tester) async {
      // The button used to only close the card, so tapping "Show me" showed
      // nothing at all. It now also travels the page to the queue.
      await seedTask('Renew the domain', dueIn: 1);
      await mount(tester, const TodayScreen());

      expect(find.text('Show me'), findsOneWidget);
      await tester.tap(find.text('Show me'));
      await pump(tester, frames: 20);

      expect(find.text('Show me'), findsNothing);
      expect(find.text('DO THIS NEXT'), findsOneWidget);
      expect(find.text('Renew the domain'), findsOneWidget);
    });

    testWidgets('a chore with no client is on the morning too', (tester) async {
      await seedTask('Call the accountant', dueIn: 1);
      await mount(tester, const TodayScreen());

      expect(find.text('Call the accountant'), findsOneWidget);
      expect(find.text('tomorrow'), findsOneWidget);
    });

    testWidgets('tapping a row opens the thing it is about', (tester) async {
      final clientId = (await tester.runAsync(() => store.addClient(Client(
            name: 'Acme',
            status: 'delivered',
            amount: 2000,
            due: inDays(-4),
            created: '2026-01-01',
          ))))!;
      await mount(tester, const TodayScreen());

      await reveal(tester, find.text('Acme owes you'));
      // A lazy list builds a little past the fold, so finding the row is not
      // the same as it being on screen; scroll it the rest of the way in.
      await tester.ensureVisible(find.text('Acme owes you'));
      await pump(tester);
      await tester.tap(find.text('Acme owes you'));
      await pump(tester);

      expect(find.byType(ClientDetailScreen), findsOneWidget);
      expect(clientId, 1);
    });

    testWidgets('a task on the morning can be ticked off where it stands',
        (tester) async {
      await seedTask('Chase the deposit', dueIn: 0);
      await mount(tester, const TodayScreen());

      await tester.tap(find.byTooltip('Mark Chase the deposit done'));
      await pump(tester);

      final after = (await tester.runAsync(() => store.tasks()))!.single;
      expect(after.done, isTrue);
      expect(find.text('Chase the deposit'), findsNothing);
      expect(find.text('Done for today'), findsOneWidget);
    });

    testWidgets('an empty morning says what to do instead', (tester) async {
      await mount(tester, const TodayScreen());
      expect(find.text('Done for today'), findsOneWidget);
      // Still a way out of the empty state, not just an explanation of it.
      expect(find.text('All work'), findsOneWidget);
    });

    testWidgets('a task can be created from the morning, empty day and all',
        (tester) async {
      await mount(tester, const TodayScreen());

      // The emptiest day there is still offers the way to put work on it.
      expect(find.text('DO THIS NEXT'), findsOneWidget);

      await tester.ensureVisible(find.text('Add a task'));
      await pump(tester);
      await tester.tap(find.text('Add a task'));
      await pump(tester);
      await tester.enterText(find.byType(TextField).first, 'Renew the domain');
      await pump(tester);
      await tester.ensureVisible(find.text('Add task'));
      await pump(tester);
      await tester.tap(find.text('Add task'));
      await pump(tester, frames: 12);

      expect(find.text('Renew the domain'), findsOneWidget);
      expect(find.text('Done for today'), findsNothing);

      final task = (await tester.runAsync(() => store.tasks()))!.single;
      expect(task.title, 'Renew the domain');
    });

    testWidgets('All work opens the full list from an empty day',
        (tester) async {
      await mount(tester, const TodayScreen());

      await tester.tap(find.text('All work'));
      await pump(tester, frames: 12);

      expect(find.byType(TasksScreen), findsOneWidget);
    });
  });
}