/// A task: one piece of work somebody wrote down to get done.
///
/// Kept in its own file because it is the only model in this app with a priority
/// and a completion moment, and because `models.dart` had grown long enough that
/// adding to it meant reading it. `models.dart` exports this, so nothing outside
/// has to know it is here separately.
library;

/// How pressing a piece of work is.
///
/// Ordered most urgent first and stored by name rather than by number, for the
/// same reason [EventRecurrence] is: a kind added later cannot silently
/// renumber what is already on disk.
///
/// [normal] is the default, and deliberately not [high]. A task arrives either
/// from the chat or from a person in a hurry, neither of whom has read the
/// ranking rules, and defaulting to the top of the list would put every task
/// ever created above every task they later decided mattered most. A priority
/// that is always high is not a priority.
enum TaskPriority {
  high,
  normal,
  low;

  /// Higher is more pressing. This is what the queue sorts on; the colour on a
  /// row is decoration over it, never a second opinion.
  int get rank => switch (this) {
        TaskPriority.high => 2,
        TaskPriority.normal => 1,
        TaskPriority.low => 0,
      };

  /// The word shown where a row or a form says what this is.
  String get label => switch (this) {
        TaskPriority.high => 'High',
        TaskPriority.normal => 'Normal',
        TaskPriority.low => 'Low',
      };

  /// Reads a stored value, treating anything unrecognised as [normal].
  ///
  /// Parsed rather than indexed because the column came from a restored backup
  /// or a build that knew a kind this one does not, and a list that will not
  /// open because one row holds a word we do not recognise is a worse outcome
  /// than that row sorting in the middle.
  static TaskPriority parse(Object? raw) => switch (raw) {
        'high' => TaskPriority.high,
        'low' => TaskPriority.low,
        _ => TaskPriority.normal,
      };
}

/// A piece of work the user ticks off.
///
/// Deliberately its own table rather than a fourth kind of deadline. A deadline
/// is dated and nothing else — "hand the site over by Friday" — and a task is
/// something you do: it can carry a date or not, it can be attached to a client,
/// a project, both or neither, it can be given a priority, and it is finished
/// rather than merely reached. Folding it into the deadlines table would mean
/// every one of those columns nullable on rows that never use them, and the one
/// place this app has to answer "what should I do next" would have to ask which
/// of two shapes a row is before it could sort anything.
///
/// Both links are nullable on purpose. One-off work with just a deadline is
/// most of the list in the first week of using this, and there is nowhere else
/// for it to live.
class Task {
  final int? id;
  final String title;

  /// Who it is for, when somebody is. The same link [Deadline] has, so a chase
  /// and a chore read the same way on a client's page.
  final int? clientId;

  /// Which project it belongs to, when it belongs to one. Separate from
  /// [clientId] rather than derived through the project, because a project can
  /// be for the user's own business and a task can still be somebody's chase.
  final int? projectId;

  /// ISO date, nullable. A task with no date is still a task; the date is only
  /// what lets it come up in the queue as late.
  final String? due;

  final TaskPriority priority;

  /// Finished, rather than deleted. [completedAt] says when, which is what makes
  /// the archived list readable — "done Tuesday" is evidence, and a list of
  /// tasks that simply vanished is not.
  final bool done;
  final String? completedAt;

  /// Anything the user wanted to write down about it.
  final String? note;

  final String created;

  const Task({
    this.id,
    required this.title,
    this.clientId,
    this.projectId,
    this.due,
    this.priority = TaskPriority.normal,
    this.done = false,
    this.completedAt,
    this.note,
    this.created = '',
  });

  DateTime? get parsedDue => due == null ? null : DateTime.tryParse(due!);

  /// Unfinished and past its date. Takes [today] rather than reading the clock,
  /// for the reason everything else in this file does: the answer has to be
  /// checkable at a known date.
  bool isOverdueOn(DateTime today) {
    if (done) return false;
    final d = parsedDue;
    if (d == null) return false;
    return DateTime(d.year, d.month, d.day)
        .isBefore(DateTime(today.year, today.month, today.day));
  }

  /// Days until due. Negative when late, null when there is no date.
  int? daysUntilDue(DateTime today) {
    final d = parsedDue;
    if (d == null) return null;
    return DateTime(d.year, d.month, d.day)
        .difference(DateTime(today.year, today.month, today.day))
        .inDays;
  }

  Task copyWith({
    int? id,
    String? title,
    int? clientId,
    int? projectId,
    String? due,
    TaskPriority? priority,
    bool? done,
    String? completedAt,
    String? note,
    bool clearDue = false,
    bool clearProject = false,
    bool clearClient = false,
    bool clearNote = false,
    bool clearCompleted = false,
  }) =>
      Task(
        id: id ?? this.id,
        title: title ?? this.title,
        clientId: clearClient ? null : (clientId ?? this.clientId),
        projectId: clearProject ? null : (projectId ?? this.projectId),
        due: clearDue ? null : (due ?? this.due),
        priority: priority ?? this.priority,
        done: done ?? this.done,
        completedAt:
            clearCompleted ? null : (completedAt ?? this.completedAt),
        note: clearNote ? null : (note ?? this.note),
        created: created,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'title': title,
        'client_id': clientId,
        'project_id': projectId,
        'due': due,
        'priority': priority.name,
        'done': done ? 1 : 0,
        'completed_at': completedAt,
        'note': note,
        'created': created,
      };

  /// Row for an UPDATE.
  ///
  /// Writes nulls, for the reason [Client.toUpdateMap] does: clearing a date or
  /// an attachment has to actually clear it.
  Map<String, Object?> toUpdateMap() => {
        'title': title,
        'client_id': clientId,
        'project_id': projectId,
        'due': due,
        'priority': priority.name,
        'done': done ? 1 : 0,
        'completed_at': completedAt,
        'note': note,
      };

  factory Task.fromMap(Map<String, Object?> m) => Task(
        id: m['id'] as int?,
        title: m['title'] as String? ?? '',
        clientId: m['client_id'] as int?,
        projectId: m['project_id'] as int?,
        due: m['due'] as String?,
        priority: TaskPriority.parse(m['priority']),
        done: (m['done'] as int? ?? 0) == 1,
        completedAt: m['completed_at'] as String?,
        note: m['note'] as String?,
        created: m['created'] as String? ?? '',
      );
}
