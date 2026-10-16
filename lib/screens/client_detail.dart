import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../currency.dart';
import '../human_date.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

/// The first match, or null.
///
/// Written out rather than using firstOrNull, which lives in package:collection
/// and is not a dependency here. Reaching for it through a transitive one works
/// until it does not.
Client? _firstClient(Iterable<Client> xs) => xs.isEmpty ? null : xs.first;

/// Everything about one client, in one place.
///
/// The Business screen is a list to scan, and that is the right shape for "who
/// is late". It is the wrong shape for "what is actually going on with Acme",
/// which is per client and spread across three tables: the invoice, the ledger
/// and the deadlines. Until this screen existed the app had the data and
/// nowhere to show it, which is also why asking the model about a specific
/// client was a guess.
class ClientDetailScreen extends ConsumerWidget {
  const ClientDetailScreen({super.key, required this.clientId});

  final int clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clients = ref.watch(clientsProvider).valueOrNull;
    final received = ref.watch(receivedTotalsProvider).valueOrNull ?? const <int, double>{};
    final payments =
        ref.watch(paymentsProvider).valueOrNull?.where((p) => p.clientId == clientId).toList() ??
            const <Payment>[];
    final deadlines = ref.watch(openDeadlinesProvider).valueOrNull
            ?.where((d) => d.clientId == clientId)
            .toList() ??
        const <Deadline>[];

    final client =
        clients == null ? null : _firstClient(clients.where((c) => c.id == clientId));
    if (client == null) {
      return Scaffold(
        backgroundColor: KoruColors.cream,
        appBar: AppBar(),
        body: clients == null
            ? const KoruLoading(label: 'Loading this client')
            : const Center(
                child: EmptyHint(
                  icon: Icons.person_off_outlined,
                  title: 'That client is gone',
                  body: 'They were deleted from the list.',
                ),
              ),
      );
    }

    final currency = ref.watch(currencyProvider).valueOrNull ?? defaultCurrency;
    final balance = client.balanceWith(received[clientId] ?? 0);
    final today = DateTime.now();

    return Scaffold(
      backgroundColor: KoruColors.cream,
      appBar: AppBar(title: Text(client.name)),
      body: KoruSettle(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            KoruSpace.gutter,
            KoruSpace.sm,
            KoruSpace.gutter,
            KoruSpace.tail,
          ),
          children: [
            _statusPill(client, balance, currency),
            const SizedBox(height: KoruSpace.md),
            _moneySummary(client, balance, received[clientId] ?? 0, currency),
            if (client.isRetainer) ...[
              const SizedBox(height: KoruSpace.md),
              _RetainerPanel(
                client: client,
                onAddNext: () => _addNextRetainerDeadline(context, ref, client),
              ),
            ],
            if (client.note != null && client.note!.trim().isNotEmpty) ...[
              const SizedBox(height: KoruSpace.lg),
              const SectionLabel('Note'),
              const SizedBox(height: KoruSpace.xs + 2),
              KoruCard(
                child: Text(
                  client.note!,
                  style: KoruType.body,
                ),
              ),
            ],
            KoruSection(
              label: 'Payments',
              hint: payments.isEmpty ? null : '${payments.length} recorded',
              dividerIndent: KoruSpace.row,
              empty: const EmptyHint(
                icon: Icons.payments_outlined,
                title: 'Nothing recorded',
                body: 'Record a payment from the Business screen when money '
                    'comes in, and the balance follows.',
              ),
              children: [
                for (final p in payments) _paymentRow(ref, p, currency),
              ],
            ),
            KoruSection(
              label: 'Deadlines',
              hint: 'Still open for this client.',
              dividerIndent: KoruSpace.row,
              empty: const EmptyHint(
                icon: Icons.event_available_rounded,
                title: 'Nothing scheduled',
                body: 'Nothing open for this client. Say "add deadline" in Talk '
                    'to put one on the list.',
              ),
              children: [
                for (final d in deadlines) _deadlineRow(ref, d, today),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusPill(Client c, double balance, Currency currency) {
    final tone = switch (c.status) {
      'paid' => KoruTones.leaf,
      'active' => KoruTones.gold,
      'delivered' => KoruTones.clay,
      _ => KoruTones.neutral,
    };
    final late = c.isOverdueOn(DateTime.now());
    return Row(
      children: [
        KoruPill(
          label: c.status.toUpperCase(),
          color: tone.ink,
          background: tone.fill,
        ),
        if (balance > 0) ...[
          const SizedBox(width: KoruSpace.sm),
          KoruPill(
            label: '${money(balance)} ${currency.code} OUTSTANDING',
            color: late ? KoruColors.clay : KoruColors.gold,
            background: late ? KoruColors.claySoft : KoruColors.goldSoft,
          ),
        ],
        if (c.isRetainer) ...[
          const SizedBox(width: KoruSpace.sm),
          KoruPill(
            label: 'RETAINER',
            color: KoruColors.leaf,
            background: KoruColors.leafSoft,
          ),
        ],
      ],
    );
  }

  Widget _moneySummary(Client c, double balance, double received, Currency currency) {
    final meta = <String>[
      if (c.amount != null) '${money(c.amount!)} ${currency.code} invoiced',
      if (received > 0) '${money(received)} received',
      if (c.leadSource != null) 'via ${c.leadSource}',
      // Shown where the number can be checked. A phone number that only
      // exists in the editor and appears nowhere else is indistinguishable
      // from one that failed to save.
      if (c.phone != null) c.phone!,
    ];
    return KoruCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            balance > 0 ? money(balance) : money(received),
            style: KoruType.metric,
          ),
          const SizedBox(height: KoruSpace.xs),
          Text(
            balance > 0
                ? '${currency.code} still owed'
                : '${currency.code} received, nothing outstanding',
            style: KoruType.caption,
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: KoruSpace.sm + 2),
            Text(meta.join('  ·  '), style: KoruType.meta.copyWith(fontSize: 13)),
          ],
        ],
      ),
    );
  }

  Widget _paymentRow(WidgetRef ref, Payment p, Currency currency) {
    return KoruRow(
      title: '${money(p.amount)} ${currency.code}',
      subtitle: p.note == null
          ? formatDate(p.date, DateTime.now())
          : '${formatDate(p.date, DateTime.now())}  ·  ${p.note}',
      trailing: IconButton(
        tooltip: 'Undo this payment',
        icon: const Icon(Icons.undo_rounded, size: KoruSize.icon),
        visualDensity: VisualDensity.compact,
        onPressed: () async {
          final store = await ref.read(storeProvider.future);
          await store.deletePayment(p.id!);
          _refresh(ref);
        },
      ),
    );
  }

  Widget _deadlineRow(WidgetRef ref, Deadline d, DateTime today) {
    final late = d.isOverdueOn(today);
    return KoruRow(
      title: d.title,
      subtitle: late
          ? 'was due ${formatDate(d.due, DateTime.now())}'
          : 'due ${formatDate(d.due, DateTime.now())}',
      subtitleIn: late ? KoruColors.clay : null,
      accent: late ? KoruColors.clay : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Mark ${d.title} done',
            icon: Icon(
              Icons.radio_button_unchecked_rounded,
              size: KoruSize.icon,
              color: KoruColors.inkFaint,
            ),
            visualDensity: VisualDensity.compact,
            onPressed: () async {
              final store = await ref.read(storeProvider.future);
              await store.setDeadlineDone(d.id!, true);
              ref.invalidate(openDeadlinesProvider);
            },
          ),
          IconButton(
            tooltip: 'Delete ${d.title}',
            icon: const Icon(Icons.close_rounded, size: KoruSize.icon),
            visualDensity: VisualDensity.compact,
            onPressed: () async {
              final store = await ref.read(storeProvider.future);
              await store.deleteDeadline(d.id!);
              ref.invalidate(openDeadlinesProvider);
            },
          ),
        ],
      ),
    );
  }

  /// Puts next month's retainer on the calendar.
  ///
  /// The whole reason a retainer is worth a field of its own is that it is the
  /// same amount every month, and a job you retype each month is the chore the
  /// feature exists to remove.
  Future<void> _addNextRetainerDeadline(
    BuildContext context,
    WidgetRef ref,
    Client client,
  ) async {
    final store = await ref.read(storeProvider.future);
    final next = await store.nextRetainerDue(client);
    if (next == null) {
      // Never paid, so there is no anchor for "next month" and guessing one
      // would be a date nobody agreed to.
      if (context.mounted) {
        toast(context, 'Record a payment first, then this will know when the next is due');
      }
      return;
    }
    final open = await store.deadlines(clientId: client.id!);
    final stamp = _RetainerPanel.iso(next);
    if (open.any((d) => d.due == stamp && d.title.contains('Retainer'))) {
      if (context.mounted) toast(context, 'Already on the calendar for $stamp');
      return;
    }
    await store.addDeadline(Deadline(
      clientId: client.id,
      title: '${client.name} retainer',
      due: stamp,
    ));
    ref.invalidate(openDeadlinesProvider);
    if (context.mounted) toast(context, 'Retainer due $stamp added');
  }

  static void _refresh(WidgetRef ref) {
    ref
      ..invalidate(clientsProvider)
      ..invalidate(paymentsProvider)
      ..invalidate(receivedTotalsProvider)
      ..invalidate(openDeadlinesProvider)
      ..invalidate(guideFactsProvider);
  }
}

/// Last paid and next due, for a client paid on a standing agreement.
///
/// Deliberately a readout rather than a new money calculation. The question this
/// answers is "is the retainer actually turning up", and that is a question
/// about payment dates, not about invoice balances.
class _RetainerPanel extends ConsumerWidget {
  const _RetainerPanel({required this.client, required this.onAddNext});

  final Client client;
  final VoidCallback onAddNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!client.isRetainer) return const SizedBox.shrink();
    final currency = ref.watch(currencyProvider).valueOrNull ?? defaultCurrency;

    return FutureBuilder<({DateTime? last, DateTime? next})>(
      future: () async {
        final store = await ref.read(storeProvider.future);
        return (
          last: await store.lastPaymentOn(client.id!),
          next: await store.nextRetainerDue(client),
        );
      }(),
      builder: (context, snap) {
        final last = snap.data?.last;
        final next = snap.data?.next;
        final today = DateTime.now();
        final late = next != null && next.isBefore(today);
        final tone = late ? KoruTones.clay : KoruTones.leaf;
        final subtitle = last == null
            ? 'Never paid. A retainer that has not started is not income.'
            : late
                ? 'Was due ${formatDay(next, DateTime.now())} and has not landed'
                : 'Next due ${formatDay(next!, DateTime.now())}';
        return KoruCard(
          background: tone.fill,
          accent: tone.ink,
          elevated: false,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KoruIconBadge(
                icon: Icons.autorenew_rounded,
                color: tone.ink,
                background: KoruColors.surface,
              ),
              const SizedBox(width: KoruSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${money(client.monthly!)} ${currency.code} per month',
                      style: KoruType.rowTitle,
                    ),
                    const SizedBox(height: KoruSpace.xs),
                    Text(
                      subtitle,
                      style: KoruType.body.copyWith(
                        fontSize: 13,
                        color: late ? KoruColors.clay : KoruColors.inkSoft,
                      ),
                    ),
                    if (last != null) ...[
                      const SizedBox(height: KoruSpace.sm),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: onAddNext,
                          icon: const Icon(
                            Icons.event_repeat_rounded,
                            size: KoruSize.iconSm,
                          ),
                          label: const Text('Add next one to my list'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}