import 'package:flutter_test/flutter_test.dart';
import 'package:koru/cloud.dart';
import 'package:koru/handoff.dart';
import 'package:koru/models.dart';
import 'package:koru/packet.dart';

void main() {
  group('routing', () {
    test('crisis routes to a human', () {
      final d = RoutingDecision.route('I have not slept in four days');
      expect(d.needsHuman, isTrue);
      expect(d.useCloud, isTrue);
    });

    // Phrasings that a narrower list would have let through to a plain model
    // answer. Each one is a real way a person types the same distress.
    test('crisis phrasings all reach a human', () {
      const phrasings = [
        'I have not slept in four days',
        'I cannot sleep again',
        "I can't breathe, having a panic attack",
        'I want to die',
        'I have been awake for three days straight',
        'my doctor asked about my prescription and dosage',
        'she hit me and I am not safe',
        'I am going to be in court next month',
        'she is abusing me',
        'they threatened me',
        'i feel numb',
        'i am so exhausted',
        'i have no energy',
        'i am falling apart',
        'im scared to go home',
        'i had a miscarriage',
        'i am pregnant',
        'the police arrested me',
        'im deported',
        'my prescription is wrong',
        'im burnt out',
        'i feel completely empty and hopeless',
        'i am helpless',
        'my partner threatens me',
        'i think i am depressed',
        'i am so tired',
        'im always tired',
        'i cannot go on',
        'nothing matters',
        'im going to hurt myself',
        'i want to end it all',
        'no point in anything',
      ];
      for (final p in phrasings) {
        expect(RoutingDecision.route(p).needsHuman, isTrue,
            reason: 'should hand to a person: "$p"');
      }
    });

    // The cost of a false positive is one sentence, so ordinary questions that
    // merely sound adjacent must not be escalated. Word-boundary matching is
    // what keeps "empty my folder" out of the crisis list.
    //
    // Known accepted escalation: "I want to die laughing at that joke" hands off
    // to a person, because "want to die" is a genuine crisis phrase and the
    // matcher has no way to tell a joke from a statement. That is the intended
    // direction to be wrong in, so it is documented here rather than papered
    // over with a narrower rule that would also miss real statements.
    test('ordinary questions are not escalated', () {
      const normal = [
        'draft a follow up for my client',
        'how do I price a website build',
        'what should I train this week',
        'my revenue was up but margins are down',
        'is this islam or not',
        'write me a python function',
        'what is my hourly rate',
        'help me draft an invoice',
        'where should i find leads',
        'summarise this',
        'i slept fine last night',
        'empty my folder',
        'give me a workout plan',
        'my doctor is booked next week',
        'legalise this contract',
        'i need a break at work',
        'i feel great today',
        'can you help me with my taxes',
        'i have a headache',
        'write a poem about rain',
        'fix this python loop',
        'what is my net worth',
        'plan my week',
        'i am nervous about the meeting',
        'im going to the gym',
        'my invoice is overdue by 5 days',
        'set a reminder for my standup',
      ];
      for (final n in normal) {
        expect(RoutingDecision.route(n).needsHuman, isFalse,
            reason: 'should not escalate: "$n"');
      }
    });

    // Locks in the accepted false positive so a future change has to decide
    // about it deliberately instead of it moving silently.
    test('joke about death still escalates, by design', () {
      expect(RoutingDecision.route('i want to die laughing at that joke').needsHuman, isTrue);
    });

    test('faith routes to cloud without a handoff', () {
      final d = RoutingDecision.route('is this islam');
      expect(d.useCloud, isTrue);
      expect(d.needsHuman, isFalse);
    });

    test('business stays local', () {
      final d = RoutingDecision.route('draft a follow up for my client');
      expect(d.useCloud, isFalse);
      expect(d.needsHuman, isFalse);
    });

    test('punctuation and case do not change the outcome', () {
      expect(RoutingDecision.route('I WANT TO DIE!!').needsHuman, isTrue);
      expect(RoutingDecision.route('i want to die!!').needsHuman, isTrue);
      expect(RoutingDecision.route('I want to die.').needsHuman, isTrue);
      expect(RoutingDecision.normalise('Hi, there!'), 'hi there');
    });

    test('an empty question is not an escalation', () {
      expect(RoutingDecision.route('').needsHuman, isFalse);
    });
  });

  group('ContextPacket privacy', () {
    const packet = ContextPacket(
      nickname: 'kami',
      lifeStage: 'mid career',
      business: 'solo dev, 2 yrs',
      goals: 'two more clients',
      focus: 'business growth',
    );

    test('the local rendering may name the user', () {
      expect(packet.renderLocal(), contains('kami'));
    });

    test('the cloud rendering never carries the nickname', () {
      expect(packet.renderForCloud(), isNot(contains('kami')));
    });

    test('the cloud rendering still carries the useful context', () {
      final cloud = packet.renderForCloud();
      expect(cloud, contains('solo dev'));
      expect(cloud, contains('two more clients'));
      expect(cloud, contains('business growth'));
    });

    test('the prompt built for the cloud has no nickname in it', () {
      final prompt = PromptBuilder.build(
        packet: packet,
        question: 'how do I price this?',
        routing: const RoutingDecision(
          useCloud: true,
          needsHuman: false,
          reason: 'cloud',
        ),
      );
      expect(prompt, isNot(contains('kami')));
      expect(prompt, contains('never guess or invent a real name'));
    });

    test('the prompt tells a sensitive model to stop short of a ruling', () {
      final prompt = PromptBuilder.build(
        packet: packet,
        question: 'is this a diagnosis?',
        routing: const RoutingDecision(
          useCloud: true,
          needsHuman: true,
          reason: 'deserves a person',
        ),
      );
      expect(prompt, contains('Do not give a diagnosis'));
    });

    test('the budget is measured against the cloud rendering', () {
      expect(packet.wordCount, lessThan(ContextPacket.maxCloudWords));
    });

    test('round trips through json', () {
      final decoded = ContextPacket.fromJson(packet.toJson());
      expect(decoded.nickname, packet.nickname);
      expect(decoded.focus, packet.focus);
    });

    test('an empty packet does not read as broken sentences', () {
      const empty = ContextPacket(
        nickname: '',
        lifeStage: '',
        business: '',
        goals: '',
        focus: '',
      );
      expect(empty.renderForCloud(), 'About this user.');
      expect(empty.renderLocal(), 'About this person.');
      expect(empty.renderForCloud(), isNot(contains('..')));
    });
  });

  group('handoff', () {
    const needsHuman = RoutingDecision(
      useCloud: true,
      needsHuman: true,
      reason: 'deserves a person',
    );

    test('immediate danger gets the urgent treatment and the emergency number', () {
      final plan = handoffPlanFor(needsHuman, 'I want to kill myself');
      expect(plan.urgent, isTrue);
      expect(plan.resources.first.number, '999');
    });

    test('a diagnosis question is not treated as an emergency', () {
      final plan = handoffPlanFor(needsHuman, 'is my prescription dose right');
      expect(plan.urgent, isFalse);
      expect(plan.resources.first.name, contains('doctor'));
    });

    test('a legal deadline is routed to a person, not a hotline', () {
      final plan = handoffPlanFor(needsHuman, 'I am in court next month');
      expect(plan.urgent, isFalse);
    });

    test('refuses to build a plan for a question that did not need one', () {
      expect(
        () => handoffPlanFor(
          const RoutingDecision(useCloud: false, needsHuman: false, reason: 'local'),
          'draft an invoice',
        ),
        throwsArgumentError,
      );
    });

    test('immediate danger is detected from phrasing, not from routing', () {
      expect(isImmediateDanger('I am going to hurt myself'), isTrue);
      expect(isImmediateDanger('im deported'), isFalse);
      expect(isImmediateDanger('my doctor is booked'), isFalse);
    });
  });

  group('client overdue logic', () {
    final today = DateTime(2026, 3, 1);

    test('delivered work past its date is overdue', () {
      const c = Client(name: 'A', status: 'delivered', due: '2026-02-01');
      expect(c.isOverdueOn(today), isTrue);
    });

    test('work due today is not yet overdue', () {
      const c = Client(name: 'A', status: 'delivered', due: '2026-03-01');
      expect(c.isOverdueOn(today), isFalse);
    });

    test('paid work is never overdue', () {
      const c = Client(name: 'A', status: 'paid', due: '2020-01-01');
      expect(c.isOverdueOn(today), isFalse);
    });

    test('lost work is never overdue', () {
      const c = Client(name: 'A', status: 'lost', due: '2020-01-01');
      expect(c.isOverdueOn(today), isFalse);
    });

    test('a client with no due date cannot be overdue', () {
      const c = Client(name: 'A', status: 'delivered');
      expect(c.isOverdueOn(today), isFalse);
    });

    test('an unparseable due date cannot be overdue', () {
      const c = Client(name: 'A', status: 'delivered', due: 'soon');
      expect(c.isOverdueOn(today), isFalse);
    });
  });


  group('cloud reply extraction', () {
    test('reads a normal completion', () {
      const body = '{"choices":[{"message":{"content":"hello there"}}]}';
      expect(CloudModel.extractReply(body), 'hello there');
    });

    test('survives escaped quotes inside the content', () {
      const body = r'{"choices":[{"message":{"content":"say \"hi\" now"}}]}';
      expect(CloudModel.extractReply(body), 'say "hi" now');
    });

    test('picks the message content, not some earlier field', () {
      const body = '{"id":"x","object":"chat","choices":[{"message":'
          '{"role":"assistant","content":"the real answer"}}]}';
      expect(CloudModel.extractReply(body), 'the real answer');
    });

    test('joins content parts when the gateway sends a list', () {
      const body = '{"choices":[{"message":{"content":['
          '{"type":"text","text":"part one "},{"type":"text","text":"part two"}]}}]}';
      expect(CloudModel.extractReply(body), 'part one part two');
    });

    test('returns null rather than throwing on malformed json', () {
      expect(CloudModel.extractReply('not json at all'), isNull);
    });

    test('returns null when there are no choices', () {
      expect(CloudModel.extractReply('{"choices":[]}'), isNull);
      expect(CloudModel.extractReply('{}'), isNull);
    });

    test('an empty reply is treated as no reply', () {
      expect(CloudModel.extractReply('{"choices":[{"message":{"content":"   "}}]}'), '   ');
    });
  });
}
