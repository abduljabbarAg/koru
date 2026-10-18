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
///
/// The no-isolate factory matters. `databaseFactoryFfi` runs SQLite on a
/// background isolate, and `testWidgets` executes its body inside a fake-async
/// zone that never yields to the real event loop, so every store await would
/// hang until the test timed out. Running on the same isolate keeps the work in
/// microtasks, which fake async does drain.
bool _initialised = false;

void initTestDatabase() {
  if (_initialised) return;
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  _initialised = true;
}

Future<ProfileStore> openTestStore() async {
  initTestDatabase();
  final dir = await Directory.systemTemp.createTemp('koru_test');
  return ProfileStore.open(directory: dir);
}

/// A store together with the directory holding it.
///
/// For the tests that have to close a database and open it again, which is the
/// only honest check that a row was really written rather than still sitting in
/// the connection. Everything else uses [openTestStore] and never needs this.
Future<(ProfileStore, Directory)> openTestStoreWithDirectory() async {
  initTestDatabase();
  final dir = await Directory.systemTemp.createTemp('koru_test');
  return (await ProfileStore.open(directory: dir), dir);
}
