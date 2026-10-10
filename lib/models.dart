/// Domain models, kept out of the storage layer so the assistant and the UI can
/// reason about them without importing sqflite.
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
      );

  DateTime? get parsedDue => due == null ? null : DateTime.tryParse(due!);

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
  bool isOverdueOn(DateTime today) {
    if (status == 'paid' || status == 'lost') return false;
    final d = parsedDue;
    if (d == null) return false;
    final midnight = DateTime(today.year, today.month, today.day);
    return d.isBefore(midnight);
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
