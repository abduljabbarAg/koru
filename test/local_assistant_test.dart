import 'package:flutter_test/flutter_test.dart';
import 'package:koru/local/local_assistant.dart';
import 'package:koru/models.dart';

/// Facts built from records the user actually entered, so the answers below are
/// the answers a real device would give.
LocalFacts facts({
  String nickname = 'kami',
  String goals = 'two more clients',
  double? bmi = 24.5,
  List<FitnessEntry> fitness = const [],
  List<Client> clients = const [],
}) =>
    LocalFacts(
      nickname: nickname,
      lifeStage: 'running a business',
      goals: goals,
      height: 1.8,
      bmi: bmi,
      fitness: fitness,
      clients: clients,
      today: DateTime(2026, 3, 1),
    );

FitnessEntry log(String day, double kg) => FitnessEntry(day: day, weight: kg);

void main() {
  const a = LocalAssistant();

  group('greeting', () {
    test('greets by nickname when there is one', () {
      final out = a.answer(question: 'hello', facts: facts());
      expect(out.text, contains('kami'));
    });

    test('an empty profile produces an invitation rather than a shrug', () {
      final out = a.answer(
        question: 'hi there',
        facts: facts(nickname: '', goals: '', bmi: null),
      );
      expect(out.text, contains('profile'));
    });
  });

  group('status', () {
    test('summarises business and fitness together', () {
      final out = a.answer(
        question: 'how am i doing?',
        facts: facts(
          clients: const [
            Client(name: 'Acme', status: 'paid', amount: 5000, created: '2026-01-01'),
            Client(name: 'Globex', status: 'delivered', amount: 2000, created: '2026-01-02'),
            Client(name: 'Initech', status: 'lead', amount: 900, created: '2026-01-03'),
          ],
          fitness: [log('2026-02-25', 80), log('2026-02-18', 81)],
        ),
      );
      expect(out.text, contains('1 paid'));
      expect(out.text, contains('two more clients'));
      expect(out.usedData, isTrue);
    });

    test('with no records at all it says so', () {
      final out = a.answer(
        question: 'give me a status update',
        facts: facts(fitness: const [], clients: const [], goals: ''),
      );
      expect(out.text, contains('Nothing logged yet'));
    });
  });

  group('business', () {
    test('names who is overdue', () {
      final out = a.answer(
        question: 'who should I chase for payment?',
        facts: facts(clients: const [
          Client(
            name: 'Acme',
            status: 'delivered',
            amount: 1500,
            due: '2026-02-01',
            created: '2026-01-01',
          ),
          Client(
            name: 'Globex',
            status: 'delivered',
            amount: 500,
            due: '2026-04-01',
            created: '2026-01-02',
          ),
        ]),
      );
      expect(out.text, contains('Acme'));
      expect(out.text, isNot(contains('Globex')));
    });

    test('does not call paid work overdue', () {
      final out = a.answer(
        question: 'is anything overdue?',
        facts: facts(clients: const [
          Client(
            name: 'Acme',
            status: 'paid',
            amount: 100,
            due: '2020-01-01',
            created: '2020-01-01',
          ),
        ]),
      );
      expect(out.text, isNot(contains('Overdue')));
    });

    test('points out the biggest lever when money is outstanding', () {
      final out = a.answer(
        question: 'where is my money?',
        facts: facts(clients: const [
          Client(name: 'A', status: 'delivered', amount: 4000, created: '2026-01-01'),
        ]),
      );
      expect(out.text, contains('4000'));
    });

    test('with no clients it explains what to do', () {
      final out = a.answer(question: 'how is business', facts: facts());
      expect(out.text, contains('No clients yet'));
    });
  });

  group('fitness', () {
    test('reports the latest weight', () {
      final out = a.answer(
        question: 'what is my bmi?',
        facts: facts(fitness: [log('2026-02-28', 79.4)]),
      );
      expect(out.text, contains('79.4'));
    });

    test('refuses to invent a trend from one reading', () {
      final out = a.answer(
        question: 'how is my weight trending?',
        facts: facts(fitness: [log('2026-02-28', 79.4)]),
      );
      expect(out.text, contains('79.4'));
      expect(out.text.toLowerCase(), isNot(contains('trend up')));
    });

    test('reports a downward trend over a fortnight', () {
      final out = a.answer(
        question: 'am I losing weight?',
        facts: facts(fitness: [log('2026-02-28', 78), log('2026-02-14', 80)]),
      );
      expect(out.text, contains('down 1.00kg a week'));
    });

    test('two readings a day apart are not a trend', () {
      final out = a.answer(
        question: 'my weight?',
        facts: facts(fitness: [log('2026-02-28', 78), log('2026-02-27', 81)]),
      );
      expect(out.text, isNot(contains('per week')));
    });

    test('asks for a first log when there is none', () {
      final out = a.answer(question: 'show me my measurements', facts: facts());
      expect(out.text, contains('No measurements logged yet'));
    });
  });

  group('goals', () {
    test('recalls the stated goal', () {
      final out = a.answer(question: 'what are my goals?', facts: facts());
      expect(out.text, contains('two more clients'));
    });

    test('says when there are none', () {
      final out = a.answer(question: 'what are my goals?', facts: facts(goals: ''));
      expect(out.text, contains('not set a goal'));
    });
  });

  group('capabilities and identity', () {
    test('explains what it can do on device', () {
      final out = a.answer(question: 'what can you do?', facts: facts());
      expect(out.text, contains('this device'));
      expect(out.text, contains('pipeline'));
    });

    test('says where it runs', () {
      final out = a.answer(question: 'who are you?', facts: facts());
      expect(out.text, contains('this phone'));
    });
  });

  group('unknown questions', () {
    test('does not pretend to answer', () {
      final out = a.answer(
        question: 'write me a poem about the sea',
        facts: facts(),
      );
      expect(out.suggestCloud, isTrue);
      expect(out.text, contains('could not'));
    });
  });

  group('LocalFacts', () {
    test('weight trend is null with under two readings', () {
      expect(facts(fitness: const []).weightTrendPerWeek, isNull);
      expect(facts(fitness: [log('2026-02-28', 80)]).weightTrendPerWeek, isNull);
    });

    test('weight trend needs a real gap in time', () {
      final f = facts(fitness: [log('2026-02-28', 80), log('2026-02-27', 82)]);
      expect(f.weightTrendPerWeek, isNull);
    });

    test('weight trend is kg per week', () {
      final f = facts(fitness: [log('2026-02-28', 79), log('2026-02-14', 80)]);
      // One kilo lost across two weeks.
      expect(f.weightTrendPerWeek, closeTo(-0.5, 0.001));
    });

    test('readings without a weight are ignored for the trend', () {
      final f = facts(fitness: [
        const FitnessEntry(day: '2026-02-28'),
        log('2026-02-21', 80),
        log('2026-02-14', 81),
      ]);
      expect(f.weightTrendPerWeek, closeTo(-1.0, 0.01));
    });

    test('hasRecords reflects actual data', () {
      expect(facts().hasRecords, isFalse);
      expect(facts(clients: const [Client(name: 'x', created: '2026-01-01')]).hasRecords, isTrue);
    });
  });
}
