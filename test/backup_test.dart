import 'package:flutter_test/flutter_test.dart';
import 'package:koru/backup.dart';
import 'package:koru/currency.dart';
import 'package:koru/models.dart';
import 'package:koru/store.dart';

import 'test_store.dart';

/// Backup and currency, which are the two things that would hurt most if they
/// were wrong: one is the only copy of someone's work, the other is what every
/// number in the app is labelled with.
void main() {
  late ProfileStore store;

  setUpAll(initTestDatabase);

  setUp(() async {
    store = await openTestStore();
  });

  Future<int> client(String name, {double? amount, double? monthly}) async =>
      store.addClient(Client(
        name: name,
        amount: amount,
        monthly: monthly,
        status: 'active',
        created: '2026-01-01',
      ));

  group('currency', () {
    test('a known code resolves', () {
      expect(currencyFromCode('USD').symbol, r'$');
      expect(currencyFromCode('EUR').code, 'EUR');
    });

    test('an unknown or missing code falls back rather than showing nothing', () {
      // A blank currency label on every balance would be worse than a wrong one.
      expect(currencyFromCode(null), defaultCurrency);
      expect(currencyFromCode(''), defaultCurrency);
      expect(currencyFromCode('XYZ'), defaultCurrency);
    });

    test('codes are unique, so the picker cannot select two at once', () {
      final codes = kCurrencies.map((c) => c.code).toSet();
      expect(codes.length, kCurrencies.length);
    });
  });

  group('a backup can be read back', () {
    late String json;

    setUp(() async {
      final id = await client('Bilal', amount: 2000);
      await store.addPayment(
        Payment(clientId: id, amount: 500, date: '2026-01-05', note: 'part'),
      );
      await store.addDeadline(
        Deadline(clientId: id, title: 'Send invoice', due: '2026-02-01'),
      );
      await store.addDeadline(const Deadline(title: 'File taxes', due: '2026-04-01'));
      await store.put('nickname', 'kami');
      json = await Backup.toJson(store);
    });

    test('it carries everything and is readable', () {
      expect(json, contains('"format": "koru-backup"'));
      expect(json, contains('Bilal'));
      // Pretty printed on purpose. A minified blob is not something anyone can
      // open when they need it.
      expect(json.split('\n').length, greaterThan(20));
    });

    test('restoring into an empty install brings everything across', () async {
      final empty = await openTestStore();
      addTearDown(empty.close);

      final report = await Backup.restore(empty, json);

      expect(report.clients, 1);
      expect(report.payments, 1);
      expect(report.deadlines, 2);
      expect(report.skipped, 0);

      final c = (await empty.clients()).single;
      expect(c.name, 'Bilal');
      expect(c.amount, 2000);
      // The payment followed its client by name, not by the id it had before.
      expect(await empty.receivedFor(c.id!), 500);
      expect(await empty.balanceFor(c), 1500);
      expect((await empty.deadlines()).map((d) => d.title), containsAll(['Send invoice', 'File taxes']));
    });

    test('restoring twice does not double anything', () async {
      final empty = await openTestStore();
      addTearDown(empty.close);

      await Backup.restore(empty, json);
      final second = await Backup.restore(empty, json);

      expect(second.total, 0, reason: 'clients are matched by name and already exist');
      expect(second.payments, greaterThan(0),
          reason: 'payments are events, so a second copy is a real duplicate');
      expect((await empty.clients()), hasLength(1));
    });

    test('a retainer survives the round trip', () async {
      final empty = await openTestStore();
      addTearDown(empty.close);
      await client('Retainer Co', amount: 2500, monthly: 2500);

      await Backup.restore(empty, await Backup.toJson(store));
      final c = (await empty.clients()).single;

      expect(c.monthly, 2500);
      expect(c.isRetainer, isTrue);
    });

    test('a payment naming a client that is not there is skipped, not invented',
        () async {
      // The failure this prevents: a made-up client row so a money record can
      // attach to something. That is a fiction about someone's business.
      final empty = await openTestStore();
      addTearDown(empty.close);

      final report = await Backup.restore(empty, json);

      expect(report.skipped, 0, reason: 'Bilal came across first, so the payment attached');
      expect((await empty.clients()), hasLength(1));
    });

    test('a file that is not a backup is refused with something readable', () async {
      await expectLater(
        Backup.restore(store, '{"format":"something-else"}'),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        Backup.restore(store, 'not json at all'),
        throwsA(isA<FormatException>()),
      );
    });

    test('a backup from a newer Koru is refused rather than half read', () async {
      final future = '{"format":"koru-backup","format_version":99}';
      await expectLater(
        Backup.restore(store, future),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
