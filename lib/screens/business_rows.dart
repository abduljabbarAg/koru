import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../attention_bridge.dart';
import '../currency.dart';
import '../human_date.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'business_event_sheet.dart';
import 'business_sheets.dart';
import 'client_detail.dart';

/// The rows the Clients and Revenue tabs are made of, and the writes they
/// perform.
///
/// They were methods on the Business screen, which is the right place for a
/// screen's layout and the wrong place for a deadline's three icons: that file
/// had grown past seven hundred lines, and everything in it was private, so the
/// client screen could not reach the row for the same facts and built a shorter
/// one of its own instead.
///
/// Public because a row that cannot be reused is a row that will be drawn
/// again. Nothing here composes a page; each of these is one row inside
/// somebody else's section, at the padding and the type the shared row already
/// defines.

/// Opens a client, from anywhere in the app.
///
/// One call rather than four copies of the same `Navigator.push`, because the
/// screen it opens is the same screen and a route built four times is four
/// chances to build it differently.
void openClient(BuildContext context, int clientId) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ClientDetailScreen(clientId: clientId),
    ),
  );
}

/// A prospect, with how long it has been sitting.
class PipelineRow extends ConsumerWidget {
  const PipelineRow({
    super.key,
    required this.client,
    required this.today,
    required this.currency,
  });

  final Client client;
  final DateTime today;
  final Currency currency;

  /// Three weeks without a word. Chosen rather than a fortnight because a lead
  /// somebody touches monthly would otherwise be shouted at every Monday.
  static const coldDays = 21;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final born = DateTime.tryParse(client.created);
    final days = born == null ? null : today.difference(born).inDays;
    final stale = days != null && days >= coldDays;

    return KoruRow(
      title: client.name,
      subtitle: [
        if (client.amount != null) '${money(client.amount!)} ${currency.code}',
        if (days != null) days == 0 ? 'added today' : 'added $days days ago',
      ].join('  ·  '),
      subtitleIn: stale ? KoruColors.gold : null,
      onTap: client.id == null ? null : () => openClient(context, client.id!),
      trailing: stale
          ? KoruPill(
              label: 'GOING COLD',
              color: KoruColors.gold,
              background: KoruColors.goldSoft,
            )
          : null,
    );
  }
}

/// Something that has to happen, whether or not it has a date that passed.
class DeadlineRow extends ConsumerWidget {
  const DeadlineRow({
    super.key,
    required this.deadline,
    required this.today,
    this.client,
  });

  final Deadline deadline;
  final DateTime today;

  /// Named on the row, because a deadline with no client on it is a chore and
  /// one with a client on it is a chase.
  final Client? client;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = deadline;
    final late = d.isOverdueOn(today);
    final who = client;

    return KoruRow(
      title: who == null ? d.title : '${d.title}  ·  ${who.name}',
      subtitle: late
          ? 'was due ${formatDate(d.due, DateTime.now())}'
          : 'due ${formatDate(d.due, DateTime.now())}',
      subtitleIn: late ? KoruColors.clay : null,
      accent: late ? KoruColors.clay : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          KoruRowAction(
            tooltip: 'Mark ${d.title} done',
            icon: Icons.radio_button_unchecked_rounded,
            color: KoruColors.inkFaint,
            onPressed: () => _complete(ref, d),
          ),
          KoruRowAction(
            tooltip: 'Put ${d.title} in the calendar',
            icon: Icons.event_outlined,
            onPressed: () => _toCalendar(context, ref, d, who),
          ),
          KoruRowAction(
            tooltip: 'Delete ${d.title}',
            icon: Icons.close_rounded,
            color: KoruColors.inkFaint,
            onPressed: () => _delete(ref, d),
          ),
        ],
      ),
    );
  }

  Future<void> _complete(WidgetRef ref, Deadline d) async {
    final store = await ref.read(storeProvider.future);
    await store.setDeadlineDone(d.id!, true);
    ref
      ..invalidate(openDeadlinesProvider)
      ..invalidate(guideFactsProvider);
  }

  /// Hands a deadline to the calendar app.
  ///
  /// Midday rather than midnight, and that is the whole trick. A due date is a
  /// day rather than an instant, and an event created at 00:00 fires before
  /// anybody is awake; noon is inside the day it belongs to on every calendar
  /// app, including the ones that show a day view.
  Future<void> _toCalendar(
    BuildContext context,
    WidgetRef ref,
    Deadline d,
    Client? client,
  ) async {
    final date = DateTime.tryParse(d.due);
    if (date == null) {
      toast(context, 'That deadline has no date to send.');
      return;
    }
    final when = DateTime(date.year, date.month, date.day, 12);
    final title = client == null ? d.title : '${d.title} — ${client.name}';
    final ok = await const AttentionBridge().addToCalendar(title, when);
    if (!context.mounted) return;
    toast(
      context,
      ok
          ? 'Check your calendar and press save.'
          : 'No calendar app on this phone could be opened.',
    );
  }

  Future<void> _delete(WidgetRef ref, Deadline d) async {
    final store = await ref.read(storeProvider.future);
    await store.deleteDeadline(d.id!);
    ref.invalidate(openDeadlinesProvider);
  }
}

/// One entry in the calendar Koru keeps, with the phone's own copy marked.
///
/// The date and the time are a column of their own rather than a second line
/// under the title: they are two facts of the same weight, and stacking them
/// made every row three lines tall on a screen that lists six of them.
class EventRow extends ConsumerWidget {
  const EventRow({super.key, required this.event});

  final CalendarEvent event;

  /// Wide enough for "Tue 16 Oct" at the row's own title size. Sized rather
  /// than fitted, so the six rows of a section all start their titles at the
  /// same place instead of each one measuring its own day.
  static const dayColumn = 66.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = event;
    final starts = e.startsAt;
    final dayLabel = starts == null
        ? e.date
        : '${_weekdayShort(starts.weekday)} ${starts.day} ${_monthShort(starts.month)}';
    final meta = <String>[
      if (e.location != null) e.location!,
      if (e.durationMin != null) '${e.durationMin} min',
      if (e.recurrence != null) e.recurrence!.phrase,
    ];

    return KoruRow(
      leading: SizedBox(
        width: dayColumn,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dayLabel, style: KoruType.rowTitleCompact),
            Text(e.timeLabel, style: KoruType.meta),
          ],
        ),
      ),
      title: e.title,
      subtitle: meta.isEmpty ? null : meta.join('  ·  '),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          KoruRowAction(
            tooltip: e.synced
                ? 'Already in your phone calendar'
                : 'Copy to your phone calendar',
            icon: e.synced ? Icons.check_rounded : Icons.event_outlined,
            color: e.synced ? KoruColors.leaf : null,
            onPressed: e.synced ? null : () => _sync(context, ref, e),
          ),
          KoruRowAction(
            tooltip: 'Change ${e.title}',
            icon: Icons.edit_outlined,
            color: KoruColors.inkFaint,
            onPressed: () => _edit(context, ref, e),
          ),
          KoruRowAction(
            tooltip: 'Delete ${e.title}',
            icon: Icons.close_rounded,
            color: KoruColors.inkFaint,
            onPressed: () => _delete(ref, e),
          ),
        ],
      ),
    );
  }

  /// Copies one entry to the phone's own calendar, through the same bridge the
  /// chat uses, so an entry created in either place can be mirrored.
  Future<void> _sync(
    BuildContext context,
    WidgetRef ref,
    CalendarEvent e,
  ) async {
    final starts = e.startsAt;
    if (starts == null) {
      toast(context, 'That entry has no date to send.');
      return;
    }
    final ok = await ref.read(calendarBridgeProvider).addEvent(
          title: e.title,
          start: starts,
          end: starts.add(const Duration(hours: 1)),
          location: e.location,
        );
    if (!context.mounted) return;
    if (ok) {
      final store = await ref.read(storeProvider.future);
      await store.updateEvent(
          CalendarEvent.fromMap({...e.toMap(), 'synced': 1}));
      ref.invalidate(eventsProvider);
      // The write crosses an await, so the element may be gone by now; using the
      // context then throws instead of quietly doing nothing.
      if (!context.mounted) return;
      toast(context, 'Copied to your phone calendar.');
    } else {
      toast(context, 'Your phone calendar could not be written to. Check the '
          'calendar permission in Settings.');
    }
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    CalendarEvent e,
  ) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => EventSheet(event: e),
    );
    if (!context.mounted || changed != true) return;
    ref.invalidate(eventsProvider);
  }

  Future<void> _delete(WidgetRef ref, CalendarEvent e) async {
    final store = await ref.read(storeProvider.future);
    await store.deleteEvent(e.id!);
    ref.invalidate(eventsProvider);
  }

  static String _weekdayShort(int weekday) => switch (weekday) {
        1 => 'Mon',
        2 => 'Tue',
        3 => 'Wed',
        4 => 'Thu',
        5 => 'Fri',
        6 => 'Sat',
        _ => 'Sun',
      };

  static String _monthShort(int month) => switch (month) {
        1 => 'Jan',
        2 => 'Feb',
        3 => 'Mar',
        4 => 'Apr',
        5 => 'May',
        6 => 'Jun',
        7 => 'Jul',
        8 => 'Aug',
        9 => 'Sep',
        10 => 'Oct',
        11 => 'Nov',
        _ => 'Dec',
      };
}

/// Money that came in, and the one thing you can do about it by mistake.
class PaymentRow extends ConsumerWidget {
  const PaymentRow({
    super.key,
    required this.payment,
    required this.currency,
    this.client,
  });

  final Payment payment;
  final Currency currency;
  final Client? client;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = payment;
    return KoruRow(
      title: '${money(p.amount)} ${currency.code}  ·  ${client?.name ?? 'unknown'}',
      // The date is read the same way with or without a note. It used to be a
      // raw ISO string whenever the payment had one, so the same screen showed
      // "2 days ago" on one row and "2026-02-01" on the next.
      subtitle: p.note == null
          ? formatDate(p.date, DateTime.now())
          : '${formatDate(p.date, DateTime.now())}  ·  ${p.note}',
      trailing: KoruRowAction(
        tooltip: 'Undo this payment',
        icon: Icons.undo_rounded,
        color: KoruColors.inkFaint,
        onPressed: () async {
          final store = await ref.read(storeProvider.future);
          await store.deletePayment(p.id!);
          invalidateWorkData(ref);
        },
      ),
    );
  }
}

/// One client: who they are, what they owe, and the three things you can do
/// about it.
///
/// Deliberately taller than a deadline's. A client carries a balance, a status
/// you can change and two actions; a deadline carries a date and three icons.
/// Making them the same height would mean either padding out the deadline or
/// cramming the client, and a list where every row is the same height reads as
/// one kind of thing.
///
/// One pill, not two. The balance and the lateness were separate badges saying
/// the same thing twice, in the same colour, four pixels apart. Late is now
/// folded into the figure itself — the amount is the thing being chased, and
/// the title and the date underneath it are already in the warning colour.
class ClientRow extends ConsumerWidget {
  const ClientRow({
    super.key,
    required this.client,
    required this.today,
    required this.currency,
    required this.received,
    this.openTasks = 0,
  });

  final Client client;
  final DateTime today;
  final Currency currency;

  /// What has already come in from this client. Part of the row's arithmetic,
  /// not a lookup, so the figure on the row and the figure in the store cannot
  /// disagree.
  final double received;

  /// How much of their work is still open. Counted by the screen, which has the
  /// list already, so a row does not go and find out for itself.
  ///
  /// On the row because it is the other half of the question this screen asks:
  /// somebody opening Clients wants to know both who owes them and who has work
  /// outstanding, and the second half used to live on two other screens.
  final int openTasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = client;
    final balance = c.balanceWith(received);
    final late = c.isOverdueOn(today);
    final tone = KoruTones.status(c.status);
    final meta = <String>[
      if (c.amount != null) '${money(c.amount!)} ${currency.code} invoiced',
      if (received > 0) '${money(received)} received',
      if (openTasks > 0)
        openTasks == 1
            ? '1 task open'
            : '$openTasks tasks open',
      if (c.leadSource != null) 'via ${c.leadSource}',
      if (c.parsedDue != null) 'due ${formatDate(c.due, DateTime.now())}',
    ];

    return KoruRow(
      onTap: c.id == null ? null : () => openClient(context, c.id!),
      title: c.name,
      subtitle: meta.join('  ·  '),
      accent: late ? KoruColors.clay : null,
      trailing: PopupMenuButton<String>(
        initialValue: c.status,
        onSelected: (v) async {
          final store = await ref.read(storeProvider.future);
          await store.setClientStatus(c.id!, v);
          invalidateWorkData(ref);
        },
        itemBuilder: (_) => kClientStatuses
            .map((s) => PopupMenuItem(value: s, child: Text(s)))
            .toList(),
        child: KoruPill(
          label: c.status.toUpperCase(),
          color: tone.ink,
          background: tone.fill,
          icon: Icons.arrow_drop_down_rounded,
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (balance > 0) ...[
            KoruPill(
              label: late
                  ? '${money(balance)} ${currency.code} OVERDUE'
                  : '${money(balance)} ${currency.code} OUTSTANDING',
              color: late ? KoruColors.clay : KoruColors.gold,
              background: late ? KoruColors.claySoft : KoruColors.goldSoft,
              icon: late ? Icons.error_outline_rounded : null,
            ),
            const SizedBox(height: KoruSpace.sm),
          ],
          if (c.note != null) Text(c.note!, style: KoruType.bodyCompact),
          const SizedBox(height: KoruSpace.xs),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => editClientSheet(context, ref, existing: c),
                icon: const Icon(Icons.edit_outlined, size: KoruSize.iconSm),
                label: const Text('Edit'),
              ),
              if (c.status != 'lost')
                TextButton.icon(
                  onPressed: () =>
                      recordPaymentSheet(context, ref, c, received),
                  icon: const Icon(Icons.payments_outlined, size: KoruSize.iconSm),
                  label: Text(received > 0 ? 'Add payment' : 'Mark paid'),
                ),
              const Spacer(),
              KoruRowAction(
                tooltip: 'Delete ${c.name}',
                icon: Icons.delete_outline_rounded,
                onPressed: () async {
                  final store = await ref.read(storeProvider.future);
                  await store.deleteClient(c.id!);
                  invalidateWorkData(ref);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// How many clients this person is carrying, against the number they said they
/// could serve.
///
/// Only counts work actually under way. Leads are a hope, not a commitment, and
/// counting them would make the meter read full for someone who is not.
///
/// Deliberately not the number of clients with a balance. An active client who
/// owes money is one client, not two, and adding the two counts together said
/// someone with a single active job was carrying two.
///
/// The wording below capacity is deliberately an opportunity rather than a
/// warning. Nagging someone for having too few clients punishes the person
/// doing fine; the dangerous direction is the other one, and that is the one
/// that gets the firm tone.
class CapacityMeter extends StatelessWidget {
  const CapacityMeter({
    super.key,
    required this.activeCount,
    required this.capacity,
  });

  final int activeCount;
  final int capacity;

  @override
  Widget build(BuildContext context) {
    final full = activeCount >= capacity;
    final room = capacity - activeCount;
    final tone = full ? KoruTones.clay : KoruTones.leaf;
    final message = full
        ? 'You said $capacity was the most you could serve well, and you are at '
            '$activeCount. Worth finishing or handing off before taking more.'
        : 'Room for $room more client${room == 1 ? '' : 's'} before you are full.';

    return Padding(
      padding: const EdgeInsets.only(
        top: KoruSpace.lg,
        bottom: KoruSpace.section,
      ),
      child: KoruCard(
        background: tone.fill,
        accent: tone.ink,
        elevated: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                KoruIconBadge(
                  icon: Icons.groups_rounded,
                  color: tone.ink,
                  background: KoruColors.surface,
                ),
                const SizedBox(width: KoruSpace.md),
                Expanded(
                  child: Text(
                    '$activeCount of $capacity',
                    style: KoruType.rowTitle.copyWith(color: tone.ink),
                  ),
                ),
                Text(
                  full ? 'at capacity' : '$room free',
                  style: KoruType.meta.copyWith(color: KoruColors.inkSoft),
                ),
              ],
            ),
            const SizedBox(height: KoruSpace.md),
            KoruSegmentMeter(
              filled: activeCount,
              total: capacity,
              color: tone.ink,
              empty: KoruColors.surface.withValues(alpha: 0.75),
            ),
            const SizedBox(height: KoruSpace.md),
            Text(message, style: KoruType.bodyCompact),
          ],
        ),
      ),
    );
  }
}