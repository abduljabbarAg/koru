/// Every way the app asks the reader to pick one thing.
///
/// Six sets of these existed — the kind of a project, the currencies, the help
/// topics, the project filter, the questions the chat offers, the onboarding
/// capacity tiles — and they were six different controls at five different
/// heights, with five different ways of drawing the tick. Picking something is
/// the most-repeated gesture in the app, so it looks like the same gesture
/// everywhere: a pill for a run of them, a tile for a tall one, and a run of
/// either given a label and a place to sit.
library;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'surfaces.dart';

/// A full-width row the user picks, marked in the brand colour when it is
/// chosen.
///
/// Onboarding had three of these written separately — the stage list, the work
/// list, the capacity grid — with three paddings and two different ways of
/// showing the tick. Picking something is the most-repeated gesture in the app
/// and it should look like the same gesture everywhere.
///
/// Chosen is marked three ways, not one. The fill alone fails the reader who
/// cannot separate the two tints, on either brightness, and a hairline alone is
/// invisible on the surface the tile sits on. So the chosen row gets the tint,
/// a heavier outline, a tick, and the title in the accent — the tick being the
/// part that carries it with colour switched off entirely.
class KoruSelectableTile extends StatelessWidget {
  const KoruSelectableTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.trailing,
    this.blurb,
    this.large = false,
  });

  /// The same tile with a bigger, centred label: a set of small numbers.
  ///
  /// A variant rather than a separate widget, because the onboarding capacity
  /// question had been given its own implementation that differed from this one
  /// in padding, corner radius, border weight and how the tick was drawn.
  const KoruSelectableTile.large({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  })  : icon = null,
        trailing = null,
        blurb = null,
        large = true;

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Widget? trailing;

  /// One line under the label saying what picking this actually gets you.
  ///
  /// There because a row that names a choice without saying what it costs is how
  /// somebody picks one and only afterwards finds out what it takes — a company
  /// with twenty models is a different promise from one with three.
  final String? blurb;

  /// Centres a bigger label and drops the tick: the number is the whole mark.
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: KoruSpace.sm),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(KoruRadius.field),
          child: AnimatedContainer(
            duration: KoruMotion.quick,
            curve: KoruMotion.easeOut,
            padding: large
                ? const EdgeInsets.symmetric(
                    horizontal: KoruSpace.md,
                    vertical: KoruSpace.xl,
                  )
                : const EdgeInsets.symmetric(
                    horizontal: KoruSpace.lg,
                    vertical: KoruSpace.mdl,
                  ),
            alignment: large ? Alignment.center : null,
            decoration: BoxDecoration(
              color: selected ? KoruColors.leafSoft : KoruColors.surface,
              borderRadius: BorderRadius.circular(KoruRadius.field),
              border: Border.fromBorderSide(
                selected ? KoruBorders.selected() : KoruBorders.hairline(),
              ),
              boxShadow: selected ? KoruElevation.pressed : KoruElevation.none,
            ),
            child: Row(
              mainAxisAlignment:
                  large ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: KoruSize.icon,
                    color: selected ? KoruColors.leaf : KoruColors.inkSoft,
                  ),
                  const SizedBox(width: KoruSpace.md),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: large
                        ? CrossAxisAlignment.center
                        : CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        textAlign:
                            large ? TextAlign.center : TextAlign.start,
                        style: large
                            ? KoruType.dialogTitle.copyWith(
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: selected ? KoruColors.leaf : KoruColors.ink,
                              )
                            : KoruType.rowTitle.copyWith(
                                fontWeight:
                                    selected ? FontWeight.w600 : FontWeight.w500,
                                color: selected ? KoruColors.leaf : KoruColors.ink,
                              ),
                      ),
                      if (blurb != null && !large)
                        Padding(
                          padding: const EdgeInsets.only(top: KoruSpace.xxs),
                          child: Text(
                            blurb!,
                            style: KoruType.caption.copyWith(height: 1.35),
                          ),
                        ),
                    ],
                  ),
                ),
                // The tick comes before whatever else the row says rather than
                // instead of it. A chosen provider that also carries a status
                // used to show the status and lose the tick, which is the one
                // row on the sheet a reader could not tell was the answer.
                if (selected && !large) ...[
                  Icon(
                    Icons.check_circle_rounded,
                    size: KoruSize.icon,
                    color: KoruColors.leaf,
                  ),
                  if (trailing != null) const SizedBox(width: KoruSpace.sm),
                ],
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The pill version of [KoruSelectableTile].
///
/// Six sets of these existed — currencies, help topics, payment terms, the
/// project filter, the chat's suggested questions — and they were five different
/// chips with five different heights.
class KoruSelectablePill extends StatelessWidget {
  const KoruSelectablePill({
    super.key,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.icon,
    this.dense = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;
  final IconData? icon;

  /// The tighter version for a filter bar that already has a label above it.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KoruRadius.pill),
        child: AnimatedContainer(
          duration: KoruMotion.quick,
          curve: KoruMotion.easeOut,
          padding: EdgeInsets.symmetric(
            horizontal: KoruSpace.md,
            vertical: dense ? KoruSpace.xsm : KoruSpace.sm,
          ),
          decoration: BoxDecoration(
            color: selected ? KoruColors.leafSoft : KoruColors.surface,
            borderRadius: BorderRadius.circular(KoruRadius.pill),
            border: Border.fromBorderSide(
              selected ? KoruBorders.selected() : KoruBorders.hairline(),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: KoruSize.iconSm,
                  color: selected ? KoruColors.leaf : KoruColors.inkFaint,
                ),
                const SizedBox(width: KoruSpace.xs),
              ],
              // Flexible, so a label too long for the width wraps instead of
              // overflowing the row. These labels are the questions the reader
              // is being offered and the currencies they can pick; a chip that
              // quietly cuts one of them in half is worse than a chip that is
              // two lines tall. The longest suggestion does not fit on one line
              // on a small phone, and it used to take the thread with it.
              Flexible(
                child: Text(
                  label,
                  style: (dense ? KoruType.bodySmall : KoruType.caption)
                      .copyWith(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? KoruColors.leaf : KoruColors.inkSoft,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A row of pills above a list, wrapping onto a second line when it has to.
///
/// The filter on Projects, the suggested questions on the chat's opening
/// screen, the currencies and the help topics during onboarding: four sets of
/// the same control, written out four times with three different gaps and two
/// different bottom margins, which is why a filter bar on one screen sat a
/// different distance from its list than the one on the next.
///
/// One definition also means the pills in a filter and the pills in a form are
/// the same size of thing, so a row of choices never changes height depending
/// on which screen it is on.
class KoruFilterBar extends StatelessWidget {
  const KoruFilterBar({
    super.key,
    required this.children,
    this.alignment = WrapAlignment.start,
    this.padding = const EdgeInsets.only(bottom: KoruSpace.lg),
  });

  /// The pills, or anything else the caller wants in the run.
  final List<Widget> children;

  /// Start, or centre. Centred is for the chat's opening suggestions, where the
  /// run belongs to a centred block rather than to the left edge of a page.
  final WrapAlignment alignment;

  /// Overridden where the bar is not above a list — inside a card, or under a
  /// heading that already owns the space beneath it.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Wrap(
        spacing: KoruSpace.sm,
        runSpacing: KoruSpace.sm,
        alignment: alignment,
        children: children,
      ),
    );
  }
}
/// A named run of pills inside a card, for a set of choices that is part of a
/// form rather than a filter over a list.
///
/// The filter bar with a heading, so the label has a shape of its own and the
/// run below it has an edge to sit on. Used wherever a page asks for several
/// things out of a fixed set.
class KoruChoiceGroup extends StatelessWidget {
  const KoruChoiceGroup({
    super.key,
    required this.label,
    required this.children,
    this.caption,
  });

  /// Above the run. Small and quiet; the choices themselves are the content.
  final String label;

  final List<Widget> children;

  /// One line under the label saying how many may be picked.
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(label, padding: const EdgeInsets.only(bottom: KoruSpace.xs)),
        if (caption != null)
          Padding(
            padding: const EdgeInsets.only(bottom: KoruSpace.sm),
            child: Text(caption!, style: KoruType.caption),
          ),
        Wrap(
          spacing: KoruSpace.sm,
          runSpacing: KoruSpace.sm,
          children: children,
        ),
      ],
    );
  }
}
