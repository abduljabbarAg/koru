import 'dart:async';

import 'package:flutter/services.dart';

/// Controls the inference engine bundled inside the APK.
///
/// The APK ships glen and a 0.5B model, so choosing "On-device model" needs no
/// setup at all: this starts the bundled server and points the client at it. If
/// the engine is missing, or fails to start, the caller falls back and says so
/// rather than leaving the user on a spinner.
///
/// Everything here degrades. A build without the binary, a device that refuses
/// to exec it, and a model that will not load all end in the same place: no
/// bundled engine, and the built-in engine still works.
class BundledEngine {
  const BundledEngine();

  static const MethodChannel _channel = MethodChannel('koru/local_engine');
  static const int defaultPort = 8099;

  /// Whether the binary is present and executable.
  Future<bool> get available async {
    try {
      return await _channel.invokeMethod<bool>('available') ?? false;
    } catch (_) {
      return false;
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
  Future<BundledStartResult> start({
    int port = defaultPort,
    Duration timeout = const Duration(seconds: 180),
    Future<bool> Function() isHealthy = _neverHealthy,
    void Function(int percent)? onProgress,
  }) async {
    if (!await available) {
      return const BundledStartResult.notBundled();
    }

    bool launched;
    try {
      launched = await _channel.invokeMethod<bool>('start', {'port': port}) ?? false;
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
    return BundledStartResult.failed(
      'The bundled engine did not answer within ${timeout.inSeconds} seconds. '
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
