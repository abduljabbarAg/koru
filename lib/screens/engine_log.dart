import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../local/bundled_engine.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

/// The engine's own account of what it did, on a screen.
///
/// This exists because "couldn't start" is not a diagnosis. The native side
/// writes every failure it knows about into filesDir/llama-server.log, and
/// until now the only way to read it was adb, which nobody reports a bug with.
/// A person who cannot get a model running has one piece of information that
/// would settle it, and it has to be reachable by them without a cable.
///
/// Everything here is copyable, because a log nobody can paste into a bug report
/// is a log nobody will report a bug with.
class EngineLogScreen extends ConsumerStatefulWidget {
  const EngineLogScreen({super.key});

  @override
  ConsumerState<EngineLogScreen> createState() => _EngineLogScreenState();
}

/// The platform's answer, and the log, together.
///
/// Two platform calls kept as one value so the screen cannot show a status from
/// one moment and a log from another and let somebody read the gap as meaning.
class _Loaded {
  const _Loaded({required this.status, required this.diagnosis});
  final BundledEngineStatus status;
  final EngineDiagnosis diagnosis;
}

class _EngineLogScreenState extends ConsumerState<EngineLogScreen> {
  /// Read once when the screen opens rather than watched.
  ///
  /// Watching the status provider would re-read the platform every time it
  /// invalidated, and reading the status is not free — it is one platform hop
  /// per refresh, on a screen nobody is going to sit and watch change. Null is
  /// also the spinner: there is nothing to show until both answers are in, and
  /// showing a status from one call and an empty log from another is worse than
  /// showing neither.
  _Loaded? _loaded;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final engine = ref.read(bundledEngineProvider);
    // Both at once. Sequential would be tidier to read and slower to wait for,
    // and this is the screen somebody opens when something is already wrong.
    final results = await Future.wait([
      engine.status(),
      engine.diagnose(),
    ]);
    if (!mounted) return;
    setState(() {
      _loaded = _Loaded(
        status: results[0] as BundledEngineStatus,
        diagnosis: results[1] as EngineDiagnosis,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final ready = _loaded;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Engine log'),
        actions: [
          IconButton(
            onPressed: ready == null ? null : () => _copy(context, ready),
            icon: const Icon(Icons.copy_rounded, size: KoruSize.icon),
            tooltip: 'Copy everything on this screen',
          ),
        ],
      ),
      body: KoruPagePadding(
        bottom: KoruSpace.xxl,
        child: ListView(
        children: [
          Text(
            'What the model engine said about itself. If it will not start, '
            'this is the part that says why.',
            style: KoruType.caption.copyWith(height: 1.45),
          ),
          const SizedBox(height: KoruSpace.lg),
          if (ready == null)
            // Named rather than a bare bar: this is the screen somebody opens
            // when something is already broken, and a ring that says nothing
            // leaves them waiting with nowhere to look.
            const KoruLoading(label: 'Asking the engine')
          else ...[
            _statusCard(ready.status, ready.diagnosis),
            const SizedBox(height: KoruSpace.lg),
            const SectionLabel('The log itself'),
            _log(ready.diagnosis.tail),
            const SizedBox(height: KoruSpace.lg),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(KoruSize.button),
              ),
              onPressed: () => _copy(context, ready),
              icon: const Icon(Icons.copy_rounded, size: KoruSize.icon),
              label: const Text('Copy this to send with a report'),
            ),
            const SizedBox(height: KoruSpace.sm),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(KoruSize.buttonInCard),
              ),
              onPressed: () {
                _loaded = null;
                _load();
              },
              icon: const Icon(Icons.refresh_rounded, size: KoruSize.icon),
              label: const Text('Read it again'),
            ),
          ],
        ],
        ),
      ),
    );
  }

  /// What the platform said about the binary and the model, each named.
  ///
  /// Named separately because they fail separately and for unrelated reasons: a
  /// binary that was never extracted is a packaging problem, and a model with no
  /// room to unpack is a phone that is full. One merged line hides which.
  Widget _statusCard(BundledEngineStatus status, EngineDiagnosis diagnosis) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Fact(
          label: 'Engine binary',
          value: status.available
              ? 'Found at ${status.path}'
              : status.reason ?? 'Not on disk',
          ok: status.available,
        ),
        _Fact(
          label: 'Model',
          value: status.modelAvailable
              ? 'On disk (${(status.modelBytes / (1024 * 1024)).round()} MB)'
              : status.modelProblem ?? 'Not unpacked yet',
          ok: status.modelAvailable,
        ),
        _Fact(
          label: 'Engine process',
          value: diagnosis.alive ? 'Running' : 'Not running',
          ok: diagnosis.alive,
        ),
      ],
    );
  }

  Widget _log(String text) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 140),
      padding: const EdgeInsets.all(KoruSpace.mdl),
      decoration: BoxDecoration(
        color: KoruColors.surface,
        borderRadius: BorderRadius.circular(KoruRadius.field),
        border: Border.fromBorderSide(KoruBorders.hairline()),
      ),
      // The shared monospace role, because this is output and not prose: the
      // reason is often in the shape of it — a path, a byte count, a tensor
      // name — and it has to be selectable so it can be pasted into a report.
      child: SelectableText(text, style: KoruType.mono),
    );
  }

  Future<void> _copy(BuildContext context, _Loaded loaded) async {
    final text = [
      'Engine binary: '
      '${loaded.status.available ? 'found' : loaded.status.reason ?? 'missing'}'
      '\n${loaded.status.path ?? ''}',
      'Model: '
      '${loaded.status.modelAvailable ? 'on disk' : loaded.status.modelProblem ?? 'not unpacked'}',
      'Process: ${loaded.diagnosis.alive ? 'running' : 'not running'}',
      '',
      loaded.diagnosis.tail,
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    toast(context, 'Copied. Paste it into a bug report.');
  }
}

/// One named fact about the engine, marked with whether it is the wanted answer.
class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, required this.ok});

  final String label;
  final String value;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: KoruSpace.sml),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
            size: KoruSize.iconSm,
            color: ok ? KoruColors.leaf : KoruColors.clay,
          ),
          const SizedBox(width: KoruSpace.sm),
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: KoruType.caption.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: KoruType.caption.copyWith(
                color: ok ? KoruColors.inkSoft : KoruColors.clay,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}