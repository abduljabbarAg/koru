import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koru/cloud.dart';
import 'package:koru/cloud_providers.dart';
import 'package:koru/engine.dart';
import 'package:koru/screens/chat.dart';
import 'package:koru/secrets.dart';
import 'package:koru/state.dart';
import 'package:koru/store.dart';
import 'package:koru/theme.dart';
import 'package:koru/widgets.dart';

import 'fake_cloud.dart';
import 'test_store.dart';

/// The switcher sheet, and what it can still be used for.
///
/// There is no engine to choose any more, so the sheet has exactly one job left:
/// say whether anything is connected, and change which company answers. Every
/// test here is about that claim, because a list of companies with nothing
/// ticked and no explanation is how somebody concludes a model is connected when
/// it is not.
void main() {
  late ProfileStore store;

  setUpAll(initTestDatabase);

  setUp(() async {
    store = await openTestStore();
    await store.completeOnboarding();
  });

  Future<void> pump(WidgetTester tester, {int frames = 8}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  /// The chat on its own, with the model and the keystore replaced.
  Future<void> mountChat(WidgetTester tester, {String key = 'test-key'}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storeProvider.overrideWith((ref) async => store),
          secretsProvider.overrideWithValue(TestKeyStore(key: key)),
          cloudModelProvider.overrideWithValue(TestCloudModel()),
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
    final row = find.widgetWithText(KoruSelectableTile, label);
    for (var i = 0; i < 12 && row.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(SingleChildScrollView).last, const Offset(0, -220));
      await pump(tester, frames: 1);
    }
    await tester.ensureVisible(row);
    await pump(tester, frames: 1);
    await tester.tap(row);
  }

  Finder tickIn(String label) => find.descendant(
        of: find.widgetWithText(KoruSelectableTile, label),
        matching: find.byIcon(Icons.check_circle_rounded),
      );

  group('the engine control in the app bar', () {
    testWidgets('says plainly that nothing is connected, on a fresh install',
        (tester) async {
      await mountChat(tester, key: '');

      // Not "CLOUD MODEL" over a chat that will refuse to answer. That
      // contradiction is the whole reason this control reads the link.
      expect(find.text('No model connected'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_rounded), findsWidgets);
    });

    testWidgets('names the company once a key is saved', (tester) async {
      await mountChat(tester);

      expect(find.text('OpenRouter'), findsOneWidget);
      expect(find.text('No model connected'), findsNothing);
      // The model underneath, as the second line of the control.
      expect(find.byType(KoruEngineBarButton), findsOneWidget);
    });

    testWidgets('opens the switcher, which says what is missing',
        (tester) async {
      await mountChat(tester, key: '');
      await tester.tap(find.byType(KoruEngineBarButton).first);
      await pump(tester);

      expect(find.text('Who answers'), findsOneWidget);
      expect(find.text('Nothing is connected'), findsOneWidget);
      // And offers the one thing that fixes it.
      expect(find.text('Add a key'), findsOneWidget);
    });

    testWidgets('says connected, rather than nothing, once there is a key',
        (tester) async {
      await mountChat(tester);
      await tester.tap(find.byType(KoruEngineBarButton).first);
      await pump(tester);

      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('Nothing is connected'), findsNothing);
      // No "connect" button on a screen where there is something to connect.
      expect(find.text('Add a key'), findsNothing);
    });

    testWidgets('the chosen company is marked without relying on colour',
        (tester) async {
      await mountChat(tester);
      await tester.tap(find.byType(KoruEngineBarButton).first);
      await pump(tester);

      expect(tickIn('OpenRouter'), findsOneWidget);
      expect(tickIn('Groq'), findsNothing);
    });

    testWidgets('offers every provider, and no engines', (tester) async {
      await mountChat(tester);
      await tester.tap(find.byType(KoruEngineBarButton).first);
      await pump(tester);

      for (final provider in kCloudProviders) {
        expect(
          find.widgetWithText(KoruSelectableTile, provider.label),
          findsWidgets,
          reason: '${provider.label} is offered without leaving the chat',
        );
      }
      // The rows that used to be here. Nothing in the app may offer either of
      // them, and a test that walks the list is the only place that is checked.
      expect(find.text('Local model'), findsNothing);
      expect(find.text('Cloud model'), findsNothing);
    });

    testWidgets('choosing a company writes it, and the bar follows',
        (tester) async {
      await mountChat(tester);
      await tester.tap(find.byType(KoruEngineBarButton).first);
      await pump(tester);
      await tapInSheet(tester, 'Groq');
      await pump(tester);

      expect(await tester.runAsync(() => store.get('cloud_provider')), 'groq');
    });
  });

  group('the not-connected state is honest', () {
    testWidgets('a question with nothing connected refuses, and says why',
        (tester) async {
      await mountChat(tester, key: '');
      await tester.enterText(find.byType(TextField), 'who owes me money?');
      await tester.tap(find.byTooltip('Send'));
      await pump(tester, frames: 12);

      expect(find.textContaining('cannot answer'), findsWidgets);
      expect(find.text('Connect a cloud model'), findsOneWidget);
      // Nothing claims a model produced this sentence. The badge is null on the
      // reply, so there is no "CLOUD MODEL" mark under an answer no model wrote.
      expect(
        find.descendant(
          of: find.byType(KoruEngineBadge),
          matching: find.text('CLOUD MODEL'),
        ),
        findsNothing,
      );
    });

    testWidgets('a company with no key is named, so the fix is obvious',
        (tester) async {
      await tester.runAsync(() => store.put('cloud_provider', 'groq'));
      await mountChat(tester, key: '');
      await tester.enterText(find.byType(TextField), 'who owes me money?');
      await tester.tap(find.byTooltip('Send'));
      await pump(tester, frames: 12);

      expect(find.textContaining('Groq'), findsWidgets);
      expect(find.text('Add a cloud key'), findsOneWidget);
    });
  });

  group('what the engine is called', () {
    testWidgets('a reply a model wrote is named, and the label opens nothing',
        (tester) async {
      await mountChat(tester);
      await tester.enterText(find.byType(TextField), 'who owes me money?');
      await tester.tap(find.byTooltip('Send'));
      await pump(tester, frames: 12);

      final badge = find.byType(KoruEngineBadge);
      expect(badge, findsWidgets);
      // Scoped to the badge: the app bar above it names the same company, so a
      // bare text finder would match twice and prove nothing about the reply.
      expect(
        find.descendant(of: badge, matching: find.text('CLOUD MODEL')),
        findsOneWidget,
        reason: 'a model really did answer, so the reply says which one',
      );

      // And it is not a control: tapping it must not open the switcher, which is
      // the thing that was wrong with it.
      await tester.tap(badge.first);
      await pump(tester);
      expect(find.text('Who answers'), findsNothing);
    });

    testWidgets('a reply the app built carries no engine label at all',
        (tester) async {
      await mountChat(tester);
      await tester.enterText(find.byType(TextField), 'add client Bilal for 2000');
      await tester.tap(find.byTooltip('Send'));
      await pump(tester, frames: 12);

      expect(find.byType(WriteCard), findsOneWidget);
      // The card is built by the app, so naming a model on the message above it
      // would be the one claim this app is not allowed to make.
      expect(find.byType(KoruEngineBadge), findsNothing);
    });

    testWidgets('the bar control fits on the narrowest phone this runs on',
        (tester) async {
      // The control lives next to the wordmark and the clear button, so a long
      // company name is the thing that would push the bar off the edge. Checked
      // at the width of a small phone rather than at the test default of 800.
      tester.view.physicalSize = const Size(320, 568) * 3;
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await mountChat(tester);

      final handle = tester.ensureSemantics();
      expect(find.byType(KoruEngineBarButton), findsOneWidget);
      expect(tester.takeException(), isNull);
      handle.dispose();
    });
  });

  group('the engine is one value', () {
    test('nothing offers a choice that cannot be honoured', () {
      expect(KoruEngine.values, hasLength(1));
      expect(KoruEngine.parse('onDevice'), KoruEngine.cloud);
    });
  });

  // The two things about the sheet's appearance that were wrong and are not
  // tested anywhere else: it is a surface of its own, and the chosen row is
  // marked by more than a tint.
  for (final brightness in [Brightness.light, Brightness.dark]) {
    final name = brightness == Brightness.dark ? 'in the dark' : 'in the light';

    testWidgets('the sheet is a surface of its own $name', (tester) async {
      KoruColors.setBrightness(brightness);
      addTearDown(() => KoruColors.setBrightness(Brightness.light));

      await mountChat(tester);
      await tester.tap(find.byType(KoruEngineBarButton).first);
      await pump(tester);

      // The sheet's own box, not the page behind it. Painted by KoruSheetBody, so
      // every sheet in the app gets it whether or not its caller remembered.
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

    testWidgets('the chosen company is marked without relying on tint $name',
        (tester) async {
      KoruColors.setBrightness(brightness);
      addTearDown(() => KoruColors.setBrightness(Brightness.light));

      await mountChat(tester);
      await tester.tap(find.byType(KoruEngineBarButton).first);
      await pump(tester);

      BoxDecoration tileOf(String label) => tester
          .widget<AnimatedContainer>(
            find
                .descendant(
                  of: find.widgetWithText(KoruSelectableTile, label),
                  matching: find.byType(AnimatedContainer),
                )
                .first,
          )
          .decoration as BoxDecoration;

      final picked = tileOf('OpenRouter');
      final other = tileOf('Groq');

      // Three differences, so no single one of them failing leaves the choice
      // unreadable: a different fill, a heavier outline, and an outline in the
      // accent rather than the hairline.
      expect(picked.color, isNot(other.color));
      expect(picked.border!.top.width, greaterThan(other.border!.top.width));
      expect(picked.border!.top.color, isNot(other.border!.top.color));

      // And the tint is a real difference on both palettes, in whichever
      // direction that palette needs: the dark sheet is the one where a chosen
      // row is the lighter of the two, so a test that pinned a direction would
      // only ever have checked one of the two.
      final delta = (picked.color!.computeLuminance() -
              other.color!.computeLuminance())
          .abs();
      expect(delta, greaterThan(0.004),
          reason: 'the fill is carrying part of the mark on this palette');
    });
  }
}