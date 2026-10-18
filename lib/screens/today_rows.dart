import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import '../work_queue.dart';

/// How one row of the morning's queue is drawn.
///
/// Kept out of the screen because the screen is a page and this is one line of
/// it, and because a row that has to be drawn twice is a row that ends up with
/// two paddings.
///
/// The row does not name a client. Work is the user's own — the client is the
/// one it is being done *for*, not the one doing it — and a name on every line
/// read as an assignment, as if the job had been handed to somebody else.
class QueueRow extends StatelessWidget {
  const QueueRow({
    super.key,
    required this.item,
    this.currency = 'AED',
    this.onOpen,
    this.onDone,
    this.doneLabel,
  });

  final WorkItem item;

  /// Shown beside the figure on a row that has money attached.
  final String currency;

  /// Opens the thing. Null when there is nowhere to go, which is not the same as
  /// a row that looks broken: the trailing control is the only way to act on it.
  final VoidCallback? onOpen;

  /// Ticks it off from the list, without going anywhere first. This is the
  /// control that makes the queue usable rather than a report: the most common
  /// thing anybody does with a list of work is finish a line on it.
  final VoidCallback? onDone;

  /// The word on that control, so a row about something already finished reads
  /// as finished rather than as untappable.
  final String? doneLabel;

  @override
  Widget build(BuildContext context) {
    final late = item.overdue;
    final tone = _toneFor(item);
    final parts = <String>[
      item.detail,
      if (item.money != null) '${money(item.money!)} $currency',
    ];
    final canDone = onDone != null;

    return KoruRow(
      onTap: onOpen,
      leading: KoruIconBadge(icon: tone.icon, color: tone.ink, background: tone.fill),
      title: item.title,
      subtitle: parts.isEmpty ? null : parts.join('  ·  '),
      subtitleIn: late ? KoruColors.clay : null,
      accent: late ? KoruColors.clay : null,
      body: _priority(item.priority),
      trailing: canDone
          ? KoruRowAction(
              tooltip: doneLabel ?? 'Mark ${item.title} done',
              icon: Icons.radio_button_unchecked_rounded,
              color: KoruColors.inkFaint,
              onPressed: onDone,
            )
          : null,
    );
  }

  /// The pill, when somebody said this mattered more or less than the rest.
  ///
  /// Nothing is drawn for the middle. Three pills on every row is a wall, and the
  /// middle is the answer most rows already have; the ordering below is what
  /// makes the middle legible.
  Widget _priority(TaskPriority? priority) {
    final p = priority;
    if (p == null || p == TaskPriority.normal) return const SizedBox.shrink();
    final tone = p == TaskPriority.high ? KoruTones.clay : KoruTones.neutral;
    return KoruPill(
      label: p.label.toUpperCase(),
      color: tone.ink,
      background: tone.fill,
    );
  }

  /// The badge and its pair of colours, measured in the palette so both
  /// brightnesses hold.
  ///
  /// Colour says when, not what: late is clay everywhere, a place to be is
  /// green, and a task that is neither is the quiet grey. A reader can sort the
  /// queue by colour before reading a word of it, which is the whole point of a
  /// ranked list on a phone.
  static ({IconData icon, Color ink, Color fill}) _toneFor(WorkItem item) {
    late ({Color ink, Color fill}) tone;
    final IconData icon;
    switch (item.kind) {
      case WorkKind.money:
        icon = Icons.account_balance_wallet_outlined;
        tone = item.overdue ? KoruTones.clay : KoruTones.gold;
      case WorkKind.task:
        icon = Icons.task_alt_rounded;
        tone = item.overdue
            ? KoruTones.clay
            : item.daysOut == 0
                ? KoruTones.gold
                : KoruTones.neutral;
      case WorkKind.deadline:
        icon = Icons.flag_outlined;
        tone = item.overdue ? KoruTones.clay : KoruTones.gold;
      case WorkKind.event:
        icon = Icons.event_outlined;
        tone = KoruTones.leaf;
      case WorkKind.project:
        icon = Icons.work_outline;
        tone = KoruTones.neutral;
    }
    return (icon: icon, ink: tone.ink, fill: tone.fill);
  }
}