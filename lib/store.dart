import 'dart:async';

import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';

import 'packet.dart';

/// Local, encrypted-at-rest-in-practice storage.
///
/// v1 stores plain SQLite on the app's private directory, which Android already
/// isolates per-app. The encryption layer is a named later task; the schema and
/// access path are written so that swapping in SQLCipher changes only [open].
class ProfileStore {
  ProfileStore(this._db);

  final Database _db;

  static Future<ProfileStore> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final db = await openDatabase(
      '${dir.path}/koru.db',
      version: 1,
      onCreate: (d, v) async {
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
      },
    );
    return ProfileStore(db);
  }

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

  /// The only place a ContextPacket is ever constructed.
  Future<ContextPacket> packet() async {
    final m = await all();
    return ContextPacket(
      nickname: m['nickname'] ?? 'the user',
      lifeStage: m['stage'] ?? '',
      business: m['business'] ?? '',
      goals: m['goals'] ?? '',
      fitness: m['fitness_summary'] ?? '',
      focus: '',
    );
  }

  Future<bool> get onboarded async => (await get('onboarded')) == '1';

  Future<void> completeOnboarding() => put('onboarded', '1');

  Future<void> wipe() async {
    await _db.delete('profile');
    await _db.delete('fitness');
    await _db.delete('business');
    await _db.delete('knowledge');
  }

  // -- fitness
  Future<void> addFitness(FitnessEntry e) async {
    await _db.insert('fitness', e.toMap());
  }

  Future<List<FitnessEntry>> fitness({int limit = 30}) async {
    final rows = await _db.query('fitness', orderBy: 'day DESC, id DESC', limit: limit);
    return rows.map(FitnessEntry.fromMap).toList();
  }

  // -- business
  Future<void> addClient(Client c) async {
    await _db.insert('business', c.toMap());
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

  Future<void> deleteClient(int id) async {
    await _db.delete('business', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> close() => _db.close();
}

class FitnessEntry {
  final String day;
  final double? weight;
  final double? waist;
  final double? chest;
  final double? arm;
  final double? leg;
  final String? note;

  const FitnessEntry({
    required this.day,
    this.weight,
    this.waist,
    this.chest,
    this.arm,
    this.leg,
    this.note,
  });

  Map<String, Object?> toMap() => {
        'day': day,
        if (weight != null) 'weight': weight,
        if (waist != null) 'waist': waist,
        if (chest != null) 'chest': chest,
        if (arm != null) 'arm': arm,
        if (leg != null) 'leg': leg,
        if (note != null) 'note': note,
      };

  factory FitnessEntry.fromMap(Map<String, Object?> m) => FitnessEntry(
        day: m['day'] as String? ?? '',
        weight: (m['weight'] as num?)?.toDouble(),
        waist: (m['waist'] as num?)?.toDouble(),
        chest: (m['chest'] as num?)?.toDouble(),
        arm: (m['arm'] as num?)?.toDouble(),
        leg: (m['leg'] as num?)?.toDouble(),
        note: m['note'] as String?,
      );

  /// BMI needs only weight and height; height lives in the profile.
  double? bmi(double heightM) {
    final w = weight;
    if (w == null || heightM <= 0) return null;
    return w / (heightM * heightM);
  }
}

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
    required this.status,
    this.amount,
    this.due,
    this.leadSource,
    this.note,
    required this.created,
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
}