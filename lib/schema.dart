import 'package:sqflite/sqflite.dart';

/// Everything this app has ever done to a database, in one file.
///
/// Each migration is written to be runnable against the database as it was at
/// the time and as it is now, because it runs once per person, on their phone,
/// with their data, and nothing else in the app will ever run it. A migration
/// that throws leaves every existing install unable to open the app at all, and
/// no other test touches this code — so the tests in `test/migration_test.dart`
/// build a real old database and upgrade it for real.
///
/// Kept apart from `store.dart` because this is a history and that is a set of
/// queries: mixed together, the file that has to be right about everybody's data
/// was also the file that was over nine hundred lines.
///
/// The rule every entry below obeys: additive and nullable where it can be. A
/// new table, or a column nobody is forced to fill in. Nothing rewrites a
/// person's records on the way up, because a migration that can lose data is a
/// migration that can lose data.
class Schema {
  const Schema._();

  /// What this build writes.
  static const int version = 12;

  /// A database being created at [version].
  ///
  /// Runs every step from the start, in order, rather than only the last: a
  /// fresh install and an upgrade must end up with exactly the same shape, and
  /// building the current version directly would be the one way of finding out
  /// that they do not.
  static Future<void> create(Database d, int version) async {
    await _createV1(d);
    if (version >= 2) await _migrateToV2(d);
    if (version >= 3) await _migrateToV3(d);
    if (version >= 4) await _migrateToV4(d);
    if (version >= 5) await _migrateToV5(d);
    if (version >= 6) await _migrateToV6(d);
    if (version >= 7) await _migrateToV7(d);
    if (version >= 8) await _migrateToV8(d);
    if (version >= 9) await _migrateToV9(d);
    if (version >= 10) await _migrateToV10(d);
    if (version >= 11) await _migrateToV11(d);
    if (version >= 12) await _migrateToV12(d);
  }

  /// A database that already existed, opened at a higher [to].
  ///
  /// Every step between [from] and now, and nothing outside it: a migration that
  /// runs against a shape it did not create is the most likely way to corrupt
  /// somebody's data, and the cheapest thing in the world to prevent.
  static Future<void> upgrade(Database d, int from, int to) async {
    if (from < 2) await _migrateToV2(d);
    if (from < 3) await _migrateToV3(d);
    if (from < 4) await _migrateToV4(d);
    if (from < 5) await _migrateToV5(d);
    if (from < 6) await _migrateToV6(d);
    if (from < 7) await _migrateToV7(d);
    if (from < 8) await _migrateToV8(d);
    if (from < 9) await _migrateToV9(d);
    if (from < 10) await _migrateToV10(d);
    if (from < 11) await _migrateToV11(d);
    if (from < 12) await _migrateToV12(d);
  }

  /// Every stored engine becomes the one that is left.
  ///
  /// The on-device engine is gone — the bundled 1.7B model took the APK from
  /// 16 MB to 258 MB and was the direct cause of every complaint about the
  /// assistant — so an install still holding `'onDevice'` names something this
  /// build cannot run. It is rewritten here rather than only guarded at the read,
  /// so the value is healed once, on the device, and every later read (the app
  /// bar, the switcher, a backup) sees an engine that exists instead of each of
  /// them remembering a fallback. `KoruEngine.parse` heals it again at the read
  /// for the cases the migration cannot: a value written by a later build, or a
  /// profile row that was truncated.
  ///
  /// `'cloud'` is the only value this build accepts, so the one statement covers
  /// `'onDevice'`, the older `'builtIn'`, and anything this build has never heard
  /// of. One statement, no read-modify-write, and no way for it to fail on real
  /// data: the profile table has existed since v1 and value is NOT NULL, so the
  /// worst case is a row that does not match and nothing happens.
  ///
  /// It deliberately does *not* decide whether a key exists. A key lives in the
  /// Android keystore, not in this database, so SQL cannot see it and must not
  /// guess: after this runs, a person with no key is in the honest
  /// nothing-connected state, which the app bar, the switcher and the reply card
  /// all say out loud and offer to fix.
  static Future<void> _migrateToV12(Database d) async {
    await d.execute(
      "UPDATE profile SET value = 'cloud' WHERE key = 'engine' AND value <> 'cloud'",
    );
  }

  /// Things to do, as a list in their own right.
  ///
  /// Added because the app had a great deal of date-shaped data — deadlines,
  /// calendar entries, payments, projects — and nowhere to put "call the
  /// plumber". Every one of those needs a client or a date to be reachable
  /// through, which means the ordinary work of a week, the kind with no client
  /// and no deadline, had nowhere at all to live. That is most of what a person
  /// is asked to do on a day, and a helper whose only lists are other people's
  /// invoices reads as empty however much money is on file.
  ///
  /// Additive and fully nullable, so there is nothing here that can fail on
  /// somebody's real data: a new table, three indexes, no column touched, no
  /// row rewritten. Existing installs open exactly as they were and gain an
  /// empty list.
  ///
  /// The indexes are for the three questions the app now asks constantly: what
  /// is open, what belongs to this project, and what belongs to this client.
  /// Without them each of those is a scan of the whole list and a sort, on the
  /// screen the user opens every morning.
  static Future<void> _migrateToV11(Database d) async {
    await d.execute('''
      CREATE TABLE IF NOT EXISTS tasks(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        client_id INTEGER,
        project_id INTEGER,
        due TEXT,
        priority TEXT NOT NULL DEFAULT 'normal',
        done INTEGER NOT NULL DEFAULT 0,
        completed_at TEXT,
        note TEXT,
        created TEXT NOT NULL
      )
    ''');
    await d.execute(
        'CREATE INDEX IF NOT EXISTS idx_tasks_open ON tasks(done, priority, due)');
    await d.execute(
        'CREATE INDEX IF NOT EXISTS idx_tasks_project ON tasks(project_id)');
    await d.execute(
        'CREATE INDEX IF NOT EXISTS idx_tasks_client ON tasks(client_id)');
  }

  /// A stored engine this build no longer has becomes the one that ships.
  ///
  /// The built-in engine is gone, and every install that had it selected still
  /// has the literal string `'builtIn'` in the profile table. Rewriting it here
  /// rather than only guarding the read is deliberate: the value is healed once,
  /// on the device, so every later read — the app bar, the switcher, a backup —
  /// sees an engine that exists instead of depending on each of them to remember
  /// a fallback.
  ///
  /// An engine this build has never heard of is treated the same way. It can only
  /// come from a downgrade, a restored backup or a truncated row, and all three
  /// land on a phone where answering something is better than answering nothing.
  ///
  /// One statement, no read-modify-write, and no way for it to fail on real data:
  /// the profile table has existed since v1 and value is NOT NULL, so the worst
  /// case is a row that does not match and nothing happens.
  ///
  /// Superseded by [_migrateToV12], which is the same sentence with one engine
  /// left instead of two. It is kept because a migration runs once per person and
  /// is never revisited: an install going from v9 today runs this and then v12,
  /// and deleting a step an existing phone has not taken yet is how a database
  /// stops opening.
  static Future<void> _migrateToV10(Database d) async {
    await d.execute(
      "UPDATE profile SET value = 'onDevice' "
      "WHERE key = 'engine' AND value NOT IN ('onDevice', 'cloud')",
    );
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
}
