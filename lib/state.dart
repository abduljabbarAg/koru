import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'attention.dart';
import 'attention_bridge.dart';
import 'calendar_bridge.dart';
import 'cloud.dart';
import 'cloud_providers.dart';
import 'currency.dart';
import 'deep_link.dart';
import 'engine.dart';
import 'guide.dart';
import 'handoff.dart';
import 'local/bulk_import.dart';
import 'local/bundled_engine.dart';
import 'local/local_assistant.dart';
import 'local/local_model_client.dart';
import 'local/write_intent.dart';
import 'models.dart';
import 'packet.dart';
import 'proposed_write.dart';
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

final cloudKeyProvider = FutureProvider.family<String, String>((ref, providerId) async {
  final secrets = ref.watch(secretsProvider);
  return secrets.readKey(providerId);
});

enum MsgRole { user, koru }

class Msg {
  final MsgRole role;
  final String text;
  final String? why;
  final bool pending;
  final bool local;

  /// When this message was written, for the timestamp under the bubble. Null
  /// on the opening greeting, which has no moment.
  final DateTime? time;

  /// Which engine produced this message. Null on the opening greeting and on
  /// anything the user typed.
  final KoruEngine? engine;
  final HandoffPlan? handoff;

  /// Measured generation speed, when the engine reported it. Shown so a slow
  /// answer is explained rather than looking broken.
  final double? tokensPerSecond;

  /// A write waiting for the user to approve it. Set instead of an answer when
  /// the message was understood as an instruction to record something.
  final ProposedWrite? proposed;

  const Msg(
    this.role,
    this.text, {
    this.why,
    this.pending = false,
    this.local = false,
    this.time,
    this.engine,
    this.handoff,
    this.tokensPerSecond,
    this.proposed,
  });

  Msg copyWith({String? text, bool? pending, ProposedWrite? proposed}) => Msg(
        role,
        text ?? this.text,
        why: why,
        pending: pending ?? this.pending,
        local: local,
        time: time,
        engine: engine,
        handoff: handoff,
        tokensPerSecond: tokensPerSecond,
        proposed: proposed ?? this.proposed,
      );

  /// The same message, stamped with when it arrived.
  Msg stampedAt(DateTime t) => Msg(
        role,
        text,
        why: why,
        pending: pending,
        local: local,
        time: t,
        engine: engine,
        handoff: handoff,
        tokensPerSecond: tokensPerSecond,
        proposed: proposed,
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

  /// Progress of the local engine warming up, 0 to 100, while null when it is
  /// not happening. Shown on the splash and the chat rather than hidden in
  /// Settings, because this is now something the app does on its own.
  final int? engineProgress;

  /// Set when the engine could not be brought up, so the failure is visible
  /// where the question will be asked rather than only in Settings.
  final String? engineProblem;

  /// What the model is doing right now, so the waiting indicator can say so.
  ///
  /// A prefill on this phone takes seconds and a decode is four tokens a second.
  /// Those feel identical as three bouncing dots and completely different once
  /// named, which is the difference between "it is working" and "it is working on
  /// the right thing".
  final String? activity;

  const ChatState({
    required this.messages,
    required this.busy,
    this.loaded = false,
    this.engineProgress,
    this.engineProblem,
    this.activity,
  });

  ChatState copyWith({
    List<Msg>? messages,
    bool? busy,
    bool? loaded,
    int? engineProgress,
    String? engineProblem,
    String? activity,
  }) =>
      ChatState(
        messages: messages ?? this.messages,
        busy: busy ?? this.busy,
        loaded: loaded ?? this.loaded,
        engineProgress: engineProgress ?? this.engineProgress,
        engineProblem: engineProblem ?? this.engineProblem,
        activity: activity ?? this.activity,
      );
}

const _greeting = 'I am here, and I run on this phone. Ask about your work, '
    'your money and your deadlines. I will tell you when a person should '
    'answer instead of me.';

class ChatNotifier extends Notifier<ChatState> {
  @override
  ChatState build() {
    // Notifier has no dispose to override in this version of Riverpod, so the
    // liveness flag is armed from here instead.
    ref.onDispose(() => _gone = true);
    return const ChatState(
      messages: [Msg(MsgRole.koru, _greeting, local: true)],
      busy: false,
    );
  }

  /// Loads the persisted thread. Chat history used to live only in this
  /// notifier, so closing the app lost the conversation.
  Future<void> load() async {
    if (state.loaded) return;
    final store = await ref.read(storeProvider.future);
    _warmEngine(store);
    final records = await store.chat();
    if (records.isEmpty) {
      state = state.copyWith(loaded: true);
      return;
    }
    final messages = <Msg>[
      const Msg(MsgRole.koru, _greeting, local: true),
      ...records.map((r) {
        final at = DateTime.tryParse(r.created);
        return r.role == 'user'
            ? Msg(MsgRole.user, r.text, time: at)
            : Msg(MsgRole.koru, r.text, why: r.why, local: !r.needsHuman,
                time: at);
      }),
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
        clients: await store.clients(),
        received: await store.receivedTotals(),
        deadlines: await store.deadlines(),
        projects: await store.projects(),
        projectNotes: await _latestNotePerProject(store),
        events: await store.events(),
      );

  Future<void> ask(String question) async {
    final q = question.trim();
    if (q.isEmpty || state.busy) return;

    // A request is stale once a newer one starts or this one is stopped.
    //
    // This used to be a boolean that stop() set and that ask() cleared *after*
    // an early return that tested it, so it never cleared. One press of Stop and
    // every message afterwards was dropped before it reached the screen, with
    // no error anywhere: the chat simply stopped working and stayed that way
    // until the app was restarted. A counter cannot get into that state,
    // because starting a request is what makes the previous one stale.
    final mine = ++_generation;
    bool stale() => mine != _generation;

    // Names what is being attempted rather than how the bytes are moving.
    //
    // It used to open with "Waking up" on every request and only move on when
    // the engine reported a token or a prefill tick, so anything that did not go
    // through the local model sat on "Waking up" for the whole answer. A
    // question the app can answer without the model, and a list being read into
    // a plan, are different jobs and should not claim the same one.
    state = state.copyWith(activity: _activityFor(q));
    // Captured before the new turn is added, so the model sees the conversation
    // that happened before this question and not the question twice.
    final history = _recentTurns();

    state = state.copyWith(
      busy: true,
      messages: [
        ...state.messages,
        Msg(MsgRole.user, q, time: DateTime.now()),
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
    final reply = await _respond(q, routing, store, history, stale);

    // A stopped generation must not overwrite the bubble, because the stop
    // button has already replaced it with something truthful.
    if (stale()) return;

    final messages = [...state.messages];
    messages[messages.length - 1] = reply.stampedAt(DateTime.now());
    state = state.copyWith(busy: false, messages: messages);

    await store.addChat(ChatRecord(
      role: 'koru',
      text: reply.text,
      why: reply.why,
      needsHuman: reply.handoff != null,
      created: DateTime.now().toIso8601String(),
    ));
  }

  /// Brings the chosen engine up without being asked.
  ///
  /// Choosing "on-device model" used to mean choosing it AND then going to
  /// Settings and pressing start, every launch, with no indication anywhere
  /// else in the app that anything needed doing. The model is bundled, so
  /// nothing about starting it is a user decision, and the answer is already
  /// stored: if they picked the local engine they want the local engine.
  ///
  /// Deliberately not awaited by load(). A cold start copies about half a
  /// gigabyte out of the APK and takes tens of seconds, and blocking the chat
  /// on it would make the app look dead on open. It reports progress instead.
  void _warmEngine(ProfileStore store) {
    unawaited(() async {
      if (KoruEngine.parse(await store.get('engine')) != KoruEngine.onDevice) return;
      final engine = ref.read(bundledEngineProvider);
      final client = ref.read(localModelClientProvider);

      // Already answering from a previous run of the app, so leave it alone.
      final healthy = await client
          .check('http://127.0.0.1:${BundledEngine.defaultPort}')
          .then((r) => r is LocalReply)
          .catchError((_) => false);
      if (healthy) return;

      state = state.copyWith(engineProgress: 0);
      // The model the user chose, if any. Null means the bundled default, which
      // is the right answer for most people and the fast one.
      final chosen = await store.get('model_path');
      final result = await engine.start(
        modelPath: (chosen == null || chosen.isEmpty) ? null : chosen,
        onProgress: (percent) {
          if (_gone) return;
          state = state.copyWith(engineProgress: percent);
        },
        isHealthy: () async {
          final check =
              await client.check('http://127.0.0.1:${BundledEngine.defaultPort}');
          return check is LocalReply;
        },
      );

      if (_gone) return;
      if (result.started && result.endpoint != null) {
        // Warm the real prompt, once, in the background.
        //
        // glen's own warm() encodes the word "warm" into a scratch cache it then
        // throws away, so it shares no prefix with an actual question and helps
        // nothing. The engine reuses the longest common token prefix between
        // turns, which means one throwaway request carrying the real system
        // prompt fills that cache, and the user's first question then starts
        // from a prefix hit instead of prefilling it cold.
        //
        // Measured on this phone: a 222 token prompt cold is about 14.5 seconds,
        // and the same prompt warm is 1.2. That gap is the whole cold start.
        unawaited(_warmPrefix(ref, client, result.endpoint!, store));

        await store.put(
          'local_model',
          jsonEncode(LocalModelConfig(
            endpoint: result.endpoint!,
            modelId: 'qwen2.5-0.5b-instruct',
            label: 'Bundled',
            sizeBytes: 491400032,
          ).toMap()),
        );
        ref.invalidate(localModelProvider);
        state = state.copyWith(engineProgress: null, engineProblem: null);
      } else {
        state = state.copyWith(
          engineProgress: null,
          engineProblem: result.reason,
        );
      }
    }());
  }

  /// Prefills the real system prompt so the first question is not a cold start.
  ///
  /// Fire and forget. It costs one forward pass of the prompt, which is the same
  /// work the first question would have done anyway, and it happens while the
  /// user is still reading the chat rather than after they have typed.
  Future<void> _warmPrefix(
    Ref ref,
    LocalModelClient client,
    String endpoint,
    ProfileStore store,
  ) async {
    try {
      final currency = (await ref.read(currencyProvider.future)).code;
      final system = LocalModelPrompt.build(
        packet: await store.packet(),
        facts: await _modelFacts(store),
        currency: currency,
      );
      await client.chatStream(
        endpoint: endpoint,
        model: 'qwen2.5-0.5b-instruct',
        system: system,
        // Any question at all. Only the system prompt is what has to match.
        question: 'ready?',
        maxTokens: 1,
        onToken: (_) {},
      );
    } catch (_) {
      // Nothing here is worth surfacing. If the warm-up fails the first question
      // simply pays the cold cost it was always going to pay.
    }
  }

  /// Characters of earlier conversation allowed into one prompt.
  ///
  /// The bundled engine runs with a 1024 token KV cache and the system prompt
  /// plus the caller's records already use a few hundred of it, so roughly 1200
  /// characters of history leaves genuine headroom for the answer itself. This
  /// has to stay comfortably under the window, not at it: the window also has to
  /// hold the reply, and an overrun takes the engine down with it.
  static const _historyBudgetChars = 1200;

  /// Reads a pasted list, or null when the message is not one.
  ///
  /// Returns null rather than a message for anything it is not confident about,
  /// because the caller has an ordinary path for those and falling through to it
  /// is always better than forcing a list onto a sentence.
  Future<Msg?> _importPlan(String q, ProfileStore store) async {
    // Two lines or more. One line is a sentence, not a list.
    final lines = q.split('\n').where((l) => l.trim().isNotEmpty).length;
    if (lines < 2) return null;

    final parsed = const BulkClientParser().parse(q);
    // One readable row out of several lines is a sentence that happened to be
    // split, not a list. Treating it as one would put a list card in front of
    // somebody who asked a question.
    if (parsed.rows.length < 2) return null;

    final fingerprint = ProposedImport.fingerprintOf(q);
    final plan = ProposedImport(
      steps: stepsForImport(parsed.rows),
      problems: parsed.problems,
      source: q,
      fingerprint: fingerprint,
    );

    // The same list pasted twice must not double everyone's balance. Says so
    // rather than quietly doing nothing, because a card that appears to do
    // nothing looks broken.
    if (await plan.alreadyImported(store)) {
      return const Msg(
        MsgRole.koru,
        'You have already added these. I did not add them again, in case that '
        'was not what you meant.',
        why: 'This exact list was imported before.',
        local: true,
      );
    }

    final count = parsed.rows.length;
    final clients = count == 1 ? 'client' : 'clients';
    final missed = parsed.problems.length;
    // Built as one string rather than an interpolation of conditionals, because
    // the earlier version read as four sentences glued together and one of them
    // was empty whenever every line parsed.
    final tail = missed == 0
        ? ''
        : ', and $missed '
            '${missed == 1 ? 'line' : 'lines'} I could not read';
    return Msg(
      MsgRole.koru,
      'I read $count $clients out of that$tail. '
          'Nothing is saved until you say so.',
      why: 'Read as a list, not a sentence.',
      local: true,
      proposed: plan,
    );
  }

  /// Counts requests. Anything started before the current one is stale.
  int _generation = 0;

  /// Replaces a reply that claims it saved something with one that did not.
  ///
  /// Only reached when no write was proposed, because a write that went through
  /// a card really was saved and the model is right to say so. A model that says
  /// "I've added Bilal" when nothing was added is worse than useless: the chat
  /// looks like a receipt and the record is simply not there.
  String _honestAboutWrites(String text) {
    if (!WriteClaimGuard.claimsWrite(text)) return text;
    return WriteClaimGuard.nothingWasSaved;
  }

  /// What the app is about to do about [q], in the user's terms.
  ///
  /// Names the job rather than how the bytes are moving. It used to open on
  /// "Waking up" for every request and only move on when the engine reported a
  /// token or a prefill tick, so anything that did not go through the local model
  /// sat on "Waking up" for the whole answer, which is both wrong and the reason
  /// the indicator seemed stuck.
  String _activityFor(String q) {
    // A write is decided by the parser rather than the model, so claiming the
    // model was working on it was never true. Each kind gets its own name,
    // because "working out what you meant" over a calendar entry is a pause
    // with no explanation.
    final intent = const WriteIntentParser().parse(q);
    if (intent is AddEventIntent) return 'Checking your calendar';
    if (intent is AddDeadlineIntent) return 'Checking what is due';
    if (intent != null) return 'Working out what you meant';
    if (q.split('\n').where((l) => l.trim().isNotEmpty).length > 1) {
      return 'Reading your list';
    }
    final lower = q.toLowerCase();
    if (lower.contains('due') ||
        lower.contains('owe') ||
        lower.contains('today') ||
        lower.contains('overdue')) {
      return 'Checking what is due';
    }
    if (lower.contains('who') || lower.contains('client')) {
      return 'Looking up your clients';
    }
    return 'Working out what you meant';
  }

  /// Set when this notifier goes away. Riverpod's Notifier ref has no `mounted`,
  /// and the engine start is a long await that can outlive the screen that
  /// asked for it, so it needs its own liveness flag rather than a ref to ask.
  bool _gone = false;

  /// Stops the answer being written.
  ///
  /// There is no way to interrupt a socket read part way through, so this marks
  /// the request dead and lets it drain in the background. The tokens stop
  /// updating the bubble immediately, which is what pressing stop has to do.
  void stop() {
    if (!state.busy) return;
    // Bumping the counter retires whatever is in flight. Nothing has to clear it
    // later, which is exactly the thing the old flag kept forgetting to do.
    _generation++;
    final messages = [...state.messages];
    final at = messages.lastIndexWhere((m) => m.pending);
    if (at >= 0) {
      messages[at] = const Msg(
        MsgRole.koru,
        'Stopped.',
        why: 'You stopped this one.',
        local: true,
      );
    }
    state = state.copyWith(busy: false, messages: messages);
  }

  /// Edits a message the user sent and asks again from there.
  ///
  /// Everything from that point on is dropped, because keeping the old answer
  /// would leave two replies to the same question on screen with nothing saying
  /// which one is current.
  Future<void> editAndResend(int messageIndex, String text) async {
    final q = text.trim();
    if (q.isEmpty || messageIndex < 0 || messageIndex >= state.messages.length) return;

    final target = state.messages[messageIndex];

    // Everything is checked before anything is destroyed.
    //
    // This used to delete the stored records and trim the screen first, then
    // call ask(), which can return immediately if an answer is already running.
    // That ordering meant an edit during a reply wiped the conversation and
    // added nothing in its place: messages gone, no new turn, and no error.
    // Deleting is the last thing that happens here, not the first.
    if (target.role != MsgRole.user) {
      state = state.copyWith(messages: [
        ...state.messages,
        const Msg(
          MsgRole.koru,
          'That one is mine, so you cannot edit it. Long press anything you '
          'sent to change a question.',
          why: 'Only your own messages can be edited.',
          local: true,
        ),
      ]);
      return;
    }
    if (state.busy) {
      state = state.copyWith(messages: [
        ...state.messages,
        const Msg(
          MsgRole.koru,
          'I am still answering that one. Stop it first if you want to change '
          'the question.',
          why: 'Editing while an answer is running.',
          local: true,
        ),
      ]);
      return;
    }

    final store = await ref.read(storeProvider.future);
    // The stored transcript has no greeting, the screen does, so the two
    // indices are offset by one. Getting this wrong would delete the wrong
    // part of the conversation, which is why it is not left implicit.
    const greetingOffset = 1;
    await store.truncateChat(messageIndex - greetingOffset);

    // ask() appends the user turn itself, so the screen is trimmed to just
    // before the edited message and the new turn is added once, not twice.
    state = state.copyWith(messages: state.messages.sublist(0, messageIndex));
    await ask(q);
  }

  /// The last few exchanges, oldest first, for the model's prompt.
  List<ChatTurn> _recentTurns() {
    // Budgeted in TOKENS against the engine's real context window, not in
    // characters or turns. This is not a detail: an earlier version allowed 8
    // turns of 400 characters each, which is roughly 1600 tokens, against a
    // 1024 token KV cache. A conversation that grew past the window made glen
    // index off the end of the cache and panic, killing the engine. The next
    // question restarted it cold, the one after started from an even longer
    // transcript, and the app got slower and slower instead of just slow.
    //
    // Measured on the target phone: 222 token prompt cold is 14.5s, then every
    // follow-up reuses the cached prefix and costs 3.6s. Decode itself never
    // moved off about 4 tok/s.
    const budgetChars = _historyBudgetChars;
    final out = <ChatTurn>[];
    var used = 0;
    for (final m in state.messages.reversed) {
      if (m.pending || m.text.trim().isEmpty) continue;
      if (m.role != MsgRole.user && m.role != MsgRole.koru) continue;

      final text = m.text.length > 400 ? '${m.text.substring(0, 400)}...' : m.text;
      // Counted in characters, not a token estimate. The two differ by about
      // four to one, and a budget that is quietly measured in something other
      // than what it says is how a limit stops being a limit.
      final cost = text.length + 8;
      if (used + cost > budgetChars) break;
      used += cost;

      out.add(ChatTurn(
        m.role == MsgRole.user ? ChatRole.user : ChatRole.koru,
        text,
      ));
    }
    return out.reversed.toList();
  }

  Future<Msg> _respond(
    String q,
    RoutingDecision routing,
    ProfileStore store,
    List<ChatTurn> history,
    bool Function() isStale,
  ) async {
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

    // A pasted list, before anything else.
    //
    // Checked first because a list and a sentence can both contain "add client",
    // and a list read as a sentence produces one enormous client called
    // "Bilal 3000 Acme 5000". Two or more readable rows is the signal, so a
    // single line still takes the ordinary single-write path and its amount can
    // still be corrected in the card.
    final imported = await _importPlan(q, store);
    if (imported != null) return imported;

    // An instruction to record something never reaches an engine at all. It is
    // recognised by a plain parser, resolved against the real records, and comes
    // back as a card to approve. A 0.5B model is a poor tool caller, and waiting
    // fifteen seconds for a possibly wrong write is a bad trade for a keystroke.
    final intent = const WriteIntentParser().parse(q);
    if (intent != null) {
      final resolution = await const WriteResolver().resolve(intent, store);
      if (resolution.isWrite) {
        return Msg(
          MsgRole.koru,
          'Here is what I understood. Nothing is saved until you say so.',
          why: 'Read as an instruction, not a question.',
          local: true,
          proposed: resolution.write,
        );
      }
      return Msg(
        MsgRole.koru,
        resolution.problem!,
        why: 'Could not turn that into something to save.',
        local: true,
      );
    }

    switch (KoruEngine.parse(await store.get('engine'))) {
      case KoruEngine.builtIn:
        return _askBuiltIn(q, routing, store);
      case KoruEngine.onDevice:
        return _askOnDevice(q, routing, store, history, isStale);
      case KoruEngine.cloud:
        return _askCloud(q, routing, store, history, isStale);
    }
  }

  /// Carries out an approved write and replaces the card with the outcome.
  ///
  /// The card is removed either way. Leaving an approved card on screen would
  /// offer the same write twice.
  Future<void> applyWrite(ProposedWrite write) async {
    final store = await ref.read(storeProvider.future);
    await write.apply(store);
    ref
      ..invalidate(clientsProvider)
      ..invalidate(paymentsProvider)
      ..invalidate(receivedTotalsProvider)
      ..invalidate(openDeadlinesProvider)
      ..invalidate(eventsProvider)
      ..invalidate(guideFactsProvider);

    // An import is remembered only once it has actually landed. Recording it
    // before would mean a failed import could never be retried, because the
    // next attempt would be refused as a duplicate of a list that never made it.
    if (write is ProposedImport) {
      await write.rememberImport(store);
    }

    // Read it back. apply() returning without throwing is not proof, and this
    // app has already been bitten by a reply claiming a save that did not
    // happen. The app holds itself to the same rule as the model: no save is
    // reported that has not been looked at afterwards.
    final problem = await write.verify(store);

    // A calendar entry can also go into the phone's own calendar. Opt-in from
    // Settings, and a failure there is a missing mirror rather than a failed
    // save: the in-app copy already landed and is verified above.
    var syncNote = '';
    if (problem == null && write is ProposedEvent) {
      syncNote = await _mirrorToPhoneCalendar(store, write);
    }

    final messages = [...state.messages];
    final at = messages.lastIndexWhere((m) => m.proposed != null);
    if (at < 0) return;
    messages[at] = Msg(
      MsgRole.koru,
      '${problem ?? 'Added ${write.summary}. You can undo this from Clients.'}'
      '$syncNote',
      // Saying why, when the write did not land, is the difference between a
      // bug report and a user who thinks their records are fine.
      why: problem == null ? 'You approved this, and I checked it saved.'
          : 'You approved this, and I checked. It did not save as described.',
      local: true,
    );
    state = state.copyWith(messages: messages);
  }

  /// Copies an approved entry to the phone's calendar, if the user turned that
  /// on. Returns a sentence about the outcome, or empty when nothing was
  /// attempted.
  Future<String> _mirrorToPhoneCalendar(
    ProfileStore store,
    ProposedEvent event,
  ) async {
    if (await store.get('calendar_sync') != '1') return '';
    final startsAt = event.startsAt;
    if (startsAt == null) return '';

    final ok = await ref.read(calendarBridgeProvider).addEvent(
          title: event.title,
          start: startsAt,
          end: startsAt.add(const Duration(hours: 1)),
          location: event.location,
        );

    // Marked synced only when it really is, for the same reason the write above
    // is verified: a flag claiming a copy that does not exist is exactly the
    // kind of quiet lie this app is built to avoid.
    if (ok) {
      final rows = (await store.events())
          .where((e) => e.title == event.title && e.date == event.date)
          .toList();
      for (final row in rows) {
        await store.updateEvent(
            CalendarEvent.fromMap({...row.toMap(), 'synced': 1}));
      }
      return ' I also put it in your phone calendar.';
    }
    return ' I could not put it in your phone calendar, so add it there '
        'yourself if you want it on your home screen.';
  }

  /// Drops an unapproved card without doing anything.
  void discardWrite() {
    final messages = [...state.messages];
    final at = messages.lastIndexWhere((m) => m.proposed != null);
    if (at < 0) return;
    messages[at] = const Msg(
      MsgRole.koru,
      'Noted, and not saved.',
      why: 'You discarded this.',
      local: true,
    );
    state = state.copyWith(messages: messages);
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
  Future<Msg> _askOnDevice(
    String q,
    RoutingDecision routing,
    ProfileStore store,
    List<ChatTurn> history,
    bool Function() isStale,
  ) async {
    final config = await ref.read(localModelProvider.future);
    final client = ref.read(localModelClientProvider);
    final routing2 = routing;

    final system = LocalModelPrompt.build(
      packet: await store.packet(),
      facts: await _modelFacts(store),
      currency: (await ref.read(currencyProvider.future)).code,
    );

    final buffer = StringBuffer();
    Object? failure;
    Object? unavailable;

    try {
      final result = await client.chatStream(
        endpoint: config.endpoint,
        model: config.modelId,
        system: system,
        question: q,
        history: [
          for (final t in history)
            (
              role: t.role == ChatRole.user ? 'user' : 'assistant',
              content: t.text,
            ),
        ],
        onToken: (delta) {
          // Checked per token, not per reply: a cancelled request that keeps
          // writing into the buffer would repaint the bubble the stop button
          // just replaced.
          if (isStale()) return;
          buffer.write(delta);
          _updatePending(buffer.toString());
        },
        onProgress: (done, total) {
          if (isStale()) return;
          if (state.activity != 'Reading your records') {
            state = state.copyWith(activity: 'Reading your records');
          }
          _updatePendingProgress(done, total);
        },
      );
      switch (result) {
        case LocalReply(:final tokensPerSecond):
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
        case LocalUnavailable(:final detail):
          unavailable = detail;
        case LocalFailed(:final reason):
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

  /// Replaces the text of the bubble currently being written.
  ///
  /// `pending` means "this message is still being generated", not "this message
  /// has no text yet". It used to be set from `text.isEmpty`, which meant the
  /// very first token cleared the flag, this guard then rejected every token
  /// after it, and the answer appeared all at once when generation finished.
  ///
  /// Symptom, for anyone reading this later: one letter appears instantly and
  /// the rest of the reply lands in a single jump several seconds later. The
  /// engine was streaming the whole time. glen sends each token as its own
  /// flushed chunk, 300ms apart, and that was measured on the device.
  void _updatePending(String text) {
    if (text.isEmpty) return;
    final messages = [...state.messages];
    final at = messages.lastIndexWhere((m) => m.pending);
    if (at < 0) return;
    // Still pending: the answer is not finished, so the typing indicator stays.
    messages[at] = messages[at].copyWith(text: text);
    state = state.copyWith(messages: messages);
  }

  /// Shows how far the model has got reading the prompt.
  ///
  /// Prefill is the longest silent stretch in the whole exchange: the prompt
  /// carries the caller's records, so the model spends seconds working through
  /// them before a single word comes out. A bare ellipsis through that window
  /// is indistinguishable from a crash, so the bubble names what is happening.
  /// Stops at the first token, when there is real text to show instead.
  void _updatePendingProgress(int done, int total) {
    final messages = [...state.messages];
    if (messages.isEmpty) return;
    final last = messages.last;
    if (!last.pending || last.text.isNotEmpty) return;
    final pct = total <= 0 ? 0 : (done * 100 / total).round().clamp(0, 100);
    messages[messages.length - 1] =
        last.copyWith(text: 'Reading your records, $pct%', pending: true);
    state = state.copyWith(messages: messages);
  }

  Future<Msg> _askCloud(
    String q,
    RoutingDecision routing,
    ProfileStore store,
    List<ChatTurn> history,
    bool Function() isStale,
  ) async {
    final selection = await ref.read(cloudSelectionProvider.future);
    final key = await ref.read(cloudKeyProvider(selection.provider.id).future);
    // Streams into the pending bubble, exactly as the local engine does.
    //
    // Cloud used to be one request with no tokens until the whole reply had
    // arrived, which made a frontier model look slower than the small one on
    // this phone. It was never slower; the wait was just invisible.
    final buffer = StringBuffer();
    final result = await ref.read(cloudModelProvider).ask(
          packet: await store.packet(),
          question: q,
          routing: routing,
          provider: selection.provider,
          model: selection.model,
          apiKey: key,
          history: [
            for (final t in history)
              (
                role: t.role == ChatRole.user ? 'user' : 'assistant',
                content: t.text,
              ),
          ],
          onToken: (delta) {
            if (isStale()) return;
            buffer.write(delta);
            _updatePending(buffer.toString());
          },
        );

    switch (result) {
      case CloudReply(:final text):
        // Anything already streamed is what the bubble is showing, so the
        // finished message must be that same text rather than a second copy.
        return Msg(
          MsgRole.koru,
          _honestAboutWrites(
              buffer.isNotEmpty ? buffer.toString().trim() : text),
          why: routing.reason,
          local: false,
          engine: KoruEngine.cloud,
        );
      case CloudUnavailable():
        // No key. Answer from the records and say why, rather than passing off a
        // weaker answer as the stronger one the user asked for.
        final fallback = await _askBuiltIn(q, routing, store);
        return fallback.copyWith(
          text: '${_honestAboutWrites(fallback.text)}\n\n(I answered that '
              'from your own records because no ${selection.provider.label} '
              'key is set. Add one in Settings.)',
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
        clients: await store.clients(),
        received: await store.receivedTotals(),
        deadlines: await store.deadlines(),
        projects: await store.projects(),
        projectNotes: await _latestNotePerProject(store),
        events: await store.events(),
      );
}

/// The most recent note per project, keyed by project id.
///
/// N+1 by nature: the notes table is per project and there is no single query
/// that answers "latest for each". Projects are few and this runs once per
/// reply, so the round trips are cheaper than keeping a denormalised copy in
/// sync with every note write.
Future<Map<int, String>> _latestNotePerProject(ProfileStore store) async {
  final out = <int, String>{};
  for (final p in await store.projects()) {
    final id = p.id;
    if (id == null) continue;
    final notes = await store.projectNotes(id, limit: 1);
    if (notes.isNotEmpty) out[id] = notes.first.body;
  }
  return out;
}

final chatProvider = NotifierProvider<ChatNotifier, ChatState>(ChatNotifier.new);

final clientsProvider = FutureProvider<List<Client>>((ref) async {
  final store = await ref.watch(storeProvider.future);
  return store.clients();
});

/// Money received per client, as a single grouped total.
///
/// One query for the whole screen rather than one per row. [Client.balanceWith]
/// turns each total into a balance, and the same totals give the screen-wide
/// figures, so the header and the rows cannot disagree.
final receivedTotalsProvider = FutureProvider<Map<int, double>>((ref) async {
  final store = await ref.watch(storeProvider.future);
  return store.receivedTotals();
});

/// What is worth interrupting the user about, worst first.
///
/// Shared by the widget, the notification and the launcher badge so that all
/// three cannot drift apart: the badge saying 3 while the notification says 2 is
/// the sort of thing that makes a helper feel broken rather than busy.
///
/// Invalidated whenever the data underneath it changes, so a payment recorded in
/// the app clears the badge without the user having to do anything.
final attentionProvider = FutureProvider<List<AttentionItem>>((ref) async {
  // Watching each source rather than the store, so the list is only rebuilt when
  // something in it actually moved.
  final clients = await ref.watch(clientsProvider.future);
  final received = await ref.watch(receivedTotalsProvider.future);
  final deadlines = await ref.watch(openDeadlinesProvider.future);
  final projects = await ref.watch(projectsProvider.future);
  return Attention.build(
    clients: clients,
    deadlines: deadlines,
    received: received,
    projects: projects,
  );
});

/// Every project, most recently touched first.
final projectsProvider = FutureProvider<List<Project>>((ref) async {
  final store = await ref.watch(storeProvider.future);
  return store.projects();
});

/// Keeps the notification in step with the data.
///
/// Watching [attentionProvider] rather than recomputing is what keeps the badge,
/// the notification and the app from disagreeing: there is one list, computed
/// once, and every surface reads that same list.
final attentionPublisher = Provider<void>((ref) {
  final bridge = ref.watch(attentionBridgeProvider);
  ref.listen(attentionProvider, (previous, next) {
    final items = next.valueOrNull;
    // Skipped while loading, on purpose. Publishing the empty list during a
    // reload would clear a perfectly correct badge every time the database was
    // read, which looks like the app losing track of what it owes.
    if (items == null) return;
    bridge.publish(items, link: _linkFor(items));
    // The widget and the notification are repainted from the same list in the
    // same pass, so the home screen can never show a different answer to
    // "what needs me" than the notification does.
    bridge.updateWidget(items);
    // Let the app close the shade and land somewhere sensible when nothing is
    // outstanding any more.
    if (items.isEmpty && (previous?.valueOrNull?.isNotEmpty ?? false)) {
      bridge.clear();
    }
  }, fireImmediately: true);
});

/// Where tapping the notification should open.
KoruDeepLink? _linkFor(List<AttentionItem> items) {
  if (items.isEmpty) return null;
  final first = items.first;
  return KoruDeepLink(kind: first.kind, target: first.target);
}

final attentionBridgeProvider = Provider<AttentionBridge>((ref) => const AttentionBridge());

/// What the app has permission to do when it is closed.
final healthProvider = FutureProvider<KoruHealth>((ref) async {
  return ref.watch(healthBridgeProvider).check();
});

final healthBridgeProvider = Provider<HealthBridge>((ref) => const HealthBridge());

/// Models the bundled engine could be pointed at, bundled one first.
final availableModelsProvider = FutureProvider<List<LocalModelFile>>((ref) async {
  return ref.watch(bundledEngineProvider).models();
});

/// Whether the on-device engine could actually run.
///
/// Since 1.0.0 the binary and the 0.5B model are out of the APK, so selecting
/// the on-device engine on a fresh install found nothing to start and silently
/// fell back to the built-in assistant. That fallback answers in milliseconds,
/// which is exactly why "the local model is so much faster than cloud" looked
/// true: no model was running. The setting has to say so instead.
final localEnginePresentProvider = FutureProvider<bool>((ref) async {
  if (!await ref.watch(bundledEngineProvider).available) return false;
  final models = await ref.watch(availableModelsProvider.future);
  return models.isNotEmpty;
});

/// The path of the model the user picked, or null for the bundled default.
///
/// Empty means the same as absent. Writing an empty string rather than deleting
/// the key keeps the store's write path uniform, and treating the two the same
/// here means a half finished switch cannot leave the engine pointed at nothing.
final chosenModelProvider = FutureProvider<String?>((ref) async {
  final store = await ref.watch(storeProvider.future);
  final path = await store.get('model_path');
  return (path == null || path.isEmpty) ? null : path;
});

/// Asks for the permissions Koru needs, in the order that is least annoying.
///
/// Notifications first because without them nothing else matters, and because a
/// refusal there explains the silence better than a battery setting does.
/// Battery exemption after, since it opens a system dialog that looks alarming
/// and should not be the first thing the app asks for.
///
/// Never throws and never blocks. A person who says no to all of it still gets
/// into the app, because a helper that holds the door until you agree to
/// everything is not a helper.
Future<void> requestHealthPermissions(WidgetRef ref) async {
  final bridge = ref.read(healthBridgeProvider);
  var health = await bridge.check();
  if (!health.notifications) await bridge.requestNotifications();
  // The prompt is a dialog and the answer comes back to the settings screen, so
  // this re-reads rather than assuming.
  health = await bridge.check();
  if (!health.batteryExempt) await bridge.requestBatteryExempt();
  health = await bridge.check();
  if (health.autostart == false) await bridge.openAutostartSettings();
  ref.invalidate(healthProvider);
}

/// The payments ledger, newest first, for the money section.
final paymentsProvider = FutureProvider<List<Payment>>((ref) async {
  final store = await ref.watch(storeProvider.future);
  return store.payments(limit: 25);
});

/// Open deadlines, soonest first. [ProfileStore.deadlines] already sorts.
final openDeadlinesProvider = FutureProvider<List<Deadline>>((ref) async {
  final store = await ref.watch(storeProvider.future);
  return store.deadlines();
});

/// Calendar entries, from today forward.
///
/// Anchored at today rather than "everything on file" so the provider cannot
/// grow without bound as the calendar fills up: screens that need a different
/// window can pass their own, but the shared one answers "what is coming".
final eventsProvider = FutureProvider<List<CalendarEvent>>((ref) async {
  final store = await ref.watch(storeProvider.future);
  final today = DateTime.now();
  return store.events(from: DateTime(today.year, today.month, today.day));
});

/// Writing to the phone's own calendar. Kept behind a provider so a test can
/// replace it and no test ever touches a real calendar.
final calendarBridgeProvider = Provider<CalendarBridge>((ref) => const CalendarBridge());

/// How many clients this person is willing to carry at once.
///
/// Defaults to 5 when unset, which is also what onboarding starts on. A default
/// is a real decision: without one the meter has nothing to measure against and
/// the whole capacity idea silently does nothing on a fresh install.
final capacityProvider = FutureProvider<int>((ref) async {
  final store = await ref.watch(storeProvider.future);
  final stored = await store.number('capacity');
  return stored == null ? defaultCapacity : stored.toInt();
});

/// The default, exported so the screen and the settings control cannot
/// disagree about what a fresh install looks like.
const int defaultCapacity = 5;

/// Which engine answers. Persisted so the choice survives a restart.
final engineProvider = FutureProvider<KoruEngine>((ref) async {
  final store = await ref.watch(storeProvider.future);
  return KoruEngine.parse(await store.get('engine'));
});

/// Which cloud provider and model are selected.
final cloudSelectionProvider = FutureProvider<({CloudProvider provider, String model})>(
  (ref) async {
    final store = await ref.watch(storeProvider.future);
    final provider = providerById(await store.get('cloud_provider') ?? 'openrouter');
    final stored = await store.get('cloud_model');
    final model = (stored == null || stored.isEmpty)
        ? (provider.models.isNotEmpty ? provider.models.first : 'local')
        : stored;
    return (provider: provider, model: model);
  },
);

/// Everything the guide is allowed to look at, for the current screen.
final guideFactsProvider = FutureProvider<ScreenFacts>((ref) async {
  final store = await ref.watch(storeProvider.future);
  final all = await store.all();
  return ScreenFacts(
    clients: await store.clients(),
    received: await store.receivedTotals(),
    deadlines: await store.deadlines(),
    payments: await store.payments(limit: 25),
    hasProfile: (all['nickname']?.isNotEmpty ?? false),
  );
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

final bundledEngineProvider = Provider<BundledEngine>((ref) => const BundledEngine());

/// Whether this APK actually contains an engine and a model, and why not if it
/// does not.
final bundledEngineStatusProvider = FutureProvider<BundledEngineStatus>((ref) async {
  return ref.read(bundledEngineProvider).status();
});

final bundledEngineAvailableProvider = FutureProvider<bool>((ref) async {
  return (await ref.watch(bundledEngineStatusProvider.future)).available;
});

/// Saves a cloud key and invalidates everything that depends on it.
///
/// Returns whether it actually worked. The old version swallowed the result and
/// the UI toasted success regardless, which is how a refused write turned into
/// "nothing responds" much later with nothing to point at.
Future<bool> saveCloudKey(WidgetRef ref, String providerId, String value) async {
  final ok = await ref.read(secretsProvider).writeKey(providerId, value.trim());
  ref.invalidate(cloudKeyProvider(providerId));
  return ok;
}
