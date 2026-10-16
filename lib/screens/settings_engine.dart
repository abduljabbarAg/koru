import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine.dart';
import '../local/bundled_engine.dart';
import '../local/local_model_client.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

/// Which engine answers, and the model this phone can run.
///
/// One page for both on purpose: [EngineAbsentNotice] ends by telling the user
/// to add a .gguf "below", so separating the picker from the model panel would
/// leave a sentence pointing at a screen that is not there.
class EngineSettingsScreen extends ConsumerWidget {
  const EngineSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Engine')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
        children: const [
          _EnginePicker(),
          _EngineAbsentNotice(),
          SizedBox(height: 22),
          _LocalModelCard(),
        ],
      ),
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
                  style: TextStyle(fontSize: 12.5, color: KoruColors.inkFaint, height: 1.4),
                ),
              ),
              if (option != KoruEngine.values.last) const Divider(height: 4),
            ],
            const SizedBox(height: 8),
            Text(
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

/// Says so when the on-device engine cannot run.
///
/// Since 1.0.0 the APK ships no engine and no model. Choosing the on-device
/// engine then found nothing to start, fell back to the built-in assistant and
/// answered in a few milliseconds, which reads exactly like a model being fast.
class _EngineAbsentNotice extends ConsumerWidget {
  const _EngineAbsentNotice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final present = ref.watch(localEnginePresentProvider).valueOrNull;
    if (present != false) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        'No model on this phone, so the on-device option will answer from your '
        'own records instead. That is quick, but it is not a model. Add a .gguf '
        'below to run a real one.',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
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
                const _BundledModelPanel(),
                const SizedBox(height: 6),
                const Divider(height: 24),
                Text(
                  'Or point Koru at a server you already run',
                  style: TextStyle(fontSize: 12.5, color: KoruColors.inkFaint),
                ),
                const SizedBox(height: 14),
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
                    style: TextStyle(fontSize: 12.5, color: KoruColors.inkSoft, height: 1.4),
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
                  child: Text(
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

/// Starts the engine that ships inside the APK.
///
/// This is the path a normal user should never have to think about: the binary
/// and the model are already in the app, so "on-device model" works with no
/// setup. The first start copies several hundred megabytes out of the APK, which
/// takes a while, so the progress is shown rather than a spinner.
class _BundledModelPanel extends ConsumerStatefulWidget {
  const _BundledModelPanel();

  @override
  ConsumerState<_BundledModelPanel> createState() => _BundledModelPanelState();
}

class _BundledModelPanelState extends ConsumerState<_BundledModelPanel> {
  bool _starting = false;
  int? _progress;
  String? _message;
  bool _ready = false;

  /// Picks a different local model and restarts the engine on it.
  ///
  /// The bundled 0.5B is not the best thing this phone can run, but it is the
  /// fastest, and the choice depends on what you are asking: a sharper model
  /// three times slower is a good trade for a hard question and a bad one for
  /// everything. So both are offered and neither is removed.
  Future<void> _choose(LocalModelFile model) async {
    final store = await ref.read(storeProvider.future);
    final isBundled = model.label.startsWith('Qwen2.5');
    await store.put('model_path', isBundled ? '' : model.path);
    if (mounted) {
      setState(() {
        _message = isBundled
            ? 'Using the bundled model. It is the fast one.'
            : 'Switched. It will start on ${model.label} next time.';
      });
    }
    // Invalidate so the engine restarts against the new file.
    ref.invalidate(availableModelsProvider);
    ref.invalidate(chosenModelProvider);
    ref.invalidate(engineProvider);
  }

  /// Picks a .gguf out of the phone's own storage and brings it in.
  Future<void> _importModel() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: false,
    );
    final path = picked?.files.single.path;
    if (path == null) return;
    final problem = await ref.read(bundledEngineProvider).importModel(path);
    ref.invalidate(availableModelsProvider);
    if (!mounted) return;
    setState(() {
      _message = problem ?? 'Model added. Pick it below to use it.';
    });
  }

  Widget _modelPicker(List<LocalModelFile> models, String? chosen) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Model',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ),
            TextButton.icon(
              onPressed: _importModel,
              icon: const Icon(Icons.upload_file_rounded, size: 16),
              label: const Text('Add a model'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          models.length <= 1
              ? 'Only the bundled model is here. To add another, put a .gguf '
                  'file in this app\'s models folder under Android/data.'
              : 'A bigger model is sharper and slower. Switch when you need it, '
                  'not for everything.',
          style: TextStyle(color: KoruColors.inkFaint, fontSize: 12),
        ),
        const SizedBox(height: 10),
        for (final m in models)
          RadioListTile<String>(
            value: m.path,
            groupValue: chosen ?? '',
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(m.label, style: const TextStyle(fontSize: 13.5)),
            onChanged: (_) => _choose(m),
          ),
      ],
    );
  }

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _progress = 0;
      _message = null;
    });

    final engine = ref.read(bundledEngineProvider);
    final client = ref.read(localModelClientProvider);
    final result = await engine.start(
      onProgress: (percent) {
        if (mounted) setState(() => _progress = percent);
      },
      isHealthy: () async {
        final check = await client.check('http://127.0.0.1:${BundledEngine.defaultPort}');
        return check is LocalReply;
      },
    );

    if (!mounted) return;
    if (result.started && result.endpoint != null) {
      final store = await ref.read(storeProvider.future);
      await store.put('engine', KoruEngine.onDevice.name);
      await store.put(
        'local_model',
        jsonEncode(LocalModelConfig(
          endpoint: result.endpoint!,
          modelId: 'qwen2.5-0.5b-instruct',
          label: 'Bundled',
          sizeBytes: 491400032,
        ).toMap()),
      );
      ref.invalidate(engineProvider);
      ref.invalidate(localModelProvider);
    }
    setState(() {
      _starting = false;
      _ready = result.started;
      _message = result.started
          ? 'Model running on this phone. It is now the active engine.'
          : result.reason;
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(bundledEngineStatusProvider).valueOrNull;
    final available = status?.available;
    final progress = _progress;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _ready ? KoruColors.leafSoft : KoruColors.cream,
        borderRadius: BorderRadius.circular(KoruRadius.field),
        border: Border.all(color: _ready ? KoruColors.leaf : KoruColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.memory_rounded, size: 19, color: KoruColors.leaf),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'Bundled model',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                ),
              ),
              if (available == false)
                KoruPill(
                  label: 'NOT IN THIS BUILD',
                  color: KoruColors.clay,
                  background: KoruColors.claySoft,
                )
              else if (_ready)
                KoruPill(
                  label: 'RUNNING',
                  color: KoruColors.leaf,
                  background: KoruColors.leafSoft,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'A 0.5B model already inside this app. The first start copies it out '
            'of the package, so expect it to take a minute.',
            style: TextStyle(fontSize: 12.5, color: KoruColors.inkFaint, height: 1.4),
          ),
          const SizedBox(height: 14),
          _modelPicker(
            ref.watch(availableModelsProvider).valueOrNull ?? const [],
            ref.watch(chosenModelProvider).valueOrNull,
          ),
          if (_starting) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(KoruRadius.pill),
              child: LinearProgressIndicator(
                value: (progress ?? 0) / 100,
                minHeight: 6,
                backgroundColor: KoruColors.line,
                valueColor: AlwaysStoppedAnimation(KoruColors.leaf),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Loading the model... ${progress ?? 0}%',
              style: TextStyle(fontSize: 12, color: KoruColors.inkFaint),
            ),
          ],
          if (_message != null) ...[
            const SizedBox(height: 10),
            Text(
              _message!,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: _ready ? KoruColors.leaf : KoruColors.clay,
              ),
            ),
          ],
          if (!_starting && !_ready) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
              onPressed: available == false ? null : _start,
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('Start the bundled model'),
            ),
          ],
          // When it is unavailable, say why. A bare "NOT IN THIS BUILD" is what
          // made this hard to diagnose: the binary was in the package.
          if (_message == null && status != null && !status.available) ...[
            const SizedBox(height: 10),
            Text(
              status.summary,
              style: TextStyle(fontSize: 12, color: KoruColors.clay, height: 1.4),
            ),
            if (status.path != null) ...[
              const SizedBox(height: 4),
              Text(
                'looked in ${status.path}',
                style: TextStyle(fontSize: 11, color: KoruColors.inkFaint),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
