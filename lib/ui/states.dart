/// What a screen shows when it has no rows to show.
///
/// A loading shape, a failure with a way out of it, an empty section that says
/// what belongs there, and the figures a screen leads with. These are the states
/// a user meets when something is wrong or when they have just installed the
/// app, which is exactly when a screen that only ever looks right when it is
/// full of data looks cheapest.
library;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'marks.dart';
import 'surfaces.dart';

/// One figure worth looking at, with its label and its context.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.sub,
    required this.tint,
    required this.tintBg,
  });

  final String label;
  final String value;
  final String? sub;
  final Color tint;
  final Color tintBg;

  @override
  Widget build(BuildContext context) {
    return KoruCard(
      padding: const EdgeInsets.fromLTRB(
        KoruSpace.md,
        KoruSpace.mdl,
        KoruSpace.md,
        KoruSpace.mdl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          KoruPill(label: label, color: tint, background: tintBg),
          const SizedBox(height: KoruSpace.sm),
          // The figure is the reason the tile exists, so it leads: a step up
          // from the row type around it and in the tile's own colour, which is
          // how money reads as money at a glance rather than as one more number
          // in one more card.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: KoruType.metric.copyWith(color: tint)),
          ),
          if (sub != null) ...[
            const SizedBox(height: KoruSpace.xs),
            Text(
              sub!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: KoruType.meta,
            ),
          ],
        ],
      ),
    );
  }
}

/// A run of [StatTile]s across the top of a screen, spaced the same way.
///
/// The three figures on Business were laid out with a `Row`, three `Expanded`s
/// and two hand-written gaps, which is one more place for the gap to differ
/// from the gap everywhere else. Three is the most that fits at this type size
/// without the numbers truncating; the tiles themselves scale their own text
/// down rather than wrapping it, so a wide figure narrows instead of pushing
/// its neighbours around.
class KoruStatRow extends StatelessWidget {
  const KoruStatRow({super.key, required this.children, this.gap = KoruSpace.sm});

  final List<Widget> children;

  /// The gap between two tiles. One value, so a row of three and a row of two
  /// are the same distance apart.
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: KoruSpace.lg),
      // Tall enough for the tallest tile so the three cards share a baseline
      // and a bottom edge. Without it a figure with a two-line caption makes
      // its card taller than its two neighbours, which reads as a mistake even
      // though nobody can say what is wrong.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(width: gap),
              Expanded(child: children[i]),
            ],
          ],
        ),
      ),
    );
  }
}

/// The one big figure at the top of a screen, with its label and its context.
///
/// Separate from [StatTile] because a stat is one of several equal figures in a
/// row and a metric is the only number on the screen that matters. They were
/// being drawn by hand in three places with three different paddings, which is
/// why the "still owed" block on one screen started two pixels higher than the
/// equivalent block on another.
class KoruMetric extends StatelessWidget {
  const KoruMetric({
    super.key,
    required this.label,
    required this.value,
    this.sub,
    this.trailing,
  });

  final String label;
  final String value;

  /// One line under the figure saying what it is or what to do about it.
  final String? sub;

  /// Sits at the right of the figure: a count, a pill.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return KoruCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(), style: KoruType.label),
                const SizedBox(height: KoruSpace.sm),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: KoruType.metric),
                ),
                if (sub != null) ...[
                  const SizedBox(height: KoruSpace.xs),
                  Text(sub!, style: KoruType.caption),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: KoruSpace.md),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// What a screen says when there is nothing in it.
///
/// Every empty state in the app was a different height, a different icon size
/// and a different amount of padding. This one is the same everywhere: a tinted
/// disc, a title, one sentence of what to do instead, and an optional action.
class EmptyHint extends StatelessWidget {
  const EmptyHint({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.tint,
    this.tintBg,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  /// The colour of the icon, and behind it when [tintBg] is set. Both default
  /// to the quiet grey, which is right for "there is nothing here" and wrong
  /// for "you are all clear", so the caller says which.
  final Color? tint;
  final Color? tintBg;

  @override
  Widget build(BuildContext context) {
    final ink = tint ?? KoruColors.inkFaint;
    return KoruCard(
      child: Column(
        children: [
          if (tintBg == null)
            Icon(icon, size: 30, color: ink)
          else
            Container(
              padding: const EdgeInsets.all(KoruSpace.sm),
              decoration: BoxDecoration(color: tintBg, shape: BoxShape.circle),
              child: Icon(icon, size: 24, color: ink),
            ),
          const SizedBox(height: KoruSpace.md),
          Text(title, textAlign: TextAlign.center, style: KoruType.rowTitle),
          const SizedBox(height: KoruSpace.xs),
          Text(
            body,
            textAlign: TextAlign.center,
            style: KoruType.bodySmall,
          ),
          if (action != null) ...[
            const SizedBox(height: KoruSpace.lg),
            action!,
          ],
        ],
      ),
    );
  }
}

/// The quiet version of a spinner: a ring in the brand green, and one line
/// naming the work being waited on.
///
/// A bare spinner answers "is something happening" and nothing else, which on a
/// screen that lives or dies by one list is not the question. Naming the work
/// turns a wait into an explanation, and costs nothing when there is nothing
/// more to say.
class KoruLoading extends StatelessWidget {
  const KoruLoading({super.key, this.label = 'One moment'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: KoruSpace.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: KoruColors.leaf,
                backgroundColor: KoruColors.line,
              ),
            ),
            const SizedBox(height: KoruSpace.lg),
            Text(
              label,
              textAlign: TextAlign.center,
              style: KoruType.bodySmall.copyWith(letterSpacing: 0.2),
            ),
          ],
        ),
      ),
    );
  }
}

/// A failure the user can act on, rather than a database error string.
///
/// sqflite's messages are for whoever is debugging: "database or disk is full",
/// "no such table: projects". Shown to somebody who just tapped something they
/// are noise at best and alarming at worst. What they need is that it did not
/// work, and that trying again is reasonable.
class KoruErrorView extends StatelessWidget {
  const KoruErrorView({super.key, required this.onRetry, this.what = 'load this'});

  final VoidCallback onRetry;
  final String what;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KoruSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(KoruSpace.md),
              decoration: BoxDecoration(
                color: KoruColors.surfaceAlt,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.cloud_off_rounded, size: 26),
            ),
            const SizedBox(height: KoruSpace.md),
            Text(
              'Could not $what',
              textAlign: TextAlign.center,
              style: KoruType.rowTitleLarge,
            ),
            const SizedBox(height: KoruSpace.sm),
            Text(
              'Nothing was changed. This usually clears on its own.',
              textAlign: TextAlign.center,
              style: KoruType.body,
            ),
            const SizedBox(height: KoruSpace.lg),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: KoruSize.icon),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The shape a list has while it is still being fetched.
///
/// A spinner inside a section says "wait" and says nothing about what is
/// coming, so the reader watches the page change under them: a ring appears, it
/// is replaced by five bordered cards, and the whole screen moves twice. The
/// skeleton is the list's own geometry drawn in the palette's quiet grey, so
/// the only thing that changes when the data lands is that the grey becomes
/// words.
///
/// The row's own padding and badge measurement, deliberately, so the card that
/// replaces it is the same width and sits at the same place on the page. The
/// bars themselves are shorter than the text they stand in for: a placeholder
/// drawn to the exact height of a finished row reads as content, and the point
/// is that it plainly is not.
class KoruListSkeleton extends StatelessWidget {
  const KoruListSkeleton({super.key, this.rows = 3, this.badge = true});

  /// How many rows to draw. Two for a section that usually holds one or two.
  final int rows;

  /// False for a list whose rows lead with words rather than a badge, which is
  /// why the leading square is optional rather than always on.
  final bool badge;

  @override
  Widget build(BuildContext context) {
    return KoruCard(
      padding: const EdgeInsets.symmetric(horizontal: KoruSpace.row),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < rows; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: KoruSpace.mdl),
              child: Row(
                children: [
                  if (badge) ...[
                    _block(KoruSize.badge, KoruSize.badge),
                    const SizedBox(width: KoruSpace.md),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _bar(0.62, 12),
                        const SizedBox(height: KoruSpace.md),
                        _bar(0.34, 9),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// One of the placeholder bars. A fixed height rather than a font size: the
  /// point is that it sits on the same baseline as the text it replaces.
  Widget _bar(double widthFactor, double height) => FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: widthFactor,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: KoruColors.surfaceAlt,
            borderRadius: BorderRadius.circular(KoruRadius.pill),
          ),
        ),
      );

  /// The leading square, on the row's badge measurement.
  Widget _block(double w, double h) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: KoruColors.surfaceAlt,
          borderRadius: BorderRadius.circular(w * 0.32),
        ),
      );
}