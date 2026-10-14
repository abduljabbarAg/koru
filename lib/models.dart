/// Domain models, kept out of the storage layer so the assistant and the UI can
/// reason about them without importing sqflite.

import 'local/write_intent.dart';
///
/// Fitness is gone: the table survives for older installs, but nothing reads or
/// writes it, and a freelancer tool that also tracks body measurements was two
/// products in one.
library;

const kClientStatuses = ['lead', 'active', 'delivered', 'paid', 'lost'];

/// A client or job. [due] is an ISO date, nullable.
class Client {
  final int? id;
  final String name;
  final String status;
  final double? amount;
  final String? due;
  final String? leadSource;
  final String? note;
  final String created;

  /// Paid up front, before any work was delivered.
  ///
  /// Stored for the record and shown as "agreed X, deposit paid Y, so Z owed",
  /// but deliberately not subtracted in [balanceWith]. A deposit is a payment,
  /// so it is written into the ledger as a payment row, and money is computed
  /// from the ledger everywhere. Keeping a second copy that only affects this
  /// one screen is how a balance starts disagreeing with the ledger.
  final double? deposit;

  /// Days allowed to pay, counted from [invoicedOn]. Null means no terms were
  /// agreed, which is different from zero days, which means due immediately.
  final int? termsDays;

  /// When the work was invoiced. The anchor the terms count from.
  final String? invoicedOn;

  /// Money that arrives every month by standing agreement, rather than against
  /// a fresh invoice. Null means this is not a retainer.
  ///
  /// Deliberately separate from [amount]. A retainer has no invoice to be
  /// behind on, so folding it into the balance would invent money owed that
  /// nobody has invoiced, and a retainer paid early would look like a negative
  /// balance owed back.
  final double? monthly;

  const Client({
    this.id,
    required this.name,
    this.status = 'lead',
    this.amount,
    this.due,
    this.leadSource,
    this.note,
    this.created = '',
    this.monthly,
    this.deposit,
    this.termsDays,
    this.invoicedOn,
  });

  bool get isRetainer => monthly != null && monthly! > 0;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'status': status,
        if (amount != null) 'amount': amount,
        if (due != null) 'due': due,
        if (leadSource != null) 'lead_source': leadSource,
        if (note != null) 'note': note,
        'created': created,
        if (monthly != null) 'monthly': monthly,
        if (deposit != null) 'deposit': deposit,
        if (termsDays != null) 'terms_days': termsDays,
        if (invoicedOn != null) 'invoiced_on': invoicedOn,
      };

  /// Row for an UPDATE.
  ///
  /// Unlike [toMap] this writes nulls. An insert can afford to omit a column,
  /// but an update that omits one leaves the previous value in place, so
  /// clearing a due date or a note silently did nothing.
  Map<String, Object?> toUpdateMap() => {
        'name': name,
        'status': status,
        'amount': amount,
        'due': due,
        'lead_source': leadSource,
        'note': note,
        'created': created,
        'monthly': monthly,
        'deposit': deposit,
        'terms_days': termsDays,
        'invoiced_on': invoicedOn,
      };

  factory Client.fromMap(Map<String, Object?> m) => Client(
        id: m['id'] as int?,
        name: m['name'] as String? ?? '',
        status: m['status'] as String? ?? 'lead',
        amount: (m['amount'] as num?)?.toDouble(),
        due: m['due'] as String?,
        leadSource: m['lead_source'] as String?,
        note: m['note'] as String?,
        created: m['created'] as String? ?? '',
        monthly: (m['monthly'] as num?)?.toDouble(),
        deposit: (m['deposit'] as num?)?.toDouble(),
        termsDays: (m['terms_days'] as int?),
        invoicedOn: m['invoiced_on'] as String?,
      );

  Client copyWith({
    int? id,
    String? name,
    String? status,
    double? amount,
    String? due,
    String? leadSource,
    String? note,
    String? created,
    double? monthly,
    bool clearDue = false,
    bool clearNote = false,
    bool clearAmount = false,
    bool clearSource = false,
    bool clearMonthly = false,
    double? deposit,
    int? termsDays,
    String? invoicedOn,
    bool clearTerms = false,
  }) =>
      Client(
        id: id ?? this.id,
        name: name ?? this.name,
        status: status ?? this.status,
        amount: clearAmount ? null : (amount ?? this.amount),
        due: clearDue ? null : (due ?? this.due),
        leadSource: clearSource ? null : (leadSource ?? this.leadSource),
        note: clearNote ? null : (note ?? this.note),
        created: created ?? this.created,
        monthly: clearMonthly ? null : (monthly ?? this.monthly),
        deposit: deposit ?? this.deposit,
        termsDays: clearTerms ? null : (termsDays ?? this.termsDays),
        invoicedOn: invoicedOn ?? this.invoicedOn,
      );

  DateTime? get parsedDue => due == null ? null : DateTime.tryParse(due!);

  /// When the money is actually due.
  ///
  /// An explicit date always wins, because it is the only thing the user can be
  /// certain about. Failing that it is the invoice date plus the agreed terms,
  /// which is what makes "net 14" mean something: previously the due date had to
  /// be typed by hand, nobody typed it, and nothing was ever overdue.
  DateTime? get dueDate {
    final explicit = parsedDue;
    if (explicit != null) return explicit;
    final invoiced = invoicedOn == null ? null : DateTime.tryParse(invoicedOn!);
    final terms = termsDays;
    if (invoiced == null || terms == null) return null;
    return DateTime(invoiced.year, invoiced.month, invoiced.day + terms);
  }

  /// Terms in words, for the screen and for telling the model.
  String get termsLabel {
    final terms = termsDays;
    if (terms == null) return 'no terms agreed';
    if (terms == 0) return 'due on completion';
    return 'net $terms days';
  }

  /// Outstanding balance once [received] has come off the invoiced amount.
  ///
  /// Floored at zero, because being paid more than invoiced means nothing is
  /// owed and a negative figure reads as money owed to the freelancer. Also zero
  /// when there is no amount on file, since there is nothing to be behind on.
  ///
  /// This is the only place the rule is written. The store has a version that
  /// queries the ledger and passes the total here, and the screen has one that
  /// passes a total it already has, because a balance computed two ways is a
  /// balance that will eventually disagree with itself.
  double balanceWith(double received) {
    final invoiced = amount ?? 0;
    if (invoiced <= 0) return 0;
    final balance = invoiced - received;
    return balance < 0 ? 0 : balance;
  }

  /// Unpaid work that is past its date. Takes [today] rather than reading the
  /// clock so the answer is testable and the UI stays the only place that knows
  /// what time it is.
  /// Uses [dueDate] rather than the raw column, so a client whose terms imply a
  /// date goes overdue on that date without anyone having typed a due date in.
  bool isOverdueOn(DateTime today) {
    if (status == 'paid' || status == 'lost') return false;
    final d = dueDate;
    if (d == null) return false;
    final midnight = DateTime(today.year, today.month, today.day);
    return d.isBefore(midnight);
  }

  /// Days until due. Negative when already late, null when no date is known.
  ///
  /// Asked more often than "is it late", because what someone wants to know is
  /// usually "how many days have I got" rather than a yes or no.
  int? daysUntilDue(DateTime today) {
    final d = dueDate;
    if (d == null) return null;
    final midnight = DateTime(today.year, today.month, today.day);
    return DateTime(d.year, d.month, d.day).difference(midnight).inDays;
  }
}

/// Money actually received against a client.
///
/// The business table has one `amount` and a binary status, which cannot
/// express "they paid 500 of 2000 today". Freelancers get paid in parts and
/// asking for the balance is the question the whole app is meant to answer, so
/// what has been received is a ledger rather than a flag.
class Payment {
  final int? id;
  final int clientId;
  final double amount;
  final String date;
  final String? note;

  const Payment({
    this.id,
    required this.clientId,
    required this.amount,
    required this.date,
    this.note,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'client_id': clientId,
        'amount': amount,
        'date': date,
        if (note != null) 'note': note,
      };

  factory Payment.fromMap(Map<String, Object?> m) => Payment(
        id: m['id'] as int?,
        clientId: m['client_id'] as int,
        amount: (m['amount'] as num).toDouble(),
        date: m['date'] as String? ?? '',
        note: m['note'] as String?,
      );
}

/// A calendar entry: something with a place in time, as opposed to a deadline,
/// which only has to be finished by a date.
///
/// The distinction is real and worth its own table. A deadline is "hand the
/// site over by Friday" and can be done at any hour before it; a calendar entry
/// is "call with Bilal at 3pm" and happens at 3pm or it does not happen. Times
/// would have been squeezed into the deadlines table as a second meaning of the
/// same column, and "what is on my calendar today" cannot be answered from a
/// list of due dates.
class CalendarEvent {
  final int? id;

  /// ISO date, required. A calendar entry with no date is a task.
  final String date;

  /// "HH:mm", or null for an all-day entry.
  final String? time;

  final String title;
  final String? location;
  final String? note;

  /// Optionally attached, the same way deadlines are.
  final int? clientId;

  /// Duration in minutes, null means the default.
  final int? durationMin;

  /// True once this entry has been handed to the phone's calendar, so a second
  /// sync cannot create a duplicate. The in-app copy is always the truth; this
  /// only says whether the phone's copy exists.
  final bool synced;

  final String created;

  const CalendarEvent({
    this.id,
    required this.date,
    this.time,
    required this.title,
    this.location,
    this.note,
    this.clientId,
    this.durationMin,
    this.recurrence,
    this.synced = false,
    this.created = '',
  });

  /// How this repeats, by name. Stored as the enum's name rather than as an
  /// int, so adding a kind later cannot silently renumber the existing ones.
  final EventRecurrence? recurrence;

  bool get allDay => time == null || time!.isEmpty;

  /// The next occurrence after [from], or this event's own date when it does
  /// not repeat.
  ///
  /// Recurrence is stored as one row, not expanded into copies. Copies drift
  /// from each other the moment one is edited, and a meeting that moved stays
  /// moved. The price is that the calendar has to be asked for occurrences
  /// rather than holding them, which is what [occurrences] is for.
  List<CalendarEvent> occurrences(DateTime from, DateTime to, {int cap = 60}) {
    final r = recurrence;
    if (r == null) {
      final d = DateTime.tryParse(date);
      if (d == null) return const [];
      final day = DateTime(d.year, d.month, d.day);
      return day.isBefore(DateTime(from.year, from.month, from.day)) ||
              day.isAfter(DateTime(to.year, to.month, to.day))
          ? const []
          : [this];
    }
    final out = <CalendarEvent>[];
    var cursor = DateTime.tryParse(date);
    if (cursor == null) return const [];
    // Guarded on both ends: a recurrence created in the past still has to be
    // walked forward, and the cap stops a daily meeting filling the list to the
    // end of time.
    var guard = 0;
    while (cursor.isBefore(to) && guard < cap * 40) {
      if (!cursor.isBefore(DateTime(from.year, from.month, from.day))) {
        out.add(copyWith(date: _iso(cursor)));
        if (out.length >= cap) break;
      }
      final nextDate = r.next(cursor);
      if (nextDate == null) break;
      cursor = nextDate;
      guard++;
    }
    return out;
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'date': date,
        if (time != null) 'time': time,
        'title': title,
        if (location != null) 'location': location,
        if (note != null) 'note': note,
        if (clientId != null) 'client_id': clientId,
        if (durationMin != null) 'duration_min': durationMin,
        if (recurrence != null) 'recurrence': recurrence!.name,
        'synced': synced ? 1 : 0,
        'created': created,
      };

  Map<String, Object?> toUpdateMap() => {
        'date': date,
        'time': time,
        'title': title,
        'location': location,
        'note': note,
        'client_id': clientId,
        'duration_min': durationMin,
        'recurrence': recurrence?.name,
        'synced': synced ? 1 : 0,
        'created': created,
      };

  factory CalendarEvent.fromMap(Map<String, Object?> m) => CalendarEvent(
        id: m['id'] as int?,
        date: m['date'] as String? ?? '',
        time: m['time'] as String?,
        title: m['title'] as String? ?? '',
        location: m['location'] as String?,
        note: m['note'] as String?,
        clientId: m['client_id'] as int?,
        durationMin: m['duration_min'] as int?,
        recurrence: m['recurrence'] == null
            ? null
            : EventRecurrence.values
                .where((r) => r.name == m['recurrence'])
                .firstOrNull,
        synced: (m['synced'] as int? ?? 0) == 1,
        created: m['created'] as String? ?? '',
      );

  /// Start moment, for sorting and for handing to the phone calendar.
  ///
  /// All-day entries sort before timed ones on the same day, because "sometime
  /// today" should not come above "9am".
  DateTime? get startsAt {
    final d = DateTime.tryParse(date);
    if (d == null) return null;
    final t = time;
    if (t == null || t.isEmpty) return DateTime(d.year, d.month, d.day);
    final parts = t.split(':');
    final hour = int.tryParse(parts.isNotEmpty ? parts.first : '') ?? 0;
    final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    return DateTime(d.year, d.month, d.day, hour, minute);
  }

  /// Human label: "3:00 pm" or "All day".
  ///
  /// Minutes are always shown. "3 pm" is a rounding, and a calendar is the one
  /// place where a rounded number reads as a wrong one.
  String get timeLabel {
    final t = time;
    if (t == null || t.isEmpty) return 'All day';
    final parts = t.split(':');
    var hour = int.tryParse(parts.isNotEmpty ? parts.first : '');
    if (hour == null) return t;
    final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    final meridiem = hour >= 12 ? 'pm' : 'am';
    final twelve = hour % 12 == 0 ? 12 : hour % 12;
    return '$twelve:${minute.toString().padLeft(2, '0')} $meridiem';
  }
}

/// A dated thing that has to happen, optionally attached to a client.
class Deadline {
  final int? id;
  final int? clientId;
  final String title;
  final String due;
  final bool done;

  const Deadline({
    this.id,
    this.clientId,
    required this.title,
    required this.due,
    this.done = false,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        if (clientId != null) 'client_id': clientId,
        'title': title,
        'due': due,
        'done': done ? 1 : 0,
      };

  factory Deadline.fromMap(Map<String, Object?> m) => Deadline(
        id: m['id'] as int?,
        clientId: m['client_id'] as int?,
        title: m['title'] as String? ?? '',
        due: m['due'] as String? ?? '',
        done: (m['done'] as int? ?? 0) == 1,
      );

  bool isOverdueOn(DateTime today) {
    if (done) return false;
    final d = DateTime.tryParse(due);
    if (d == null) return false;
    return d.isBefore(DateTime(today.year, today.month, today.day));
  }
}

/// Who a project is for, which is the distinction that matters here.
///
/// Not a filter or a category. A project for a client is work somebody is
/// paying for; a personal project is work for yourself or your own business.
/// They behave differently enough that sharing a table without this column
/// meant every money question had to ask "is this billable?" first, and the
/// answer was sometimes wrong.
enum ProjectKind {
  client,
  personal;

  static ProjectKind parse(String? v) =>
      v == 'personal' ? ProjectKind.personal : ProjectKind.client;
}

/// A piece of work, tracked to completion.
///
/// Deliberately not money. A personal project has no invoice, no balance and no
/// due date, so it has no amount column either. The temptation was to reuse
/// Client, which already has name, note and a status, and that is what made
/// "how far along is my own side project" awkward to answer: the only place to
/// put it was a client record with an amount of zero, which then showed up in
/// every balance, every prompt and every chase-the-money question.
class Project {
  final int? id;
  final String name;
  final ProjectKind kind;

  /// The client this is for, when it is billable work. Always null for a
  /// personal project, and [ProjectKind.personal] ignores it if set.
  final int? clientId;

  /// What "finished" looks like, in the user's own words.
  final String? target;

  /// How they intend to get there.
  final String? plan;

  /// How far along this is, 0 to 1.
  ///
  /// Read by the app, written by the model from the notes, and overridable by
  /// the user at any time. The user has the final word: a number the model
  /// cannot argue with is worse than no number, because it will be confidently
  /// wrong and there is no way to say so except by overwriting it.
  final double progress;

  /// Why progress is where it is, which is what makes the number trustworthy
  /// and what the character says when you open the project.
  final String? progressNote;

  final String status;
  final String created;
  final String updated;

  const Project({
    this.id,
    required this.name,
    this.kind = ProjectKind.client,
    this.clientId,
    this.target,
    this.plan,
    this.progress = 0,
    this.progressNote,
    this.status = 'active',
    this.created = '',
    this.updated = '',
  });

  bool get isPersonal => kind == ProjectKind.personal;

  Project copyWith({
    int? id,
    String? name,
    ProjectKind? kind,
    int? clientId,
    String? target,
    String? plan,
    double? progress,
    String? progressNote,
    String? status,
    String? created,
    String? updated,
  }) =>
      Project(
        id: id ?? this.id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        clientId: clientId ?? this.clientId,
        target: target ?? this.target,
        plan: plan ?? this.plan,
        progress: progress ?? this.progress,
        progressNote: progressNote ?? this.progressNote,
        status: status ?? this.status,
        created: created ?? this.created,
        updated: updated ?? this.updated,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'kind': kind.name,
        'client_id': clientId,
        'target': target,
        'plan': plan,
        'progress': progress,
        'progress_note': progressNote,
        'status': status,
        'created': created,
        'updated': updated,
      };

  Map<String, Object?> toUpdateMap() => {
        'name': name,
        'kind': kind.name,
        'client_id': clientId,
        'target': target,
        'plan': plan,
        'progress': progress,
        'progress_note': progressNote,
        'status': status,
        'updated': updated,
      };

  factory Project.fromMap(Map<String, Object?> m) => Project(
        id: m['id'] as int?,
        name: m['name'] as String? ?? '',
        kind: ProjectKind.parse(m['kind'] as String?),
        clientId: m['client_id'] as int?,
        target: m['target'] as String?,
        plan: m['plan'] as String?,
        progress: (m['progress'] as num?)?.toDouble() ?? 0,
        progressNote: m['progress_note'] as String?,
        status: m['status'] as String? ?? 'active',
        created: m['created'] as String? ?? '',
        updated: m['updated'] as String? ?? '',
      );
}

/// One dated observation about a project.
///
/// Notes are the raw material for progress, not a comment field. The model reads
/// them to work out where a project has got to, which is only possible if they
/// accumulate in order rather than being overwritten by whatever the latest one
/// happened to say.
class ProjectNote {
  final int? id;
  final int projectId;
  final String body;
  final String created;

  const ProjectNote({
    this.id,
    required this.projectId,
    required this.body,
    this.created = '',
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'project_id': projectId,
        'body': body,
        'created': created,
      };

  factory ProjectNote.fromMap(Map<String, Object?> m) => ProjectNote(
        id: m['id'] as int?,
        projectId: m['project_id'] as int? ?? 0,
        body: m['body'] as String? ?? '',
        created: m['created'] as String? ?? '',
      );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
