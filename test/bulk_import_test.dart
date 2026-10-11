import 'package:flutter_test/flutter_test.dart';
import 'package:koru/local/bulk_import.dart';

/// A pasted list of clients, read into rows.
///
/// The rule that matters most here is the refusal. Every earlier version of this
/// app accepted data that was empty and then behaved as though the user had
/// given it nothing, and the symptom was a Business page reading zero with no
/// way to tell why. So a line with no amount is refused and said out loud.
void main() {
  const parser = BulkClientParser();

  ImportResult parse(String s) => parser.parse(s);

  group('one row per line', () {
    test('name and amount separated by a space', () {
      final r = parse('Bilal 3000');
      expect(r.rows.single.name, 'Bilal');
      expect(r.rows.single.amount, 3000);
      expect(r.problems, isEmpty);
    });

    test('separated by a dash', () {
      final r = parse('Bilal - 3000');
      expect(r.rows.single.name, 'Bilal');
      expect(r.rows.single.amount, 3000);
    });

    test('separated by a comma', () {
      final r = parse('Acme, 5000, net 30');
      final row = r.rows.single;
      expect(row.name, 'Acme');
      expect(row.amount, 5000);
      expect(row.termsDays, 30);
    });

    test('a two word name survives', () {
      // Stopping at the first word would drop half the company.
      final r = parse('Acme Studio 5000');
      expect(r.rows.single.name, 'Acme Studio');
      expect(r.rows.single.amount, 5000);
    });

    test('grouped figures work', () {
      expect(parse('Northwind 12,500').rows.single.amount, 12500);
    });

    test('list bullets are not part of the name', () {
      for (final bullet in ['- Bilal 3000', '* Bilal 3000', '• Bilal 3000', '1. Bilal 3000']) {
        final r = parse(bullet);
        expect(r.rows.single.name, 'Bilal', reason: 'from "$bullet"');
        expect(r.rows.single.amount, 3000);
      }
    });

    test('several lines at once', () {
      final r = parse('Bilal 3000\nAcme 5000\nLumen 1500');
      expect(r.rows.map((x) => x.name), ['Bilal', 'Acme', 'Lumen']);
      expect(r.problems, isEmpty);
    });
  });

  group('terms and dates', () {
    test('net N becomes terms, not an amount', () {
      final row = parse('Acme 5000 net 30').rows.single;
      expect(row.amount, 5000, reason: 'the 30 is days, not money');
      expect(row.termsDays, 30);
    });

    test('an iso date becomes the due date', () {
      final row = parse('Bilal - 3000 - due 2026-11-01').rows.single;
      expect(row.name, 'Bilal');
      expect(row.amount, 3000);
      expect(row.due, '2026-11-01');
    });

    test('the derived date follows the terms', () {
      final row = parse('Acme 5000 net 30').rows.single;
      final client = row.toClient(invoicedOn: DateTime(2026, 10, 1));
      expect(client.dueDate, DateTime(2026, 10, 31));
    });
  });

  group('deposits and retainers', () {
    test('a deposit is read separately from the agreed amount', () {
      final row = parse('Lumen 5000 deposit 2000').rows.single;
      expect(row.amount, 5000);
      expect(row.deposit, 2000);
    });

    test('a retainer line is not refused for having no one-off amount', () {
      final row = parse('Northwind retainer 1500').rows.single;
      expect(row.retainer, isTrue);
      expect(row.amount, 1500);
      final client = row.toClient();
      expect(client.isRetainer, isTrue);
    });
  });

  group('what it refuses, and says why', () {
    test('a line with no amount is refused, not accepted empty', () {
      // This is the zeros bug. Accepting it would add a client that owes
      // nothing, is never overdue, and makes every total on the page wrong.
      final r = parse('Bilal');
      expect(r.rows, isEmpty);
      expect(r.problems.single.reason, contains('no amount'));
    });

    test('a line with an amount and no name is refused', () {
      final r = parse('3000');
      expect(r.rows, isEmpty);
      expect(r.problems.single.reason, contains('no name'));
    });

    test('nothing is ever dropped without being listed', () {
      final r = parse('Bilal 3000\nthis line makes no sense\nAcme 5000');
      expect(r.rows, hasLength(2));
      expect(r.problems, hasLength(1));
      expect(r.problems.single.text, 'this line makes no sense');
    });

    test('a heading is not shouted about', () {
      // Someone setting up a list writes a heading, not a broken row.
      final r = parse('My clients:\nBilal 3000');
      expect(r.rows, hasLength(1));
      expect(r.problems, isEmpty);
    });

    test('blank lines are not rows and not problems', () {
      final r = parse('\n\nBilal 3000\n\n');
      expect(r.rows, hasLength(1));
      expect(r.problems, isEmpty);
    });
  });

  group('duplicates', () {
    test('the same name twice is left for the user to decide', () {
      // Silently collapsing them would hide a real mistake in the source list.
      final r = parse('Bilal 3000\nBilal 4000');
      expect(r.rows, hasLength(2));
    });
  });
}