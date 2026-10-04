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
