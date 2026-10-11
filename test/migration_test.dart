import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
      },
    );

    await db.insert('profile', {'key': 'nickname', 'value': 'kami'});
    await db.insert('profile', {'key': 'onboarded', 'value': '1'});
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
  });
}
