import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../mascot/mascot.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

/// Drafts Koru prepared and is waiting for you to approve.
///
/// Onboarding has said "drafts, never sends" since the first release. There was
/// no table behind it and no code path that produced one, so the promise was
/// empty. This screen plus [ProfileStore.addDraft] is the implementation.
///
/// Approving a draft never sends anything. The app has no messaging permission
/// and no intent to add one: the point is that you read it and then send it
/// yourself, from wherever you already talk to people.
class DraftsScreen extends ConsumerWidget {
  const DraftsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drafts = ref.watch(draftsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Drafts')),
      body: drafts.when(
        loading: () => const Center(child: CircularProgressIndicator(color: KoruColors.leaf)),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) {
          if (list.isEmpty) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
              children: [
                Center(
                  child: KoruMascot(
                    size: 118,
                    onTap: () => toast(context, 'Nothing to approve right now'),
                    semanticLabel: 'Koru. Tap to hear from him.',
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Nothing waiting on you',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: KoruColors.ink),
                ),
                const SizedBox(height: 8),
                const Text(
                  'When Koru writes something for you, it waits here for your '
                  'approval. He never sends it himself.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, color: KoruColors.inkFaint, height: 1.45),
                ),
              ],
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
            children: [
              const SectionLabel('Waiting on you'),
              ...list.map((d) => _card(context, ref, d)),
            ],
          );
        },
      ),
    );
  }

  Widget _card(BuildContext context, WidgetRef ref, Draft d) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KoruColors.surface,
        borderRadius: BorderRadius.circular(KoruRadius.card),
        border: Border.all(color: KoruColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(d.title,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
              ),
              KoruPill(
                label: d.channel.toUpperCase(),
                color: KoruColors.leaf,
                background: KoruColors.leafSoft,
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            d.body,
            style: const TextStyle(fontSize: 14, color: KoruColors.inkSoft, height: 1.5),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 42),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                onPressed: () => _resolve(context, ref, d, DraftStatus.approved),
                icon: const Icon(Icons.check_rounded, size: 17),
                label: const Text('Approve'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 42),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                onPressed: () => _resolve(context, ref, d, DraftStatus.discarded),
                icon: const Icon(Icons.close_rounded, size: 17),
                label: const Text('Discard'),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Copy draft',
                icon: const Icon(Icons.copy_rounded, size: 18, color: KoruColors.inkFaint),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: d.body));
                  if (context.mounted) toast(context, 'Copied to clipboard');
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _resolve(
      BuildContext context, WidgetRef ref, Draft d, DraftStatus status) async {
    final store = await ref.read(storeProvider.future);
    await store.setDraftStatus(d.id!, status);
    ref.invalidate(draftsProvider);
    if (context.mounted) {
      toast(context, status == DraftStatus.approved ? 'Approved' : 'Discarded');
    }
  }
}
