import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koru/attention.dart';
import 'package:koru/attention_bridge.dart';
import 'package:koru/deep_link.dart';
import 'package:koru/models.dart';

/// What counts as worth interrupting someone about.
///
/// These rules decide when Koru makes noise on a lock screen, so they are the
/// easiest thing in the app to get wrong in a way nobody notices. A rule that
/// fires too often does not feel broken, it feels like a nag, and the response
/// to a nag is to uninstall. So the quiet cases are tested as deliberately as
/// the loud ones.
void main() {
  final today = DateTime(2026, 10, 11);

  Client client(String name, {String? due, String status = 'delivered', double amount = 1000}) =>
      Client(id: name.hashCode, name: name, due: due, status: status, amount: amount);

  group('money', () {
    test('an overdue balance is worth saying out loud', () {
      final items = Attention.build(
        clients: [client('Bilal', due: '2026-10-01')],
        deadlines: const [],
        received: const {},
        today: today,
      );
      final item = items.single;
      expect(item.kind, AttentionKind.overdueMoney);
      expect(item.detail, contains('1000'));
      expect(item.target, AttentionTarget.client);
    });

    test('a client with nothing owing is not chased', () {
      final items = Attention.build(
        clients: [
          const Client(
              id: 1,
              name: 'Bilal',
              due: '2026-10-01',
              status: 'delivered',
              amount: 500,
              created: '')
        ],
        deadlines: const [],
        received: const {1: 500},
        today: today,
      );
      expect(items, isEmpty, reason: 'they paid, so there is nothing to say');
    });

    test('a paid or lost client is never overdue', () {
      final items = Attention.build(
        clients: [
          client('Bilal', due: '2026-01-01', status: 'paid'),
          client('Acme', due: '2026-01-01', status: 'lost'),
        ],
        deadlines: const [],
        received: const {},
        today: today,
      );
      expect(items, isEmpty);
    });

    test('not yet due is not overdue', () {
      final items = Attention.build(
        clients: [client('Bilal', due: '2026-12-01')],
        deadlines: const [],
        received: const {},
        today: today,
      );
      expect(items, isEmpty);
    });
  });

  group('deadlines', () {
    test('due today outranks due soon', () {
      final items = Attention.build(
        clients: const [],
        deadlines: [
          const Deadline(title: 'Soon', due: '2026-10-13'),
          const Deadline(title: 'Today', due: '2026-10-11'),
        ],
        received: const {},
        today: today,
      );
      expect(items.first.title, 'Today');
      expect(items.first.detail, 'Due today');
    });

    test('a past deadline says how many days late', () {
      final items = Attention.build(
        clients: const [],
        deadlines: [const Deadline(title: 'Invoice', due: '2026-10-09')],
        received: const {},
        today: today,
      );
      expect(items.single.detail, '2 days overdue');
    });

    test('one day late is not "1 days"', () {
      final items = Attention.build(
        clients: const [],
        deadlines: [const Deadline(title: 'Invoice', due: '2026-10-10')],
        received: const {},
        today: today,
      );
      expect(items.single.detail, '1 day overdue');
    });

    test('tomorrow reads as one day', () {
      final items = Attention.build(
        clients: const [],
        deadlines: [const Deadline(title: 'Call', due: '2026-10-12')],
        received: const {},
        today: today,
      );
      expect(items.single.detail, 'Due in 1 day');
    });

    test('a finished deadline says nothing ever again', () {
      final items = Attention.build(
        clients: const [],
        deadlines: [const Deadline(title: 'Done', due: '2026-10-01', done: true)],
        received: const {},
        today: today,
      );
      expect(items, isEmpty);
    });

    test('beyond the soon window it is not urgent', () {
      final items = Attention.build(
        clients: const [],
        deadlines: [const Deadline(title: 'Later', due: '2026-11-30')],
        received: const {},
        today: today,
      );
      expect(items, isEmpty);
    });
  });

  group('projects', () {
    test('a project with no note for a while is mentioned, quietly', () {
      final items = Attention.build(
        clients: const [],
        deadlines: const [],
        received: const {},
        projects: const [
          Project(name: 'My app', updated: '2026-09-01T00:00:00Z', created: '2026-09-01'),
        ],
        today: today,
      );
      final item = items.single;
      expect(item.kind, AttentionKind.stalledProject);
      expect(item.detail, 'No note for 40 days');
    });

    test('a recently touched project is not mentioned', () {
      final items = Attention.build(
        clients: const [],
        deadlines: const [],
        received: const {},
        projects: const [
          Project(name: 'My app', updated: '2026-10-09T00:00:00Z', created: '2026-10-01'),
        ],
        today: today,
      );
      expect(items, isEmpty);
    });

    test('a stalled project never outranks money', () {
      final items = Attention.build(
        clients: [client('Bilal', due: '2026-10-01')],
        deadlines: const [],
        received: const {},
        projects: const [
          Project(name: 'My app', updated: '2026-01-01T00:00:00Z', created: '2026-01-01'),
        ],
        today: today,
      );
      expect(items.first.kind, AttentionKind.overdueMoney);
      expect(items.last.kind, AttentionKind.stalledProject);
    });

    test('a finished project is not stalled, it is finished', () {
      final items = Attention.build(
        clients: const [],
        deadlines: const [],
        received: const {},
        projects: const [
          Project(
              name: 'Shipped',
              status: 'done',
              updated: '2026-01-01T00:00:00Z',
              created: '2026-01-01'),
        ],
        today: today,
      );
      expect(items, isEmpty);
    });
  });

  group('the payload handed to Android', () {
    // The channel is mocked rather than absent, because the thing worth
    // checking is what actually crosses into the platform. Letting it fail with
    // "no plugin" only proved that a missing plugin does not throw, which is
    // true and not interesting.
    late MethodChannel channel;
    late List<MethodCall> calls;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      channel = const MethodChannel('koru/attention');
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    Map<String, dynamic> payloadOf(MethodCall call) =>
        jsonDecode(call.arguments['payload'] as String) as Map<String, dynamic>;

    testWidgets('carries the count, the headline and the worst thing',
        (tester) async {
      const bridge = AttentionBridge();
      final items = Attention.build(
        clients: [client('Bilal', due: '2026-10-01')],
        deadlines: const [],
        received: const {},
        today: today,
      );

      final ok = await bridge.publish(
        items,
        link: KoruDeepLink(
            kind: items.first.kind, target: items.first.target),
      );

      expect(ok, isTrue);
      expect(calls.single.method, 'update');
      final payload = payloadOf(calls.single);
      expect(payload['count'], 1);
      expect(payload['headline'], '1 client owes you');
      expect(payload['top'], startsWith('Bilal owes you'));
      expect(payload['link'], 'koru://attention/overdueMoney/client');
    });

    testWidgets('repaints the widget from the same list', (tester) async {
      const bridge = AttentionBridge();
      final items = Attention.build(
        clients: [client('Bilal', due: '2026-10-01')],
        deadlines: const [],
        received: const {},
        today: today,
      );
      await bridge.updateWidget(items);

      final args = calls.single.arguments as Map;
      expect(calls.single.method, 'updateWidget');
      expect(args['count'], 1);
      expect(args['mood'], 'thinking',
          reason: 'a widget with a calm face over an overdue invoice is worse '
              'than no widget');
    });

    testWidgets('nothing outstanding is still published, with no link',
        (tester) async {
      // The quiet state has to reach the platform too, or the badge keeps
      // yesterday's count on the icon after everything is dealt with.
      const bridge = AttentionBridge();
      await bridge.publish(const []);

      final payload = payloadOf(calls.single);
      expect(payload['count'], 0);
      expect(payload['headline'], '');
      expect(payload['top'], '');
      expect(payload['link'], isNull,
          reason: 'nothing to open is not the same as opening nothing');
    });
  });

  group('a tap on a notification survives a cold start', () {
    test('round trips', () {
      const link = KoruDeepLink(
          kind: AttentionKind.overdueMoney, target: AttentionTarget.client, id: 7);
      final back = KoruDeepLink.decode(link.encode())!;
      expect(back.kind, AttentionKind.overdueMoney);
      expect(back.target, AttentionTarget.client);
      expect(back.id, 7);
    });

    test('works without an id', () {
      const link =
          KoruDeepLink(kind: AttentionKind.dueToday, target: AttentionTarget.chat);
      final back = KoruDeepLink.decode(link.encode())!;
      expect(back.id, isNull);
      expect(back.kind, AttentionKind.dueToday);
    });

    test('a link that is not ours is ignored, not thrown at', () {
      // These arrive from outside the app. A crash on launch because of a bad
      // string is a much worse outcome than opening the home screen.
      expect(KoruDeepLink.decode(null), isNull);
      expect(KoruDeepLink.decode('https://example.com'), isNull);
      expect(KoruDeepLink.decode('koru://something/else/1/2'), isNull);
      expect(KoruDeepLink.decode('koru://attention/nonsense/client'), isNull);
      expect(KoruDeepLink.decode('not a uri at all'), isNull);
      expect(KoruDeepLink.decode(''), isNull);
    });
  });

  group('the character\'s mood', () {
    test('cheerful when nothing needs you', () {
      expect(AttentionBridge.moodFor(const []), 'cheer');
    });

    test('thinking when money or a deadline is involved', () {
      final money = Attention.build(
        clients: [client('Bilal', due: '2026-10-01')],
        deadlines: const [],
        received: const {},
        today: today,
      );
      final due = Attention.build(
        clients: const [],
        deadlines: [const Deadline(title: 'Invoice', due: '2026-10-11')],
        received: const {},
        today: today,
      );
      expect(AttentionBridge.moodFor(money), 'thinking');
      expect(AttentionBridge.moodFor(due), 'thinking');
    });

    test('a quiet project alone is not urgent', () {
      final quiet = Attention.build(
        clients: const [],
        deadlines: const [],
        received: const {},
        projects: const [
          Project(name: 'My app', updated: '2026-01-01T00:00:00Z', created: '2026-01-01'),
        ],
        today: today,
      );
      expect(quiet.single.kind, AttentionKind.stalledProject);
      expect(AttentionBridge.moodFor(quiet), 'wave');
    });
  });

  group('the notification text', () {
    test('counts people rather than naming them', () {
      final items = Attention.build(
        clients: [
          client('Bilal', due: '2026-10-01'),
          client('Acme', due: '2026-10-02'),
        ],
        deadlines: const [],
        received: const {},
        today: today,
      );
      expect(Attention.headline(items), '2 clients owe you');
    });

    test('one client reads naturally', () {
      final items = Attention.build(
        clients: [client('Bilal', due: '2026-10-01')],
        deadlines: const [],
        received: const {},
        today: today,
      );
      expect(Attention.headline(items), '1 client owes you');
    });

    test('nothing to say means no notification at all', () {
      expect(Attention.headline(const []), '');
      expect(Attention.top(const []), '');
    });

    test('the lock screen line names the worst thing', () {
      final items = Attention.build(
        clients: [client('Bilal', due: '2026-10-01')],
        deadlines: [const Deadline(title: 'Send invoice', due: '2026-10-11')],
        received: const {},
        today: today,
      );
      expect(Attention.top(items), startsWith('Bilal owes you'));
    });
  });
}