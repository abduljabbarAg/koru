import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'packet.dart';

/// Cloud model call. One endpoint, one key, no user-facing configuration.
class CloudModel {
  const CloudModel();

  static const _endpoint = 'https://openrouter.ai/api/v1/chat/completions';

  Future<String> ask({
    required ContextPacket packet,
    required String question,
    required RoutingDecision routing,
    required String apiKey,
    String model = 'anthropic/claude-3.5-sonnet',
  }) async {
    if (apiKey.isEmpty) {
      return 'No cloud key set. Add one in Settings to use frontier models.';
    }
    final body = {
      'model': model,
      'messages': [
        {'role': 'system', 'content': PromptBuilder.build(packet: packet, question: question, routing: routing)},
        {'role': 'user', 'content': question},
      ],
      'max_tokens': 600,
    };
    final resp = await http.post(
      Uri.parse(_endpoint),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        'HTTP-Referer': 'https://github.com/AbduljabbarBXR/koru',
        'X-Title': 'Koru',
      },
      body: _encode(body),
    ).timeout(const Duration(seconds: 60));

    if (resp.statusCode != 200) {
      return 'Cloud model returned ${resp.statusCode}. Check the key, or retry.';
    }
    return _extract(resp.body);
  }

  String _encode(Map<String, dynamic> m) {
    final sb = StringBuffer();
    _write(sb, m);
    return sb.toString();
  }

  void _write(StringBuffer sb, Object? v) {
    if (v is Map) {
      sb.write('{');
      var first = true;
      v.forEach((k, val) {
        if (!first) sb.write(',');
        first = false;
        sb.write(jsonQuote(k.toString()));
        sb.write(':');
        _write(sb, val);
      });
      sb.write('}');
    } else if (v is List) {
      sb.write('[');
      for (var i = 0; i < v.length; i++) {
        if (i > 0) sb.write(',');
        _write(sb, v[i]);
      }
      sb.write(']');
    } else if (v is num || v is bool || v == null) {
      sb.write(v?.toString() ?? 'null');
    } else {
      sb.write(jsonQuote(v.toString()));
    }
  }

  String jsonQuote(String s) {
    final out = StringBuffer('"');
    for (final c in s.codeUnits) {
      switch (c) {
        case 34:
          out.write(r'\"');
        case 92:
          out.write(r'\\');
        case 10:
          out.write(r'\n');
        case 13:
          out.write(r'\r');
        case 9:
          out.write(r'\t');
        default:
          if (c < 0x20) {
            out.write(r'\u');
            out.write(c.toRadixString(16).padLeft(4, '0'));
          } else {
            out.writeCharCode(c);
          }
      }
    }
    out.write('"');
    return out.toString();
  }

  String _extract(String body) {
    // Minimal extraction: the only field that matters is the message text.
    final marker = '"content":';
    final start = body.indexOf(marker);
    if (start < 0) return 'Could not read the reply.';
    var i = start + marker.length;
    while (i < body.length && body[i] != '"') {
      i++;
    }
    if (i >= body.length) return 'Could not read the reply.';
    final sb = StringBuffer();
    i++;
    while (i < body.length && body[i] != '"') {
      if (body[i] == r'\' && i + 1 < body.length) {
        sb.write(body[i + 1]);
        i += 2;
      } else {
        sb.write(body[i]);
        i++;
      }
    }
    return sb.toString();
  }
}

final cloudModelProvider = Provider<CloudModel>((ref) => const CloudModel());