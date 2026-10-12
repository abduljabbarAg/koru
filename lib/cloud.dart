import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'cloud_providers.dart';
import 'packet.dart';

/// Result of a cloud call.
///
/// The old implementation returned a bare String and turned every failure into a
/// sentence the user reads as an answer, including a discarded status code. A
/// caller cannot tell "the model said this" from "the network fell over", so the
/// UI could not react differently and a wrong key looked like a dead app.
sealed class CloudResult {
  const CloudResult();
}

class CloudReply extends CloudResult {
  const CloudReply(this.text);
  final String text;
}

/// Something went wrong, and the reason is safe to show.
class CloudFailure extends CloudResult {
  const CloudFailure(this.reason, {this.detail});

  /// A short line a user can act on.
  final String reason;

  /// Diagnostic detail, kept off the chat bubble.
  final String? detail;
}

/// No key for the selected provider.
class CloudUnavailable extends CloudResult {
  const CloudUnavailable();
}

/// One frontier model call.
class CloudModel {
  const CloudModel();

  /// Measured against slow free tiers, and a slow thinking model can legitimately
  /// take this long.
  static const _timeout = Duration(seconds: 60);

  /// Asks the cloud, streaming tokens as they arrive.
  ///
  /// [onToken] is called for each piece. Cloud used to be a single http.post
  /// followed by a parse, so the screen sat empty for the entire generation and
  /// a frontier model looked slower than the 0.5B running on the phone. The
  /// latency was never lower; it was just being paid silently instead of visibly.
  Future<CloudResult> ask({
    required ContextPacket packet,
    required String question,
    required RoutingDecision routing,
    required CloudProvider provider,
    required String model,
    required String apiKey,
    List<({String role, String content})> history = const [],
    void Function(String delta)? onToken,
  }) async {
    if (apiKey.trim().isEmpty && provider.keyHint.isNotEmpty) {
      return const CloudUnavailable();
    }

    final prompt = PromptBuilder.build(packet: packet, question: question, routing: routing);
    final streaming = onToken != null && provider.format == CloudWireFormat.openai;
    final request = CloudAdapter.build(
      provider: provider,
      model: model,
      apiKey: apiKey.trim(),
      system: prompt,
      question: question,
      history: history,
      stream: streaming,
    );

    // Everything except OpenAI's wire format is still one round trip. Streaming
    // is not silently pretended into: if the endpoint cannot stream, it does not.
    if (!streaming) {
      return _askOnce(request, provider, routing);
    }

    // Declared outside the try. A local declared inside a try block is not in
    // scope in its own catch clauses, which is exactly where the partial answer
    // is needed.
    final buffer = StringBuffer();

    try {
      final streamed = http.Request('POST', request.uri)
        ..headers.addAll(request.headers)
        ..body = request.body;
      // Through a Client rather than the top level, because only a Client can
      // hand back a response with an unread body attached.
      final client = http.Client();
      final resp = await client.send(streamed).timeout(_timeout);
      if (resp.statusCode != 200) {
        final body = await resp.stream.bytesToString();
        return CloudFailure(
          CloudAdapter.explain(provider, resp.statusCode, body),
          detail: body.length > 400 ? '${body.substring(0, 400)}...' : body,
        );
      }

      final done = Completer<void>();
      resp.stream.transform(utf8.decoder).transform(const LineSplitter()).listen(
            (line) {
              if (done.isCompleted) return;
              final trimmed = line.trim();
              if (trimmed.isEmpty) return;
              if (trimmed.startsWith(':')) return;
              if (!trimmed.startsWith('data:')) return;
              final data = trimmed.substring(5).trim();
              if (data == '[DONE]') {
                if (!done.isCompleted) done.complete();
                return;
              }
              final delta = CloudAdapter.parseDelta(provider.format, data);
              if (delta == null || delta.isEmpty) return;
              buffer.write(delta);
              onToken(delta);
            },
            onDone: () {
              if (!done.isCompleted) done.complete();
            },
            onError: (_) {
              if (!done.isCompleted) done.complete();
            },
            cancelOnError: true,
          );
      // The socket is finished with once the stream ends, returned here rather
      // than leaking a client per request.
      unawaited(done.future.then((_) => client.close()));
      await done.future.timeout(_timeout, onTimeout: () {});

      final text = buffer.toString().trim();
      if (text.isEmpty) {
        return const CloudFailure(
          'The reply came back in a shape I did not recognise. '
          'Check the model name in Settings.',
        );
      }
      return CloudReply(text);
    } on TimeoutException {
      // Anything already streamed is better than nothing. A partial answer with
      // a note beats an error after the user has watched it type.
      if (buffer.isNotEmpty) return CloudReply(buffer.toString().trim());
      return const CloudFailure('The model took too long to answer.');
    } catch (e) {
      if (buffer.isNotEmpty) return CloudReply(buffer.toString().trim());
      return CloudFailure('Could not reach ${provider.label}.', detail: '$e');
    }
  }

  /// The non streaming path, for endpoints that do not stream.
  Future<CloudResult> _askOnce(
    CloudRequest request,
    CloudProvider provider,
    RoutingDecision routing,
  ) async {
    try {
      final resp = await http
          .post(request.uri, headers: request.headers, body: request.body)
          .timeout(_timeout);

      if (resp.statusCode != 200) {
        return CloudFailure(
          CloudAdapter.explain(provider, resp.statusCode, resp.body),
          detail: resp.body.length > 400 ? '${resp.body.substring(0, 400)}...' : resp.body,
        );
      }

      final text = CloudAdapter.parseText(provider.format, resp.body);
      if (text == null || text.trim().isEmpty) {
        return const CloudFailure(
          'The reply came back in a shape I did not recognise. '
          'Check the model name in Settings.',
        );
      }
      return CloudReply(text.trim());
    } on TimeoutException {
      return const CloudFailure('The model took too long to answer.');
    } catch (e) {
      return CloudFailure('Could not reach ${provider.label}.', detail: '$e');
    }
  }

  /// Cheap reachability probe, used by the Test connection button.
  ///
  /// Sends a one-token request rather than something real, so pressing the button
  /// cannot cost the user money for an answer they did not want.
  Future<CloudResult> probe({
    required CloudProvider provider,
    required String model,
    required String apiKey,
  }) async {
    if (apiKey.trim().isEmpty && provider.keyHint.isNotEmpty) {
      return const CloudUnavailable();
    }
    final request = CloudAdapter.build(
      provider: provider,
      model: model,
      apiKey: apiKey.trim(),
      system: 'Reply with the single word: ok',
      question: 'ping',
      maxTokens: 8,
    );
    try {
      final resp = await http
          .post(request.uri, headers: request.headers, body: request.body)
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode == 200) return const CloudReply('ok');
      return CloudFailure(CloudAdapter.explain(provider, resp.statusCode, resp.body));
    } on TimeoutException {
      return const CloudFailure('No answer within 20 seconds.');
    } catch (e) {
      return CloudFailure('Could not reach ${provider.label}.', detail: '$e');
    }
  }

  /// Kept for the existing tests, which exercise the OpenRouter shape directly.
  static String? extractReply(String body) =>
      CloudAdapter.parseText(CloudWireFormat.openai, body);
}

final cloudModelProvider = Provider<CloudModel>((ref) => const CloudModel());
