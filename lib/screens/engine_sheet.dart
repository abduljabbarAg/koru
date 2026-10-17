import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cloud_providers.dart';
import '../engine.dart';
import '../engine_switch.dart';
import '../local/bundled_engine.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'engine_log.dart';

/// Opens the switcher that the engine control in the app bar opens.
///
/// Titled "Who answers" rather than "Settings" on purpose, and the same words
/// the Settings index uses for the same page: the person tapping it wants to
/// change this, not go somewhere. Everything it writes goes through
/// [selectEngine] and friends, so Settings and the chat cannot end up showing
/// different engines.
Future<void> showEngineSwitcher(BuildContext context) {
  return showKoruSheet<void>(
    context,
    title: 'Who answers',
    subtitle: 'Choosing the local model starts it here. There is no setup step, '
        'and nothing to go and do first.',
    builder: (_) => const _EngineSwitcher(),
  );
}

/// Which of the three questions the sheet is asking.
  ///
  /// One sheet rather than three, even though there are now only two engines:
  /// the second and third stages still exist to complete a choice made in the
  /// first, and a stack of bottom sheets that each push the next is how somebody
  /// ends up two levels deep with no way back.
enum _Stage { engines, cloud, models }

class _EngineSwitcher extends ConsumerStatefulWidget {
  const _EngineSwitcher();

  @override
  ConsumerState<_EngineSwitcher> createState() => _EngineSwitcherState();
}

class _EngineSwitcherState extends ConsumerState<_EngineSwitcher> {
  _Stage _stage = _Stage.engines;

  /// The model the engine is being started on, while it is being started. Null
  /// the rest of the time, including once it has finished.
  String? _starting;

  /// Set when the last start worked, so the sheet says so instead of simply
  /// stopping and leaving the person to guess.
  bool _running = false;

  /// Why the last start did not work. Held here rather than read live from the
  /// chat state, because a launch warm-up could overwrite it with a failure the
  /// person never asked for.
  String? _failure;

  /// A model that would not come in from storage. Not the same as the engine
  /// failing to start, and not reported as if it were.
  String? _importProblem;

  /// Whether the model list has been asked for while the engine was booting.
  ///
  /// The start replaces the list with the wait, which is right — a picker
  /// sitting next to a progress bar invites a second choice halfway through the
  /// first one — and this is how the person who did want the other model gets
  /// it back without losing the start.
  bool _listRequested = false;

  Future<void> _choose(KoruEngine engine) async {
    await selectEngine(ref, engine);
    if (!mounted) return;
    switch (engine) {
      case KoruEngine.cloud:
        setState(() => _stage = _Stage.cloud);
      case KoruEngine.onDevice:
        setState(() => _stage = _Stage.models);
        // Started here, not one screen later. Choosing the engine used to mean
        // choosing it AND going to Settings AND pressing start, with nothing on
        // the way saying which of those had happened.
        //
        // The list is read first so the first frame of the model stage is not
        // an empty "no model found" while the platform is still answering.
        await ref.read(availableModelsProvider.future);
        if (!mounted) return;
        await _startChosen();
    }
  }

  /// Starts whatever is already chosen, which on a fresh install is the model
  /// inside the app. Nothing to choose means nothing to ask.
  Future<void> _startChosen() async {
    final models = ref.read(availableModelsProvider).valueOrNull ?? const <LocalModelFile>[];
    final model = _chosenAmong(models);
    if (model == null) return;
    await _start(model);
  }

  /// The model that is currently pointed at: the stored choice, else the bundled
  /// one, else whatever the platform listed first.
  LocalModelFile? _chosenAmong(List<LocalModelFile> models) {
    if (models.isEmpty) return null;
    final chosen = ref.read(chosenModelProvider).valueOrNull;
    if (chosen != null) {
      for (final model in models) {
        if (model.path == chosen) return model;
      }
    }
    for (final model in models) {
      if (isBundledModel(model)) return model;
    }
    return models.first;
  }

  /// Points the engine at [model] and starts it, in one tap.
  Future<void> _start(LocalModelFile model) async {
    await selectLocalModel(ref, model);
    if (!mounted) return;
    setState(() {
      _starting = model.label;
      _failure = null;
      _running = false;
      _listRequested = false;
    });

    final ok = await ref
        .read(chatProvider.notifier)
        .ensureEngineRunning(modelPath: model.path);
    if (!mounted) return;
    final problem = ok ? null : ref.read(chatProvider).engineProblem;
    // Read after the start, not before: the interesting reason is usually about
    // what just happened, and a status read taken beforehand says nothing about
    // the attempt.
    final why = ok ? null : problem ?? await _whyItDidNotStart();
    if (!mounted) return;
    setState(() {
      _starting = null;
      _running = ok;
      _failure = why;
    });
  }

  /// The platform's own account, when the start itself produced no message.
  ///
  /// Only used as a fallback, and deliberately never a guess. Every earlier
  /// version ended on "free space is the usual cause", which is a hypothesis
  /// shown to somebody who already knows something is wrong and cannot act on
  /// it. Where the platform can name the cause it is named.
  Future<String> _whyItDidNotStart() async {
    final status = await ref.read(bundledEngineStatusProvider.future);
    if (status.modelProblem != null) return status.modelProblem!;
    if (!status.available) return status.summary;
    return 'The engine launched but never answered on its port. The log says '
        'what it did in the meantime.';
  }

  /// Brings in a .gguf from the phone's own storage, so "your own model" is a tap
  /// rather than a file manager and a path read off an error message.
  Future<void> _importModel() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = picked?.files.single.path;
    if (path == null || !mounted) return;
    final problem = await ref.read(bundledEngineProvider).importModel(path);
    ref.invalidate(availableModelsProvider);
    if (!mounted) return;
    setState(() => _importProblem = problem);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_stage != _Stage.engines) _back(),
        const SizedBox(height: KoruSpace.xs),
        switch (_stage) {
          _Stage.engines => _engines(),
          _Stage.cloud => _cloud(),
          _Stage.models => _models(),
        },
      ],
    );
  }

  Widget _back() {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => setState(() => _stage = _Stage.engines),
        icon: const Icon(Icons.arrow_back_rounded,
            size: KoruSize.iconSm),
        label: const Text('All engines'),
      ),
    );
  }

  /// The two engines, each with what picking it actually costs.
  ///
  /// Every row is a full-width tile rather than a pill or a bare radio so the
  /// blurb has somewhere to go: the whole difference between a local model and a
  /// frontier model over the internet is the sentence under the name, and a
  /// control that cannot carry it is how somebody ended up expecting a chatbot
  /// and got a lookup table.
  Widget _engines() {
    final current = ref.watch(engineProvider).valueOrNull ?? KoruEngine.onDevice;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final engine in KoruEngine.values)
          KoruSelectableTile(
            label: engine.label,
            blurb: engine.blurb,
            selected: current == engine,
            icon: switch (engine) {
              KoruEngine.onDevice => Icons.memory_rounded,
              KoruEngine.cloud => Icons.cloud_outlined,
            },
            onTap: () => _choose(engine),
          ),
        // Said where the choice is made rather than buried in a privacy policy,
        // because the one thing every engine here agrees about is that some
        // questions are not this app's to answer.
        Text(
          'Anything about a crisis, a diagnosis or a court date goes to a person '
          'instead, whichever one you pick.',
          style: KoruType.caption.copyWith(height: 1.45),
        ),
      ],
    );
  }

  /// Which company answers online, and whether it has a key yet.
  ///
  /// "Cloud provider" is used here and only here in the app, for the company.
  /// The engine it serves is the "Cloud model" one step back, and saying both on
  /// one screen is what made the two look like the same setting twice.
  Widget _cloud() {
    final selection = ref.watch(cloudSelectionProvider).valueOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Which company answers online. The key for each one is kept '
          'separately, in Settings, so switching does not need a new key.',
          style: KoruType.caption.copyWith(height: 1.45),
        ),
        const SizedBox(height: KoruSpace.md),
        for (final provider in kCloudProviders)
          _providerTile(provider, selection?.provider.id),
      ],
    );
  }

  Widget _providerTile(CloudProvider provider, String? currentId) {
    // Whether this provider already has a key, so the list can mark the ones
    // that could answer right now. Twenty reads of the keystore is cheap next to
    // a question that comes back as "add a key first" for the third time.
    final hasKey =
        ref.watch(cloudKeyProvider(provider.id)).valueOrNull?.isNotEmpty ?? false;
    return KoruSelectableTile(
      label: provider.label,
      blurb: provider.note ??
          '${provider.models.length} model'
              '${provider.models.length == 1 ? '' : 's'} available',
      selected: currentId == provider.id,
      icon: Icons.cloud_outlined,
      trailing: hasKey
          ? KoruPill(
              label: 'KEY SAVED',
              color: KoruColors.leaf,
              background: KoruColors.leafSoft,
            )
          : null,
      onTap: () async {
        await selectCloudProvider(ref, provider.id);
        if (mounted) Navigator.of(context).pop();
      },
    );
  }

  Widget _models() {
    // A start is under way, or finished, or failed, and each replaces the list
    // with what is happening to it.
    final starting = _starting;
    if (starting != null && !_listRequested) return _startingPanel(starting);
    if (_failure != null) return _failurePanel();
    if (_running && !_listRequested) return _runningPanel();

    final models = ref.watch(availableModelsProvider).valueOrNull ?? const <LocalModelFile>[];
    final chosen = ref.watch(chosenModelProvider).valueOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Pick which model runs. The bundled one is the fast one and is inside '
          'the app already; anything else is a .gguf you added, and it will be '
          'slower and sharper.',
          style: KoruType.caption.copyWith(height: 1.45),
        ),
        if (_importProblem != null)
          KoruNotice(
            title: 'That file could not be added',
            message: _importProblem!,
            icon: Icons.error_outline_rounded,
            tone: KoruTones.clay,
          )
        else if (_running)
          const KoruNotice(
            title: 'Local model running',
            message: 'The choice below is saved. Picking a different model '
                'restarts the engine on it.',
            icon: Icons.check_circle_rounded,
          ),
        const SizedBox(height: KoruSpace.sm),
        if (models.isEmpty)
          KoruNotice(
            title: 'No model found',
            message: 'This build has no bundled model, and no .gguf has been '
                'added here. Add one and it will show up in this list.',
            icon: Icons.memory_rounded,
            tone: KoruTones.gold,
          )
        else
          for (final model in models)
            KoruSelectableTile(
              label: model.label,
              blurb: isBundledModel(model)
                  ? 'Inside the app. No download, no setup.'
                  : 'One you added. Sharper and slower.',
              selected: isBundledModel(model) ? chosen == null : chosen == model.path,
              icon: Icons.memory_rounded,
              onTap: () => _start(model),
            ),
        const SizedBox(height: KoruSpace.xs),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(KoruSize.buttonInCard),
          ),
          onPressed: _importModel,
          icon: const Icon(Icons.upload_file_rounded, size: KoruSize.icon),
          label: const Text('Add a model from this phone'),
        ),
        if (starting != null || _running)
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(KoruSize.buttonInCard),
            ),
            onPressed: () => setState(() => _listRequested = true),
            child: Text(_running ? 'Use a different model' : 'See the models'),
          ),
      ],
    );
  }

  /// The wait, in place.
  ///
  /// Stays up until the engine answers. Closing the sheet and leaving the person
  /// to wonder whether anything is happening is the failure this replaces, and
  /// the bar is driven by the engine's own progress rather than by a timer.
  Widget _startingPanel(String model) {
    final chat = ref.watch(chatProvider);
    final percent = chat.engineProgress;
    final at = (percent ?? 0) / 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KoruNotice(
          title: 'Starting the local model',
          message: 'Unpacking $model and waking the server up. You can close '
              'this and ask something meanwhile.',
          icon: Icons.memory_rounded,
        ),
        KoruProgressBar(
          // Null sweeps. The unpack has no number behind it, and a bar pinned
          // at zero for thirty seconds is the thing this screen is meant to stop.
          value: percent == EngineProgress.unpacking ? null : at.clamp(0.0, 1.0),
          color: KoruColors.leaf,
        ),
        const SizedBox(height: KoruSpace.sm),
        Text(
          // The two halves of a cold start are told apart, because only one of
          // them has a percentage. Measured on the phone the copy is the tens of
          // seconds and the engine's own load is about three, so printing a
          // percentage across both of them made the slow half look frozen.
          switch (percent) {
            EngineProgress.unpacking =>
              'Copying 248 MB out of the app. Once, on first use.',
            null => 'Getting it ready',
            _ => 'Waking the server up  $percent%',
          },
          style: KoruType.caption,
        ),
        const SizedBox(height: KoruSpace.md),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(KoruSize.buttonInCard),
          ),
          onPressed: () => setState(() => _listRequested = true),
          child: const Text('See the models'),
        ),
      ],
    );
  }

  Widget _runningPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const KoruNotice(
          title: 'Local model running',
          message: 'Nothing about your records left the device. The first '
              'answer takes a few seconds while it reads them.',
          icon: Icons.check_circle_rounded,
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(KoruSize.button),
          ),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Ask it something'),
        ),
        const SizedBox(height: KoruSpace.sm),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(KoruSize.buttonInCard),
            ),
          onPressed: () => setState(() => _listRequested = true),
          child: const Text('Use a different model'),
        ),
      ],
    );
  }

  /// What went wrong, in the sheet, with a way to try again.
  ///
  /// It used to be answered from the user's records instead, which returned in
  /// milliseconds and looked exactly like a fast model. The complaint that
  /// produced this panel was that: a choice that silently did nothing.
  Widget _failurePanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KoruNotice(
          title: 'It did not start',
          // The platform's own words when it has any. "The model did not start.
          // Free space is the usual cause." is a shrug written by this app about
          // something the platform knows precisely — how much room the copy needs
          // and how much the phone has — and a person cannot act on a shrug.
          message: _failure!,
          icon: Icons.error_outline_rounded,
          tone: KoruTones.clay,
        ),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, KoruSize.buttonInCard),
                ),
                onPressed: _startChosen,
                child: const Text('Try again'),
              ),
            ),
            const SizedBox(width: KoruSpace.sm),
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, KoruSize.buttonInCard),
                ),
                onPressed: () => setState(() {
                  _failure = null;
                  _listRequested = true;
                }),
                child: const Text('Another model'),
              ),
            ),
          ],
        ),
        const SizedBox(height: KoruSpace.xs),
        // The full log, one tap from the failure that pointed here. A sheet is
        // where somebody is when the engine has just refused, so that is where the
        // next step has to be.
        TextButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const EngineLogScreen()),
          ),
          icon: const Icon(Icons.article_outlined,
            size: KoruSize.iconSm),
          label: const Text('Read the engine log'),
        ),
      ],
    );
  }
}