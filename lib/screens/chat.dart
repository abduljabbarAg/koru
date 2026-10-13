import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../currency.dart';
import '../engine.dart';
import '../guide.dart';
import '../mascot/mascot.dart';
import '../proposed_write.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/thinking_dots.dart';

/// The engine warming up, or having failed to.
///
/// Reported here instead of on the splash so the app is usable while it happens.
class _EngineBanner extends StatelessWidget {
  const _EngineBanner({this.progress, this.problem});

  final int? progress;
  final String? problem;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    if (p == null && problem == null) return const SizedBox.shrink();
    final failed = p == null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      color: failed ? KoruColors.claySoft : KoruColors.leafSoft,
      child: Row(
        children: [
          if (!failed)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            const Icon(Icons.error_outline_rounded,
                size: 15, color: KoruColors.clay),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              failed
                  ? 'The on-device model did not start. $problem'
                  : 'Waking the local model up, $p%. You can carry on in the '
                      'meanwhile.',
              style: const TextStyle(fontSize: 12, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

/// Says which engine answered. The whole point of the app is that you can see
/// where an answer came from, and a local model is slow enough that an
/// unexplained pause would look like a hang.
class _EngineBadge extends StatelessWidget {
  const _EngineBadge({required this.engine, this.tokensPerSecond});

  final KoruEngine? engine;
  final double? tokensPerSecond;

  @override
  Widget build(BuildContext context) {
    final speed = tokensPerSecond;
    return switch (engine) {
      KoruEngine.onDevice => KoruPill(
          label: speed == null
              ? 'MODEL ON THIS PHONE'
              : 'THIS PHONE  ${speed.toStringAsFixed(1)} TOK/S',
          color: KoruColors.leaf,
          background: KoruColors.leafSoft,
          icon: Icons.memory_rounded,
        ),
      KoruEngine.cloud => const KoruPill(
          label: 'CLOUD MODEL',
          color: KoruColors.gold,
          background: KoruColors.goldSoft,
          icon: Icons.cloud_outlined,
        ),
      KoruEngine.builtIn => const KoruPill(
          label: 'FROM YOUR RECORDS',
          color: KoruColors.leaf,
          background: KoruColors.leafSoft,
          icon: Icons.storage_rounded,
        ),
      null => const SizedBox.shrink(),
    };
  }
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _mascot = KoruMascotController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatProvider.notifier).load();
    });
  }

  @override
  void dispose() {
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
    final engineProgress = st.engineProgress;
    final engineProblem = st.engineProblem;
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
      final atBottom =
          _scroll.position.pixels >= _scroll.position.maxScrollExtent - 140;
      if (!next.busy && !grew && !finishing && !atBottom) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    });

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            KoruMascot(size: 30, controller: _mascot, busy: st.busy),
            const SizedBox(width: 9),
            const Text('Koru'),
          ],
        ),
        actions: [
          if (st.messages.length > 1)
            IconButton(
              tooltip: 'Clear conversation',
              icon: const Icon(Icons.restart_alt_rounded, size: 21, color: KoruColors.inkFaint),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Clear this conversation?'),
                    content: const Text(
                        'Messages are stored on this device. This cannot be undone.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Clear', style: TextStyle(color: KoruColors.clay)),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  await ref.read(chatProvider.notifier).clear();
                  if (context.mounted) toast(context, 'Conversation cleared');
                }
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // Only over the empty state. Once a conversation is under way the
          // same line is a recording, and it would also sit on top of the very
          // cards it is telling the user they do not have.
          if (guideSpeech != null && st.messages.length <= 1)
            KoruGuideBanner(speech: guideSpeech, onTap: () {}),
          Expanded(
            child: st.messages.length <= 1
                ? _intro()
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    itemCount: st.messages.length,
                    itemBuilder: (_, i) => _ChatBubble(
                      m: st.messages[i],
                      index: i,
                      activity: st.activity,
                      currency: ref.watch(currencyProvider).valueOrNull?.symbol ??
                          'AED',
                      onEdit: (text) => _editMessage(context, i, text),
                      onApprove: () =>
                          ref.read(chatProvider.notifier).applyWrite(
                                st.messages[i].proposed!,
                              ),
                      onDiscard: () =>
                          ref.read(chatProvider.notifier).discardWrite(),
                    ),
                  ),
          ),
          // The engine's progress lives here rather than on the splash.
          //
          // It is the same information in the same place, but here being slow
          // costs nothing: the user can read the conversation, start typing, or
          // close the app, whereas holding the start screen for it meant a slow
          // copy or a system dialog left them stuck with nothing to do.
          if (engineProgress != null || engineProblem != null)
            _EngineBanner(progress: engineProgress, problem: engineProblem),
          _composer(st.busy),
        ],
      ),
    );
  }

  /// The empty state. Previously an empty list, which is the least useful thing
  /// a chat screen can be.
  Widget _intro() {
    const suggestions = [
      'How am I doing?',
      'Who owes me money?',
      'What should I chase this week?',
      'What is coming up?',
      'What is 15% of 2000?',
      'Schedule a call with Bilal tomorrow at 3pm',
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      children: [
        Center(
          child: KoruMascot(
            size: 132,
            controller: _mascot,
            busy: ref.watch(chatProvider).busy,
            semanticLabel: 'Koru, your helper. Tap to say hello.',
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Ask me about your clients, your money and what is due.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: KoruColors.ink),
        ),
        const SizedBox(height: 6),
        const Text(
          'Those questions are answered here, on this phone. '
          'Faith, health, medicine and law go to a stronger model instead.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13.5, color: KoruColors.inkFaint, height: 1.45),
        ),
        const SizedBox(height: 22),
        const SectionLabel('Try'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: suggestions
              .map((s) => ActionChip(
                    label: Text(s),
                    backgroundColor: KoruColors.surface,
                    side: const BorderSide(color: KoruColors.line),
                    labelStyle: const TextStyle(color: KoruColors.inkSoft, fontSize: 13),
                    onPressed: () => _useSuggestion(s),
                  ))
              .toList(),
        ),
      ],
    );
  }

  Future<void> _editMessage(BuildContext context, int index, String current) async {
    final controller = TextEditingController(text: current);
    final edited = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: KoruColors.cream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
            18, 18, 18, 18 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Edit message',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            const Text('Asking again drops the reply below it.',
                style: TextStyle(color: KoruColors.inkFaint, fontSize: 12.5)),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              minLines: 1,
              maxLines: 5,
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.all(14),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
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

  Widget _composer(bool busy) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          12, 10, 12, 10 + MediaQuery.of(context).padding.bottom * 0.2),
      decoration: const BoxDecoration(
        color: KoruColors.cream,
        border: Border(top: BorderSide(color: KoruColors.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              focusNode: _focus,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: const InputDecoration(
                hintText: 'Ask anything...',
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 9),
          // While an answer is being written the same button stops it, rather
          // than sitting greyed out. A disabled button for fifteen seconds is
          // the app looking busy; a stop square is the app offering a way out.
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: busy ? KoruColors.clay : KoruColors.leaf,
              borderRadius: BorderRadius.circular(14),
            ),
            child: IconButton(
              icon: Icon(
                busy ? Icons.stop_rounded : Icons.arrow_upward_rounded,
                color: Colors.white,
                size: busy ? 26 : 22,
              ),
              onPressed: busy
                  ? () => ref.read(chatProvider.notifier).stop()
                  : _send,
              tooltip: busy ? 'Stop' : 'Send',
            ),
          ),
        ],
      ),
    );
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
  });

  final Msg m;
  final int index;
  final String? activity;
  final String currency;

  final void Function(String text) onEdit;
  final VoidCallback onApprove;
  final VoidCallback onDiscard;

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

    final body = Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 5, left: 2),
              child: Row(
                children: [
                  const KoruMark(size: 17),
                  const SizedBox(width: 7),
                  _EngineBadge(
                    engine: m.engine,
                    tokensPerSecond: m.tokensPerSecond,
                  ),
                  if (m.why != null) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        m.why!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11.5, color: KoruColors.inkFaint),
                      ),
                    ),
                  ],
                  // The time rides in the row the badge already occupies
                  // rather than taking a row of its own, so a long thread does
                  // not grow taller than it used to.
                  if (m.time != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      _clock(m.time!),
                      style: const TextStyle(
                          fontSize: 10.5, color: KoruColors.inkFaint),
                    ),
                  ],
                ],
              ),
            ),
          ],
          Container(
            constraints: const BoxConstraints(maxWidth: 330),
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
            decoration: BoxDecoration(
              color: isUser ? KoruColors.leaf : KoruColors.surface,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isUser ? 16 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 16),
              ),
              border: isUser ? null : Border.all(color: KoruColors.line),
            ),
            child: m.pending && m.text.isEmpty
                ? KoruThinkingDots(
                    activity: switch (widget.activity) {
                      'Reading your records' => KoruActivity.reading,
                      'Writing an answer' => KoruActivity.writing,
                      'Waking up' => KoruActivity.waking,
                      'Reading your list' => KoruActivity.readingList,
                      'Checking what is due' => KoruActivity.checking,
                      'Looking up your clients' => KoruActivity.looking,
                      'Checking your calendar' => KoruActivity.checking,
                      _ => KoruActivity.thinking,
                    },
                  )
                : Text(
                    m.text,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.45,
                      // Progress text arrives on a pending bubble, so it is
                      // muted until real tokens land. A pending message that
                      // has text is progress, never an answer.
                      color: isUser
                          ? Colors.white
                          : (m.pending ? KoruColors.inkFaint : KoruColors.ink),
                    ),
                  ),
          ),
          if (m.handoff != null && !_handoffDismissed)
            HandoffCard(
              plan: m.handoff!,
              onDismiss: () => setState(() => _handoffDismissed = true),
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
      child: body,
    );
  }
}
