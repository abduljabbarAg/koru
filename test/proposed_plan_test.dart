import 'package:flutter_test/flutter_test.dart';
import 'package:koru/models.dart';
import 'package:koru/proposed_write.dart';
import 'package:koru/store.dart';

import 'test_store.dart';

/// The plan that stands between a pasted list and the ledger.
///
/// The properties that matter here are not about parsing, they are about what
/// happens when something goes wrong: that a partly applied import is impossible,
/// that the same list cannot be pasted twice, and that lines the parser could not
/// read are carried to the card instead of vanishing.
void main() {
  late ProfileStore store;

  setUpAll(initTestDatabase);

  setUp(() async {
    store = await openTestStore();
  });

  group('a plan applies whole or not at all', () {
    test('every step lands when they all succeed', () async {
      const plan = ProposedPlan(steps: [
        ProposedClient(name: 'Bilal', amount: 3000),
        ProposedClient(name: 'Acme', amount: 5000),
        ProposedClient(name: 'Lumen', amount: 1500),
      ]);

      await plan.apply(store);

      expect((await store.clients()).map((c) => c.name), ['Bilal', 'Acme', 'Lumen']);
    });

    test('nothing lands when a step in the middle fails', () async {
      // A payment for a client that does not exist is the realistic failure: it
      // refuses rather than inventing one. If the import were applied row by row,
      // Bilal would already be in the ledger by the time it hit that, and the
      // user would have no way to tell what got in.
      const orphan = ProposedPayment(
        client: Client(id: 9999, name: 'Ghost', created: ''),
        amount: 100,
      );
      const plan = ProposedPlan(steps: [
        ProposedClient(name: 'Bilal', amount: 3000),
        orphan,
        ProposedClient(name: 'Acme', amount: 5000),
      ]);


      await expectLater(plan.apply(store), throwsA(anything));

      // And the database is genuinely usable afterwards, which is the real
      // proof that the transaction rolled back rather than leaving the store in
      // whatever state a half-applied write would.
      expect(await store.clients(), isEmpty,
          reason: 'the first client must have rolled back with the rest');
      await store.addClient(
          const Client(name: 'After', amount: 1, created: '2026-01-01T00:00:00Z'));
      expect((await store.clients()).single.name, 'After');
    });

    test('an empty plan does nothing rather than opening a transaction', () async {
      await const ProposedPlan(steps: []).apply(store);
      expect(await store.clients(), isEmpty);
    });
  });

  group('money goes through the ledger', () {
    test('a deposit is a payment, so the balance comes out right', () async {
      await const ProposedClient(
        name: 'Lumen',
        amount: 5000,
        deposit: 2000,
      ).apply(store);

      final c = (await store.clients()).single;
      expect(c.deposit, 2000);
      expect(await store.balanceFor(c), 3000,
          reason: 'a deposit held only on the client row would show 5000');
      expect((await store.payments()).single.note, 'Deposit');
    });

    test('terms produce a due date with no date typed in', () async {
      await ProposedClient(
        name: 'Acme',
        amount: 5000,
        termsDays: 30,
        invoicedOn: DateTime(2026, 10, 1),
      ).apply(store);

      final c = (await store.clients()).single;
      expect(c.dueDate, DateTime(2026, 10, 31));
      expect(c.isOverdueOn(DateTime(2026, 11, 15)), isTrue);
    });

    test('a retainer is a monthly amount, not a one-off', () async {
      await const ProposedClient(name: 'Northwind', amount: 1500, retainer: true).apply(store);
      expect((await store.clients()).single.isRetainer, isTrue);
    });
  });

  group('the same list cannot be imported twice', () {
    test('a fingerprint is stable for the same text', () {
      final a = ProposedImport.fingerprintOf('Bilal 3000\nAcme 5000');
      final b = ProposedImport.fingerprintOf('  Bilal 3000\nAcme 5000\n  ');
      expect(a, b, reason: 'whitespace at the edges is not a different list');
      expect(a, isNot(ProposedImport.fingerprintOf('Bilal 3000')));
    });

    test('importing marks the text, and a second attempt is refused', () async {
      const source = 'Bilal 3000\nAcme 5000';
      final first = ProposedImport(
        steps: const [ProposedClient(name: 'Bilal', amount: 3000)],
        source: source,
        fingerprint: ProposedImport.fingerprintOf(source),
      );

      expect(await first.alreadyImported(store), isFalse);
      await first.rememberImport(store);
      expect(await first.alreadyImported(store), isTrue);

      // And the guard is on the list, not on the clients, so a corrected list
      // with one figure changed still goes through.
      const corrected = 'Bilal 3000\nAcme 6000';
      final second = ProposedImport(
        steps: [],
        source: corrected,
        fingerprint: ProposedImport.fingerprintOf(corrected),
      );
      expect(await second.alreadyImported(store), isFalse);
    });
  });

  group('the card has to be honest', () {
    test('the summary counts the steps', () {
      const plan = ProposedPlan(steps: [
        ProposedClient(name: 'Bilal', amount: 3000),
        ProposedClient(name: 'Acme', amount: 5000),
      ]);
      expect(plan.summary, '2 things to add');
      expect(const ProposedPlan(steps: []).summary, 'Nothing to add');
    });

    test('a step says what it will do, including terms', () {
      expect(
        const ProposedClient(name: 'Acme', amount: 5000, termsDays: 30).summary,
        'Add Acme, invoiced 5000, net 30',
      );
      expect(
        const ProposedClient(name: 'Acme', amount: 5000, termsDays: 0).summary,
        'Add Acme, invoiced 5000, due on completion',
      );
      expect(
        const ProposedClient(name: 'Lumen', amount: 5000, deposit: 2000).summary,
        contains('2000 paid up front'),
      );
    });
  });
}