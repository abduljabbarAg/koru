import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Nothing in the build ships an inference engine or a model.
///
/// This cannot assert on a built APK — there is one in a test suite — so it
/// asserts on the build's own configuration instead, which is where a 258 MB
/// package came from in the first place. The APK was large because a binary was
/// shipped in jniLibs, a 248 MB .gguf was declared as an asset, and CI had a job
/// that built and downloaded both. Each of those is checked here by name.
///
/// The second half is the one that keeps it from coming back: the Dart side has
/// to have no local model client either, or the next person to add a provider
/// picker finds a working example and reaches for it.
void main() {
  late Directory root;

  setUpAll(() => root = Directory.current);

  String read(String path) => File('${root.path}/$path').readAsStringSync();

  /// The file with its line comments removed.
  ///
  /// Used for the build files, which carry a comment saying why each of these
  /// things is now absent — and that comment is worth more than the check it
  /// would otherwise trip. What must be gone is the setting, not the note about
  /// it.
  String code(String path) => read(path)
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('//') && !line.trimLeft().startsWith('#'))
      .join('\n');

  group('the package', () {
    test('ships no model as an asset', () {
      final pubspec = read('pubspec.yaml');
      expect(pubspec, isNot(contains('assets/models')),
          reason: 'the bundled .gguf was declared here and copied into every APK');
      expect(pubspec, isNot(contains('.gguf')));
    });

    test('has no directory that only held a model', () {
      expect(
        Directory('${root.path}/assets/models').existsSync(),
        isFalse,
        reason: 'an empty models directory would be an invitation back',
      );
    });
  });

  group('the Android build', () {
    test('does not extract native libraries for the app to exec', () {
      // Legacy packaging existed only so the bundled binary landed on disk where
      // the app could run it. Nothing of ours needs to be exec'd.
      final gradle = code('android/app/build.gradle.kts');
      expect(gradle, isNot(contains('useLegacyPackaging')));
      expect(gradle, isNot(contains('libllama-server')));
    });

    test('ships no engine binary in jniLibs', () {
      final jni = Directory('${root.path}/android/app/src/main/jniLibs');
      expect(jni.existsSync(), isFalse);
    });

    test('the activity holds no engine channel and execs nothing', () {
      final activity =
          read('android/app/src/main/kotlin/com/abduljabbar/koru/MainActivity.kt');
      expect(activity, isNot(contains('koru/local_engine')));
      expect(activity, isNot(contains('llama')));
      expect(activity, isNot(contains('ProcessBuilder')));
      expect(activity, isNot(contains('.gguf')));
      // What it must still do.
      expect(activity, contains('koru/secure_key'));
    });
  });

  group('CI', () {
    test('builds no engine and downloads no model', () {
      final workflow = code('.github/workflows/apk.yml');
      expect(workflow, isNot(contains('llama')));
      expect(workflow, isNot(contains('.gguf')));
      expect(workflow, isNot(contains('setup-ndk')));
      expect(workflow, isNot(contains('build_engine_android')));
      // And it still builds and tests the app.
      expect(workflow, contains('flutter build apk'));
      expect(workflow, contains('flutter test'));
    });
  });

  group('the Dart side', () {
    test('has no local model client left to reach for', () {
      final lib = Directory('${root.path}/lib');
      final files = lib
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      expect(files, isNotEmpty);

      final banned = [
        'llama-server',
        'bundledEngine',
        'BundledEngine',
        'LocalModelClient',
        'LocalModelConfig',
        'local_model',
        'KoruEngine.onDevice',
        'koru/local_engine',
      ];
      for (final file in files) {
        final text = file.readAsStringSync();
        for (final word in banned) {
          expect(text, isNot(contains(word)),
              reason: '${file.path} still refers to $word');
        }
      }
    });

    test('has no model file picker', () {
      // file_picker itself stays — backups are picked with it — so this is about
      // what it is picked *for*.
      final settings = read('lib/screens/settings_engine.dart');
      expect(settings, isNot(contains('file_picker')));
      expect(read('lib/screens/engine_sheet.dart'), isNot(contains('file_picker')));
    });

    test('does not build the engine any more', () {
      expect(File('${root.path}/tool/build_engine_android.sh').existsSync(), isFalse);
    });
  });
}
