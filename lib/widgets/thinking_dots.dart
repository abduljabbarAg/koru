import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../mascot/mascot.dart';
import '../theme.dart';

/// What the model is doing, said out loud next to the animation.
///
/// Added because an animation on its own answers "is it working" but not "is it
/// doing the right thing". A model reading the records before it answers takes
/// real time, and during that the only honest thing to show is which of the two
/// slow things is happening: it is *reading the records*, or it is *writing the
/// answer*. Those feel identical as three bouncing dots and completely different
/// once named.
enum KoruActivity {
  /// A model has been asked and tokens have started arriving.
  writing('Writing an answer'),

  /// Working out what was asked, in a plan or a write.
  thinking('Working out what you meant'),

  /// Turning a pasted list into a plan.
  readingList('Reading your list'),

  /// Looking at what is due.
  checking('Checking what is due'),

  /// Looking through the client list.
  looking('Looking up your clients');

  final String label;
  const KoruActivity(this.label);
}

/// The waiting indicator.
///
/// Cycles through Google's three-stage shape rather than staying on three flat
/// dots: three dots, then three ascending, then a triangle, then back down. It
/// is more informative at a glance because the *changing silhouette* reads as
/// activity even in peripheral vision, and it stops the screen looking frozen
/// when nothing has arrived yet.
///
/// One controller drives the whole cycle so the stages cannot drift apart, which
/// is what happens when each stage owns its own animation.
class KoruThinkingDots extends StatefulWidget {
  const KoruThinkingDots({
    super.key,
    this.activity = KoruActivity.thinking,
    this.size = 18,
    this.color,
    this.showMascot = false,
  });

  final KoruActivity activity;
  final double size;

  /// Null means "whatever the current palette uses". Resolved in build rather
  /// than stored, or a caller in the other palette would be stuck with the
  /// colour it happened to construct this in.
  final Color? color;

  /// Show Koru's face instead of the animated dots.
  ///
  /// On wherever the app is speaking on somebody's behalf, which is the only
  /// place the identity of the speaker was ever in doubt.
  final bool showMascot;

  @override
  State<KoruThinkingDots> createState() => _KoruThinkingDotsState();
}

class _KoruThinkingDotsState extends State<KoruThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _cycle;

  /// One full loop of the shape cycle.
  static const _cycleMs = 1800;

  @override
  void initState() {
    super.initState();
    _cycle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _cycleMs),
    )..repeat();
  }

  @override
  void dispose() {
    _cycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // The mascot, not three dots.
        //
        // Dots say "something is happening somewhere". They do not say who is
        // doing it, and in a conversation the single most reassuring thing to
        // show is the thing you are talking to still being there. The dots were
        // also the only part of the reply that was not the mascot, which made
        // the gap between them look like a different app had taken over.
        if (widget.showMascot)
          KoruMascot(
            size: widget.size * 1.9,
            busy: true,
            semanticLabel: 'Koru is ${widget.activity.label.toLowerCase()}',
          )
        else
          AnimatedBuilder(
            animation: _cycle,
            builder: (context, _) {
              // Three stages across one loop: flat, rising, triangle.
              final t = _cycle.value * 3;
              final stage = t.floor() % 3;
              final within = Curves.easeInOut.transform(t - t.floor());

              return Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    if (i > 0) SizedBox(width: widget.size * 0.16),
                    _dot(stage, within, i),
                  ],
                ],
              );
            },
          ),
        const SizedBox(width: KoruSpace.sml),
        Text(
          widget.activity.label,
          style: KoruType.meta.copyWith(height: 1.2),
        ),
      ],
    );
  }

  Widget _dot(int stage, double t, int index) {
    // Each dot lags the one before it slightly, so the shape appears to travel
    // rather than all three moving together. That is the whole illusion.
    final lag = index * 0.12;
    final local = ((t - lag) % 1.0).clamp(0.0, 1.0);
    final lift = switch (stage) {
      0 => 0.0,
      1 => local,
      _ => _triangleHeight(local, index),
    };
    final scale = stage == 2 ? 1.0 + 0.22 * _triangleBump(local, index) : 1.0;

    return Transform.translate(
      offset: Offset(0, -lift * widget.size * 0.42),
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: widget.size * 0.3,
          height: widget.size * 0.3,
          decoration: BoxDecoration(
            color: widget.color ?? KoruColors.inkFaint,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  /// The middle dot rises highest and the outer two lower, which is what makes
  /// three dots read as a triangle rather than as a line.
  double _triangleHeight(double t, int index) {
    final phase = ((t + index * 0.16) % 1.0);
    final arc = math.sin(phase * math.pi);
    return switch (index) {
      1 => arc,
      _ => arc * 0.45,
    };
  }

  double _triangleBump(double t, int index) {
    final phase = ((t + index * 0.16) % 1.0);
    return math.sin(phase * math.pi);
  }
}