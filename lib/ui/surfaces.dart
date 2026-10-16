/// The things a screen is made of: the card, the row, the section.
///
/// A screen that wants something else reaches for a tone or an accent rather
/// than for geometry, because geometry is the one thing a reader notices as
/// inconsistency without being able to say what is wrong. The small marks live
/// in `marks.dart`, the ways of picking in `choice.dart`, and the shapes a list
/// wears while it is still loading in `states.dart`.
library;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'marks.dart';

/// A small uppercase heading.
///
/// One widget rather than a `Text` with `.toUpperCase()` written out at the
/// thirty places a heading appears, which is how eleven of them ended up with
/// letterSpacing 1 and six with 1.4.
class SectionLabel extends StatelessWidget {
  const SectionLabel(
    this.text, {
    super.key,
    this.padding = const EdgeInsets.only(bottom: KoruSpace.sml, left: 2),
  });

  final String text;

  /// The default nudges the label two pixels inside whatever it heads, which is
  /// what reads correctly over a card. A label with no card under it — a date
  /// line above a greeting, say — passes its own spacing instead.
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

/// The page padding every scrolling screen in the app uses.
///
/// Was written out at four different top values and two bottom values, which is
/// why the first thing on a screen sat at a different height depending on which
/// screen it was. One value: [KoruSpace.gutter] at the sides, a little air under
/// the bar, and [KoruSpace.tail] at the foot so nothing lands on the edge.
class KoruPagePadding extends StatelessWidget {
  const KoruPagePadding({super.key, this.bottom = KoruSpace.tail, required this.child});

  /// Clears the floating action button where there is one.
  const KoruPagePadding.aboveFab({super.key, required this.child})
      : bottom = KoruSpace.aboveFab;

  final Widget child;
  final double bottom;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
          KoruSpace.gutter,
          KoruSpace.sml,
          KoruSpace.gutter,
          bottom,
        ),
        child: child,
      );
}

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

  /// The pair for a client status. Lives here rather than in the two screens
  /// that show one, because they used to disagree: Business left a lost client
  /// on plain faint grey while the client screen gave the same status a filled
  /// pill.
  static ({Color ink, Color fill}) status(String s) => switch (s) {
        'paid' => leaf,
        'active' => gold,
        'delivered' => clay,
        'lost' => (ink: KoruColors.inkFaint, fill: KoruColors.surfaceAlt),
        _ => neutral,
      };
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
        padding: EdgeInsets.all(dense ? KoruSpace.mdl : KoruSpace.lg),
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
                    const SizedBox(height: KoruSpace.xs),
                  ],
                  Text(message, style: KoruType.bodyCompactStrong),
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
    this.body,
    this.leading,
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

  /// Anything below the title and the subtitle, at the row's own left edge.
  ///
  /// Exists because three rows needed a note or a pair of actions under their
  /// text and all three had built that space themselves, at three different
  /// offsets from the row's left edge.
  final Widget? body;

  /// Sits at the left of the title, above the row's own left edge.
  ///
  /// For the rows whose leading part is more than an icon: a calendar entry's
  /// day and time, a deadline's date. Those two rows had been built by hand
  /// around a [SizedBox], which is how a section of [KoruRow] rows ended up
  /// with one entry in it that was a different height and a different inset
  /// from the rest.
  ///
  /// Aligned to the top of the text rather than the middle of the row, because a
  /// badge centred against a two-line row floats between the two lines instead
  /// of standing beside the title it belongs to.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: KoruSpace.row,
            vertical: KoruSpace.mdl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (leading != null) ...[
                    leading!,
                    const SizedBox(width: KoruSpace.md),
                  ],
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
              if (body != null) ...[
                const SizedBox(height: KoruSpace.sml),
                body!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The small icon control at the right of a row.
///
/// A deadline row had one at eighteen pixels, the calendar had one at eighteen in
/// a different colour and the client row had one at nineteen, all three with
/// their own tooltip style. Three sizes for the same control is exactly the kind
/// of thing a reader notices without being able to name.
class KoruRowAction extends StatelessWidget {
  const KoruRowAction({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.color,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  /// Null is the quiet default; pass a tone when the action is one the row is
  /// flagging rather than offering.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: KoruSize.icon, color: color),
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
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
              padding: const EdgeInsets.only(left: 2, bottom: KoruSpace.sm),
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
