import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine.dart';
import '../mascot/mascot.dart';
import '../proposed_write.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
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
          Expanded(
            child: st.messages.length <= 1
                ? _intro()
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    itemCount: st.messages.length,
                    itemBuilder: (_, i) => _bubble(context, st.messages[i]),
                  ),
          ),
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
      'What is my BMI?',
      'Who should I chase for payment?',
      'What are my goals?',
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
          'Ask me about your work or your training.',
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

  Widget _bubble(BuildContext context, Msg m) {
    final isUser = m.role == MsgRole.user;
    final dismissed = ValueNotifier<bool>(false);

    return ValueListenableBuilder<bool>(
      valueListenable: dismissed,
      builder: (context, isDismissed, _) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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
                            style: const TextStyle(fontSize: 11.5, color: KoruColors.inkFaint),
                          ),
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
                    ? const Text('...',
                        style: TextStyle(color: KoruColors.inkFaint, fontSize: 15))
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
              if (m.handoff != null && !isDismissed)
                HandoffCard(plan: m.handoff!, onDismiss: () => dismissed.value = true),
              if (m.proposed != null)
                WriteCard(
                  write: m.proposed!,
                  onApprove: () => ref.read(chatProvider.notifier).applyWrite(m.proposed!),
                  onDiscard: () => ref.read(chatProvider.notifier).discardWrite(),
                ),
            ],
          ),
        );
      },
    );
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
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: busy ? KoruColors.line : KoruColors.leaf,
              borderRadius: BorderRadius.circular(14),
            ),
            child: IconButton(
              icon: Icon(
                busy ? Icons.hourglass_top_rounded : Icons.arrow_upward_rounded,
                color: busy ? KoruColors.inkFaint : Colors.white,
              ),
              onPressed: busy ? null : _send,
              tooltip: busy ? 'Thinking' : 'Send',
            ),
          ),
        ],
      ),
    );
  }
}
