/// The small marks a row or a card carries: an icon in a tinted square, a
/// status pill, a bar, a meter.
///
/// Separate from the surfaces they sit on because these are the objects that
/// get repeated most often and varied most. Four progress bars had two heights
/// and two track colours between them, and three row actions were eighteen
/// pixels in one place and nineteen in another — differences nobody can name and
/// everybody can see.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

/// A rounded progress track.
///
/// Replaces the four hand-built `ClipRRect` + `LinearProgressIndicator` pairs,
/// which between them had two heights, two track colours and one square corner.
class KoruProgressBar extends StatelessWidget {
  const KoruProgressBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 6,
  });

  /// Zero to one.
  final double value;

  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Stack(
        children: [
          Container(height: height, color: KoruColors.surfaceAlt),
          FractionallySizedBox(
            widthFactor: value.clamp(0.0, 1.0),
            child: Container(height: height, color: color),
          ),
        ],
      ),
    );
  }
}

/// A segmented meter: one slot per unit, filled to the count.
///
/// A continuous bar answers "roughly how much"; this answers "how many", which
/// is what a capacity question is actually about. Four of them were built by hand
/// with four different heights and two different gap widths.
class KoruSegmentMeter extends StatelessWidget {
  const KoruSegmentMeter({
    super.key,
    required this.filled,
    required this.total,
    required this.color,
    this.empty,
    this.height = 6,
  });

  final int filled;
  final int total;
  final Color color;

  /// The colour of the slots that are not filled. Defaults to the surface, which
  /// is right inside a tinted card.
  final Color? empty;

  final double height;

  @override
  Widget build(BuildContext context) {
    final slots = total.clamp(1, 20);
    return Row(
      children: [
        for (var i = 0; i < slots; i++) ...[
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == slots - 1 ? 0 : KoruSpace.xs),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(height),
                child: Container(
                  height: height,
                  color: i < filled ? color : (empty ?? KoruColors.surfaceAlt),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A small tinted square of icon that says what kind of thing a row is about.
///
/// The colour pair comes from the caller rather than being decided inside,
/// because the same icon means different things on different screens and the
/// palette has already been measured for contrast on both brightnesses.
class KoruIconBadge extends StatelessWidget {
  const KoruIconBadge({
    super.key,
    required this.icon,
    required this.color,
    required this.background,
    this.size = KoruSize.badge,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, size: size * 0.5, color: color),
    );
  }
}

/// Small pill used for statuses and routing badges.
class KoruPill extends StatelessWidget {
  const KoruPill({
    super.key,
    required this.label,
    required this.color,
    required this.background,
    this.icon,
  });

  final String label;
  final Color color;
  final Color background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KoruSpace.sml,
        vertical: KoruSpace.xs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(KoruRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: KoruSize.iconSm - 2, color: color),
            const SizedBox(width: KoruSpace.xs),
          ],
          Text(label, style: KoruType.badge.copyWith(color: color)),
        ],
      ),
    );
  }
}
