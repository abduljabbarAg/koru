import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koru/local/bundled_engine.dart';

/// Bring your own model.
///
/// The bundled Bonsai is not the only thing this phone can run: a bigger model
/// dropped into the app's own folder shows up in the picker. Both cannot ship
/// in the APK — that would take every install past 600 MB to serve a choice
/// most people make once.
///
/// So the engine lists whatever models it can find and the person picks. These
/// cover the two things that can go wrong at the platform boundary: a platform
/// that answers with a list, and one that does not exist at all.
void main() {
  const engine = BundledEngine();
  const channel = MethodChannel('koru/local_engine');

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  void mock(Object? reply) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => reply);
  }

  test('lists what the platform reports, in the order given', () async {
    // Order matters and is not cosmetic: the bundled model is first on purpose,
    // and it is the default for anyone who never touches the picker.
    mock([
      {'label': 'Bonsai-1.7B-Q1_0 (bundled)', 'path': '/data/models/bonsai.gguf'},
      {'label': 'qwen3-4b-q4_k_m (3900 MB)', 'path': '/sdcard/models/qwen3.gguf'},
    ]);

    final models = await engine.models();

    expect(models, hasLength(2));
    expect(models.first.label, contains('bundled'));
    expect(models.last.path, '/sdcard/models/qwen3.gguf');
  });

  test('a platform with no models at all is an empty list', () async {
    mock(null);
    expect(await engine.models(), isEmpty);
  });

  test('rows without a usable path are dropped rather than offered', () async {
    // A row with no path would be selectable and would then point glen at
    // nothing, which is worse than not offering it.
    mock([
      {'label': 'Good', 'path': '/a.gguf'},
      {'label': 'Broken', 'path': ''},
    ]);

    final models = await engine.models();

    expect(models.map((m) => m.label), ['Good']);
  });

  test('no platform at all is reported honestly, not thrown at', () async {
    // Desktop and any test that has not mocked the channel land here. Returning
    // empty is right: a throw here would take down the Settings screen on every
    // machine without a bundled engine.
    await expectLater(engine.models(), completion(isEmpty));
  });
}