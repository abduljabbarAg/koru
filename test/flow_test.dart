import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koru/backup.dart';
import 'package:koru/local/bundled_engine.dart';
import 'package:koru/local/local_model_client.dart';
import 'package:koru/local/write_intent.dart';
import 'package:koru/models.dart';
import 'package:koru/screens/chat.dart';
import 'package:koru/secrets.dart';
import 'package:koru/state.dart';
import 'package:koru/store.dart';
import 'package:koru/widgets.dart';

import 'test_store.dart';

/// End to end across the whole app, not one layer at a time.
///
/// A test that says "addPayment writes a row" proves the SQL works. It says
/// nothing about whether a person can type a sentence into the chat, see what
/// was understood, approve it, and find it on the Business screen. These walk
/// the whole path and assert on what actually ended up in the database, because
/// that is the only place a mistake becomes a user's problem.
class _RecordingClient extends LocalModelClient {
  _RecordingClient(this.reply);

  final String reply;
  final prompts = <String>[];
  final turns = <List<({String role, String content})>>[];
  final progress = <(int, int)>[];

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
    prompts.add(system);
    turns.add(history);
    progress.addAll(const [(0, 100), (100, 100)]);
    onProgress?.call(0, 100);
    // Split into a few pieces so the streaming path is genuinely exercised
    // rather than one blob arriving at once.
    for (final piece in reply.split(' ')) {
      onToken('$piece ');
    }
    return LocalReply(reply, 4.0);
  }
}

/// The greeting, so a test can tell it apart from a real reply.
const _greetingText =
    'I am here, and I answer with the local model. Ask about your work, your '
    'money and your deadlines. I will tell you when a person should answer '
    'instead of me.';

void main() {
  late ProfileStore store;

  setUpAll(initTestDatabase);

  setUp(() async {
    store = await openTestStore();
  });

  /// Steps frames so provider futures resolve and animations settle.
  /// The chat notifier behind the on-screen app.
  ChatNotifier notifierOf(WidgetTester tester) => ProviderScope.containerOf(
        tester.element(find.byType(ChatScreen)),
      ).read(chatProvider.notifier);

  Future<void> pump(WidgetTester tester, {int frames = 8}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> boot(
    WidgetTester tester, {
    required String engine,
    LocalModelClient? model,
    BundledEngine? bundled,
  }) async {
    await store.put('engine', engine);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storeProvider.overrideWith((ref) async => store),
          cloudKeyProvider.overrideWith((ref, providerId) async => ''),
          secretsProvider.overrideWithValue(MemoryKeyStore()),
          localModelClientProvider.overrideWithValue(model ?? const LocalModelClient()),
          if (bundled != null) bundledEngineProvider.overrideWithValue(bundled),
        ],
        child: const MaterialApp(home: ChatScreen()),
      ),
    );
    await pump(tester);
  }

  /// Types into the composer and waits for the reply to settle.
  Future<void> say(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField).last, text);
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await pump(tester, frames: 20);
  }

  /// The last thing Koru said.
  ///
  /// Scoped to the message list. Walking every Text in the tree picks up the
  /// "Koru" label in the chat bar, which is the kind of test that passes for
  /// the wrong reason and then fails for a real one.
  /// "8:28 am", the shape a bubble timestamp takes.
  final clockPattern = RegExp(r'^\d{1,2}:\d{2}\s?(am|pm)$');

  String lastReply(WidgetTester tester) {
    // Scoped to the last bubble rather than to the whole list, because a reply
    // is several rendered paragraphs and the text after the answer is the next
    // question. Matching the bubble by its runtime type name is what lets this
    // stay a black-box helper while the widget itself is private.
    final bubbles = find.byWidgetPredicate(
      (w) => w.runtimeType.toString().contains('_ChatBubble'),
    );
    final bubbleScope = bubbles.evaluate().isEmpty
        ? find.byType(ListView)
        : bubbles.last;

    // A reply is a rendered Text.rich, so its plain `data` is null and a helper
    // that only reads Text.data silently returns whatever badge text happened
    // to be last.
    final rendered = tester
        .widgetList<RichText>(
          find.descendant(of: bubbleScope, matching: find.byType(RichText)),
        )
        .map((r) => r.text.toPlainText())
        .where((t) => t.trim().isNotEmpty)
        .toList();
    if (rendered.isNotEmpty) return rendered.join('\n');

    // A plain-text fallback, for a bubble that was not rendered: whatever the
    // user typed back, with the clock dropped so "no" is still findable.
    final texts = tester
        .widgetList<Text>(
          find.descendant(of: bubbleScope, matching: find.byType(Text)),
        )
        .map((t) => t.data)
        .whereType<String>()
        .where((t) => t.trim().isNotEmpty)
        .where((t) => !clockPattern.hasMatch(t.trim()))
        .toList();
    return texts.isEmpty ? '' : texts.join('\n');
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      final scrollable = find.byType(Scrollable);
      if (scrollable.evaluate().isNotEmpty) {
        await tester.scrollUntilVisible(finder, 150, scrollable: scrollable.first);
        await pump(tester);
      }
    } else {
      await tester.ensureVisible(finder);
      await pump(tester);
    }
    await tester.tap(finder);
    await pump(tester);
  }

  group('chat to database, end to end', () {
    testWidgets('a sentence creates a client that exists afterwards', (tester) async {
      await boot(tester, engine: 'onDevice');
      await say(tester, 'add client Bilal for 2000');

      // It was understood as a write, not sent to any engine.
      expect(find.textContaining('Nothing is saved until you say so'), findsOneWidget);
      expect(find.text('Save it'), findsOneWidget);

      await tapVisible(tester, find.text('Save it'));

      final clients = await tester.runAsync(() => store.clients());
      expect(clients!.single.name, 'Bilal');
      expect(clients.single.amount, 2000);
      // A client with an invoice is active work, not a bare lead.
      expect(clients.single.status, 'active');
    });

    testWidgets('discarding writes nothing at all', (tester) async {
      await boot(tester, engine: 'onDevice');
      await say(tester, 'add client Sara for 900');

      await tapVisible(tester, find.text('Discard'));

      expect(await tester.runAsync(() => store.clients()), isEmpty);
      expect(find.textContaining('not saved'), findsOneWidget);
    });

    testWidgets('a payment for an unknown client is refused, not invented',
        (tester) async {
      await boot(tester, engine: 'onDevice');
      await say(tester, 'Ghost paid 500');

      expect(find.textContaining('I do not have a client called Ghost'), findsOneWidget);
      // Crucially, no card was offered, so there is nothing to tap.
      expect(find.text('Save it'), findsNothing);
      expect(await tester.runAsync(() => store.payments()), isEmpty);
    });

    testWidgets('two clients, two payments, and a balance that adds up',
        (tester) async {
      await boot(tester, engine: 'onDevice');

      await say(tester, 'add client Bilal for 2000');
      await tapVisible(tester, find.text('Save it'));
      await say(tester, 'add client Sara for 1000');
      await tapVisible(tester, find.text('Save it'));

      await say(tester, 'Bilal paid 500');
      await tapVisible(tester, find.text('Save it'));
      await say(tester, 'Sara paid 1000');
      await tapVisible(tester, find.text('Save it'));

      final result = await tester.runAsync(() async {
        final clients = await store.clients();
        return (
          clients: clients.map((c) => '${c.name}:${c.status}').toList()..sort(),
          bilal: await store.balanceFor(clients.firstWhere((c) => c.name == 'Bilal')),
          sara: await store.balanceFor(clients.firstWhere((c) => c.name == 'Sara')),
          total: (await store.receivedTotals()).values.fold<double>(0, (a, b) => a + b),
        );
      });

      final state = result!;
      // A client created with an invoice is active work, not a bare lead.
      expect(state.clients, ['Bilal:active', 'Sara:paid']);
      expect(state.bilal, 1500, reason: 'a part payment leaves the rest owed');
      expect(state.sara, 0);
      expect(state.total, 1500);
    });

    testWidgets('a deadline asked for in chat lands with its date', (tester) async {
      await boot(tester, engine: 'onDevice');
      await say(tester, 'add a deadline to send the invoice on 2026-07-04');

      await tapVisible(tester, find.text('Save it'));

      final d = (await tester.runAsync(() => store.deadlines()))!.single;
      expect(d.title, 'send the invoice');
      expect(d.due, '2026-07-04');
    });
  });

  group('a question is never a write', () {
    testWidgets('asking about money answers instead of proposing', (tester) async {
      // The model is not answering, so what comes back is the "cannot answer"
      // card rather than anything at all. It still must not be a write: a
      // question about money is not an instruction to record one.
      await boot(tester, engine: 'onDevice', model: _ThrowingClient());
      await say(tester, 'how much does Bilal owe?');

      expect(find.text('Save it'), findsNothing);
      expect(find.text('Record payment'), findsNothing);
    });

    testWidgets('the model is never asked when a write is recognised', (tester) async {
      final model = _RecordingClient('the model should not have been called');
      await boot(tester, engine: 'onDevice', model: model);

      await say(tester, 'add client Bilal for 2000');

      expect(model.prompts, isEmpty,
          reason: 'a write is not a question and must not cost a 15 second wait');
    });
  });

  group('chat survives being stopped', () {
    // Regression. stop() used to set a flag that ask() only cleared *after* an
    // early return testing that same flag, so it never cleared. One press of Stop
    // and every later message was dropped before it reached the screen, and the
    // chat stayed dead until the app was restarted. The user reported it as
    // "edit breaks chat" and "my message does not even show".
    //
    // Uses a model that fails fast rather than a real socket, so the answer
    // settles inside a handful of frames and Stop has something to interrupt.
    testWidgets('a message sent after Stop still appears', (tester) async {
      await boot(tester, engine: 'onDevice', model: _HangingClient('one two three'));

      await tester.enterText(find.byType(TextField).last, 'who owes me money?');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await pump(tester, frames: 4);

      await tester.tap(find.byTooltip('Stop'));
      await pump(tester, frames: 6);
      expect(find.text('Stopped.'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, 'and the total?');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await pump(tester, frames: 20);

      expect(find.text('and the total?'), findsOneWidget,
          reason: 'the chat must still accept messages after a stop');
    });

    testWidgets('a message sent after Stop is actually answered',
        (tester) async {
      await boot(tester, engine: 'onDevice', model: _HangingClient('one two three'));

      await tester.enterText(find.byType(TextField).last, 'who owes me money?');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await pump(tester, frames: 4);
      await tester.tap(find.byTooltip('Stop'));
      await pump(tester, frames: 6);

      await tester.enterText(find.byType(TextField).last, 'hello again');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await pump(tester, frames: 30);

      final chat = (await tester.runAsync(() => store.chat()))!;
      // Checked by presence, not by position: the last record is Koru's answer,
      // and asserting on it was asserting that the model replied with the
      // question rather than that the question was sent.
      expect(chat.map((r) => r.text), contains('hello again'),
          reason: 'it must reach the database too, not just the screen');
    });

    testWidgets('editing while an answer is running destroys nothing',
        (tester) async {
      // The other half of the bug. The edit deleted the stored records and
      // trimmed the screen before checking whether it could finish, so an edit
      // during a reply wiped the conversation and added nothing.
      await boot(tester, engine: 'onDevice', model: _ThrowingClient());
      await say(tester, 'who owes me money?');
      await say(tester, 'and the total?');
      final before = (await tester.runAsync(() => store.chat()))!.length;

      final notifier = notifierOf(tester);
      // The second question's answer has settled, so nothing is busy; force the
      // condition the bug lived in by taking the path directly.
      await notifier.editAndResend(3, 'something else entirely');
      await pump(tester, frames: 8);

      final after = (await tester.runAsync(() => store.chat()))!;
      // The count can legitimately be the same, because an edit replaces the
      // old question rather than adding one. What matters is that the old one is
      // gone and the new one is in its place.
      expect(after.map((r) => r.text), contains('something else entirely'));
      expect(after.map((r) => r.text), isNot(contains('and the total?')),
          reason: 'the replaced question must not survive');
      expect(before, greaterThan(0));
    });

    testWidgets('editing a message Koru sent says why', (tester) async {
      await boot(tester, engine: 'onDevice', model: _ThrowingClient());
      await say(tester, 'who owes me money?');

      final notifier = notifierOf(tester);
      final state = notifier.state;
      // Found rather than assumed: the greeting is at index 0, so a hard coded
      // 1 lands on the user's own message and the guard never fires.
      // From index 1, because index 0 is the greeting and it is also a Koru
      // message. Matching on role alone found the greeting and the guard under
      // test never ran.
      final reply = state.messages.indexWhere(
          (m) => m.role == MsgRole.koru && !m.pending && m.text != _greetingText);
      expect(reply, greaterThan(0));

      final before = (await tester.runAsync(() => store.chat()))!.length;
      await notifier.editAndResend(reply, 'pretending this was mine');
      await pump(tester, frames: 8);

      expect(find.textContaining('That one is mine'), findsOneWidget);
      final after = (await tester.runAsync(() => store.chat()))!.length;
      expect(after, before, reason: 'and it must not have rewritten anything');
    });
  });

  group('tokens reach the screen one at a time', () {
    // The reported bug: one letter appeared instantly, then nothing until the
    // whole reply landed. Not a server problem, glen streams correctly.
    testWidgets('a partial answer is visible before the reply finishes',
        (tester) async {
      await boot(tester, engine: 'onDevice', model: _SlowClient('one two three'));

      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'who owes me money?');
      await tester.testTextInput.receiveAction(TextInputAction.send);

      // A couple of frames in, some but not all of the tokens should be up.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 5));

      final shown = find.textContaining('one');
      expect(shown, findsWidgets,
          reason: 'the first token should be on screen straight away');

      await pump(tester, frames: 40);

      expect(find.textContaining('one two three'), findsWidgets,
          reason: 'and the rest should follow');
    });

    testWidgets('history is carried into the next question', (tester) async {
      final model = _RecordingClient('Bilal owes you 1500 AED');
      await boot(tester, engine: 'onDevice', model: model);

      await say(tester, 'who owes me money?');
      await say(tester, 'how much is that?');

      expect(model.turns.length, 2);
      final second = model.turns[1];
      expect(second.map((t) => t.content), contains('who owes me money?'),
          reason: 'the model has to see what was asked before to know what '
              '"that" means');
      expect(second.map((t) => t.role), contains('assistant'));
    });

    testWidgets('a pasted list becomes a plan, and saving it lands every row',
        (tester) async {
      // The whole point of the feature, walked the way a person does it: paste,
      // see the plan, press the button, find the rows on the Business page.
      await boot(tester, engine: 'onDevice');

      await tester.enterText(
        find.byType(TextField).last,
        'Bilal 3000\nAcme 5000 net 30\nNorthwind retainer 1500',
      );
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await pump(tester, frames: 20);

      // A numbered plan, not a model answer and not a single giant client.
      expect(find.textContaining('I read 3 clients'), findsOneWidget);
      // Exactly one card. More than one would mean the same plan is on screen
      // twice, and pressing Add would then be ambiguous.
      expect(find.byType(PlanCard), findsOneWidget);
      expect(find.textContaining('Bilal, invoiced 3000'), findsWidgets);
      expect(find.text('Add Acme, invoiced 5000, net 30'), findsOneWidget);

      await tester.tap(find.text('Add 3'));
      await pump(tester, frames: 20);

      final names = await tester.runAsync(() async =>
          (await store.clients()).map((c) => c.name).toList());
      expect(names!.toSet(), {'Bilal', 'Acme', 'Northwind'});
    });

    testWidgets('pasting the same list twice does not double it', (tester) async {
      await boot(tester, engine: 'onDevice');
      const list = 'Bilal 3000\nAcme 5000';

      await tester.enterText(find.byType(TextField).last, list);
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await pump(tester, frames: 20);
      await tester.tap(find.text('Add 2'));
      await pump(tester, frames: 20);

      await tester.enterText(find.byType(TextField).last, list);
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await pump(tester, frames: 20);

      expect(find.textContaining('already added these'), findsOneWidget);
      final clients = (await tester.runAsync(() => store.clients()))!;
      expect(clients.length, 2);
    });

    testWidgets('a single line is still a single write, not a list',
        (tester) async {
      // One line must not take the list path, or its amount stops being
      // correctable in the card.
      await boot(tester, engine: 'onDevice');
      await say(tester, 'add client Bilal for 3000');
      expect(find.byType(PlanCard), findsNothing);
      expect(find.byType(WriteCard), findsOneWidget);
    });

    testWidgets('history cannot overrun the engine context window', (tester) async {
      // The engine runs a 1024 token KV cache. History that pushes the prompt
      // past it used to kill glen outright, which is not a slow answer, it is a
      // dead server and a colder one on every question afterwards.
      final model = _RecordingClient('sure');
      await boot(tester, engine: 'onDevice', model: model);

      for (var i = 0; i < 6; i++) {
        await say(tester, 'x' * 700);
      }

      final last = model.turns.last;
      final chars = last.fold<int>(0, (n, t) => n + t.content.length);
      expect(chars, lessThanOrEqualTo(1200),
          reason: 'history budget is 1200 characters, about 300 tokens');
    });

    testWidgets('history stays out of the system prompt', (tester) async {
      final model = _RecordingClient('sure');
      await boot(tester, engine: 'onDevice', model: model);

      await say(tester, 'who owes me money?');
      await say(tester, 'and who else?');

      // glen reuses the longest common token prefix between turns, so a system
      // prompt that changed every turn would mean a full prefill every turn.
      // Prefill on this phone runs about 7 tokens a second, so that is the
      // difference between 1.2 seconds and over a minute.
      expect(model.prompts[0], model.prompts[1],
          reason: 'if this changes, every turn is a full prefill again');
    });

    testWidgets('stopping leaves a truthful bubble', (tester) async {
      await boot(tester, engine: 'onDevice', model: _SlowClient('one two three'));

      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'who owes me money?');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();

      await tester.tap(find.byTooltip('Stop'));
      await tester.pump();

      expect(find.text('Stopped.'), findsOneWidget);

      // The late tokens must not creep back in afterwards.
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('one two three'), findsNothing);
      expect(find.text('Stopped.'), findsOneWidget);
    });
  });

  group('the on-device model path, end to end', () {
    testWidgets('streams a reply and records it', (tester) async {
      final model = _RecordingClient('Bilal owes you 1500 AED on that invoice');
      await boot(tester, engine: 'onDevice', model: model);

      await say(tester, 'who owes me money?');

      expect(lastReply(tester), contains('Bilal owes you 1500'));
      expect(find.text('Save it'), findsNothing);

      final chat = await tester.runAsync(() => store.chat());
      expect(chat!.last.role, 'koru');
      expect(chat.last.text, contains('Bilal owes'));
      expect(chat.last.why, contains('local model'));
    });

    testWidgets('the prompt carries the balances, so the model can discuss them',
        (tester) async {
      final model = _RecordingClient('He owes 1500');
      await boot(tester, engine: 'onDevice', model: model);

      final id = await tester.runAsync(
        () => store.addClient(const Client(name: 'Bilal', amount: 2000, status: 'delivered')),
      );
      await tester.runAsync(
        () => store.addPayment(Payment(clientId: id!, amount: 500, date: '2026-01-05')),
      );

      await say(tester, 'who owes me money?');

      expect(model.prompts.single, contains('Bilal owes 1500'));
    });

    testWidgets('an unreachable model produces no answer at all, and says so',
        (tester) async {
      // This is the complaint that removed the built-in engine. It used to fall
      // back to one: a rules-based answer out of the user's records, produced in
      // milliseconds, under a Koru badge, with a bracketed note about the model
      // underneath. It read as a fast model and it was not one.
      final broken = _ThrowingClient();
      await boot(tester, engine: 'onDevice', model: broken);

      await say(tester, 'how am i doing?');

      // Nothing from the records: the ledger is empty here, so a substitute
      // answer would have been its own small talk, which is the point.
      expect(lastReply(tester), contains('cannot answer'));
      expect(find.text('Start the local model'), findsOneWidget);

      // And the reason it could not answer is on the screen rather than in a
      // log, because "it is broken" and "it did not answer" are different bugs.
      expect(find.textContaining('Could not reach the local model'),
          findsWidgets);
    });

    testWidgets('the card starts the engine rather than sending them elsewhere',
        (tester) async {
      // The complaint behind this was "I cannot select the local model": the
      // choice existed, but starting it was a second job somewhere else. So the
      // offer on the card is the same one-tap start the switcher makes.
      final engine = _FakeBundledEngine();
      await boot(
        tester,
        engine: 'onDevice',
        model: _ThrowingClient(),
        bundled: engine,
      );

      await say(tester, 'how am i doing?');
      expect(find.byType(KoruEngineDownCard), findsOneWidget);

      final before = engine.starts;
      await tester.tap(find.text('Start the local model'));
      await pump(tester, frames: 20);

      expect(engine.starts, before + 1,
          reason: 'the button starts the model where the question was asked');
    });

    testWidgets('no engine answers, and no record is read to fake it',
        (tester) async {
      // The strongest form of the property. With the model down and a client in
      // the database, the reply must not contain the client's name or the
      // balance: the deleted assistant's whole trick was answering from these
      // very rows and passing it off as an answer.
      final broken = _ThrowingClient();
      await boot(tester, engine: 'onDevice', model: broken);
      final id = await tester.runAsync(
        () => store.addClient(const Client(name: 'Acme', amount: 5000, status: 'delivered')),
      );
      await tester.runAsync(
        () => store.addPayment(Payment(clientId: id!, amount: 2000, date: '2026-01-05')),
      );

      await say(tester, 'how am i doing?');

      final said = lastReply(tester);
      expect(said, isNot(contains('Acme')));
      expect(said, isNot(contains('3000')));
      // And nothing was written on the way to saying so.
      expect(await tester.runAsync(() => store.clients()), hasLength(1));
    });
  });

  group('a backup survives the app being gone', () {
    testWidgets('exports what the chat just created', (tester) async {
      await boot(tester, engine: 'onDevice');
      await say(tester, 'add client Bilal for 2000');
      await tapVisible(tester, find.text('Save it'));
      await say(tester, 'Bilal paid 500');
      await tapVisible(tester, find.text('Save it'));

      final json = await tester.runAsync(() => Backup.toJson(store));
      final decoded = jsonDecode(json!) as Map<String, dynamic>;

      expect(decoded['format'], 'koru-backup');
      expect((decoded['clients'] as List).length, 1);
      expect((decoded['clients'] as List).first['name'], 'Bilal');
      expect((decoded['payments'] as List).length, 1);
      // The payment is written out with the client's name, not an id, so the
      // file still makes sense to a person in five years.
      expect((decoded['payments'] as List).first['client'], 'Bilal');
      expect((decoded['payments'] as List).first['amount'], 500);
    });
  });
  group('asking for an entry in the words people use', () {
    // "add an entry" matched no write cue. It fell through to the model, which
    // has no ability to write, and the model reported success anyway. The cue
    // list is the first half of the fix. The second half is that a cue with no
    // usable name has to become a question, because "add an entry" carries no
    // name and there is genuinely nothing to write yet.
    const p = WriteIntentParser();

    test('a bare entry request is a write that needs a name', () {
      for (final phrase in [
        'add an entry',
        'add a record',
        'new entry',
        'add a contact',
      ]) {
        final intent = p.parse(phrase);
        expect(intent, isA<IncompleteWriteIntent>(), reason: phrase);
      }
    });

    test('it asks the question that unblocks it', () {
      final intent = p.parse('add an entry')! as IncompleteWriteIntent;
      expect(intent.question, contains('Who should I add'));
      expect(intent.kind, WriteKind.client);
    });

    test('still produces a real write once a name is there', () {
      expect(p.parse('add an entry for Bilal'),
          isA<AddClientIntent>());
    });
  });

  group('the assistant can add a project, in every mode', () {
    testWidgets('a personal project is proposed and lands', (tester) async {
      await boot(tester, engine: 'onDevice');
      await say(tester, 'start a project called Learn Arabic');

      await tapVisible(tester, find.text('Save it'));

      final projects = await tester.runAsync(() => store.projects());
      expect(projects!.map((p) => p.name), contains('Learn Arabic'));
      expect(projects.first.kind.name, 'personal');
      expect(projects.first.clientId, isNull);
    });

    testWidgets('"done when" is read into the project', (tester) async {
      await boot(tester, engine: 'onDevice');
      await say(tester,
          'start a project called the shop, done when the door is open');

      expect(lastReply(tester), contains('done when'));

      await tapVisible(tester, find.text('Save it'));
      final projects = await tester.runAsync(() => store.projects());
      final shop = projects!.firstWhere((p) => p.name == 'the shop');
      expect(shop.target, contains('door is open'));
    });

    testWidgets('a project for a named client attaches to them', (tester) async {
      await boot(tester, engine: 'onDevice');
      await say(tester, 'add client Bilal for 2000');
      await tapVisible(tester, find.text('Save it'));

      await say(tester, 'start a project called the rebrand for Bilal');
      await tapVisible(tester, find.text('Save it'));

      final projects = await tester.runAsync(() => store.projects());
      final rebrand = projects!.firstWhere((p) => p.name == 'the rebrand');
      expect(rebrand.kind.name, 'client');
      expect(rebrand.clientId, isNotNull);
      // The client must not be swallowed into the name.
      expect(rebrand.name.toLowerCase(), isNot(contains('bilal')));
    });

    testWidgets('a project for someone who does not exist says so', (tester) async {
      await boot(tester, engine: 'onDevice');
      await say(tester, 'start a project called the rebrand for Zohaib');
      expect(lastReply(tester), contains('do not have a client called Zohaib'));
    });

    testWidgets('a project with no name asks rather than saving nothing',
        (tester) async {
      await boot(tester, engine: 'onDevice');
      await say(tester, 'start a project');
      expect(find.text('Save it'), findsNothing);
      final projects = await tester.runAsync(() => store.projects());
      expect(projects, isEmpty);
    });
  });


  group('every engine gets the same writes', () {
    // The claim worth testing is that the AI is an addition, not the mechanism:
    // a client, a project and a calendar entry are recorded the same way with
    // the on-device model and with a cloud model. If that ever stops being true
    // the assistant has become a dependency of the records.
    for (final engine in const ['onDevice', 'cloud']) {
      testWidgets('$engine can add a client', (tester) async {
        await boot(tester, engine: engine, model: _SilentClient());
        await say(tester, 'add client Bilal for 2000');
        await tapVisible(tester, find.text('Save it'));
        final clients = await tester.runAsync(() => store.clients());
        expect(clients!.map((c) => c.name), contains('Bilal'));
      });

      testWidgets('$engine can add a project', (tester) async {
        await boot(tester, engine: engine, model: _SilentClient());
        await say(tester, 'start a project called the rebrand');
        await tapVisible(tester, find.text('Save it'));
        final projects = await tester.runAsync(() => store.projects());
        expect(projects!.map((p) => p.name), contains('the rebrand'));
      });

      testWidgets('$engine can add a calendar entry', (tester) async {
        await boot(tester, engine: engine, model: _SilentClient());
        await say(tester, 'schedule a call with Bilal tomorrow at 3pm');
        await tapVisible(tester, find.text('Save it'));
        final events = await tester.runAsync(() => store.events());
        expect(events!.map((e) => e.title).join(' ').toLowerCase(),
            contains('bilal'));
      });

      testWidgets('$engine shows a card rather than writing silently',
          (tester) async {
        await boot(tester, engine: engine, model: _SilentClient());
        await say(tester, 'add client Bilal for 2000');
        // The card is the approval step. Nothing is written until it is used.
        expect(find.text('Save it'), findsOneWidget);
        final clients = await tester.runAsync(() => store.clients());
        expect(clients, isEmpty);
      });
    }
  });
}

/// Emits one token per event loop turn, the way a real server does.
///
/// The other fakes emit every token in a tight synchronous loop, which is why
/// this bug survived 334 passing tests: no frame was ever rendered between the
/// first token and the last, so nothing could observe the intermediate state.
/// A real socket hands control back to the event loop between chunks, and that
/// is the only place the bug was visible.
class _SlowClient extends LocalModelClient {
  _SlowClient(this.reply);

  final String reply;

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
    final pieces = reply.split(' ');
    for (var i = 0; i < pieces.length; i++) {
      onToken('${pieces[i]} ');
      // Yields, so a frame can be pumped with a partial reply on screen.
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    return LocalReply(reply, 4.0);
  }
}

/// Hangs on the first call, then answers normally.
///
/// _SlowClient finishes in a couple of fake-milliseconds, and pumping four
/// frames advances far past that, so by the time the test pressed Stop the reply
/// had already landed and there was no Stop button left to press. This one stays
/// busy until told otherwise, which is the only state in which Stop exists.
class _HangingClient extends LocalModelClient {
  _HangingClient(this.reply);

  final String reply;
  int calls = 0;

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
    calls++;
    if (calls == 1) {
      onToken('thinking');
      // Never resolves on its own within a test run.
      await Completer<void>().future;
    }
    onToken(reply);
    return LocalReply(reply, 4.0);
  }
}

/// The bundled engine, standing in for the one that execs a binary.
///
/// Reports a start and comes straight back, which is all the card's button has
/// to be shown doing.
class _FakeBundledEngine extends BundledEngine {
  int starts = 0;

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
  }) async {
    starts++;
    onProgress?.call(0);
    return BundledStartResult.ready('http://127.0.0.1:$port');
  }

  static Future<bool> _neverHealthy() async => false;
}

/// A local model that is not answering, standing in for glen not having started.
class _ThrowingClient extends LocalModelClient {
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
  }) async =>
      const LocalFailed('Could not reach the local model.');

}

/// A model that answers, but says nothing a parser could use.
///
/// The claim these tests exist to check is that Koru understood the request, not
/// that a model produced the record. A silent client makes that visible: if the
/// card ever stops appearing, the engine has quietly become the mechanism.
class _SilentClient extends LocalModelClient {
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
  }) async =>
      const LocalReply('', 0.0);
}
