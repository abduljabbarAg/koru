import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Outcome of a local generation.
///
/// Top level rather than nested, because Dart does not allow a class declaration
/// inside a class, and mirroring the shape of `CloudResult` in cloud.dart keeps
/// the chat layer able to treat both engines the same way.
sealed class LocalModelResult {
  const LocalModelResult();
}

class LocalReply extends LocalModelResult {
  const LocalReply(this.text, this.tokensPerSecond);

  final String text;

  /// Measured, not estimated. Shown in the chat so a slow answer is explained
  /// rather than looking broken.
  final double? tokensPerSecond;
}

class LocalUnavailable extends LocalModelResult {
  const LocalUnavailable(this.detail);

  final String detail;
}

class LocalFailed extends LocalModelResult {
  const LocalFailed(this.reason, {this.detail});

  final String reason;
  final String? detail;
}

/// Client for a locally served, OpenAI-compatible model.
///
/// Koru does not embed an inference runtime. It talks to one over loopback, the
/// same way it could talk to any OpenAI-compatible endpoint, so the engine is
/// swappable: glen, llama.cpp's server, or anything else that speaks the API.
/// Nothing about the model is compiled into the app, so the APK stays small and
/// the model can be replaced without shipping a release.
///
/// The built-in engine stays available and instant. This is opt-in, because a
/// model this size wants a few hundred megabytes of RAM a phone may not have
/// spare.
class LocalModelClient {
  const LocalModelClient({this.timeout = const Duration(seconds: 180)});

  /// Generation on a phone is slow. Measured on the target device, a median
  /// answer runs about fifteen seconds, so the timeout has to be generous or
  /// every answer arrives as a failure.
  final Duration timeout;

  static const defaultEndpoint = 'http://127.0.0.1:8080';

  /// Accepts what people actually paste: a bare host, a trailing slash, or the
  /// full completions path.
  String normaliseEndpoint(String endpoint) {
    var value = endpoint.trim();
    if (value.isEmpty) return defaultEndpoint;
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'http://$value';
    }
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    for (final suffix in const ['/v1/chat/completions', '/chat/completions', '/v1']) {
      if (value.endsWith(suffix)) {
        return value.substring(0, value.length - suffix.length);
      }
    }
    return value;
  }

  Uri _uri(String base, String path) => Uri.parse('$base$path');

  /// Whether something is answering on the other end.
  ///
  /// Tries `/health` first because that is what glen exposes, then `/v1/models`
  /// for servers that only speak the OpenAI surface.
  Future<LocalModelResult> check(String endpoint) async {
    final base = normaliseEndpoint(endpoint);
    for (final path in const ['/health', '/v1/models']) {
      try {
        final resp = await http
            .get(_uri(base, path))
            .timeout(const Duration(seconds: 5));
        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          return LocalReply('something answered at $path', null);
        }
      } catch (_) {
        // Try the next probe.
      }
    }
    return const LocalUnavailable('No local model server answered on that address.');
  }

  /// Streams a generation, reporting each token as it arrives.
  ///
  /// Streams because a silent fifteen second wait reads as a crash. The token
  /// callback carries the deltas; the returned future resolves once with the
  /// outcome, so the caller does not have to manage a subscription for something
  /// it only acts on at the end.
  Future<LocalModelResult> chatStream({
    required String endpoint,
    required String model,
    required String system,
    required String question,
    required void Function(String delta) onToken,
    int maxTokens = 160,
    double temperature = 0.7,
  }) async {
    final base = normaliseEndpoint(endpoint);
    final started = DateTime.now();
    final client = http.Client();
    try {
      final request = http.Request('POST', _uri(base, '/v1/chat/completions'))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({
          'model': model,
          'messages': [
            {'role': 'system', 'content': system},
            {'role': 'user', 'content': question},
          ],
          'max_tokens': maxTokens,
          'temperature': temperature,
          'stream': true,
        });

      final response = await client.send(request).timeout(timeout);
      if (response.statusCode != 200) {
        await response.stream.drain<void>();
        return LocalFailed('The local model returned ${response.statusCode}.');
      }

      final buffer = StringBuffer();
      var emitted = 0;
      await for (final line
          in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload == '[DONE]') break;
        if (payload.isEmpty) continue;
        final delta = parseDelta(payload);
        if (delta.isEmpty) continue;
        buffer.write(delta);
        emitted++;
        onToken(delta);
      }

      final text = buffer.toString().trim();
      if (text.isEmpty) return const LocalFailed('The local model returned nothing.');
      final elapsed = DateTime.now().difference(started).inMilliseconds;
      // Counted locally: not every server reports usage on a streamed reply.
      final tps = elapsed > 0 ? emitted * 1000 / elapsed : null;
      return LocalReply(text, tps);
    } on TimeoutException {
      return const LocalFailed('The local model took too long to answer.');
    } catch (e) {
      return LocalFailed('Could not reach the local model.', detail: '$e');
    } finally {
      client.close();
    }
  }

  /// Pulls `choices[0].delta.content` out of one SSE chunk.
  ///
  /// Public because the wire format is worth testing on its own, and a test in
  /// another library cannot reach a private static.
  ///
  /// Malformed chunks are skipped rather than thrown on, because a dropped byte
  /// mid stream should not lose the whole answer.
  static String parseDelta(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return '';
      final choices = decoded['choices'];
      if (choices is! List || choices.isEmpty) return '';
      final first = choices.first;
      if (first is! Map) return '';
      final delta = first['delta'];
      if (delta is Map && delta['content'] is String) return delta['content'] as String;
      // Some servers send a whole message rather than a delta.
      final message = first['message'];
      if (message is Map && message['content'] is String) {
        return message['content'] as String;
      }
      return '';
    } catch (_) {
      return '';
    }
  }
}

/// Where a configured local model lives and how big it is.
///
/// Size is part of the config on purpose: a phone with little free RAM should be
/// able to say no before a 500 MB download starts, not after.
class LocalModelConfig {
  final String endpoint;
  final String modelId;
  final String? label;
  final int sizeBytes;

  const LocalModelConfig({
    this.endpoint = defaultEndpoint,
    this.modelId = 'local',
    this.label,
    this.sizeBytes = 0,
  });

  bool get isConfigured => endpoint.isNotEmpty;

  /// Rough RAM needed while generating: weights plus an int8 KV cache. Measured
  /// against the models this was designed for, not a guarantee.
  double get estimatedRamMb => (sizeBytes / (1024 * 1024)) * 1.25;

  Map<String, Object?> toMap() => {
        'endpoint': endpoint,
        'model_id': modelId,
        'label': label,
        'size_bytes': sizeBytes,
      };

  factory LocalModelConfig.fromMap(Map<String, Object?> m) => LocalModelConfig(
        endpoint: m['endpoint'] as String? ?? defaultEndpoint,
        modelId: m['model_id'] as String? ?? 'local',
        label: m['label'] as String?,
        sizeBytes: (m['size_bytes'] as num?)?.toInt() ?? 0,
      );

  LocalModelConfig copyWith({
    String? endpoint,
    String? modelId,
    String? label,
    int? sizeBytes,
  }) =>
      LocalModelConfig(
        endpoint: endpoint ?? this.endpoint,
        modelId: modelId ?? this.modelId,
        label: label ?? this.label,
        sizeBytes: sizeBytes ?? this.sizeBytes,
      );
}
