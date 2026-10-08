import 'dart:convert';

/// Cloud providers Koru can talk to, and the wire formats they use.
///
/// The previous version hardcoded one endpoint and one model. Adding a key for
/// any other provider therefore could not work: the request went to OpenRouter
/// regardless, with `anthropic/claude-3.5-sonnet` hardcoded as the model, and a
/// save that silently failed still showed "Key saved".
///
/// Everything here is pure data and pure functions, so the request each provider
/// receives is unit tested without a network call.

/// How a provider expects to be called.
enum CloudWireFormat {
  /// POST {base}/chat/completions with a bearer token. OpenAI, OpenRouter,
  /// Groq, Together, DeepSeek, Mistral, xAI and most self-hosted servers.
  openai,

  /// POST {base}/messages with x-api-key and a system block. Anthropic.
  anthropic,

  /// POST {base}/models/{model}:generateContent?key=. Google.
  gemini,
}

class CloudProvider {
  const CloudProvider({
    required this.id,
    required this.label,
    required this.baseUrl,
    required this.format,
    required this.keyHint,
    this.models = const [],
    this.keyLabel = 'API key',
    this.note,
  });

  final String id;
  final String label;
  final String baseUrl;
  final CloudWireFormat format;

  /// What a key for this provider looks like, shown under the field.
  final String keyHint;
  final String keyLabel;

  /// A short curated list. Not exhaustive on purpose: anything can still be
  /// typed by hand, because providers add models faster than a shipped list.
  final List<String> models;

  final String? note;
}

/// Providers offered up front. Anything not here still works through Custom,
/// which speaks the OpenAI format that nearly every server implements.
const List<CloudProvider> kCloudProviders = [
  CloudProvider(
    id: 'openrouter',
    label: 'OpenRouter',
    baseUrl: 'https://openrouter.ai/api/v1',
    format: CloudWireFormat.openai,
    keyHint: 'sk-or-v1-...',
    models: [
      'anthropic/claude-3.5-sonnet',
      'anthropic/claude-3-haiku',
      'openai/gpt-4o-mini',
      'google/gemini-flash-1.5',
      'meta-llama/llama-3.1-8b-instruct',
      'qwen/qwen-2.5-72b-instruct',
    ],
    note: 'One key, many models. The easiest place to start.',
  ),
  CloudProvider(
    id: 'openai',
    label: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    format: CloudWireFormat.openai,
    keyHint: 'sk-...',
    models: ['gpt-4o-mini', 'gpt-4o', 'gpt-4.1-mini', 'o4-mini'],
  ),
  CloudProvider(
    id: 'anthropic',
    label: 'Anthropic',
    baseUrl: 'https://api.anthrop.com/v1',
    format: CloudWireFormat.anthropic,
    keyHint: 'sk-ant-...',
    keyLabel: 'Anthropic API key',
    models: ['claude-3-5-sonnet-20241022', 'claude-3-5-haiku-20241022', 'claude-sonnet-4-20250514'],
  ),
  CloudProvider(
    id: 'gemini',
    label: 'Google Gemini',
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
    format: CloudWireFormat.gemini,
    keyHint: 'AIza...',
    keyLabel: 'Google AI Studio key',
    models: ['gemini-2.0-flash', 'gemini-1.5-flash', 'gemini-1.5-pro'],
  ),
  CloudProvider(
    id: 'groq',
    label: 'Groq',
    baseUrl: 'https://api.groq.com/openai/v1',
    format: CloudWireFormat.openai,
    keyHint: 'gsk_...',
    models: ['llama-3.3-70b-versatile', 'llama-3.1-8b-instant', 'mixtral-8x7b-32768'],
    note: 'Very fast, free tier available.',
  ),
  CloudProvider(
    id: 'together',
    label: 'Together',
    baseUrl: 'https://api.together.xyz/v1',
    format: CloudWireFormat.openai,
    keyHint: '...',
    models: ['meta-llama/Llama-3.3-70B-Instruct-Turbo', 'Qwen/Qwen2.5-72B-Instruct-Turbo'],
  ),
  CloudProvider(
    id: 'deepseek',
    label: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com/v1',
    format: CloudWireFormat.openai,
    keyHint: 'sk-...',
    models: ['deepseek-chat', 'deepseek-reasoner'],
    note: 'Cheap, and reasoner is good with code.',
  ),
  CloudProvider(
    id: 'mistral',
    label: 'Mistral',
    baseUrl: 'https://api.mistral.ai/v1',
    format: CloudWireFormat.openai,
    keyHint: '...',
    models: ['mistral-small-latest', 'mistral-large-latest'],
  ),
  CloudProvider(
    id: 'xai',
    label: 'xAI Grok',
    baseUrl: 'https://api.x.ai/v1',
    format: CloudWireFormat.openai,
    keyHint: 'xai-...',
    models: ['grok-3-mini', 'grok-3'],
  ),
  CloudProvider(
    id: 'custom',
    label: 'Custom / self-hosted',
    baseUrl: 'http://127.0.0.1:8080/v1',
    format: CloudWireFormat.openai,
    keyHint: 'Leave blank if the server needs no key',
    note: 'Anything that speaks the OpenAI chat API: llama.cpp, LM Studio, '
        'vLLM, Ollama, OpenAI-compatible gateways.',
  ),
];

CloudProvider providerById(String id) => kCloudProviders.firstWhere(
      (p) => p.id == id,
      orElse: () => kCloudProviders.last,
    );

/// A request built for a specific provider.
class CloudRequest {
  const CloudRequest({
    required this.uri,
    required this.headers,
    required this.body,
    required this.providerId,
    required this.model,
  });

  final Uri uri;
  final Map<String, String> headers;
  final String body;
  final String providerId;
  final String model;
}

/// Builds requests and reads replies for every supported provider.
///
/// Split out from the caller so each provider's exact request shape is asserted
/// in tests. Getting the shape wrong is the difference between "nothing
/// responds" and a working answer, and there is no way to tell the two apart
/// from the failure.
class CloudAdapter {
  const CloudAdapter._();

  static Uri endpoint(CloudProvider provider, String model, String apiKey) {
    final base = provider.baseUrl.endsWith('/')
        ? provider.baseUrl.substring(0, provider.baseUrl.length - 1)
        : provider.baseUrl;
    switch (provider.format) {
      case CloudWireFormat.openai:
        return Uri.parse('$base/chat/completions');
      case CloudWireFormat.anthropic:
        return Uri.parse('$base/messages');
      case CloudWireFormat.gemini:
        return Uri.parse('$base/models/$model:generateContent').replace(
          queryParameters: {'key': apiKey},
        );
    }
  }

  static CloudRequest build({
    required CloudProvider provider,
    required String model,
    required String apiKey,
    required String system,
    required String question,
    int maxTokens = 600,
  }) {
    final uri = endpoint(provider, model, apiKey);
    switch (provider.format) {
      case CloudWireFormat.openai:
        return CloudRequest(
          uri: uri,
          headers: {
            if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
            if (provider.id == 'openrouter') ...{
              'HTTP-Referer': 'https://github.com/AbduljabbarBXR/koru',
              'X-Title': 'Koru',
            },
          },
          body: jsonEncode({
            'model': model,
            'messages': [
              {'role': 'system', 'content': system},
              {'role': 'user', 'content': question},
            ],
            'max_tokens': maxTokens,
          }),
          providerId: provider.id,
          model: model,
        );

      case CloudWireFormat.anthropic:
        // Anthropic takes the system prompt as its own field, and requires an
        // explicit version header or it refuses the request.
        return CloudRequest(
          uri: uri,
          headers: {
            if (apiKey.isNotEmpty) 'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': model,
            'max_tokens': maxTokens,
            'system': system,
            'messages': [
              {'role': 'user', 'content': question},
            ],
          }),
          providerId: provider.id,
          model: model,
        );

      case CloudWireFormat.gemini:
        return CloudRequest(
          uri: uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'systemInstruction': {
              'parts': [
                {'text': system},
              ],
            },
            'contents': [
              {
                'role': 'user',
                'parts': [
                  {'text': question},
                ],
              },
            ],
            'generationConfig': {'maxOutputTokens': maxTokens},
          }),
          providerId: provider.id,
          model: model,
        );
    }
  }

  /// Pulls the assistant text out of a provider's reply, or null.
  static String? parseText(CloudWireFormat format, String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;

    switch (format) {
      case CloudWireFormat.openai:
        final choices = decoded['choices'];
        if (choices is! List || choices.isEmpty) return null;
        final message = choices.first is Map ? (choices.first as Map)['message'] : null;
        if (message is! Map) return null;
        final content = message['content'];
        if (content is String) return content;
        // Some gateways send content as a list of parts.
        if (content is List) {
          final buffer = StringBuffer();
          for (final part in content) {
            if (part is Map && part['text'] is String) buffer.write(part['text']);
          }
          return buffer.isEmpty ? null : buffer.toString();
        }
        return null;

      case CloudWireFormat.anthropic:
        final content = decoded['content'];
        if (content is! List || content.isEmpty) return null;
        final buffer = StringBuffer();
        for (final block in content) {
          if (block is Map && block['type'] == 'text' && block['text'] is String) {
            buffer.write(block['text']);
          }
        }
        return buffer.isEmpty ? null : buffer.toString();

      case CloudWireFormat.gemini:
        final candidates = decoded['candidates'];
        if (candidates is! List || candidates.isEmpty) return null;
        final first = candidates.first;
        if (first is! Map) return null;
        final content = first['content'];
        if (content is! Map) return null;
        final parts = content['parts'];
        if (parts is! List) return null;
        final buffer = StringBuffer();
        for (final part in parts) {
          if (part is Map && part['text'] is String) buffer.write(part['text']);
        }
        return buffer.isEmpty ? null : buffer.toString();
    }
  }

  /// Turns a provider's error body into something worth reading.
  ///
  /// Without this, every failure arrived as "the cloud model returned 401" with
  /// the reason discarded, which is exactly the situation that made a bad key
  /// look like a dead app.
  static String explain(CloudProvider provider, int status, String body) {
    String? detail;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map) {
          detail = (error['message'] ?? error['type'])?.toString();
        } else if (error is String) {
          detail = error;
        }
        detail ??= decoded['message']?.toString();
      }
    } catch (_) {
      if (body.trim().isNotEmpty && body.length < 200) detail = body.trim();
    }

    final reason = switch (status) {
      400 => '${provider.label} rejected the request as malformed.',
      401 || 403 => 'That key was rejected by ${provider.label}.',
      404 => '${provider.label} does not know that model.',
      429 => '${provider.label} is rate limiting you.',
      >= 500 => '${provider.label} had a problem on its own side.',
      _ => '${provider.label} returned $status.',
    };
    if (detail == null || detail.isEmpty) return reason;
    return '$reason $detail';
  }
}
