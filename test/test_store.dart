import 'dart:io';

import 'package:koru/store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Shared setup so tests run against a real SQLite database.
///
/// package:sqflite reaches for a platform plugin, which does not exist in a test
/// process, so the FFI factory is installed globally once and every store is
/// opened in a temp directory. That way the schema and the queries are really
/// executed, and the tests fail for the reasons a user would hit rather than
/// because a mock drifted from the real thing.
bool _initialised = false;

void initTestDatabase() {
  if (_initialised) return;
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  _initialised = true;
}

Future<ProfileStore> openTestStore() async {
  initTestDatabase();
  final dir = await Directory.systemTemp.createTemp('koru_test');
  return ProfileStore.open(directory: dir);
}
