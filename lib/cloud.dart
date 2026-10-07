import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'packet.dart';

/// Result of a cloud call.
///
/// The old implementation returned a bare String and turned every failure into a
/// sentence the user reads as an answer, including a raw exception dump. A caller
/// cannot tell "the model said this" from "the network fell over", so the UI
/// could not react differently. This makes the difference explicit.
sealed class CloudResult {
  const CloudResult();
}

class CloudReply extends CloudResult {
  const CloudReply(this.text);
  final String text;
}

class CloudFailure extends CloudResult {
  const CloudFailure(this.reason, {this.detail});

  /// A short line safe to show a user.
  final String reason;

  /// Diagnostic detail, kept for a debug surface rather than the chat bubble.
  final String? detail;
}

class CloudUnavailable extends CloudResult {
  const CloudUnavailable();
  @override
  String toString() => 'CloudUnavailable';
}

/// One frontier model call. One endpoint, one key, no user-facing routing
/// configuration.
class CloudModel {
  const CloudModel();

  static const _endpoint = 'https://openrouter.ai/api/v1/chat/completions';
  static const _model = 'anthropic/claude-3.5-sonnet';
  static const _timeout = Duration(seconds: 45);

  Future<CloudResult> ask({
    required ContextPacket packet,
    required String question,
    required RoutingDecision routing,
    required String apiKey,
    String model = _model,
  }) async {
    if (apiKey.trim().isEmpty) return const CloudUnavailable();

    final prompt = PromptBuilder.build(packet: packet, question: question, routing: routing);
    final body = jsonEncode({
      'model': model,
      'messages': [
        {'role': 'system', 'content': prompt},
        {'role': 'user', 'content': question},
      ],
      'max_tokens': 600,
    });

    try {
      final resp = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
              'HTTP-Referer': 'https://github.com/AbduljabbarBXR/koru',
              'X-Title': 'Koru',
            },
            body: body,
          )
          .timeout(_timeout);

      if (resp.statusCode == 401 || resp.statusCode == 403) {
        return const CloudFailure(
          'That cloud key was rejected. Check it in Settings.',
        );
      }
      if (resp.statusCode == 429) {
        return const CloudFailure('The model is rate limited right now. Try again shortly.');
      }
      if (resp.statusCode != 200) {
        return CloudFailure(
          'The cloud model returned ${resp.statusCode}.',
          detail: resp.body.length > 400 ? '${resp.body.substring(0, 400)}...' : resp.body,
        );
      }
      final text = extractReply(resp.body);
      if (text == null || text.trim().isEmpty) {
        return const CloudFailure('Could not read the reply from the model.');
      }
      return CloudReply(text.trim());
    } on TimeoutException {
      return const CloudFailure('The model took too long to answer.');
    } catch (e) {
      return CloudFailure('Could not reach the model.', detail: '$e');
    }
  }

  /// Pulls the assistant text out of an OpenRouter response.
  ///
  /// The previous version scanned for the first `"content":` and copied until
  /// the next quote, which breaks on escaped quotes and on any response where
  /// content is not the first field. The project already depended on
  /// `dart:convert` for the request body, so the decoder was there.
  static String? extractReply(String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final first = choices.first;
    if (first is! Map) return null;
    final message = first['message'];
    if (message is! Map) return null;
    final content = message['content'];
    if (content is String) return content;
    // Some gateways return content as a list of parts.
    if (content is List) {
      final buffer = StringBuffer();
      for (final part in content) {
        if (part is Map && part['text'] is String) buffer.write(part['text']);
      }
      return buffer.isEmpty ? null : buffer.toString();
    }
    return null;
  }
}

final cloudModelProvider = Provider<CloudModel>((ref) => const CloudModel());
