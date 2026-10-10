import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:koru/cloud.dart';
import 'package:koru/cloud_providers.dart';
import 'package:koru/guide.dart';
import 'package:koru/models.dart';

/// The bug this exists to prevent: someone pasted a working key, the app sent it
/// to the one hardcoded endpoint with one hardcoded model, and nothing happened.
/// Each provider's exact request shape is asserted here so that cannot be
/// silent again.
void main() {
  group('provider registry', () {
    test('covers the providers people actually have keys for', () {
      final ids = kCloudProviders.map((p) => p.id).toSet();
      for (final expected in [
        'openrouter', 'openai', 'anthropic', 'gemini', 'groq',
        'together', 'deepseek', 'mistral', 'xai', 'custom',
      ]) {
        expect(ids, contains(expected), reason: 'missing provider $expected');
      }
    });

    test('every provider suggests a model, except custom', () {
      // Custom is whatever the user happens to be running, so a shipped list
      // would be a guess. The UI falls back to a free text field when empty.
      for (final provider in kCloudProviders.where((p) => p.id != 'custom')) {
        expect(provider.models, isNotEmpty, reason: '${provider.id} has no models');
      }
      expect(providerById('custom').models, isEmpty);
    });

    test('no provider has a duplicate model or an empty id', () {
      for (final provider in kCloudProviders) {
        expect(provider.id.trim(), isNotEmpty);
        expect(provider.models.toSet().length, provider.models.length,
            reason: '${provider.id} lists a model twice');
      }
    });

    test('an unknown id falls back rather than throwing', () {
      expect(providerById('nonsense').id, 'custom');
      expect(providerById('openai').id, 'openai');
    });

    test('base urls have no trailing slash', () {
      for (final provider in kCloudProviders) {
        expect(provider.baseUrl.endsWith('/'), isFalse, reason: provider.id);
      }
    });
  });

  group('openai wire format', () {
    final provider = providerById('openrouter');

    CloudRequest build() => CloudAdapter.build(
          provider: provider,
          model: 'anthropic/claude-3.5-sonnet',
          apiKey: 'sk-or-v1-test',
          system: 'be brief',
          question: 'hello',
        );

    test('posts to chat completions', () {
      expect(build().uri.toString(),
          'https://openrouter.ai/api/v1/chat/completions');
    });

    test('authenticates with a bearer token', () {
      expect(build().headers['Authorization'], 'Bearer sk-or-v1-test');
    });

    test('sends the system prompt as its own message', () {
      final body = jsonDecode(build().body) as Map<String, dynamic>;
      final messages = body['messages'] as List;
      expect((messages.first as Map)['role'], 'system');
      expect((messages.first as Map)['content'], 'be brief');
      expect((messages.last as Map)['content'], 'hello');
      expect(body['model'], 'anthropic/claude-3.5-sonnet');
    });

    test('sends openrouter attribution', () {
      expect(build().headers['X-Title'], 'Koru');
    });

    test('omits the bearer token when there is no key', () {
      final request = CloudAdapter.build(
        provider: provider,
        model: 'm',
        apiKey: '',
        system: 's',
        question: 'q',
      );
      expect(request.headers.containsKey('Authorization'), isFalse);
    });

    test('does not send attribution for other providers', () {
      final request = CloudAdapter.build(
        provider: providerById('groq'),
        model: 'm',
        apiKey: 'k',
        system: 's',
        question: 'q',
      );
      expect(request.headers.containsKey('X-Title'), isFalse);
      expect(request.uri.toString(), 'https://api.groq.com/openai/v1/chat/completions');
    });

    test('reads the reply', () {
      const body = '{"choices":[{"message":{"content":"hi"}}]}';
      expect(CloudAdapter.parseText(CloudWireFormat.openai, body), 'hi');
    });

    test('reads a reply delivered as parts', () {
      const body = '{"choices":[{"message":{"content":[{"text":"a "},{"text":"b"}]}}]}';
      expect(CloudAdapter.parseText(CloudWireFormat.openai, body), 'a b');
    });
  });

  group('anthropic wire format', () {
    final provider = providerById('anthropic');

    CloudRequest build() => CloudAdapter.build(
          provider: provider,
          model: 'claude-3-5-sonnet-20241022',
          apiKey: 'sk-ant-test',
          system: 'be brief',
          question: 'hello',
        );

    test('posts to messages', () {
      expect(build().uri.toString(), 'https://api.anthrop.com/v1/messages');
    });

    test('authenticates with x-api-key, not a bearer token', () {
      final headers = build().headers;
      expect(headers['x-api-key'], 'sk-ant-test');
      expect(headers.containsKey('Authorization'), isFalse);
    });

    test('sends the version header it requires', () {
      expect(build().headers['anthropic-version'], '2023-06-01');
    });

    test('sends the system prompt as its own field, not a message', () {
      final body = jsonDecode(build().body) as Map<String, dynamic>;
      expect(body['system'], 'be brief');
      final messages = body['messages'] as List;
      expect(messages, hasLength(1));
      expect((messages.first as Map)['role'], 'user');
      expect(body.containsKey('max_tokens'), isTrue);
    });

    test('reads a content block reply', () {
      const body = '{"content":[{"type":"text","text":"hi"}]}';
      expect(CloudAdapter.parseText(CloudWireFormat.anthropic, body), 'hi');
    });

    test('skips non text blocks', () {
      const body = '{"content":[{"type":"thinking"},{"type":"text","text":"ok"}]}';
      expect(CloudAdapter.parseText(CloudWireFormat.anthropic, body), 'ok');
    });
  });

  group('gemini wire format', () {
    final provider = providerById('gemini');

    CloudRequest build() => CloudAdapter.build(
          provider: provider,
          model: 'gemini-2.0-flash',
          apiKey: 'AIzaTest',
          system: 'be brief',
          question: 'hello',
        );

    test('posts to generateContent with the key in the query', () {
      final uri = build().uri;
      expect(uri.path, contains('models/gemini-2.0-flash:generateContent'));
      expect(uri.queryParameters['key'], 'AIzaTest');
    });

    test('uses contents and systemInstruction', () {
      final body = jsonDecode(build().body) as Map<String, dynamic>;
      expect((body['systemInstruction'] as Map)['parts'], isNotEmpty);
      final contents = body['contents'] as List;
      expect((contents.first as Map)['role'], 'user');
      expect((body['generationConfig'] as Map)['maxOutputTokens'], isNotNull);
    });

    test('reads a candidates reply', () {
      const body = '{"candidates":[{"content":{"parts":[{"text":"hi"}]}}]}';
      expect(CloudAdapter.parseText(CloudWireFormat.gemini, body), 'hi');
    });
  });

  group('error explanations', () {
    test('a rejected key says so and quotes the provider', () {
      final text = CloudAdapter.explain(
        providerById('anthropic'),
        401,
        '{"error":{"type":"authentication_error","message":"invalid x-api-key"}}',
      );
      expect(text, contains('Anthropic'));
      expect(text, contains('rejected'));
      expect(text, contains('invalid x-api-key'));
    });

    test('a bad model name is distinguishable from a bad key', () {
      final text = CloudAdapter.explain(
        providerById('openai'),
        404,
        '{"error":{"message":"The model does not exist"}}',
      );
      expect(text, contains('does not know that model'));
    });

    test('rate limiting reads as rate limiting', () {
      expect(
        CloudAdapter.explain(providerById('groq'), 429, ''),
        contains('rate limiting'),
      );
    });

    test('a server fault does not blame the key', () {
      expect(
        CloudAdapter.explain(providerById('openai'), 503, ''),
        contains('its own side'),
      );
    });

    test('a body that is not json still yields the status reason', () {
      expect(
        CloudAdapter.explain(providerById('deepseek'), 400, 'gateway timeout'),
        contains('malformed'),
      );
    });

    test('unrecognised statuses still name the provider', () {
      expect(CloudAdapter.explain(providerById('mistral'), 418, ''), contains('Mistral'));
    });
  });

  group('reply extraction compatibility', () {
    test('the old entry point still reads an openai reply', () {
      expect(
        CloudModel.extractReply('{"choices":[{"message":{"content":"x"}}]}'),
        'x',
      );
    });
  });

  group('Guide', () {
    ScreenFacts facts({
      List<Client> clients = const [],
      List<FitnessEntry> fitness = const [],
      Map<int, double> received = const {},
      double? bmi,
      bool hasProfile = false,
    }) =>
        ScreenFacts(
          clients: clients,
          fitness: fitness,
          received: received,
          bmi: bmi,
          hasProfile: hasProfile,
        );

    group('business', () {
      test('says nothing helpful when there are no clients', () {
        expect(Guide.forBusiness(facts()), contains('No clients yet'));
      });

      test('names the one client who owes, and how much', () {
        final line = Guide.forBusiness(facts(
          clients: const [Client(id: 1, name: 'Acme', status: 'delivered', amount: 2400)],
        ));
        expect(line, contains('Acme owes you 2400 AED'));
      });

      test('counts a part payment, so a part payer still reads as owing', () {
        final line = Guide.forBusiness(facts(
          clients: const [Client(id: 1, name: 'Acme', status: 'delivered', amount: 2400)],
          received: const {1: 500},
        ));
        expect(line, contains('Acme owes you 1900 AED'));
      });

      test('adds up several debtors and leads with the largest', () {
        final line = Guide.forBusiness(facts(
          clients: const [
            Client(id: 1, name: 'Small', status: 'delivered', amount: 100),
            Client(id: 2, name: 'Big', status: 'delivered', amount: 3000),
          ],
        ));
        expect(line, contains('2 clients owe you 3100 AED'));
        expect(line, contains('Big most of all'));
      });

      test('says nothing is owed once the ledger is settled', () {
        final line = Guide.forBusiness(facts(
          clients: const [Client(id: 1, name: 'Acme', status: 'paid', amount: 2400)],
          received: const {1: 2400},
        ));
        expect(line, isNot(contains('owes')));
      });

      test('a client marked paid but never actually paid still reads as owing', () {
        // The ledger is the only thing that settles a client. Status alone is
        // a label someone typed, so this is a data-entry mistake worth
        // surfacing rather than hiding behind the flag.
        final line = Guide.forBusiness(facts(
          clients: const [Client(id: 1, name: 'B', status: 'paid', amount: 100)],
        ));
        expect(line, contains('B owes you 100 AED'));
      });

      test('mentions the pipeline when nothing is unpaid', () {
        final line = Guide.forBusiness(facts(
          clients: const [
            Client(id: 1, name: 'A', status: 'active'),
            Client(id: 2, name: 'B', status: 'paid', amount: 100),
          ],
          received: const {2: 100},
        ));
        expect(line, contains('pipeline'));
      });
    });

    group('fitness', () {
      test('refuses to call one reading a trend', () {
        final line = Guide.forFitness(facts(
          fitness: const [FitnessEntry(day: '2026-02-28', weight: 80)],
          bmi: 24.7,
        ));
        expect(line, contains('not a trend'));
      });

      test('reports the band and the trend once there is history', () {
        final line = Guide.forFitness(facts(
          fitness: const [
            FitnessEntry(day: '2026-02-28', weight: 78),
            FitnessEntry(day: '2026-02-14', weight: 80),
          ],
          bmi: 24.1,
        ));
        expect(line, contains('24.1'));
        expect(line, contains('healthy range'));
        expect(line, contains('-1.00 kg a week'));
      });

      test('asks for a baseline when there is nothing', () {
        expect(Guide.forFitness(facts()), contains('baseline'));
      });

      test('does not present a bmi band as a verdict', () {
        final line = Guide.forFitness(facts(
          fitness: const [
            FitnessEntry(day: '2026-02-28', weight: 95),
            FitnessEntry(day: '2026-02-14', weight: 96),
          ],
          bmi: 29.3,
        ));
        expect(line, contains('not a verdict'));
      });
    });

    group('settings and chat', () {
      test('settings is silent when there is nothing worth saying', () {
        // Context plus a client means there is nothing left to prompt about.
        final line = Guide.forSettings(facts(
          hasProfile: true,
          clients: const [Client(name: 'A', status: 'paid', created: '2026-01-01')],
        ));
        expect(line, isNull);
      });

      test('settings prompts when context exists but records do not', () {
        final line = Guide.forSettings(
          ScreenFacts(hasProfile: true),
        );
        expect(line, contains('measurement'));
      });

      test('chat prompts only when goals exist with nothing to check against', () {
        expect(
          Guide.forChat(ScreenFacts(hasProfile: true)),
          contains('goals'),
        );
        expect(Guide.forChat(facts()), isNull);
      });
    });

    group('vary', () {
      test('drops nulls and never returns null for a full list', () {
        for (var seed = 0; seed < 12; seed++) {
          final out = Guide.vary(const ['a', 'b', null], seed);
          expect(out, anyOf('a', 'b'));
        }
      });

      test('returns null when everything is null', () {
        expect(Guide.vary(const [null, null], 1), isNull);
        expect(Guide.vary(const [], 1), isNull);
      });
    });

    group('ScreenFacts trend', () {
      test('needs two readings three days apart', () {
        expect(facts().weightTrendPerWeek, isNull);
        expect(
          facts(fitness: const [
            FitnessEntry(day: '2026-02-28', weight: 80),
            FitnessEntry(day: '2026-02-27', weight: 82),
          ]).weightTrendPerWeek,
          isNull,
        );
      });

      test('ignores readings with no weight', () {
        final f = facts(fitness: const [
          FitnessEntry(day: '2026-02-28'),
          FitnessEntry(day: '2026-02-21', weight: 80),
          FitnessEntry(day: '2026-02-14', weight: 81),
        ]);
        expect(f.weightTrendPerWeek, closeTo(-1.0, 0.01));
      });
    });
  });
}
