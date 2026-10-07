import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cloud.dart';
import 'handoff.dart';
import 'local/local_assistant.dart';
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
  final HandoffPlan? handoff;

  const Msg(
    this.role,
    this.text, {
    this.why,
    this.pending = false,
    this.local = false,
    this.handoff,
  });

  Msg copyWith({String? text, bool? pending, HandoffPlan? handoff}) => Msg(
        role,
        text ?? this.text,
        why: why,
        pending: pending ?? this.pending,
        local: local,
        handoff: handoff ?? this.handoff,
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
    // A question that needs a person gets the card and stops there. It does not
    // also get a model answer to argue with, which is what the old text prefix
    // invited.
    if (routing.needsHuman) {
      return Msg(
        MsgRole.koru,
        'I am stepping aside on this one. Here is who to talk to.',
        why: routing.reason,
        handoff: handoffPlanFor(routing, q),
      );
    }

    if (!routing.useCloud) {
      final local = const LocalAssistant().answer(question: q, facts: await _facts(store));
      return Msg(MsgRole.koru, local.text, why: routing.reason, local: true);
    }

    final key = await ref.read(cloudKeyProvider.future);
    final result = await ref.read(cloudModelProvider).ask(
          packet: await store.packet(),
          question: q,
          routing: routing,
          apiKey: key,
        );

    switch (result) {
      case CloudReply(:final text):
        return Msg(MsgRole.koru, text, why: routing.reason, local: false);
      case CloudUnavailable():
        // Cloud is the right place for this question but there is no key, so say
        // so instead of silently answering with something weaker.
        return const Msg(
          MsgRole.koru,
          'This one deserves a stronger model than the one on your phone, and I '
          'do not have a cloud key yet. Add one in Settings and I will send a '
          'pseudonymous summary with the question.',
          why: 'No cloud key set.',
          local: true,
        );
      case CloudFailure(:final reason):
        return Msg(MsgRole.koru, reason, why: routing.reason, local: false);
    }
  }
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
