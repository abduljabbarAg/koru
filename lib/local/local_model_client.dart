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
  const LocalReply(this.text, this.tokensPerSecond, {this.prefillMs});

  final String text;

  /// Measured, not estimated. Shown in the chat so a slow answer is explained
  /// rather than looking broken.
  final double? tokensPerSecond;

  /// How long the engine spent reading the prompt before the first token.
  ///
  /// Silent, and on this device it is the longest part of a cold first ask, so
  /// it is worth separating from decode rather than blending the two.
  final int? prefillMs;
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
  /// Tries `/health` first — both glen and llama-server expose it — then
  /// `/v1/models` for servers that only speak the OpenAI surface.
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
  ///
  /// [onProgress] covers the window before the first token. Prefill reads the
  /// caller's records and takes seconds on a phone. glen sent it as SSE
  /// comments so the stream stayed OpenAI compatible; llama-server does not, so
  /// on those builds the progress callback simply never fires and the user
  /// watches a blank bubble for the whole prefill. That is a graceful
  /// degradation, not a bug, but it is also the difference between "working"
  /// and "working on glen" and should not be mistaken for one.
  Future<LocalModelResult> chatStream({
    required String endpoint,
    required String model,
    required String system,
    required String question,
    required void Function(String delta) onToken,
    void Function(int done, int total)? onProgress,
    List<({String role, String content})> history = const [],
    int maxTokens = 160,
    double temperature = 0.7,
  }) async {
    final base = normaliseEndpoint(endpoint);
    final started = DateTime.now();
    // When the first token actually arrived, which is what separates the time
    // spent reading the prompt from the time spent writing the answer.
    DateTime? firstTokenAt;
    final client = http.Client();
    try {
      final request = http.Request('POST', _uri(base, '/v1/chat/completions'))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({
          'model': model,
          'messages': [
            {'role': 'system', 'content': system},
            // Earlier turns go in as real messages rather than being flattened
            // into the prompt, because the engine's chat template already knows
            // how to lay them out and that layout is what the token prefix
            // reuse matches on. Flattening them into prose would break the
            // cache and make every follow-up a full prefill again.
            for (final turn in history) ...[
              {'role': turn.role, 'content': turn.content},
            ],
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
        final progress = parseProgress(line);
        if (progress != null) {
          onProgress?.call(progress.$1, progress.$2);
          continue;
        }
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload == '[DONE]') break;
        if (payload.isEmpty) continue;
        final delta = parseDelta(payload);
        if (delta.isEmpty) continue;
        buffer.write(delta);
        emitted++;
        firstTokenAt ??= DateTime.now();
        onToken(delta);
      }

      final text = buffer.toString().trim();
      if (text.isEmpty) return const LocalFailed('The local model returned nothing.');
      final total = DateTime.now().difference(started).inMilliseconds;
      // Decode rate only, and this distinction was the difference between
      // "the model got slower" and "the model is fine".
      //
      // The old number was emitted tokens over the whole request, prefill
      // included. Prefill on this phone runs about 15 tokens a second against a
      // decode of 4, and the first message of a conversation prefills the whole
      // prompt while every message after it reuses the cached prefix. So the
      // same 4 tok/s decode was being reported as 4 tok/s on a warm follow-up
      // and 0.3 tok/s on a cold first ask, and reading those two numbers as a
      // 13x slowdown in the engine is exactly what it looked like.
      //
      // Both are still worth knowing, so decode is what is shown and the
      // prefill wait is reported separately where it can be explained.
      final decode = DateTime.now().difference(firstTokenAt ?? started).inMilliseconds;
      final tps = decode > 0 ? emitted * 1000 / decode : null;
      return LocalReply(text, tps, prefillMs: total - decode);
    } on TimeoutException {
      return const LocalFailed('The local model took too long to answer.');
    } catch (e) {
      return LocalFailed('Could not reach the local model.', detail: '$e');
    } finally {
      client.close();
    }
  }

  /// Reads an SSE comment of the form `: prefill 128/300`.
  ///
  /// Returns null for anything else, including every ordinary data line, so the
  /// caller can run this first and fall through without special-casing. A
  /// comment is ignored by conforming readers by definition, which is why the
  /// engine can report progress without a stock OpenAI client choking on it.
  static (int, int)? parseProgress(String line) {
    if (!line.startsWith(':')) return null;
    // The space after the colon is optional. An SSE comment is the whole line
    // after ':', so both ': prefill 1/2' and ':prefill 1/2' are the same thing
    // and the engine is free to write whichever.
    final rest = line.substring(1).trim();
    if (!rest.startsWith('prefill')) return null;
    final parts = rest.substring('prefill'.length).trim().split('/');
    if (parts.length != 2) return null;
    final done = int.tryParse(parts[0].trim());
    final total = int.tryParse(parts[1].trim());
    if (done == null || total == null || total <= 0) return null;
    return (done, total);
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
    this.endpoint = LocalModelClient.defaultEndpoint,
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
        endpoint: m['endpoint'] as String? ?? LocalModelClient.defaultEndpoint,
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
