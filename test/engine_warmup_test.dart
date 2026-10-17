import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koru/engine_launch.dart';
import 'package:koru/local/bundled_engine.dart';
import 'package:koru/local/local_model_client.dart';
import 'package:koru/main.dart';
import 'package:koru/screens/chat.dart';
import 'package:koru/secrets.dart';
import 'package:koru/state.dart';
import 'package:koru/store.dart';
import 'package:koru/theme.dart';
import 'package:koru/widgets.dart';

import 'test_store.dart';

/// The engine the app would start, standing in for llama-server on loopback.
///
/// Counts starts and stops, because the two claims this file is about are both
/// about how many of each there are: a returning user must get one start they
/// did not have to ask for, and backgrounding must not cost them a stop.
class _CountingEngine extends BundledEngine {
  _CountingEngine({this.serving = false});

  /// Whether the model is already on disk. False is the first run, and the only
  /// run where the 248 MB copy is reported.
  final bool serving;

  int starts = 0;
  int stops = 0;

  /// How many times the platform was asked what models there are, which is the
  /// call that makes it copy one out of the APK.
  int listings = 0;

  final _gate = Completer<void>();
  final _unpack = Completer<void>();

  /// Lets a held start finish, the way an engine eventually answers.
  void letFinish() {
    if (!_gate.isCompleted) _gate.complete();
  }

  /// Lets the copy of the model out of the APK finish.
  ///
  /// Held separately from the start, because the copy is what makes this the
  /// slow part: listing the models is what makes the platform materialise the
  /// bundled one, and nothing reports a percentage while it happens.
  void letUnpack() {
    if (!_unpack.isCompleted) _unpack.complete();
  }

  @override
  Future<BundledEngineStatus> status() async => BundledEngineStatus(
        available: true,
        modelAvailable: serving,
        modelBytes: BundledEngine.bundledModelBytes,
      );

  @override
  Future<List<LocalModelFile>> models() async {
    listings++;
    // The copy happens inside this call, which is why the engine asks for the
    // catalog first and the app can only report the wait as "unpacking".
    if (!serving) await _unpack.future;
    return const [
      LocalModelFile(
        label: 'Bonsai-1.7B-Q1_0 (bundled)',
        path: '/data/models/Bonsai-1.7B-Q1_0.gguf',
      ),
    ];
  }

  @override
  Future<void> stop() async {
    stops++;
    letFinish();
  }

  @override
  Future<BundledStartResult> start({
    int port = BundledEngine.defaultPort,
    String? modelPath,
    Duration timeout = const Duration(seconds: 180),
    Future<bool> Function() isHealthy = _neverHealthy,
    void Function(int percent)? onProgress,
  }) async {
    starts++;
    onProgress?.call(0);
    onProgress?.call(42);
    await _gate.future;
    return BundledStartResult.ready('http://127.0.0.1:$port');
  }

  static Future<bool> _neverHealthy() async => false;
}

/// A model that answers in one token, so what is being tested is the wait and
/// not the generation.
class _AnsweringClient extends LocalModelClient {
  const _AnsweringClient();

  @override
  Future<LocalModelResult> check(String endpoint) async =>
      const LocalUnavailable('No local model server answered on that address.');

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
    return const LocalReply('Bilal owes 2000.', 4.0);
  }
}

void main() {
  late ProfileStore store;

  setUpAll(initTestDatabase);

  setUp(() async {
    store = await openTestStore();
  });

  Future<void> pump(WidgetTester tester, {int frames = 10}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  /// The whole app, with the engine and the server it is started against
  /// replaced. Mounting [RootGate] is what makes the launch warm-up observable:
  /// it is the first thing in `initState`, so if a start has been requested by
  /// the time the first frame is up, the app did not wait for anything.
  Future<void> mountApp(
    WidgetTester tester, {
    required BundledEngine engine,
    Widget child = const RootGate(),
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storeProvider.overrideWith((ref) async => store),
          cloudKeyProvider.overrideWith((ref, providerId) async => ''),
          secretsProvider.overrideWithValue(MemoryKeyStore()),
          bundledEngineProvider.overrideWithValue(engine),
          localModelClientProvider.overrideWithValue(const _AnsweringClient()),
        ],
        child: MaterialApp(theme: buildKoruTheme(), home: child),
      ),
    );
    await tester.pump();
  }

  group('the engine is warmed at launch', () {
    testWidgets('a returning user gets a start they never asked for',
        (tester) async {
      // The complaint this exists for: "first token is too small, and this model
      // is smaller, so why is it slower". Measured on the phone, generation is
      // not the cost — streaming first token is 0.46s and the engine spawn is
      // about 3.0s — so the three seconds belong at launch, not after send.
      await tester.runAsync(store.completeOnboarding);
      await tester.runAsync(() => store.put('engine', 'onDevice'));
      final engine = _CountingEngine(serving: true);

      await mountApp(tester, engine: engine);
      await pump(tester);

      expect(engine.starts, greaterThanOrEqualTo(1),
          reason: 'the model must be coming up while the user is reading the '
              'splash, not after they press send');
    });

    testWidgets('the warm-up does not wait for onboarding to be decided',
        (tester) async {
      // The first run has nothing stored, so the engine resolves to the one
      // that needs no key and no network, and there is nothing about starting
      // it that is the person's decision. Onboarding is the one stretch of time
      // where a 248 MB copy costs the user nothing, which is why it happens
      // there and not mid-question.
      final engine = _CountingEngine();

      await mountApp(tester, engine: engine);
      await pump(tester);

      expect(await tester.runAsync(() => store.get('onboarded')), isNull);
      expect(engine.listings, greaterThanOrEqualTo(1),
          reason: 'a fresh install gets the copy while it is reading onboarding, '
              'not after the first question');
      expect(
        find.text('Unpacking the local model, 248 MB. Once, on first use.'),
        findsOneWidget,
        reason: 'and it is told that, rather than being left on a bar at zero '
            'for thirty seconds',
      );

      engine
        ..letUnpack()
        ..letFinish();
      await pump(tester, frames: 20);
      expect(engine.starts, 1,
          reason: 'one copy, one start: the warm-up is asked for once');
    });

    testWidgets('a returning user is not shown a copy that is not happening',
        (tester) async {
      // The model is already on disk, so the bar has a real percentage to show.
      // Claiming a 248 MB copy on every launch would be the same lie as never
      // claiming it.
      await tester.runAsync(store.completeOnboarding);
      final engine = _CountingEngine(serving: true);

      await mountApp(tester, engine: engine);
      await pump(tester);

      expect(find.textContaining('Unpacking the local model'), findsNothing);
      expect(find.text('Starting the local model  42%'), findsOneWidget);
    });

    testWidgets('the cloud engine is not started behind the person\'s back',
        (tester) async {
      // The one thing the warm-up must not do. Somebody who chose the cloud
      // model and has no key must not have a 248 MB local copy started for them
      // on every launch.
      await tester.runAsync(store.completeOnboarding);
      await tester.runAsync(() => store.put('engine', 'cloud'));
      final engine = _CountingEngine();

      await mountApp(tester, engine: engine);
      await pump(tester);

      expect(engine.starts, 0);
    });
  });

  group('the engine outlives the screen', () {
    testWidgets('backgrounding and navigating never stop it', (tester) async {
      // Measured on the phone: about 3.0s from process spawn to listening, plus
      // a cold prompt prefix on the first question after. A stop on the way out
      // makes the second question of every session pay all of it again, for a
      // background switch somebody made for a second and undid.
      await tester.runAsync(store.completeOnboarding);
      await tester.runAsync(() => store.put('engine', 'onDevice'));
      final engine = _CountingEngine(serving: true);

      await mountApp(tester, engine: engine);
      await pump(tester, frames: 20);
      engine.letFinish();
      await pump(tester, frames: 20);

      final afterLaunch = engine.stops;

      // Background, then back. The app in the other app, not the app dead.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await pump(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pump(tester, frames: 20);

      expect(engine.stops, afterLaunch,
          reason: 'coming back must not cost the engine; only the process '
              'going away may stop it');

      // And the ordinary navigation that used to be the risk: every tab, plus
      // opening and dismissing the engine switcher.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storeProvider.overrideWith((ref) async => store),
            cloudKeyProvider.overrideWith((ref, providerId) async => ''),
            secretsProvider.overrideWithValue(MemoryKeyStore()),
            bundledEngineProvider.overrideWithValue(engine),
            localModelClientProvider
                .overrideWithValue(const _AnsweringClient()),
          ],
          child: MaterialApp(theme: buildKoruTheme(), home: const HomeShell()),
        ),
      );
      await pump(tester, frames: 20);

      for (final tab in ['Talk', 'Business', 'Projects', 'Settings', 'Today']) {
        await tester.tap(find.text(tab));
        await pump(tester, frames: 4);
      }

      await tester.tap(find.text('Talk'));
      await pump(tester, frames: 4);
      await tester.tap(find.byType(KoruEngineBarButton).first);
      await pump(tester, frames: 4);
      await tester.tapAt(const Offset(400, 20));
      await pump(tester, frames: 8);

      expect(engine.stops, afterLaunch,
          reason: 'no ordinary navigation stops the engine either');
    });
  });

  group('a question sent before the model is up', () {
    testWidgets('streams a real answer rather than reporting a dead engine',
        (tester) async {
      // The whole point. A question sent a second after opening the app used to
      // be answered with "I cannot answer that", because the turn asked a port
      // that had nothing on it yet and never waited. Nothing was wrong with the
      // engine; it simply had not finished starting.
      await tester.runAsync(store.completeOnboarding);
      await tester.runAsync(() => store.put('engine', 'onDevice'));
      final engine = _CountingEngine(serving: true);

      await mountApp(tester, engine: engine, child: const ChatScreen());
      // The launch warm-up, asked for exactly as `main.dart` asks for it. A chat
      // screen on its own does not start the engine; launch does.
      unawaited(ProviderScope.containerOf(tester.element(find.byType(ChatScreen)))
          .read(engineWarmUpProvider.future));
      await pump(tester);
      expect(engine.starts, greaterThanOrEqualTo(1));

      await tester.enterText(find.byType(TextField), 'who owes me money?');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await pump(tester, frames: 6);

      // Still starting. The bubble must say what it is waiting for rather than
      // showing a bare spinner or, worse, an answer from nowhere.
      expect(find.text('Starting the local model'), findsWidgets,
          reason: 'the wait is named, so silence after send is not a failure');
      expect(find.textContaining('cannot answer'), findsNothing);

      engine.letFinish();
      await pump(tester, frames: 30);

      expect(find.textContaining('Bilal owes 2000'), findsWidgets,
          reason: 'a real streamed answer, from the model that was asked');
      expect(find.textContaining('cannot answer'), findsNothing);
      expect(find.byType(KoruEngineDownCard), findsNothing);
    });
  });
}