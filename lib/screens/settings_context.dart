import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

/// What Koru knows about you, and the sheet that changes it.
///
/// Its own page rather than the first card of a list of ten. Onboarding told
/// the user they could change all of this in Settings, and this is the setting
/// somebody comes back to most: the stage and the goals move, the nickname
/// rarely, and the rest of Settings is about how the app behaves rather than
/// about who it is behaving for.
class ContextSettingsScreen extends ConsumerWidget {
  const ContextSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packet = ref.watch(packetProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Your context')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
        children: [
          packet.when(
            loading: () => LinearProgressIndicator(color: KoruColors.leaf),
            error: (e, _) => Text('$e'),
            data: (p) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const KoruMark(size: 34),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(p.nickname,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (p.lifeStage.isNotEmpty) _line('Stage', p.lifeStage),
                    if (p.business.isNotEmpty) _line('Work', p.business),
                    if (p.goals.isNotEmpty) _line('Goals', p.goals),
                    if (p.focus.isNotEmpty) _line('Focus', p.focus),
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
                      onPressed: () => _editContext(context, ref),
                      icon: const Icon(Icons.edit_outlined, size: 17),
                      label: const Text('Edit this context'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12.5, color: KoruColors.inkFaint, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(fontSize: 13.5, color: KoruColors.ink, height: 1.4)),
          ),
        ],
      ),
    );
  }

  /// Onboarding told the user they could change all of this here. Until now
  /// this screen only displayed it, so the sentence was a lie.
  Future<void> _editContext(BuildContext context, WidgetRef ref) async {
    final store = await ref.read(storeProvider.future);
    final m = await store.all();
    if (!context.mounted) return;

    final nick = TextEditingController(text: m['nickname'] ?? '');
    final stage = TextEditingController(text: m['stage'] ?? '');
    final business = TextEditingController(text: m['business'] ?? '');
    final goals = TextEditingController(text: m['goals'] ?? '');
    final focus = TextEditingController(text: m['help_focus'] ?? '');

    final saved = await showKoruSheet<bool>(
      context,
      title: 'Your context',
      subtitle: 'This is what Koru knows about you. It stays on this device.',
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: nick,
            decoration: const InputDecoration(
                labelText: 'Nickname', helperText: 'Never sent to a cloud model'),
          ),
          const SizedBox(height: 12),
          TextField(controller: stage, decoration: const InputDecoration(labelText: 'Stage')),
          const SizedBox(height: 12),
          TextField(
              controller: business, decoration: const InputDecoration(labelText: 'Work')),
          const SizedBox(height: 12),
          TextField(
            controller: goals,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Goals'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: focus,
            decoration: const InputDecoration(labelText: 'Help me most with'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved != true) return;
    await store.put('nickname', nick.text.trim());
    await store.put('stage', stage.text.trim());
    await store.put('business', business.text.trim());
    await store.put('goals', goals.text.trim());
    await store.put('help_focus', focus.text.trim());
    ref.invalidate(packetProvider);
    ref.invalidate(guideFactsProvider);
    if (context.mounted) toast(context, 'Context updated');
  }
}
