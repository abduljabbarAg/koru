import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine.dart';
import '../engine_switch.dart';
import '../state.dart';
import '../widgets.dart';
import 'engine_sheet.dart';

/// The engine control in the chat's app bar.
///
/// It lives here rather than in `ui/thread.dart` because everything in `ui/`
/// knows no providers — the widget itself is [KoruEngineBarButton], a piece of
/// type and colour — and this is the part that has to know what the store says
/// and what the platform is doing right now.
///
/// The detail line is the reason this is a bar control and not a pill. "CLOUD
/// MODEL" tells somebody that something is answering; "OpenRouter" tells them
/// who, and that is the question behind the complaint this was built for.
class EngineBarControl extends ConsumerWidget {
  const EngineBarControl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.watch(engineProvider).valueOrNull ?? KoruEngine.onDevice;
    final chat = ref.watch(chatProvider);

    // Null while the platform is being asked, which is deliberately not read as
    // an absence: a build that does have a model must not announce that it has
    // none on every open while one platform call is in flight.
    final present = ref.watch(localEnginePresentProvider).valueOrNull;
    final nothingToRun = engine == KoruEngine.onDevice && present == false;

    return KoruEngineBarButton(
      engine: engine,
      starting: chat.engineProgress != null,
      progress: chat.engineProgress,
      failed: chat.engineProblem != null || nothingToRun,
      tokensPerSecond: _lastSpeed(chat.messages),
      detail: _detail(ref, engine),
      onTap: () => showEngineSwitcher(context),
    );
  }

  /// What to say under the engine's name, from whatever that engine can be
  /// honest about.
  ///
  /// Left out entirely rather than filled with a placeholder: a line reading
  /// "loading" next to a bar that is otherwise finished is noise, and the first
  /// line already says which engine is answering.
  String? _detail(WidgetRef ref, KoruEngine engine) => switch (engine) {
        KoruEngine.onDevice => _localModel(ref),
        KoruEngine.cloud => ref
                .watch(cloudSelectionProvider)
                .valueOrNull
                ?.provider
                .label,
      };

  /// The model the engine is pointed at: the stored choice, else the one inside
  /// the app, else whatever the platform listed first.
  ///
  /// The same order [EngineBarControl] and the switcher resolve it in, so the
  /// bar cannot name a model the sheet would then offer somewhere else.
  String? _localModel(WidgetRef ref) {
    final models = ref.watch(availableModelsProvider).valueOrNull;
    if (models == null || models.isEmpty) return null;
    final chosen = ref.watch(chosenModelProvider).valueOrNull;
    if (chosen != null) {
      for (final model in models) {
        if (model.path == chosen) return model.label;
      }
    }
    for (final model in models) {
      if (isBundledModel(model)) return model.label;
    }
    return models.first.label;
  }

  /// How fast the last answered turn came back, which is the only figure in the
  /// app that says whether the local model is worth using on this phone.
  ///
  /// The newest turn that reported one rather than the newest turn: the
  /// unanswered turn above it has no figure yet, and a bar dropping back to no
  /// number the moment a question is asked reads as a fault.
  double? _lastSpeed(List<Msg> messages) {
    for (final message in messages.reversed) {
      final speed = message.tokensPerSecond;
      if (speed != null) return speed;
    }
    return null;
  }
}