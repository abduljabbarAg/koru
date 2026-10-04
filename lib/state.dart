import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cloud.dart';
import 'packet.dart';
import 'store.dart';

/// Riverpod holds the store, the chat thread and the current packet.
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

final cloudKeyProvider = StateProvider<String>((ref) => '');

enum MsgRole { user, koru }

class Msg {
  final MsgRole role;
  final String text;
  final String? why;
  final bool pending;

  const Msg(this.role, this.text, {this.why, this.pending = false});
}

class ChatState {
  final List<Msg> messages;
  final bool busy;

  const ChatState({required this.messages, required this.busy});

  ChatState copyWith({List<Msg>? messages, bool? busy}) =>
      ChatState(messages: messages ?? this.messages, busy: busy ?? this.busy);
}

class ChatNotifier extends Notifier<ChatState> {
  @override
  ChatState build() => const ChatState(
        messages: [
          Msg(MsgRole.koru,
              'I am here. Ask about your work, your training, or anything else. '
              'I will tell you when a person should answer instead of me.'),
        ],
        busy: false,
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
    final packet = await store.packet();
    final routing = RoutingDecision.route(q);
    final key = ref.read(cloudKeyProvider);

    String reply;
    try {
      reply = await ref.read(cloudModelProvider).ask(
            packet: packet,
            question: q,
            routing: routing,
            apiKey: key,
          );
    } catch (e) {
      reply = 'Could not reach the model. $e';
    }

    final head = routing.needsHuman
        ? '[Please bring in a person for this one] '
        : '';

    final out = [...state.messages];
    out[out.length - 1] = Msg(
      MsgRole.koru,
      '$head$reply',
      why: routing.reason,
    );
    state = state.copyWith(busy: false, messages: out);
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