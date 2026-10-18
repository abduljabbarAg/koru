import 'package:flutter_test/flutter_test.dart';
import 'package:koru/attention.dart';
import 'package:koru/models.dart';
import 'package:koru/work_queue.dart';

/// How the morning's queue is ordered.
///
/// This is the answer to "what should I do now", and it is the one thing on the
/// app's front door. It is pure and takes the date, so every rule below can be
/// checked at a known day rather than only ever being correct at whichever
/// moment the test happened to run.
void main() {
  /// A fixed day, so nothing here depends on the date the suite runs.
  final today = DateTime(2026, 10, 17);

  String day(int offset) {
    final d = DateTime(2026, 10, 17 + offset);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  Task task(String title,
          {int? dueIn, TaskPriority priority = TaskPriority.normal}) =>
      Task(
        title: title,
        due: dueIn == null ? null : day(dueIn),
        priority: priority,
        created: '2026-10-01',
      );

  List<WorkItem> queue({
    List<Client> clients = const [],
    List<Task> tasks = const [],
    List<Deadline> deadlines = const [],
    Map<int, double> received = const {},
    List<CalendarEvent> events = const [],
    List<Project> projects = const [],
  }) =>
      WorkQueue.build(
        clients: clients,
        deadlines: deadlines,
        tasks: tasks,
        received: received,
        events: events,
        projects: projects,
        today: today,
      );

  group('a task list', () {
    test('is ranked late first, then by priority, then by date', () {
      final items = queue(tasks: [
        task('no date', priority: TaskPriority.high),
        task('later', dueIn: 9),
        task('sooner', dueIn: 1),
        task('normal, far off', dueIn: 20),
        task('overdue', dueIn: -2, priority: TaskPriority.low),
      ]);

      expect(
        items.map((i) => i.title),
        [
          // Late beats everything, whatever the priority: a high-priority thing
          // with no date is a wish, a low-priority thing that was due two days
          // ago is a problem.
          'overdue',
          // Then the high-priority undated one, because the user said so.
          'no date',
          // Then the dated ones, soonest first.
          'sooner',
          'later',
          'normal, far off',
        ],
      );
    });

    test('is stable, so the same data always reads the same way', () {
      // Eight rows that compare entirely equal: no date, the middle priority,
      // nothing said about any of them. Dart's sort is not stable, so without a
      // deliberate last word these come back in whatever order the algorithm
      // happened to leave them in.
      final many = [for (var i = 0; i < 8; i++) task('task $i')];
      final first = queue(tasks: many).map((i) => i.title).toList();

      // The same records, read twice. A queue that reshuffles between two
      // rebuilds of the same data cannot be scanned.
      final second = queue(tasks: many).map((i) => i.title).toList();

      expect(second, first);
      expect(first.toSet(), hasLength(8));
    });

    test('rows that compare equal keep the order they were recorded in', () {
      final many = [for (var i = 0; i < 8; i++) task('task $i')];
      // Dart's sort is not stable, so without a deliberate last word these eight
      // identical rows can come back in whatever order the algorithm left them
      // in — and the reader sees a list that moves about between two frames.
      expect(queue(tasks: many).first.title, 'task 0');
      expect(
        queue(tasks: many.reversed.toList()).first.title,
        'task 7',
        reason: 'nothing else distinguishes them, so the order they were written '
            'in is the answer',
      );
    });

    test('a finished task is not in the queue at all', () {
      expect(
        queue(tasks: [
          const Task(id: 1, title: 'finished', done: true),
          const Task(id: 2, title: 'open'),
        ]),
        hasLength(1),
        reason: 'a finished task is history, not work',
      );
      expect(
        queue(tasks: [
          const Task(id: 1, title: 'finished', done: true),
          const Task(id: 2, title: 'open'),
        ]).single.title,
        'open',
      );
    });
  });

  group('the things the user named as reminders', () {
    test('money that is late is the top of the list', () {
      final items = queue(
        clients: [
          Client(
            id: 1,
            name: 'Acme',
            status: 'delivered',
            amount: 2000,
            due: day(-5),
            created: '2026-01-01',
          ),
        ],
        received: const {1: 0},
        tasks: [task('urgent', dueIn: -3, priority: TaskPriority.high)],
      );

      expect(items.first.kind, WorkKind.money);
      expect(items.first.title, 'Acme owes you');
      // The figure travels with the row. A chase somebody has to go and look the
      // number up for is a chase that does not get sent.
      expect(items.first.money, 2000);
      expect(items.first.overdue, isTrue);
      expect(items.last.title, 'urgent');
    });

    test('a one-off date, which used to have nowhere to live', () {
      // Nothing here belongs to anybody: no client, no project. This is the case
      // the whole table exists for.
      final items = queue(tasks: [task('renew the domain', dueIn: 2)]);
      expect(items.single.title, 'renew the domain');
      expect(items.single.clientId, isNull);
      expect(items.single.projectId, isNull);
      expect(items.single.detail, 'in 2 days');
    });

    test('a date somebody agreed to by', () {
      final items = queue(
        deadlines: const [Deadline(id: 1, title: 'Send invoice', due: '2026-10-16')],
      );
      expect(items.single.kind, WorkKind.deadline);
      expect(items.single.title, 'Send invoice');
      expect(items.single.detail, '1 day overdue');
      expect(items.single.overdue, isTrue);
    });

    test('a payment to follow up on, once it is due', () {
      final items = queue(
        clients: [
          Client(
            id: 1,
            name: 'Retainer Co',
            status: 'active',
            amount: 900,
            monthly: 900,
            due: day(2),
            created: '2026-01-01',
          ),
        ],
        received: const {1: 0},
      );
      expect(items.single.kind, WorkKind.money);
      expect(items.single.overdue, isFalse);
      expect(items.single.detail, 'in 2 days');
    });

    test('a place to be, today and tomorrow only', () {
      final items = queue(events: [
        CalendarEvent(id: 1, date: day(0), time: '15:00', title: 'Call Bilal'),
        CalendarEvent(id: 2, date: day(1), time: '10:00', title: 'Site visit'),
        // A week out is planning, not something to be interrupted about.
        CalendarEvent(id: 3, date: day(7), time: '10:00', title: 'Kickoff'),
      ]);
      expect(items.map((i) => i.title), ['Call Bilal', 'Site visit']);
      expect(items.first.detail, 'Today at 3:00 pm');
    });

    test('a monthly retainer that has not landed', () {
      // A retainer with no invoice behind it has no due date of its own, so the
      // only honest thing is to leave it off and let the client's own terms
      // decide. A row invented from a monthly figure would be a date nobody
      // agreed to.
      final items = queue(
        clients: [
          const Client(id: 1, name: 'Quiet Co', status: 'active', monthly: 900, created: '2026-01-01'),
        ],
      );
      expect(items, isEmpty);
      expect(Attention.soonWindow.inDays, greaterThan(0));
    });

    test('a project that has gone quiet, under everything dated', () {
      final items = queue(
        projects: [
          const Project(
            id: 1,
            name: 'the shop',
            created: '2026-01-01',
            updated: '2026-09-01T00:00:00Z',
          ),
        ],
        tasks: [task('undated chore')],
      );
      expect(items.first.title, 'undated chore');
      expect(items.last.title, 'the shop');
      expect(items.last.kind, WorkKind.project);
    });
  });

  test('the header counts rather than lists', () {
    final items = queue(
      clients: [
        Client(id: 1, name: 'Acme', amount: 100, due: day(-1), created: '2026-01-01'),
      ],
      tasks: [task('later', dueIn: 5), task('undated')],
    );
    final brief = WorkQueue.brief(items);
    expect(brief, contains('1 late'));
    expect(brief, contains('3 total'));
    expect(WorkQueue.brief([]), isEmpty);
  });
}