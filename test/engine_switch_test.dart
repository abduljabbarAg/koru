import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koru/engine.dart';
import 'package:koru/local/bundled_engine.dart';
import 'package:koru/local/local_model_client.dart';
import 'package:koru/screens/chat.dart';
import 'package:koru/secrets.dart';
import 'package:koru/state.dart';
import 'package:koru/store.dart';
import 'package:koru/theme.dart';
import 'package:koru/widgets.dart';

import 'test_store.dart';

/// An engine that reports what it was asked to do instead of launching one.
///
/// The complaint this file is written against was a choice that did nothing
/// until somebody went and found a Settings screen, so the thing under test is
/// whether choosing starts anything. That cannot be shown against the real
/// engine, which execs a 450 KB binary that is not in a test process.
class _FakeEngine extends BundledEngine {
  _FakeEngine({
    this.catalog = const [
      LocalModelFile(
        label: 'Bonsai-1.7B-Q1_0 (bundled)',
        path: '/data/models/Bonsai-1.7B-Q1_0.gguf',
      ),
      LocalModelFile(
        label: 'Qwen3-4B-Q4_K_M (3900 MB)',
        path: '/sdcard/Android/data/koru/files/models/Qwen3.gguf',
      ),
    ],
    this.failWith,
  });

  final List<LocalModelFile> catalog;

  /// When set, the start fails with this rather than coming up.
  final String? failWith;

  /// How many times something tried to start it.
  int starts = 0;

  /// The model it was pointed at, null being the bundled default.
  String? startedOn;

  final _held = Completer<void>();

  /// Releases a start that was reported progress first.
  void letFinish() {
    if (!_held.isCompleted) _held.complete();
  }

  @override
  Future<bool> get available async => true;

  @override
  Future<List<LocalModelFile>> models() async => catalog;

  @override
  Future<BundledStartResult> start({
    int port = BundledEngine.defaultPort,
    String? modelPath,
    Duration timeout = const Duration(seconds: 180),
    Future<bool> Function() isHealthy = _neverHealthy,
    void Function(int percent)? onProgress,
  }) async {
    starts++;
    startedOn = modelPath;
    onProgress?.call(0);
    // Reported before the wait, which is the whole shape of a cold start: a
    // number moves, then the engine answers some time later.
    onProgress?.call(42);
    await _held.future;
    final problem = failWith;
    if (problem != null) return BundledStartResult.failed(problem);
    return BundledStartResult.ready('http://127.0.0.1:$port');
  }

  static Future<bool> _neverHealthy() async => false;
}

/// A client that answers instantly, so a question is about routing and not about
/// waiting on a phone.
class _FakeClient extends LocalModelClient {
  const _FakeClient({this.serving = false});

  /// Whether something is already on the loopback port.
  final bool serving;

  @override
  Future<LocalModelResult> check(String endpoint) async => serving
      ? const LocalReply('something answered', null)
      : const LocalUnavailable('No local model server answered on that address.');

  @override
  Future<LocalModelResult> chatStream({
    required String endpoint,
    required String model,
    required String system,
    required String question,
    required void Function(String delta) onToken,
    void Function(int done, int total)? onProgress,
    List<({String role, String content})> history = const [],
    int maxTokens = 160,
    double temperature = 0.7,
  }) async {
    onToken('Bilal owes 2000.');
    return const LocalReply('Bilal owes 2000.', 3.4);
  }
}

void main() {
  late ProfileStore store;

  setUpAll(initTestDatabase);

  setUp(() async {
    store = await openTestStore();
  });

  Future<void> pump(WidgetTester tester, {int frames = 8}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  /// The chat, with the two seams that would otherwise need a real phone: the
  /// engine that gets started, and the server it is started against.
  Future<void> mountChat(
    WidgetTester tester, {
    required _FakeEngine engine,
    _FakeClient client = const _FakeClient(),
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storeProvider.overrideWith((ref) async => store),
          cloudKeyProvider.overrideWith((ref, providerId) async => ''),
          secretsProvider.overrideWithValue(MemoryKeyStore()),
          bundledEngineProvider.overrideWithValue(engine),
          localModelClientProvider.overrideWithValue(client),
        ],
        child: MaterialApp(theme: buildKoruTheme(), home: const ChatScreen()),
      ),
    );
    await pump(tester);
  }

  /// Taps a row in the open sheet, scrolling it into view first.
  ///
  /// The provider list is twenty rows in a 600 pixel test window, so anything
  /// past the first few has to be dragged to before it can be hit. That is the
  /// same thing a person does, which is why it is done here rather than by
  /// reaching into the state.
  Future<void> tapInSheet(WidgetTester tester, String label) async {
    // Scoped to a tile where there is one. The app bar names the provider and
    // the model as its detail line, so the same words can be on screen twice
    // and a plain text finder would land on whichever came first.
    final tile = find.widgetWithText(KoruSelectableTile, label);
    final row = tile.evaluate().isNotEmpty ? tile : find.text(label);
    for (var i = 0; i < 12 && row.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(SingleChildScrollView).last, const Offset(0, -220));
      await pump(tester, frames: 1);
    }
    await tester.ensureVisible(row);
    await pump(tester, frames: 1);
    await tester.tap(row);
  }

  group('the engine control in the app bar', () {
    testWidgets('opens the switcher, and all three engines are in it',
        (tester) async {
      await tester.runAsync(store.completeOnboarding);
      final engine = _FakeEngine();
      await mountChat(tester, engine: engine);

      await tester.tap(find.byType(KoruEngineBarButton).first);
      await pump(tester);

      expect(find.text('Who answers'), findsOneWidget);
      for (final option in KoruEngine.values) {
        expect(find.text(option.label), findsOneWidget,
            reason: '${option.label} is offered without leaving the chat');
        // Each row says what it costs, because the built-in engine is not a
        // model and picking it by accident should not look like a downgrade
        // somebody hid.
        expect(find.text(option.blurb), findsOneWidget);
      }
    });

    testWidgets('switching writes the engine and the app bar says so afterwards',
        (tester) async {
      await tester.runAsync(store.completeOnboarding);
      await mountChat(tester, engine: _FakeEngine());

      await tester.tap(find.byType(KoruEngineBarButton).first);
      await pump(tester);
      await tapInSheet(tester, 'Online model');
      await pump(tester);
      await tapInSheet(tester, 'OpenRouter');
      await pump(tester);

      expect(await tester.runAsync(() => store.get('engine')), 'cloud');
      expect(find.text('ONLINE MODEL'), findsOneWidget,
          reason: 'the app bar follows the store, so the two cannot disagree');
      // The provider chosen on the way through is kept too: choosing the
      // engine and choosing who answers it are two different decisions.
      expect(
        await tester.runAsync(() => store.get('cloud_provider')),
        'openrouter',
      );
    });

    testWidgets('the cloud list only appears for cloud, and the models only for '
        'on-device', (tester) async {
      await tester.runAsync(store.completeOnboarding);
      await mountChat(tester, engine: _FakeEngine());

      await tester.tap(find.byType(KoruEngineBarButton).first);
      await pump(tester);

      // Counted inside the tiles rather than by text alone: the app bar now
      // carries the provider and the model name as its detail line, so the same
      // words can legitimately be on screen twice — once as what is answering and
      // once as what is being offered.
      Finder provider(String name) => find.widgetWithText(KoruSelectableTile, name);
      Finder model(String name) => find.widgetWithText(KoruSelectableTile, name);

      // Neither sub-picker is offered before the engine is chosen. Both were
      // reachable from the same row at one point, which made "where am I" the
      // first question the sheet had to answer.
      expect(provider('OpenRouter'), findsNothing);
      expect(model('Bonsai-1.7B-Q1_0 (bundled)'), findsNothing);

      await tapInSheet(tester, 'Online model');
      await pump(tester);
      expect(provider('OpenRouter'), findsOneWidget);
      expect(model('Bonsai-1.7B-Q1_0 (bundled)'), findsNothing);

      await tapInSheet(tester, 'All three');
      await pump(tester);
      await tapInSheet(tester, 'On this phone');
      await pump(tester);

      // Choosing it starts the bundled model straight away, so what is on the
      // sheet is the wait rather than a list of models to pick from.
      expect(model('Bonsai-1.7B-Q1_0 (bundled)'), findsNothing);
      expect(provider('OpenRouter'), findsNothing);
      await tapInSheet(tester, 'See the models');
      await pump(tester);
      expect(model('Bonsai-1.7B-Q1_0 (bundled)'), findsOneWidget);
      expect(model('Qwen3-4B-Q4_K_M (3900 MB)'), findsOneWidget);
      expect(provider('OpenRouter'), findsNothing);
    });

    testWidgets('choosing on-device starts the engine there and then',
        (tester) async {
      await tester.runAsync(store.completeOnboarding);
      final engine = _FakeEngine();
      await mountChat(tester, engine: engine);
      expect(engine.starts, 0, reason: 'nothing has asked for it yet');

      await tester.tap(find.byType(KoruEngineBarButton).first);
      await pump(tester);
      await tapInSheet(tester, 'On this phone');
      await pump(tester);

      // The sheet is still up, reporting the start rather than closing and
      // leaving the person to wonder whether anything happened. One tap, no
      // Settings visit, no separate bundling step.
      expect(engine.starts, 1);
      expect(find.text('Starting the model on this phone'), findsOneWidget);
      expect(find.text('Waking the server up  42%'), findsOneWidget);
      expect(find.text('THIS PHONE  42%'), findsOneWidget,
          reason: 'the app bar behind it says the same thing, not that a model '
              'is already running');

      engine.letFinish();
      await pump(tester);

      expect(engine.starts, 1, reason: 'choosing the engine started it');
      expect(await tester.runAsync(() => store.get('engine')), 'onDevice');
      expect(find.text('Running on this phone'), findsOneWidget);
      expect(find.text('MODEL ON THIS PHONE'), findsOneWidget,
          reason: 'and now that it is up, the app bar can say so');
    });

    testWidgets('a model the person brought is started in preference to the '
        'bundled one', (tester) async {
      await tester.runAsync(store.completeOnboarding);
      final engine = _FakeEngine();
      await mountChat(tester, engine: engine);

      await tester.tap(find.byType(KoruEngineBarButton).first);
      await pump(tester);
      await tapInSheet(tester, 'On this phone');
      await pump(tester);
      // The bundled model is already booting; asking for another one has to
      // actually restart the engine rather than join the start in flight.
      await tapInSheet(tester, 'See the models');
      await pump(tester);
      await tapInSheet(tester, 'Qwen3-4B-Q4_K_M (3900 MB)');
      engine.letFinish();
      await pump(tester, frames: 20);

      expect(
        engine.startedOn,
        '/sdcard/Android/data/koru/files/models/Qwen3.gguf',
        reason: 'the picker is not locked to the model that shipped',
      );
      expect(
        await tester.runAsync(() => store.get('model_path')),
        '/sdcard/Android/data/koru/files/models/Qwen3.gguf',
      );
    });

    testWidgets('an engine that is already up is not started again',
        (tester) async {
      await tester.runAsync(store.completeOnboarding);
      final engine = _FakeEngine();
      await mountChat(
        tester,
        engine: engine,
        // Something is already serving on the port, as it would be after the
        // app has been open once with the on-device engine selected.
        client: const _FakeClient(serving: true),
      );

      await tester.tap(find.byType(KoruEngineBarButton).first);
      await pump(tester);
      await tapInSheet(tester, 'On this phone');
      await pump(tester);

      expect(engine.starts, 0, reason: 'there was nothing to start');
      expect(find.text('Running on this phone'), findsOneWidget);
    });

    testWidgets('a build with no model on it says so and offers to add one',
        (tester) async {
      await tester.runAsync(store.completeOnboarding);
      final engine = _FakeEngine(catalog: const []);
      await mountChat(tester, engine: engine);

      await tester.tap(find.byType(KoruEngineBarButton).first);
      await pump(tester);
      await tapInSheet(tester, 'On this phone');
      await pump(tester);

      // Nothing was launched, and the app bar does not claim a model is on
      // the phone. This is the shape of the failure that made the bundled build
      // look broken: the engine was chosen, nothing came up, and the app
      // answered anyway as if it had.
      expect(engine.starts, 0);
      expect(find.text('No model found'), findsOneWidget);
      expect(find.text('Add a model from this phone'), findsOneWidget);
      expect(find.text('THIS PHONE  NOT RUNNING'), findsOneWidget);
    });

    testWidgets('a failed start says what failed and offers another go',
        (tester) async {
      await tester.runAsync(store.completeOnboarding);
      final engine = _FakeEngine(failWith: 'exec failed for libllama-server.so');
      await mountChat(tester, engine: engine);

      await tester.tap(find.byType(KoruEngineBarButton).first);
      await pump(tester);
      await tapInSheet(tester, 'On this phone');
      await pump(tester);
      engine.letFinish();
      await pump(tester);

      // Said, not swallowed. The old behaviour fell back to the built-in
      // assistant, which answers in milliseconds and reads as a fast model.
      // In the sheet and in the banner behind it: the reason is visible from
      // wherever the person is standing.
      expect(find.textContaining('exec failed'), findsWidgets);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Running on this phone'), findsNothing);
    });
  });

  group('what the engine is called', () {
    testWidgets('a starting engine is never announced as a running one',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildKoruTheme(),
            home: const Scaffold(
              body: KoruEngineBadge(
                engine: KoruEngine.onDevice,
                starting: true,
                progress: 42,
              ),
            ),
          ),
        ),
      );

      expect(find.text('THIS PHONE  42%'), findsOneWidget);
      expect(find.text('MODEL ON THIS PHONE'), findsNothing);
    });

    testWidgets('a failed engine says so rather than naming a model',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildKoruTheme(),
            home: const Scaffold(
              body: KoruEngineBadge(engine: KoruEngine.onDevice, failed: true),
            ),
          ),
        ),
      );

      expect(find.text('THIS PHONE  NOT RUNNING'), findsOneWidget);
    });

    testWidgets('the chat says starting while the model is still being unpacked',
        (tester) async {
      await tester.runAsync(() async {
        await store.completeOnboarding();
        await store.put('engine', 'onDevice');
      });
      final engine = _FakeEngine();
      await mountChat(tester, engine: engine);

      // The launch warm-up is under way and is not finished.
      expect(find.text('THIS PHONE  42%'), findsOneWidget);
      expect(find.text('MODEL ON THIS PHONE'), findsNothing);

      engine.letFinish();
      await pump(tester);

      // Only once it has answered is it a model on this phone.
      expect(find.text('MODEL ON THIS PHONE'), findsOneWidget);
    });
  });
}