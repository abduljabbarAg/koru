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
  ProfileStore(Database db) : _db = db, _root = db;

  /// A store scoped to an open transaction, so writes through it cannot escape
  /// one. [transaction] uses this and nothing else should.
  ProfileStore._scoped(DatabaseExecutor db) : _db = db, _root = null;

  /// Queries and writes. Either the real database or an open transaction.
  final DatabaseExecutor _db;

  /// The real database, for the things a transaction cannot do.
  ///
  /// Null inside a scoped store. Casting it there threw a type error at runtime
  /// and, worse, made the rollback test pass for the wrong reason: it proved
  /// nothing landed because the cast failed before anything ran, not because the
  /// transaction rolled back. A test that passes for the wrong reason is worse
  /// than no test, so [transaction] and [close] refuse clearly instead.
  final Database? _root;

  static const int schemaVersion = 9;

  static Future<ProfileStore> open({Directory? directory}) async {
    final dir = directory ?? await getApplicationDocumentsDirectory();
    final db = await openDatabase(
      '${dir.path}/koru.db',
      version: schemaVersion,
      onCreate: (d, v) async {
        await _createV1(d);
        if (v >= 2) await _migrateToV2(d);
        if (v >= 3) await _migrateToV3(d);
        if (v >= 4) await _migrateToV4(d);
        if (v >= 5) await _migrateToV5(d);
        if (v >= 6) await _migrateToV6(d);
        if (v >= 7) await _migrateToV7(d);
        if (v >= 8) await _migrateToV8(d);
        if (v >= 9) await _migrateToV9(d);
      },
      onUpgrade: (d, from, to) async {
        if (from < 2) await _migrateToV2(d);
        if (from < 3) await _migrateToV3(d);
        if (from < 4) await _migrateToV4(d);
        if (from < 5) await _migrateToV5(d);
        if (from < 6) await _migrateToV6(d);
        if (from < 7) await _migrateToV7(d);
        if (from < 8) await _migrateToV8(d);
        if (from < 9) await _migrateToV9(d);
      },
    );
    return ProfileStore(db);
  }

  /// Repeat rules for calendar entries.
  ///
  /// Additive, so existing installs keep their entries. The column is the
  /// enum's name rather than an integer so a future kind cannot silently
  /// renumber what is already stored.
  static Future<void> _migrateToV8(Database d) async {
    await d.execute('ALTER TABLE events ADD COLUMN recurrence TEXT');
  }

  /// A phone number on the client.
  ///
  /// Nullable and additive, so a client added before this keeps working with no
  /// number on file. It is only used to build a WhatsApp link — nothing is
  /// uploaded, no account is connected, and the app never sends anything by
  /// itself. The number goes into a link the user taps and finishes themselves,
  /// which is the same deal as tapping an email address.
  static Future<void> _migrateToV9(Database d) async {
    await d.execute('ALTER TABLE business ADD COLUMN phone TEXT');
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
        phone TEXT,
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

  /// How a client actually gets paid, worked out rather than typed in.
  ///
  /// Added because "add client" was a name and an optional amount and an
  /// optional date, and all three were optional. Which meant the normal outcome
  /// was a client with nothing in it, every total on the Business page reading
  /// zero, and nothing ever overdue, so the notification and widget system had
  /// nothing to ever say. The features worked; they were being handed empty.
  ///
  /// Deposit, terms and the invoice date are the three things that were missing.
  /// The deposit is a payment, so it goes into the ledger rather than being
  /// subtracted here, which keeps one source of truth for money: agreed minus
  /// received, where received includes the deposit.
  static Future<void> _migrateToV6(Database d) async {
    // Additive columns, all nullable. Existing rows keep working exactly as
    // they did, including clients with no amount, because making them required
    // here would mean a migration that can fail on someone's real data.
    for (final column in ['deposit', 'terms_days', 'invoiced_on']) {
      await d.execute('ALTER TABLE business ADD COLUMN $column');
    }
  }

  /// Calendar entries.
  ///
  /// A separate table from deadlines on purpose: deadlines answer "what has to
  /// be finished by when", this answers "what is on my calendar", and the two
  /// questions have different shapes (a time, a duration, a place).
  static Future<void> _migrateToV7(Database d) async {
    await d.execute('''
      CREATE TABLE IF NOT EXISTS events(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        time TEXT,
        title TEXT NOT NULL,
        location TEXT,
        note TEXT,
        client_id INTEGER,
        duration_min INTEGER,
        synced INTEGER NOT NULL DEFAULT 0,
        created TEXT NOT NULL
      )
    ''');
    // Calendar screens ask for one day or one week at a time, constantly.
    await d.execute(
        'CREATE INDEX IF NOT EXISTS idx_events_date ON events(date, time)');
  }

  /// Projects and their notes.
  ///
  /// Added because "project" was doing two incompatible jobs at once. Work for a
  /// client is money, so it belonged with clients; work for yourself is not, and
  /// putting it in the same table meant a side project with an amount of zero
  /// showed up in every balance total, every prompt and every "who owes you"
  /// question. So kind is explicit and the money lives somewhere else.
  static Future<void> _migrateToV5(Database d) async {
    await d.execute('''
      CREATE TABLE IF NOT EXISTS projects(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        kind TEXT NOT NULL DEFAULT 'client',
        client_id INTEGER,
        target TEXT,
        plan TEXT,
        progress REAL DEFAULT 0,
        progress_note TEXT,
        status TEXT NOT NULL DEFAULT 'active',
        created TEXT NOT NULL,
        updated TEXT NOT NULL
      )
    ''');
    await d.execute('''
      CREATE TABLE IF NOT EXISTS project_notes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project_id INTEGER NOT NULL,
        body TEXT NOT NULL,
        created TEXT NOT NULL
      )
    ''');
    // Notes are read newest last, per project, constantly. Without this the
    // query behind "where am I with this" is a full scan and a sort.
    await d.execute(
        'CREATE INDEX IF NOT EXISTS idx_project_notes_project ON project_notes(project_id, id)');
    // A project belongs to at most one client. Not enforced as a foreign key
    // because the app deletes clients rather than cascading, and a cascade that
    // silently took a user's work with it would be the wrong default.
    await d.execute(
        'CREATE INDEX IF NOT EXISTS idx_projects_client ON projects(client_id)');
  }

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

  /// A retainer, meaning money that arrives every month without a new invoice.
  ///
  /// Additive on purpose, and nullable so every existing client is unaffected:
  /// almost nobody has a retainer, and a default of 0 would make a zero-rate
  /// client look like a free one.
  static Future<void> _migrateToV4(Database d) async {
    await d.execute('ALTER TABLE business ADD COLUMN monthly REAL');
  }

  /// Chat history, added when onboarding already promised a companion that
  /// remembers and the app had nowhere to keep the conversation.
  ///
  /// The drafts table came with it and was never written to. Both it and the
  /// older `knowledge` table are still created and still cleared by [wipe],
  /// because dropping a table needs a migration that destroys whatever a user
  /// had typed into it, and an empty table costs nothing. Nothing reads or
  /// writes them.
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
      // help_focus was written during onboarding and then never read by anything,
      // which left ContextPacket.focus permanently empty.
      focus: m['help_focus'] ?? '',
      projects: await _packetProjects(),
    );
  }

  /// Projects as the cloud sees them: what the work is, never who it is for.
  ///
  /// A client project is named by its target rather than its owner, because the
  /// owner is a person and this string leaves the phone. Money is left out too,
  /// since the packet is about shape not amounts.
  Future<List<String>> _packetProjects() async {
    final out = <String>[];
    for (final pr in await projects()) {
      if (pr.kind == ProjectKind.client) {
        final target = pr.target?.trim();
        final what = target != null && target.isNotEmpty ? target : 'client work';
        out.add('a client project ($what, '
            '${(pr.progress * 100).round()}% along)');
      } else {
        out.add('personal project (${pr.name}, '
            '${(pr.progress * 100).round()}% along)');
      }
    }
    return out;
  }

  Future<bool> get onboarded async => (await get('onboarded')) == '1';

  Future<void> completeOnboarding() => put('onboarded', '1');

  Future<void> wipe() async {
    // payments and deadlines are in this list because this is the only promise
    // the app makes about deletion, and a ledger left behind after "delete
    // everything" is the worst possible thing to leave behind. `knowledge` and
    // `drafts` still appear: the features are gone but the tables exist on
    // older installs and must be cleared with everything else.
    for (final table in [
      'profile',
      'fitness',
      'business',
      'knowledge',
      'drafts',
      'chat',
      'payments',
      'deadlines',
      'projects',
      'project_notes',
      'events',
    ]) {
      await _db.delete(table);
    }
  }

  // -- fitness ---------------------------------------------------------
  //
  // Removed with the screen. The table is still created and still cleared by
  // wipe, because dropping it needs a migration that destroys whatever was
  // logged there, and an empty table costs nothing.

  // -- business --------------------------------------------------------

  Future<int> addClient(Client c) => _db.insert('business', c.toMap());

  /// One client by id, or null when it is not on file.
  ///
  /// Exists so a write can confirm its target still exists. The payments table
  /// carries no foreign key to this one, so without this check a payment for a
  /// deleted client is recorded against nobody and simply vanishes from every
  /// balance.
  Future<Client?> client(int id) async {
    final rows = await _db.query('business',
        where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Client.fromMap(rows.first);
  }

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
  //
  // Removed. The table survives; these accessors do not.

  // -- drafts ----------------------------------------------------------
  //
  // Removed. addDraft never had a caller, so the screen showed nothing forever.

  /// Money received, newest first, optionally narrowed to one client.
  ///
  /// Paged rather than returned whole: a ledger grows every time someone is paid,
  /// and the only thing the UI ever shows is the latest handful. Totals come from
  /// [receivedFor], which sums in SQL and so is unaffected by this limit.
  Future<List<Payment>> payments({int? clientId, int limit = 20}) async {
    final rows = await _db.query(
      'payments',
      where: clientId == null ? null : 'client_id = ?',
      whereArgs: clientId == null ? null : [clientId],
      orderBy: 'date DESC, id DESC',
      limit: limit,
    );
    return rows.map(Payment.fromMap).toList();
  }

  Future<int> addPayment(Payment p) => _db.insert('payments', p.toMap());

  /// When this client last paid, or null if they never have.
  ///
  /// A retainer is judged on whether the money is turning up, not on an invoice
  /// balance, so this is the only number that says whether a retainer is being
  /// honoured.
  Future<DateTime?> lastPaymentOn(int clientId) async {
    final r = await _db.rawQuery(
      'SELECT MAX(date) AS last FROM payments WHERE client_id = ?',
      [clientId],
    );
    final value = r.first['last'] as String?;
    return value == null ? null : DateTime.tryParse(value);
  }

  /// When a retainer is next due, or null when it is not a retainer or has never
  /// been paid.
  ///
  /// A month after the last payment, not a fixed day of the month, because most
  /// retainers are billed on whatever day the relationship started and a fixed
  /// date would drift.
  Future<DateTime?> nextRetainerDue(Client c) async {
    if (!c.isRetainer || c.id == null) return null;
    final last = await lastPaymentOn(c.id!);
    if (last == null) return null;
    return DateTime(last.year, last.month + 1, last.day);
  }

  /// Withdraws a payment that was recorded by mistake.
  ///
  /// The client is deliberately not re-marked unpaid here. The status is derived
  /// from the ledger when the screen next reads it, so undoing one row is enough
  /// and guessing at the resulting status here would be a second source of truth.
  Future<void> deletePayment(int id) =>
      _db.delete('payments', where: 'id = ?', whereArgs: [id]);

  /// What has been received against one client, in total.
  Future<double> receivedFor(int clientId) async {
    final r = await _db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) AS total FROM payments WHERE client_id = ?',
      [clientId],
    );
    return (r.first['total'] as num).toDouble();
  }

  /// What has been received against every client, in one query.
  ///
  /// Grouped in SQL rather than by summing rows in Dart, because summing rows
  /// means reading the whole ledger and then only being right about the last
  /// thousand payments. Clients with no payments are absent from the map, which
  /// reads as nothing received, which is what they are.
  Future<Map<int, double>> receivedTotals() async {
    final rows = await _db.rawQuery(
      'SELECT client_id, COALESCE(SUM(amount), 0) AS total FROM payments GROUP BY client_id',
    );
    return {
      for (final r in rows) r['client_id'] as int: (r['total'] as num).toDouble(),
    };
  }

  /// Outstanding balance for a client: invoiced minus everything received.
  ///
  /// Reads the ledger, so it costs a query per client. The screen shows a whole
  /// list and so uses [Client.balanceWith] against a single grouped total
  /// instead; the arithmetic is shared either way.
  Future<double> balanceFor(Client c) async {
    if (c.id == null) return 0;
    return c.balanceWith(await receivedFor(c.id!));
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

  Future<void> setDeadlineDone(int id, bool done) =>
      _db.update('deadlines', {'done': done ? 1 : 0}, where: 'id = ?', whereArgs: [id]);

  Future<void> deleteDeadline(int id) =>
      _db.delete('deadlines', where: 'id = ?', whereArgs: [id]);

  // -- calendar events -------------------------------------------------

  /// Events from [from] (inclusive) to [to] (inclusive), soonest first.
  ///
  /// Both ends optional so "everything on file" and "this week" are the same
  /// query. All-day entries sort before timed ones on the same day by the
  /// secondary order on time, with NULL first, which SQLite does for free.
  Future<List<CalendarEvent>> events({DateTime? from, DateTime? to}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (from != null) {
      where.add('date >= ?');
      args.add(_isoDate(from));
    }
    if (to != null) {
      where.add('date <= ?');
      args.add(_isoDate(to));
    }
    final rows = await _db.query(
      'events',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'date ASC, time ASC, id ASC',
    );
    return rows.map(CalendarEvent.fromMap).toList();
  }

  Future<int> addEvent(CalendarEvent e) => _db.insert('events', e.toMap());

  Future<void> updateEvent(CalendarEvent e) async {
    await _db.update('events', e.toUpdateMap(),
        where: 'id = ?', whereArgs: [e.id]);
  }

  Future<void> deleteEvent(int id) =>
      _db.delete('events', where: 'id = ?', whereArgs: [id]);

  /// One entry by id, or null once it has been deleted.
  Future<CalendarEvent?> event(int id) async {
    final rows = await _db.query('events', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : CalendarEvent.fromMap(rows.first);
  }

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // -- projects --------------------------------------------------------

  Future<int> addProject(Project p) => _db.insert('projects', p.toMap());

  Future<void> updateProject(Project p) async {
    await _db.update('projects', p.toUpdateMap(),
        where: 'id = ?', whereArgs: [p.id]);
  }

  /// Projects, most recently touched first.
  ///
  /// Ordered by [Project.updated] rather than by name because the question this
  /// screen answers is "what am I in the middle of", and the thing you worked on
  /// yesterday is the answer far more often than the alphabetical first.
  Future<List<Project>> projects({ProjectKind? kind}) async {
    final rows = await _db.query(
      'projects',
      where: kind == null ? null : 'kind = ?',
      whereArgs: kind == null ? null : [kind.name],
      orderBy: 'updated DESC, id DESC',
    );
    return rows.map(Project.fromMap).toList();
  }

  Future<Project?> project(int id) async {
    final rows = await _db.query('projects', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Project.fromMap(rows.first);
  }

  Future<void> deleteProject(int id) async {
    // The notes go too. They are the only record of what actually happened, so
    // leaving them behind would mean a note that referred to nothing.
    await _db.delete('project_notes', where: 'project_id = ?', whereArgs: [id]);
    await _db.delete('projects', where: 'id = ?', whereArgs: [id]);
  }

  // -- project notes ----------------------------------------------------

  Future<int> addProjectNote(ProjectNote n) => _db.insert('project_notes', n.toMap());

  Future<void> deleteProjectNote(int id) =>
      _db.delete('project_notes', where: 'id = ?', whereArgs: [id]);

  /// Every note for a project, oldest first.
  ///
  /// Oldest first because this is read by a model to work out how far along
  /// something is, and a sequence reversed is a sequence misread.
  Future<List<ProjectNote>> projectNotes(int projectId, {int limit = 200}) async {
    final rows = await _db.query(
      'project_notes',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'id ASC',
      limit: limit,
    );
    return rows.map(ProjectNote.fromMap).toList();
  }

  /// The newest notes across every project, for the model to read at a glance.
  Future<List<ProjectNote>> recentProjectNotes({int limit = 20}) async {
    final rows = await _db.query('project_notes', orderBy: 'id DESC', limit: limit);
    return rows.map(ProjectNote.fromMap).toList().reversed.toList();
  }

  // -- chat ------------------------------------------------------------

  Future<int> addChat(ChatRecord record) => _db.insert('chat', record.toMap());

  Future<List<ChatRecord>> chat({int limit = 200}) async {
    final rows = await _db.query('chat', orderBy: 'id ASC', limit: limit);
    return rows.map(ChatRecord.fromMap).toList();
  }

  Future<void> clearChat() => _db.delete('chat');

  /// Runs [action] against the database as one all-or-nothing unit.
  ///
  /// Used by bulk import. Twenty rows applied one at a time can fail on the
  /// eleventh and leave nine clients behind with no record of which nine, and
  /// the user has no way to tell what happened from what they see afterwards.
  /// A transaction means the import either lands whole or not at all, so the
  /// screen and the ledger can never disagree about how far it got.
  ///
  /// The [ProfileStore] handed to [action] is scoped to the transaction. Using
  /// the outer store inside would quietly write outside it, which defeats the
  /// entire point and is the reason this returns a scoped instance rather than
  /// just running [action].
  Future<T> transaction<T>(Future<T> Function(ProfileStore scoped) action) async {
    late T result;
    final root = _root;
    if (root == null) {
      throw StateError(
        'This store is already inside a transaction and cannot open another. '
        'Nested transactions are not needed here and would not be atomic.',
      );
    }
    await root.transaction((txn) async {
      result = await action(ProfileStore._scoped(txn));
    });
    return result;
  }

  /// Keeps the first [keep] messages and drops everything after them.
  ///
  /// Used when an earlier message is edited: the exchange it started, and the
  /// answer it produced, are both wrong now. Deleting by id rather than
  /// re-inserting the survivors keeps their original timestamps.
  Future<void> truncateChat(int keep) async {
    if (keep <= 0) return clearChat();
    final rows = await _db.query('chat', columns: ['id'], orderBy: 'id ASC', limit: keep);
    if (rows.length < keep) return;
    await _db.delete('chat', where: 'id > ?', whereArgs: [rows.last['id']!]);
  }

  Future<void> close() async {
    final root = _root;
    if (root == null) {
      throw StateError('A transaction-scoped store does not own the database.');
    }
    await root.close();
  }
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
