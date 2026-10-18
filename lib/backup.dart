import 'dart:convert';
import 'dart:io';

import 'models.dart';
import 'store.dart';

/// A readable dump of everything Koru holds.
///
/// This is not a database backup and does not claim to be one. The point of the
/// privacy promise is that the data never leaves the phone, and the obvious
/// failure of that promise is losing the phone: three years of clients, invoices
/// and what was actually paid, gone with a dropped device and no way to get it
/// back. A file the user saves themselves is the only copy that survives.
///
/// JSON rather than a SQLite file on purpose. A raw database copy is not readable
/// by a human, not restorable on a different device, and would carry the
/// `knowledge` and `drafts` tables that no longer have features behind them.
/// This is a record of what the app knows, in a form someone can read in five
/// years even if Koru is gone.
class Backup {
  const Backup._();

  /// The format version, so a future restore knows what it is looking at.
  static const int formatVersion = 1;

  /// Builds the whole record.
  ///
  /// Read from the store rather than assembled from providers, because a backup
  /// that silently omits a table when its provider has not loaded yet is worse
  /// than no backup at all.
  static Future<Map<String, Object?>> build(ProfileStore store) async {
    final profile = await store.all();
    // Read once. Calling store.clients() inside the payment loop turned a
    // single export into one query per row, which on a phone is the difference
    // between a second and a coffee break.
    final clients = await store.clients();
    return {
      'format': 'koru-backup',
      'format_version': formatVersion,
      'created': DateTime.now().toIso8601String(),
      'profile': profile,
      'clients': [
        for (final c in clients)
          {
            'name': c.name,
            'status': c.status,
            if (c.amount != null) 'amount': c.amount,
            if (c.monthly != null) 'monthly': c.monthly,
            if (c.due != null) 'due': c.due,
            if (c.leadSource != null) 'lead_source': c.leadSource,
            if (c.note != null) 'note': c.note,
            'created': c.created,
          }
      ],
      'payments': [
        for (final p in await store.payments(limit: 100000))
          {
            'client': _nameOf(clients, p.clientId),
            'amount': p.amount,
            'date': p.date,
            if (p.note != null) 'note': p.note,
          }
      ],
      'deadlines': [
        for (final d in await store.deadlines(openOnly: false))
          {
            if (d.clientId != null) 'client': _nameOf(clients, d.clientId!),
            'title': d.title,
            'due': d.due,
            'done': d.done,
          }
      ],
      // Tasks are in the backup for the reason the ledger is: a file somebody
      // keeps for years that silently omits the list they wrote their week on
      // is not a backup of their work. A task that belongs to a client is
      // matched by name like everything else, and one that belongs to nobody is
      // restored as a task that belongs to nobody — which is most of them, and
      // the reason a restore has to be able to keep a row with no client on it.
      'tasks': [
        for (final t in await store.tasks())
          {
            'title': t.title,
            if (t.clientId != null) 'client': _nameOf(clients, t.clientId!),
            'due': t.due,
            'priority': t.priority.name,
            'done': t.done,
            if (t.completedAt != null) 'completed_at': t.completedAt,
            if (t.note != null) 'note': t.note,
            'created': t.created,
          }
      ],
      'chat': [
        for (final c in await store.chat())
          {
            'role': c.role,
            'text': c.text,
            'created': c.created,
          }
      ],
    };
  }

  static String _nameOf(List<Client> clients, int id) {
    for (final c in clients) {
      if (c.id == id) return c.name;
    }
    return 'unknown';
  }

  /// Pretty-printed JSON, which is the point. A file someone can open and read
  /// is worth keeping; a minified blob of the same data is not.
  static Future<String> toJson(ProfileStore store) async =>
      const JsonEncoder.withIndent('  ').convert(await build(store));

  /// A filename that sorts and is obvious in a file manager.
  static String fileName([DateTime? at]) {
    final d = at ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'koru-backup-${d.year}-${two(d.month)}-${two(d.day)}'
        '-${two(d.hour)}${two(d.minute)}.json';
  }

  /// Writes it to [directory], returning the file written.
  ///
  /// The caller decides where that is. On Android the only sensible place the
  /// user can actually reach is somewhere the share sheet can pick up, so this
  /// deliberately does not choose a path.
  static Future<File> writeTo(ProfileStore store, Directory directory) async {
    final file = File('${directory.path}/${fileName()}');
    await file.writeAsString(await toJson(store), flush: true);
    return file;
  }

  /// Reads a backup back.
  ///
  /// Returns a count of what was applied, or throws with something a person can
  /// act on. Import is additive and never destructive: everything is merged
  /// into what is already there and nothing is deleted or overwritten, because
  /// the likely reason someone is restoring is that they lost the current data
  /// and overwriting it with an older file would be a second loss.
  ///
  /// Clients are matched by name. A payment is attached to the client it names,
  /// or to the first client with that name if there are several, and is skipped
  /// entirely when there is none: a payment with no client cannot be shown and
  /// a made-up one would be a fiction.
  static Future<RestoreReport> restore(ProfileStore store, String json) async {
    final decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('That file is not a Koru backup.');
    }
    if (decoded['format'] != 'koru-backup') {
      throw const FormatException('That file is not a Koru backup.');
    }
    final version = decoded['format_version'];
    if (version is! int || version > formatVersion) {
      throw FormatException(
        'That backup was made by a newer version of Koru (format $version). '
        'Update the app first.',
      );
    }

    final byName = <String, List<Client>>{};
    for (final c in await store.clients()) {
      byName.putIfAbsent(c.name.toLowerCase(), () => <Client>[]).add(c);
    }

    Client? resolve(Object? name) {
      if (name is! String) return null;
      final matches = byName[name.toLowerCase()];
      return (matches == null || matches.isEmpty) ? null : matches.first;
    }

    var clients = 0;
    for (final row in _rows(decoded['clients'])) {
      final name = row['name'];
      if (name is! String || name.trim().isEmpty) continue;
      if (byName.containsKey(name.toLowerCase())) continue;
      final created = await store.addClient(Client(
        name: name,
        status: row['status'] as String? ?? 'lead',
        amount: _num(row['amount']),
        due: row['due'] as String?,
        leadSource: row['lead_source'] as String?,
        note: row['note'] as String?,
        monthly: _num(row['monthly']),
        created: row['created'] as String? ?? '',
      ));
      byName
          .putIfAbsent(name.toLowerCase(), () => <Client>[])
          .add((await store.clients()).firstWhere((c) => c.id == created));
      clients++;
    }

    var payments = 0;
    var orphans = 0;
    // Already-known payments, so a second restore is a no-op rather than a
    // second copy. Without this, restoring the same file twice would quietly
    // double someone's income, and the balance they trust would be wrong.
    final existing = <String>{};
    for (final p in await store.payments(limit: 100000)) {
      existing.add('${p.clientId}|${p.amount}|${p.date}|${p.note ?? ''}');
    }

    for (final row in _rows(decoded['payments'])) {
      final client = resolve(row['client']);
      final amount = _num(row['amount']);
      if (client == null || amount == null) {
        orphans++;
        continue;
      }
      final date = row['date'] as String? ?? '';
      final note = row['note'] as String?;
      final key = '${client.id}|$amount|$date|${note ?? ''}';
      if (existing.contains(key)) continue;
      await store.addPayment(
        Payment(clientId: client.id!, amount: amount, date: date, note: note),
      );
      existing.add(key);
      payments++;
    }

    var tasks = 0;
    final knownTasks = <String>{};
    for (final t in await store.tasks()) {
      knownTasks.add('${t.clientId ?? ''}|${t.title}|${t.due ?? ''}');
    }
    for (final row in _rows(decoded['tasks'])) {
      final title = row['title'];
      if (title is! String || title.trim().isEmpty) continue;
      // No client is a legitimate state rather than a broken row, so it resolves
      // to nobody rather than counting as an orphan. Skipping these would mean a
      // restore quietly dropped exactly the one-off chores the task list was
      // added for.
      final client = resolve(row['client']);
      final due = row['due'] as String?;
      final key = '${client?.id ?? ''}|$title|${due ?? ''}';
      if (knownTasks.contains(key)) continue;
      await store.addTask(Task(
        title: title,
        clientId: client?.id,
        due: due,
        priority: TaskPriority.parse(row['priority']),
        done: row['done'] == true,
        completedAt: row['completed_at'] as String?,
        note: row['note'] as String?,
        created: row['created'] as String? ?? '',
      ));
      knownTasks.add(key);
      tasks++;
    }

    var deadlines = 0;
    final knownDeadlines = <String>{};
    for (final d in await store.deadlines(openOnly: false)) {
      knownDeadlines.add('${d.clientId ?? ''}|${d.title}|${d.due}');
    }
    for (final row in _rows(decoded['deadlines'])) {
      final title = row['title'];
      if (title is! String || title.trim().isEmpty) continue;
      final client = resolve(row['client']);
      final due = row['due'] as String? ?? '';
      final key = '${client?.id ?? ''}|$title|$due';
      if (knownDeadlines.contains(key)) continue;
      await store.addDeadline(Deadline(
        clientId: client?.id,
        title: title,
        due: due,
        done: row['done'] == true,
      ));
      knownDeadlines.add(key);
      deadlines++;
    }

    return RestoreReport(
      clients: clients,
      payments: payments,
      deadlines: deadlines,
      tasks: tasks,
      skipped: orphans,
    );
  }

  static List<Map<String, dynamic>> _rows(Object? raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().toList();
  }

  static double? _num(Object? v) => v is num ? v.toDouble() : null;
}

/// What a restore actually did, so it can be said plainly rather than as
/// "import complete" when some of it did not apply.
class RestoreReport {
  const RestoreReport({
    required this.clients,
    required this.payments,
    required this.deadlines,
    this.tasks = 0,
    required this.skipped,
  });

  final int clients;
  final int payments;
  final int deadlines;

  /// Tasks restored. Optional in the constructor because an older caller that
  /// never heard of them still builds a valid report.
  final int tasks;

  /// Payments that named a client this install does not have. They are counted
  /// and dropped rather than attached to whoever happens to be first in the
  /// list, which would be a fabricated record of money.
  final int skipped;

  int get total => clients + payments + deadlines + tasks;

  String get summary {
    if (total == 0) return 'Nothing new in that backup';
    final parts = <String>[
      if (clients > 0) '$clients client${clients == 1 ? '' : 's'}',
      if (payments > 0) '$payments payment${payments == 1 ? '' : 's'}',
      if (deadlines > 0) '$deadlines deadline${deadlines == 1 ? '' : 's'}',
      if (tasks > 0) '$tasks task${tasks == 1 ? '' : 's'}',
    ];
    final base = 'Restored ${parts.join(', ')}';
    return skipped == 0 ? base : '$base. $skipped payment${skipped == 1 ? '' : 's'} skipped, no matching client';
  }
}
