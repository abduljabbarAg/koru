import 'package:flutter_test/flutter_test.dart';
import 'package:koru/cloud_providers.dart';
import 'package:koru/engine.dart';
import 'package:koru/packet.dart';

/// The guards and the one engine, tested on their own.
///
/// These exist because of measured behaviour on real devices, not because of
/// theory. The small on-device model that has since been removed answered a
/// dosing question with dosing advice and a contract question with a ruling,
/// after the routing gate was bypassed by talking to the server directly, and it
/// cheerfully reported saving a record it could not have saved. The engine it
/// ran on is gone; the obligations are not, and the lists below are what
/// survives of them.
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
      // Verbatim from the measured run. If the wording this list is protecting
      // against changes, this stops matching, which is a reason to look again
      // rather than to relax it.
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
        'Your hourly rate is 250 AED.',
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

  group('a model claiming it saved something', () {
    test('catches the ordinary ways of claiming one', () {
      for (final claim in [
        "I've added Bilal for 2000.",
        'I have added Bilal.',
        'I added the client.',
        "I've saved that.",
        'Saved successfully.',
        'All set.',
      ]) {
        expect(WriteClaimGuard.claimsWrite(claim), isTrue, reason: claim);
      }
    });

    test('catches it through curly punctuation and odd casing', () {
      // The guard folds case and punctuation before matching, and used to fold
      // the answer but not the needle, so an apostrophe in the needle made it
      // match nothing at all.
      expect(WriteClaimGuard.claimsWrite('I’ve added Bilal'), isTrue);
      expect(WriteClaimGuard.claimsWrite('ADDED SUCCESSFULLY'), isTrue);
    });

    test('does not fire on an ordinary answer', () {
      for (final answer in [
        'Bilal owes you 2000.',
        'You have four clients still to chase.',
        'The invoice is due on the 14th.',
      ]) {
        expect(WriteClaimGuard.claimsWrite(answer), isFalse, reason: answer);
      }
    });

    test('the replacement tells you the phrasing that would work', () {
      expect(WriteClaimGuard.nothingWasSaved, contains('add client'));
      expect(WriteClaimGuard.nothingWasSaved, contains('not saved'));
    });
  });

  group('KoruEngine', () {
    // The migration. This is the only thing standing between an install that was
    // on a removed engine and a chat that cannot answer anything, so it is
    // checked on the exact strings that are sitting in the profile table on
    // somebody's phone rather than on the shape of the enum.
    test('an install on the removed on-device engine lands on the one that exists',
        () {
      expect(KoruEngine.parse('onDevice'), KoruEngine.cloud,
          reason: "the literal string on disk today is 'onDevice'");
    });

    test('an install on the older removed engine lands on the one that exists', () {
      expect(KoruEngine.parse('builtIn'), KoruEngine.cloud,
          reason: "the literal string on disk was 'builtIn'");
    });

    test('an unknown or absent stored value lands on the one that exists', () {
      for (final stored in [null, '', 'nonsense', 'BUILTIN', 'on device', '0']) {
        expect(KoruEngine.parse(stored), KoruEngine.cloud,
            reason: 'parse($stored) must not leave the app with no engine');
      }
    });

    test('a stored value that is still the real engine is respected', () {
      expect(KoruEngine.parse('cloud'), KoruEngine.cloud);
    });

    test('there is exactly one engine, and it is the cloud one', () {
      // A second value here would be a claim the app cannot keep: there is
      // nothing to add it to.
      expect(KoruEngine.values, [KoruEngine.cloud]);
    });

    test('the engine names itself, and the name is used everywhere', () {
      // One getter, because the app bar, the switcher, the badge on a reply and
      // Settings all read it. Four copies of the words is how the same engine
      // came to be called four different things.
      expect(KoruEngine.cloud.label, 'Cloud model');
    });
  });

  group('EngineLink', () {
    CloudProvider stub(String id, String label) =>
        CloudProvider(
          id: id,
          label: label,
          baseUrl: 'https://example.test',
          format: CloudWireFormat.openai,
          keyHint: 'sk-test',
        );

    test('a saved key is the only thing that counts as connected', () {
      // Not the selection: a provider is always "selected", the default one is
      // filled in for somebody who has never chosen anything, so a link reading
      // "connected" from that would be true on a fresh install and mean nothing.
      final provider = stub('openrouter', 'OpenRouter');
      expect(
        EngineLink(provider: provider, model: 'a', hasKey: true).isConnected,
        isTrue,
      );
      expect(
        EngineLink(provider: provider, model: 'a', hasKey: false).isConnected,
        isFalse,
      );
    });

    test('the label names the company when there is one, and says so when not',
        () {
      final provider = stub('openrouter', 'OpenRouter');
      expect(
        EngineLink(provider: provider, model: 'a', hasKey: true).label,
        'OpenRouter',
      );
      expect(
        EngineLink(provider: provider, model: 'a', hasKey: false).label,
        'No model connected',
      );
    });

    test('two missing-key states, two different sentences', () {
      final provider = stub('openrouter', 'OpenRouter');
      // Nobody has chosen anything yet.
      final nothing = EngineLink(provider: provider, model: 'a', hasKey: false);
      // A company was chosen and its key never arrived.
      final missing = EngineLink(
        provider: provider,
        model: 'a',
        hasKey: false,
        providerChosen: true,
      );
      expect(nothing.missing, 'No model is connected yet.');
      expect(missing.missing, 'No OpenRouter key is saved.');
      expect(nothing.recovery, EngineRecovery.connectCloud);
      expect(missing.recovery, EngineRecovery.addCloudKey);
    });

    test('a link that could not be read says so rather than guessing', () {
      // A keystore that is gone leaves the app unable to tell. It says nothing
      // is connected, which is a statement about what it knows, and offers the
      // same tap.
      expect(EngineLink.unreadable.isConnected, isFalse);
      expect(EngineLink.unreadable.missing, 'No model is connected yet.');
      expect(EngineLink.unreadable.label, 'No model connected');
      expect(EngineLink.unreadable.recovery, EngineRecovery.connectCloud);
    });

    test('a connected link has nothing missing to report', () {
      final link = EngineLink(
        provider: stub('openrouter', 'OpenRouter'),
        model: 'a',
        hasKey: true,
      );
      expect(link.missing, isEmpty);
    });
  });

  group('EngineUnavailable', () {
    // The wording is the feature. The old behaviour answered a question nobody
    // asked with rules-based prose; what replaced it has to say what is missing
    // and what to do about it, in that order, on every path.
    test('a missing key says which provider and offers to add one', () {
      const down = EngineUnavailable(
        detail: 'There is no OpenRouter key saved',
        recovery: EngineRecovery.addCloudKey,
      );
      expect(down.text, contains('cannot answer'));
      expect(down.text, contains('OpenRouter'));
      expect(down.actionLabel, 'Add a cloud key');
    });

    test('nothing connected offers to connect one', () {
      const down = EngineUnavailable(
        detail: 'No model is connected yet.',
        recovery: EngineRecovery.connectCloud,
      );
      expect(down.title, 'No model connected');
      expect(down.text, contains('Nothing is connected'));
      expect(down.actionLabel, 'Connect a cloud model');
    });

    test('no offer is phrased as an answer', () {
      for (final recovery in EngineRecovery.values) {
        final down = EngineUnavailable(detail: 'x', recovery: recovery);
        expect(down.text, startsWith('I cannot answer that.'));
        expect(down.title, isNot(contains('?')));
      }
    });
  });

  group('routing gate covers the model failure cases', () {
    // The three questions the measured model got dangerously wrong. Each has to
    // be stopped before a model is asked, which is the actual safety property.
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
          reason: 'must never reach a model: "$phrase"',
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
          reason: 'must never reach a model: "$question"',
        );
      }
    });

    test('an ordinary question is handed on, and says which model takes it', () {
      final decision = RoutingDecision.route('who owes me money?');
      expect(decision.needsHuman, isFalse);
      expect(decision.reason, contains('cloud model'));
    });
  });
}