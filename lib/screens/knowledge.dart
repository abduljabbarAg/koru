import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../guide.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

/// What the user is learning, with progress.
///
/// The `knowledge` table has existed since the first commit and has never been
/// read or written by anything. This is the screen that gives it a purpose.
class KnowledgeScreen extends ConsumerWidget {
  const KnowledgeScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, {KnowledgeTopic? existing}) async {
    final topic = TextEditingController(text: existing?.topic ?? '');
    final note = TextEditingController(text: existing?.note ?? '');
    var progress = existing?.progress ?? 0.0;

    final saved = await showKoruSheet<bool>(
      context,
      title: existing == null ? 'New topic' : 'Edit topic',
      subtitle: 'A course, a skill, a certification. Whatever you are working through.',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(controller: topic, decoration: const InputDecoration(labelText: 'Topic')),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Note', hintText: 'Where you got to'),
            ),
            const SizedBox(height: 18),
            Text('Progress: ${(progress * 100).round()}%',
                style: const TextStyle(fontSize: 13, color: KoruColors.inkSoft)),
            Slider(
              value: progress,
              onChanged: (v) => setSheet(() => progress = v),
              activeColor: KoruColors.leaf,
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(existing == null ? 'Add topic' : 'Save changes'),
            ),
          ],
        ),
      ),
    );

    if (saved != true || topic.text.trim().isEmpty) return;
    final store = await ref.read(storeProvider.future);
    final record = KnowledgeTopic(
      id: existing?.id,
      topic: topic.text.trim(),
      progress: progress,
      note: note.text.trim().isEmpty ? null : note.text.trim(),
      updated: existing?.updated ?? DateTime.now().toIso8601String(),
    );
    if (existing == null) {
      await store.addTopic(record);
    } else {
      await store.updateTopic(record);
    }
    ref.invalidate(topicsProvider);
    if (context.mounted) toast(context, existing == null ? 'Topic added' : 'Topic updated');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topics = ref.watch(topicsProvider);
    final guide = ref.watch(guideFactsProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Learn')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref),
        backgroundColor: KoruColors.leaf,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Topic'),
      ),
      body: topics.when(
        loading: () => const Center(child: CircularProgressIndicator(color: KoruColors.leaf)),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) {
          final done = list.where((t) => t.progress >= 1).length;
          final average = list.isEmpty
              ? 0.0
              : list.fold<double>(0, (a, t) => a + t.progress.clamp(0.0, 1.0)) / list.length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
            children: [
              KoruGuideBanner(
                speech: guide == null ? null : Guide.forLearn(guide),
                onTap: () {},
              ),
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      label: 'TOPICS',
                      value: '${list.length}',
                      sub: 'tracked',
                      tint: KoruColors.leaf,
                      tintBg: KoruColors.leafSoft,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StatTile(
                      label: 'AVERAGE',
                      value: '${(average * 100).round()}%',
                      sub: 'across all topics',
                      tint: KoruColors.gold,
                      tintBg: KoruColors.goldSoft,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StatTile(
                      label: 'DONE',
                      value: '$done',
                      sub: 'finished',
                      tint: KoruColors.clay,
                      tintBg: KoruColors.claySoft,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              if (list.isEmpty)
                EmptyHint(
                  icon: Icons.school_outlined,
                  title: 'Nothing on the list',
                  body: 'Track a course or a skill so progress is visible instead of remembered.',
                  action: FilledButton(
                    onPressed: () => _edit(context, ref),
                    child: const Text('Add a topic'),
                  ),
                ),
              ...list.map((t) => _tile(context, ref, t)),
            ],
          );
        },
      ),
    );
  }

  Widget _tile(BuildContext context, WidgetRef ref, KnowledgeTopic t) {
    final percent = t.percent;
    final tint = percent >= 100
        ? KoruColors.leaf
        : percent >= 50
            ? KoruColors.gold
            : KoruColors.clay;
    final tintBg = percent >= 100
        ? KoruColors.leafSoft
        : percent >= 50
            ? KoruColors.goldSoft
            : KoruColors.claySoft;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
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
                child: Text(t.topic,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              ),
              KoruPill(label: '$percent%', color: tint, background: tintBg),
              IconButton(
                tooltip: 'Edit ${t.topic}',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_outlined, size: 17, color: KoruColors.inkFaint),
                onPressed: () => _edit(context, ref, existing: t),
              ),
              IconButton(
                tooltip: 'Delete ${t.topic}',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline_rounded, size: 17, color: KoruColors.inkFaint),
                onPressed: () async {
                  final store = await ref.read(storeProvider.future);
                  await store.deleteTopic(t.id!);
                  ref.invalidate(topicsProvider);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(KoruRadius.pill),
            child: LinearProgressIndicator(
              value: t.progress.clamp(0.0, 1.0),
              minHeight: 7,
              backgroundColor: KoruColors.line,
              valueColor: AlwaysStoppedAnimation(tint),
            ),
          ),
          if (t.note != null) ...[
            const SizedBox(height: 9),
            Text(t.note!,
                style: const TextStyle(fontSize: 12.5, color: KoruColors.inkSoft, height: 1.4)),
          ],
        ],
      ),
    );
  }
}
