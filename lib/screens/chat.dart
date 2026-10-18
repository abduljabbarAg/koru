import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../currency.dart';
import '../engine.dart';
import '../guide.dart';
import '../human_date.dart';
import '../mascot/mascot.dart';
import '../proposed_write.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/thinking_dots.dart';
import 'chat_reply.dart';
import 'engine_bar.dart';
import 'engine_sheet.dart';
import 'settings_cloud.dart';

/// The reply renderer lives beside this file and is re-exported, so a reply can
/// still be driven on its own through `package:koru/screens/chat.dart`.
export 'chat_reply.dart';

/// The screen the app is named for.
///
/// Everything that makes it feel like one conversation lives in the shared
/// thread primitives — the bubbles, the composer, the engine's banner, the way
/// back to the newest turn — so this file is only the state: what has been
/// said, what is being said, and where the view is.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _mascot = KoruMascotController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Attached to the controller rather than wrapped in a NotificationListener,
    // because the controller is already here and one listener is fewer moving
    // parts than a wrapper that has to forward notifications it does not use.
    _scroll.addListener(_trackScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _scroll.removeListener(_trackScroll);
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final q = _input.text;
    if (q.trim().isEmpty) return;
    _input.clear();
    _focus.requestFocus();
    await ref.read(chatProvider.notifier).ask(q);
    _mascot.greet();
    // An explicit send always lands at the new turn. The listener in build
    // handles following the stream and follows when the reader is already at
    // the bottom; this is the case where they were not, and pressed send
    // anyway, which is itself a request to go there.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _useSuggestion(String text) {
    _input.text = text;
    _input.selection = TextSelection.collapsed(offset: text.length);
    _send();
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(chatProvider);
    final guide = ref.watch(guideFactsProvider).valueOrNull;
    final guideSpeech = guide == null ? null : Guide.vary([
          Guide.forChat(guide),
          // Said when there is a profile and nothing else, which is the moment
          // a nudge is actually useful. Silence otherwise, on purpose.
          null,
        ], st.messages.length);

    // Follow the answer down while it streams, follow a new turn as soon as it
    // is added, and otherwise only follow when the reader is already at the
    // bottom. Auto-scrolling a conversation out from under someone reading the
    // top of it is worse than not scrolling at all.
    //
    // The two "grew" and "finishing" cases exist because the extent only
    // catches up a frame after the list is rebuilt: jumping on the update that
    // adds a turn would jump to the end of the *old* list, which is exactly how
    // an approval card ended up just below the fold.
    ref.listen(chatProvider, (previous, next) {
      if (!_scroll.hasClients) return;
      final grew = next.messages.length != previous?.messages.length;
      final finishing = previous?.busy == true && !next.busy;
      // A new turn always brings the view back: that is what pressing send
      // means. Arriving tokens do not, because the reader may be reading back
      // through an earlier answer and being dragged to the bottom on every
      // token makes that impossible.
      if (grew) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_scroll.hasClients) return;
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
          setState(() => _following = true);
        });
        return;
      }
      if (!_following) return;
      if (!next.busy && !finishing) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    });

    return Scaffold(
      appBar: AppBar(
        titleSpacing: KoruSpace.gutter,
        // Flexible so the wordmark gives way rather than the bar: the engine
        // control is the thing on this bar somebody has to be able to reach on
        // the narrowest phone this runs on, and a bar that has quietly pushed
        // itself off the edge is worse than a shortened name.
        title: Row(
          children: [
            KoruMascot(size: KoruSize.mark, controller: _mascot, busy: st.busy),
            const SizedBox(width: KoruSpace.sm),
            const Flexible(
              child: Text('Koru', maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        actions: [
          // Which engine answers is a fact about this screen, so it is said here
          // and changed here. It used to hang off the badge on a reply, which
          // meant the control only existed once there was a conversation and
          // then appeared once per message instead of once per screen.
          const EngineBarControl(),
          if (st.messages.length > 1)
            IconButton(
              tooltip: 'Clear conversation',
              icon: Icon(
                Icons.restart_alt_rounded,
                size: KoruSize.icon,
                color: KoruColors.inkFaint,
              ),
              onPressed: _confirmClear,
            ),
          const SizedBox(width: KoruSpace.xs),
        ],
      ),
      body: Column(
        children: [
          // Only over the empty state. Once a conversation is under way the
          // same line is a recording, and it would also sit on top of the very
          // cards it is telling the user they do not have.
          if (guideSpeech != null && st.messages.length <= 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                KoruSpace.gutter,
                KoruSpace.sml,
                KoruSpace.gutter,
                0,
              ),
              child: KoruGuideBanner(speech: guideSpeech, onTap: () {}),
            ),
          Expanded(
            // The thread and the way back to the newest turn are stacked rather
            // than laid out one above the other, because the button appears and
            // disappears as the reader scrolls. In a Column it would take its
            // space from the composer and lift it off the keyboard mid-answer,
            // which is the kind of movement nobody notices until it is
            // happening to them.
            child: Stack(
              children: [
                Positioned.fill(
                  child: st.messages.length <= 1
                      ? _intro(st)
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(
                            KoruSpace.gutter,
                            KoruSpace.md,
                            KoruSpace.gutter,
                            KoruSpace.sm,
                          ),
                          itemCount: st.messages.length,
                          itemBuilder: (_, i) {
                            final m = st.messages[i];
                            final above = i == 0 ? null : st.messages[i - 1];
                            return _ChatBubble(
                              m: m,
                              index: i,
                              activity: st.activity,
                              currency: ref
                                      .watch(currencyProvider)
                                      .valueOrNull
                                      ?.symbol ??
                                  'AED',
                              // Two turns in a row from the same speaker are one
                              // thought, so they sit closer together and the
                              // badge is shown once for the run rather than on
                              // every message in it.
                              grouped: above != null && above.role == m.role,
                              // Only where the conversation crosses midnight,
                              // which is the one place a reader loses their
                              // bearings.
                              dayDivider: _dayDivider(above, m),
                              onEdit: (text) => _editMessage(context, i, text),
                              onApprove: () => ref
                                  .read(chatProvider.notifier)
                                  .applyWrite(m.proposed!),
                              onDiscard: () => ref
                                  .read(chatProvider.notifier)
                                  .discardWrite(),
                              onFixEngine: (u) => _fixEngine(context, u),
                            );
                          },
                        ),
                ),
                // A way back down while an answer is arriving.
                //
                // Only shown when the reader is actually scrolled up. Following
                // a stream by dragging is the normal way to read back through a
                // long answer, and the view used to keep yanking itself to the
                // bottom, so the only way to read was to wait for it to finish.
                if (st.busy && !_following)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: KoruSpace.lg,
                    child: Center(
                      child: KoruJumpToNewest(onTap: _jumpToNewest),
                    ),
                  ),
              ],
            ),
          ),
          KoruComposer(
            controller: _input,
            focusNode: _focus,
            busy: st.busy,
            onSend: _send,
            onStop: () => ref.read(chatProvider.notifier).stop(),
          ),
        ],
      ),
    );
  }

  /// Whether the reader is at the bottom, which is what decides if an arriving
  /// token should scroll the view or be left for later.
  bool _following = true;

  void _trackScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    // A finger tolerance, because "at the bottom" during a drag is never
    // exactly true and a reader would be yanked back by a pixel.
    _following = pos.maxScrollExtent - pos.pixels < 48;
  }

  void _jumpToNewest() {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
    setState(() => _following = true);
  }

  /// The label for the line that marks a new day, or null when the turn belongs
  /// to the same run as the one above it.
  ///
  /// Compares calendar days rather than hours, so a conversation that runs past
  /// midnight is cut in the right place, and a message with no timestamp yet —
  /// the turn that was just appended — never moves a divider. The first turn
  /// draws nothing: a thread that opens on a divider labels a conversation
  /// nobody has lost track of yet.
  static String? _dayDivider(Msg? above, Msg m) {
    final at = m.time;
    if (at == null || above == null) return null;
    final was = above.time;
    if (was == null) return null;
    if (was.year == at.year && was.month == at.month && was.day == at.day) {
      return null;
    }
    return _dayLabel(at, DateTime.now());
  }

  /// "Today", "Yesterday", or the date. Worded by a person rather than left to
  /// the relative formatter, which says them in lower case and would put "today"
  /// in the middle of a sentence.
  static String _dayLabel(DateTime at, DateTime now) {
    final n = daysBetween(now, at);
    if (n == 0) return 'Today';
    if (n == -1) return 'Yesterday';
    return formatDay(at, now, style: DateStyle.short);
  }

  /// Throws the thread away, after saying what that costs.
  ///
  /// A dialog rather than a toast's undo, because there is no undo: the messages
  /// are gone the moment this lands and the person has to know that before they
  /// press it rather than after.
  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear this conversation?'),
        content: const Text(
            'Messages are stored on this device. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: KoruColors.clay),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(chatProvider.notifier).clear();
    if (mounted) toast(context, 'Conversation cleared');
  }

  /// The empty state.
  ///
  /// Not an empty list, which is the least useful thing a chat screen can be.
  /// The mascot is the hero because it is the thing the reader has not met yet,
  /// and the questions underneath are the ones this app can actually answer, so
  /// the first thing a new user learns is what to ask rather than that they are
  /// looking at a text box.
  ///
  /// Which engine is answering is not repeated here. It used to be, as a
  /// tappable badge, and it is now in the app bar where it can be changed —
  /// saying it twice on one screen meant a reader had to work out which of the
  /// two was the control.
  ///
  /// The questions sit on a card rather than floating loose, because they are
  /// the one thing on this screen the reader can act on before they have typed
  /// anything, and a card says so where a scattered run of pills does not.
  Widget _intro(ChatState st) {
    const suggestions = [
      'How am I doing?',
      'Who owes me money?',
      'What should I chase this week?',
      'What is coming up?',
      'What is 15% of 2000?',
      'Schedule a call with Bilal tomorrow at 3pm',
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        KoruSpace.gutter,
        KoruSpace.sm,
        KoruSpace.gutter,
        KoruSpace.lg,
      ),
      children: [
        Center(
          child: KoruMascot(
            size: 132,
            controller: _mascot,
            busy: st.busy,
            semanticLabel: 'Koru, your helper. Tap to say hello.',
          ),
        ),
        const SizedBox(height: KoruSpace.xl),
        Text(
          'Ask me about your clients, your money and what is due.',
          textAlign: TextAlign.center,
          style: KoruType.rowTitleLarge,
        ),
        const SizedBox(height: KoruSpace.sm),
        // Says what is behind the answers rather than pretending there is one on
        // the phone. It used to promise a local model and route faith, health,
        // medicine and law somewhere else; there is one model now, and it is
        // online.
        Text(
          'Answers come from the cloud model you connect in Settings. Faith, '
          'health, medicine and law go to a person instead.',
          textAlign: TextAlign.center,
          style: KoruType.bodySmall,
        ),
        const SizedBox(height: KoruSpace.md),
        KoruCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionLabel('Try one of these'),
              KoruFilterBar(
                padding: EdgeInsets.zero,
                children: [
                  for (final s in suggestions)
                    KoruSelectablePill(
                      label: s,
                      onTap: () => _useSuggestion(s),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Carries out the action on a "nothing could answer" card.
  ///
  /// Two destinations and no third. Both are one tap from the question the
  /// person just asked, which is the point of the card: a failure that sends
  /// them somewhere else to arrange it reads as a dead end, and the sentence
  /// above it already said there was nothing they could do about it.
  Future<void> _fixEngine(BuildContext context, EngineUnavailable down) async {
    if (!context.mounted) return;
    switch (down.recovery) {
      case EngineRecovery.addCloudKey:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const CloudSettingsScreen()),
        );
      case EngineRecovery.connectCloud:
        // Nobody has picked a company yet, so the sheet is where that happens —
        // and it says plainly that nothing is connected rather than opening on
        // a list of companies with no tick on any of them.
        await showEngineSwitcher(context);
    }
  }

  Future<void> _editMessage(BuildContext context, int index, String current) async {
    final controller = TextEditingController(text: current);
    final edited = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => KoruSheetBody(
        title: 'Edit message',
        subtitle: 'Asking again drops the reply below it.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              minLines: 1,
              maxLines: 5,
            ),
            const SizedBox(height: KoruSpace.lg),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Ask again'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (edited == null) return;
    final q = edited.trim();
    if (q.isEmpty || q == current.trim()) return;
    await ref.read(chatProvider.notifier).editAndResend(index, q);
  }
}

/// One message, with its badge, its bubble and anything it proposed.
///
/// A stateful widget rather than a value notifier allocated inside build: the
/// old shape created a fresh [ValueNotifier] for every bubble on every rebuild
/// and never disposed it, so a long conversation leaked one notifier per
/// message per frame while the handoff card lost its dismissed state every time
/// the screen redraw. The dismiss now lives with the bubble it belongs to and
/// dies with it.
class _ChatBubble extends StatefulWidget {
  const _ChatBubble({
    required this.m,
    required this.index,
    required this.activity,
    required this.currency,
    required this.onEdit,
    required this.onApprove,
    required this.onDiscard,
    required this.onFixEngine,
    required this.grouped,
    required this.dayDivider,
  });

  final Msg m;
  final int index;
  final String? activity;
  final String currency;

  /// The same speaker as the message above, so this one closes their run
  /// rather than starting a new one.
  final bool grouped;

  /// Set when this turn opens a new day in the thread.
  final String? dayDivider;

  final void Function(String text) onEdit;
  final VoidCallback onApprove;
  final VoidCallback onDiscard;

  /// Runs the action on the "no engine could answer" card, if this turn has one.
  final void Function(EngineUnavailable down) onFixEngine;

  @override
  State<_ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<_ChatBubble> {
  bool _handoffDismissed = false;

  Msg get m => widget.m;

  String _clock(DateTime t) {
    final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final minute = t.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${t.hour >= 12 ? 'pm' : 'am'}';
  }

  @override
  Widget build(BuildContext context) {
    final isUser = m.role == MsgRole.user;
    final time = m.time;
    // A run of turns by one speaker is one block of conversation: the mark, the
    // engine badge and the clock belong to the run rather than to every turn in
    // it, and the turns sit closer together. Everything after that is the same
    // shape whichever side of the thread it is on.
    final opens = !widget.grouped;

    final body = Padding(
      padding: EdgeInsets.only(
        bottom: widget.grouped ? KoruSpace.sm : KoruSpace.lg,
      ),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isUser && opens)
            KoruMessageMeta(
              leading: const KoruMark(size: KoruSize.markSm),
              // Built only when a model actually wrote this. A badge with a
              // null engine renders nothing, but constructing one for every app
              // reply means the tree claims there was provenance to report.
              badge: m.engine == null ? null : KoruEngineBadge(engine: m.engine),
              why: m.why,
              clock: time == null ? null : _clock(time),
            ),
          KoruBubble(
            mine: isUser,
            child: m.pending && m.text.isEmpty
                ? KoruThinkingDots(
                    // Koru's own face while she is working. The dots meant the
                    // reply came from somewhere; this means it came from her.
                    showMascot: true,
                    activity: switch (widget.activity) {
                      'Writing an answer' => KoruActivity.writing,
                      'Reading your list' => KoruActivity.readingList,
                      'Checking what is due' => KoruActivity.checking,
                      'Looking up your clients' => KoruActivity.looking,
                      'Checking your calendar' => KoruActivity.checking,
                      _ => KoruActivity.thinking,
                    },
                  )
                // The time goes inside the bubble rather than in a row
                // above it. A row per message is what made a long thread
                // grow tall enough to push the approval cards below the
                // fold, which is a worse problem than not having a time at
                // all. Only the turn that opens a run carries it.
                : isUser
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // The accent foreground comes from the palette rather
                          // than from white: in the dark palette the brand green
                          // is light, and hard-coded white on it is 1.9:1.
                          Text(
                            m.text,
                            style: KoruType.bodyStrong.copyWith(
                              color: KoruColors.onAccent,
                            ),
                          ),
                          if (time != null && opens) ...[
                            const SizedBox(height: KoruSpace.xs),
                            Text(
                              _clock(time),
                              style: KoruType.micro.copyWith(
                                color: KoruColors.onAccent.withValues(alpha: 0.72),
                              ),
                            ),
                          ],
                        ],
                      )
                    : RichReply(text: m.text, muted: m.pending),
          ),
          if (m.handoff != null && !_handoffDismissed)
            HandoffCard(
              plan: m.handoff!,
              onDismiss: () => setState(() => _handoffDismissed = true),
            ),
          if (m.unavailable != null)
            KoruEngineDownCard(
              unavailable: m.unavailable!,
              onFix: () => widget.onFixEngine(m.unavailable!),
            ),
          if (m.proposed is ProposedPlan)
            PlanCard(
              write: m.proposed! as ProposedPlan,
              onApprove: widget.onApprove,
              onDiscard: widget.onDiscard,
            )
          else if (m.proposed != null)
            WriteCard(
              write: m.proposed!,
              currency: widget.currency,
              onApprove: widget.onApprove,
              onDiscard: widget.onDiscard,
            ),
        ],
      ),
    );

    final divider = widget.dayDivider;

    // Long press, not a button on every message: an icon beside each message
    // clutters the thread, and both actions are rare enough that reaching for
    // them is fine. On your own messages it opens the editor; on Koru's it
    // copies the answer, which is what people screenshot chats for.
    return GestureDetector(
      onLongPress: () async {
        if (isUser) {
          widget.onEdit(m.text);
          return;
        }
        if (m.text.isEmpty) return;
        await Clipboard.setData(ClipboardData(text: m.text));
        if (context.mounted) toast(context, 'Copied');
      },
      child: divider == null
          ? body
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KoruThreadDivider(label: divider),
                body,
              ],
            ),
    );
  }
}
