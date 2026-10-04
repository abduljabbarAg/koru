import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packet = ref.watch(packetProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
        children: [
          const SectionLabel('Your context'),
          packet.when(
            loading: () => const LinearProgressIndicator(color: KoruColors.leaf),
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
                        Text(p.nickname,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (p.lifeStage.isNotEmpty) _line('Stage', p.lifeStage),
                    if (p.business.isNotEmpty) _line('Work', p.business),
                    if (p.fitness.isNotEmpty) _line('Fitness', p.fitness),
                    if (p.goals.isNotEmpty) _line('Goals', p.goals),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          const SectionLabel('What leaves this phone'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'When a cloud model is used, only this is sent:',
                    style: TextStyle(fontSize: 13.5, color: KoruColors.inkSoft),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: KoruColors.cream,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: KoruColors.line),
                    ),
                    child: Text(
                      packet.maybeWhen(
                        data: (p) => p.render(),
                        orElse: () => '...',
                      ),
                      style: const TextStyle(
                          fontSize: 12.5, color: KoruColors.ink, height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Pseudonymous, not anonymous. It carries general context, '
                    'never your name or your records.',
                    style: TextStyle(fontSize: 12.5, color: KoruColors.inkFaint, height: 1.45),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          const SectionLabel('Cloud model'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('OpenRouter API key',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 4),
                  const Text('Stored on this device. Needed for frontier answers.',
                      style: TextStyle(fontSize: 12.5, color: KoruColors.inkFaint)),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: ref.watch(cloudKeyProvider),
                    obscureText: true,
                    decoration: const InputDecoration(hintText: 'sk-or-v1-...'),
                    onChanged: (v) => ref.read(cloudKeyProvider.notifier).state = v,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          const SectionLabel('Routing'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  _Route('Faith, mental health, medical, legal', 'Cloud model'),
                  SizedBox(height: 10),
                  _Route('Everything else', 'On device'),
                  SizedBox(height: 10),
                  _Route('Crisis, diagnosis, legal ruling', 'Hand to a person'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          const SectionLabel('Data'),
          OutlinedButton.icon(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete everything?'),
                  content: const Text(
                      'Your profile, clients and fitness logs will be removed from this device. '
                      'This cannot be undone.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete', style: TextStyle(color: KoruColors.clay)),
                    ),
                  ],
                ),
              );
              if (ok == true) {
                final store = await ref.read(storeProvider.future);
                await store.wipe();
                ref.invalidate(clientsProvider);
                ref.invalidate(fitnessProvider);
                ref.invalidate(packetProvider);
                if (context.mounted) toast(context, 'All data deleted');
              }
            },
            icon: const Icon(Icons.delete_outline_rounded, color: KoruColors.clay),
            label: const Text('Delete all local data', style: TextStyle(color: KoruColors.clay)),
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
                style: const TextStyle(
                    fontSize: 12.5, color: KoruColors.inkFaint, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 13.5, color: KoruColors.ink, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

class _Route extends StatelessWidget {
  final String topic;
  final String where;
  const _Route(this.topic, this.where);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(topic,
              style: const TextStyle(fontSize: 13.5, color: KoruColors.ink)),
        ),
        Text(where,
            style: const TextStyle(
                fontSize: 12.5, color: KoruColors.leaf, fontWeight: FontWeight.w700)),
      ],
    );
  }
}