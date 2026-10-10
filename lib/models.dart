/// Domain models, kept out of the storage layer so the assistant and the UI can
/// reason about them without importing sqflite.
library;

/// One weight-and-measurements log.
class FitnessEntry {
  final int? id;
  final String day;
  final double? weight;
  final double? waist;
  final double? chest;
  final double? arm;
  final double? leg;
  final String? note;

  const FitnessEntry({
    this.id,
    required this.day,
    this.weight,
    this.waist,
    this.chest,
    this.arm,
    this.leg,
    this.note,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'day': day,
        if (weight != null) 'weight': weight,
        if (waist != null) 'waist': waist,
        if (chest != null) 'chest': chest,
        if (arm != null) 'arm': arm,
        if (leg != null) 'leg': leg,
        if (note != null) 'note': note,
      };

  /// Row for an UPDATE. Writes nulls so a cleared field is actually cleared.
  Map<String, Object?> toUpdateMap() => {
        'day': day,
        'weight': weight,
        'waist': waist,
        'chest': chest,
        'arm': arm,
        'leg': leg,
        'note': note,
      };

  factory FitnessEntry.fromMap(Map<String, Object?> m) => FitnessEntry(
        id: m['id'] as int?,
        day: m['day'] as String? ?? '',
        weight: (m['weight'] as num?)?.toDouble(),
        waist: (m['waist'] as num?)?.toDouble(),
        chest: (m['chest'] as num?)?.toDouble(),
        arm: (m['arm'] as num?)?.toDouble(),
        leg: (m['leg'] as num?)?.toDouble(),
        note: m['note'] as String?,
      );

  FitnessEntry copyWith({
    int? id,
    String? day,
    double? weight,
    double? waist,
    double? chest,
    double? arm,
    double? leg,
    String? note,
    bool clearNote = false,
  }) =>
      FitnessEntry(
        id: id ?? this.id,
        day: day ?? this.day,
        weight: weight ?? this.weight,
        waist: waist ?? this.waist,
        chest: chest ?? this.chest,
        arm: arm ?? this.arm,
        leg: leg ?? this.leg,
        note: clearNote ? null : (note ?? this.note),
      );

  /// BMI needs only weight and height; height lives in the profile.
  double? bmi(double heightM) {
    final w = weight;
    if (w == null || heightM <= 0) return null;
    return w / (heightM * heightM);
  }

  /// Parsed [day], or null when the stored value is not a date.
  DateTime? get parsedDay => DateTime.tryParse(day);
}

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

  const Client({
    this.id,
    required this.name,
    this.status = 'lead',
    this.amount,
    this.due,
    this.leadSource,
    this.note,
    this.created = '',
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'status': status,
        if (amount != null) 'amount': amount,
        if (due != null) 'due': due,
        if (leadSource != null) 'lead_source': leadSource,
        if (note != null) 'note': note,
        'created': created,
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
    bool clearDue = false,
    bool clearNote = false,
    bool clearAmount = false,
    bool clearSource = false,
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
      );

  DateTime? get parsedDue => due == null ? null : DateTime.tryParse(due!);

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

/// A message Koru prepared and is waiting for the user to approve.
///
/// Onboarding has always promised "drafts, never sends". Nothing ever
/// implemented it: there was no table, no screen, and no code path that produced
/// one. This is that feature.
enum DraftStatus { pending, approved, discarded }

class Draft {
  final int? id;
  final String title;
  final String body;
  final String channel;
  final DraftStatus status;
  final String created;

  const Draft({
    this.id,
    required this.title,
    required this.body,
    this.channel = 'note',
    this.status = DraftStatus.pending,
    this.created = '',
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'title': title,
        'body': body,
        'channel': channel,
        'status': status.name,
        'created': created,
      };

  factory Draft.fromMap(Map<String, Object?> m) => Draft(
        id: m['id'] as int?,
        title: m['title'] as String? ?? '',
        body: m['body'] as String? ?? '',
        channel: m['channel'] as String? ?? 'note',
        status: DraftStatus.values.firstWhere(
          (s) => s.name == m['status'],
          orElse: () => DraftStatus.pending,
        ),
        created: m['created'] as String? ?? '',
      );

  Draft copyWith({int? id, DraftStatus? status}) => Draft(
        id: id ?? this.id,
        title: title,
        body: body,
        channel: channel,
        status: status ?? this.status,
        created: created,
      );

  /// First line, for list rows.
  String get preview {
    final trimmed = body.trim().replaceAll(RegExp(r'\s+'), ' ');
    return trimmed.length <= 90 ? trimmed : '${trimmed.substring(0, 89)}...';
  }
}

/// Something the user is learning or building, with progress on it.
class KnowledgeTopic {
  final int? id;
  final String topic;
  final double progress;
  final String? note;
  final String updated;

  const KnowledgeTopic({
    this.id,
    required this.topic,
    this.progress = 0,
    this.note,
    this.updated = '',
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'topic': topic,
        'progress': progress,
        if (note != null) 'note': note,
        'updated': updated,
      };

  /// Row for an UPDATE. Writes nulls so a cleared note is actually cleared.
  Map<String, Object?> toUpdateMap() => {
        'topic': topic,
        'progress': progress,
        'note': note,
        'updated': updated,
      };

  factory KnowledgeTopic.fromMap(Map<String, Object?> m) => KnowledgeTopic(
        id: m['id'] as int?,
        topic: m['topic'] as String? ?? '',
        progress: (m['progress'] as num?)?.toDouble() ?? 0,
        note: m['note'] as String?,
        updated: m['updated'] as String? ?? '',
      );

  KnowledgeTopic copyWith({
    int? id,
    String? topic,
    double? progress,
    String? note,
    String? updated,
    bool clearNote = false,
  }) =>
      KnowledgeTopic(
        id: id ?? this.id,
        topic: topic ?? this.topic,
        progress: progress ?? this.progress,
        note: clearNote ? null : (note ?? this.note),
        updated: updated ?? this.updated,
      );

  /// Progress as a whole percentage, clamped. The column is a 0..1 fraction.
  int get percent => (progress.clamp(0.0, 1.0) * 100).round();
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
