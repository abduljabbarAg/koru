import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:koru/models.dart';
import 'package:koru/store.dart';

import 'test_store.dart';

/// Exercises the real store against a real SQLite database in a temp directory,
/// so the schema and the queries are actually run rather than assumed.
void main() {
  setUpAll(initTestDatabase);

  late Directory dir;
  late ProfileStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('koru_store_test');
    store = await ProfileStore.open(directory: dir);
  });

  tearDown(() async {
    await store.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('profile', () {
    test('round trips a value', () async {
      await store.put('nickname', 'kami');
      expect(await store.get('nickname'), 'kami');
    });

    test('overwrites rather than duplicating', () async {
      await store.put('nickname', 'a');
      await store.put('nickname', 'b');
      expect(await store.get('nickname'), 'b');
      expect(await store.all(), hasLength(1));
    });

    test('a missing key is null, not an error', () async {
      expect(await store.get('nothing'), isNull);
    });

    test('numbers parse and round trip', () async {
      await store.putNumber('capacity', 8);
      expect(await store.number('capacity'), 8);
    });

    test('a non numeric value is not a number', () async {
      await store.put('capacity', 'lots');
      expect(await store.number('capacity'), isNull);
    });

    test('onboarding is one way until wiped', () async {
      expect(await store.onboarded, isFalse);
      await store.completeOnboarding();
      expect(await store.onboarded, isTrue);
      await store.wipe();
      expect(await store.onboarded, isFalse);
    });

    test('help_focus reaches the packet instead of being dropped', () async {
      await store.put('help_focus', 'business growth');
      final packet = await store.packet();
      expect(packet.focus, 'business growth');
      expect(packet.renderForCloud(), contains('asking about: business growth'));
    });
  });

  group('business', () {
    test('stores and reads back every field', () async {
      await store.addClient(const Client(
        name: 'Acme',
        status: 'delivered',
        amount: 1500,
        due: '2026-02-01',
        leadSource: 'referral',
        note: 'net 30',
        created: '2026-01-01',
      ));
      final c = (await store.clients()).single;
      expect(c.name, 'Acme');
      expect(c.status, 'delivered');
      expect(c.amount, 1500);
      expect(c.due, '2026-02-01');
      expect(c.leadSource, 'referral');
      expect(c.note, 'net 30');
    });

    test('a default status is applied on read', () async {
      await store.addClient(const Client(name: 'x', created: '2026-01-01'));
      expect((await store.clients()).single.status, 'lead');
    });

    test('changes status', () async {
      final id = await store.addClient(const Client(name: 'x', created: '2026-01-01'));
      await store.setClientStatus(id, 'paid');
      expect((await store.clients()).single.status, 'paid');
    });

    test('clears a due date and a note', () async {
      await store.addClient(const Client(
        name: 'x',
        created: '2026-01-01',
        due: '2026-02-01',
        note: 'hello',
      ));
      final c = (await store.clients()).single;
      await store.updateClient(c.copyWith(clearDue: true, clearNote: true));
      final after = (await store.clients()).single;
      expect(after.due, isNull);
      expect(after.note, isNull);
    });

    test('deletes', () async {
      final id = await store.addClient(const Client(name: 'x', created: '2026-01-01'));
      await store.deleteClient(id);
      expect(await store.clients(), isEmpty);
    });
  });

  group('chat', () {
    test('round trips in insertion order', () async {
      await store.addChat(const ChatRecord(role: 'user', text: 'hi', created: '2026-01-01'));
      await store.addChat(const ChatRecord(
        role: 'koru',
        text: 'hello',
        why: 'Answered on device.',
        created: '2026-01-01',
      ));
      final records = await store.chat();
      expect(records.map((r) => r.role), ['user', 'koru']);
      expect(records.last.why, 'Answered on device.');
      expect(records.last.needsHuman, isFalse);
    });

    test('a handoff survives the round trip', () async {
      await store.addChat(const ChatRecord(
        role: 'koru',
        text: 'stepping aside',
        needsHuman: true,
        created: '2026-01-01',
      ));
      expect((await store.chat()).single.needsHuman, isTrue);
    });

    test('clears', () async {
      await store.addChat(const ChatRecord(role: 'user', text: 'hi', created: '2026-01-01'));
      await store.clearChat();
      expect(await store.chat(), isEmpty);
    });
  });

  group('wipe', () {
    test('clears every table', () async {
      final clientId = await store.addClient(
          const Client(name: 'x', created: '2026-01-01'));
      await store.put('nickname', 'kami');
      await store.addClient(const Client(name: 'x', created: '2026-01-01'));
      await store.addPayment(Payment(clientId: clientId, amount: 10, date: '2026-01-01'));
      await store.addDeadline(const Deadline(title: 'x', due: '2026-01-01'));
      await store.addChat(const ChatRecord(role: 'user', text: 'hi', created: '2026-01-01'));

      await store.wipe();

      expect(await store.all(), isEmpty);
      expect(await store.clients(), isEmpty);
      expect(await store.payments(), isEmpty);
      expect(await store.deadlines(openOnly: false), isEmpty);
      expect(await store.chat(), isEmpty);
    });
  });

  group('the payments ledger', () {
    late Client bilal;

    setUp(() async {
      bilal = Client(
        id: await store.addClient(
          const Client(name: 'Bilal', status: 'delivered', amount: 2000),
        ),
        name: 'Bilal',
        status: 'delivered',
        amount: 2000,
      );
    });

    test('balance is invoiced minus what has been received', () async {
      expect(await store.balanceFor(bilal), 2000);
      await store.addPayment(Payment(
        clientId: bilal.id!,
        amount: 500,
        date: '2026-01-05',
      ));
      expect(await store.balanceFor(bilal), 1500);
      await store.addPayment(Payment(
        clientId: bilal.id!,
        amount: 1500,
        date: '2026-01-06',
      ));
      expect(await store.balanceFor(bilal), 0);
    });

    test('overpaying never shows as money owed to the freelancer', () async {
      await store.addPayment(Payment(
        clientId: bilal.id!,
        amount: 2500,
        date: '2026-01-05',
      ));
      expect(await store.balanceFor(bilal), greaterThanOrEqualTo(0));
      expect(await store.balanceFor(bilal), 0);
    });

    test('a client with no amount on file has no balance', () async {
      final free = Client(
        id: await store.addClient(const Client(name: 'Prospect', status: 'lead')),
        name: 'Prospect',
      );
      expect(await store.balanceFor(free), 0);
    });

    test('payments are kept per client, newest first', () async {
      final other = Client(
        id: await store.addClient(const Client(name: 'Sara', amount: 100)),
        name: 'Sara',
      );
      await store.addPayment(Payment(clientId: bilal.id!, amount: 1, date: '2026-01-01'));
      await store.addPayment(Payment(clientId: bilal.id!, amount: 2, date: '2026-02-01'));
      await store.addPayment(Payment(clientId: other.id!, amount: 9, date: '2026-03-01'));

      final mine = await store.payments(clientId: bilal.id!);
      expect(mine.map((p) => p.amount).toList(), [2, 1]);
      expect(await store.receivedFor(bilal.id!), 3);
    });

    test('the grouped totals agree with the per-client figure', () async {
      final other = Client(
        id: await store.addClient(const Client(name: 'Sara', amount: 100)),
        name: 'Sara',
      );
      await store.addPayment(Payment(clientId: bilal.id!, amount: 500, date: '2026-01-01'));
      await store.addPayment(Payment(clientId: bilal.id!, amount: 250, date: '2026-02-01'));
      await store.addPayment(Payment(clientId: other.id!, amount: 40, date: '2026-02-02'));

      final totals = await store.receivedTotals();
      expect(totals[bilal.id!], 750);
      expect(totals[other.id!], 40);
      // The screen derives every figure from this map, so it has to match the
      // per-client query or the header and the rows will disagree.
      expect(totals[bilal.id!], await store.receivedFor(bilal.id!));
    });

    test('a client with no payments is absent from the totals, not zero', () async {
      await store.addClient(const Client(name: 'Never paid', amount: 100));
      expect(await store.receivedTotals(), isEmpty);
    });

    test('undoing a payment gives the money back', () async {
      await store.addPayment(Payment(clientId: bilal.id!, amount: 500, date: '2026-01-01'));
      final payment = (await store.payments()).single;
      expect(await store.balanceFor(bilal), 1500);

      await store.deletePayment(payment.id!);

      expect(await store.balanceFor(bilal), 2000);
      expect(await store.payments(), isEmpty);
      expect(await store.receivedTotals(), isEmpty);
    });

    test('the list is capped but the totals are not', () async {
      for (var i = 0; i < 5; i++) {
        await store.addPayment(
            Payment(clientId: bilal.id!, amount: 10, date: '2026-01-0${i + 1}'));
      }
      expect(await store.payments(limit: 3), hasLength(3));
      // The cap is for display only. A total that silently stopped counting
      // past the page size would under-report money owed.
      expect((await store.receivedTotals())[bilal.id!], 50);
    });
  });

  group('deadlines', () {
    test('open ones come back soonest first and can be filtered by client', () async {
      final id = await store.addClient(const Client(name: 'Sara'));
      await store.addDeadline(Deadline(clientId: id, title: 'Late', due: '2026-03-01'));
      await store.addDeadline(Deadline(clientId: id, title: 'Soon', due: '2026-01-05'));
      await store.addDeadline(const Deadline(title: 'Tax', due: '2026-02-01'));

      final open = await store.deadlines();
      expect(open.map((d) => d.title).toList(), ['Soon', 'Tax', 'Late']);

      final sara = await store.deadlines(clientId: id);
      expect(sara.map((d) => d.title).toList(), ['Soon', 'Late']);
    });

    test('overdue ignores anything already done', () {
      final today = DateTime(2026, 1, 10);
      expect(const Deadline(title: 'Late', due: '2026-01-01').isOverdueOn(today), isTrue);
      expect(const Deadline(title: 'Done', due: '2026-01-01', done: true).isOverdueOn(today), isFalse);
      expect(const Deadline(title: 'Today', due: '2026-01-10').isOverdueOn(today), isFalse);
    });

    test('completing one takes it out of the open list, and can be undone', () async {
      final id = await store.addDeadline(const Deadline(title: 'Send invoice', due: '2026-01-05'));
      expect(await store.deadlines(), hasLength(1));

      await store.setDeadlineDone(id, true);
      expect(await store.deadlines(), isEmpty);
      expect(await store.deadlines(openOnly: false), hasLength(1));

      await store.setDeadlineDone(id, false);
      expect(await store.deadlines(), hasLength(1));
    });

    test('deletes', () async {
      final id = await store.addDeadline(const Deadline(title: 'Dropped', due: '2026-01-05'));
      await store.deleteDeadline(id);
      expect(await store.deadlines(openOnly: false), isEmpty);
    });
  });

  group('the balance rule', () {
    // The single place the arithmetic is written, shared by the store and the
    // screen. Both a query and a precomputed total feed it, so the two cannot
    // disagree about what is owed.
    test('is the invoice minus what has come in', () {
      const c = Client(name: 'Bilal', amount: 2000);
      expect(c.balanceWith(0), 2000);
      expect(c.balanceWith(500), 1500);
      expect(c.balanceWith(2000), 0);
    });

    test('never goes negative, because negative reads as money owed to you', () {
      const c = Client(name: 'Bilal', amount: 2000);
      expect(c.balanceWith(2500), 0);
      expect(c.balanceWith(999999), 0);
    });

    test('is zero when there is nothing invoiced', () {
      expect(const Client(name: 'Prospect').balanceWith(0), 0);
      expect(const Client(name: 'Prospect').balanceWith(100), 0);
    });
  });

  group('retainers', () {
    test('a retainer survives the round trip', () async {
      final id = await store.addClient(const Client(
        name: 'Retainer Co',
        status: 'active',
        amount: 2500,
        monthly: 2500,
        created: '2026-01-01',
      ));
      final c = (await store.clients()).single;
      expect(c.id, id);
      expect(c.monthly, 2500);
      expect(c.isRetainer, isTrue);
    });

    test('a client with no retainer is not one', () async {
      await store.addClient(const Client(name: 'One off', amount: 100));
      final c = (await store.clients()).single;
      expect(c.monthly, isNull);
      expect(c.isRetainer, isFalse);
    });

    test('a zero monthly rate is not a retainer', () {
      expect(const Client(name: 'x', monthly: 0).isRetainer, isFalse);
    });

    test('a retainer does not change the invoice balance', () async {
      // A retainer has no invoice behind it, so folding it into the balance
      // would invent money owed that nobody billed.
      final id = await store.addClient(const Client(
        name: 'Retainer Co',
        status: 'active',
        amount: 2500,
        monthly: 2500,
      ));
      await store.addPayment(Payment(clientId: id, amount: 2500, date: '2026-01-15'));
      final c = (await store.clients()).single;
      expect(await store.balanceFor(c), 0);
    });

    test('next due is a month after the last payment', () async {
      final id = await store.addClient(const Client(
        name: 'Retainer Co',
        status: 'active',
        amount: 2500,
        monthly: 2500,
      ));
      await store.addPayment(Payment(clientId: id, amount: 2500, date: '2026-01-15'));
      final c = (await store.clients()).single;

      expect(await store.lastPaymentOn(id), DateTime(2026, 1, 15));
      expect(await store.nextRetainerDue(c), DateTime(2026, 2, 15));
    });

    test('next due rolls into the following year', () async {
      final id = await store.addClient(const Client(
        name: 'Retainer Co',
        status: 'active',
        amount: 2500,
        monthly: 2500,
      ));
      await store.addPayment(Payment(clientId: id, amount: 2500, date: '2026-12-15'));
      final c = (await store.clients()).single;
      expect(await store.nextRetainerDue(c), DateTime(2027, 1, 15));
    });

    test('a retainer never paid has no next due date', () async {
      final id = await store.addClient(const Client(
        name: 'Retainer Co',
        status: 'active',
        monthly: 2500,
      ));
      final c = (await store.clients()).singleWhere((x) => x.id == id);
      expect(await store.lastPaymentOn(id), isNull);
      expect(await store.nextRetainerDue(c), isNull);
    });

    test('a non retainer never reports a due date', () async {
      final id = await store.addClient(const Client(name: 'One off', amount: 100));
      await store.addPayment(Payment(clientId: id, amount: 100, date: '2026-01-15'));
      final c = (await store.clients()).single;
      expect(await store.nextRetainerDue(c), isNull);
    });
  });
}
