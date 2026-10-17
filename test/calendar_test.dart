import 'package:flutter_test/flutter_test.dart';
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

  group('durations are read, and a bare number is not one', () {
    const p = WriteIntentParser();

    test('"for 2 hours" is two hours', () {
      final e = p.parse('schedule a call with Bilal tomorrow at 3pm for 2 hours')
          as AddEventIntent;
      expect(e.durationMin, 120);
    });

    test('"90 minutes" is ninety minutes', () {
      final e = p.parse('schedule a review with Acme friday for 90 minutes')
          as AddEventIntent;
      expect(e.durationMin, 90);
    });

    test('"an hour and a half" is understood', () {
      final e = p.parse('schedule a workshop monday for an hour and a half')
          as AddEventIntent;
      expect(e.durationMin, 90);
    });

    test('the duration does not become the title', () {
      final e = p.parse('schedule a call with Bilal tomorrow at 3pm for 2 hours')
          as AddEventIntent;
      expect(e.title.toLowerCase(), isNot(contains('hours')));
      expect(e.title.toLowerCase(), isNot(contains('for')));
    });

    test('the phrase leaves nothing behind', () {
      final e = p.parse('schedule a call with Bilal tomorrow at 3pm for 2 hours')
          as AddEventIntent;
      expect(e.title.trim(), 'call with Bilal');
    });

    test('a bare "for 2" is not read as two hours', () {
      // In a sentence about a meeting, "for 2" is two o'clock far more often,
      // and reading it as a length invents a block nobody asked for.
      final e = p.parse('schedule a call with Bilal tomorrow for 2') as AddEventIntent;
      expect(e.durationMin, isNull);
    });
  });

  group('recurrence', () {
    const p = WriteIntentParser();

    test('the common phrases are read', () {
      expect((p.parse('schedule a standup with Acme every week monday')
              as AddEventIntent)
              .recurrence,
          EventRecurrence.weekly);
      expect((p.parse('schedule a sync with Bilal every month on the 3rd')
              as AddEventIntent)
              .recurrence,
          EventRecurrence.monthly);
      expect((p.parse('schedule a call with Bilal every two weeks')
              as AddEventIntent)
              .recurrence,
          EventRecurrence.fortnightly);
    });

    test('"every two weeks" is not read as weekly', () {
      // "every two weeks" contains "every", so the short match has to lose.
      final e = p.parse('schedule a call with Bilal every two weeks')
          as AddEventIntent;
      expect(e.recurrence, EventRecurrence.fortnightly);
      expect(e.recurrence, isNot(EventRecurrence.weekly));
    });

    test('a single entry is left alone', () {
      expect((p.parse('schedule a call with Bilal tomorrow') as AddEventIntent)
          .recurrence, isNull);
    });
  });

  group('editing an entry', () {
    const p = WriteIntentParser();

    test('moving a call to another day is an edit, not a new entry', () {
      final e = p.parse('move the call with Bilal to thursday') as EditEventIntent;
      expect(e.title.toLowerCase(), contains('bilal'));
      expect(e.date, isNotNull);
    });

    test('a reschedule names the entry', () {
      final e = p.parse('reschedule the standup with Acme to 10am') as EditEventIntent;
      expect(e.title.toLowerCase(), contains('acme'));
      expect(e.time, '10:00');
    });

    test('an edit with nothing to change asks rather than proposing', () {
      expect(p.parse('move the call with Bilal'), isA<IncompleteWriteIntent>());
    });
  });

  group('a repeating entry rolls forward', () {
    test('a weekly entry occurs on the right days', () {
      const e = CalendarEvent(
        id: 1,
        date: '2026-10-12',
        time: '09:00',
        title: 'Standup',
        recurrence: EventRecurrence.weekly,
      );
      final occ = e.occurrences(DateTime(2026, 10, 12), DateTime(2026, 11, 9));
      expect(occ.map((o) => o.date).toList(), [
        '2026-10-12', '2026-10-19', '2026-10-26', '2026-11-02', '2026-11-09',
      ]);
    });

    test('a monthly entry does not drift onto a short month', () {
      // Adding 30 days to 31 January lands on 2 March, which is the wrong
      // meeting. This is the whole reason recurrence is a date arithmetic and
      // not a duration.
      const e = CalendarEvent(
        id: 2,
        date: '2026-01-31',
        title: 'Rent',
        recurrence: EventRecurrence.monthly,
      );
      final next = e.recurrence!.next(DateTime(2026, 1, 31))!;
      expect(next.month, 2);
      expect(next.day, 28);
    });

    test('a non-recurring entry only occurs on its own day', () {
      const e = CalendarEvent(id: 3, date: '2026-10-12', title: 'Once');
      expect(e.occurrences(DateTime(2026, 10, 1), DateTime(2026, 11, 1)).length, 1);
      expect(e.occurrences(DateTime(2026, 11, 1), DateTime(2026, 12, 1)), isEmpty);
    });

    test('the walk forward is capped so a daily entry cannot run away', () {
      const e = CalendarEvent(
        id: 4,
        date: '2020-01-01',
        title: 'Daily',
        recurrence: EventRecurrence.daily,
      );
      expect(
        e.occurrences(DateTime(2026, 1, 1), DateTime(2030, 1, 1)).length,
        lessThanOrEqualTo(60),
      );
    });
  });


  group('an entry survives a round trip through storage', () {
    test('the repeat rule is stored and read back', () async {
      final store = await openTestStore();
      final id = await store.addEvent(const CalendarEvent(
        date: '2026-10-12',
        time: '09:00',
        title: 'Standup',
        durationMin: 30,
        recurrence: EventRecurrence.weekly,
        created: '2026-10-01T00:00:00.000',
      ));
      final back = await store.event(id);
      expect(back, isNotNull);
      expect(back!.title, 'Standup');
      expect(back.durationMin, 30);
      expect(back.recurrence, EventRecurrence.weekly);
    });

    test('an entry with no repeat stays a single entry', () async {
      final store = await openTestStore();
      final id = await store.addEvent(const CalendarEvent(
        date: '2026-10-12',
        title: 'Once',
        created: '2026-10-01T00:00:00.000',
      ));
      expect((await store.event(id))!.recurrence, isNull);
    });
  });

}
