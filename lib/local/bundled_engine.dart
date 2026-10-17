import 'dart:async';

import 'package:flutter/services.dart';

/// Controls the inference engine bundled inside the APK.
///
/// The APK ships llama.cpp and a 1-bit 1.7B model, so choosing "Local model"
/// needs no setup at all: this starts the bundled server and points the client at
/// it. If the engine is missing, or fails to start, the caller falls back and
/// says so rather than leaving the user on a spinner.
///
/// Everything here degrades. A build without the binary, a device that refuses
/// to exec it, and a model that will not load all end in the same place: no
/// bundled engine, and the app saying so rather than answering by some other
/// means.
class BundledEngine {
  const BundledEngine();

  static const MethodChannel _channel = MethodChannel('koru/local_engine');
  static const int defaultPort = 8099;

  /// The model that ships inside the APK, and how big it is.
  ///
  /// Bonsai-1.7B-Q1_0: 1-bit weights, 231 MB on disk, and markedly sharper than
  /// the Qwen 0.5B it replaced. The size is stated rather than measured off
  /// disk because it is written into the model config the settings screen
  /// reads, and a config that guessed would report a wrong RAM estimate.
  static const bundledModelId = 'Bonsai-1.7B-Q1_0';
  static const bundledModelBytes = 248302272;

  /// Whether the binary is present and executable.
  Future<bool> get available async => (await status()).available;

  /// Full status, including why it is unavailable.
  ///
  /// A bare boolean was not enough. The binary was sitting in the APK and the
  /// app still said "no bundled model", because modern Android maps native
  /// libraries straight out of the package instead of extracting them, so the
  /// file the app looks for was never created. The paths and flags here make that
  /// visible instead of leaving a shrug.
  Future<BundledEngineStatus> status() async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('status');
      if (raw == null) return const BundledEngineStatus.unavailable('No status from the platform.');
      return BundledEngineStatus(
        available: raw['available'] == true,
        path: raw['path'] as String?,
        exists: raw['exists'] == true,
        executable: raw['executable'] == true,
        modelPath: raw['modelPath'] as String?,
        modelAvailable: raw['modelAvailable'] == true,
        modelBytes: (raw['modelBytes'] as num?)?.toInt() ?? 0,
        modelProblem: raw['modelProblem'] as String?,
        reason: raw['reason'] as String?,
      );
    } catch (e) {
      return BundledEngineStatus.unavailable('Could not ask the platform: $e');
    }
  }

  /// Last lines from the engine's own log, for diagnosing a failed start.
  Future<String> log() async {
    try {
      return await _channel.invokeMethod<String>('log') ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Starts the bundled engine and waits for it to answer.
  ///
  /// The first run copies roughly half a gigabyte out of the APK, so the wait is
  /// generous and the timeout is reported rather than swallowed. A process can be
  /// alive and still loading a model, so health is polled instead of trusting the
  /// start call to mean anything.
  /// Why the engine is not answering, in its own words.
  Future<EngineDiagnosis> diagnose() async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('diagnose');
      return EngineDiagnosis(
        alive: raw?['alive'] == true,
        log: (raw?['log'] as String? ?? '').trim(),
      );
    } on PlatformException {
      return const EngineDiagnosis(alive: false, log: '');
    } on MissingPluginException {
      return const EngineDiagnosis(alive: false, log: '');
    }
  }

  /// Every model the engine could be pointed at.
  ///
  /// The bundled one is always first. Anything else is a .gguf the person put
  /// in the app's own folder, which is how a bigger model gets onto a phone that
  /// shipped with a small one: bundling both would take the install past 900 MB
  /// to serve a choice most people make once.
  Future<List<LocalModelFile>> models() async {
    try {
      final raw = await _channel.invokeListMethod<dynamic>('models');
      if (raw == null) return const [];
      return [
        for (final item in raw)
          if (item is Map)
            LocalModelFile(
              label: item['label'] as String? ?? 'Model',
              path: item['path'] as String? ?? '',
            ),
      ].where((m) => m.path.isNotEmpty).toList();
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  /// Copies a model the person picked from their own storage into the app.
  ///
  /// So that adding a model is a tap rather than a file manager and a path
  /// typed from an error message.
  Future<String?> importModel(String sourcePath) async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'importModel',
        {'path': sourcePath},
      );
      if (raw == null) return 'Could not import that file.';
      if (raw['ok'] != true) return raw['error'] as String? ?? 'Could not import that file.';
      return null;
    } on PlatformException {
      return 'Could not import that file.';
    } on MissingPluginException {
      return 'This build has no model support.';
    }
  }

  Future<BundledStartResult> start({
    int port = defaultPort,
    String? modelPath,
    Duration timeout = const Duration(seconds: 180),
    Future<bool> Function() isHealthy = _neverHealthy,
    void Function(int percent)? onProgress,
  }) async {
    if (!await available) {
      return const BundledStartResult.notBundled();
    }

    bool launched;
    try {
      launched = await _channel.invokeMethod<bool>('start', {
        'port': port,
        'modelPath': modelPath,
      }) ??
          false;
    } catch (e) {
      return BundledStartResult.failed('Could not launch the bundled engine: $e');
    }
    if (!launched) {
      final detail = await log();
      return BundledStartResult.failed(
        detail.isEmpty
            ? 'The bundled engine would not start. Android may have refused to '
                'run it.'
            : 'The bundled engine would not start:\n$detail',
      );
    }

    // Poll while the model loads, reporting progress so the wait is legible.
    const tick = Duration(milliseconds: 700);
    final deadline = DateTime.now().add(timeout);
    var elapsed = 0;
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(tick);
      elapsed += tick.inMilliseconds;
      onProgress?.call((elapsed * 100 ~/ timeout.inMilliseconds).clamp(0, 99));
      if (await isHealthy()) {
        onProgress?.call(100);
        return BundledStartResult.ready('http://127.0.0.1:$port');
      }
    }
    // A model the engine cannot load does not fail at launch, it dies while
    // loading the file. start() reported success for that, the health poll then
    // timed out, and the message said only that nothing answered. The reason is
    // in the engine's own log, so it is fetched and passed on: "missing tensor
    // blk.0.attn_q.weight" is a diagnosis, "did not answer in 180 seconds" is
    // not.
    final why = await diagnose();
    return BundledStartResult.failed(
      '${why.alive ? 'The engine is running but did not answer' : 'The engine stopped'} '
      'within ${timeout.inSeconds} seconds. $why'
      'It may be out of memory.',
    );
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {
      // Stopping is best effort.
    }
  }

  static Future<bool> _neverHealthy() async => false;
}

/// Outcome of starting the bundled engine.
class BundledStartResult {
  const BundledStartResult._({
    required this.started,
    this.endpoint,
    this.reason,
    this.kind = BundledStartKind.ready,
  });

  const BundledStartResult.ready(String endpoint)
      : this._(started: true, endpoint: endpoint);

  const BundledStartResult.failed(String reason)
      : this._(started: false, reason: reason, kind: BundledStartKind.failed);

  const BundledStartResult.notBundled()
      : this._(
          started: false,
          reason: 'This build does not include a model.',
          kind: BundledStartKind.notBundled,
        );

  final bool started;
  final String? endpoint;
  final String? reason;
  final BundledStartKind kind;
}

enum BundledStartKind { ready, failed, notBundled }

/// What the platform says about the bundled engine.
class BundledEngineStatus {
  const BundledEngineStatus({
    required this.available,
    this.path,
    this.exists = false,
    this.executable = false,
    this.modelPath,
    this.modelAvailable = false,
    this.modelBytes = 0,
    this.modelProblem,
    this.reason,
  });

  const BundledEngineStatus.unavailable(String this.reason)
      : available = false,
        path = null,
        exists = false,
        executable = false,
        modelPath = null,
        modelAvailable = false,
        modelBytes = 0,
        modelProblem = null;

  final bool available;
  final String? path;
  final bool exists;
  final bool executable;
  final String? modelPath;
  final bool modelAvailable;

  /// How much room the model on disk is taking, once there is one.
  final int modelBytes;

  /// Why the bundled model is not on disk, when it is not.
  ///
  /// This is the platform saying what happened rather than this app guessing.
  /// A copy of a few hundred megabytes that runs out of room used to surface as
  /// "free space is the usual cause", which is a hypothesis shown to somebody who
  /// already knows something is wrong and cannot tell what. The numbers are
  /// here so the person can act on it.
  final String? modelProblem;

  final String? reason;

  /// One line for the settings screen.
  String get summary {
    if (!available) return reason ?? 'The bundled engine is not available.';
    if (modelAvailable) return 'Engine and model are on disk.';
    return modelProblem ?? 'Engine is on disk, but the model has not been unpacked yet.';
  }
}

/// One model the engine could be pointed at.
class LocalModelFile {
  const LocalModelFile({required this.label, required this.path});

  /// Shown in the picker, with the size already worked out.
  final String label;
  final String path;
}

/// What the engine said about itself when it would not answer.
class EngineDiagnosis {
  const EngineDiagnosis({required this.alive, required this.log});

  final bool alive;
  final String log;

  /// The tail of the log, which is where the reason is.
  String get tail {
    if (log.isEmpty) return 'The engine wrote nothing about why.';
    final lines = log.split('\n').where((l) => l.trim().isNotEmpty).toList();
    return lines.take(6).join('\n');
  }

  @override
  String toString() => tail;
}
