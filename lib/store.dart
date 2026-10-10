import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'models.dart';
import 'packet.dart';

/// Local storage. Everything the user has ever entered lives here and nowhere
/// else.
///
/// v1 stores plain SQLite in the app's private directory, which Android isolates
/// per app. The encryption layer is a named later task; the schema and access
/// path are written so that swapping in SQLCipher changes only [open].
class ProfileStore {
  ProfileStore(this._db);

  final Database _db;

  static const int schemaVersion = 3;

  static Future<ProfileStore> open({Directory? directory}) async {
    final dir = directory ?? await getApplicationDocumentsDirectory();
    final db = await openDatabase(
      '${dir.path}/koru.db',
      version: schemaVersion,
      onCreate: (d, v) async {
        await _createV1(d);
        if (v >= 2) await _migrateToV2(d);
        if (v >= 3) await _migrateToV3(d);
      },
      onUpgrade: (d, from, to) async {
        if (from < 2) await _migrateToV2(d);
        if (from < 3) await _migrateToV3(d);
      },
    );
    return ProfileStore(db);
  }

  static Future<void> _createV1(Database d) async {
    await d.execute('''
      CREATE TABLE profile(
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await d.execute('''
      CREATE TABLE fitness(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        day TEXT NOT NULL,
        weight REAL,
        waist REAL,
        chest REAL,
        arm REAL,
        leg REAL,
        note TEXT
      )
    ''');
    await d.execute('''
      CREATE TABLE business(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        status TEXT NOT NULL,
        amount REAL,
        due TEXT,
        lead_source TEXT,
        note TEXT,
        created TEXT NOT NULL
      )
    ''');
    await d.execute('''
      CREATE TABLE knowledge(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        topic TEXT NOT NULL,
        progress REAL DEFAULT 0,
        note TEXT,
        updated TEXT NOT NULL
      )
    ''');
  }

  /// Drafts and chat history. The `knowledge` table already existed but nothing
  /// read or wrote it; drafts and chat were missing entirely even though the
  /// onboarding screen promised drafts and the app called itself a companion that
  /// remembers.
  /// Money received, and dated work. Both are per client so "what is owed and
  /// by when" is a query rather than something retyped by hand.
  static Future<void> _migrateToV3(Database d) async {
    await d.execute('''
      CREATE TABLE IF NOT EXISTS payments(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_id INTEGER NOT NULL,
        amount REAL NOT NULL,
        date TEXT NOT NULL,
        note TEXT
      )
    ''');
    await d.execute('''
      CREATE TABLE IF NOT EXISTS deadlines(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_id INTEGER,
        title TEXT NOT NULL,
        due TEXT NOT NULL,
        done INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  static Future<void> _migrateToV2(Database d) async {
    await d.execute('''
      CREATE TABLE drafts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        channel TEXT NOT NULL DEFAULT 'note',
        status TEXT NOT NULL DEFAULT 'pending',
        created TEXT NOT NULL
      )
    ''');
    await d.execute('''
      CREATE TABLE chat(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        role TEXT NOT NULL,
        text TEXT NOT NULL,
        why TEXT,
        needs_human INTEGER NOT NULL DEFAULT 0,
        created TEXT NOT NULL
      )
    ''');
  }

  // -- profile ---------------------------------------------------------

  Future<void> put(String key, String value) async {
    await _db.insert(
      'profile',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> get(String key) async {
    final rows = await _db.query('profile', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<Map<String, String>> all() async {
    final rows = await _db.query('profile');
    return {for (final r in rows) r['key'] as String: r['value'] as String};
  }

  Future<double?> number(String key) async => double.tryParse((await get(key)) ?? '');

  Future<void> putNumber(String key, double value) => put(key, '$value');

  /// The only place a ContextPacket is ever constructed.
  Future<ContextPacket> packet() async {
    final m = await all();
    return ContextPacket(
      nickname: m['nickname'] ?? 'the user',
      lifeStage: m['stage'] ?? '',
      business: m['business'] ?? '',
      goals: m['goals'] ?? '',
      fitness: m['fitness_summary'] ?? '',
      // help_focus was written during onboarding and then never read by anything,
      // which left ContextPacket.focus permanently empty.
      focus: m['help_focus'] ?? '',
    );
  }

  Future<bool> get onboarded async => (await get('onboarded')) == '1';

  Future<void> completeOnboarding() => put('onboarded', '1');

  /// Recomputes the fitness line that goes into the packet. Called after every
  /// measurement change so the context can never drift from the logs.
  Future<void> refreshFitnessSummary() async {
    final height = await number('height');
    final entries = await fitness(limit: 1);
    if (entries.isEmpty) {
      await put('fitness_summary', 'no measurements yet');
      return;
    }
    final latest = entries.first;
    final parts = <String>[];
    final w = latest.weight;
    if (w != null) parts.add('weight ${w.toStringAsFixed(1)}kg');
    final bmi = height == null ? null : latest.bmi(height);
    if (bmi != null) {
      parts.add('BMI ${bmi.toStringAsFixed(1)}');
      await putNumber('bmi', double.parse(bmi.toStringAsFixed(1)));
    }
    if (height != null) parts.add('height ${height.toStringAsFixed(2)}m');
    await put('fitness_summary', parts.isEmpty ? 'no measurements yet' : parts.join(', '));
  }

  Future<void> wipe() async {
    for (final table in ['profile', 'fitness', 'business', 'knowledge', 'drafts', 'chat']) {
      await _db.delete(table);
    }
  }

  // -- fitness ---------------------------------------------------------

  Future<int> addFitness(FitnessEntry e) => _db.insert('fitness', e.toMap());

  Future<List<FitnessEntry>> fitness({int limit = 30}) async {
    final rows = await _db.query('fitness', orderBy: 'day DESC, id DESC', limit: limit);
    return rows.map(FitnessEntry.fromMap).toList();
  }

  Future<void> updateFitness(FitnessEntry e) async {
    final id = e.id;
    if (id == null) return;
    await _db.update('fitness', e.toUpdateMap(), where: 'id = ?', whereArgs: [id]);
    await refreshFitnessSummary();
  }

  Future<void> deleteFitness(int id) async {
    await _db.delete('fitness', where: 'id = ?', whereArgs: [id]);
    await refreshFitnessSummary();
  }

  // -- business --------------------------------------------------------

  Future<int> addClient(Client c) => _db.insert('business', c.toMap());

  Future<List<Client>> clients() async {
    // '<' inside a string is fine, but Dart's parser treats an unbalanced
    // '<' after a quote in an argument as a type argument, so orderBy uses a
    // named constant to keep the parser out of it.
    const order = 'created' ' DESC';
    final rows = await _db.query('business', orderBy: order);
    return rows.map(Client.fromMap).toList();
  }

  Future<void> setClientStatus(int id, String status) async {
    await _db.update('business', {'status': status}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateClient(Client c) async {
    final id = c.id;
    if (id == null) return;
    await _db.update('business', c.toUpdateMap(), where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteClient(int id) =>
      _db.delete('business', where: 'id = ?', whereArgs: [id]);

  // -- knowledge -------------------------------------------------------

  Future<int> addTopic(KnowledgeTopic t) => _db.insert('knowledge', t.toMap());

  Future<List<KnowledgeTopic>> topics() async {
    const order = 'updated' ' DESC';
    final rows = await _db.query('knowledge', orderBy: order);
    return rows.map(KnowledgeTopic.fromMap).toList();
  }

  Future<void> updateTopic(KnowledgeTopic t) async {
    final id = t.id;
    if (id == null) return;
    await _db.update('knowledge', t.toUpdateMap(), where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteTopic(int id) =>
      _db.delete('knowledge', where: 'id = ?', whereArgs: [id]);

  // -- drafts ----------------------------------------------------------

  Future<int> addDraft(Draft d) => _db.insert('drafts', d.toMap());

  /// Money received, newest first.
  Future<List<Payment>> payments({int? clientId}) async {
    final rows = clientId == null
        ? await _db.query('payments', orderBy: 'date DESC, id DESC')
        : await _db.query('payments',
            where: 'client_id = ?', whereArgs: [clientId], orderBy: 'date DESC, id DESC');
    return rows.map(Payment.fromMap).toList();
  }

  Future<int> addPayment(Payment p) => _db.insert('payments', p.toMap());

  /// What has been received against one client, in total.
  Future<double> receivedFor(int clientId) async {
    final r = await _db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) AS total FROM payments WHERE client_id = ?',
      [clientId],
    );
    return (r.first['total'] as num).toDouble();
  }

  /// Outstanding balance for a client: invoiced minus everything received.
  ///
  /// Zero when a client has no amount on file, rather than a negative balance,
  /// because a negative number here would read as money owed to the freelancer.
  Future<double> balanceFor(Client c) async {
    final invoiced = c.amount ?? 0;
    if (invoiced <= 0) return 0;
    return invoiced - await receivedFor(c.id!);
  }

  Future<List<Deadline>> deadlines({int? clientId, bool openOnly = true}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (clientId != null) {
      where.add('client_id = ?');
      args.add(clientId);
    }
    if (openOnly) where.add('done = 0');
    final rows = await _db.query(
      'deadlines',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'due ASC',
    );
    return rows.map(Deadline.fromMap).toList();
  }

  Future<int> addDeadline(Deadline d) => _db.insert('deadlines', d.toMap());

  Future<List<Draft>> drafts({DraftStatus? status}) async {
    final rows = await _db.query(
      'drafts',
      where: status == null ? null : 'status = ?',
      whereArgs: status == null ? null : [status.name],
      orderBy: 'id DESC',
    );
    return rows.map(Draft.fromMap).toList();
  }

  Future<void> setDraftStatus(int id, DraftStatus status) async {
    await _db.update('drafts', {'status': status.name}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteDraft(int id) =>
      _db.delete('drafts', where: 'id = ?', whereArgs: [id]);

  // -- chat ------------------------------------------------------------

  Future<int> addChat(ChatRecord record) => _db.insert('chat', record.toMap());

  Future<List<ChatRecord>> chat({int limit = 200}) async {
    final rows = await _db.query('chat', orderBy: 'id ASC', limit: limit);
    return rows.map(ChatRecord.fromMap).toList();
  }

  Future<void> clearChat() => _db.delete('chat');

  Future<void> close() => _db.close();
}

/// A persisted chat turn.
///
/// Carries [needsHuman] because a handoff is part of the record of what was
/// said, not just a decoration: reloading the thread has to bring the escalation
/// card back with it.
class ChatRecord {
  final int? id;
  final String role;
  final String text;
  final String? why;
  final bool needsHuman;
  final String created;

  const ChatRecord({
    this.id,
    required this.role,
    required this.text,
    this.why,
    this.needsHuman = false,
    this.created = '',
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'role': role,
        'text': text,
        'why': why,
        'needs_human': needsHuman ? 1 : 0,
        'created': created,
      };

  factory ChatRecord.fromMap(Map<String, Object?> m) => ChatRecord(
        id: m['id'] as int?,
        role: m['role'] as String? ?? 'koru',
        text: m['text'] as String? ?? '',
        why: m['why'] as String?,
        needsHuman: (m['needs_human'] as int? ?? 0) == 1,
        created: m['created'] as String? ?? '',
      );
}
