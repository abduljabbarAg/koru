import 'dart:async';

import 'package:koru/cloud.dart';
import 'package:koru/cloud_providers.dart';
import 'package:koru/packet.dart';
import 'package:koru/secrets.dart';

/// A keystore that always answers with a key.
///
/// The chat now has one honest door: with nothing connected it refuses to answer
/// and offers to connect something. A test about the chat — streaming, stop,
/// history, editing — would otherwise spend its whole budget on that state and
/// never reach the thing it was written for. Overriding the key store rather than
/// the provider is deliberate: the link reads the keystore directly, so a key
/// faked any other way would leave the app bar claiming nothing is connected
/// while the chat answered anyway.
class TestKeyStore implements KeyStore {
  const TestKeyStore({this.key = 'test-key'});

  /// What every provider answers with. Empty to test the nothing-connected
  /// state instead.
  final String key;

  @override
  Future<String> readKey(String providerId) async => key;

  @override
  Future<bool> writeKey(String providerId, String value) async => true;

  @override
  Future<bool> clearKey(String providerId) async => true;
}

/// A keystore that refuses to answer.
///
/// Stands in for a locked screen or a vendor keystore that has gone, which is
/// the one dependency in the connected-state read that can fail on a phone that
/// is otherwise fine.
class BrokenKeyStore implements KeyStore {
  const BrokenKeyStore();

  @override
  Future<String> readKey(String providerId) async =>
      throw StateError('the keystore is locked');

  @override
  Future<bool> writeKey(String providerId, String value) async => false;

  @override
  Future<bool> clearKey(String providerId) async => false;
}

/// A model that answers, and records what it was asked.
///
/// Stands in for the one model there is. Split out of `flow_test.dart` because
/// three suites need one and three private copies is how they drift: this is the
/// seam every chat test now has, and it behaves the same in all of them.
class TestCloudModel extends CloudModel {
  TestCloudModel({
    this.reply = 'ok',
    this.gap = Duration.zero,
    this.hangFirstCall = false,
    this.replies,
  });

  /// What to answer. Streamed a word at a time so the token path is genuinely
  /// exercised rather than one blob arriving at once.
  final String reply;

  /// How long to wait between tokens. Zero means a tight synchronous loop, which
  /// no frame can observe; anything real hands control back to the event loop
  /// between chunks, and that is the only place a streaming bug is visible.
  final Duration gap;

  /// Every system prompt sent, in order. Two identical entries is the property
  /// that keeps a follow-up from re-paying for the whole context.
  final prompts = <String>[];

  /// Every conversation sent, in order.
  final turns = <List<({String role, String content})>>[];

  final questions = <String>[];

  /// When true, the first call never finishes. The only state in which the Stop
  /// button exists at all.
  final bool hangFirstCall;

  /// Different answers per call, for tests that need two questions answered
  /// differently.
  final List<String>? replies;

  /// How many times this has been asked.
  int calls = 0;

  @override
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
    prompts.add(PromptBuilder.build(
      packet: packet,
      question: question,
      routing: routing,
    ));
    turns.add(history);
    questions.add(question);
    calls++;

    final answer = replies != null
        ? replies![(calls - 1) % replies!.length]
        : reply;

    if (hangFirstCall && calls == 1) {
      onToken?.call('thinking');
      // Never resolves on its own within a test run.
      await Completer<void>().future;
    }

    for (final word in answer.split(' ')) {
      onToken?.call('$word ');
      if (gap > Duration.zero) {
        await Future<void>.delayed(gap);
      }
    }
    return CloudReply(answer);
  }
}

/// A model that could not be reached.
///
/// [reason] is what the provider is said to have said, and it is the only thing
/// on screen when this is in use — which is the point. An unreachable provider
/// and a missing key are different states and must not read alike.
class FailingCloudModel extends CloudModel {
  const FailingCloudModel({this.reason = 'Could not reach OpenRouter.'});

  final String reason;

  @override
  Future<CloudResult> ask({
    required ContextPacket packet,
    required String question,
    required RoutingDecision routing,
    required CloudProvider provider,
    required String model,
    required String apiKey,
    List<({String role, String content})> history = const [],
    void Function(String delta)? onToken,
  }) async =>
      CloudFailure(reason);
}