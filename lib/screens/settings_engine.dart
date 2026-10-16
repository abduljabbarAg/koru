import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine.dart';
import '../engine_switch.dart';
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
                // Through the shared writer, the same one the chat's badge
                // uses. Two copies of this write is how Settings and the chat
                // end up showing different engines on the same install.
                onChanged: (value) {
                  if (value != null) selectEngine(ref, value);
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
/// It used to be a permanent condition: the APK shipped no engine and no model,
/// so choosing the on-device engine found nothing to start, fell back to the
/// built-in assistant and answered in a few milliseconds, which reads exactly
/// like a model being fast. Bundled builds no longer hit this, and a build where
/// the engine could not be fetched still does — so it is stated when it is true
/// rather than left in as a warning nobody can act on.
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
  String? _message;
  bool _ready = false;

  /// Picks a different local model.
  ///
  /// The bundled 0.5B is not the best thing this phone can run, but it is the
  /// fastest, and the choice depends on what you are asking: a sharper model
  /// three times slower is a good trade for a hard question and a bad one for
  /// everything. So both are offered and neither is removed.
  ///
  /// Goes through the shared writer, so picking a model here and picking one in
  /// the chat's switcher are the same act rather than two writes that could
  /// disagree.
  Future<void> _choose(LocalModelFile model) async {
    await selectLocalModel(ref, model);
    if (!mounted) return;
    setState(() {
      _message = isBundledModel(model)
          ? 'Using the bundled model. It is the fast one.'
          : 'Switched. It will start on ${model.label} next time.';
    });
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
              ? 'Only the bundled model is here. Use "Add a model" to bring '
                  'your own .gguf onto this phone.'
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

  /// Starts the bundled engine through the same path the chat's switcher uses.
  ///
  /// It used to run its own copy of the start, which meant writing the model id
  /// and size of a model this build no longer ships and starting on a different
  /// address than the one the chat would have used. One call now, so the two
  /// screens cannot disagree about whether the engine is up.
  Future<void> _start() async {
    setState(() {
      _starting = true;
      _message = null;
    });

    final ok = await ref.read(chatProvider.notifier).ensureEngineRunning();
    if (!mounted) return;
    setState(() {
      _starting = false;
      _ready = ok;
      _message = ok
          ? 'Model running on this phone. It is now the active engine.'
          : ref.read(chatProvider).engineProblem ?? 'The model did not start.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(bundledEngineStatusProvider).valueOrNull;
    final available = status?.available;
    // Read from the chat state rather than a field of this panel: the engine
    // can also be started from the chat, and two progress bars reading two
    // copies of the same number is how one of them ends up stuck.
    final progress = ref.watch(chatProvider).engineProgress;

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
