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
      await store.putNumber('height', 1.82);
      expect(await store.number('height'), 1.82);
    });

    test('a non numeric value is not a number', () async {
      await store.put('height', 'tall');
      expect(await store.number('height'), isNull);
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

  group('fitness', () {
    test('stores and reads newest first', () async {
      await store.addFitness(const FitnessEntry(day: '2026-01-01', weight: 82));
      await store.addFitness(const FitnessEntry(day: '2026-02-01', weight: 80));
      final list = await store.fitness();
      expect(list.first.day, '2026-02-01');
      expect(list.first.weight, 80);
    });

    test('updates an entry in place', () async {
      final id = await store.addFitness(const FitnessEntry(day: '2026-01-01', weight: 82));
      final entry = (await store.fitness()).first;
      await store.updateFitness(entry.copyWith(id: id, weight: 81));
      expect((await store.fitness()).first.weight, 81);
      expect(await store.fitness(), hasLength(1));
    });

    test('deletes an entry', () async {
      final id = await store.addFitness(const FitnessEntry(day: '2026-01-01', weight: 82));
      await store.deleteFitness(id);
      expect(await store.fitness(), isEmpty);
    });

    test('refreshing the summary includes height and bmi', () async {
      await store.putNumber('height', 2.0);
      await store.addFitness(const FitnessEntry(day: '2026-01-01', weight: 80));
      await store.refreshFitnessSummary();
      expect(await store.get('fitness_summary'), 'weight 80.0kg, BMI 20.0, height 2.00m');
      expect(await store.number('bmi'), 20.0);
    });

    test('a summary with no logs says so', () async {
      await store.refreshFitnessSummary();
      expect(await store.get('fitness_summary'), 'no measurements yet');
    });

    test('a summary without height still reports the weight', () async {
      await store.addFitness(const FitnessEntry(day: '2026-01-01', weight: 80));
      await store.refreshFitnessSummary();
      expect(await store.get('fitness_summary'), 'weight 80.0kg');
    });

    test('deleting the last log resets the summary', () async {
      final id = await store.addFitness(const FitnessEntry(day: '2026-01-01', weight: 80));
      await store.refreshFitnessSummary();
      await store.deleteFitness(id);
      expect(await store.get('fitness_summary'), 'no measurements yet');
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

  group('knowledge', () {
    test('stores and reads back', () async {
      await store.addTopic(const KnowledgeTopic(
        topic: 'Rust',
        progress: 0.25,
        note: 'chapter 4',
        updated: '2026-01-01',
      ));
      final t = (await store.topics()).single;
      expect(t.topic, 'Rust');
      expect(t.progress, 0.25);
      expect(t.percent, 25);
    });

    test('updates progress', () async {
      final id = await store.addTopic(
          const KnowledgeTopic(topic: 'Rust', updated: '2026-01-01'));
      final t = (await store.topics()).single;
      await store.updateTopic(t.copyWith(id: id, progress: 0.9));
      expect((await store.topics()).single.percent, 90);
    });

    test('deletes', () async {
      final id = await store.addTopic(
          const KnowledgeTopic(topic: 'x', updated: '2026-01-01'));
      await store.deleteTopic(id);
      expect(await store.topics(), isEmpty);
    });
  });

  group('drafts', () {
    test('a new draft is pending', () async {
      final id = await store.addDraft(const Draft(title: 'Follow up', body: 'Hi there', created: '2026-01-01'));
      final d = (await store.drafts()).single;
      expect(d.id, id);
      expect(d.status, DraftStatus.pending);
    });

    test('filters by status', () async {
      final id = await store.addDraft(
          const Draft(title: 'a', body: 'b', created: '2026-01-01'));
      await store.setDraftStatus(id, DraftStatus.approved);
      expect(await store.drafts(status: DraftStatus.pending), isEmpty);
      expect(await store.drafts(status: DraftStatus.approved), hasLength(1));
      expect(await store.drafts(), hasLength(1));
    });

    test('deletes', () async {
      final id = await store.addDraft(
          const Draft(title: 'a', body: 'b', created: '2026-01-01'));
      await store.deleteDraft(id);
      expect(await store.drafts(), isEmpty);
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
      await store.put('nickname', 'kami');
      await store.addFitness(const FitnessEntry(day: '2026-01-01', weight: 80));
      await store.addClient(const Client(name: 'x', created: '2026-01-01'));
      await store.addTopic(const KnowledgeTopic(topic: 'x', updated: '2026-01-01'));
      await store.addDraft(const Draft(title: 'x', body: 'y', created: '2026-01-01'));
      await store.addChat(const ChatRecord(role: 'user', text: 'hi', created: '2026-01-01'));

      await store.wipe();

      expect(await store.all(), isEmpty);
      expect(await store.fitness(), isEmpty);
      expect(await store.clients(), isEmpty);
      expect(await store.topics(), isEmpty);
      expect(await store.drafts(), isEmpty);
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
  });
}
