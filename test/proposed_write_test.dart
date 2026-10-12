import 'package:flutter_test/flutter_test.dart';
import 'package:koru/models.dart';
import 'package:koru/proposed_write.dart';

import 'test_store.dart';

/// Read the database back after writing.
///
/// apply() returning without throwing is not evidence of anything: sqflite
/// reports success for a write a constraint or a trigger quietly discarded. The
/// whole point of verify() is that the app checks rather than assumes, and these
/// tests are what make the check meaningful.
void main() {
  group('verify reads the write back instead of trusting apply', () {
    test('a client that really saved reports nothing wrong', () async {
      final store = await openTestStore();
      const write = ProposedClient(name: 'Bilal', amount: 2000);

      await write.apply(store);
      expect(await write.verify(store), isNull);

      final clients = await store.clients();
      expect(clients.single.name, 'Bilal');
      expect(clients.single.amount, 2000);
    });

    test('an edit is confirmed against the stored row, not the intent', () async {
      final store = await openTestStore();
      await store.addClient(const Client(name: 'Bilal', amount: 2000, status: 'active'));
      final client = (await store.clients()).single;

      final write = ProposedEditClient(client: client, amount: 3000);
      await write.apply(store);

      expect(await write.verify(store), isNull);
      expect((await store.clients()).single.amount, 3000);
    });

    test('an edit leaves the fields it never mentioned alone', () async {
      final store = await openTestStore();
      await store.addClient(const Client(
        name: 'Bilal',
        amount: 2000,
        due: '2026-05-01',
        status: 'active',
      ));
      final client = (await store.clients()).single;

      final write = ProposedEditClient(client: client, amount: 3000);
      await write.apply(store);

      final after = (await store.clients()).single;
      expect(after.amount, 3000);
      expect(after.due, '2026-05-01', reason: 'the sentence did not mention it');
      expect(after.status, 'active');
    });

    test('a delete is confirmed by the client being gone', () async {
      final store = await openTestStore();
      await store.addClient(const Client(name: 'Bilal', amount: 2000));
      final client = (await store.clients()).single;

      final write = ProposedDeleteClient(client: client);
      await write.apply(store);

      expect(await write.verify(store), isNull);
      expect((await store.clients()), isEmpty);
    });

    test('a payment is confirmed in the ledger', () async {
      final store = await openTestStore();
      final id = await store.addClient(const Client(name: 'Bilal', amount: 2000));
      final client = (await store.clients()).singleWhere((c) => c.id == id);

      final write = ProposedPayment(client: client, amount: 500);
      await write.apply(store);

      expect(await write.verify(store), isNull);
      final paid = await store.payments();
      expect(paid.map((p) => p.amount), contains(500));
    });
  });

  group('the summaries say what will happen', () {
    test('a delete says the payments are kept', () async {
      const write = ProposedDeleteClient(
        client: Client(id: 1, name: 'Bilal', amount: 2000),
      );
      expect(write.summary, contains('Bilal'));
      expect(write.summary.toLowerCase(), contains('payments'));
    });

    test('an edit names the client and the new value', () {
      const write = ProposedEditClient(
        client: Client(id: 1, name: 'Bilal', amount: 2000),
        amount: 3000,
      );
      expect(write.summary, contains('Bilal'));
      expect(write.summary, contains('3000'));
    });
  });
}
