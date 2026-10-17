import 'dart:convert';

import '../engine.dart';
import '../store.dart';
import 'bundled_engine.dart';
import 'local_model_client.dart';

/// Where the bundled engine serves, and where the chat looks for it.
///
/// One function because three callers used to build this string themselves and a
/// single wrong character in one of them is a chat that cannot reach a model
/// which is plainly running on the port beside it.
String bundledEndpoint({int port = BundledEngine.defaultPort}) =>
    'http://127.0.0.1:$port';

/// What came of trying to bring the local model up.
class LocalEngineOutcome {
  const LocalEngineOutcome({
    required this.running,
    this.problem,
    this.endpoint,
    this.started = false,
  });

  /// True when something is answering on the port, whether this call is what got
  /// it there or not.
  final bool running;

  /// Why not, in the engine's own words where it had any.
  final String? problem;

  /// Where questions should go, once it is up.
  final String? endpoint;

  /// True when this call is what started it.
  ///
  /// Kept apart from [running] because the two look identical from outside and
  /// are not: an engine already serving means there is nothing to wait for, and
  /// a cold one copies a few hundred megabytes out of the APK. A progress bar
  /// that runs for a model that was already up is a lie told slowly.
  final bool started;
}

/// Starts the engine that ships inside the APK, and reports how it went.
///
/// No providers and no widgets: the chat, the engine switcher and Settings all
/// hand it what it needs, which is the whole reason it is here. Choosing "the
/// local model" used to mean choosing it and then walking to Settings to press
/// a start button, with two copies of the start sequence that could drift apart
/// and neither of which told the person who was tapping what it was doing. There
/// is one sequence now and every caller sees the same progress.
///
/// Nothing here writes the engine choice. Deciding *that* a model should run is
/// the switcher's job; this only makes it run.
class LocalEngineRunner {
  const LocalEngineRunner({
    required this.engine,
    required this.client,
    required this.store,
  });

  final BundledEngine engine;
  final LocalModelClient client;
  final ProfileStore store;

  /// Whether something is already answering on the loopback port.
  Future<bool> isRunning() async => await client
      .check(bundledEndpoint())
      .then((result) => result is LocalReply)
      .catchError((_) => false);

  /// Brings the engine up, reporting progress as it goes.
  ///
  /// [modelPath] wins over the stored choice, because the picker writes a model
  /// and then starts it in the same breath. A start that quietly used the
  /// previous choice would look exactly like the picker being ignored.
  ///
  /// The stored endpoint is written here rather than by each caller, so the chat
  /// and Settings cannot end up pointing the client at a different address than
  /// the one that was just verified as answering.
  Future<LocalEngineOutcome> start({
    String? modelPath,
    void Function(int percent)? onProgress,
  }) async {
    // Two phases, told apart, because they are two different waits.
    //
    // Listing the models is what makes the platform materialise the bundled one
    // out of the APK: 248 MB of copying with nothing to report into, which on the
    // target phone is the slowest thing this app ever does. The engine's own
    // load after it is about 3 seconds and reports a real percentage. Both used
    // to be reported as 0%, so the slow half looked like a frozen bar and then
    // jumped, and the fast half looked like it was the thing that was slow.
    //
    // Asked whether it is needed rather than assumed, because reporting "copying
    // 248 MB" on every launch of an app that has already done it once would be
    // the same kind of lie in the other direction.
    final status = await engine.status();
    final copying = status.available && !status.modelAvailable;
    onProgress?.call(copying ? EngineProgress.unpacking : 0);

    // One listing, used for three decisions below. The platform puts the
    // bundled model first and that ordering is part of the contract, not a
    // presentational detail.
    final catalog = await engine.models();
    final bundled = catalog.isEmpty ? null : catalog.first.path;
    final stored = (await store.get('model_path')) ?? '';
    final wanted = modelPath ?? stored;

    // An empty stored path means the bundled model, so a stored choice and a
    // requested one have to be compared as what they name rather than as
    // strings. Compared raw, "start the bundled model" looks like a request to
    // switch to it — which stopped an engine that was already running the
    // bundled model and started it again for nothing.
    final runningOn = stored.isEmpty ? bundled : stored;
    final askingFor = wanted.isEmpty ? bundled : wanted;

    if (await isRunning()) {
      if (askingFor == runningOn) {
        return LocalEngineOutcome(running: true, endpoint: bundledEndpoint());
      }
      // Up on a different model. The engine serves one file for the life of the
      // process, so a start beside it would succeed and change nothing.
      //
      // The one place this app ever stops an engine, and deliberately so: the
      // person asked for a different model, and the alternative is a restart
      // that silently keeps serving the old file. Nothing else stops it — not
      // backgrounding, not navigating away — because the next question would
      // then pay a cold start for no reason anybody asked for.
      await engine.stop();
    }

    final result = await engine.start(
      modelPath: askingFor,
      onProgress: onProgress,
      isHealthy: () async => await client.check(bundledEndpoint()) is LocalReply,
    );
    if (!result.started || result.endpoint == null) {
      return LocalEngineOutcome(running: false, problem: result.reason);
    }

    // A model the person brought themselves is not the bundled one, and writing
    // the bundled name and size into the config is how the screen came to claim
    // a 231 MB model while a four gigabyte one was loaded.
    final own = askingFor == null ? null : _modelAt(catalog, askingFor);
    await store.put(
      'local_model',
      jsonEncode(LocalModelConfig(
        endpoint: result.endpoint!,
        modelId: own?.label ?? BundledEngine.bundledModelId,
        label: own?.label ?? 'Bundled',
        // Only the bundled size is known here. The platform reports a path and
        // a label, never a file size, and inventing one is how the RAM estimate
        // came to be wrong by several gigabytes.
        sizeBytes: own == null ? BundledEngine.bundledModelBytes : 0,
      ).toMap()),
    );

    return LocalEngineOutcome(
      running: true,
      endpoint: result.endpoint,
      started: true,
    );
  }

  /// The row the engine would show for [path], or null when it is not one it
  /// knows about. A path that has gone missing must still start on something
  /// rather than be refused: the platform validates the choice and falls back to
  /// the bundled model itself.
  LocalModelFile? _modelAt(List<LocalModelFile> catalog, String path) {
    for (final model in catalog) {
      if (model.path == path) return model;
    }
    return null;
  }
}