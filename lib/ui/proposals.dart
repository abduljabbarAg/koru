import 'package:flutter/material.dart';

import '../handoff.dart';
import '../proposed_write.dart';
import '../theme.dart';
import 'marks.dart';
import 'surfaces.dart';

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
      padding: const EdgeInsets.only(top: KoruSpace.sml, bottom: KoruSpace.xs),
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
                    style: KoruType.rowTitle.copyWith(height: 1.35),
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
        padding: const EdgeInsets.only(top: KoruSpace.sml),
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
                    child: Text(plan.headline, style: KoruType.rowTitleLarge),
                  ),
                  if (onDismiss != null)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close_rounded, size: KoruSize.icon),
                      onPressed: onDismiss,
                      tooltip: 'Dismiss',
                    ),
                ],
              ),
              const SizedBox(height: KoruSpace.md),
              Text(plan.body, style: KoruType.bodySmall),
              const SizedBox(height: KoruSpace.md),
              ...plan.resources.map(
                (r) => Padding(
                  padding: const EdgeInsets.only(bottom: KoruSpace.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(
                          top: KoruSpace.xsm,
                          right: KoruSpace.xs,
                        ),
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
                              style: KoruType.bodyCompactStrong.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(r.detail, style: KoruType.bodySmall),
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
      padding: const EdgeInsets.only(top: KoruSpace.sml, bottom: KoruSpace.xs),
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
                    padding: const EdgeInsets.only(top: KoruSpace.xs),
                    child: Text(
                      steps.length == 1
                          ? 'Koru wants to add one client'
                          : 'Koru wants to add ${steps.length} clients',
                      style: KoruType.rowTitle.copyWith(height: 1.3),
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
                padding: const EdgeInsets.only(bottom: KoruSpace.xsm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text('${i + 1}.', style: KoruType.meta),
                    ),
                    Expanded(
                      child: Text(
                        steps[i].summary,
                        style: KoruType.bodyCompactStrong,
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
                      style: KoruType.bodyCompactStrong.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: KoruSpace.xs),
                    for (final p in problems.take(6))
                      Padding(
                        padding: const EdgeInsets.only(bottom: KoruSpace.xxs),
                        child: Text(
                          '"${p.text}" - ${p.reason}',
                          style: KoruType.micro.copyWith(color: KoruColors.inkSoft),
                        ),
                      ),
                    if (problems.length > 6)
                      Text(
                        'and ${problems.length - 6} more',
                        style: KoruType.micro,
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: KoruSpace.md),
            Text(
              'Nothing is saved until you press Add. All of it goes in together, '
              'or none of it does.',
              style: KoruType.micro,
            ),
            const SizedBox(height: KoruSpace.sm),
            Row(
              children: [
                if (busy)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: KoruSpace.sm),
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
                  const SizedBox(width: KoruSpace.sm),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(KoruSize.buttonInCard),
                      ),
                      onPressed: steps.isEmpty ? null : onApprove,
                      icon: const Icon(Icons.check_rounded, size: KoruSize.icon),
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