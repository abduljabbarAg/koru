import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'attention.dart';
import 'attention_bridge.dart';
import 'calendar_bridge.dart';
import 'cloud.dart';
import 'cloud_providers.dart';
import 'deep_link.dart';
import 'engine.dart';
import 'guide.dart';
import 'handoff.dart';
import 'local/bulk_import.dart';
import 'local/write_intent.dart';
import 'models.dart';
import 'packet.dart';
import 'permission_consent.dart';
import 'proposed_write.dart';
import 'secrets.dart';
import 'store.dart';
import 'work_queue.dart';

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

  /// When this message was written, for the timestamp under the bubble. Null
  /// on the opening greeting, which has no moment.
  final DateTime? time;

  /// Which engine produced this message. Null on the opening greeting, on
  /// anything the user typed, and on anything the app itself said — a card it
  /// built, a write it confirmed. A badge naming an engine under a sentence no
  /// model wrote is the lie this whole path exists to stop telling.
  final KoruEngine? engine;
  final HandoffPlan? handoff;

  /// A write waiting for the user to approve it. Set instead of an answer when
  /// the message was understood as an instruction to record something.
  final ProposedWrite? proposed;

  /// Set instead of an answer when nothing could answer at all.
  ///
  /// Carries the one tap that fixes it. The alternative used to be a substitute
  /// answer from the app's own rules, which is worse than silence: it put a
  /// sentence under a Koru badge and let the reader believe a model had spoken.
  final EngineUnavailable? unavailable;

  const Msg(
    this.role,
    this.text, {
    this.why,
    this.pending = false,
    this.time,
    this.engine,
    this.handoff,
    this.proposed,
    this.unavailable,
  });

  Msg copyWith({String? text, bool? pending, ProposedWrite? proposed}) => Msg(
        role,
        text ?? this.text,
        why: why,
        pending: pending ?? this.pending,
        time: time,
        engine: engine,
        handoff: handoff,
        proposed: proposed ?? this.proposed,
        unavailable: unavailable,
      );

  /// The same message, stamped with when it arrived.
  Msg stampedAt(DateTime t) => Msg(
        role,
        text,
        why: why,
        pending: pending,
        time: t,
        engine: engine,
        handoff: handoff,
        proposed: proposed,
        unavailable: unavailable,
      );
}

/// Tells [ChatState.copyWith] to leave a field alone.
///
/// The activity field has to be settable *back* to null — a turn finished, a
/// new one has not started — and `?? this.x` cannot express that, so a stale
/// label otherwise stays on the composer for the rest of the session.
const _keep = Object();

/// What the chat is showing right now.
class ChatState {
  final List<Msg> messages;
  final bool busy;
  final bool loaded;

  /// What the model is doing right now, so the waiting indicator can say so.
  ///
  /// Names the job rather than how the bytes are moving. A model reading the
  /// caller's records and a model writing an answer feel identical as three
  /// bouncing dots and completely different once named.
  final String? activity;

  const ChatState({
    required this.messages,
    required this.busy,
    this.loaded = false,
    this.activity,
  });

  ChatState copyWith({
    List<Msg>? messages,
    bool? busy,
    bool? loaded,
    Object? activity = _keep,
  }) =>
      ChatState(
        messages: messages ?? this.messages,
        busy: busy ?? this.busy,
        loaded: loaded ?? this.loaded,
        activity:
            identical(activity, _keep) ? this.activity : activity as String?,
      );
}

const _greeting = 'I am here. Tell me what you need recorded, or ask me about '
    'your work, your money and what is due. I will tell you when a person '
    'should answer instead of me.';

class ChatNotifier extends Notifier<ChatState> {
  @override
  ChatState build() {
    // Notifier has no dispose to override in this version of Riverpod, so the
    // liveness flag is armed from here instead.
    ref.onDispose(() => _gone = true);
    return const ChatState(
      messages: [Msg(MsgRole.koru, _greeting)],
      busy: false,
    );
  }

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
      const Msg(MsgRole.koru, _greeting),
      ...records.map((r) {
        final at = DateTime.tryParse(r.created);
        return r.role == 'user'
            ? Msg(MsgRole.user, r.text, time: at)
            : Msg(MsgRole.koru, r.text, why: r.why, time: at);
      }),
    ];
    state = state.copyWith(messages: messages, loaded: true);
  }

  Future<void> clear() async {
    final store = await ref.read(storeProvider.future);
    await store.clearChat();
    // A question held for a turn that is still running belongs to a conversation
    // that no longer exists.
    _queued.clear();
    state = const ChatState(
      messages: [Msg(MsgRole.koru, _greeting)],
      busy: false,
      loaded: true,
    );
  }

  Future<void> ask(String question) async {
    final q = question.trim();
    if (q.isEmpty) return;

    // Asked while an answer is still arriving: held, not dropped.
    //
    // It used to return here, silently. On this phone an answer takes about
    // thirteen seconds, so the window in which a second question is refused is
    // not an edge case — it is most of the time somebody is reading the last
    // answer and thinking of the next one. The composer had already cleared
    // itself by then, so the question was gone and the screen went on showing
    // the previous answer: what the user described as asking a second question
    // and getting the same answer back. Nothing was sent, so nothing could
    // depend on the new input either.
    //
    // Holding it instead means the question goes out as soon as the turn it was
    // typed during is finished, carrying the exchange that came before it, which
    // is what the person meant by asking it at all.
    if (state.busy) {
      _queued.add(q);
      return;
    }
    await _turn(q);
    await _drainQueued();
  }

  /// Questions typed while an answer was arriving, oldest first.
  final List<String> _queued = [];

  bool _draining = false;

  /// Sends whatever was asked while a turn was running, one at a time.
  ///
  /// One at a time, so two turns can never interleave their tokens into one
  /// bubble. There is no engine queue any more to serialise against — the local
  /// one served a single slot — but the screen still only has one pending
  /// bubble, and two answers writing into it would be the same bug with a
  /// different cause.
  Future<void> _drainQueued() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_queued.isNotEmpty && !_gone) {
        await _turn(_queued.removeAt(0));
      }
    } finally {
      _draining = false;
    }
  }

  /// One question, start to finish: the turn itself.
  ///
  /// Wrapped rather than written inline so that a turn — including the store
  /// writes at both ends — is one named thing rather than three calls spread
  /// across the notifier.
  Future<void> _turn(String q) => _answer(q);

  Future<void> _answer(String q) async {
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

    // Names the job rather than how the bytes are moving. A question the app
    // can resolve against its own records, and a pasted list being read into a
    // plan, are different things and should not claim the same one.
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

  /// Characters of earlier conversation allowed into one prompt.
  ///
  /// Roughly 1200 characters is about 300 tokens, which is inside every window
  /// worth worrying about: the provider that served the local model ran a 1024
  /// token KV cache, and history that overran it took the engine down with it.
  /// A frontier model has room, but the cap is still worth keeping because it is
  /// what makes a follow-up's cost predictable, and a conversation that grows
  /// without bound gets slow rather than wrong.
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
  /// Names the job rather than how the bytes are moving. It used to sit on
  /// whatever the engine last reported — "Waking up" until a token or a prefill
  /// tick arrived — so anything resolved without the model appeared stuck for
  /// the whole answer.
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
      );
    }
    state = state.copyWith(busy: false, messages: messages);
    // Anything asked while this was being written goes now rather than waiting
    // for the socket to finish draining a reply nobody is going to read. The
    // stopped turn is retired, so it can no longer write, and the engine serves
    // one request at a time.
    if (_queued.isNotEmpty) unawaited(_drainQueued());
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
          proposed: resolution.write,
        );
      }
      return Msg(
        MsgRole.koru,
        resolution.problem!,
        why: 'Could not turn that into something to save.',
      );
    }

    // One engine, and it is a model. There is no other path that answers out of
    // the records instead, because that is the thing this app used to do whenever
    // a model was not available and it is what made a broken engine look like a
    // fast one.
    //
    // Whether anything is connected is checked before the question is asked of
    // anybody, so "no key" is reported in a second rather than after a round
    // trip to a provider that is going to refuse it.
    //
    // A read that throws is treated as nothing connected rather than allowed to
    // escape: the keystore is the one dependency here that can be gone (reinstall,
    // a locked screen, a vendor keystore that refuses), and a turn that throws
    // leaves the composer on a pending bubble forever. Not connected is the
    // honest reading of "the app cannot tell", and it has a button on it.
    final EngineLink link;
    try {
      link = await ref.read(engineLinkProvider.future);
    } catch (_) {
      return _notConnected(EngineLink.unreadable);
    }
    if (!link.isConnected) return _notConnected(link);
    return _askCloud(q, routing, store, history, isStale);
  }

  /// What to say when nothing can answer, and the one tap that changes it.
  ///
  /// The whole of the reply. It used to reach for a rules-based assistant that
  /// answered out of the user's own records, which produced a sentence in
  /// milliseconds and read exactly like a fast model — the reason a phone with
  /// no model running looked better than one with a frontier model on it.
  ///
  /// No engine badge goes on this message, deliberately. A label naming a model
  /// under a sentence no model wrote is the one lie this path exists to stop
  /// telling, and the bar above already says plainly that nothing is connected.
  Msg _notConnected(EngineLink link) {
    final down = EngineUnavailable(detail: link.missing, recovery: link.recovery);
    return Msg(
      MsgRole.koru,
      down.text,
      why: 'No model is connected.',
      unavailable: down,
    );
  }

  /// Carries out an approved write and replaces the card with the outcome.
  ///
  /// The card is removed either way. Leaving an approved card on screen would
  /// offer the same write twice.
  Future<void> applyWrite(ProposedWrite write) async {
    final store = await ref.read(storeProvider.future);
    await write.apply(store);
    // Everything the write could have moved, in one list. This was five
    // hand-maintained calls and grew a sixth every time something new was
    // added, which is how a screen ends up reading a list the chat has already
    // changed.
    for (final provider in _workData) {
      ref.invalidate(provider);
    }

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
    // Felt, not just shown. The card is gone by the time anyone reads a toast,
    // and this is the only confirmation that survives looking away for a second.
    HapticFeedback.mediumImpact();

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
      '${problem ?? write.applied ?? 'Added ${write.summary}. You can undo this from Clients.'}'
      '$syncNote',
      // Saying why, when the write did not land, is the difference between a
      // bug report and a user who thinks their records are fine.
      why: problem == null ? 'You approved this, and I checked it saved.'
          : 'You approved this, and I checked. It did not save as described.',
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
    );
    state = state.copyWith(messages: messages);
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
  /// model was streaming the whole time — it sends each token as its own flushed
  /// chunk, which is why this has to be driven from the token callback and not
  /// from the finished result.
  void _updatePending(String text) {
    if (text.isEmpty) return;
    final messages = [...state.messages];
    final at = messages.lastIndexWhere((m) => m.pending);
    if (at < 0) return;
    // Still pending: the answer is not finished, so the typing indicator stays.
    messages[at] = messages[at].copyWith(text: text);
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
    // Streams into the pending bubble, so a frontier model never sits silent for
    // the length of an answer. It used to be one request with no tokens until
    // the whole reply had arrived, which made the wait invisible and the model
    // look slow rather than busy.
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
            // The first token is the moment the job changes from "working out
            // what you meant" to "writing an answer", and the dots say which.
            // One write, not one per token.
            if (state.activity != 'Writing an answer') {
              state = state.copyWith(activity: 'Writing an answer');
            }
            buffer.write(delta);
            _updatePending(buffer.toString());
          },
        );

    switch (result) {
      case CloudReply(:final text):
        // Anything already streamed is what the bubble is showing, so the
        // finished message must be that same text rather than a second copy.
        final answer =
            _honestAboutWrites(buffer.isNotEmpty ? buffer.toString().trim() : text);
        // Defence in depth. The routing gate already stopped the question
        // reaching a model at all, but a guard on the output is the property
        // that matters: whatever the gate misses, an answer that gives dose or
        // case-law advice is not shown under a Koru badge.
        if (ModelOutputGuard.needsHuman(answer)) {
          return Msg(
            MsgRole.koru,
            'I am stepping aside on this one. Here is who to talk to.',
            why: 'The model drifted into an area that needs a person.',
            handoff: handoffPlanFor(routing, q),
          );
        }
        return Msg(
          MsgRole.koru,
          answer,
          why: routing.reason,
          engine: KoruEngine.cloud,
        );
      case CloudUnavailable():
        // The key was gone by the time the request was made. Reached rarely —
        // the link is checked before the question is asked of anybody — but it
        // is a real possibility on a key cleared from Settings while a turn was
        // in flight, and it has to land in the same honest place as any other
        // missing key rather than in an empty bubble.
        final down = EngineUnavailable(
          detail: 'No ${selection.provider.label} key is set',
          recovery: EngineRecovery.addCloudKey,
        );
        return Msg(
          MsgRole.koru,
          down.text,
          why: 'No cloud key is set for ${selection.provider.label}.',
          unavailable: down,
        );
      case CloudFailure(:final reason):
        return Msg(
          MsgRole.koru,
          reason,
          why: routing.reason,
          engine: KoruEngine.cloud,
        );
    }
  }

}

/// The link a notification tap asked us to open.
///
/// Null when no tap is waiting. Reading it takes the value and clears it, so a
/// second rebuild cannot navigate twice: the notification is gone from the tray
/// the moment it is tapped, and a replayed link would yank the user out of
/// whatever they had started reading.
///
/// Held in a provider rather than pushed straight into the navigator because a
/// cold start usually beats Flutter to the tap. The app is built first, and only
/// then does there exist a navigator to push onto.
final pendingLinkProvider = NotifierProvider<PendingLink, KoruDeepLink?>(
  PendingLink.new,
);

class PendingLink extends Notifier<KoruDeepLink?> {
  @override
  KoruDeepLink? build() {
    // Asked for rather than pushed in, because the link usually exists before
    // anything is listening.
    Future.microtask(_drain);
    return null;
  }

  Future<void> _drain() async {
    final link = await const AttentionBridge().takeLink();
    if (link == null) return;
    state = link;
    // Only meaningful once something is mounted to navigate.
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }

  /// Marks a link as handled so it cannot fire a second time.
  void clear() => state = null;

  /// Listens for taps that arrive while the app is already open.
  void listenOnOpen() {
    const AttentionBridge().listen((link) {
      state = link;
    });
  }
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
  final events = await ref.watch(eventsProvider.future);
  // Tasks too. The user writes these down expecting them to be waited on, and a
  // notification that ignored the one list they wrote themselves would be the
  // clearest possible way for this app to say it does not read what is on it.
  final tasks = await ref.watch(tasksProvider.future);
  return Attention.build(
    clients: clients,
    deadlines: deadlines,
    received: received,
    projects: projects,
    // Today's entries used to stay inside the Business screen, so a call at 3pm
    // could not reach a notification or the widget however overdue it got.
    events: events,
    tasks: tasks,
  );
});

/// Every project, most recently touched first.
final projectsProvider = FutureProvider<List<Project>>((ref) async {
  final store = await ref.watch(storeProvider.future);
  return store.projects();
});

/// Every task, done ones included, oldest first.
///
/// One read rather than two. The Tasks screen splits this list in half itself,
/// and a pending list and an archive fetched separately can disagree for as long
/// as one of them is still loading — which reads as a task that vanished.
final tasksProvider = FutureProvider<List<Task>>((ref) async {
  final store = await ref.watch(storeProvider.future);
  return store.tasks();
});

/// The day's work, ranked.
///
/// The screen that answers "what should I do now". Built from the same providers
/// [attentionProvider] is built from, plus the tasks the notification has no way
/// to know about, so the badge on the phone and the list inside it are reading
/// the same records.
final workQueueProvider = FutureProvider<List<WorkItem>>((ref) async {
  final clients = await ref.watch(clientsProvider.future);
  final received = await ref.watch(receivedTotalsProvider.future);
  final deadlines = await ref.watch(openDeadlinesProvider.future);
  final tasks = await ref.watch(tasksProvider.future);
  final projects = await ref.watch(projectsProvider.future);
  final events = await ref.watch(eventsProvider.future);
  return WorkQueue.build(
    clients: clients,
    deadlines: deadlines,
    tasks: tasks,
    received: received,
    projects: projects,
    events: events,
  );
});

/// Everything a write to a client, a payment, a deadline, a calendar entry, a
/// task or a project can have moved.
///
/// One list, because every one of those feeds the same queue and the same money
/// totals, and a screen left showing what was true a minute ago is worse than a
/// slow one. Held here rather than next to a screen so the screens cannot each
/// remember a different subset of it, and held as a list rather than as calls so
/// that the chat and a button on a row drop exactly the same things.
final List<ProviderOrFamily> _workData = [
  clientsProvider,
  paymentsProvider,
  receivedTotalsProvider,
  openDeadlinesProvider,
  eventsProvider,
  tasksProvider,
  projectsProvider,
  workQueueProvider,
  attentionProvider,
  guideFactsProvider,
  // The packet is what the model is told the user is working on, so a project
  // that moved has to be in it before the next question.
  packetProvider,
];

/// Drops the derived data after a write from a widget.
void invalidateWorkData(WidgetRef ref) {
  for (final provider in _workData) {
    ref.invalidate(provider);
  }
}

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

/// The reason Koru wants these three, in one place, said once.
///
/// Android shows a permission dialog with no explanation attached: "Allow Koru to
/// send notifications?" gives somebody no way to judge whether the answer is
/// right. So the judgement has to be made before the dialog, not after.
///
/// One message covering all three, because three separate explanations is three
/// separate reasons to stop reading. Said in the order the prompts appear.
const permissionReason = 'Koru needs three things to work when it is closed: '
    'notifications to tell you something is due, battery exemption so it can '
    'check on time, and your calendar so a meeting is not entered twice.';

/// Asks for the permissions Koru needs, in the order that is least annoying.
///
/// Notifications first because without them nothing else matters, and because a
/// refusal there explains the silence better than a battery setting does.
/// Battery exemption after, since it opens a system dialog that looks alarming
/// and should not be the first thing the app asks for. Calendar last, because it
/// is the only one that can be refused without losing anything.
///
/// Never throws and never blocks. A person who says no to all of it still gets
/// into the app, because a helper that holds the door until you agree to
/// everything is not a helper.
Future<void> requestHealthPermissions(
  WidgetRef ref, {
  ScaffoldMessengerState? messenger,
}) async {
  // Said before the first prompt, and left up. A reason that flashes past while
  // a dialog opens is not a reason, so the delay lives in the caller that owns
  // a screen: a Timer there can be cancelled when the screen goes, whereas a
  // bare delay here outlives the widget and outlives the test.
  if (messenger != null) {
    messenger
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(
        content: Text(permissionReason),
        duration: Duration(seconds: 7),
        behavior: SnackBarBehavior.floating,
      ));
  }

  final bridge = ref.read(healthBridgeProvider);
  var health = await bridge.check();
  if (!health.notifications) await bridge.requestNotifications();
  // The prompt is a dialog and the answer comes back to the settings screen, so
  // this re-reads rather than assuming.
  health = await bridge.check();
  if (!health.batteryExempt) await bridge.requestBatteryExempt();
  health = await bridge.check();
  if (health.autostart == false) await bridge.openAutostartSettings();

  // Calendar. Only asked if it is not already granted, and a refusal is normal:
  // the in-app calendar is the source of truth and works without this, so being
  // told no costs the user nothing they can see.
  final calendar = ref.read(calendarBridgeProvider);
  if (!await calendar.hasPermission) await calendar.requestPermission();

  ref.invalidate(healthProvider);
  ref.invalidate(calendarPermissionProvider);
}

/// Whether the permission explanation still owes this person a look.
///
/// The old signal was the stored `asked_permissions` flag, and it was the wrong
/// question. "Did we ask" is not "do they have anything", and the previous
/// release set that flag for every user who was already onboarded — before any
/// explanation existed to see — so the new screen could never appear for an
/// upgrading install. The reported symptom was exactly that.
///
/// This asks the real one: what has actually been granted. The flag the old
/// version wrote is still read, still on disk, and now only decides between
/// "asked by a snackbar nobody could read" and "not asked at all", both of
/// which resolve the same way.
final permissionConsentProvider = FutureProvider<PermissionConsent>((ref) async {
  final store = await ref.watch(storeProvider.future);
  final health = await ref.watch(healthProvider.future);
  final calendar = await ref.watch(calendarPermissionProvider.future);
  return PermissionConsent.fromStore(
    await store.all(),
    health: health,
    calendarGranted: calendar,
  );
});

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

/// Whether Koru may write to the phone's own calendar.
///
/// A provider rather than a read inside the settings switch, so a grant made on
/// first run shows up there without the screen having to guess when to look.
final calendarPermissionProvider = FutureProvider<bool>(
  (ref) => ref.watch(calendarBridgeProvider).hasPermission,
);

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

/// The engine, as stored.
///
/// One value, and nothing writes it any more except the migration that healed
/// whatever an older install had. It is still read rather than assumed, so the
/// string sitting in somebody's profile table is the thing the app answers with
/// — see [KoruEngine.parse] for why it has to be a total function.
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
        ? (provider.models.isNotEmpty ? provider.models.first : '')
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

/// Saves a cloud key and invalidates everything that depends on it.
///
/// Returns whether it actually worked. The old version swallowed the result and
/// the UI toasted success regardless, which is how a refused write turned into
/// "nothing responds" much later with nothing to point at.
Future<bool> saveCloudKey(WidgetRef ref, String providerId, String value) async {
  final ok = await ref.read(secretsProvider).writeKey(providerId, value.trim());
  ref.invalidate(cloudKeyProvider(providerId));
  // The link is what every surface reads to decide whether a model is
  // connected, so a key that has just landed — or just been cleared — has to
  // reach it or the app bar goes on saying "nothing connected" with a key saved.
  ref.invalidate(engineLinkProvider);
  return ok;
}

/// Whether a model can answer, and which one.
///
/// The single answer to the only question left about engines, and the reason
/// five surfaces do not each work it out: the store for the provider, the store
/// for the model, and the keystore for the key. Read from [cloudSelectionProvider]
/// rather than repeating those three reads, so the bar, the switcher, Settings
/// and the chat cannot disagree.
final engineLinkProvider = FutureProvider<EngineLink>((ref) async {
  final selection = await ref.watch(cloudSelectionProvider.future);
  final store = await ref.watch(storeProvider.future);
  // Read live rather than watching [cloudKeyProvider]: the key is stored per
  // provider, so the provider can change without the family key changing, and
  // watching the family would keep the last company's key.
  final key = await ref.watch(secretsProvider).readKey(selection.provider.id);
  return EngineLink(
    engine: await ref.watch(engineProvider.future),
    provider: selection.provider,
    model: selection.model,
    hasKey: key.trim().isNotEmpty,
    providerChosen: (await store.get('cloud_provider'))?.isNotEmpty ?? false,
  );
});
