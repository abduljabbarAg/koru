import 'attention.dart';
import 'human_date.dart';
import 'models.dart';

/// What kind of thing a queue row is about.
///
/// Decides what tapping the row opens and what the badge on it says. Named
/// rather than inferred from the title, because a row whose title happens to
/// read like another kind is how a screen ends up taking you somewhere that does
/// not match what you pressed.
enum WorkKind { task, deadline, event, money, project }

/// One line of the morning's queue: a thing to do, and enough about it to
/// decide whether to do it now.
///
/// Plain data, no widgets and no providers, for the reason everything in
/// `attention.dart` is plain data: the queue is shown on a screen, counted in a
/// header and asserted on in a test, and three shapes for the same idea is how
/// they come to disagree.
class WorkItem {
  final WorkKind kind;

  /// The row's own id, so tapping it opens the thing rather than a search for it.
  final int? id;

  /// What has to happen, in the user's words.
  final String title;

  /// Whose it is, when it is somebody's. Carried as an id for the reason
  /// `AttentionItem` does: there is no reliable way back from a title to a
  /// client, and the row needs their number as well as their name.
  final int? clientId;

  /// Which project, when the task belongs to one.
  final int? projectId;

  /// How pressing it is, when the user said. Null for everything that is not a
  /// task, which sorts as [TaskPriority.normal] rather than as urgent: a
  /// deadline nobody prioritised is not a low-priority deadline.
  final TaskPriority? priority;

  /// Days from [WorkQueue.build]'s today. Null when there is no date, which is
  /// not the same as a date far away: this one cannot be late.
  final int? daysOut;

  /// Past its date. Carried rather than worked out at the point of comparison so
  /// that the screen and the ranking can never read the clock differently.
  final bool overdue;

  /// Money attached to this row, when there is any. A chase for 400 reads as a
  /// bigger job than a chore, and the number is the reason it is on the list at
  /// all.
  final double? money;

  /// One more line under the title: how far off it is, or what kind of thing it
  /// is when there is no date to describe.
  final String detail;

  const WorkItem({
    required this.kind,
    required this.title,
    this.id,
    this.clientId,
    this.projectId,
    this.priority,
    this.daysOut,
    this.overdue = false,
    this.money,
    this.detail = '',
  });

  /// Sorts as normal when nothing was said. See [TaskPriority] for why the
  /// middle is the right default.
  int get priorityRank => (priority ?? TaskPriority.normal).rank;
}

/// Builds and orders the day's work.
///
/// The one question this app is asked every morning is "what should I do right
/// now", and the records that answer it were already all here — money that is
/// late, deadlines that have arrived, places to be, tasks with a date on them —
/// but they were spread across five tabs and no screen put them in one order.
/// So nothing on this list is new data. This is the ranking, not another engine.
///
/// Pure and synchronous, with the date passed in, for the same reasons
/// `Attention` is: the answer has to be checkable at a known day rather than
/// only ever be correct at whichever moment the test happened to run.
class WorkQueue {
  const WorkQueue._();

  /// How far ahead a deadline or an amount due counts as "today's problem".
  ///
  /// Named here and taken from [Attention], because the notification and this
  /// queue are two renderings of the same records and two windows that drifted
  /// apart would put an item on one and not the other.
  static const soonWindow = Attention.soonWindow;

  /// How long without a note before a project is worth mentioning.
  static const stalledAfter = Attention.stalledAfter;

  static List<WorkItem> build({
    required List<Client> clients,
    required List<Deadline> deadlines,
    required List<Task> tasks,
    required Map<int, double> received,
    List<CalendarEvent> events = const [],
    List<Project> projects = const [],
    DateTime? today,
  }) {
    final now = today ?? DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    final out = <WorkItem>[];

    double balanceOf(Client c) =>
        c.id == null ? 0 : c.balanceWith(received[c.id!] ?? 0);

    // Money first, because it is the only thing on this list that is already
    // costing the user something while it sits there. Late above merely due:
    // "three days late" is a different conversation from "due Friday".
    for (final c in clients) {
      final owing = balanceOf(c);
      if (owing <= 0) continue;
      final days = c.daysUntilDue(now);
      if (days == null) continue;
      if (days > soonWindow.inDays) continue;
      final late = days < 0;
      out.add(WorkItem(
        kind: WorkKind.money,
        id: c.id,
        clientId: c.id,
        title: late ? '${c.name} owes you' : '${c.name} is owed',
        // The figure is in the row rather than left for the reader to go and
        // look up, because a chase nobody can size is a chase that does not
        // happen.
        money: owing,
        daysOut: days,
        overdue: late,
        detail: late
            ? overdueSince(c.parsedDue, now)
            : formatDate(c.due, now),
      ));
    }

    // Tasks. All of them, dated or not: a task the user wrote down and has not
    // finished is work they are carrying, and hiding the undated ones until
    // somebody gives them a date would mean the list only ever showed what the
    // app had nagged about.
    for (final t in tasks) {
      if (t.done) continue;
      final days = t.daysUntilDue(now);
      out.add(WorkItem(
        kind: WorkKind.task,
        id: t.id,
        clientId: t.clientId,
        projectId: t.projectId,
        title: t.title,
        priority: t.priority,
        daysOut: days,
        overdue: t.isOverdueOn(now),
        detail: switch (days) {
          null => 'No date on it',
          0 => 'Due today',
          _ => formatDate(t.due, now),
        },
      ));
    }

    for (final d in deadlines) {
      if (d.done) continue;
      final days = daysBetween(midnight, DateTime.tryParse(d.due) ?? midnight);
      if (days > soonWindow.inDays) continue;
      out.add(WorkItem(
        kind: WorkKind.deadline,
        id: d.id,
        clientId: d.clientId,
        title: d.title,
        daysOut: days,
        overdue: days < 0,
        detail: days < 0
            ? '${-days} day${days == -1 ? '' : 's'} overdue'
            : formatDate(d.due, now),
      ));
    }

    // Places to be. The next day only, and only while the hour has not passed:
    // telling somebody about a call at 3pm at four in the afternoon is how a
    // notification gets switched off for good.
    for (final e in events) {
      final starts = e.startsAt;
      if (starts == null) continue;
      final days = daysBetween(midnight, starts);
      if (days < 0 || days > 1) continue;
      if (days == 0 && _isPast(now, e)) continue;
      out.add(WorkItem(
        kind: WorkKind.event,
        id: e.id,
        clientId: e.clientId,
        title: e.title,
        daysOut: days,
        detail: [
          days == 0 ? 'Today' : 'Tomorrow',
          if (!e.allDay) e.timeLabel,
        ].join(' at '),
      ));
    }

    // Projects, and only the ones that have gone quiet. A project is not due
    // work; it appears here because nothing else in the app has said anything
    // about it in a fortnight.
    for (final p in projects) {
      if (p.status != 'active') continue;
      final touched = DateTime.tryParse(p.updated.isEmpty ? p.created : p.updated);
      if (touched == null) continue;
      final quiet = daysBetween(DateTime(touched.year, touched.month, touched.day), midnight);
      if (quiet < stalledAfter.inDays) continue;
      out.add(WorkItem(
        kind: WorkKind.project,
        id: p.id,
        clientId: p.clientId,
        title: p.name,
        priority: TaskPriority.low,
        daysOut: null,
        detail: 'No note for $quiet days',
      ));
    }

    // Sorted with each row's own position as the last word. Dart's sort is not
    // stable, so two rows that compare equal — two chores with no date on them,
    // say — can come back in either order, and a queue that reshuffles between
    // two builds of the same data cannot be scanned. Falling back to the order
    // they were gathered in keeps that from ever happening.
    final ranked = [
      for (var i = 0; i < out.length; i++) (at: i, item: out[i]),
    ]..sort((a, b) {
        final by = compare(a.item, b.item);
        return by == 0 ? a.at.compareTo(b.at) : by;
      });
    return [for (final r in ranked) r.item];
  }

  /// The order the queue is in, in the order the reasons matter.
  ///
  /// Written out rather than folded into one arithmetic score, because every
  /// attempt to compress this into a single number eventually weights the wrong
  /// part and nobody can tell which rule moved.
  static int compare(WorkItem a, WorkItem b) {
    // Money that is already late is the top of the list, above late work. Both
    // are "overdue", but one of them is somebody else owing the user money,
    // which is the only row on this screen where being a day late costs
    // something real.
    final money = _lateMoney(b).compareTo(_lateMoney(a));
    if (money != 0) return money;

    // Then late work of any kind, whatever its priority. A high-priority thing
    // with no date on it is a wish; a plain thing that was due yesterday is a
    // problem, and the date is the only evidence that distinguishes them.
    final late = (b.overdue ? 1 : 0).compareTo(a.overdue ? 1 : 0);
    if (late != 0) return late;

    // Then what the user said about it.
    final priority = b.priorityRank.compareTo(a.priorityRank);
    if (priority != 0) return priority;

    // Then the date, soonest first, which also puts the most overdue first
    // among rows that are all overdue.
    final due = _dueKey(a).compareTo(_dueKey(b));
    if (due != 0) return due;

    // Finally something stable. A list that reshuffles itself between two
    // rebuilds of the same data cannot be scanned, and the ids are the only
    // thing here that does not move when the clock does. [build] breaks a
    // remaining tie by the order the rows were gathered in, which is what covers
    // rows that have not been written anywhere yet and so have no id.
    final kind = a.kind.index.compareTo(b.kind.index);
    if (kind != 0) return kind;
    return (a.id ?? 0).compareTo(b.id ?? 0);
  }

  /// One line for the header, counting rather than listing.
  ///
  /// A greeting that names five things is a list the reader has to read twice;
  /// this says how late things are and gets out of the way.
  static String brief(List<WorkItem> items) {
    if (items.isEmpty) return '';
    final late = items.where((i) => i.overdue).length;
    final today = items.where((i) => i.daysOut == 0).length;
    final parts = <String>[
      if (late > 0) '$late late',
      if (today > 0) '$today due today',
    ];
    if (parts.isEmpty) return '${items.length} in the queue';
    return '${parts.join('  ·  ')}  ·  ${items.length} total';
  }

  /// Money that is already late. Only ever 0 or 1.
  static int _lateMoney(WorkItem i) =>
      i.kind == WorkKind.money && i.overdue ? 1 : 0;

  /// Undated rows sort below every dated one, whichever way the date points.
  ///
  /// A sentinel rather than null because null is not orderable and a row without
  /// a date has to be somewhere, not just absent from the comparison.
  static int _dueKey(WorkItem i) => i.daysOut ?? _undated;

  /// Anything further than this is "no date", which keeps it out of the way of
  /// real dates for as long as the app exists.
  static const int _undated = 1000000;

  /// Whether a timed entry has already happened today.
  static bool _isPast(DateTime now, CalendarEvent e) {
    final starts = e.startsAt;
    if (starts == null || e.allDay) return false;
    return starts.isBefore(now);
  }
}