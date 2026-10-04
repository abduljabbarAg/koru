import 'package:flutter_test/flutter_test.dart';
import 'package:koru/packet.dart';

void main() {
  test('packet is pseudonymous: carries context, no name', () {
    const p = ContextPacket(
      nickname: 'kami',
      lifeStage: 'mid career',
      business: 'solo dev, 2 yrs',
      goals: 'two more clients',
      fitness: 'weight 80kg, BMI 24.5',
      focus: '',
    );
    final s = p.render();
    expect(s.contains('kami'), isTrue);
    expect(s.contains('solo dev'), isTrue);
    expect(p.wordCount, lessThan(60));
  });

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
      'they threatened me',
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
      'she threatened me',
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
      'what is my bmi',
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

  test('faith routes to cloud', () {
    final d = RoutingDecision.route('is this islam');
    expect(d.useCloud, isTrue);
    expect(d.needsHuman, isFalse);
  });

  test('business stays local', () {
    final d = RoutingDecision.route('draft a follow up for my client');
    expect(d.useCloud, isFalse);
    expect(d.needsHuman, isFalse);
  });
}
