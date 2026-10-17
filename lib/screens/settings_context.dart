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
      body: KoruPagePadding(
        bottom: KoruSpace.xxl,
        child: ListView(
          children: [
            packet.when(
              // A named wait rather than a bare bar: the reader is on this page
              // precisely to change what the app knows about them, and a spinner
              // with no words is a worse thing to be staring at than "one
              // moment" is.
              loading: () => const KoruLoading(label: 'Reading what Koru knows'),
              // Not the exception. A failed read here is a database message
              // addressed to whoever is debugging it, and it is shown where the
              // one thing this page can offer is still offered.
              error: (e, _) => KoruErrorView(
                onRetry: () => ref.invalidate(packetProvider),
                what: 'read your context',
              ),
              data: (p) => KoruCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const KoruMark(size: KoruSize.badge),
                        const SizedBox(width: KoruSpace.md),
                        Expanded(
                          child: Text(
                            p.nickname,
                            style: KoruType.rowTitleLarge,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: KoruSpace.mdl),
                    if (p.lifeStage.isNotEmpty) _line('Stage', p.lifeStage),
                    if (p.business.isNotEmpty) _line('Work', p.business),
                    if (p.goals.isNotEmpty) _line('Goals', p.goals),
                    if (p.focus.isNotEmpty) _line('Focus', p.focus),
                    const SizedBox(height: KoruSpace.xsm),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize:
                            const Size.fromHeight(KoruSize.buttonInCard),
                      ),
                      onPressed: () => _editContext(context, ref),
                      icon: const Icon(Icons.edit_outlined,
                          size: KoruSize.iconSm),
                      label: const Text('Edit this context'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One row of the card: what the field is called, and what is in it.
  ///
  /// The label column is the same width for every row so the values line up
  /// under each other rather than stepping in and out with the label's length.
  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: KoruSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: KoruType.label),
          ),
          Expanded(child: Text(value, style: KoruType.bodyCompactStrong)),
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KoruFieldStack(
            children: [
              TextField(
                controller: nick,
                decoration: const InputDecoration(
                  labelText: 'Nickname',
                  helperText: 'Never sent to the online model',
                ),
              ),
              TextField(
                controller: stage,
                decoration: const InputDecoration(labelText: 'Stage'),
              ),
              TextField(
                controller: business,
                decoration: const InputDecoration(labelText: 'Work'),
              ),
              TextField(
                controller: goals,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Goals'),
              ),
              TextField(
                controller: focus,
                decoration: const InputDecoration(labelText: 'Help me most with'),
              ),
            ],
          ),
          const SizedBox(height: KoruSpace.xl),
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
