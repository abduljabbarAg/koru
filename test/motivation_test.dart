import 'package:flutter_test/flutter_test.dart';
import 'package:koru/motivation.dart';

void main() {
  group('quoteFor', () {
    test('is stable for the same day', () {
      // The whole point of keying on the date. Scrolling and tab switches
      // recompute this screen, and a quote that reshuffles each time reads as
      // a glitch rather than a line.
      final morning = quoteFor(DateTime(2026, 3, 14, 7, 12));
      final evening = quoteFor(DateTime(2026, 3, 14, 22, 41));
      expect(evening.text, morning.text);
      expect(evening.by, morning.by);
    });

    test('changes between days', () {
      expect(
        quoteFor(DateTime(2026, 3, 14)).text,
        isNot(quoteFor(DateTime(2026, 3, 15)).text),
      );
    });

    test('rotates rather than repeating one line forever', () {
      // A month of mornings on one quote is the failure mode when the index is
      // derived from something coarser than the day.
      final seen = <String>{
        for (var d = 0; d < 30; d++)
          quoteFor(DateTime(2026, 3, 1).add(Duration(days: d))).text,
      };
      expect(seen.length, greaterThan(5));
    });

    test('does not throw for a date before the epoch', () {
      // A fresh install with a clock set behind the reference date would index
      // backwards and crash on the very first screen the user sees.
      expect(() => quoteFor(DateTime(1999, 1, 1)), returnsNormally);
    });

    test('every quote has text and an attribution', () {
      for (var d = 0; d < 40; d++) {
        final q = quoteFor(DateTime(2026, 1, 1).add(Duration(days: d)));
        expect(q.text.trim(), isNotEmpty);
        expect(q.by.trim(), isNotEmpty);
      }
    });
  });
}