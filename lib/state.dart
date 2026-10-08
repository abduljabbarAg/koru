import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cloud.dart';
import 'engine.dart';
import 'handoff.dart';
import 'local/local_assistant.dart';
import 'local/local_model_client.dart';
import 'models.dart';
import 'packet.dart';
import 'secrets.dart';
import 'store.dart';

/// Riverpod holds the store, the chat thread and the current packet.
///
/// Everything that changes is a Notifier, so no widget holds mutable state.

final storeProvider = FutureProvider<ProfileStore>((ref) async {
  final s = await ProfileStore.open();
  ref.onDispose(s.close);
  return s;
});

final onboardedProvider = StateProvider<bool>((ref) => false);

final packetProvider = FutureProvider<ContextPacket>((ref) async {
  final store = await ref.watch(storeProvider.future);
  return store.packet();
});

/// Where a reply came from. The chat screen shows this so the user can always
/// tell an on-device answer from a cloud one.
enum AnswerSource { local, cloud, human }

final cloudKeyProvider = FutureProvider<String>((ref) async {
  final secrets = ref.watch(secretsProvider);
  return secrets.readKey();
});

enum MsgRole { user, koru }

class Msg {
  final MsgRole role;
  final String text;
  final String? why;
  final bool pending;
  final bool local;

  /// Which engine produced this message. Null on the opening greeting and on
  /// anything the user typed.
  final KoruEngine? engine;
  final HandoffPlan? handoff;

  /// Measured generation speed, when the engine reported it. Shown so a slow
  /// answer is explained rather than looking broken.
  final double? tokensPerSecond;

  const Msg(
    this.role,
    this.text, {
    this.why,
    this.pending = false,
    this.local = false,
    this.engine,
    this.handoff,
    this.tokensPerSecond,
  });

  Msg copyWith({String? text, bool? pending}) => Msg(
        role,
        text ?? this.text,
        why: why,
        pending: pending ?? this.pending,
        local: local,
        engine: engine,
        handoff: handoff,
        tokensPerSecond: tokensPerSecond,
      );

  AnswerSource get source {
    if (handoff != null) return AnswerSource.human;
    return local ? AnswerSource.local : AnswerSource.cloud;
  }
}

class ChatState {
  final List<Msg> messages;
  final bool busy;
  final bool loaded;

  const ChatState({
    required this.messages,
    required this.busy,
    this.loaded = false,
  });

  ChatState copyWith({List<Msg>? messages, bool? busy, bool? loaded}) => ChatState(
        messages: messages ?? this.messages,
        busy: busy ?? this.busy,
        loaded: loaded ?? this.loaded,
      );
}

const _greeting = 'I am here, and I run on this phone. Ask about your work, '
    'your training, or anything else. I will tell you when a person should '
    'answer instead of me.';

class ChatNotifier extends Notifier<ChatState> {
  @override
  ChatState build() => const ChatState(
        messages: [Msg(MsgRole.koru, _greeting, local: true)],
        busy: false,
      );

  /// Loads the persisted thread. Chat history used to live only in this
  /// notifier, so closing the app lost the conversation.
  Future<void> load() async {
    if (state.loaded) return;
    final store = await ref.read(storeProvider.future);
    final records = await store.chat();
    if (records.isEmpty) {
      state = state.copyWith(loaded: true);
      return;
    }
    final messages = <Msg>[
      const Msg(MsgRole.koru, _greeting, local: true),
      ...records.map((r) => r.role == 'user'
          ? Msg(MsgRole.user, r.text)
          : Msg(MsgRole.koru, r.text, why: r.why, local: !r.needsHuman)),
    ];
    state = state.copyWith(messages: messages, loaded: true);
  }

  Future<void> clear() async {
    final store = await ref.read(storeProvider.future);
    await store.clearChat();
    state = const ChatState(
      messages: [Msg(MsgRole.koru, _greeting, local: true)],
      busy: false,
      loaded: true,
    );
  }

  /// Everything the local assistant is allowed to know, gathered once.
  Future<LocalFacts> _facts(ProfileStore store) async => LocalFacts(
        nickname: (await store.get('nickname')) ?? '',
        lifeStage: (await store.get('stage')) ?? '',
        goals: (await store.get('goals')) ?? '',
        height: await store.number('height'),
        bmi: await store.number('bmi'),
        fitness: await store.fitness(),
        clients: await store.clients(),
      );

  Future<void> ask(String question) async {
    final q = question.trim();
    if (q.isEmpty || state.busy) return;

    state = state.copyWith(
      busy: true,
      messages: [
        ...state.messages,
        Msg(MsgRole.user, q),
        const Msg(MsgRole.koru, '', pending: true),
      ],
    );

    final store = await ref.read(storeProvider.future);
    await store.addChat(ChatRecord(
      role: 'user',
      text: q,
      created: DateTime.now().toIso8601String(),
    ));

    final routing = RoutingDecision.route(q);
    final reply = await _respond(q, routing, store);

    final messages = [...state.messages];
    messages[messages.length - 1] = reply;
    state = state.copyWith(busy: false, messages: messages);

    await store.addChat(ChatRecord(
      role: 'koru',
      text: reply.text,
      why: reply.why,
      needsHuman: reply.handoff != null,
      created: DateTime.now().toIso8601String(),
    ));
  }

  Future<Msg> _respond(String q, RoutingDecision routing, ProfileStore store) async {
    // Safety first, above every engine. A question that needs a person gets the
    // card and stops there. It does not also get a model answer to argue with,
    // which is what the old text prefix invited, and no engine may override this.
    if (routing.needsHuman) {
      return Msg(
        MsgRole.koru,
        'I am stepping aside on this one. Here is who to talk to.',
        why: routing.reason,
        handoff: handoffPlanFor(routing, q),
      );
    }

    switch (KoruEngine.parse(await store.get('engine'))) {
      case KoruEngine.builtIn:
        return _askBuiltIn(q, routing, store);
      case KoruEngine.onDevice:
        return _askOnDevice(q, routing, store);
      case KoruEngine.cloud:
        return _askCloud(q, routing, store);
    }
  }

  /// Deterministic answers from the user's own records. No model, no network,
  /// no RAM. The default, because it works the instant the app opens.
  Future<Msg> _askBuiltIn(String q, RoutingDecision routing, ProfileStore store) async {
    final answer = const LocalAssistant().answer(question: q, facts: await _facts(store));
    return Msg(
      MsgRole.koru,
      answer.text,
      why: routing.reason,
      local: true,
      engine: KoruEngine.builtIn,
    );
  }

  /// Real generation from a model served on this device over loopback.
  ///
  /// Streams, because a median of about fifteen seconds of silence reads as a
  /// crash. Measured on the target phone: 2.57 tok/s decode with prefill
  /// dominating, so tokens are shown as they arrive.
  ///
  /// Falls back to the built-in engine rather than failing outright, because
  /// someone who picked the local model on a phone that has since filled up
  /// should get an answer, not an error. The fallback says so, so nothing is
  /// quietly downgraded behind their back.
  Future<Msg> _askOnDevice(String q, RoutingDecision routing, ProfileStore store) async {
    final config = await ref.read(localModelProvider.future);
    final client = ref.read(localModelClientProvider);
    final routing2 = routing;

    final system = LocalModelPrompt.build(
      packet: await store.packet(),
      question: q,
      facts: await _modelFacts(store),
    );

    final buffer = StringBuffer();
    Object? failure;
    Object? unavailable;

    try {
      final stream = client.chatStream(
        endpoint: config.endpoint,
        model: config.modelId,
        system: system,
        question: q,
        onToken: (delta) {
          buffer.write(delta);
          _updatePending(buffer.toString());
        },
      );
      final result = await stream.last;
      switch (result) {
        case LocalModelClient.Reply(:final tokensPerSecond):
          final text = buffer.toString().trim();
          if (text.isEmpty) {
            failure = 'The local model returned nothing.';
            break;
          }
          // Defence in depth. The gate already stopped the question reaching
          // here, but a model this size will still drift into dosing or legal
          // advice on innocuous phrasing, and that answer does not get shown.
          if (ModelOutputGuard.needsHuman(text)) {
            return Msg(
              MsgRole.koru,
              'I am stepping aside on this one. Here is who to talk to.',
              why: 'The model on this phone drifted into an area that needs a person.',
              handoff: handoffPlanFor(routing2, q),
            );
          }
          return Msg(
            MsgRole.koru,
            text,
            why: 'Answered by the model on this phone.',
            local: true,
            engine: KoruEngine.onDevice,
            tokensPerSecond: tokensPerSecond,
          );
        case LocalModelClient.Unavailable(:final detail):
          unavailable = detail;
        case LocalModelClient.Failed(:final reason):
          failure = reason;
      }
    } catch (e) {
      failure = '$e';
    }

    final fallback = await _askBuiltIn(q, routing, store);
    final note = unavailable != null
        ? 'I would have used the model on this phone but could not reach it: $unavailable'
        : 'The local model did not answer: $failure';
    return fallback.copyWith(text: '${fallback.text}\n\n($note)');
  }

  /// Replaces the pending bubble so streamed tokens appear as they arrive.
  void _updatePending(String text) {
    final messages = [...state.messages];
    if (messages.isEmpty) return;
    final last = messages.last;
    if (last.pending) {
      messages[messages.length - 1] = last.copyWith(text: text, pending: text.isEmpty);
      state = state.copyWith(messages: messages);
    }
  }

  Future<Msg> _askCloud(String q, RoutingDecision routing, ProfileStore store) async {
    final key = await ref.read(cloudKeyProvider.future);
    final result = await ref.read(cloudModelProvider).ask(
          packet: await store.packet(),
          question: q,
          routing: routing,
          apiKey: key,
        );

    switch (result) {
      case CloudReply(:final text):
        return Msg(
          MsgRole.koru,
          text,
          why: routing.reason,
          local: false,
          engine: KoruEngine.cloud,
        );
      case CloudUnavailable():
        // No key. Answer from the records and say why, rather than passing off a
        // weaker answer as the stronger one the user asked for.
        final fallback = await _askBuiltIn(q, routing, store);
        return fallback.copyWith(
          text: '${fallback.text}\n\n(I answered that from your own records '
              'because no cloud key is set. Add one in Settings.)',
        );
      case CloudFailure(:final reason):
        return Msg(
          MsgRole.koru,
          reason,
          why: routing.reason,
          local: false,
          engine: KoruEngine.cloud,
        );
    }
  }

  /// Facts for the on-device model, in the shape its prompt wants.
  Future<LocalEngineFacts> _modelFacts(ProfileStore store) async => LocalEngineFacts(
        nickname: (await store.get('nickname')) ?? '',
        goals: (await store.get('goals')) ?? '',
        focus: (await store.get('help_focus')) ?? '',
        height: await store.number('height'),
        bmi: await store.number('bmi'),
        fitness: await store.fitness(limit: 5),
        clients: await store.clients(),
      );
}

final chatProvider = NotifierProvider<ChatNotifier, ChatState>(ChatNotifier.new);

final clientsProvider = FutureProvider<List<Client>>((ref) async {
  final store = await ref.watch(storeProvider.future);
  return store.clients();
});

final fitnessProvider = FutureProvider<List<FitnessEntry>>((ref) async {
  final store = await ref.watch(storeProvider.future);
  return store.fitness();
});

final topicsProvider = FutureProvider<List<KnowledgeTopic>>((ref) async {
  final store = await ref.watch(storeProvider.future);
  return store.topics();
});

final draftsProvider = FutureProvider<List<Draft>>((ref) async {
  final store = await ref.watch(storeProvider.future);
  return store.drafts(status: DraftStatus.pending);
});

/// Which engine answers. Persisted so the choice survives a restart.
final engineProvider = FutureProvider<KoruEngine>((ref) async {
  final store = await ref.watch(storeProvider.future);
  return KoruEngine.parse(await store.get('engine'));
});

/// Config for the on-device model, if one has been set up.
final localModelProvider = FutureProvider<LocalModelConfig>((ref) async {
  final store = await ref.watch(storeProvider.future);
  return localModelConfigFrom(await store.get('local_model'));
});

/// Parses stored JSON defensively. A corrupt value falls back to the default
/// rather than taking Settings down with it.
LocalModelConfig localModelConfigFrom(String? raw) {
  if (raw == null || raw.isEmpty) return const LocalModelConfig();
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const LocalModelConfig();
    return LocalModelConfig.fromMap(decoded.cast<String, Object?>());
  } catch (_) {
    return const LocalModelConfig();
  }
}

final localModelClientProvider =
    Provider<LocalModelClient>((ref) => const LocalModelClient());

/// Height, pulled out because three different screens need it to compute BMI.
final heightProvider = FutureProvider<double?>((ref) async {
  final store = await ref.watch(storeProvider.future);
  return store.number('height');
});

/// Saves a cloud key and invalidates everything that depends on it.
Future<void> saveCloudKey(WidgetRef ref, String value) async {
  await ref.read(secretsProvider).writeKey(value.trim());
  ref.invalidate(cloudKeyProvider);
}
