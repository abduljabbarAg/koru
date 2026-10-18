import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../mascot/mascot.dart';
import '../theme.dart';
import 'surfaces.dart';

/// The moment money lands.
///
/// Recording a payment is the one action in this app that is unambiguously
/// good news, and it used to end in a grey snackbar sentence. It now ends in a
/// fountain: Koru cheers, the amount rises into view in the green that means
/// received, and the phone gives one soft thump. No dialog, no button to
/// dismiss — it is gone in a second and a half, which is long enough to feel
/// and short enough to never be in the way.
///
/// An overlay rather than a screen or a snackbar, so it can appear whatever
/// surface the payment was recorded from — the money list, a client page, a
/// sheet — without any of them owning it.
void celebrateMoneyIn(
  BuildContext context, {
  required String amount,
  String? caption,
}) {
  // Felt on every platform, even when the overlay is not available.
  HapticFeedback.mediumImpact();
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _MoneyInBurst(
      amount: amount,
      caption: caption,
      onDone: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

/// The burst itself: a card that fades up, pops, and fades away.
class _MoneyInBurst extends StatefulWidget {
  const _MoneyInBurst({
    required this.amount,
    this.caption,
    required this.onDone,
  });

  final String amount;
  final String? caption;

  /// Called once, when the animation has finished and the entry can go.
  final VoidCallback onDone;

  @override
  State<_MoneyInBurst> createState() => _MoneyInBurstState();
}

class _MoneyInBurstState extends State<_MoneyInBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  final _mascot = KoruMascotController();

  @override
  void initState() {
    super.initState();
    _mascot.cheer();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Up quickly, hold, go quietly. A burst that lingers stops being a reward
    // and starts being a dialog.
    final fade = _c.drive(
      TweenSequence<double>([
        TweenSequenceItem(
          tween: Tween(begin: 0.0, end: 1.0)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 16,
        ),
        TweenSequenceItem(tween: ConstantTween(1.0), weight: 64),
        TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 0.0)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: 20,
        ),
      ]),
    );
    final pop = _c.drive(
      Tween(begin: 0.86, end: 1.0).chain(CurveTween(curve: Curves.easeOutBack)),
    );

    return IgnorePointer(
      child: Align(
        alignment: const Alignment(0, -0.2),
        child: FadeTransition(
          opacity: fade,
          child: ScaleTransition(
            scale: pop,
            child: KoruCard(
              accent: KoruColors.leaf,
              padding: const EdgeInsets.symmetric(
                horizontal: KoruSpace.xl,
                vertical: KoruSpace.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  KoruMascot(
                    size: 64,
                    controller: _mascot,
                    semanticLabel: 'Koru, celebrating',
                  ),
                  const SizedBox(height: KoruSpace.sm),
                  Text(
                    widget.amount,
                    style: KoruType.stat.copyWith(color: KoruColors.leaf),
                  ),
                  const SizedBox(height: KoruSpace.xxs),
                  Text(widget.caption ?? 'received', style: KoruType.caption),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
