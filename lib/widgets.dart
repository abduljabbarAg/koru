import 'package:flutter/material.dart';

import 'handoff.dart';
import 'mascot/mascot.dart';
import 'proposed_write.dart';
import 'theme.dart';

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
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
          color: KoruColors.inkFaint,
        ),
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
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 20),
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
                    padding: const EdgeInsets.only(bottom: 10),
                  ),
                Text(
                  title,
                  style: text.headlineMedium?.copyWith(
                    color: KoruColors.ink,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.9,
                    height: 1.12,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 9),
                  Text(
                    subtitle!,
                    style: text.titleSmall?.copyWith(
                      color: KoruColors.inkSoft,
                      height: 1.45,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(top: 2),
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
  });

  final String label;

  /// The rows. They bring their own padding; the surface brings the border.
  final List<Widget> children;

  /// One line under the label saying what this section is for.
  final String? hint;

  /// How far the separator between two rows starts from the left edge.
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(label),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 10),
              child: Text(
                hint!,
                style: text.bodySmall?.copyWith(
                  color: KoruColors.inkFaint,
                  height: 1.4,
                ),
              ),
            ),
          Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            color: KoruColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(KoruRadius.card),
              side: BorderSide(color: KoruColors.line),
            ),
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
    this.size = 34,
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
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, size: size * 0.5, color: color),
    );
  }
}

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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KoruColors.surface,
        borderRadius: BorderRadius.circular(KoruRadius.card),
        border: Border.all(color: KoruColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: tintBg,
              borderRadius: BorderRadius.circular(KoruRadius.pill),
            ),
            child: Text(
              label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: tint),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: KoruColors.ink,
              letterSpacing: -0.6,
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(sub!, style: TextStyle(fontSize: 13, color: KoruColors.inkFaint)),
          ],
        ],
      ),
    );
  }
}

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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: KoruColors.surface,
        borderRadius: BorderRadius.circular(KoruRadius.card),
        border: Border.all(color: KoruColors.line),
      ),
      child: Column(
        children: [
          if (tintBg == null)
            Icon(icon, size: 30, color: ink)
          else
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: tintBg, shape: BoxShape.circle),
              child: Icon(icon, size: 24, color: ink),
            ),
          const SizedBox(height: 10),
          Text(title,
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: KoruColors.ink)),
          const SizedBox(height: 4),
          Text(body,
              textAlign: TextAlign.center,
              style: TextStyle(color: KoruColors.inkFaint, fontSize: 13, height: 1.4)),
          if (action != null) ...[
            const SizedBox(height: 16),
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
          const SizedBox(height: 16),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: KoruColors.inkFaint,
                  letterSpacing: 0.2,
                ),
          ),
        ],
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
    this.duration = const Duration(milliseconds: 420),
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
      curve: Curves.easeOutCubic,
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

    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 4),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: KoruColors.goldSoft,
        borderRadius: BorderRadius.circular(KoruRadius.card),
        border: Border.all(color: KoruColors.gold),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit_note_rounded, size: 18, color: KoruColors.gold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  write.summary,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: KoruColors.ink,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          if (write is ProposedPayment) ...[
            const SizedBox(height: 12),
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
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(42)),
                  onPressed: _busy || amountError ? null : _approve,
                  child: const Text('Save it'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(42)),
                  onPressed: _busy ? null : widget.onDiscard,
                  child: const Text('Discard'),
                ),
              ),
            ],
          ),
        ],
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
    final accent = plan.urgent ? KoruColors.clay : KoruColors.gold;
    final accentBg = plan.urgent ? KoruColors.claySoft : KoruColors.goldSoft;

    return Semantics(
      liveRegion: true,
      container: true,
      label: '${plan.headline}. ${plan.body}',
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: KoruColors.surface,
          borderRadius: BorderRadius.circular(KoruRadius.card),
          border: Border.all(color: accent, width: 1.4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: accentBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    plan.urgent ? Icons.emergency_share_rounded : Icons.pan_tool_alt_rounded,
                    size: 19,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    plan.headline,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: KoruColors.ink,
                    ),
                  ),
                ),
                if (onDismiss != null)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.close_rounded, size: 18, color: KoruColors.inkFaint),
                    onPressed: onDismiss,
                    tooltip: 'Dismiss',
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              plan.body,
              style: TextStyle(fontSize: 13.5, color: KoruColors.inkSoft, height: 1.45),
            ),
            const SizedBox(height: 14),
            ...plan.resources.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 5, right: 9),
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.name,
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13.5, color: KoruColors.ink),
                            ),
                            Text(
                              r.detail,
                              style: TextStyle(fontSize: 12.5, color: KoruColors.inkFaint, height: 1.35),
                            ),
                            Text(
                              '${r.number} - ${r.hours}',
                              style: TextStyle(fontSize: 12.5, color: accent, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),
          ],
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(KoruRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
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
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: BoxDecoration(
          color: KoruColors.cream,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                    color: KoruColors.line, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle,
                  style: TextStyle(fontSize: 13, color: KoruColors.inkFaint, height: 1.4)),
            ],
            const SizedBox(height: 18),
            Flexible(child: SingleChildScrollView(child: builder(ctx))),
          ],
        ),
      ),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          KoruMascot(size: mascotSize, onTap: onTap),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(left: 4),
              padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
              decoration: BoxDecoration(
                color: KoruColors.surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                border: Border.all(color: KoruColors.line),
                boxShadow: [
                  BoxShadow(
                    color: KoruColors.shadow,
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1, right: 8),
                    child: Icon(
                      Icons.format_quote_rounded,
                      size: 16,
                      color: KoruColors.inkFaint,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      text,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: KoruColors.ink,
                        height: 1.45,
                      ),
                    ),
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

    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 4),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: KoruColors.goldSoft,
        borderRadius: BorderRadius.circular(KoruRadius.card),
        border: Border.all(color: KoruColors.gold),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.playlist_add_check_rounded,
                  size: 17, color: KoruColors.clay),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  steps.length == 1 ? 'Koru wants to add one client' : 'Koru wants to add ${steps.length} clients',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Every step, numbered. Not a summary of a summary: the user is being
          // asked to agree to twenty specific claims about money, so all twenty
          // are on the screen.
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 20,
                    child: Text('${i + 1}.',
                        style: TextStyle(
                            color: KoruColors.inkFaint, fontSize: 12.5)),
                  ),
                  Expanded(
                    child: Text(steps[i].summary,
                        style: const TextStyle(fontSize: 13, height: 1.35)),
                  ),
                ],
              ),
            ),
          if (problems.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: KoruColors.claySoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${problems.length} line${problems.length == 1 ? '' : 's'} I could not read',
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  for (final p in problems.take(6))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text('"${p.text}" — ${p.reason}',
                          style: TextStyle(
                              fontSize: 11.5, color: KoruColors.inkSoft)),
                    ),
                  if (problems.length > 6)
                    Text('and ${problems.length - 6} more',
                        style: TextStyle(
                            fontSize: 11.5, color: KoruColors.inkFaint)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Nothing is saved until you press Add. All of it goes in together, '
            'or none of it does.',
            style: TextStyle(
                fontSize: 11.5, color: KoruColors.inkFaint, height: 1.35),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (busy)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: KoruColors.clay),
                  ),
                )
              else ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: onDiscard,
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
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
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 38, color: KoruColors.inkFaint),
            const SizedBox(height: 12),
            Text('Could not $what',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              'Nothing was changed. This usually clears on its own.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: KoruColors.inkSoft),
            ),
            const SizedBox(height: 14),
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
