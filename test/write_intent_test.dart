import 'package:flutter_test/flutter_test.dart';
import 'package:koru/local/write_intent.dart';

/// The parser guards the write path, so it is tested adversarially: every case
/// here is a sentence that could plausibly corrupt a ledger if it parsed the
/// wrong way, or silently do nothing when it should have asked.
void main() {
  const parser = WriteIntentParser();

  WriteIntent? parse(String s) => parser.parse(s);

  group('refuses anything that is not an instruction', () {
    final questions = [
      'How much does Bilal owe?',
      'Who owes me money?',
      'What is outstanding?',
      'When is the invoice due?',
      'Did Bilal pay?',
      'Should I chase Acme?',
      'Which client is late?',
      'Am I making money?',
      'Is Acme late?',
    ];
    for (final q in questions) {
      test('"$q" writes nothing', () {
        expect(parse(q), isNull, reason: 'a question must never be a command');
      });
    }

    test('chatter writes nothing', () {
      expect(parse('thanks, that helps'), isNull);
      expect(parse(''), isNull);
      expect(parse('   '), isNull);
      expect(parse('hello'), isNull);
    });

    test('a statement with no write verb writes nothing', () {
      expect(parse('Bilal is a difficult client'), isNull);
      expect(parse('the site launch slipped to next month'), isNull);
    });
  });

  group('adding a client', () {
    test('reads a name and an invoice', () {
      final intent = parse('add client Bilal for 2000') as AddClientIntent;
      expect(intent.name, 'Bilal');
      expect(intent.amount, 2000);
    });

    test('accepts the longer phrasings', () {
      expect((parse('add a new client called Acme Studio') as AddClientIntent).name,
          'Acme Studio');
      expect((parse('log client Sara') as AddClientIntent).name, 'Sara');
      expect((parse('create a customer Northwind Traders') as AddClientIntent).name,
          'Northwind Traders');
    });

    test('keeps the name free of a trailing clause', () {
      final intent = parse('add client Bilal with a website redesign') as AddClientIntent;
      expect(intent.name, 'Bilal');
    });

    test('reads a grouped amount', () {
      expect((parse('add client Acme for 12,500') as AddClientIntent).amount, 12500);
    });

    test('a name with no amount is still a client', () {
      final intent = parse('add client Prospective Ltd') as AddClientIntent;
      expect(intent.name, 'Prospective Ltd');
      expect(intent.amount, isNull);
    });

    test('declines rather than inventing a name from numbers alone', () {
      expect(parse('add client 2000'), isNull);
    });

    test('reads a due date', () {
      final intent = parse('add client Bilal for 2000 due 2026-04-01') as AddClientIntent;
      expect(intent.due, '2026-04-01');
      expect(intent.amount, 2000);
    });
  });

  group('recording a payment', () {
    test('reads a name and an amount', () {
      final intent = parse('Bilal paid 500') as RecordPaymentIntent;
      expect(intent.clientName, 'Bilal');
      expect(intent.amount, 500);
    });

    test('handles the "paid me" shape', () {
      final intent = parse('Bilal paid me 500') as RecordPaymentIntent;
      expect(intent.clientName, 'Bilal');
      expect(intent.amount, 500);
    });

    test('handles a two word client name', () {
      final intent = parse('Acme Studio paid 1200') as RecordPaymentIntent;
      expect(intent.clientName, 'Acme Studio');
      expect(intent.amount, 1200);
    });

    test('handles the explicit recording shape', () {
      final intent =
          parse('record a payment of 750 from Acme Studio') as RecordPaymentIntent;
      expect(intent.clientName, 'Acme Studio');
      expect(intent.amount, 750);
    });

    test('handles the explicit shape with currency', () {
      final intent =
          parse('record a payment of 750 AED from Acme') as RecordPaymentIntent;
      expect(intent.clientName, 'Acme');
      expect(intent.amount, 750);
    });

    test('a payment with no amount leaves it blank rather than guessing', () {
      final intent = parse('Bilal paid') as RecordPaymentIntent;
      expect(intent.clientName, 'Bilal');
      expect(intent.amount, isNull);
    });

    test('handles mark as paid', () {
      final intent = parse('mark Acme as paid') as RecordPaymentIntent;
      expect(intent.clientName, 'Acme');
    });

    test('reads a grouped amount', () {
      expect((parse('Bilal paid 2,000') as RecordPaymentIntent).amount, 2000);
    });
  });

  group('adding a deadline', () {
    test('reads a title', () {
      final intent = parse('add a deadline to send the invoice') as AddDeadlineIntent;
      expect(intent.title, 'send the invoice');
    });

    test('reads a title and a date', () {
      final intent =
          parse('add a deadline to send the invoice on friday') as AddDeadlineIntent;
      expect(intent.title, 'send the invoice');
      expect(intent.due, isNotNull);
    });

    test('reads an explicit ISO date', () {
      final intent =
          parse('add a deadline to deliver the site by 2026-05-04') as AddDeadlineIntent;
      expect(intent.due, '2026-05-04');
      expect(intent.title, 'deliver the site');
    });

    test('reads a relative date', () {
      final intent =
          parse('remind me to chase Bilal in 3 days') as AddDeadlineIntent;
      expect(intent.title, 'chase Bilal');
      expect(intent.due, isNotNull);
      final due = DateTime.parse(intent.due!);
      final today = DateTime.now();
      expect(due.difference(DateTime(today.year, today.month, today.day)).inDays, 3);
    });

    test('handles a reminder phrasing', () {
      final intent = parse('remind me to send the contract') as AddDeadlineIntent;
      expect(intent.title, 'send the contract');
    });
  });

  group('does not confuse one write for another', () {
    test('a deadline mentioning a client is a deadline, not a payment', () {
      final intent =
          parse('add a deadline to call Bilal about the 2000 invoice') as AddDeadlineIntent;
      expect(intent, isA<AddDeadlineIntent>());
      expect(intent.title, 'call Bilal about the 2000 invoice');
    });

    test('a deadline beats the client cue', () {
      // "add a deadline to add client work" would otherwise read as adding a
      // client called "work".
      final intent = parse('add a deadline to add client work') as AddDeadlineIntent;
      expect(intent.title, 'add client work');
    });

    test('adding a client is not a payment', () {
      expect(parse('add client Bilal'), isA<AddClientIntent>());
    });

    test('the first cue wins when two are present', () {
      final intent = parse('add client Acme for 3000') as AddClientIntent;
      expect(intent.amount, 3000);
    });
  });

  group('summaries read as a confirmation', () {
    test('describe the write without ambiguity', () {
      expect((parse('add client Bilal for 2000') as AddClientIntent).summary,
          'Add Bilal, invoiced 2000');
      expect((parse('Bilal paid 500') as RecordPaymentIntent).summary,
          'Record 500 from Bilal');
      expect((parse('add client Sara') as AddClientIntent).summary,
          'Add a client called Sara');
    });

    test('a part amount is not rounded away', () {
      expect((parse('Bilal paid 500.50') as RecordPaymentIntent).summary,
          'Record 500.50 from Bilal');
    });
  });
}