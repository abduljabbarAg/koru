import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koru/models.dart';
import 'package:koru/screens/chat.dart';
import 'package:koru/secrets.dart';
import 'package:koru/state.dart';
import 'package:koru/store.dart';
import 'package:koru/theme.dart';
import 'package:koru/widgets.dart';

import 'test_store.dart';

/// Everything the model is supposed to be able to do to the business.
///
/// The audit behind this file: the write path is a parser and a resolver that
/// run before either engine is chosen, so a capability is either available to
/// both or to neither, and "the cloud model can do it" is never a separate
/// question. What that leaves to prove is whether each sentence is understood at
/// all, whether it lands as a card the person has to approve rather than a
/// silent write, and whether approving it actually changes the records.
///
/// Both engines are walked over the same table because the claim being made is
/// that both can do all of it. A case that passes on one and fails on the other
/// is the whole bug this file was written to find.
class _Case {
  const _Case(
    this.what,
    this.says, {
    required this.lands,
    this.summary,
    this.button = 'Save it',
    this.destructive = false,
  });

  /// What the capability is called in the report.
  final String what;

  /// How somebody would say it.
  final String says;

  /// Whether the records say it happened. Run after the card is approved.
  final Future<bool> Function(ProfileStore store) lands;

  /// A fragment the confirmation card has to contain, so an approval that shows
  /// the wrong thing fails rather than passing on the store alone.
  final String? summary;

  /// The button that commits it. A delete says something different on purpose.
  final String button;

  /// Whether the card has to read as destructive.
  final bool destructive;
}

void main() {
  late ProfileStore store;

  setUpAll(initTestDatabase);

  setUp(() async {
    store = await openTestStore();
    final bilal = await store.addClient(const Client(
      name: 'Bilal',
      amount: 2000,
      status: 'active',
      created: '2026-01-01',
    ));
    await store.addPayment(Payment(
      clientId: bilal,
      amount: 500,
      date: '2026-01-05',
    ));
    await store.addProject(const Project(
      name: 'the shop',
      kind: ProjectKind.personal,
      target: 'the door is open',
      progress: 0.1,
      created: '2026-01-01',
      updated: '2026-01-01',
    ));
  });

  /// Every record a write could touch, as one comparable string.
  ///
  /// Used to prove that nothing was written before the card was approved, which
  /// is the difference between a change somebody agreed to and one that
  /// happened while they were reading.
  Future<String> snapshot(ProfileStore s) async {
    final clients = (await s.clients())
        .map((c) => '${c.name}|${c.amount}|${c.due}|${c.status}|${c.note}')
        .join(',');
    final payments = (await s.payments())
        .map((p) => '${p.clientId}|${p.amount}')
        .join(',');
    final projects = (await s.projects())
        .map((p) => '${p.name}|${p.target}|${p.plan}|${p.progress}')
        .join(',');
    final notes = <String>[];
    for (final p in await s.projects()) {
      for (final n in await s.projectNotes(p.id!)) {
        notes.add('${p.name}:${n.body}');
      }
    }
    final deadlines =
        (await s.deadlines()).map((d) => '${d.title}|${d.due}').join(',');
    final events = (await s.events())
        .map((e) => '${e.title}|${e.date}|${e.time}')
        .join(',');
    return 'clients[$clients] payments[$payments] projects[$projects] '
        'notes[${notes.join(',')}] deadlines[$deadlines] events[$events]';
  }

  Future<void> boot(WidgetTester tester, String engine) async {
    await store.put('engine', engine);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storeProvider.overrideWith((ref) async => store),
          cloudKeyProvider.overrideWith((ref, providerId) async => ''),
          secretsProvider.overrideWithValue(MemoryKeyStore()),
        ],
        child: MaterialApp(theme: buildKoruTheme(), home: const ChatScreen()),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> say(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField).last, text);
    await tester.testTextInput.receiveAction(TextInputAction.send);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> pumpFrames(WidgetTester tester, {int frames = 20}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      final scrollable = find.byType(Scrollable);
      if (scrollable.evaluate().isNotEmpty) {
        await tester.scrollUntilVisible(finder, 150, scrollable: scrollable.first);
        await pumpFrames(tester, frames: 6);
      }
    }
    await tester.ensureVisible(finder);
    await pumpFrames(tester, frames: 6);
    await tester.tap(finder);
    await pumpFrames(tester, frames: 20);
  }

  final cases = <_Case>[
    _Case(
      'creates a client',
      'add client Sara for 900',
      summary: 'Sara',
      lands: (s) async =>
          (await s.clients()).any((c) => c.name == 'Sara' && c.amount == 900),
    ),
    _Case(
      'edits a client',
      'change client Bilal status to lead',
      summary: 'Bilal',
      lands: (s) async =>
          (await s.clients()).any((c) => c.name == 'Bilal' && c.status == 'lead'),
    ),
    _Case(
      'deletes a client',
      'delete client Bilal',
      summary: 'Delete Bilal',
      button: 'Delete it',
      destructive: true,
      lands: (s) async => !(await s.clients()).any((c) => c.name == 'Bilal'),
    ),
    _Case(
      'creates a project',
      'start a project called the garden for Bilal',
      summary: 'the garden',
      lands: (s) async => (await s.projects()).any((p) => p.name == 'the garden'),
    ),
    _Case(
      'edits a project',
      'change the project the shop so it is done when the roof is on',
      summary: 'Change project the shop',
      lands: (s) async =>
          (await s.projects()).any((p) => p.name == 'the shop' &&
              p.target == 'The roof is on'),
    ),
    _Case(
      'records progress on a project',
      'the shop project is now half done',
      summary: '50% along',
      lands: (s) async =>
          (await s.projects()).any((p) => p.name == 'the shop' && p.progress == 0.5),
    ),
    _Case(
      'deletes a project',
      'delete project the shop',
      summary: 'Delete project the shop',
      button: 'Delete it',
      destructive: true,
      lands: (s) async => !(await s.projects()).any((p) => p.name == 'the shop'),
    ),
    _Case(
      'records a payment',
      'Bilal paid 500',
      summary: 'from Bilal',
      lands: (s) async =>
          (await s.payments()).where((p) => p.amount == 500).length == 2,
    ),
    _Case(
      'changes an agreed amount',
      'change the amount on Bilal to 3000',
      summary: 'amount to 3000',
      lands: (s) async =>
          (await s.clients()).any((c) => c.name == 'Bilal' && c.amount == 3000),
    ),
    _Case(
      'sets a due date',
      'change client Bilal due 2026-03-01',
      summary: 'due 2026-03-01',
      lands: (s) async =>
          (await s.clients()).any((c) => c.name == 'Bilal' && c.due == '2026-03-01'),
    ),
    _Case(
      'adds a note to a client',
      'add a note to Bilal that the invoice is late',
      summary: 'the invoice is late',
      lands: (s) async =>
          (await s.clients()).any((c) => c.note == 'the invoice is late'),
    ),
    _Case(
      'adds a note to a project',
      'add a note on the shop project that the site visit went well',
      summary: 'the site visit went well',
      lands: (s) async {
        final shop = (await s.projects()).where((p) => p.name == 'the shop');
        if (shop.isEmpty) return false;
        return (await s.projectNotes(shop.first.id!))
            .any((n) => n.body.contains('site visit went well'));
      },
    ),
  ];

  for (final engine in const ['onDevice', 'cloud']) {
    group('with the $engine engine', () {
      for (final c in cases) {
        testWidgets(c.what, (tester) async {
          final before = await tester.runAsync(() => snapshot(store));

          await boot(tester, engine);
          await say(tester, c.says);

          // Understood as something to record, and offered rather than done.
          expect(find.byType(WriteCard), findsOneWidget,
              reason: '"${c.says}" must come back as a card to approve');
          expect(find.textContaining(c.summary!), findsWidgets,
              reason: 'the card has to say what it understood');

          // Nothing was written yet. This is the assertion that separates a
          // proposed write from a silent one, and it is the one that matters for
          // a delete or a changed figure.
          expect(await tester.runAsync(() => snapshot(store)), before,
              reason: 'nothing may be saved before the card is approved');

          if (c.destructive) {
            expect(find.text(c.button), findsOneWidget,
                reason: 'a delete has to be labelled as one, not as "Save it"');
            final card = tester.widget<KoruCard>(find.ancestor(
              of: find.text(c.button),
              matching: find.byType(KoruCard),
            ).first);
            expect(card.accent, KoruColors.clay,
                reason: 'and it has to look like the one action that cannot be '
                    'taken back');
          }

          await tapVisible(tester, find.text(c.button));

          expect(find.byType(WriteCard), findsNothing,
              reason: 'the card is replaced by what actually happened');
          expect(await tester.runAsync(() => c.lands(store)), isTrue,
              reason: '"${c.says}" did not land in the records');

          // And it is reported, not just done: the thread says what happened.
          expect(find.textContaining('checked'), findsWidgets,
              reason: 'the outcome has to be said, and said as checked');
        });
      }
    });
  }

  group('a question that is not a write reaches the model', () {
    testWidgets('"how much does Bilal owe" is not read as a payment',
        (tester) async {
      // The parser being eager is worse than it being silent, and this is the
      // sentence that keeps it honest.
      await boot(tester, 'onDevice');
      await say(tester, 'how much does Bilal owe');
      expect(find.byType(WriteCard), findsNothing);
    });
  });
}