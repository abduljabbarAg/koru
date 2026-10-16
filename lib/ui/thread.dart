import 'package:flutter/material.dart';

import '../engine.dart';
import '../theme.dart';
import 'marks.dart';
import 'surfaces.dart';

/// One message in the thread.
///
/// The bubble was written out inside the chat screen, where there was no way to
/// get at it from anywhere else and no way to test it without a whole
/// conversation behind it. It is the most-repeated object in the app and the one
/// that was least specified, which is why two rounds of replies had ended up
/// with a 330-pixel cap hard-coded, a shadow that made them look pasted on, and
/// a tail corner that pointed the wrong way on one of the two sides.
///
/// Two rules hold it together. The tail corner sits on the corner nearest the
/// sender, so the reader's eye is led to who is speaking; and the two sides are
/// made from the same padding and the same radius as each other, so the thread
/// reads as one geometry rather than two.
class KoruBubble extends StatelessWidget {
  const KoruBubble({
    super.key,
    required this.child,
    required this.mine,
    this.width,
  });

  /// The message. Brings its own internal layout; this brings the shape.
  final Widget child;

  /// True for the person asking, false for Koru.
  final bool mine;

  /// Overrides the width cap. Normally null, and the bubble takes what a phone
  /// can give it.
  final double? width;

  /// How much of the thread's width one turn may take.
  ///
  /// Not a fixed number of pixels: a bubble that is a fixed width on a wide
  /// phone looks like a column of stamps, and the same constant on a narrow one
  /// clips the longest line anybody sends.
  static double maxWidthFor(BuildContext context) =>
      (MediaQuery.sizeOf(context).width - KoruSpace.gutter * 2) * 0.84;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width ?? maxWidthFor(context)),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: KoruSpace.lg,
            vertical: KoruSpace.md,
          ),
          decoration: BoxDecoration(
            // The user's own turn is filled and lifts; Koru's is the surface
            // itself with a hairline. A shadow on both sides makes every
            // exchange look like a stack of cards.
            color: mine ? KoruColors.leaf : KoruColors.surface,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(KoruRadius.bubble),
              topRight: const Radius.circular(KoruRadius.bubble),
              bottomLeft: Radius.circular(mine ? KoruRadius.bubble : KoruSpace.xs),
              bottomRight: Radius.circular(mine ? KoruSpace.xs : KoruRadius.bubble),
            ),
            border: mine ? null : Border.fromBorderSide(KoruBorders.hairline()),
            boxShadow: mine ? KoruElevation.low : KoruElevation.none,
          ),
          child: DefaultTextStyle.merge(
            style: KoruType.bodyStrong.copyWith(
              color: mine ? KoruColors.onAccent : KoruColors.ink,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// The line above a Koru reply: who answered, why, and when.
///
/// In the badge's own row rather than a row of its own, because a line per
/// message is what made a long thread grow tall enough to push an approval card
/// below the fold.
class KoruMessageMeta extends StatelessWidget {
  const KoruMessageMeta({
    super.key,
    this.why,
    this.clock,
    this.leading,
    this.badge,
  });

  /// The badge naming the engine. Null when there is no engine to name yet.
  final Widget? badge;

  /// One line of reasoning, clipped to a single line.
  final String? why;

  /// The time, already formatted.
  final String? clock;

  /// Anything to the left of the badge.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: KoruSpace.xsm, left: KoruSpace.xxs),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: KoruSpace.xsm),
          ],
          if (badge != null) badge!,
          if (why != null) ...[
            const SizedBox(width: KoruSpace.sm),
            Expanded(
              child: Text(
                why!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: KoruType.meta,
              ),
            ),
          ],
          if (clock != null) ...[
            const SizedBox(width: KoruSpace.xsm),
            Text(clock!, style: KoruType.micro),
          ],
        ],
      ),
    );
  }
}

/// Says which engine answered, and is how the engine is changed.
///
/// The whole point of the app is that you can see where an answer came from, and
/// a local model is slow enough that an unexplained pause would look like a hang.
///
/// Tappable, because the badge is the only place on this screen that knows which
/// engine is selected and the answer to "who is answering" is the first question
/// most people have once they have asked one. Reaching Settings to change it made
/// the badge a label; making it the control is what makes it the answer.
///
/// Honest about a starting engine, which is the part that has to be right: a pill
/// saying a model is on this phone while it is still being copied out of the APK
/// is the one thing this widget must never say, because the person acts on it.
class KoruEngineBadge extends StatelessWidget {
  const KoruEngineBadge({
    super.key,
    required this.engine,
    this.tokensPerSecond,
    this.starting = false,
    this.progress,
    this.failed = false,
    this.onTap,
  });

  final KoruEngine? engine;
  final double? tokensPerSecond;

  /// The engine is being brought up right now.
  ///
  /// Only consulted for the on-device engine: the other two have nothing to
  /// start, so a "starting" line on either of them would be noise.
  final bool starting;

  /// How far the start has got, 0 to 100, while it is in one.
  final int? progress;

  /// The last attempt to start it did not work.
  final bool failed;

  /// Opens the switcher. Null leaves the pill as a label, which is what a badge
  /// on a message nobody is choosing anything needs to be.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final engine = this.engine;
    if (engine == null) return const SizedBox.shrink();

    final speed = tokensPerSecond;
    final pill = switch (engine) {
      // The three states that are not "running" come first inside this case,
      // because a start that failed has already been through the branch that
      // reported it starting, and a stale progress value must not keep a dead
      // engine looking like it is on its way up.
      KoruEngine.onDevice => KoruPill(
          label: switch ((failed, starting, progress)) {
            (true, _, _) => 'THIS PHONE  NOT RUNNING',
            (false, true, final int percent?) => 'THIS PHONE  $percent%',
            (false, true, _) => 'THIS PHONE  STARTING',
            _ => speed == null
                ? 'MODEL ON THIS PHONE'
                : 'THIS PHONE  ${speed.toStringAsFixed(1)} TOK/S',
          },
          color: failed ? KoruColors.clay : KoruColors.leaf,
          background: failed ? KoruColors.claySoft : KoruColors.leafSoft,
          icon: Icons.memory_rounded,
        ),
      KoruEngine.cloud => KoruPill(
          label: 'CLOUD MODEL',
          color: KoruColors.gold,
          background: KoruColors.goldSoft,
          icon: Icons.cloud_outlined,
        ),
      KoruEngine.builtIn => KoruPill(
          label: 'FROM YOUR RECORDS',
          color: KoruColors.leaf,
          background: KoruColors.leafSoft,
          icon: Icons.storage_rounded,
        ),
    };

    final tap = onTap;
    if (tap == null) return pill;

    // The chevron is the affordance. A pill that looks like a label and opens
    // something is how a control ends up being a label for six months.
    return Semantics(
      button: true,
      label: 'Change who answers',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: tap,
          borderRadius: BorderRadius.circular(KoruRadius.pill),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: KoruSpace.xxs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                pill,
                Icon(
                  Icons.expand_more_rounded,
                  size: KoruSize.iconSm,
                  color: KoruColors.inkFaint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The engine warming up, or having failed to.
///
/// Full-bleed rather than a card, because it sits between the thread and the
/// composer and is about this screen rather than part of it. It is the one place
/// the app interrupts a conversation, so it earns the tint but not a shadow.
class KoruEngineBanner extends StatelessWidget {
  const KoruEngineBanner({super.key, this.progress, this.problem});

  final int? progress;
  final String? problem;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    if (p == null && problem == null) return const SizedBox.shrink();
    final failed = p == null;
    final tone = failed ? KoruTones.clay : KoruTones.leaf;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: KoruSpace.gutter,
        vertical: KoruSpace.md,
      ),
      color: tone.fill,
      child: Row(
        children: [
          if (!failed)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: tone.ink,
              ),
            )
          else
            Icon(Icons.error_outline_rounded, size: KoruSize.iconSm, color: tone.ink),
          const SizedBox(width: KoruSpace.sm),
          Expanded(
            child: Text(
              failed
                  ? 'The on-device model did not start. $problem'
                  : 'Waking the local model up, $p%. You can carry on in the '
                      'meanwhile.',
              style: KoruType.bodyCompactStrong,
            ),
          ),
        ],
      ),
    );
  }
}

/// The composer: one field and one button, pinned to the bottom of the thread.
///
/// While an answer is being written the same button stops it, rather than sitting
/// greyed out. A disabled button for fifteen seconds is the app looking busy; a
/// stop square is the app offering a way out. Keeping both states in one control
/// is also what stops the layout moving when a reply starts and finishes.
class KoruComposer extends StatelessWidget {
  const KoruComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  /// True while a reply is arriving, which turns the button into a stop.
  final bool busy;

  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    // The home indicator's inset, not the keyboard's: the Scaffold has already
    // given back the height the keyboard took, so adding the inset here again
    // would push the composer twice as far as it needs to go.
    final safe = MediaQuery.paddingOf(context).bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(
        KoruSpace.md,
        KoruSpace.sm,
        KoruSpace.md,
        safe > 0 ? safe : KoruSpace.sm,
      ),
      decoration: BoxDecoration(
        color: KoruColors.cream,
        border: Border(top: BorderSide(color: KoruColors.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              style: KoruType.bodyStrong,
              decoration: InputDecoration(
                hintText: 'Ask anything...',
                hintStyle: KoruType.bodyStrong.copyWith(color: KoruColors.inkFaint),
                fillColor: KoruColors.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: KoruSpace.lg,
                  vertical: KoruSpace.md,
                ),
              ),
            ),
          ),
          const SizedBox(width: KoruSpace.sm),
          AnimatedContainer(
            duration: KoruMotion.quick,
            curve: KoruMotion.easeOut,
            width: KoruSize.touch,
            height: KoruSize.touch,
            decoration: BoxDecoration(
              color: busy ? KoruColors.clay : KoruColors.leaf,
              borderRadius: BorderRadius.circular(KoruRadius.field),
              boxShadow: KoruElevation.pressed,
            ),
            child: IconButton(
              icon: Icon(
                busy ? Icons.stop_rounded : Icons.arrow_upward_rounded,
                color: KoruColors.onAccent,
                size: busy ? 26 : 22,
              ),
              onPressed: busy ? onStop : onSend,
              tooltip: busy ? 'Stop' : 'Send',
            ),
          ),
        ],
      ),
    );
  }
}

/// A way back to the newest turn while an answer is arriving.
///
/// Only shown when the reader is actually scrolled up. Following a stream by
/// dragging is the normal way to read back through a long answer, so a control
/// that is always present would be in the way of the thread it sits over.
class KoruJumpToNewest extends StatelessWidget {
  const KoruJumpToNewest({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: KoruColors.surface,
        shape: BoxShape.circle,
        border: Border.fromBorderSide(KoruBorders.hairline()),
        boxShadow: KoruElevation.raised,
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          // 24 plus the icon is the smallest comfortable target, and this is a
          // control people hit with a thumb while reading one-handed.
          child: Padding(
            padding: const EdgeInsets.all(KoruSpace.md),
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 22,
              color: KoruColors.inkSoft,
            ),
          ),
        ),
      ),
    );
  }
}

/// The line that says where a run of messages starts.
///
/// A conversation that crosses midnight is two conversations, and without a
/// marker the reader scrolls back through an afternoon and cannot tell where
/// yesterday ended. It is a hairline either side of a small label rather than a
/// full-width band, so it separates without becoming a section the eye stops
/// on, and it is the one element in the thread allowed to break the column: it
/// spans the thread while every message beside it is indented to its own side.
class KoruThreadDivider extends StatelessWidget {
  const KoruThreadDivider({super.key, required this.label});

  /// "Today", "Yesterday", or the date.
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: KoruSpace.xs, bottom: KoruSpace.lg),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: KoruSpace.md),
            child: Text(label.toUpperCase(), style: KoruType.label),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}