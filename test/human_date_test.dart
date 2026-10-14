import 'package:flutter_test/flutter_test.dart';
import 'package:koru/human_date.dart';

/// "due in 3 days" answers the question; "2026-10-16" makes the reader count.
///
/// Every screen showed the raw ISO date and left the arithmetic to whoever was
/// reading, which is the work the app exists to do.
void main() {
  // A Wednesday, so weekday names cannot pass by accident on a weekend-only
  // coincidence.
  final from = DateTime(2026, 10, 14);

  group('relative', () {
    String rel(String iso) => formatDate(iso, from);

    test('the near days are named', () {
      expect(rel('2026-10-14'), 'today');
      expect(rel('2026-10-15'), 'tomorrow');
      expect(rel('2026-10-13'), 'yesterday');
    });

    test('counts days while counting helps', () {
      expect(rel('2026-10-17'), 'in 3 days');
      expect(rel('2026-10-20'), 'in 6 days');
    });

    test('switches to weeks once counting days stops helping', () {
      expect(rel('2026-10-20'), 'in 6 days');
      expect(rel('2026-10-21'), 'next week');
      expect(rel('2026-10-28'), 'in 2 weeks');
    });

    test('months and years are not spelled as hundreds of days', () {
      expect(rel('2026-11-13'), 'in a month');
      expect(rel('2027-04-14'), 'in 6 months');
    });

    test('past dates count back', () {
      expect(rel('2026-10-11'), '3 days ago');
      expect(rel('2026-10-12'), '2 days ago');
    });
  });

  group('absolute', () {
    test('short drops the year when it is this one', () {
      expect(formatDate('2026-10-16', from, style: DateStyle.short),
          'Fri 16 Oct');
      expect(formatDate('2027-01-04', from, style: DateStyle.short),
          'Mon 4 Jan 2027');
    });

    test('the card style always carries the year', () {
      // Agreeing to a date is not the moment to be vague about it.
      expect(formatDate('2026-10-16', from, style: DateStyle.unambiguous),
          '16 Oct 2026');
      expect(formatDate('2026-10-16', from, style: DateStyle.long),
          '16 October 2026');
    });
  });

  group('day counting', () {
    test('an entry at 23:00 tonight is still tonight', () {
      final late = DateTime(2026, 10, 14, 23, 0);
      final noon = DateTime(2026, 10, 14, 12, 0);
      expect(daysBetween(noon, late), 0);
      expect(horizonFor(noon, late), Horizon.today);
    });

    test('a timestamped ISO string still reads as its own day', () {
      expect(parseDay('2026-10-16T09:30:00')?.day, 16);
    });

    test('nonsense is no date rather than a crash', () {
      expect(parseDay('not a date'), isNull);
      expect(parseDay(null), isNull);
      expect(parseDay(''), isNull);
      expect(formatDate('nonsense', from), 'no date');
    });
  });

  group('overdue phrasing', () {
    test('says how late, not just that it is late', () {
      expect(overdueSince(DateTime(2026, 10, 11), from), 'overdue by 3 days');
      expect(overdueSince(DateTime(2026, 10, 13), from), 'overdue by 1 day');
      expect(overdueSince(DateTime(2026, 10, 14), from), 'due today');
      expect(overdueSince(null, from), 'overdue');
    });
  });
}
