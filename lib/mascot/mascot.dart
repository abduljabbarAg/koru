import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../theme.dart';
import 'mascot_animation.dart';
import 'mascot_clips.dart';

/// Lets a parent screen drive the mascot without rebuilding it.
///
/// Intents are queued rather than run immediately because the mascot owns the
/// clock. A screen can call [cheer] the instant a save succeeds and the
/// animation still starts on the next tick, against the same `now` the ticker is
/// already using.
class KoruMascotController {
  final List<KoruClip> _pending = <KoruClip>[];

  /// A short, friendly hello. Played when a reply lands.
  void greet() => _pending.add(KoruClip.greet);

  /// A bigger reaction. Played when the user actually achieved something.
  void cheer() => _pending.add(KoruClip.cheer);

  /// A wave. Played on direct interaction.
  void wave() => _pending.add(KoruClip.wave);

  /// Plays one named animation.
  ///
  /// The three above are the ones with an obvious meaning, and they stay as
  /// their own names because "cheer" says more at the call site than
  /// play(KoruClip.cheer) does. This is for the cases where the face has to
  /// match the situation, like an onboarding screen that is waiting for an
  /// answer, and the mood is information rather than a reaction.
  void play(KoruClip clip) => _pending.add(clip);

  void _drain(void Function(KoruClip clip) apply) {
    if (_pending.isEmpty) return;
    final queued = List<KoruClip>.of(_pending);
    _pending.clear();
    // Only the newest intent survives. Queuing a wave behind a cheer would play
    // two full clips back to back, which reads as a hiccup rather than a
    // reaction.
    apply(queued.last);
  }

  @visibleForTesting
  int get pendingCount => _pending.length;
}

/// Koru, the helper.
///
/// Plays the generated sprite atlas frame by frame and falls back to a vector
/// portrait if the atlas cannot be decoded, so a packaging mistake degrades to
/// something that still looks deliberate rather than an empty box.
class KoruMascot extends StatefulWidget {
  KoruMascot({
    super.key,
    this.size = 120,
    this.busy = false,
    this.controller,
    this.onTap,
    this.semanticLabel,
  });

  final double size;

  /// Pins the mascot to the thinking clip while true.
  final bool busy;

  final KoruMascotController? controller;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  State<KoruMascot> createState() => _KoruMascotState();
}

class _KoruMascotState extends State<KoruMascot> with SingleTickerProviderStateMixin {
  static const String _atlasAsset = 'assets/mascot/koru_atlas.png';

  /// Decoded once per process. A failed decode is cached too, so a missing
  /// asset does not retry on every mascot that mounts.
  static Future<ui.Image>? _atlasFuture;

  final KoruAnimator _animator = KoruAnimator();

  Ticker? _ticker;
  ui.Image? _atlas;
  int _now = 0;

  KoruClip _clip = KoruClip.idle;
  int _frame = 0;

  @override
  void initState() {
    super.initState();
    _animator.start(_now);
    _animator.setBusy(widget.busy, _now);
    _ticker = createTicker(_onTick)..start();
    unawaited(_loadAtlas());
  }

  @override
  void didUpdateWidget(covariant KoruMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.busy != widget.busy) {
      _animator.setBusy(widget.busy, _now);
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    // Ticker hands us the elapsed time directly, so there is nothing to query.
    final now = elapsed.inMilliseconds;
    _now = now;
    _animator.setBusy(widget.busy, now);

    final controller = widget.controller;
    if (controller != null) {
      controller._drain((clip) => _animator.play(clip, now));
    }

    final clip = _animator.clipAt(now);
    final frame = _animator.frameAt(clip, now);
    // The state machine already decides what changed; only rebuild when the
    // visible frame actually moved. Repainting a mascot on every vsync while
    // it sits still is pure waste on a low end phone.
    if (clip == _clip && frame == _frame) return;
    setState(() {
      _clip = clip;
      _frame = frame;
    });
  }

  Future<void> _loadAtlas() async {
    try {
      final future = _atlasFuture ??= _decodeAtlas();
      final image = await future;
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() => _atlas = image);
    } catch (_) {
      // The vector portrait below takes over and stays put.
    }
  }

  static Future<ui.Image> _decodeAtlas() async {
    final data = await rootBundle.load(_atlasAsset);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  void _handleTap() {
    widget.onTap?.call();
    if (widget.busy) return;
    _animator.wave(_now);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final art = _atlas != null
        ? _AtlasFrame(image: _atlas!, clip: _clip, frame: _frame, size: widget.size)
        : CustomPaint(
            size: Size.square(widget.size),
            painter: KoruMascotPainter(size: widget.size, clip: _clip, frame: _frame),
          );

    return Semantics(
      label: widget.semanticLabel ?? 'Koru, your helper',
      image: true,
      button: widget.onTap != null,
      child: GestureDetector(
        onTap: widget.onTap ?? _handleTap,
        behavior: HitTestBehavior.opaque,
        child: art,
      ),
    );
  }
}

/// Paints one cell of the atlas.
class _AtlasFrame extends StatelessWidget {
  const _AtlasFrame({
    required this.image,
    required this.clip,
    required this.frame,
    required this.size,
  });

  final ui.Image image;
  final KoruClip clip;
  final int frame;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _AtlasPainter(image: image, clip: clip, frame: frame),
    );
  }
}

class _AtlasPainter extends CustomPainter {
  _AtlasPainter({required this.image, required this.clip, required this.frame});

  final ui.Image image;
  final KoruClip clip;
  final int frame;

  @override
  void paint(Canvas canvas, Size size) {
    final index = koruClipStart(clip) + koruClampFrame(clip, frame);
    final cell = koruClipCell(index);

    canvas.drawImageRect(
      image,
      Rect.fromLTWH(
        (cell.col * kCell).toDouble(),
        (cell.row * kCell).toDouble(),
        kCell.toDouble(),
        kCell.toDouble(),
      ),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_AtlasPainter old) =>
      old.image != image || old.clip != clip || old.frame != frame;
}

/// Vector stand-in for the mascot.
///
/// Two jobs: it covers the frames while the atlas decodes, and it keeps the app
/// presentable if the asset ever fails to load in a release build.
class KoruMascotPainter extends CustomPainter {
  KoruMascotPainter({
    required this.size,
    this.frame = 0,
    this.clip = KoruClip.idle,
  });

  final double size;
  final int frame;
  final KoruClip clip;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 192.0;
    double l(double v) => v * s;

    final length = math.max(1, koruClipLength(clip));
    final t = frame / length;
    final bob = math.sin(t * math.pi * 2) * l(1.6);
    final centreY = l(96) + l(22) + bob;

    // Coil.
    final coil = Path();
    coil.moveTo(l(96), centreY - l(35));
    for (var i = 1; i <= 24; i++) {
      final f = i / 24;
      coil.lineTo(
        l(96) + l(26) * math.sin(f * math.pi * 1.7) - l(26) * math.sin(math.pi * 1.7),
        centreY - l(35) - l(12) * (1 - f),
      );
    }
    canvas.drawPath(
      coil,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = l(6)
        ..color = KoruColors.leaf,
    );

    // Shell.
    final body = Path()
      ..addOval(Rect.fromCenter(
        center: Offset(l(96), centreY),
        width: l(78),
        height: l(82),
      ));
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = l(3.4)
        ..color = KoruColors.leaf,
    );
    canvas.drawPath(body, Paint()..color = KoruColors.cream);

    // Arms, mirrored so both hang clear of the shell.
    final rightAngle = _rightArmAngle(t);
    for (final side in [1.0, -1.0]) {
      final angle = side > 0 ? rightAngle : math.pi - rightAngle;
      final shoulder = Offset(l(96) + side * l(33), centreY + l(5));
      final wrist = shoulder + Offset(math.cos(angle) * l(24), math.sin(angle) * l(24));
      canvas.drawLine(
        shoulder,
        wrist,
        Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = l(7)
          ..color = KoruColors.leaf,
      );
      canvas.drawOval(
        Rect.fromCenter(center: wrist, width: l(13), height: l(10)),
        Paint()..color = KoruColors.leaf,
      );
    }

    // Face.
    final eyeY = centreY - l(7);
    if (clip == KoruClip.blink && _blinkClosed(t)) {
      for (final dx in [-17.0, 17.0]) {
        final curve = Path()
          ..moveTo(l(96) + l(dx) - l(7), eyeY)
          ..quadraticBezierTo(l(96) + l(dx), eyeY + l(6), l(96) + l(dx) + l(7), eyeY);
        canvas.drawPath(
          curve,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = l(2.9)
            ..color = KoruColors.ink,
        );
      }
    } else {
      for (final dx in [-17.0, 17.0]) {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(l(96) + l(dx), eyeY),
            width: l(8),
            height: l(10),
          ),
          Paint()..color = KoruColors.ink,
        );
      }
    }

    final smile = Path()
      ..moveTo(l(86), centreY + l(13))
      ..quadraticBezierTo(l(96), centreY + l(20), l(106), centreY + l(13));
    canvas.drawPath(
      smile,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = l(2.8)
        ..color = KoruColors.ink,
    );
  }

  double _rightArmAngle(double t) {
    switch (clip) {
      case KoruClip.wave:
        return -1.35 + math.sin(t * math.pi * 4) * 0.42;
      case KoruClip.cheer:
        return -1.95;
      case KoruClip.greet:
        return -1.25 + math.sin(t * math.pi) * 0.5;
      case KoruClip.think:
        return -2.05;
      case KoruClip.idle:
      case KoruClip.blink:
        return 1.15;
    }
  }

  bool _blinkClosed(double t) => clip == KoruClip.blink && (t < 0.25 || (t > 0.5 && t < 0.75));

  @override
  bool shouldRepaint(KoruMascotPainter oldDelegate) =>
      oldDelegate.frame != frame ||
      oldDelegate.clip != clip ||
      oldDelegate.size != size;
}
