import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final q = _input.text;
    _input.clear();
    ref.read(chatProvider.notifier).ask(q);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(chatProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            KoruMark(size: 26),
            SizedBox(width: 10),
            Text('Koru'),
          ],
        ),
        actions: [
          if (st.busy)
            const Padding(
              padding: EdgeInsets.only(right: 18),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: KoruColors.leaf),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              itemCount: st.messages.length,
              itemBuilder: (_, i) => _bubble(st.messages[i]),
            ),
          ),
          _composer(),
        ],
      ),
    );
  }

  Widget _bubble(Msg m) {
    final isUser = m.role == MsgRole.user;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isUser)
            Padding(
              padding: const EdgeInsets.only(bottom: 5, left: 2),
              child: Row(
                children: [
                  const KoruMark(size: 17),
                  const SizedBox(width: 7),
                  Text(m.why ?? '',
                      style: const TextStyle(fontSize: 11.5, color: KoruColors.inkFaint)),
                ],
              ),
            ),
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
            child: m.pending
                ? const Text('...',
                    style: TextStyle(color: KoruColors.inkFaint, fontSize: 15))
                : Text(
                    m.text,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.45,
                      color: isUser ? Colors.white : KoruColors.ink,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _composer() {
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
              color: KoruColors.leaf,
              borderRadius: BorderRadius.circular(14),
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white),
              onPressed: _send,
            ),
          ),
        ],
      ),
    );
  }
}