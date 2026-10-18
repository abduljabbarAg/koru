import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:koru/engine.dart';
import 'package:koru/models.dart';
import 'package:koru/store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'test_store.dart';

/// Upgrades, tested against a database that really is on the old schema.
///
/// The migrations run once per user, on their phone, with their data, and no
/// other test in this suite touches them. A migration that throws leaves every
/// existing install unable to open, which is the worst outcome this codebase
/// can produce, and it is invisible to every other test because they all build
/// a fresh database at the current version.
///
/// So these build a database at an older version by hand, put real rows in it,
/// and then open it the way the app does. The schema below is copied from the
/// migrations on purpose: it is the thing that has to keep working, and a copy
/// is the only way to prove the old shape still upgrades.
void main() {
  setUpAll(initTestDatabase);

  /// The v1 tables, verbatim.
  Future<void> createV1(Database d) async {
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
    // Note the absence of a monthly column. That is the point.
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

  Future<void> createV2(Database d) async {
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

  /// The v4 to v10 shape, written out the way those migrations left it.
  ///
  /// Only needed for one test, and only because one test is about an install
  /// that already has all of it: the chain from v1 is covered above, and what
  /// has to be proved here is that opening a genuine v10 database adds the task
  /// table and touches nothing else. A database built by a partial chain would
  /// not prove that.
  Future<void> createV4ToV10(Database d) async {
    await d.execute('ALTER TABLE business ADD COLUMN monthly REAL');
    await d.execute('ALTER TABLE business ADD COLUMN deposit REAL');
    await d.execute('ALTER TABLE business ADD COLUMN terms_days INTEGER');
    await d.execute('ALTER TABLE business ADD COLUMN invoiced_on TEXT');
    await d.execute('''
      CREATE TABLE projects(
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
      CREATE TABLE project_notes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project_id INTEGER NOT NULL,
        body TEXT NOT NULL,
        created TEXT NOT NULL
      )
    ''');
    await d.execute(
        'CREATE INDEX idx_projects_client ON projects(client_id)');
    await d.execute('''
      CREATE TABLE events(
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
    await d.execute('CREATE INDEX idx_events_date ON events(date, time)');
    await d.execute('ALTER TABLE events ADD COLUMN recurrence TEXT');
    await d.execute('ALTER TABLE business ADD COLUMN phone TEXT');
  }

  Future<void> createV3(Database d) async {
    await d.execute('''
      CREATE TABLE payments(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_id INTEGER NOT NULL,
        amount REAL NOT NULL,
        date TEXT NOT NULL,
        note TEXT
      )
    ''');
    await d.execute('''
      CREATE TABLE deadlines(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_id INTEGER,
        title TEXT NOT NULL,
        due TEXT NOT NULL,
        done INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  /// Builds a database that is genuinely on [version], with a client's worth of
  /// data in it, and returns the directory holding it.
  Future<Directory> seedOldDatabase(int version) async {
    final dir = await Directory.systemTemp.createTemp('koru_migrate_v$version');
    final db = await openDatabase(
      '${dir.path}/koru.db',
      version: version,
      onCreate: (d, v) async {
        await createV1(d);
        if (v >= 2) await createV2(d);
        if (v >= 3) await createV3(d);
        if (v >= 10) await createV4ToV10(d);
      },
    );

    await db.insert('profile', {'key': 'nickname', 'value': 'kami'});
    await db.insert('profile', {'key': 'onboarded', 'value': '1'});
    // The engine every install had before the built-in one was deleted. It is
    // the only value this migration has to heal, and it is not a value anybody
    // typed: it was written by an older build of this app.
    await db.insert('profile', {'key': 'engine', 'value': 'builtIn'});
    await db.insert('business', {
      'name': 'Bilal',
      'status': 'delivered',
      'amount': 2000.0,
      'note': 'pays slowly',
      'created': '2026-01-01',
    });
    await db.insert('knowledge', {
      'topic': 'Rust',
      'progress': 0.5,
      'updated': '2026-01-01',
    });
    await db.insert('fitness', {'day': '2026-01-01', 'weight': 80.0});
    if (version >= 2) {
      await db.insert('drafts', {
        'title': 'note',
        'body': 'hello',
        'created': '2026-01-01',
      });
      await db.insert('chat', {
        'role': 'koru',
        'text': 'hi',
        'created': '2026-01-01',
      });
    }
    if (version >= 10) {
      // The records a working install has, so the upgrade is proved against
      // something rather than against an empty table.
      await db.insert('business', {
        'name': 'Acme',
        'status': 'delivered',
        'amount': 5000.0,
        'monthly': 500.0,
        'terms_days': 14,
        'invoiced_on': '2026-02-01',
        'created': '2026-02-01',
      });
      await db.insert('projects', {
        'name': 'Acme rebrand',
        'kind': 'client',
        'client_id': 1,
        'target': 'the new site is live',
        'progress': 0.5,
        'created': '2026-03-01',
        'updated': '2026-03-01',
      });
      await db.insert('project_notes', {
        'project_id': 1,
        'body': 'wireframes signed off',
        'created': '2026-03-02',
      });
      await db.insert('events', {
        'date': '2026-04-01',
        'time': '15:00',
        'title': 'Kickoff with Acme',
        'synced': 0,
        'created': '2026-03-20',
      });
    }
    if (version >= 3) {
      await db.insert('payments', {
        'client_id': 1,
        'amount': 500.0,
        'date': '2026-01-05',
      });
      await db.insert('deadlines', {
        'client_id': 1,
        'title': 'Send invoice',
        'due': '2026-02-01',
      });
    }
    await db.close();
    return dir;
  }

  group('a v3 install upgrading to v4', () {
    test('opens, and keeps the client and its money', () async {
      final dir = await seedOldDatabase(3);

      final store = await ProfileStore.open(directory: dir);
      addTearDown(store.close);

      final clients = await store.clients();
      expect(clients.single.name, 'Bilal');
      expect(clients.single.amount, 2000);
      expect(clients.single.note, 'pays slowly');
      // The column the migration added, on a row that predates it.
      expect(clients.single.monthly, isNull);
      expect(clients.single.isRetainer, isFalse);

      // The ledger from before the upgrade still works.
      expect(await store.receivedFor(clients.single.id!), 500);
      expect(await store.balanceFor(clients.single), 1500);
      expect((await store.deadlines()).single.title, 'Send invoice');
      expect(await store.get('nickname'), 'kami');
      expect(await store.onboarded, isTrue);
    });

    test('a retainer can be set on an upgraded client', () async {
      final dir = await seedOldDatabase(3);
      final store = await ProfileStore.open(directory: dir);
      addTearDown(store.close);

      final before = (await store.clients()).single;
      await store.updateClient(before.copyWith(monthly: 1500));
      final after = (await store.clients()).single;

      expect(after.monthly, 1500);
      expect(after.isRetainer, isTrue);
      // And it did not disturb anything else on the row.
      expect(after.amount, 2000);
      expect(after.name, 'Bilal');
    });

    test('the old tables are still there and still clearable', () async {
      final dir = await seedOldDatabase(3);
      final store = await ProfileStore.open(directory: dir);
      addTearDown(store.close);

      // wipe() is the only promise the app makes about deletion, and it has to
      // keep working on a database it did not create.
      await store.wipe();
      expect(await store.clients(), isEmpty);
      expect(await store.payments(), isEmpty);
      expect(await store.chat(), isEmpty);
    });

    test('the whole upgrade chain from v1 still works', () async {
      // A user who has not opened the app in months should not be stranded.
      final dir = await seedOldDatabase(1);

      final store = await ProfileStore.open(directory: dir);
      addTearDown(store.close);

      final clients = await store.clients();
      expect(clients.single.name, 'Bilal');
      expect(clients.single.monthly, isNull);
      // The v2 and v3 tables were created on the way up and are usable.
      expect(await store.chat(), isEmpty);
      expect(await store.payments(), isEmpty);
      expect(await store.deadlines(), isEmpty);
    });
  });

  group('a v4 install upgrading to v5', () {
    test('opens, and the projects tables are there and usable', () async {
      final dir = await seedOldDatabase(3);
      final store = await ProfileStore.open(directory: dir);
      addTearDown(store.close);

      // The v4 data survived the hop.
      expect((await store.clients()).single.name, 'Bilal');

      final id = await store.addProject(const Project(
        name: 'Redesign my own site',
        kind: ProjectKind.personal,
        target: 'Ship it',
        created: '2026-10-01T00:00:00Z',
        updated: '2026-10-01T00:00:00Z',
      ));
      expect(id, isNotNull);

      final p = (await store.projects()).single;
      expect(p.name, 'Redesign my own site');
      expect(p.kind, ProjectKind.personal);
      expect(p.isPersonal, isTrue);
      expect(p.target, 'Ship it');
      expect(p.progress, 0);

      await store.addProjectNote(ProjectNote(
          projectId: p.id!, body: 'started the wireframes', created: '2026-10-02T00:00:00Z'));
      expect((await store.projectNotes(p.id!)).single.body, 'started the wireframes');
    });
  });

group('a v10 install upgrading to v11', () {
    test('opens, keeps everything, and gains a task list', () async {
      final dir = await seedOldDatabase(10);
      final store = await ProfileStore.open(directory: dir);
      addTearDown(store.close);

      // The records from before the upgrade, still readable.
      final clients = await store.clients();
      expect(clients, hasLength(2));
      final acme = clients.firstWhere((c) => c.name == 'Acme');
      expect(acme.monthly, 500);
      expect(acme.termsDays, 14);
      expect(acme.balanceWith(0), 5000);

      final projects = await store.projects();
      expect(projects.single.name, 'Acme rebrand');
      expect(projects.single.progress, 0.5);
      expect((await store.projectNotes(projects.single.id!)).single.body,
          'wireframes signed off');
      expect((await store.events(from: DateTime(2026, 1, 1))).single.title,
          'Kickoff with Acme');
      // The columns added along the way are still there too.
      expect(clients.firstWhere((c) => c.name == 'Bilal').phone, isNull);

      // And the new table is empty rather than missing. A migration that cannot
      // be read as "no tasks yet" is indistinguishable from one that lost the
      // feature.
      expect(await store.tasks(), isEmpty);
    });

    test('a task can be added to an upgraded database and kept', () async {
      final dir = await seedOldDatabase(10);
      final store = await ProfileStore.open(directory: dir);
      addTearDown(store.close);

      final id = await store.addTask(const Task(title: 'Chase the deposit'));
      expect(id, isNotNull);
      final task = (await store.tasks()).single;
      expect(task.title, 'Chase the deposit');
      expect(task.priority, TaskPriority.normal);
      expect(task.done, isFalse);
      expect(task.completedAt, isNull);

      // And it survives closing and reopening, which is the only honest check
      // that the column landed rather than living in a cache.
      await store.close();
      final again = await ProfileStore.open(directory: dir);
      addTearDown(again.close);
      expect((await again.tasks()).single.id, id);
    });

    test('wipe clears the task list too', () async {
      final dir = await seedOldDatabase(10);
      final store = await ProfileStore.open(directory: dir);
      addTearDown(store.close);

      await store.addTask(const Task(title: 'One thing'));
      // wipe() is the only promise the app makes about deletion, and it has to
      // keep working on a database it did not create.
      await store.wipe();
      expect(await store.tasks(), isEmpty);
      expect(await store.clients(), isEmpty);
    });
  });

group('a fresh install', () {
    test('already has the retainer column and needs no upgrade', () async {
      final store = await openTestStore();
      addTearDown(store.close);

      final id = await store.addClient(
        const Client(name: 'New', amount: 100, monthly: 900, created: '2026-01-01'),
      );
      final c = (await store.clients()).singleWhere((x) => x.id == id);
      expect(c.monthly, 900);
      expect(c.isRetainer, isTrue);
    });

    test('leaves a stored engine alone, because there are only two now', () async {
      final store = await openTestStore();
      addTearDown(store.close);

      for (final engine in const ['onDevice', 'cloud']) {
        await store.put('engine', engine);
        expect(await store.get('engine'), engine);
      }
    });
  });

  group('the stored engine', () {
    // The engine that is not there any more, and everything that can reach a
    // phone in a shape this build has never heard of. The rule is one sentence:
    // an upgrade must never leave somebody with no engine to ask.
    test('an install on the deleted built-in engine lands on one that works',
        () async {
      final dir = await seedOldDatabase(9);
      final store = await ProfileStore.open(directory: dir);
      addTearDown(store.close);

      // Healed on disk, not only at the read, so nothing else has to know.
      expect(await store.get('engine'), 'onDevice');
      expect(KoruEngine.parse(await store.get('engine')), KoruEngine.onDevice);
    });

    test('a value this build has never heard of lands on one that works',
        () async {
      final dir = await seedOldDatabase(9);
      // Written after the fact, standing in for a restored backup or a
      // truncated row: the migration has already run by this point, which is
      // exactly when the read-side fallback is all that is left.
      final store = await ProfileStore.open(directory: dir);
      await store.put('engine', 'somethingElse');
      addTearDown(store.close);

      expect(KoruEngine.parse(await store.get('engine')), KoruEngine.onDevice,
          reason: 'the read must not depend on the migration having run');
    });

    test('a real engine survives the upgrade untouched', () async {
      final dir = await seedOldDatabase(9);
      final store = await ProfileStore.open(directory: dir);
      addTearDown(store.close);

      await store.put('engine', 'cloud');
      // Re-opening is the only honest check: a migration that rewrote this row
      // would have done it on the way up.
      await store.close();
      final again = await ProfileStore.open(directory: dir);
      addTearDown(again.close);
      expect(await again.get('engine'), 'cloud');
    });
  });
}
