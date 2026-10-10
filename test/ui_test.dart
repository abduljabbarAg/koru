import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koru/models.dart';
import 'package:koru/screens/business.dart';
import 'package:koru/screens/client_detail.dart';
import 'package:koru/secrets.dart';
import 'package:koru/state.dart';
import 'package:koru/store.dart';

import 'test_store.dart';

/// The Business screen and the client screen that hangs off it, driven the way
/// a person would drive them: tap, scroll, read what is on screen, then confirm
/// against the database.
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

  /// Mounts a screen inside the overrides every test here needs.
  Future<void> mount(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storeProvider.overrideWith((ref) async => store),
          cloudKeyProvider.overrideWith((ref, providerId) async => ''),
          secretsProvider.overrideWithValue(MemoryKeyStore()),
        ],
        child: MaterialApp(home: child),
      ),
    );
    await pump(tester);
  }

  Future<int> seed(
    WidgetTester tester, {
    required String name,
    double? amount,
    String status = 'delivered',
    double? monthly,
    String created = '2026-01-01',
    String? due,
  }) async {
    final id = await store.addClient(Client(
      name: name,
      amount: amount,
      status: status,
      monthly: monthly,
      created: created,
      due: due,
    ));
    return id;
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

  group('the capacity meter', () {
    testWidgets('counts work under way and not leads or settled clients',
        (tester) async {
      await store.putNumber('capacity', 4);
      await seed(tester, name: 'Active One', amount: 100, status: 'active');
      await seed(tester, name: 'Delivered One', amount: 100, status: 'delivered');
      await seed(tester, name: 'A Lead', amount: 100, status: 'lead');
      await seed(tester, name: 'Settled', amount: 100, status: 'paid');

      await mount(tester, const BusinessScreen());

      // Two, not four: a lead is a hope and a settled client is history.
      expect(find.text('2 of 4'), findsOneWidget);
      // And not three: an active client who owes money is one client, not two.
      expect(find.text('3 of 4'), findsNothing);
      expect(find.text('2 free'), findsOneWidget);
    });

    testWidgets('says plainly when you are at the limit', (tester) async {
      await store.putNumber('capacity', 1);
      await seed(tester, name: 'Only One', amount: 100, status: 'active');

      await mount(tester, const BusinessScreen());

      expect(find.text('1 of 1'), findsOneWidget);
      expect(find.text('at capacity'), findsOneWidget);
      expect(find.textContaining('before taking more'), findsOneWidget);
    });

    testWidgets('falls back to five when nothing was ever chosen', (tester) async {
      await seed(tester, name: 'Only One', amount: 100, status: 'active');
      await mount(tester, const BusinessScreen());
      expect(find.text('1 of 5'), findsOneWidget);
    });
  });

  group('the pipeline', () {
    testWidgets('lists leads and active work oldest first', (tester) async {
      await seed(tester, name: 'Newer', status: 'lead', created: '2026-05-01');
      await seed(tester, name: 'Older', status: 'active', created: '2026-01-01');
      await seed(tester, name: 'Settled', status: 'paid', created: '2026-01-01');

      await mount(tester, const BusinessScreen());

      expect(find.text('Pipeline (2)'), findsOneWidget);
      // The settled client is not in the pipeline.
      expect(find.text('Settled'), findsOneWidget, reason: 'still in the client list');
    });

    testWidgets('marks a prospect that has gone cold', (tester) async {
      final old = DateTime.now().subtract(const Duration(days: 40));
      await seed(
        tester,
        name: 'Gone Cold',
        status: 'lead',
        created: '${old.year}-01-01',
      );

      await mount(tester, const BusinessScreen());
      await tapVisible(tester, find.text('Gone Cold'));

      expect(find.text('Gone Cold'), findsWidgets);
    });
  });

  group('the client screen', () {
    testWidgets('shows the balance, the payments and the deadlines',
        (tester) async {
      final id = await seed(tester, name: 'Acme', amount: 3000, status: 'delivered');
      await store.addPayment(Payment(clientId: id, amount: 1200, date: '2026-02-01', note: 'part'));
      await store.addDeadline(Deadline(clientId: id, title: 'Send invoice', due: '2026-06-01'));

      await mount(tester, const ClientDetailScreen(clientId: 1));

      expect(find.text('Acme'), findsOneWidget);
      expect(find.text('1800'), findsOneWidget, reason: 'invoiced 3000, received 1200');
      expect(find.text('1 recorded'), findsOneWidget);
      expect(find.text('Send invoice'), findsOneWidget);
    });

    testWidgets('a retainer shows what it costs and when it is next due',
        (tester) async {
      final id = await seed(
        tester,
        name: 'Retainer Co',
        status: 'active',
        monthly: 2500,
        amount: 2500,
      );
      await store.addPayment(Payment(clientId: id, amount: 2500, date: '2026-01-15'));

      await mount(tester, const ClientDetailScreen(clientId: 1));

      expect(find.textContaining('per month'), findsOneWidget);
      expect(find.textContaining('Next due'), findsOneWidget);
      expect(find.text('RETAINER'), findsOneWidget);
    });

    testWidgets('a retainer that has never been paid says so', (tester) async {
      await seed(tester, name: 'Quiet Co', status: 'active', monthly: 1500, amount: 1500);

      await mount(tester, const ClientDetailScreen(clientId: 1));

      expect(find.textContaining('Never paid'), findsOneWidget);
    });

    testWidgets('tapping a payment undo removes it', (tester) async {
      final id = await seed(tester, name: 'Acme', amount: 500, status: 'delivered');
      await store.addPayment(Payment(clientId: id, amount: 500, date: '2026-02-01'));

      await mount(tester, const ClientDetailScreen(clientId: 1));
      await tapVisible(tester, find.byTooltip('Undo this payment'));

      expect(await tester.runAsync(() => store.payments()), isEmpty);
    });

    testWidgets('a deleted client does not crash the screen', (tester) async {
      await mount(tester, const ClientDetailScreen(clientId: 999));
      expect(find.text('That client is gone'), findsOneWidget);
    });
  });

  group('editing a client', () {
    testWidgets('a retainer can be set and cleared', (tester) async {
      await seed(tester, name: 'Acme', amount: 100, status: 'active');
      await mount(tester, const BusinessScreen());

      await tapVisible(tester, find.text('Edit'));
      await pump(tester);

      expect(find.text('Monthly retainer'), findsOneWidget);
      await tapVisible(tester, find.text('Save changes'));

      final client = (await tester.runAsync(() => store.clients()))!.single;
      expect(client.monthly, isNull);
    });
  });
}
