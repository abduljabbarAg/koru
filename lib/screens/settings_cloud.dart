import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cloud.dart';
import '../cloud_providers.dart';
import '../secrets.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

/// Which company answers online: provider, model, key, and a test that costs
/// nothing.
///
/// Titled for the company rather than for the model, because the model is what
/// the company serves and the company is what you give the key to. It was called
/// "Cloud model", the same words the engine option in [EngineSettingsScreen]
/// used, so the index had two rows called "Cloud model" and no way to tell the
/// engine from the provider.
///
/// Its own page because it is the one setting that asks for a secret: twenty
/// providers, several models each, a key field, and a result that has to be
/// believed. Sitting between the routing table and the currency picker it read
/// like one more row rather than the door the data goes out of.
class CloudSettingsScreen extends StatelessWidget {
  const CloudSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cloud provider')),
      body: KoruPagePadding(
        bottom: KoruSpace.xxl,
        child: ListView(
          children: [
            const _CloudCard(),
            Text(
              'Any provider works. Pick one, paste the key, test it. Only '
              'questions about faith, health, medicine or law are ever sent, '
              'and only when the cloud model is the engine.',
              style: KoruType.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

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
  /// Filter over providers and models at once.
  final _cloudSearch = TextEditingController();
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
    _cloudSearch.dispose();
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

    return KoruCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search, because there are twenty providers and several models
          // each. Scrolling a dropdown to find a model is the wrong interface,
          // and someone looking for "glm" should not have to know whether that
          // is Z.ai, Zhipu or a custom endpoint.
          TextField(
            controller: _cloudSearch,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Find a provider or model',
              hintText: 'atria, glm, grok, claude, qwen...',
              prefixIcon: const Icon(Icons.search_rounded, size: KoruSize.icon),
              suffixIcon: _cloudSearch.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded,
                          size: KoruSize.iconSm),
                      onPressed: () => setState(() => _cloudSearch.clear()),
                    ),
            ),
          ),
          const SizedBox(height: KoruSpace.md),
          DropdownButtonFormField<String>(
            value: _providerId,
            decoration: const InputDecoration(labelText: 'Cloud provider'),
            isExpanded: true,
            items: (CloudSearch.providersMatching(_cloudSearch.text))
                .map((p) => DropdownMenuItem(value: p.id, child: Text(p.label)))
                .toList(),
            onChanged: (v) {
              if (v != null) _pickProvider(v);
            },
          ),
          if (provider.note != null) ...[
            const SizedBox(height: KoruSpace.sm),
            Text(provider.note!, style: KoruType.caption),
          ],
          const SizedBox(height: KoruSpace.mdl),
          // "Which model this company serves", named that way because "Model"
          // on its own is the word that used to mean both this and the engine.
          if (provider.models.isNotEmpty)
            DropdownButtonFormField<String>(
              value: provider.models.contains(_modelController.text)
                  ? _modelController.text
                  : provider.models.first,
              decoration: const InputDecoration(labelText: 'Model they serve'),
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
          const SizedBox(height: KoruSpace.mdl),
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
                    Padding(
                      padding: const EdgeInsets.only(right: KoruSpace.xs),
                      child: Icon(
                        Icons.lock_rounded,
                        size: KoruSize.iconSm,
                        color: KoruColors.leaf,
                      ),
                    ),
                  IconButton(
                    tooltip: _revealed ? 'Hide key' : 'Show key',
                    icon: Icon(
                      _revealed
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: KoruSize.icon,
                      color: KoruColors.inkFaint,
                    ),
                    onPressed: () => setState(() => _revealed = !_revealed),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: KoruSpace.xsm),
          Text(
            'Encrypted with the Android keystore, and kept per provider.',
            style: KoruType.caption,
          ),
          const SizedBox(height: KoruSpace.mdl),
          Row(
            children: [
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, KoruSize.buttonInCard),
                ),
                onPressed: _busy ? null : _test,
                child: Text(_busy ? 'Testing...' : 'Test connection'),
              ),
              const SizedBox(width: KoruSpace.md),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, KoruSize.buttonInCard),
                ),
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
            const SizedBox(height: KoruSpace.md),
            Text(_status!, style: KoruType.bodyCompactStrong),
          ],
        ],
      ),
    );
  }
}
