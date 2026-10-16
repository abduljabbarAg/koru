import 'package:flutter_test/flutter_test.dart';
import 'package:koru/local/local_assistant.dart';
import 'package:koru/models.dart';

void main() {
  const a = LocalAssistant();

  LocalFacts facts({List<Client> clients = const [], bool rich = true}) =>
      LocalFacts(
        nickname: 'kami',
        lifeStage: 'running a business',
        goals: 'two more clients',
        today: DateTime(2026, 3, 1),
        clients: rich
            ? (clients.isEmpty
                ? const [
                    Client(
                      id: 1,
                      name: 'Acme',
                      status: 'delivered',
                      amount: 1500,
                      due: '2026-02-01',
                      created: '2026-01-01',
                    ),
                    Client(
                      id: 2,
                      name: 'Globex',
                      status: 'lead',
                      amount: 900,
                      created: '2026-01-02',
                    ),
                    Client(
                      id: 3,
                      name: 'Initech',
                      status: 'paid',
                      amount: 500,
                      created: '2026-01-03',
                    ),
                  ]
                : clients)
            : const [],
        received: rich ? const {3: 500} : const {},
        deadlines: rich
            ? const [Deadline(title: 'Send invoice', due: '2026-03-05')]
            : const [],
      );

  String ask(String q, {LocalFacts? f, String? previous}) =>
      a.answer(question: q, facts: f ?? facts(), previousQuestion: previous).text;

  group('advice intents are domain-aware and substantial', () {
    final table = <String, List<String>>{
      'how much should I charge for a logo': ['quote', 'day', 'third'],
      'what should my day rate be': ['rate', 'say'],
      'should I invoice them yet': ['invoice', 'delivered'],
      "they haven't paid me what do I do": ['step', 'today'],
      'do I need to register for vat': ['vat', 'accountant'],
      'my cash flow is a mess': ['cash', 'chasing'],
      'should I take a deposit': ['deposit', 'half', 'front'],
      'how do retainers work': ['retainer', 'month'],
      'they keep asking for extra work': ['scope', 'change order'],
      'how do I say no to a job': ['say', 'warm', 'fast'],
      'they want a discount': ['price', 'value', 'move'],
      'the client questioned my invoice': ['warmth', 'specifics', 'numbers'],
      'should I give them a refund': ['refund', 'earned'],
      'they cancelled the project halfway': ['cancel', 'deposit', 'kill fee'],
      'do I need a contract': ['contract', 'writing', 'scope'],
      'how do I onboard a new client': ['first', 'week', 'client'],
      'how long will this project take': ['day', 'time', 'long'],
      'I am swamped': ['work', 'say no', 'money'],
      'should I hire someone': ['hire', 'subcontract', 'trial'],
      'what invoicing software do you recommend': ['tool', 'invoice'],
      'draft a chase message': ['message', 'invoice', 'day'],
    };

    table.forEach((question, markers) {
      test('"$question" answers in its own domain', () {
        final out = ask(question);
        expect(out.length, greaterThan(150),
            reason: 'too short to be real advice: $out');
        final lower = out.toLowerCase();
        expect(lower, isNot(startsWith('i can help')));
        expect(lower, isNot(startsWith('happy to help')));
        expect(lower, isNot(startsWith('as an ai')));
        expect(lower, isNot(contains('as an ai language model')));
        final hits = markers.where(lower.contains).toList();
        expect(hits.length, greaterThanOrEqualTo(1),
            reason: 'expected one of $markers, got none in: $out');
        final hasConcrete = RegExp(r'\d').hasMatch(out) ||
            lower.contains('example') ||
            lower.contains('e.g.') ||
            lower.contains('for instance') ||
            lower.contains('say') ||
            lower.contains('like') ||
            lower.contains('one') ||
            lower.contains('first');
        expect(hasConcrete, isTrue, reason: 'no concrete number/example: $out');
      });
    });
  });

  group('negation', () {
    test('"don\'t invoice yet" acknowledges the hold, not a lecture on invoicing', () {
      final out = ask("don't invoice yet");
      expect(out.toLowerCase(), contains('holding'));
      expect(out.toLowerCase(), contains('invoice'));
      expect(out.length, greaterThan(100));
    });

    test('"should I hold off on chasing them?" is a hold, not a chase list', () {
      final out = ask('should I hold off on chasing them?');
      final lower = out.toLowerCase();
      expect(lower, contains('chas'));
      expect(
        ['hold', 'wait', 'hmm', 'not yet', 'before', 'leave them alone',
                'put a date', 'look again']
            .any(lower.contains),
        isTrue,
        reason: 'expected a cautious answer, got: $out',
      );
      expect(lower, isNot(contains('chase these first')));
    });
  });

  group('multi-part and follow-up turns', () {
    test('a two-part question gets both parts', () {
      final out = ask('how much should I charge and should I take a deposit');
      expect(out.toLowerCase(), contains('quote'));
      expect(
        ['deposit', 'half', 'up front']
            .any((k) => out.toLowerCase().contains(k)),
        isTrue,
        reason: 'missing deposit note: $out',
      );
    });

    test('a two-part question with facts names both the quote and the deposit', () {
      final out = ask('how much should I charge and should I take a deposit');
      expect(out.toLowerCase(), contains('deposit'));
      expect(out.length, greaterThan(300));
    });

    test('"what about the VAT?" after a quote question answers VAT', () {
      final out = ask('what about the VAT?',
          previous: 'how much should I charge for a logo');
      expect(out.toLowerCase(), contains('vat'));
      expect(out.toLowerCase(), isNot(contains('day rate')));
    });

    test('a bare follow-up prefers the records side of the business', () {
      final out = ask('what about the invoice?',
          previous: 'should I take a deposit');
      expect(out.toLowerCase(), contains('invoice'));
    });
  });

  group('vague, off-topic and unmatched input', () {
    for (final q in ['huh', 'what', 'idk', 'um']) {
      test('"$q" gets a clarifying question with options', () {
        final out = ask(q);
        expect(out, contains('?'));
        expect(
          ['owe', 'chase', 'due', 'client', 'Acme']
              .any((k) => out.toLowerCase().contains(k.toLowerCase())),
          isTrue,
          reason: 'expected a record-grounded prompt, got: $out',
        );
        expect(out.toLowerCase(), isNot(startsWith('i could not')));
      });
    }

    test('pure punctuation is treated as unclear, not an error', () {
      final out = ask('???');
      expect(out.toLowerCase(), contains('did not get'));
      expect(out, contains('?'));
    });

    for (final q in ['write me a poem about the sea', 'blah blah blah whatever']) {
      test('"$q" gets the honest fallback with a route back', () {
        final out = ask(q);
        expect(out.toLowerCase(), contains('could not'));
        expect(
          ['business', 'money', 'owe', 'charge', 'invoice']
              .any((k) => out.toLowerCase().contains(k)),
          isTrue,
          reason: 'no route back to the domain: $out',
        );
        expect(a.answer(question: q, facts: facts()).suggestCloud, isTrue);
      });
    }

    test('unrelated chatter still sounds like the same person', () {
      final out = ask('the weather looks awful today');
      expect(
        ['weather', 'curtains', 'diary']
            .any((k) => out.toLowerCase().contains(k)),
        isTrue,
      );
      expect(out.toLowerCase(), isNot(startsWith('as an ai')));
    });
  });

  group('advice answers use the records where they exist', () {
    test('the chase draft names the overdue client, amount and days late', () {
      final out = ask('draft a chase message');
      expect(out, contains('Acme'));
      expect(out, contains('1500'));
      expect(out, contains('28 days late'));
    });

    test('cash flow advice starts from the money actually on file', () {
      final out = ask('my cash flow is a mess');
      expect(out, contains('2400'));
      expect(out, contains('2 clients'));
    });

    test('a retainer question notices there are no retainers yet', () {
      final out = ask('how do retainers work');
      expect(out.toLowerCase(), contains('no retainers'));
    });

    test('timeline advice mentions the open deadline', () {
      final out = ask('how long will this project take');
      expect(out, contains('1 open deadline'));
    });
  });

  group('voice', () {
    final battery = [
      'how much should I charge',
      'they want a discount',
      'do I need a contract',
      'what invoicing software do you recommend',
      'I am swamped',
      'what about the VAT',
      'huh',
      'bye',
      'thanks',
    ];
    test('no reply in the battery opens with the AI hedge', () {
      for (final q in battery) {
        final out = ask(q).toLowerCase();
        expect(out, isNot(startsWith('as an ai')), reason: 'for "$q"');
        expect(out, isNot(contains('language model')), reason: 'for "$q"');
        expect(out, isNot(contains('i cannot provide')), reason: 'for "$q"');
      }
    });

    test('goodbye, thanks and greetings stay warm and short', () {
      expect(ask('bye').length, lessThan(80));
      expect(ask('thanks').toLowerCase(), contains('help'));
      expect(ask('hi').toLowerCase(), contains('kami'));
    });
  });
}
