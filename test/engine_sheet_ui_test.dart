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

/// An engine that is already up, so a reply can be labelled honestly.
///
/// Without it the launch warm-up finds nothing to start, sets the "not running"
/// problem, and the badge correctly says NOT RUNNING — which is right for a real
/// phone with no model and wrong for what these tests are looking at.
class _ReadyEngine extends BundledEngine {
  const _ReadyEngine();

  /// The model is on disk, so the start does not report a copy out of the APK.
  ///
  /// Also stops the platform channel being reached: a method channel with no
  /// handler never answers inside a widget test, and a start that hangs there is
  /// indistinguishable from a slow engine.
  @override
  Future<BundledEngineStatus> status() async => const BundledEngineStatus(
        available: true,
        modelAvailable: true,
        modelBytes: BundledEngine.bundledModelBytes,
      );

  @override
  Future<bool> get available async => true;

  @override
  Future<List<LocalModelFile>> models() async => const [
        LocalModelFile(
          label: 'Bonsai-1.7B-Q1_0 (bundled)',
          path: '/data/models/Bonsai-1.7B-Q1_0.gguf',
        ),
      ];

  @override
  Future<BundledStartResult> start({
    int port = BundledEngine.defaultPort,
    String? modelPath,
    Duration timeout = const Duration(seconds: 180),
    Future<bool> Function() isHealthy = _neverHealthy,
    void Function(int percent)? onProgress,
  }) async =>
      BundledStartResult.ready('http://127.0.0.1:$port');

  static Future<bool> _neverHealthy() async => false;
}

/// A model that answers, so a reply has an engine to be labelled with.
///
/// The badge is only worth testing on a reply a model actually wrote. On a reply
/// with nothing behind it there is deliberately no label at all, which is its own
/// test above.
class _AnsweringClient extends LocalModelClient {
  const _AnsweringClient();

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
    onToken('Nobody owes you anything yet.');
    // No measured speed: the badge prefers a rate when it has one, and this test
    // is about which engine is named rather than how fast it was.
    return const LocalReply('Nobody owes you anything yet.', null);
  }
}

/// What the switcher sheet actually looks like.
///
/// Two things, neither of which anything was checking. The sheet was opened
/// with a transparent background and painted no surface of its own, so its
/// tiles were drawn straight onto the page behind it — two near-identical
/// creams on top of each other, which reads as a sheet that failed to render
/// rather than as a sheet. And a chosen row was told apart by its tint alone,
/// which is the one distinction a reader cannot make when the tint is the
/// difference between two colours they can already barely see.
void main() {
  late ProfileStore store;

  setUpAll(initTestDatabase);

  setUp(() async {
    store = await openTestStore();
    // These read the app-wide palette, not the theme, so a dark run has to set
    // it the way the app does when the system brightness changes.
    KoruColors.setBrightness(Brightness.light);
  });

  tearDown(() => KoruColors.setBrightness(Brightness.light));

  Future<void> pump(WidgetTester tester, {int frames = 8}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  /// The chat on its own, with the engine control in its bar.
  Future<void> mountChat(
    WidgetTester tester, {
    Brightness? brightness,
    LocalModelClient client = const LocalModelClient(),
  }) async {
    if (brightness != null) KoruColors.setBrightness(brightness);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storeProvider.overrideWith((ref) async => store),
          cloudKeyProvider.overrideWith((ref, providerId) async => ''),
          secretsProvider.overrideWithValue(MemoryKeyStore()),
          localModelClientProvider.overrideWithValue(client),
          bundledEngineProvider.overrideWithValue(const _ReadyEngine()),
        ],
        child: MaterialApp(
          theme: buildKoruTheme(
            brightness: brightness ?? Brightness.light,
          ),
          home: const ChatScreen(),
        ),
      ),
    );
    await pump(tester);
  }

  /// The same, with the switcher open the way the bar control opens it.
  Future<void> openSwitcher(WidgetTester tester,
      {Brightness? brightness}) async {
    await mountChat(tester, brightness: brightness);
    await tester.tap(find.byType(KoruEngineBarButton).first);
    await pump(tester);
  }

  /// The fill and the outline of one selectable row.
  BoxDecoration tileOf(WidgetTester tester, String label) =>
      tester
          .widget<AnimatedContainer>(
            find
                .descendant(
                  of: find.widgetWithText(KoruSelectableTile, label),
                  matching: find.byType(AnimatedContainer),
                )
                .first,
          )
          .decoration
          as BoxDecoration;

  Finder tickIn(String label) => find.descendant(
        of: find.widgetWithText(KoruSelectableTile, label),
        matching: find.byIcon(Icons.check_circle_rounded),
      );

  for (final brightness in [Brightness.light, Brightness.dark]) {
    final name = brightness == Brightness.dark ? 'in the dark' : 'in the light';

    testWidgets('the sheet is a surface of its own $name', (tester) async {
      await openSwitcher(tester, brightness: brightness);

      // The sheet's own box, not the page behind it. Painted by KoruSheetBody,
      // so every sheet in the app gets it whether or not its caller remembered.
      final sheet = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(KoruSheetBody),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final surface = sheet.decoration as BoxDecoration;
      expect(surface.color, KoruColors.cream);
      expect(surface.borderRadius, isNotNull);
      expect(surface.boxShadow, isNotEmpty);

      // A sheet and the page behind it are the same colour by design — the
      // palette has one page colour — so what separates them is the edge: a
      // rounded top, a hairline along it and a shadow underneath.
      expect(
        (surface.borderRadius! as BorderRadius).topLeft.x,
        KoruRadius.sheet,
      );
      expect(surface.border!.top.color, KoruColors.line);
      expect(surface.border!.top.width, 1.0);
    });

    testWidgets('the chosen engine is marked without relying on colour $name',
        (tester) async {
      // A stored engine from before the built-in one was deleted, which is what
      // an upgrading install actually holds. It must resolve to one of the two
      // rows rather than to nothing.
      await tester.runAsync(() async {
        await store.completeOnboarding();
        await store.put('engine', 'builtIn');
      });
      await openSwitcher(tester, brightness: brightness);

      final chosen = KoruEngine.parse('builtIn').label;
      final others =
          KoruEngine.values.map((e) => e.label).where((l) => l != chosen).toList();

      // A tick. This is the part that survives the colour being unreadable, or
      // switched off entirely.
      expect(tickIn(chosen), findsOneWidget);
      for (final other in others) {
        expect(tickIn(other), findsNothing);
      }

      final picked = tileOf(tester, chosen);
      for (final other in others) {
        final other_ = tileOf(tester, other);

        // A different fill, a heavier outline, and an outline in the accent
        // rather than the hairline. Three differences, so no single one of them
        // failing leaves the choice unreadable.
        expect(picked.color, isNot(other_.color));
        expect(picked.border!.top.width,
            greaterThan(other_.border!.top.width));
        expect(picked.border!.top.color, isNot(other_.border!.top.color));
      }

      // And the tint is a real difference on both palettes, in whichever
      // direction that palette needs: the dark sheet is the one where a chosen
      // row is the lighter of the two, so a test that pinned a direction would
      // only ever have checked one of the two.
      for (final other in others) {
        final delta =
            (picked.color!.computeLuminance() - tileOf(tester, other).color!.computeLuminance())
                .abs();
        expect(delta, greaterThan(0.004),
            reason: 'the fill is carrying part of the mark on this palette');
      }
    });
  }

  testWidgets('the app bar names the company when one is selected',
      (tester) async {
    await tester.runAsync(() async {
      await store.completeOnboarding();
      await store.put('engine', 'cloud');
    });
    await mountChat(tester);

    // Which company is the whole reason this is a bar control rather than a
    // pill: "CLOUD MODEL" says something is answering, "OpenRouter" says who.
    expect(find.text('CLOUD MODEL'), findsOneWidget);
    expect(find.text('OpenRouter'), findsOneWidget);
  });

  testWidgets('a reply with no engine behind it is not labelled as if it had one',
      (tester) async {
    // Cloud, with no key. The old app answered from the user's records in this
    // state and stamped the reply FROM YOUR RECORDS, which is what made a
    // missing key look like a working assistant.
    await tester.runAsync(() async {
      await store.completeOnboarding();
      await store.put('engine', 'cloud');
    });
    await mountChat(tester);

    await tester.enterText(find.byType(TextField), 'who owes me money?');
    await tester.tap(find.byTooltip('Send'));
    await pump(tester, frames: 12);

    expect(find.textContaining('cannot answer'), findsWidgets);
    expect(find.text('Add a cloud key'), findsOneWidget);
    // Nothing claims a model produced this sentence.
    expect(find.text('LOCAL MODEL'), findsNothing);
    expect(find.text('CLOUD MODEL'), findsOneWidget,
        reason: 'the bar names what is selected, and nothing answered');
  });

  testWidgets('the label on a reply opens nothing', (tester) async {
    await tester.runAsync(() async {
      await store.completeOnboarding();
      await store.put('engine', 'onDevice');
    });
    await mountChat(tester, client: const _AnsweringClient());

    await tester.enterText(find.byType(TextField), 'who owes me money?');
    await tester.tap(find.byTooltip('Send'));
    await pump(tester, frames: 12);

    final badge = find.byType(KoruEngineBadge);
    expect(badge, findsWidgets);
    // Scoped to the badge: the app bar above it names the same engine, so a
    // bare text finder would match twice and prove nothing about the reply.
    expect(
      find.descendant(of: badge, matching: find.text('LOCAL MODEL')),
      findsOneWidget,
      reason: 'a model really did answer, so the reply says which one',
    );

    // And it is not a control: tapping it must not open the switcher, which is
    // the thing that was wrong with it.
    await tester.tap(badge.first);
    await pump(tester);
    expect(find.text('Who answers'), findsNothing);
  });

  testWidgets('the bar still fits on the narrowest phone this runs on',
      (tester) async {
    // The control lives next to the wordmark and the clear button, so a long
    // model name is the thing that would push the bar off the edge. Checked at
    // the width of a small phone rather than at the test default of 800.
    tester.view.physicalSize = const Size(320, 568) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      await store.completeOnboarding();
      await store.put('engine', 'cloud');
      await store.put('model_path', '/sdcard/a-very-long-model-name-indeed.gguf');
    });
    await mountChat(tester);

    final handle = tester.ensureSemantics();
    expect(find.byType(KoruEngineBarButton), findsOneWidget);
    expect(tester.takeException(), isNull);
    handle.dispose();
  });
}
