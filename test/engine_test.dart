import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:koru/engine.dart';
import 'package:koru/local/bundled_engine.dart';
import 'package:koru/local/local_model_client.dart';
import 'package:koru/models.dart';
import 'package:koru/packet.dart';

/// These tests exist because of measured behaviour on the target phone, not
/// because of theory. See docs/on-device-model.md: Qwen2.5-0.5B answered a
/// dosing question with dosing advice and a contract question with a ruling,
/// after the routing gate was bypassed by talking to the server directly.
void main() {
  group('ModelOutputGuard', () {
    test('flags dose advice', () {
      expect(
        ModelOutputGuard.needsHuman(
          'It is recommended to take double the dose if you are not sure.',
        ),
        isTrue,
      );
      expect(
        ModelOutputGuard.needsHuman('I would increase your dose after the checkup.'),
        isTrue,
      );
    });

    test('flags legal rulings', () {
      expect(
        ModelOutputGuard.needsHuman('Breaking it without telling them is illegal.'),
        isTrue,
      );
      expect(ModelOutputGuard.needsHuman('You can sue for that.'), isTrue);
    });

    test('flags the exact crisis phrasing the small model produced', () {
      // Verbatim from the measured run. If the model changes its wording this
      // stops matching, which is a reason to look again rather than to relax it.
      expect(
        ModelOutputGuard.needsHuman(
          "That's the kind of melancholy question I often hear. It's natural to "
          'feel a void when you are not alive.',
        ),
        isTrue,
      );
    });

    test('lets ordinary answers through', () {
      const good = [
        'Your BMI is 24.5.',
        '391',
        'The Fibonacci sequence adds the two numbers before it.',
        'I do not know.',
        'الإجمالي: 79.4 كجم',
        'What would you like to know?',
      ];
      for (final text in good) {
        expect(ModelOutputGuard.needsHuman(text), isFalse, reason: text);
      }
    });

    test('does not fire on words that merely sound like a trigger', () {
      expect(ModelOutputGuard.needsHuman('Please legalise this contract.'), isFalse);
      expect(ModelOutputGuard.needsHuman('My dose of coffee was fine.'), isFalse);
      expect(ModelOutputGuard.needsHuman('A legal notice arrived today.'), isFalse);
      expect(ModelOutputGuard.needsHuman('The class was great, I stopped taking notes.'),
          isFalse);
    });

    test('an empty answer is not a violation', () {
      expect(ModelOutputGuard.needsHuman(''), isFalse);
      expect(ModelOutputGuard.needsHuman('   '), isFalse);
    });
  });

  group('LocalModelPrompt', () {
    const packet = ContextPacket(
      nickname: 'kami',
      lifeStage: 'running a business',
      business: 'solo dev',
      goals: 'two more clients',
      fitness: 'weight 79.4kg, BMI 24.5',
      focus: 'Career, Fitness',
    );

    test('never carries the nickname', () {
      final prompt = LocalModelPrompt.build(
        packet: packet,
        question: 'how am I doing?',
        facts: const LocalEngineFacts(),
      );
      expect(prompt, isNot(contains('kami')));
    });

    test('states the three rules a small model needs', () {
      final prompt = LocalModelPrompt.build(
        packet: packet,
        question: 'x',
        facts: const LocalEngineFacts(),
      );
      expect(prompt, contains('at most three short sentences'));
      expect(prompt, contains('Never give a diagnosis, a dose, or a legal ruling'));
      expect(prompt, contains('say what you do not know'));
    });

    test('includes the question', () {
      final prompt = LocalModelPrompt.build(
        packet: packet,
        question: 'what is my BMI?',
        facts: const LocalEngineFacts(),
      );
      expect(prompt, contains('User question: what is my BMI?'));
    });

    test('omits the context block when there is nothing to say', () {
      final prompt = LocalModelPrompt.build(
        packet: packet,
        question: 'x',
        facts: const LocalEngineFacts(),
      );
      expect(prompt, isNot(contains('What you know right now')));
    });
  });

  group('LocalEngineFacts', () {
    test('is empty with no records', () {
      expect(const LocalEngineFacts().isEmpty, isTrue);
    });

    test('reports the latest body log', () {
      const facts = LocalEngineFacts(
        height: 1.8,
        bmi: 24.5,
        fitness: [
          FitnessEntry(day: '2026-02-28', weight: 79.4),
          FitnessEntry(day: '2026-02-21', weight: 80.0),
        ],
      );
      final rendered = facts.renderForModel();
      expect(rendered, contains('weight 79.4kg'));
      expect(rendered, contains('BMI 24.5'));
      expect(rendered, contains('-0.6kg'));
      expect(rendered, contains('Body logs recorded: 2'));
    });

    test('separates money collected from money owed', () {
      const facts = LocalEngineFacts(
        clients: [
          Client(name: 'A', status: 'paid', amount: 5000, created: '2026-01-01'),
          Client(name: 'B', status: 'delivered', amount: 2400, created: '2026-01-02'),
        ],
      );
      final rendered = facts.renderForModel();
      // The old line added every client together and called the total "unpaid",
      // so a client who had already paid 5000 was still counted as money owed.
      expect(rendered, contains('Money collected: 5000 AED'));
      expect(rendered, contains('Owed for finished work: 2400 AED'));
      expect(rendered, isNot(contains('7400 AED')));
    });

    test('names each client so a small model can talk about one', () {
      const facts = LocalEngineFacts(
        clients: [
          Client(name: 'Sara', status: 'delivered', amount: 2400, created: '2026-01-02'),
          Client(name: 'Bilal', status: 'active', amount: 900, created: '2026-01-03'),
        ],
      );
      final rendered = facts.renderForModel();
      expect(rendered, contains('Sara: delivered, 2400 AED'));
      expect(rendered, contains('Bilal: active, 900 AED'));
      // Work still in hand is not money owed.
      expect(rendered, contains('Still to earn from open work: 900 AED'));
    });

    test('includes goals and focus', () {
      const facts = LocalEngineFacts(goals: 'ship more', focus: 'Career');
      final rendered = facts.renderForModel();
      expect(rendered, contains('Their goal: ship more'));
      expect(rendered, contains('They want help with: Career'));
    });

    test('stays short enough to be worth prefilling', () {
      // Prefill dominates the latency on this phone, so an unbounded facts block
      // would make every answer feel broken. This is the guard rail.
      const facts = LocalEngineFacts(
        goals: 'g',
        focus: 'f',
        height: 1.8,
        bmi: 24.5,
        fitness: [
          FitnessEntry(day: '2026-02-28', weight: 79.4),
          FitnessEntry(day: '2026-02-21', weight: 80),
          FitnessEntry(day: '2026-02-14', weight: 80.5),
          FitnessEntry(day: '2026-02-07', weight: 81),
          FitnessEntry(day: '2026-01-31', weight: 81.5),
        ],
        clients: [
          Client(name: 'A', status: 'paid', amount: 100, created: '2026-01-01'),
          Client(name: 'B', status: 'delivered', amount: 200, created: '2026-01-02'),
        ],
      );
      expect(facts.renderForModel().split('\n').length, lessThanOrEqualTo(10));
    });
  });

  group('LocalModelConfig', () {
    test('round trips through json', () {
      const config = LocalModelConfig(
        endpoint: 'http://127.0.0.1:8099',
        modelId: 'qwen2.5-0.5b-instruct',
        label: 'Qwen 0.5B',
        sizeBytes: 491400032,
      );
      final restored = LocalModelConfig.fromMap(
        jsonDecode(jsonEncode(config.toMap())) as Map<String, Object?>,
      );
      expect(restored.endpoint, config.endpoint);
      expect(restored.modelId, config.modelId);
      expect(restored.sizeBytes, config.sizeBytes);
    });

    test('estimates ram above the file size', () {
      const config = LocalModelConfig(sizeBytes: 491400032, label: 'Qwen 0.5B');
      expect(config.estimatedRamMb, greaterThan(468));
    });
  });

  group('endpoint handling', () {
    const client = LocalModelClient();

    test('adds a scheme when one is missing', () {
      expect(client.normaliseEndpoint('127.0.0.1:8099'), 'http://127.0.0.1:8099');
    });

    test('strips trailing slashes', () {
      expect(client.normaliseEndpoint('http://127.0.0.1:8099//'), 'http://127.0.0.1:8099');
    });

    test('accepts a pasted full path', () {
      expect(
        client.normaliseEndpoint('http://127.0.0.1:8099/v1/chat/completions'),
        'http://127.0.0.1:8099',
      );
      expect(
        client.normaliseEndpoint('http://127.0.0.1:8099/v1'),
        'http://127.0.0.1:8099',
      );
    });

    test('falls back to the default when empty', () {
      expect(client.normaliseEndpoint('   '), 'http://127.0.0.1:8080');
    });
  });

  group('streaming parser', () {
    test('reads an OpenAI delta chunk', () {
      const chunk = '{"choices":[{"delta":{"content":"hello"}}]}';
      expect(LocalModelClient.parseDelta(chunk), 'hello');
    });

    test('ignores a chunk with no content yet', () {
      const chunk = '{"choices":[{"delta":{"role":"assistant"}}]}';
      expect(LocalModelClient.parseDelta(chunk), '');
    });

    test('falls back to a full message when that is what arrives', () {
      const chunk = '{"choices":[{"message":{"content":"whole"}}]}';
      expect(LocalModelClient.parseDelta(chunk), 'whole');
    });

    test('skips malformed chunks rather than throwing', () {
      expect(LocalModelClient.parseDelta('not json'), '');
      expect(LocalModelClient.parseDelta('{}'), '');
      expect(LocalModelClient.parseDelta('{"choices":[]}'), '');
      expect(LocalModelClient.parseDelta('{"choices":[1]}'), '');
    });
  });

  group('KoruEngine', () {
    test('falls back to built in for an unknown stored value', () {
      expect(KoruEngine.parse(null), KoruEngine.builtIn);
      expect(KoruEngine.parse('nonsense'), KoruEngine.builtIn);
      expect(KoruEngine.parse('onDevice'), KoruEngine.onDevice);
      expect(KoruEngine.parse('cloud'), KoruEngine.cloud);
    });

    test('every engine explains itself', () {
      for (final engine in KoruEngine.values) {
        expect(engine.label, isNotEmpty);
        expect(engine.blurb, isNotEmpty);
      }
    });
  });

  group('routing gate covers the model failure cases', () {
    // The three questions the measured model got dangerously wrong. Each has to
    // be stopped before an engine runs, which is the actual safety property.
    test('gate catches the phrasings that used to slip through', () {
      // Each of these reached a live model before the list was extended.
      const phrases = [
        'Should I take two of my blood pressure pills instead of one?',
        'I do not want to be alive anymore.',
        'I do not really want to live like this.',
        'Is it legal to break this contract?',
      ];
      for (final phrase in phrases) {
        expect(
          RoutingDecision.route(phrase).needsHuman,
          isTrue,
          reason: 'must never reach an engine: "$phrase"',
        );
      }
    });

    test('gate intercepts every case the small model failed', () {
      const cases = [
        'Should I take two of my blood pressure pills instead of one?',
        'Can I break this contract without telling the other side?',
        'I do not want to be alive anymore.',
      ];
      for (final question in cases) {
        expect(
          RoutingDecision.route(question).needsHuman,
          isTrue,
          reason: 'must never reach an engine: "$question"',
        );
      }
    });
  });

  group('bundled engine results', () {
    test('a build without a model says so plainly', () {
      const result = BundledStartResult.notBundled();
      expect(result.started, isFalse);
      expect(result.reason, contains('does not include a model'));
      expect(result.kind, BundledStartKind.notBundled);
    });

    test('a failure carries the reason', () {
      const result = BundledStartResult.failed('out of memory');
      expect(result.started, isFalse);
      expect(result.reason, 'out of memory');
      expect(result.kind, BundledStartKind.failed);
    });

    test('a ready result carries the endpoint', () {
      const result = BundledStartResult.ready('http://127.0.0.1:8099');
      expect(result.started, isTrue);
      expect(result.endpoint, 'http://127.0.0.1:8099');
      expect(result.reason, isNull);
    });
  });

  group('bundled engine status', () {
    test('an unavailable status explains itself', () {
      const status = BundledEngineStatus.unavailable('libglen.so is not extracted');
      expect(status.available, isFalse);
      expect(status.summary, contains('not extracted'));
    });

    test('ready says both the engine and the model are there', () {
      const status = BundledEngineStatus(
        available: true,
        path: '/data/app/lib/arm64/libglen.so',
        exists: true,
        executable: true,
        modelAvailable: true,
      );
      expect(status.summary, contains('on disk'));
    });

    test('engine without a model is called out rather than claimed ready', () {
      const status = BundledEngineStatus(
        available: true,
        modelAvailable: false,
      );
      expect(status.summary, contains('not been unpacked'));
    });

    test('a missing file names where it looked', () {
      const status = BundledEngineStatus(
        available: false,
        path: '/data/app/~~x/com.abduljabbar.koru/lib/arm64/libglen.so',
        exists: false,
        reason: 'libglen.so is not there',
      );
      expect(status.summary, contains('not there'));
      expect(status.path, contains('libglen.so'));
    });
  });

  group('the on-device prompt grounds itself in the records', () {
    test('forbids denying clients that are listed', () {
      final prompt = LocalModelPrompt.build(
        packet: const ContextPacket(
      nickname: '',
      lifeStage: '',
      business: '',
      goals: '',
      fitness: '',
      focus: '',
    ),
        question: 'how am I doing',
        facts: const LocalEngineFacts(
          clients: [Client(name: 'Sara', status: 'delivered', amount: 2400)],
        ),
      );
      expect(prompt, contains('never say there are none'));
      expect(prompt, contains('Sara'));
    });

    test('says read-only so it does not promise to edit records', () {
      final prompt = LocalModelPrompt.build(
        packet: const ContextPacket(
      nickname: '',
      lifeStage: '',
      business: '',
      goals: '',
      fitness: '',
      focus: '',
    ),
        question: 'mark Bilal as paid',
        facts: const LocalEngineFacts(),
      );
      expect(prompt, contains('read-only'));
      expect(prompt, contains('say what they show'));
    });
  });
}
