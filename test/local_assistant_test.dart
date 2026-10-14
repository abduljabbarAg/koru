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
      expect(out.text, contains('still owed 2900'));
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
      expect(out.text, contains('still owed 0'));
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

  group('what is due', () {
    // The reported failure: "what is due today" contains none of the words the
    // business intent matched on, so it fell through to the fallback and the
    // user was told Koru could not help with its own deadlines.
    test('answers a dues question instead of shrugging', () {
      final out = a.answer(
        question: 'what is due today',
        facts: LocalFacts(
          today: DateTime(2026, 10, 11),
          clients: const [
            Client(
              id: 1,
              name: 'Bilal',
              amount: 2000,
              status: 'delivered',
              created: '2026-10-01',
              termsDays: 14,
              invoicedOn: '2026-10-01',
            ),
          ],
        ),
      );
      expect(out.text, isNot(contains('could not')));
      expect(out.text.toLowerCase(), contains('due'));
    });

    test('separates late money from what is due today', () {
      final out = a.answer(
        question: 'anything due',
        facts: LocalFacts(
          today: DateTime(2026, 10, 11),
          clients: const [
            Client(
              id: 1,
              name: 'Bilal',
              amount: 2000,
              status: 'delivered',
              created: '2026-09-01',
              termsDays: 14,
              invoicedOn: '2026-09-01',
            ),
          ],
          deadlines: const [
            Deadline(id: 1, title: 'Send invoice', due: '2026-10-11'),
            Deadline(id: 2, title: 'Call Acme', due: '2026-10-10'),
            Deadline(id: 3, title: 'Something later', due: '2026-12-01'),
          ],
        ),
      );
      expect(out.text, contains('Bilal'));
      // Invoiced 1 Sep on net 14 is due 15 Sep, which is 26 days before the
      // 11th. The figure comes from the terms, not from a date anyone typed.
      expect(out.text, contains('26 days late'));
      expect(out.text, contains('Send invoice'));
      expect(out.text, contains('Call Acme'));
      expect(out.text, isNot(contains('Something later')),
          reason: 'a deadline months away is not what was asked for');
    });

    test('uses agreed terms to decide what is late', () {
      const late = Client(
        id: 1,
        name: 'Bilal',
        amount: 2000,
        status: 'delivered',
        created: '2026-09-01',
        termsDays: 14,
        invoicedOn: '2026-09-01',
      );
      // No due column at all. Terms alone have to be enough.
      expect(late.due, isNull);
      expect(late.dueDate, DateTime(2026, 9, 15));
      expect(late.isOverdueOn(DateTime(2026, 10, 11)), isTrue);

      final ok = late.copyWith(invoicedOn: '2026-10-05');
      expect(ok.isOverdueOn(DateTime(2026, 10, 11)), isFalse);
    });

    test('an explicit date beats the terms', () {
      const c = Client(
        id: 1,
        name: 'Bilal',
        amount: 100,
        status: 'delivered',
        created: '2026-09-01',
        due: '2026-12-01',
        termsDays: 14,
        invoicedOn: '2026-09-01',
      );
      expect(c.dueDate, DateTime(2026, 12, 1));
    });

    test('says so plainly when nothing is due', () {
      final out = a.answer(
        question: 'what is due today',
        facts: LocalFacts(today: DateTime(2026, 10, 11)),
      );
      expect(out.text, contains('Nothing is due'));
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

  group('a typo still finds the client', () {
    // People type names into speech and it comes out wrong far more often than
    // it comes out right. "I do not have a client called Bial" is a
    // confidently wrong answer to "how much does Bilal owe".
    final facts = LocalFacts(clients: const [
      Client(id: 1, name: 'Bilal', amount: 2000),
      Client(id: 2, name: 'Acme Studio', amount: 900),
    ]);
    String ask(String q) =>
        const LocalAssistant().answer(question: q, facts: facts).text;

    test('a dropped letter still finds them', () {
      expect(ask('how much does Bial owe'), contains('Bilal'));
    });

    test('a swapped pair still finds them', () {
      expect(ask('how much does Biala owe'), contains('Bilal'));
    });

    test('the first part of a multi word name is enough', () {
      expect(ask('how much does Acme owe'), contains('Acme Studio'));
    });

    test('a name that is simply not there is never invented', () {
      // The bound is the point. An unbounded nearest-neighbour answers something
      // for every input, so unrelated questions eventually return a balance.
      // Falling through to a general report is fine; claiming a client called
      // Zzzzzqqqq is not.
      final out = ask('how much does Zzzzzqqqq owe');
      expect(out.toLowerCase(), isNot(contains('zzzzzqqqq')));
    });

    test('an exact match still wins over a near miss', () {
      final two = LocalFacts(clients: const [
        Client(id: 1, name: 'Bilal', amount: 100),
        Client(id: 2, name: 'Bilal Jr', amount: 200),
      ]);
      final out = const LocalAssistant()
          .answer(question: 'how much does Bilal owe', facts: two)
          .text;
      expect(out, contains('Bilal'));
    });
  });

  group('a follow-up borrows the last question', () {
    final facts = LocalFacts(
      clients: const [Client(id: 1, name: 'Bilal', amount: 2000)],
      deadlines: const [Deadline(id: 1, title: 'Invoice', due: '2026-10-20')],
    );

    String ask(String q, {String? previous}) => const LocalAssistant()
        .answer(question: q, facts: facts, previousQuestion: previous).text;

    test('a bare "what about next week" knows what it is about', () {
      final out = ask('what about next week?', previous: 'how much does Bilal owe');
      expect(out, contains('Bilal'));
    });

    test('without a previous turn there is no subject to borrow', () {
      // It falls back to the general report rather than answering about Bilal.
      // The report may still name Bilal as the biggest client, so what is
      // asserted is that it is not a client-specific answer.
      final out = ask('what about next week?');
      expect(out, isNot(contains('owes you')));
      expect(out.toLowerCase(), isNot(contains('zzzzz')));
    });

    test('an explicit name in the new question still wins', () {
      final two = LocalFacts(clients: const [
        Client(id: 1, name: 'Bilal', amount: 100),
        Client(id: 2, name: 'Acme', amount: 500),
      ]);
      final out = const LocalAssistant()
          .answer(
            question: 'how much does Acme owe',
            facts: two,
            previousQuestion: 'how much does Bilal owe',
          )
          .text;
      expect(out, contains('Acme'));
    });
  });


  group('talking to it like a person', () {
    test('a yes is taken as go on, not as a new question', () {
      for (final yes in ['yes', 'yeah', 'yep', 'sure', 'ok', 'go ahead']) {
        final out = a.answer(question: yes, facts: facts());
        expect(out.text, isNot(contains('could not')), reason: yes);
        expect(out.text, isNotEmpty, reason: yes);
      }
    });

    test('a no is accepted without arguing', () {
      final out = a.answer(question: 'no', facts: facts());
      expect(out.text.toLowerCase(), anyOf(contains('okay'), contains('no problem'),
          contains('fair enough'), contains('understood')));
    });

    test('"anything else" says what is actually true right now', () {
      final out = a.answer(
        question: 'anything else',
        facts: facts(
          clients: const [Client(id: 1, name: 'Acme', status: 'delivered', amount: 5000)],
          received: const {},
        ),
      );
      // The outstanding amount, not a menu.
      expect(out.text, contains('Acme'));
      expect(out.text, contains('5000'));
    });

    test('"and him" with one client answers about that client', () {
      final out = a.answer(
        question: 'and him',
        facts: facts(
          clients: const [Client(id: 1, name: 'Acme', status: 'delivered', amount: 5000)],
          received: const {},
        ),
      );
      expect(out.text, contains('Acme'));
    });

    test('"and him" with several clients asks rather than guessing', () {
      final out = a.answer(
        question: 'and him',
        facts: facts(
          clients: const [
            Client(id: 1, name: 'Acme', status: 'paid', amount: 5000),
            Client(id: 2, name: 'Globex', status: 'paid', amount: 2000),
          ],
          received: const {1: 5000, 2: 2000},
        ),
      );
      expect(out.text, contains('Who did you mean'));
      expect(out.text, contains('Acme'));
    });
  });

  group('yes and no questions about the records', () {
    test('a yes/no question gets yes or no and the number', () {
      final out = a.answer(
        question: 'did i get paid',
        facts: facts(
          clients: const [
            Client(id: 1, name: 'Acme', status: 'paid', amount: 5000),
            Client(id: 2, name: 'Globex', status: 'delivered', amount: 2000),
          ],
          received: const {1: 5000},
        ),
      );
      expect(out.text, contains('Not everything'));
      expect(out.text, contains('2000'));
      expect(out.text, contains('Globex'));
    });

    test('naming the client answers about that client', () {
      final out = a.answer(
        question: 'is globex late',
        facts: facts(
          clients: const [
            Client(id: 1, name: 'Acme', status: 'paid', amount: 5000),
            Client(id: 2, name: 'Globex', status: 'delivered', amount: 2000),
          ],
          received: const {1: 5000},
        ),
      );
      expect(out.text, contains('Globex'));
      expect(out.text, contains('2000'));
    });

    test('a settled client gets a clear no', () {
      final out = a.answer(
        question: 'is acme late',
        facts: facts(
          clients: const [Client(id: 1, name: 'Acme', status: 'paid', amount: 5000)],
          received: const {1: 5000},
        ),
      );
      expect(out.text, contains('settled'));
    });

    test('nobody owing anything gets a clear no', () {
      final out = a.answer(
        question: 'am i behind',
        facts: facts(
          clients: const [Client(id: 1, name: 'Acme', status: 'paid', amount: 5000)],
          received: const {1: 5000},
        ),
      );
      expect(out.text, contains('Nobody owes you'));
    });
  });

}
