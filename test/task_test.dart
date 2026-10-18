import 'package:flutter_test/flutter_test.dart';
import 'package:koru/models.dart';
import 'package:koru/store.dart';

import 'test_store.dart';

/// Tasks, as the database holds them.
///
/// The list had no table at all before this, which is the thing worth testing:
/// the screen, the queue and the notification all assume there is a list, and a
/// write that half works is how a person's week disappears without an error
/// anywhere.
void main() {
  setUpAll(initTestDatabase);

  late ProfileStore store;

  setUp(() async {
    store = await openTestStore();
  });

  /// An ISO date [days] from now, so nothing here depends on which day it is.
  String inDays(int days) => _isoOf(DateTime.now().add(Duration(days: days)));

  test('a task with no client, no project and no date is a complete record', () async {
    final id = await store.addTask(const Task(title: 'Renew the domain'));
    final task = (await store.tasks()).single;

    expect(id, isNotNull);
    expect(task.title, 'Renew the domain');
    expect(task.clientId, isNull);
    expect(task.projectId, isNull);
    expect(task.due, isNull);
    // The default has to be the middle of the list rather than the top, or every
    // task ever written outranks everything the user actually cares about.
    expect(task.priority, TaskPriority.normal);
    expect(task.isOverdueOn(DateTime.now()), isFalse);
    expect(task.daysUntilDue(DateTime.now()), isNull);
  });

  test('a task links to a client and a project, or to either alone', () async {
    final clientId = await store.addClient(
        const Client(name: 'Acme', amount: 1000, created: '2026-01-01'));
    final projectId = await store.addProject(const Project(
      name: 'Acme rebrand',
      clientId: null,
      created: '2026-01-01',
      updated: '2026-01-01',
    ));

    await store.addTask(const Task(title: 'Both', clientId: null, projectId: null));
    await store.addTask(Task(title: 'Theirs', clientId: clientId));
    await store.addTask(Task(title: 'Ours', projectId: projectId));

    expect((await store.tasks(clientId: clientId)).single.title, 'Theirs');
    expect((await store.tasks(projectId: projectId)).single.title, 'Ours');
    expect(await store.tasks(clientId: clientId, projectId: projectId), isEmpty);
  });

  test('finishing a task stamps when, and un-finishing clears it', () async {
    final id = await store.addTask(const Task(title: 'Send the quote'));
    expect((await store.tasks()).single.completedAt, isNull);

    await store.setTaskDone(id, true);
    var task = (await store.tasks()).single;
    expect(task.done, isTrue);
    // The moment is what makes the archive readable rather than a list of rows
    // that vanished.
    expect(task.completedAt, isNotNull);
    expect(DateTime.tryParse(task.completedAt!), isNotNull);

    await store.setTaskDone(id, false);
    task = (await store.tasks()).single;
    expect(task.done, isFalse);
    // A timestamp from when it was first finished, on a row that is open again,
    // is a claim about a day that has not happened.
    expect(task.completedAt, isNull);
  });

  test('open and finished are one list, split by a flag', () async {
    await store.addTask(const Task(title: 'Waiting'));
    final done = await store.addTask(const Task(title: 'Finished'));
    await store.setTaskDone(done, true);

    expect((await store.tasks()).map((t) => t.title), ['Waiting', 'Finished']);
    expect((await store.tasks(openOnly: true)).single.title, 'Waiting');
  });

  test('priority is stored by name and read back, including a bad value', () async {
    for (final p in TaskPriority.values) {
      final id = await store.addTask(Task(title: p.name, priority: p));
      final task = (await store.task(id))!;
      expect(task.priority, p);
      expect(task.priority.rank, p.rank);
    }
    // A value this build does not recognise must not stop a list opening. The
    // column can hold one from a restored backup or a newer build, and a task
    // list that will not open is a far worse outcome than that row sorting in
    // the middle.
    expect(TaskPriority.parse('nonsense'), TaskPriority.normal);
    expect(TaskPriority.parse(null), TaskPriority.normal);
  });

  test('an overdue task says so, and a finished one never does', () async {
    final id = await store.addTask(Task(title: 'Late', due: inDays(-3)));
    var task = (await store.task(id))!;
    expect(task.isOverdueOn(DateTime.now()), isTrue);
    expect(task.daysUntilDue(DateTime.now()), -3);

    await store.setTaskDone(id, true);
    task = (await store.task(id))!;
    // Being late about something already finished is noise, and it is what an
    // archive would shout about forever if it were not stopped here.
    expect(task.isOverdueOn(DateTime.now()), isFalse);
  });

  test('everything survives a restart', () async {
    final (first, dir) = await openTestStoreWithDirectory();
    await first.addTask(Task(
      title: 'Call the accountant',
      priority: TaskPriority.high,
      due: _isoOf(DateTime.now().add(const Duration(days: 2))),
      created: DateTime.now().toIso8601String(),
    ));
    await first.close();

    final again = await ProfileStore.open(directory: dir);
    addTearDown(again.close);

    final task = (await again.tasks()).single;
    expect(task.title, 'Call the accountant');
    expect(task.priority, TaskPriority.high);
    expect(task.due, isNotNull);
    expect(task.done, isFalse);
  });

  test('deleting removes it and nothing else', () async {
    final keep = await store.addTask(const Task(title: 'Keep'));
    final drop = await store.addTask(const Task(title: 'Drop'));

    await store.deleteTask(drop);
    expect((await store.tasks()).single.id, keep);
  });
}

/// The same day in the form the store speaks.
String _isoOf(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}