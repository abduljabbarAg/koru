import 'package:flutter/material.dart';

import '../engine.dart';
import '../theme.dart';
import 'marks.dart';
import 'surfaces.dart';

/// How wide the engine control's two lines may be before they give way.
///
/// Sized so the control still leaves room for the app bar's own actions on the
/// narrowest phone this runs on, which is what a bound is for: a model name
/// long enough to matter is exactly the one that would otherwise push the
/// clear-conversation button off the edge.
const double _engineBarWords = 120;

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

/// Says which engine answered, as one pill's worth of label.
///
/// One function, because two widgets say this and they must never disagree: the
/// control in the app bar names the engine that is answering *now* and the small
/// mark on a reply names the engine that wrote *that*. A second copy of the
/// switch is how the bar ends up claiming one thing while a reply underneath it
/// says the same thing in different words.
///
/// The names are [KoruEngine.label] in small caps and nothing else — "LOCAL
/// MODEL", "CLOUD MODEL". Four different ways of naming the same engine across
/// four screens is what a person reads as "the app has two or three engines",
/// which is worse than any one of the names being poor. The states that matter
/// are appended, because they are the thing that changes and the name is not.
({String label, IconData icon, ({Color ink, Color fill}) tone}) koruEngineSummary({
  required KoruEngine? engine,
  bool starting = false,
  int? progress,
  bool failed = false,
  double? tokensPerSecond,
}) {
  final speed = tokensPerSecond;
  return switch (engine) {
    null => (
        label: '',
        icon: Icons.memory_rounded,
        tone: KoruTones.neutral,
      ),
    // The three states that are not "running" come first inside this case,
    // because a start that failed has already been through the branch that
    // reported it starting, and a stale progress value must not keep a dead
    // engine looking like it is on its way up.
    KoruEngine.onDevice => (
        label: switch ((failed, starting, progress)) {
          (true, _, _) => 'LOCAL MODEL  NOT RUNNING',
          // The copy out of the APK has no percentage. Saying so beats printing
          // "-1%" or pretending it is 0.
          (false, true, EngineProgress.unpacking) => 'LOCAL MODEL  UNPACKING',
          (false, true, final int percent?) => 'LOCAL MODEL  $percent%',
          (false, true, _) => 'LOCAL MODEL  STARTING',
          _ => speed == null
              ? 'LOCAL MODEL'
              : 'LOCAL MODEL  ${speed.toStringAsFixed(1)} TOK/S',
        },
        icon: Icons.memory_rounded,
        tone: failed ? KoruTones.clay : KoruTones.leaf,
      ),
    KoruEngine.cloud => (
        label: 'CLOUD MODEL',
        icon: Icons.cloud_outlined,
        tone: KoruTones.gold,
      ),
  };
}

/// Names the engine on a reply. A label, never a control.
///
/// It used to open the switcher, and that is the thing it must not do again:
/// changing who answers is a decision about the app, not about the sentence
/// above it, and a control sitting on each reply means the place you change it
/// is somewhere different every time you look. The control lives in the app bar,
/// which is always in the same place.
///
/// What is left here is the provenance. The engine that wrote a reply can be a
/// different one from the engine that will write the next, and the difference
/// has to be readable on the reply itself, so this says what is honest about a
/// starting engine too: a label saying the local model is ready while it is
/// still being copied out of the APK is the one thing this must never say,
/// because the reader acts on it.
class KoruEngineBadge extends StatelessWidget {
  const KoruEngineBadge({
    super.key,
    required this.engine,
    this.tokensPerSecond,
    this.starting = false,
    this.progress,
    this.failed = false,
  });

  final KoruEngine? engine;
  final double? tokensPerSecond;

  /// The engine is being brought up right now.
  ///
  /// Only consulted for the local engine: the other one has nothing to start, so
  /// a "starting" line on it would be noise.
  final bool starting;

  /// How far the start has got, 0 to 100, while it is in one.
  final int? progress;

  /// The last attempt to start it did not work.
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final engine = this.engine;
    if (engine == null) return const SizedBox.shrink();

    final summary = koruEngineSummary(
      engine: engine,
      tokensPerSecond: tokensPerSecond,
      starting: starting,
      progress: progress,
      failed: failed,
    );
    return KoruPill(
      label: summary.label,
      color: summary.tone.ink,
      background: summary.tone.fill,
      icon: summary.icon,
    );
  }
}

/// The engine control for the chat's app bar.
///
/// Where the switcher is opened from. It lives in the bar rather than on a
/// reply because the answer to "who is answering, and can I change it" is a
/// property of the screen, not of any one message: a control that is only
/// reachable once a conversation exists is a control nobody finds while they are
/// still deciding who they are talking to.
///
/// Two lines, because one cannot carry what is being asked for. The first is
/// the engine's own name — including the starting and failed states, so a slow
/// phone explains itself. The second is the detail that makes the name mean
/// something: which model the local engine is running, which company answers the
/// cloud one, or how fast the last answer actually came back.
class KoruEngineBarButton extends StatelessWidget {
  const KoruEngineBarButton({
    super.key,
    required this.engine,
    required this.detail,
    required this.onTap,
    this.tokensPerSecond,
    this.starting = false,
    this.progress,
    this.failed = false,
  });

  final KoruEngine? engine;

  /// The model, the provider company, or the speed — whichever this engine can
  /// be honest about. Empty means "not known yet", and the line is left out
  /// rather than filled with a placeholder.
  final String? detail;

  final VoidCallback onTap;
  final double? tokensPerSecond;
  final bool starting;
  final int? progress;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final engine = this.engine;
    if (engine == null) return const SizedBox.shrink();

    final summary = koruEngineSummary(
      engine: engine,
      tokensPerSecond: tokensPerSecond,
      starting: starting,
      progress: progress,
      failed: failed,
    );
    final detail = this.detail?.trim();
    // The speed is already in the label for a local model that has answered, so
    // saying it twice in two different type sizes reads as a mistake.
    final second = detail == null || detail.isEmpty || detail == summary.label
        ? null
        : detail;

    return Semantics(
      button: true,
      label: 'Change who answers. ${summary.label}'
          '${second == null ? '' : '. $second'}',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(KoruRadius.field),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KoruSpace.sm,
              vertical: KoruSpace.xxs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  summary.icon,
                  size: KoruSize.iconSm,
                  color: summary.tone.ink,
                ),
                const SizedBox(width: KoruSpace.xsm),
                // Bounded rather than wrapped: a long model name has to give way
                // before it can push the bar's own actions off the screen.
                ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxWidth: _engineBarWords),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        summary.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: KoruType.rowTitleCompact,
                      ),
                      if (second != null)
                        Text(
                          second,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: KoruType.micro,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: KoruSpace.xxs),
                // The affordance. A control shaped like a label is how a control
                // ends up being a label for six months.
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
              // The copy out of the APK gets its own line rather than a
              // percentage. It is the one part of a cold start that takes tens
              // of seconds and reports nothing, and a bar sitting at zero for
              // thirty seconds is what made the app look dead on first launch.
              failed
                  ? 'The local model did not start. $problem'
                  : p == EngineProgress.unpacking
                      ? 'Unpacking the local model, 248 MB. Once, on first use. '
                          'You can carry on in the meanwhile.'
                      : 'Starting the local model, $p%. You can carry on in the '
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
        border: Border(top: KoruBorders.hairline()),
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
        color: KoruColors.nothing,
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