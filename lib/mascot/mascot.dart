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
  const KoruMascot({
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

    // Face.
    //
    // Two eyes, and they blink on their own clock. Earlier both closed at the
    // same instant from the same frame, which read as a single flat bar across
    // the face rather than as a face doing something.
    //
    // Each eye gets its own period, its own phase and its own duty cycle, all
    // derived from a fixed seed so a given eye is consistently itself from run
    // to run, and the two are never in step for long.
    final eyeY = centreY - l(7);
    for (final eye in _eyes) {
      final dx = eye.dx;
      // A blink is a quick squeeze, not a long closure. 0.11 of the cycle is
      // roughly how long a real blink lasts against a ~4 s period.
      final cycleT = (t / eye.period + eye.phase) % 1.0;
      final closed = cycleT < eye.duty;

      if (closed) {
        // A downcurve lid rather than a straight line, so a blink keeps the
        // expression alive instead of snapping to a bar.
        final curve = Path()
          ..moveTo(l(96) + l(dx) - l(8), eyeY - l(1))
          ..quadraticBezierTo(
              l(96) + l(dx), eyeY + l(7), l(96) + l(dx) + l(8), eyeY - l(1));
        canvas.drawPath(
          curve,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = l(2.9)
            ..color = KoruColors.ink,
        );
      } else {
        // Round, with a highlight, because a flat disc has nothing in it to
        // catch the light and reads as a sticker.
        final centre = Offset(l(96) + l(dx), eyeY);
        canvas.drawOval(
          Rect.fromCenter(center: centre, width: l(9), height: l(11)),
          Paint()..color = KoruColors.ink,
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: centre + Offset(l(2.2), l(-2.6)),
            width: l(2.6),
            height: l(2.6),
          ),
          Paint()..color = KoruColors.cream.withValues(alpha: 0.85),
        );
      }
    }

    // A mouth that is a smile, and that actually changes: it opens while the
    // model is streaming an answer and flattens while it is thinking, so the
    // face is doing the same job the status line is.
    final speaking = clip == KoruClip.think || clip == KoruClip.cheer;
    final mouthOpen = speaking
        ? (0.5 + 0.5 * math.sin(t * math.pi * 6)) * 0.55
        : 0.0;

    if (mouthOpen > 0.05) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(l(96), centreY + l(16)),
          width: l(16),
          height: l(4) + l(16) * mouthOpen,
        ),
        Paint()..color = KoruColors.ink,
      );
    } else {
      final smile = Path()
        ..moveTo(l(86), centreY + l(13))
        ..quadraticBezierTo(l(96), centreY + l(21), l(106), centreY + l(13));
      canvas.drawPath(
        smile,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = l(2.8)
          ..color = KoruColors.ink,
      );
    }
  }


  @override
  bool shouldRepaint(KoruMascotPainter oldDelegate) =>
      oldDelegate.frame != frame ||
      oldDelegate.clip != clip ||
      oldDelegate.size != size;
}

/// One eye's blinking personality.
///
/// Fixed at construction rather than randomised per frame: an eye that changed
/// its period every frame would strobe, and one that re-rolled on every rebuild
/// would never be recognisable as the same eye twice.
class _Eye {
  const _Eye(this.dx, this.period, this.phase, this.duty);

  /// Horizontal offset from the face centre.
  final double dx;

  /// Seconds between blinks.
  final double period;

  /// Where this eye sits in its own cycle, 0 to 1. Different per eye so the two
  /// do not fall into lockstep.
  final double phase;

  /// Fraction of the period spent closed. Short, because a real blink is brief.
  final double duty;
}

const _eyes = <_Eye>[
  // Left: quicker and shallower than the right, and offset so the two are out
  // of step for most of any given cycle.
  _Eye(-17.0, 3.7, 0.0, 0.085),
  _Eye(17.0, 5.1, 0.55, 0.12),
];
