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
      child: Icon(Icons.spa_rounded, color: Colors.white, size: size * 0.6),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 2),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
          color: KoruColors.inkFaint,
        ),
      ),
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
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: KoruColors.ink,
              letterSpacing: -0.6,
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(sub!, style: const TextStyle(fontSize: 13, color: KoruColors.inkFaint)),
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
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
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
          Icon(icon, size: 30, color: KoruColors.inkFaint),
          const SizedBox(height: 10),
          Text(title,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: KoruColors.ink)),
          const SizedBox(height: 4),
          Text(body,
              textAlign: TextAlign.center,
              style: const TextStyle(color: KoruColors.inkFaint, fontSize: 13, height: 1.4)),
          if (action != null) ...[
            const SizedBox(height: 16),
            action!,
          ],
        ],
      ),
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
              const Icon(Icons.edit_note_rounded, size: 18, color: KoruColors.gold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  write.summary,
                  style: const TextStyle(
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
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: KoruColors.ink,
                    ),
                  ),
                ),
                if (onDismiss != null)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded, size: 18, color: KoruColors.inkFaint),
                    onPressed: onDismiss,
                    tooltip: 'Dismiss',
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              plan.body,
              style: const TextStyle(fontSize: 13.5, color: KoruColors.inkSoft, height: 1.45),
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
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13.5, color: KoruColors.ink),
                            ),
                            Text(
                              r.detail,
                              style: const TextStyle(fontSize: 12.5, color: KoruColors.inkFaint, height: 1.35),
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
        decoration: const BoxDecoration(
          color: KoruColors.cream,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                  style: const TextStyle(fontSize: 13, color: KoruColors.inkFaint, height: 1.4)),
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
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1, right: 8),
                    child: Icon(
                      Icons.format_quote_rounded,
                      size: 16,
                      color: KoruColors.inkFaint,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      text,
                      style: const TextStyle(
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
              const Icon(Icons.playlist_add_check_rounded,
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
                        style: const TextStyle(
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
                          style: const TextStyle(
                              fontSize: 11.5, color: KoruColors.inkSoft)),
                    ),
                  if (problems.length > 6)
                    Text('and ${problems.length - 6} more',
                        style: const TextStyle(
                            fontSize: 11.5, color: KoruColors.inkFaint)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            'Nothing is saved until you press Add. All of it goes in together, '
            'or none of it does.',
            style: TextStyle(
                fontSize: 11.5, color: KoruColors.inkFaint, height: 1.35),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (busy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
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
