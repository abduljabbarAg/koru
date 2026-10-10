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
}
