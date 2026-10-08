import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cloud.dart';
import '../cloud_providers.dart';
import '../engine.dart';
import '../guide.dart';
import '../local/local_model_client.dart';
import '../secrets.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'drafts.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packet = ref.watch(packetProvider);
    final guide = ref.watch(guideFactsProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
        children: [
          KoruGuideBanner(
            speech: guide == null ? null : Guide.forSettings(guide),
            onTap: () {},
          ),
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
                        Expanded(
                          child: Text(p.nickname,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (p.lifeStage.isNotEmpty) _line('Stage', p.lifeStage),
                    if (p.business.isNotEmpty) _line('Work', p.business),
                    if (p.fitness.isNotEmpty) _line('Fitness', p.fitness),
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
          const SizedBox(height: 22),
          const SectionLabel('Engine'),
          const _EnginePicker(),
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
                      packet.maybeWhen(data: (p) => p.renderForCloud(), orElse: () => '...'),
                      style: const TextStyle(
                          fontSize: 12.5, color: KoruColors.ink, height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Pseudonymous, not anonymous. It carries general context and '
                    'never your nickname, your name or your records.',
                    style: TextStyle(fontSize: 12.5, color: KoruColors.inkFaint, height: 1.45),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          const _LocalModelCard(),
          const SizedBox(height: 22),
          const SectionLabel('Cloud model'),
          const _CloudCard(),
          const SizedBox(height: 8),
          const Text(
            'Any provider works. Pick one, paste the key, test it. Only questions '
            'about faith, health, medicine or law are ever sent.',
            style: TextStyle(fontSize: 12.5, color: KoruColors.inkFaint, height: 1.45),
          ),
          const SizedBox(height: 22),
          const SectionLabel('Routing'),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
          const SectionLabel('Shortcuts'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.drafts_outlined, color: KoruColors.leaf),
                  title: const Text('Drafts'),
                  subtitle: const Text('What Koru wrote and is holding for you'),
                  trailing: const Icon(Icons.chevron_right_rounded, color: KoruColors.inkFaint),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const DraftsScreen()),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const SectionLabel('Data'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined, color: KoruColors.clay),
                  title: const Text('Clear conversation'),
                  subtitle: const Text('Keeps your profile, clients and logs'),
                  onTap: () async {
                    await ref.read(chatProvider.notifier).clear();
                    if (context.mounted) toast(context, 'Conversation cleared');
                  },
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _deleteEverything(context, ref),
                      icon: const Icon(Icons.delete_outline_rounded, color: KoruColors.clay),
                      label: const Text('Delete all local data',
                          style: TextStyle(color: KoruColors.clay)),
                    ),
                  ),
                ),
              ],
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
    final height = TextEditingController(text: (m['height'] ?? ''));

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
          const SizedBox(height: 12),
          TextField(
            controller: height,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Height', suffixText: 'm'),
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
    final h = double.tryParse(height.text.trim());
    if (h != null && h > 0) await store.putNumber('height', h);
    await store.refreshFitnessSummary();
    ref.invalidate(packetProvider);
    if (context.mounted) toast(context, 'Context updated');
  }

  /// Clears the key too. The old version left it in memory, so "delete all local
  /// data" did not delete all of the local data.
  Future<void> _deleteEverything(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete everything?'),
        content: const Text(
            'Your profile, clients, logs, topics, drafts, conversation and your '
            'cloud key will all be removed from this device. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: KoruColors.clay)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final store = await ref.read(storeProvider.future);
    await store.wipe();
    final secrets = ref.read(secretsProvider);
    for (final provider in kCloudProviders) {
      await secrets.clearKey(provider.id);
    }

    await ref.read(chatProvider.notifier).clear();
    ref.invalidate(clientsProvider);
    ref.invalidate(fitnessProvider);
    ref.invalidate(topicsProvider);
    ref.invalidate(draftsProvider);
    ref.invalidate(packetProvider);
    ref.invalidate(cloudKeyProvider);
    ref.invalidate(heightProvider);
    ref.read(onboardedProvider.notifier).state = false;

    if (context.mounted) toast(context, 'All data deleted');
  }
}

/// Provider, model, key, and a test that costs nothing.
///
/// The old version had one hardcoded endpoint, one hardcoded model, and a field
/// that reported success even when the keystore refused the write. Someone with
/// a key for any other provider had no way to make it work.
class _CloudCard extends ConsumerStatefulWidget {
  const _CloudCard();

  @override
  ConsumerState<_CloudCard> createState() => _CloudCardState();
}

class _CloudCardState extends ConsumerState<_CloudCard> {
  final _controller = TextEditingController();
  final _modelController = TextEditingController();
  bool _revealed = false;
  String? _status;
  bool _busy = false;
  String _providerId = 'openrouter';

  @override
  void initState() {
    super.initState();
    ref.read(cloudSelectionProvider).whenData((selection) {
      if (!mounted) return;
      setState(() {
        _providerId = selection.provider.id;
        _modelController.text = selection.model;
      });
    });
    _loadKey(_providerId);
  }

  @override
  void dispose() {
    _controller.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _loadKey(String providerId) async {
    final value = await ref.read(cloudKeyProvider(providerId).future);
    if (!mounted) return;
    setState(() => _controller.text = value);
  }

  Future<void> _pickProvider(String id) async {
    setState(() {
      _providerId = id;
      _status = null;
      final provider = providerById(id);
      _modelController.text = provider.models.isNotEmpty ? provider.models.first : '';
    });
    await _loadKey(id);
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final store = await ref.read(storeProvider.future);
    final provider = providerById(_providerId);
    await store.put('cloud_provider', provider.id);
    await store.put('cloud_model', _modelController.text.trim());
    final ok = await saveCloudKey(ref, provider.id, _controller.text);
    ref.invalidate(cloudSelectionProvider);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      toast(context, 'Saved for ${provider.label}');
    } else {
      // Told the truth. This used to say "saved" no matter what happened, which
      // is exactly how a key that never persisted became "nothing responds".
      toast(context, 'Could not write to the keystore. Not saved.');
    }
  }

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    final provider = providerById(_providerId);
    final key = _controller.text.trim();
    // Save first so a successful test also persists the configuration.
    final store = await ref.read(storeProvider.future);
    await store.put('cloud_provider', provider.id);
    await store.put('cloud_model', _modelController.text.trim());
    final saved = await saveCloudKey(ref, provider.id, key);
    final result = await ref.read(cloudModelProvider).probe(
          provider: provider,
          model: _modelController.text.trim(),
          apiKey: key,
        );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = switch (result) {
        CloudReply() => saved
            ? 'Connected to ${provider.label}, and the key is saved.'
            : 'Connected, but the key could not be written to the keystore.',
        CloudUnavailable() => 'Add a key first.',
        CloudFailure(:final reason) => reason,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = providerById(_providerId);
    final hasKey = ref.watch(cloudKeyProvider(_providerId)).valueOrNull?.isNotEmpty ?? false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _providerId,
              decoration: const InputDecoration(labelText: 'Provider'),
              isExpanded: true,
              items: kCloudProviders
                  .map((p) => DropdownMenuItem(value: p.id, child: Text(p.label)))
                  .toList(),
              onChanged: (v) {
                if (v != null) _pickProvider(v);
              },
            ),
            if (provider.note != null) ...[
              const SizedBox(height: 8),
              Text(
                provider.note!,
                style: const TextStyle(fontSize: 12.5, color: KoruColors.inkFaint, height: 1.4),
              ),
            ],
            const SizedBox(height: 14),
            if (provider.models.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: provider.models.contains(_modelController.text)
                    ? _modelController.text
                    : provider.models.first,
                decoration: const InputDecoration(labelText: 'Model'),
                isExpanded: true,
                items: provider.models
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _modelController.text = v);
                },
              )
            else
              TextField(
                controller: _modelController,
                decoration: const InputDecoration(labelText: 'Model id'),
              ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              obscureText: !_revealed,
              decoration: InputDecoration(
                labelText: provider.keyLabel,
                hintText: provider.keyHint,
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasKey)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(Icons.lock_rounded, size: 16, color: KoruColors.leaf),
                      ),
                    IconButton(
                      tooltip: _revealed ? 'Hide key' : 'Show key',
                      icon: Icon(
                        _revealed ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        size: 19,
                        color: KoruColors.inkFaint,
                      ),
                      onPressed: () => setState(() => _revealed = !_revealed),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Encrypted with the Android keystore, and kept per provider.',
              style: TextStyle(fontSize: 12, color: KoruColors.inkFaint),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: _busy ? null : _test,
                  child: Text(_busy ? 'Testing...' : 'Test connection'),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: _busy ? null : _save,
                  child: const Text('Save'),
                ),
                if (hasKey)
                  TextButton(
                    onPressed: () async {
                      await ref.read(secretsProvider).clearKey(_providerId);
                      ref.invalidate(cloudKeyProvider(_providerId));
                      _controller.clear();
                      if (context.mounted) toast(context, 'Key removed');
                    },
                    child: const Text('Remove'),
                  ),
              ],
            ),
            if (_status != null) ...[
              const SizedBox(height: 12),
              Text(
                _status!,
                style: const TextStyle(fontSize: 12.5, color: KoruColors.inkSoft, height: 1.4),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Route extends StatelessWidget {
  const _Route(this.topic, this.where);

  final String topic;
  final String where;

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

/// Picks which engine answers. Everything else on this screen depends on it.
class _EnginePicker extends ConsumerWidget {
  const _EnginePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.watch(engineProvider).valueOrNull ?? KoruEngine.builtIn;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final option in KoruEngine.values) ...[
              RadioListTile<KoruEngine>(
                value: option,
                groupValue: engine,
                onChanged: (value) async {
                  if (value == null) return;
                  final store = await ref.read(storeProvider.future);
                  await store.put('engine', value.name);
                  ref.invalidate(engineProvider);
                },
                contentPadding: EdgeInsets.zero,
                activeColor: KoruColors.leaf,
                title: Text(
                  option.label,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                subtitle: Text(
                  option.blurb,
                  style: const TextStyle(fontSize: 12.5, color: KoruColors.inkFaint, height: 1.4),
                ),
              ),
              if (option != KoruEngine.values.last) const Divider(height: 4),
            ],
            const SizedBox(height: 8),
            const Text(
              'Anything about a crisis, a diagnosis or a court date goes to a '
              'person instead, whichever engine is selected.',
              style: TextStyle(fontSize: 12.5, color: KoruColors.inkFaint, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

/// Points Koru at a model server running on this phone, and says plainly what
/// it is and is not good for.
class _LocalModelCard extends ConsumerStatefulWidget {
  const _LocalModelCard();

  @override
  ConsumerState<_LocalModelCard> createState() => _LocalModelCardState();
}

class _LocalModelCardState extends ConsumerState<_LocalModelCard> {
  late final TextEditingController _endpoint;
  late final TextEditingController _modelId;
  String? _status;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _endpoint = TextEditingController();
    _modelId = TextEditingController();
    ref.read(localModelProvider).whenData((config) {
      _endpoint.text = config.endpoint;
      _modelId.text = config.modelId;
    });
  }

  @override
  void dispose() {
    _endpoint.dispose();
    _modelId.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _status = null;
    });
    final client = ref.read(localModelClientProvider);
    final result = await client.check(_endpoint.text);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _status = switch (result) {
        LocalReply(:final text) => 'Found it: $text',
        LocalUnavailable(:final detail) => detail,
        LocalFailed(:final reason) => reason,
      };
    });
  }

  Future<void> _save() async {
    final store = await ref.read(storeProvider.future);
    final config = LocalModelConfig(
      endpoint: ref.read(localModelClientProvider).normaliseEndpoint(_endpoint.text),
      modelId: _modelId.text.trim().isEmpty ? 'local' : _modelId.text.trim(),
    );
    await store.put('local_model', jsonEncode(config.toMap()));
    ref.invalidate(localModelProvider);
    if (mounted) toast(context, 'Local model saved');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('On-device model'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _endpoint,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Server address',
                    hintText: 'http://127.0.0.1:8099',
                    helperText: 'Anything that speaks the OpenAI chat API',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _modelId,
                  decoration: const InputDecoration(
                    labelText: 'Model id',
                    hintText: 'qwen2.5-0.5b-instruct',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                      onPressed: _checking ? null : _check,
                      child: Text(_checking ? 'Checking...' : 'Test connection'),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                      onPressed: _save,
                      child: const Text('Save'),
                    ),
                  ],
                ),
                if (_status != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _status!,
                    style: const TextStyle(fontSize: 12.5, color: KoruColors.inkSoft, height: 1.4),
                  ),
                ],
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: KoruColors.goldSoft,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: KoruColors.gold),
                  ),
                  child: const Text(
                    'Measured on this phone: about 2.6 tokens a second once a '
                    'short answer starts, so expect roughly ten to twenty '
                    'seconds. Koru is built for short answers. It is not good '
                    'with health numbers and must never be used instead of a '
                    'person for anything urgent.',
                    style: TextStyle(fontSize: 12.5, color: KoruColors.ink, height: 1.45),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
