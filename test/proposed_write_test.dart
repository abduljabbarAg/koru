import 'package:flutter_test/flutter_test.dart';
import 'package:koru/local/write_intent.dart';
import 'package:koru/models.dart';
import 'package:koru/proposed_write.dart';
import 'package:koru/store.dart';

import 'test_store.dart';

/// Resolving is the step between "I understood the sentence" and "this touches
/// a real record", so it is tested against a real database rather than mocks.
void main() {
  late ProfileStore store;

  setUpAll(initTestDatabase);

  setUp(() async {
    store = await openTestStore();
  });

  const parser = WriteIntentParser();
  const resolver = WriteResolver();

  Future<WriteResolution> resolve(String sentence) =>
      resolver.resolve(parser.parse(sentence)!, store);

  Future<Client> addClient(String name, {double? amount, String status = 'delivered'}) async {
    final id = await store.addClient(Client(
      name: name,
      amount: amount,
      status: status,
      created: '2026-01-01',
    ));
    return Client(id: id, name: name, amount: amount, status: status);
  }

  group('a payment for a client on file', () {
    test('resolves to a write pointing at the real client', () async {
      final bilal = await addClient('Bilal', amount: 2000);
      final resolution = await resolve('Bilal paid 500');

      expect(resolution.isWrite, isTrue);
      final write = resolution.write! as ProposedPayment;
      expect(write.client.id, bilal.id);
      expect(write.amount, 500);
      expect(resolution.problem, isNull);
    });

    test('applying it appends to the ledger and leaves a part payment unsettled',
        () async {
      final bilal = await addClient('Bilal', amount: 2000);
      await (await resolve('Bilal paid 500')).write!.apply(store);

      expect((await store.payments()).single.amount, 500);
      expect(await store.balanceFor(bilal), 1500);
      // Still owed, so the client must not have been marked settled.
      expect((await store.clients()).single.status, isNot('paid'));
    });

    test('applying enough to clear the balance settles the client', () async {
      final bilal = await addClient('Bilal', amount: 2000);
      await (await resolve('Bilal paid 2000')).write!.apply(store);

      expect(await store.balanceFor(bilal), 0);
      expect((await store.clients()).single.status, 'paid');
    });

    test('a name that is a prefix resolves to the one client', () async {
      await addClient('Bilal', amount: 100);
      final resolution = await resolve('Bilal paid 10');
      expect((resolution.write! as ProposedPayment).client.name, 'Bilal');
    });
  });

  group('a payment for a client who is not on file', () {
    test('is refused with a sentence saying so', () async {
      final resolution = await resolve('Nobody paid 500');
      expect(resolution.isWrite, isFalse);
      expect(resolution.problem, contains('Nobody'));
    });

    test('is refused rather than invented', () async {
      await resolve('Ghost paid 500');
      expect(await store.payments(), isEmpty);
      expect(await store.clients(), isEmpty);
    });
  });

  group('an ambiguous client name', () {
    test('is reported rather than picked', () async {
      await addClient('Acme', amount: 100);
      await addClient('Acme Holdings', amount: 200);

      // "Acme" is an exact match for one of them, so it resolves. A name that
      // only partly matches several does not.
      expect((await resolve('Acme paid 10')).write, isA<ProposedPayment>());

      await addClient('Acme Trading', amount: 300);
      await addClient('Acme Digital', amount: 400);
      final vague = await resolve('Acme Trad paid 10');
      expect(vague.isWrite, isFalse);
    });
  });

  group('adding a client', () {
    test('applies with whatever the sentence said', () async {
      await (await resolve('add client Sara for 1500')).write!.apply(store);
      final created = (await store.clients()).single;
      expect(created.name, 'Sara');
      expect(created.amount, 1500);
    });

    test('a client with no amount becomes a lead, not an active job', () async {
      await (await resolve('add client Prospective Ltd')).write!.apply(store);
      expect((await store.clients()).single.status, 'lead');
    });
  });

  group('adding a deadline', () {
    test('applies the title and the date', () async {
      await (await resolve('add a deadline to send the invoice on 2026-05-04')).write!
          .apply(store);
      final d = (await store.deadlines()).single;
      expect(d.title, 'send the invoice');
      expect(d.due, '2026-05-04');
    });

    test('falls back to today rather than inventing a date', () async {
      await (await resolve('add a deadline to file taxes')).write!.apply(store);
      final today = DateTime.now().toIso8601String().substring(0, 10);
      expect((await store.deadlines()).single.due, today);
    });
  });

  group('nothing is written without an approve', () {
    test('resolving alone touches nothing', () async {
      await addClient('Bilal', amount: 2000);
      await resolve('Bilal paid 500');
      await resolve('add client Sara');
      await resolve('add a deadline to send the invoice');

      expect(await store.payments(), isEmpty);
      expect(await store.clients(), hasLength(1));
      expect(await store.deadlines(), isEmpty);
    });
  });
}