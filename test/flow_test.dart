import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koru/backup.dart';
import 'package:koru/local/local_model_client.dart';
import 'package:koru/models.dart';
import 'package:koru/screens/chat.dart';
import 'package:koru/secrets.dart';
import 'package:koru/state.dart';
import 'package:koru/store.dart';

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
  final progress = <(int, int)>[];

  @override
  Future<LocalModelResult> chatStream({
    required String endpoint,
    required String model,
    required String system,
    required String question,
    required void Function(String delta) onToken,
    void Function(int done, int total)? onProgress,
    int maxTokens = 160,
    double temperature = 0.7,
  }) async {
    prompts.add(system);
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

void main() {
  late ProfileStore store;

  setUpAll(initTestDatabase);

  setUp(() async {
    store = await openTestStore();
  });

  /// Steps frames so provider futures resolve and animations settle.
  Future<void> pump(WidgetTester tester, {int frames = 8}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> boot(
    WidgetTester tester, {
    required String engine,
    LocalModelClient? model,
  }) async {
    await store.put('engine', engine);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storeProvider.overrideWith((ref) async => store),
          cloudKeyProvider.overrideWith((ref, providerId) async => ''),
          secretsProvider.overrideWithValue(MemoryKeyStore()),
          localModelClientProvider.overrideWithValue(model ?? const LocalModelClient()),
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
  String lastReply(WidgetTester tester) {
    final texts = tester
        .widgetList<Text>(find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Text),
        ))
        .map((t) => t.data)
        .whereType<String>()
        .where((t) => t.trim().isNotEmpty)
        .toList();
    return texts.isEmpty ? '' : texts.last;
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
      await boot(tester, engine: 'builtIn');
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
      await boot(tester, engine: 'builtIn');
      await say(tester, 'add client Sara for 900');

      await tapVisible(tester, find.text('Discard'));

      expect(await tester.runAsync(() => store.clients()), isEmpty);
      expect(find.textContaining('not saved'), findsOneWidget);
    });

    testWidgets('a payment for an unknown client is refused, not invented',
        (tester) async {
      await boot(tester, engine: 'builtIn');
      await say(tester, 'Ghost paid 500');

      expect(find.textContaining('I do not have a client called Ghost'), findsOneWidget);
      // Crucially, no card was offered, so there is nothing to tap.
      expect(find.text('Save it'), findsNothing);
      expect(await tester.runAsync(() => store.payments()), isEmpty);
    });

    testWidgets('two clients, two payments, and a balance that adds up',
        (tester) async {
      await boot(tester, engine: 'builtIn');

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
      await boot(tester, engine: 'builtIn');
      await say(tester, 'add a deadline to send the invoice on 2026-07-04');

      await tapVisible(tester, find.text('Save it'));

      final d = (await tester.runAsync(() => store.deadlines()))!.single;
      expect(d.title, 'send the invoice');
      expect(d.due, '2026-07-04');
    });
  });

  group('a question is never a write', () {
    testWidgets('asking about money answers instead of proposing', (tester) async {
      await boot(tester, engine: 'builtIn');
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
      expect(chat.last.why, contains('on this phone'));
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

    testWidgets('falls back to the built-in engine when the model is unreachable',
        (tester) async {
      final broken = _ThrowingClient();
      await boot(tester, engine: 'onDevice', model: broken);

      await say(tester, 'how am i doing?');

      // An answer still arrived, and it said why the model did not.
      expect(lastReply(tester), contains('did not answer'));
    });
  });

  group('the built-in assistant, end to end', () {
    testWidgets('answers a status question from the ledger', (tester) async {
      await boot(tester, engine: 'builtIn');
      final id = await tester.runAsync(
        () => store.addClient(const Client(name: 'Acme', amount: 5000, status: 'delivered')),
      );
      await tester.runAsync(
        () => store.addPayment(Payment(clientId: id!, amount: 2000, date: '2026-01-05')),
      );

      await say(tester, 'how am i doing?');

      expect(lastReply(tester), contains('3000'));
      expect(lastReply(tester), isNot(contains('5000 AED booked')));
    });

    testWidgets('offers to record rather than record silently', (tester) async {
      await boot(tester, engine: 'builtIn');
      await say(tester, 'what can you do?');
      expect(lastReply(tester), contains('add client'));
    });
  });

  group('a backup survives the app being gone', () {
    testWidgets('exports what the chat just created', (tester) async {
      await boot(tester, engine: 'builtIn');
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
    int maxTokens = 160,
    double temperature = 0.7,
  }) async =>
      const LocalFailed('Could not reach the local model.');
}
