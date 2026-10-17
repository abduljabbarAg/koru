import 'package:flutter/material.dart';

import '../mascot/mascot.dart';
import '../theme.dart';
import 'surfaces.dart';

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
                    padding: const EdgeInsets.only(bottom: KoruSpace.sm),
                  ),
                Text(title, style: KoruType.display),
                if (subtitle != null) ...[
                  const SizedBox(height: KoruSpace.sm),
                  Text(subtitle!, style: KoruType.bodyStrong),
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

/// The mark, for the places with no room to animate it.
class KoruMark extends StatelessWidget {
  const KoruMark({super.key, this.size = 28});

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

/// The bar that shows how far through a flow the reader is.
///
/// Onboarding had one, and it was a row of rectangles built inline against a
/// `margin` that was the only place in the app using `sm - 2`. Any second flow
/// would have copied it. The bar is also the only progress indicator in the app
/// that shows a count as well as a position, so the two never disagree.
class KoruStepBar extends StatelessWidget {
  const KoruStepBar({
    super.key,
    required this.step,
    required this.steps,
    this.height = 4,
  });

  /// Zero-based index of the page being shown.
  final int step;

  final int steps;

  final double height;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < steps; i++) ...[
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(height),
              child: AnimatedContainer(
                duration: KoruMotion.quick,
                curve: KoruMotion.easeOut,
                height: height,
                color: i <= step ? KoruColors.leaf : KoruColors.line,
              ),
            ),
          ),
          if (i != steps - 1) const SizedBox(width: KoruSpace.xsm),
        ],
      ],
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


/// The chrome every sheet in the app is built on: a grab handle, a title, one
/// line of context, and a body that scrolls.
///
/// Four sheets — new client, new project, change entry, edit message — each
/// drew their own. This is the one they all draw now, so a sheet opened from
/// Projects looks like a sheet opened from Business.
///
/// The surface is painted here rather than left to the sheet behind it, and
/// that is a bug fixed rather than a style chosen. The sheet is opened
/// transparent, so nothing was painted under the content at all: the engine
/// switcher drew its white tiles straight onto the cream chat behind it, which
/// is two near-identical colours on top of each other and reads as a sheet that
/// failed to render. The sheet owns its own background, its own top edge and its
/// own shadow, so it is a surface wherever it is opened from.
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: KoruColors.cream,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(KoruRadius.sheet),
        ),
        // A hairline along the top edge is what separates the sheet from the
        // page on a light palette, where the two are close to the same colour.
        border: Border(top: KoruBorders.hairline()),
        boxShadow: KoruElevation.raised,
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: KoruSpace.xl,
          right: KoruSpace.xl,
          top: KoruSpace.md,
          bottom: KoruSpace.xl + MediaQuery.viewInsetsOf(context).bottom,
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
                  borderRadius: BorderRadius.circular(KoruRadius.pill),
                ),
              ),
            ),
            if (title != null) ...[
              Text(title!, style: KoruType.sheetTitle),
              const SizedBox(height: KoruSpace.xs),
            ],
            if (subtitle != null)
              Text(subtitle!, style: KoruType.bodySmall),
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
    // The body paints its own surface, its own top edge and its own shadow, so
    // the sheet needs no background of its own and cannot be left transparent
    // by the next caller that forgets one.
    backgroundColor: KoruColors.nothing,
    barrierColor: KoruColors.shadow,
    builder: (ctx) => KoruSheetBody(
      title: title,
      subtitle: subtitle,
      child: builder(ctx),
    ),
  );
}

/// The one way this app says something and forgets it.
///
/// Built here rather than at each call site so the shape is the same everywhere,
/// and so a screen that needs to say something does not have to know how a snack
/// bar is styled in order to say it.
void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: KoruColors.ink,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(KoruRadius.field)),
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
          const SizedBox(width: KoruSpace.xs),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(
                KoruSpace.lg,
                KoruSpace.md,
                KoruSpace.mdl,
                KoruSpace.md,
              ),
              decoration: BoxDecoration(
                color: KoruColors.surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(KoruSpace.xs),
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
                    padding: const EdgeInsets.only(
                      top: KoruSpace.xxs,
                      right: KoruSpace.sm,
                    ),
                    child: Icon(
                      Icons.format_quote_rounded,
                      size: KoruSize.iconSm,
                      color: KoruColors.inkFaint,
                    ),
                  ),
                  Expanded(
                    child: Text(text, style: KoruType.bodyCompactStrong),
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