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
import 'engine_log.dart';

/// Which engine answers, and the model this phone can run.
///
/// Titled the same words as the switcher sheet opens with, because it is the
/// same question asked in the same place: "who answers". It used to be called
/// "Engine", which collided with the model underneath it — the page is about
/// both, and the engine is only the first half of it.
///
/// One page for both on purpose: [EngineAbsentNotice] ends by telling the user
/// to add a .gguf "below", so separating the picker from the model panel would
/// leave a sentence pointing at a screen that is not there.
class EngineSettingsScreen extends ConsumerWidget {
  const EngineSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Who answers')),
      body: KoruPagePadding(
        bottom: KoruSpace.xxl,
        child: ListView(
          children: const [
            _EnginePicker(),
            _EngineAbsentNotice(),
            SizedBox(height: KoruSpace.section),
            _LocalModelCard(),
            SizedBox(height: KoruSpace.section),
            _EngineLogLink(),
          ],
        ),
      ),
    );
  }
}

/// Picks which engine answers. Everything else on this screen depends on it.
///
/// The same [KoruSelectableTile] the switcher sheet uses, so a choice made here
/// and a choice made in the chat are visibly the same act. They were a radio
/// list and a stack of tiles respectively, which meant the two screens could not
/// be compared by eye and nobody could tell from the chat whether the page had
/// been changed.
class _EnginePicker extends ConsumerWidget {
  const _EnginePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.watch(engineProvider).valueOrNull ?? KoruEngine.builtIn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final option in KoruEngine.values)
          KoruSelectableTile(
            label: option.label,
            blurb: option.blurb,
            selected: engine == option,
            icon: switch (option) {
              KoruEngine.builtIn => Icons.storage_rounded,
              KoruEngine.onDevice => Icons.memory_rounded,
              KoruEngine.cloud => Icons.cloud_outlined,
            },
            // Through the shared writer, the same one the chat's switcher uses.
            // Two copies of this write is how Settings and the chat end up
            // showing different engines on the same install.
            onTap: () => selectEngine(ref, option),
          ),
        const SizedBox(height: KoruSpace.xs),
        // Said where the choice is made rather than buried in a privacy policy.
        Text(
          'Anything about a crisis, a diagnosis or a court date goes to a '
          'person instead, whichever engine is selected.',
          style: KoruType.bodySmall,
        ),
      ],
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
      padding: const EdgeInsets.only(bottom: KoruSpace.md),
      child: KoruNotice(
        title: 'No model on this phone',
        message: 'So the on-device option will answer from your own records '
            'instead. That is quick, but it is not a model. Add a .gguf below '
            'to run a real one.',
        icon: Icons.memory_rounded,
        tone: KoruTones.gold,
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
        const SectionLabel('Your own server'),
        KoruCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KoruFieldStack(
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
                  TextField(
                    controller: _modelId,
                    decoration: const InputDecoration(
                      labelText: 'Model id',
                      hintText: 'qwen2.5-0.5b-instruct',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: KoruSpace.lg),
              const _BundledModelPanel(),
              const SizedBox(height: KoruSpace.xs),
              const Divider(height: KoruSpace.xxl),
              Text(
                'Or point Koru at a server you already run',
                style: KoruType.caption,
              ),
              const SizedBox(height: KoruSpace.mdl),
              Row(
                children: [
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, KoruSize.buttonInCard),
                    ),
                    onPressed: _checking ? null : _check,
                    child: Text(_checking ? 'Checking...' : 'Test connection'),
                  ),
                  const SizedBox(width: KoruSpace.md),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, KoruSize.buttonInCard),
                    ),
                    onPressed: _save,
                    child: const Text('Save'),
                  ),
                ],
              ),
              if (_status != null) ...[
                const SizedBox(height: KoruSpace.md),
                Text(_status!, style: KoruType.bodyCompactStrong),
              ],
              const SizedBox(height: KoruSpace.mdl),
              KoruNotice(
                message: 'Measured on this phone: about 2.6 tokens a second '
                    'once a short answer starts, so expect roughly ten to '
                    'twenty seconds. Koru is built for short answers. It is not '
                    'good with health numbers and must never be used instead of '
                    'a person for anything urgent.',
                icon: Icons.speed_rounded,
                tone: KoruTones.gold,
                dense: true,
              ),
            ],
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Model on this phone', style: KoruType.label),
            ),
            TextButton.icon(
              onPressed: _importModel,
              icon: const Icon(Icons.upload_file_rounded,
                  size: KoruSize.iconSm),
              label: const Text('Add a model'),
            ),
          ],
        ),
        const SizedBox(height: KoruSpace.xs),
        Text(
          models.length <= 1
              ? 'Only the bundled model is here. Use "Add a model" to bring '
                  'your own .gguf onto this phone.'
              : 'A bigger model is sharper and slower. Switch when you need it, '
                  'not for everything.',
          style: KoruType.caption,
        ),
        const SizedBox(height: KoruSpace.sml),
        // The same tile the switcher sheet picks from, so a model chosen here and
        // a model chosen there look like the same choice and cannot disagree
        // about which one is the answer.
        for (final m in models)
          KoruSelectableTile(
            label: m.label,
            selected: isBundledModel(m) ? chosen == null : chosen == m.path,
            icon: Icons.memory_rounded,
            onTap: () => _choose(m),
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
      padding: const EdgeInsets.all(KoruSpace.mdl),
      decoration: BoxDecoration(
        color: _ready ? KoruColors.leafSoft : KoruColors.surface,
        borderRadius: BorderRadius.circular(KoruRadius.field),
        border: Border.fromBorderSide(
          _ready ? KoruBorders.selected() : KoruBorders.hairline(),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              KoruIconBadge(
                icon: Icons.memory_rounded,
                color: KoruColors.leaf,
                background: KoruColors.leafSoft,
              ),
              const SizedBox(width: KoruSpace.md),
              Expanded(
                child: Text('Bundled model', style: KoruType.rowTitleLarge),
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
          const SizedBox(height: KoruSpace.sm),
          Text(
            'A 0.5B model already inside this app. The first start copies it out '
            'of the package, so expect it to take a minute.',
            style: KoruType.caption,
          ),
          const SizedBox(height: KoruSpace.mdl),
          _modelPicker(
            ref.watch(availableModelsProvider).valueOrNull ?? const [],
            ref.watch(chosenModelProvider).valueOrNull,
          ),
          if (_starting) ...[
            const SizedBox(height: KoruSpace.md),
            KoruProgressBar(
              value: (progress ?? 0) / 100,
              color: KoruColors.leaf,
            ),
            const SizedBox(height: KoruSpace.xsm),
            Text(
              'Loading the model... ${progress ?? 0}%',
              style: KoruType.caption,
            ),
          ],
          if (_message != null) ...[
            const SizedBox(height: KoruSpace.sml),
            Text(
              _message!,
              style: KoruType.bodyCompactStrong.copyWith(
                color: _ready ? KoruColors.leaf : KoruColors.clay,
              ),
            ),
          ],
          if (!_starting && !_ready) ...[
            const SizedBox(height: KoruSpace.sml),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, KoruSize.buttonInCard),
              ),
              onPressed: available == false ? null : _start,
              icon: const Icon(Icons.play_arrow_rounded, size: KoruSize.icon),
              label: const Text('Start the bundled model'),
            ),
          ],
          // When it is unavailable, say why. A bare "NOT IN THIS BUILD" is what
          // made this hard to diagnose: the binary was in the package.
          if (_message == null && status != null && !status.available) ...[
            const SizedBox(height: KoruSpace.sml),
            Text(
              status.summary,
              style: KoruType.caption.copyWith(color: KoruColors.clay),
            ),
            if (status.path != null) ...[
              const SizedBox(height: KoruSpace.xxs),
              Text(
                'looked in ${status.path}',
                style: KoruType.micro,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// The way to the engine's own log, always there.
///
/// Not shown only on failure, which is the obvious place to put it and the wrong
/// one: a start that hangs, or one that is slow enough to look broken while it is
/// actually working, never reaches a failure message at all. Someone deciding
/// whether to uninstall needs this open next to a model that will not start,
/// and that is precisely the person a failure-only link abandons.
class _EngineLogLink extends StatelessWidget {
  const _EngineLogLink();

  @override
  Widget build(BuildContext context) {
    return KoruCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('If the model will not start', style: KoruType.rowTitleLarge),
          const SizedBox(height: KoruSpace.xs),
          Text(
            'The engine writes down what went wrong on this phone. Read it, '
            'and copy it in if you report it — it is the difference between '
            '"it does not work" and an answer.',
            style: KoruType.bodySmall,
          ),
          const SizedBox(height: KoruSpace.md),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, KoruSize.buttonInCard),
            ),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const EngineLogScreen()),
            ),
            icon: const Icon(Icons.article_outlined, size: KoruSize.icon),
            label: const Text('Read the engine log'),
          ),
        ],
      ),
    );
  }
}
