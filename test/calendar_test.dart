import 'package:flutter_test/flutter_test.dart';
import 'package:koru/local/local_assistant.dart';
import 'package:koru/local/write_intent.dart';
import 'package:koru/models.dart';

import 'test_store.dart';

/// Calendar entries, walked the way the feature is used: said in plain words,
/// approved, stored, then asked about again.
void main() {
  group('saying an entry in plain words', () {
    const parser = WriteIntentParser();

    test('reads a title, a date and a time', () {
      final intent = parser.parse('schedule a call with Bilal tomorrow at 3pm');
      expect(intent, isA<AddEventIntent>());
      final e = intent! as AddEventIntent;
      expect(e.title, 'call with Bilal');
      expect(e.time, '15:00');
      expect(e.date, isNotNull);
      expect(DateTime.parse(e.date!).isAfter(DateTime.now()), isTrue);
    });

    test('reads a 24 hour time and a location', () {
      final e = parser
          .parse('book a meeting with Acme on friday at 14:30 at the studio')!
          as AddEventIntent;
      expect(e.title, 'meeting with Acme');
      expect(e.time, '14:30');
      expect(e.location, 'The studio');
    });

    test('an entry with no date lands on today rather than nowhere', () {
      final e = parser.parse('add a meeting with Bilal')! as AddEventIntent;
      expect(e.title, 'meeting with Bilal');
      expect(e.date, isNotNull);
      expect(e.time, isNull, reason: 'no time was said, so it is all day');
    });

    test('a bare number is not a time', () {
      final e = parser.parse('schedule a call with 3 clients tomorrow')!
          as AddEventIntent;
      expect(e.time, isNull);
    });

    test('a question about the calendar is not an instruction', () {
      expect(parser.parse('when is my meeting with Bilal?'), isNull);
    });

    test('a deadline is still a deadline, not an event', () {
      expect(parser.parse('add a deadline to send the invoice on friday'),
          isA<AddDeadlineIntent>());
    });
  });

  group('the store keeps entries', () {
    test('round trip, windowed reads and delete', () async {
      final store = await openTestStore();
      final id = await store.addEvent(const CalendarEvent(
        date: '2026-10-20',
        time: '15:00',
        title: 'Call with Bilal',
        location: 'Studio',
      ));
      await store.addEvent(const CalendarEvent(
        date: '2026-11-02',
        title: 'Offsite',
      ));

      final all = await store.events();
      expect(all.length, 2);
      expect(all.first.title, 'Call with Bilal', reason: 'soonest first');
      expect(all.first.timeLabel, '3:00 pm');

      final thatWeek = await store.events(
        from: DateTime(2026, 10, 19),
        to: DateTime(2026, 10, 21),
      );
      expect(thatWeek.single.location, 'Studio');

      // All-day entries sort before timed ones on the same day.
      final sameDay = await store.events(
          from: DateTime(2026, 10, 20), to: DateTime(2026, 10, 20));
      expect(sameDay.single.time, '15:00');

      await store.deleteEvent(id);
      expect((await store.events()).single.title, 'Offsite');
      await store.close();
    });

    test('delete everything takes the calendar with it', () async {
      final store = await openTestStore();
      await store.addEvent(
          const CalendarEvent(date: '2026-10-20', title: 'Call'));
      await store.wipe();
      expect(await store.events(), isEmpty);
      await store.close();
    });
  });

  group('asking about the calendar', () {
    const a = LocalAssistant();

    test('today shows as today, with the time', () {
      final out = a.answer(
        question: 'what is on my calendar',
        facts: LocalFacts(
          today: DateTime(2026, 10, 14, 9),
          events: const [
            CalendarEvent(
                date: '2026-10-14', time: '15:00', title: 'Call with Bilal'),
          ],
        ),
      );
      expect(out.text, contains('Call with Bilal'));
      expect(out.text, contains('3:00 pm'));
      expect(out.text, contains('Today'));
    });

    test('an empty calendar says how to fill it', () {
      final out =
          a.answer(question: 'what is on today', facts: LocalFacts());
      expect(out.text, contains('schedule a call'));
    });

    test('deadlines appear alongside entries', () {
      final out = a.answer(
        question: 'what is on my calendar',
        facts: LocalFacts(
          today: DateTime(2026, 10, 14),
          deadlines: const [Deadline(title: 'Send invoice', due: '2026-10-14')],
        ),
      );
      expect(out.text, contains('Send invoice'));
    });
  });

  group('arithmetic and named clients', () {
    const a = LocalAssistant();

    test('a percentage', () {
      final out = a.answer(question: 'what is 15% of 2000', facts: LocalFacts());
      expect(out.text, contains('300'));
    });

    test('a sum in words', () {
      final out =
          a.answer(question: 'what is 2000 plus 500', facts: LocalFacts());
      expect(out.text, contains('2500'));
    });

    test('a sum with precedence', () {
      final out =
          a.answer(question: 'calculate 10 + 4 * 2', facts: LocalFacts());
      expect(out.text, contains('18'));
    });

    test('one named client, from the ledger', () {
      final out = a.answer(
        question: 'how much does Bilal owe?',
        facts: LocalFacts(
          clients: const [Client(id: 1, name: 'Bilal', amount: 2000)],
          received: const {1: 500},
        ),
      );
      expect(out.text, contains('Bilal'));
      expect(out.text, contains('1500'));
      expect(out.usedData, isTrue);
    });

    test('the date, without the clock unless it was asked for', () {
      final out =
          a.answer(question: 'what day is it', facts: LocalFacts(today: DateTime(2026, 10, 14)));
      expect(out.text, contains('Wednesday'));
      expect(out.text, contains('14 October 2026'));
      expect(out.text, isNot(contains('It is 12:')));

      final clocked =
          a.answer(question: 'what time is it', facts: LocalFacts());
      expect(clocked.text.toLowerCase(), contains('it is'));
    });
  });
}
