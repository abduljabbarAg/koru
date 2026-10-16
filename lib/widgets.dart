import 'package:flutter/material.dart';

import 'handoff.dart';
import 'mascot/mascot.dart';
import 'proposed_write.dart';
import 'theme.dart';

/// A colour pair from the palette, as a tone.
///
/// Two jobs, done once: the accent that carries meaning and the soft fill it
/// sits on. The pairing is measured in `test/theme_test.dart`, so a pair cannot
/// be introduced that does not hold up on both brightnesses.
class KoruTones {
  /// Settled, correct, running.
  static ({Color ink, Color fill}) get leaf =>
      (ink: KoruColors.leaf, fill: KoruColors.leafSoft);

  /// Late, overdue, wrong.
  static ({Color ink, Color fill}) get clay =>
      (ink: KoruColors.clay, fill: KoruColors.claySoft);

  /// Attention without alarm: something to do today.
  static ({Color ink, Color fill}) get gold =>
      (ink: KoruColors.gold, fill: KoruColors.goldSoft);

  /// Nothing needs saying. The quiet grey the palette already measures.
  static ({Color ink, Color fill}) get neutral =>
      (ink: KoruColors.inkSoft, fill: KoruColors.surfaceAlt);
}

/// The card every screen is built out of.
///
/// One shape, one padding, one hairline, one shadow. Before this the app had
/// five different bordered rounded boxes per screen and a corner radius of 8 in
/// one place and 22 in another; nothing about that variation was information,
/// it was just five people reaching for a number. Now a card is a card, and a
/// screen that wants to be different says so through [accent] or
/// [background] rather than by inventing geometry.
class KoruCard extends StatelessWidget {
  const KoruCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(KoruSpace.card),
    this.onTap,
    this.accent,
    this.background,
    this.elevated = true,
  });

  /// The content. It brings its own internal spacing; this brings the edges.
  final Widget child;

  /// Inside the card. The same on every card in the app.
  final EdgeInsetsGeometry padding;

  /// Makes the whole card a control. The ripple is clipped to the corner.
  final VoidCallback? onTap;

  /// Paints the outline in this colour instead of the hairline, for a card
  /// whose colour is carrying meaning.
  final Color? accent;

  /// Paints over the surface. Used with [accent] for a tinted card.
  final Color? background;

  /// Whether the card lifts off the page.
  ///
  /// False for a card that is itself part of a list already on a card, where a
  /// second shadow would read as two nested surfaces.
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final tint = accent;
    final body = Padding(padding: padding, child: child);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background ?? KoruColors.surface,
        borderRadius: BorderRadius.circular(KoruRadius.card),
        border: Border.fromBorderSide(
          tint == null ? KoruBorders.hairline() : KoruBorders.accent(tint),
        ),
        boxShadow: elevated ? KoruElevation.low : KoruElevation.none,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(KoruRadius.card),
        child: Material(
          type: MaterialType.transparency,
          child: onTap == null ? body : InkWell(onTap: onTap, child: body),
        ),
      ),
    );
  }
}

/// A card that is making a point: a soft fill, an accent outline, an icon and
/// one line of explanation.
///
/// This is the shape that was written out by hand in six places — the overdue
/// banner, the capacity meter, the retainer panel, the engine banner, the
/// onboarding review's missing answers, the local-model warning. Each of them
/// had its own padding, its own corner radius and its own idea of how strong the
/// border should be. One component means "the app is telling you something"
/// looks the same whether it is about money, a model or a permission.
class KoruNotice extends StatelessWidget {
  const KoruNotice({
    super.key,
    required this.message,
    this.title,
    this.icon,
    this.tone,
    this.trailing,
    this.onTap,
    this.dense = false,
  });

  /// One line, or a few. Rendered in `ink`, not in the accent: the accent is
  /// already carried by the icon and the outline.
  final String message;

  /// An optional line above [message], in the accent.
  final String? title;

  /// The icon in the corner of the notice.
  final IconData? icon;

  /// The accent pair. Null is the settled green.
  final ({Color ink, Color fill})? tone;

  /// Sits at the right of the notice. A button, usually.
  final Widget? trailing;

  final VoidCallback? onTap;

  /// The tighter version, for a notice inside another card.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final pair = tone ?? KoruTones.leaf;
    return Padding(
      padding: EdgeInsets.only(bottom: dense ? KoruSpace.md : KoruSpace.lg),
      child: KoruCard(
        padding: EdgeInsets.all(dense ? KoruSpace.md + 2 : KoruSpace.lg),
        background: pair.fill,
        accent: pair.ink,
        elevated: false,
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[
              KoruIconBadge(
                icon: icon!,
                color: pair.ink,
                background: KoruColors.surface,
                size: KoruSize.badge,
              ),
              const SizedBox(width: KoruSpace.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null) ...[
                    Text(title!, style: KoruType.label.copyWith(color: pair.ink)),
                    const SizedBox(height: KoruSpace.xs + 2),
                  ],
                  Text(
                    message,
                    style: KoruType.bodyStrong.copyWith(
                      fontSize: dense ? 13.5 : 14,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: KoruSpace.sm),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

/// One row of a grouped list: a badge, a title, a line of metadata, and
/// whatever sits at the right.
///
/// Every list in the app was written as its own row widget, and they had drifted
/// apart: some padded 14, some 16, some left six pixels where an icon used to
/// be; the title was w500 in one place and w700 in another and w600 in a third.
/// This is the row, and the padding and the type are decided here once.
///
/// Rows lead with words rather than a badge, which is why the separators in a
/// [KoruSection] are indented by [KoruSpace.row] and not further.
class KoruRow extends StatelessWidget {
  const KoruRow({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.subtitleIn,
    this.accent,
  });

  /// The thing this row is about.
  final String title;

  /// The line under it: a date, a figure, where they came from.
  final String? subtitle;

  /// The same line, in the accent rather than faint, when the row is flagged.
  final Color? subtitleIn;

  /// Sits at the right of the row: the controls, or a status.
  final Widget? trailing;

  final VoidCallback? onTap;

  /// Paints the title in an accent when the row is flagged.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: KoruSpace.row,
            vertical: KoruSpace.md + 2,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: KoruType.rowTitle.copyWith(
                        color: accent ?? KoruColors.ink,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: KoruSpace.xs),
                      Text(
                        subtitle!,
                        style: KoruType.meta.copyWith(
                          color: subtitleIn ?? KoruColors.inkFaint,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: KoruSpace.sm),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A full-width row the user picks, marked in the brand colour when it is
/// chosen.
///
/// Onboarding had three of these written separately — the stage list, the work
/// list, the capacity grid — with three paddings and two different ways of
/// showing the tick. Picking something is the most-repeated gesture in the app
/// and it should look like the same gesture everywhere.
class KoruSelectableTile extends StatelessWidget {
  const KoruSelectableTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.trailing,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: KoruSpace.sm + 2),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(KoruRadius.field),
          child: AnimatedContainer(
            duration: KoruMotion.quick,
            curve: KoruMotion.easeOut,
            padding: const EdgeInsets.symmetric(
              horizontal: KoruSpace.lg,
              vertical: KoruSpace.lg - 2,
            ),
            decoration: BoxDecoration(
              color: selected ? KoruColors.leafSoft : KoruColors.surface,
              borderRadius: BorderRadius.circular(KoruRadius.field),
              border: Border.fromBorderSide(
                selected ? KoruBorders.selected() : KoruBorders.hairline(),
              ),
              boxShadow: selected ? KoruElevation.pressed : KoruElevation.none,
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: KoruSize.icon, color: KoruColors.inkSoft),
                  const SizedBox(width: KoruSpace.md),
                ],
                Expanded(
                  child: Text(
                    label,
                    style: KoruType.bodyStrong.copyWith(
                      fontSize: 16,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (trailing != null) trailing!
                else if (selected)
                  Icon(
                    Icons.check_circle_rounded,
                    size: 21,
                    color: KoruColors.leaf,
                  ),
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
            horizontal: KoruSpace.md + 2,
            vertical: dense ? KoruSpace.sm - 1 : KoruSpace.sm + 1,
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
                const SizedBox(width: KoruSpace.xs + 2),
              ],
              Text(
                label,
                style: KoruType.body.copyWith(
                  fontSize: dense ? 13 : 13.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? KoruColors.leaf : KoruColors.inkSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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

class KoruMark extends StatelessWidget {
  const KoruMark({super.key, this.size = 28});

  /// Static mark for places with no room to animate, such as a dense list row.
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: KoruColors.leaf,
        borderRadius: BorderRadius.circular(size * 0.32),
        boxShadow: KoruElevation.pressed,
      ),
      child: Icon(Icons.spa_rounded, color: KoruColors.onAccent, size: size * 0.6),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(
    this.text, {
    super.key,
    this.padding = const EdgeInsets.only(bottom: 10, left: 2),
  });

  final String text;

  /// The default nudges the label two pixels inside whatever it heads, which
  /// is what reads correctly over a card. A label with no card under it — a
  /// date line above a greeting, say — passes its own spacing instead.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Text(
        text.toUpperCase(),
        style: KoruType.label,
      ),
    );
  }
}

/// The block that opens a screen: a date line, a display line, and one
/// sentence of where things stand.
///
/// Type does the work here rather than colour or chrome. A header that is
/// decorated — gradients, banners, coloured panels — announces itself louder
/// than the list underneath it, which is exactly the wrong order for a screen
/// whose job is to be read. [eyebrow] is uppercased by [SectionLabel] so every
/// screen shouts in the same voice, and [trailing] exists for the one thing a
/// header sometimes wants beside its words, such as a face.
class KoruScreenHeader extends StatelessWidget {
  const KoruScreenHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.trailing,
  });

  /// The display line, kept sentence case: "Good morning".
  final String title;

  /// The small line above [title], such as today's date.
  final String? eyebrow;

  /// One line under [title] saying where things stand. Null leaves it out
  /// rather than reserving the space for it.
  final String? subtitle;

  /// Anything that sits to the right of the text.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: KoruSpace.xs, bottom: KoruSpace.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null)
                  SectionLabel(
                    eyebrow!,
                    padding: const EdgeInsets.only(bottom: KoruSpace.sm + 2),
                  ),
                Text(title, style: KoruType.display),
                if (subtitle != null) ...[
                  const SizedBox(height: KoruSpace.sm + 1),
                  Text(
                    subtitle!,
                    style: KoruType.bodyStrong.copyWith(
                      fontSize: 15,
                      color: KoruColors.inkSoft,
                      height: 1.45,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: KoruSpace.md),
            Padding(
              padding: const EdgeInsets.only(top: KoruSpace.xxs),
              child: trailing,
            ),
          ],
        ],
      ),
    );
  }
}

/// A titled run of rows, grouped on one surface and separated by hairlines.
///
/// Grouping is the whole point. Five bordered cards stacked eight pixels apart
/// read as five separate decisions; the same five rows behind one border, under
/// one heading, read as one list. The heading carries the explanation so a row
/// never has to, and [dividerIndent] lets the separators line up under the text
/// rather than under whatever icon leads the row.
class KoruSection extends StatelessWidget {
  const KoruSection({
    super.key,
    required this.label,
    required this.children,
    this.hint,
    this.dividerIndent = 0,
    this.action,
    this.empty,
  });

  final String label;

  /// The rows. They bring their own padding; the surface brings the border.
  final List<Widget> children;

  /// One line under the label saying what this section is for.
  final String? hint;

  /// How far the separator between two rows starts from the left edge.
  final double dividerIndent;

  /// Sits at the right of the heading. The add/edit control for the section.
  final Widget? action;

  /// Shown in place of the rows when there are none. Without it an empty
  /// section is a card with nothing in it, which looks like a bug.
  final Widget? empty;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: KoruSpace.section),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: SectionLabel(label)),
              if (action != null) action!,
            ],
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: KoruSpace.sm + 2),
              child: Text(hint!, style: KoruType.bodySmall),
            ),
          if (children.isEmpty && empty != null)
            empty!
          else if (children.isNotEmpty)
            KoruCard(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) Divider(indent: dividerIndent),
                    children[i],
                  ],
                ],
              ),
            ),
        ],
      ),
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
      padding: const EdgeInsets.fromLTRB(KoruSpace.md + 2, KoruSpace.md + 2, KoruSpace.md, KoruSpace.md + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          KoruPill(label: label, color: tint, background: tintBg),
          const SizedBox(height: KoruSpace.sm + 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: KoruType.stat),
          ),
          if (sub != null) ...[
            const SizedBox(height: KoruSpace.xs + 1),
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
              padding: const EdgeInsets.all(KoruSpace.sm + 2),
              decoration: BoxDecoration(color: tintBg, shape: BoxShape.circle),
              child: Icon(icon, size: 24, color: ink),
            ),
          const SizedBox(height: KoruSpace.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: KoruType.bodyStrong.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: KoruSpace.xs),
          Text(
            body,
            textAlign: TextAlign.center,
            style: KoruType.bodySmall.copyWith(fontSize: 13),
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

/// A gentle fade and settle the first time something appears.
///
/// The motion is doing one job: saying "this is the screen arriving". It is a
/// few pixels of rise and a crossfade on an ease-out curve, it runs once per
/// appearance rather than on every rebuild, and it stands aside completely when
/// the system has asked for reduced motion. Anything more than this reads as
/// decoration, and decoration on a work screen is noise.
class KoruSettle extends StatelessWidget {
  const KoruSettle({
    super.key,
    required this.child,
    this.duration = KoruMotion.settle,
    this.rise = 10,
  });

  final Widget child;

  final Duration duration;

  /// How far the content rises from, in logical pixels.
  final double rise;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: duration,
      curve: KoruMotion.easeOut,
      builder: (context, t, child) {
        final settled = t.clamp(0.0, 1.0);
        return Opacity(
          opacity: settled,
          child: Transform.translate(
            offset: Offset(0, (1 - settled) * rise),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// A write waiting to be approved.
///
/// Nothing reaches the database until this is tapped. That is the whole point:
/// the parser reads plain language and will occasionally read it wrongly, and
/// the cheapest possible recovery from a wrong read is seeing it before it
/// happens rather than undoing it after.
///
/// An amount can be corrected in place, because "Bilal paid 500" where 5000
/// was meant is the most likely wrong read and the easiest to fix.
class WriteCard extends StatefulWidget {
  const WriteCard({
    super.key,
    required this.write,
    required this.onApprove,
    required this.onDiscard,
    this.currency = 'AED',
  });

  final ProposedWrite write;
  final VoidCallback onApprove;
  final VoidCallback onDiscard;

  /// Shown beside the amount. Defaults so a caller that has not been updated
  /// still renders, but every real caller passes the user's currency.
  final String currency;

  @override
  State<WriteCard> createState() => _WriteCardState();
}

class _WriteCardState extends State<WriteCard> {
  late final TextEditingController _amount = TextEditingController(
    text: _suggestedAmount,
  );
  bool _busy = false;

  String? get _suggestedAmount {
    final write = widget.write;
    if (write is! ProposedPayment) return null;
    final amount = write.amount;
    // Blank stays blank. Pre-filling the outstanding balance would silently turn
    // "Bilal paid" into "Bilal paid everything he owes", which is a different
    // statement about money.
    if (amount == null) return null;
    return amount == amount.roundToDouble()
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _approve() async {
    final write = widget.write;
    if (write is! ProposedPayment) {
      widget.onApprove();
      return;
    }
    final entered = double.tryParse(_amount.text.trim());
    if (entered == null || entered <= 0) {
      setState(() {});
      return;
    }
    setState(() => _busy = true);
    widget.onApprove();
  }

  @override
  Widget build(BuildContext context) {
    final write = widget.write;
    final amountError = write is ProposedPayment &&
        (double.tryParse(_amount.text.trim()) ?? 0) <= 0;

    return Padding(
      padding: const EdgeInsets.only(top: KoruSpace.sm + 2, bottom: KoruSpace.xs),
      child: KoruCard(
        background: KoruColors.goldSoft,
        accent: KoruColors.gold,
        elevated: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KoruIconBadge(
                  icon: Icons.edit_note_rounded,
                  color: KoruColors.gold,
                  background: KoruColors.surface,
                ),
                const SizedBox(width: KoruSpace.md),
                Expanded(
                  child: Text(
                    write.summary,
                    style: KoruType.bodyStrong.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
            if (write is ProposedPayment) ...[
              const SizedBox(height: KoruSpace.md),
              TextField(
                controller: _amount,
                enabled: !_busy,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Amount received',
                  suffixText: widget.currency,
                  isDense: true,
                  errorText: amountError ? 'Enter an amount' : null,
                ),
              ),
            ],
            const SizedBox(height: KoruSpace.md),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(KoruSize.buttonInCard),
                    ),
                    onPressed: _busy || amountError ? null : _approve,
                    child: const Text('Save it'),
                  ),
                ),
                const SizedBox(width: KoruSpace.sm),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(KoruSize.buttonInCard),
                    ),
                    onPressed: _busy ? null : widget.onDiscard,
                    child: const Text('Discard'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The escalation card shown when Koru decides a person should answer.
///
/// This replaces a line of text in the chat bubble. The routing layer already
/// knew when to step aside; now there is somewhere to step aside to.
class HandoffCard extends StatelessWidget {
  const HandoffCard({super.key, required this.plan, this.onDismiss});

  final HandoffPlan plan;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final tone = plan.urgent ? KoruTones.clay : KoruTones.gold;

    return Semantics(
      liveRegion: true,
      container: true,
      label: '${plan.headline}. ${plan.body}',
      child: Padding(
        padding: const EdgeInsets.only(top: KoruSpace.sm + 2),
        child: KoruCard(
          accent: tone.ink,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  KoruIconBadge(
                    icon: plan.urgent
                        ? Icons.emergency_share_rounded
                        : Icons.pan_tool_alt_rounded,
                    color: tone.ink,
                    background: tone.fill,
                  ),
                  const SizedBox(width: KoruSpace.md),
                  Expanded(
                    child: Text(
                      plan.headline,
                      style: KoruType.bodyStrong.copyWith(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (onDismiss != null)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: onDismiss,
                      tooltip: 'Dismiss',
                    ),
                ],
              ),
              const SizedBox(height: KoruSpace.md),
              Text(plan.body, style: KoruType.body.copyWith(fontSize: 13.5)),
              const SizedBox(height: KoruSpace.md),
              ...plan.resources.map(
                (r) => Padding(
                  padding: const EdgeInsets.only(bottom: KoruSpace.sm + 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 6, right: KoruSpace.sm + 1),
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: tone.ink,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.name,
                              style: KoruType.bodyStrong.copyWith(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              r.detail,
                              style: KoruType.bodySmall.copyWith(fontSize: 12.5),
                            ),
                            Text(
                              '${r.number} - ${r.hours}',
                              style: KoruType.meta.copyWith(
                                color: tone.ink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
      padding: const EdgeInsets.symmetric(horizontal: KoruSpace.sm + 1, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(KoruRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: KoruSize.iconSm - 4, color: color),
            const SizedBox(width: KoruSpace.xs),
          ],
          Text(label, style: KoruType.badge.copyWith(color: color)),
        ],
      ),
    );
  }
}

/// The chrome every sheet in the app is built on: a grab handle, a title, one
/// line of context, and a body that scrolls.
///
/// Four sheets — new client, new project, change entry, edit message — each
/// drew their own. This is the one they all draw now, so a sheet opened from
/// Projects looks like a sheet opened from Business.
class KoruSheetBody extends StatelessWidget {
  const KoruSheetBody({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
  });

  /// The body. Brings its own internal spacing.
  final Widget child;

  /// Omitted by the one sheet that is a single field and does not need a
  /// heading of its own.
  final String? title;

  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: KoruSpace.xl,
        right: KoruSpace.xl,
        top: KoruSpace.md,
        bottom: KoruSpace.xl + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: KoruSpace.lg),
              decoration: BoxDecoration(
                color: KoruColors.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (title != null) ...[
            Text(title!, style: KoruType.sheetTitle),
            const SizedBox(height: KoruSpace.xs),
          ],
          if (subtitle != null)
            Text(
              subtitle!,
              style: KoruType.bodySmall.copyWith(fontSize: 13),
            ),
          SizedBox(height: title != null ? KoruSpace.lg : KoruSpace.xs),
          Flexible(
            child: SingleChildScrollView(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A titled sheet body used by every add/edit flow, so the five forms in the app
/// stop looking like five different apps.
Future<T?> showKoruSheet<T>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext) builder,
  String? subtitle,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: KoruColors.shadow,
    builder: (ctx) => KoruSheetBody(
      title: title,
      subtitle: subtitle,
      child: builder(ctx),
    ),
  );
}

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: KoruColors.ink,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KoruRadius.field),
      ),
    ));
}

/// Koru with a comic panel beside him.
///
/// The mascot used to be decoration. This puts him next to something he actually
/// said about the screen you are on, shaped like a comic speech balloon, so he
/// reads as a helper rather than a logo.
class KoruGuideBanner extends StatelessWidget {
  const KoruGuideBanner({
    super.key,
    required this.speech,
    this.mascotSize = 64,
    this.onTap,
  });

  /// Null means Koru has nothing to say, and nothing renders. Silence is
  /// deliberate: a mascot that speaks on every visit is noise, and people learn
  /// to ignore it, which costs the one message that would have mattered.
  final String? speech;

  final double mascotSize;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = speech;
    if (text == null || text.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: KoruSpace.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          KoruMascot(size: mascotSize, onTap: onTap),
          const SizedBox(width: KoruSpace.xs + 2),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(
                KoruSpace.lg,
                KoruSpace.md,
                KoruSpace.lg - 2,
                KoruSpace.md,
              ),
              decoration: BoxDecoration(
                color: KoruColors.surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(KoruRadius.card),
                  bottomLeft: Radius.circular(KoruRadius.card),
                  bottomRight: Radius.circular(KoruRadius.card),
                ),
                border: Border.fromBorderSide(KoruBorders.hairline()),
                boxShadow: KoruElevation.low,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1, right: KoruSpace.sm),
                    child: Icon(
                      Icons.format_quote_rounded,
                      size: KoruSize.iconSm,
                      color: KoruColors.inkFaint,
                    ),
                  ),
                  Expanded(
                    child: Text(text, style: KoruType.bodyStrong.copyWith(fontSize: 13.5)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Whole units, no decimals.
///
/// Balances are compared and summed constantly and a stray cent should never be
/// the reason two figures that are the same money look different.
String money(double v) {
  if (v.abs() >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
  if (v.abs() >= 10000) return '${(v / 1000).toStringAsFixed(0)}k';
  return v.toStringAsFixed(0);
}

/// A numbered plan, shown before anything is written.
///
/// Deliberately different from [WriteCard] rather than a variant of it. A single
/// write is one line and one decision; an import is a list, and showing twenty
/// rows behind a card meant for one makes the size of the change invisible until
/// after it has happened. So the steps are numbered, visible, and the lines that
/// could not be read are on the card too.
///
/// Naming the unreadable lines is the point. A list of twenty that silently
/// becomes seventeen is the same failure as the Business page reading zero,
/// only slower to notice.
class PlanCard extends StatelessWidget {
  const PlanCard({
    super.key,
    required this.write,
    required this.onApprove,
    required this.onDiscard,
    this.busy = false,
  });

  final ProposedPlan write;
  final VoidCallback onApprove;
  final VoidCallback onDiscard;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final steps = write.steps;
    final problems = write.problems;

    return Padding(
      padding: const EdgeInsets.only(top: KoruSpace.sm + 2, bottom: KoruSpace.xs),
      child: KoruCard(
        background: KoruColors.goldSoft,
        accent: KoruColors.gold,
        elevated: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KoruIconBadge(
                  icon: Icons.playlist_add_check_rounded,
                  color: KoruColors.clay,
                  background: KoruColors.surface,
                ),
                const SizedBox(width: KoruSpace.md),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: KoruSpace.xs + 2),
                    child: Text(
                      steps.length == 1
                          ? 'Koru wants to add one client'
                          : 'Koru wants to add ${steps.length} clients',
                      style: KoruType.bodyStrong.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: KoruSpace.md),
            // Every step, numbered. Not a summary of a summary: the user is being
            // asked to agree to twenty specific claims about money, so all twenty
            // are on the screen.
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: KoruSpace.sm - 1),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text(
                        '${i + 1}.',
                        style: KoruType.meta.copyWith(fontSize: 12.5),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        steps[i].summary,
                        style: KoruType.body.copyWith(fontSize: 13, color: KoruColors.ink),
                      ),
                    ),
                  ],
                ),
              ),
            if (problems.isNotEmpty) ...[
              const SizedBox(height: KoruSpace.xs),
              KoruCard(
                padding: const EdgeInsets.all(KoruSpace.md),
                background: KoruColors.claySoft,
                accent: KoruColors.clay,
                elevated: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${problems.length} line${problems.length == 1 ? '' : 's'} I could not read',
                      style: KoruType.bodyStrong.copyWith(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: KoruSpace.xs),
                    for (final p in problems.take(6))
                      Padding(
                        padding: const EdgeInsets.only(bottom: KoruSpace.xxs),
                        child: Text(
                          '"${p.text}" - ${p.reason}',
                          style: KoruType.meta.copyWith(
                            fontSize: 11.5,
                            color: KoruColors.inkSoft,
                          ),
                        ),
                      ),
                    if (problems.length > 6)
                      Text(
                        'and ${problems.length - 6} more',
                        style: KoruType.meta.copyWith(fontSize: 11.5),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: KoruSpace.md),
            Text(
              'Nothing is saved until you press Add. All of it goes in together, '
              'or none of it does.',
              style: KoruType.meta.copyWith(fontSize: 11.5, height: 1.35),
            ),
            const SizedBox(height: KoruSpace.sm + 2),
            Row(
              children: [
                if (busy)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: KoruSpace.sm + 2),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: KoruColors.clay,
                      ),
                    ),
                  )
                else ...[
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(KoruSize.buttonInCard),
                      ),
                      onPressed: onDiscard,
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: KoruSpace.sm + 2),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(KoruSize.buttonInCard),
                      ),
                      onPressed: steps.isEmpty ? null : onApprove,
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: Text(steps.length == 1 ? 'Add' : 'Add ${steps.length}'),
                    ),
                  ),
                ],
              ],
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
              style: KoruType.bodyStrong.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
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
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}