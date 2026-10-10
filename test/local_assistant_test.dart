import 'package:flutter_test/flutter_test.dart';
import 'package:koru/local/local_assistant.dart';
import 'package:koru/models.dart';

/// Facts built from records the user actually entered, so the answers below are
/// the answers a real device would give.
LocalFacts facts({
  String nickname = 'kami',
  String goals = 'two more clients',
  List<Client> clients = const [],
  Map<int, double> received = const {},
  List<Deadline> deadlines = const [],
}) =>
    LocalFacts(
      nickname: nickname,
      lifeStage: 'running a business',
      goals: goals,
      clients: clients,
      received: received,
      deadlines: deadlines,
      today: DateTime(2026, 3, 1),
    );

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
        facts: facts(nickname: '', goals: ''),
      );
      expect(out.text, contains('profile'));
    });
  });

  group('status', () {
    test('summarises money, not statuses', () {
      final out = a.answer(
        question: 'how am i doing?',
        facts: facts(
          clients: const [
            Client(id: 1, name: 'Acme', status: 'paid', amount: 5000),
            Client(id: 2, name: 'Globex', status: 'delivered', amount: 2000),
            Client(id: 3, name: 'Initech', status: 'lead', amount: 900),
          ],
          received: const {1: 5000},
        ),
      );
      // Globex and Initech both still owe, because neither has been paid.
      expect(out.text, contains('2 owing a balance'));
      expect(out.text, contains('still owed 2900 AED'));
      expect(out.text, contains('two more clients'));
      expect(out.usedData, isTrue);
    });

    test('with no records at all it says so', () {
      final out = a.answer(
        question: 'give me a status update',
        facts: facts(clients: const [], goals: ''),
      );
      expect(out.text, contains('Nothing on file yet'));
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
          Client(id: 1, name: 'A', status: 'delivered', amount: 4000),
        ]),
      );
      expect(out.text, contains('4000'));
    });

    test('does not count money already received as still owed', () {
      final out = a.answer(
        question: 'who owes me money?',
        facts: facts(
          clients: const [Client(id: 1, name: 'A', status: 'paid', amount: 4000)],
          received: const {1: 4000},
        ),
      );
      expect(out.text, contains('still owed 0 AED'));
    });

    test('names upcoming deadlines', () {
      final out = a.answer(
        question: 'what is coming up?',
        facts: facts(
          clients: const [Client(id: 1, name: 'A', status: 'active')],
          deadlines: const [Deadline(title: 'Send invoice', due: '2026-04-01')],
        ),
      );
      expect(out.text, contains('Send invoice'));
    });

    test('with no clients it explains what to do', () {
      final out = a.answer(question: 'how is business', facts: facts());
      expect(out.text, contains('No clients yet'));
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
    test('hasRecords reflects actual data', () {
      expect(facts().hasRecords, isFalse);
      expect(
        facts(clients: const [Client(name: 'x', created: '2026-01-01')]).hasRecords,
        isTrue,
      );
    });

    test('a deadline alone counts as having records', () {
      expect(
        facts(deadlines: const [Deadline(title: 'x', due: '2026-01-01')]).hasRecords,
        isTrue,
      );
    });

    test('a balance comes from the ledger, not the invoice amount', () {
      final f = facts(
        clients: const [Client(id: 7, name: 'A', amount: 2000)],
        received: const {7: 500},
      );
      expect(f.balanceOf(f.clients.single), 1500);
    });
  });
}
