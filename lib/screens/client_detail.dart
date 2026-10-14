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
        appBar: AppBar(),
        body: clients == null
            ? Center(child: CircularProgressIndicator(color: KoruColors.leaf))
            : const EmptyHint(
                icon: Icons.person_off_outlined,
                title: 'That client is gone',
                body: 'They were deleted from the list.',
              ),
      );
    }

    final currency = ref.watch(currencyProvider).valueOrNull ?? defaultCurrency;
    final balance = client.balanceWith(received[clientId] ?? 0);
    final today = DateTime.now();

    return Scaffold(
      appBar: AppBar(title: Text(client.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _statusPill(client, balance, currency),
          const SizedBox(height: 14),
          _moneySummary(client, balance, received[clientId] ?? 0, currency),
          if (client.isRetainer) ...[
            const SizedBox(height: 14),
            _RetainerPanel(
              client: client,
              onAddNext: () => _addNextRetainerDeadline(context, ref, client),
            ),
          ],
          if (client.note != null && client.note!.trim().isNotEmpty) ...[
            const SizedBox(height: 18),
            const SectionLabel('Note'),
            const SizedBox(height: 6),
            Text(
              client.note!,
              style: TextStyle(fontSize: 14, color: KoruColors.inkSoft, height: 1.5),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(child: SectionLabel('Payments')),
              if (payments.isNotEmpty)
                Text(
                  '${payments.length} recorded',
                  style: TextStyle(fontSize: 12, color: KoruColors.inkFaint),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (payments.isEmpty)
            Text(
              'Nothing recorded. Tap "Record payment" on the Business screen when '
              'money comes in.',
              style: TextStyle(fontSize: 13, color: KoruColors.inkFaint, height: 1.4),
            )
          else
            ...payments.map((p) => _paymentRow(ref, p, currency)),
          const SizedBox(height: 18),
          const SectionLabel('Deadlines'),
          const SizedBox(height: 4),
          if (deadlines.isEmpty)
            Text(
              'Nothing scheduled for this client.',
              style: TextStyle(fontSize: 13, color: KoruColors.inkFaint, height: 1.4),
            )
          else
            ...deadlines.map((d) => _deadlineRow(ref, d, today)),
        ],
      ),
    );
  }

  Widget _statusPill(Client c, double balance, Currency currency) {
    final (color, background) = switch (c.status) {
      'paid' => (KoruColors.leaf, KoruColors.leafSoft),
      'active' => (KoruColors.gold, KoruColors.goldSoft),
      'delivered' => (KoruColors.clay, KoruColors.claySoft),
      _ => (KoruColors.inkSoft, const Color(0xFFEFEBE7)),
    };
    final late = c.isOverdueOn(DateTime.now());
    return Row(
      children: [
        KoruPill(label: c.status.toUpperCase(), color: color, background: background),
        if (balance > 0) ...[
          const SizedBox(width: 8),
          KoruPill(
            label: '${money(balance)} ${currency.code} OUTSTANDING',
            color: late ? KoruColors.clay : KoruColors.gold,
            background: late ? KoruColors.claySoft : KoruColors.goldSoft,
          ),
        ],
        if (c.isRetainer) ...[
          const SizedBox(width: 8),
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
    ];
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
          Text(
            balance > 0 ? money(balance) : money(received),
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              color: KoruColors.ink,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            balance > 0
                ? '${currency.code} still owed'
                : '${currency.code} received, nothing outstanding',
            style: TextStyle(fontSize: 13, color: KoruColors.inkFaint),
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              meta.join('  ·  '),
              style: TextStyle(fontSize: 12.5, color: KoruColors.inkSoft),
            ),
          ],
        ],
      ),
    );
  }

  Widget _paymentRow(WidgetRef ref, Payment p, Currency currency) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: KoruColors.surface,
        borderRadius: BorderRadius.circular(KoruRadius.card),
        border: Border.all(color: KoruColors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${money(p.amount)} ${currency.code}',
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  p.note == null
                      ? formatDate(p.date, DateTime.now())
                      : '${formatDate(p.date, DateTime.now())}  ·  ${p.note}',
                  style: TextStyle(fontSize: 12.5, color: KoruColors.inkFaint),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Undo this payment',
            icon: Icon(Icons.undo_rounded, size: 18, color: KoruColors.inkFaint),
            onPressed: () async {
              final store = await ref.read(storeProvider.future);
              await store.deletePayment(p.id!);
              _refresh(ref);
            },
          ),
        ],
      ),
    );
  }

  Widget _deadlineRow(WidgetRef ref, Deadline d, DateTime today) {
    final late = d.isOverdueOn(today);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
      decoration: BoxDecoration(
        color: KoruColors.surface,
        borderRadius: BorderRadius.circular(KoruRadius.card),
        border: Border.all(color: late ? KoruColors.clay : KoruColors.line),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Mark ${d.title} done',
            icon: Icon(Icons.radio_button_unchecked_rounded, color: KoruColors.inkFaint),
            onPressed: () async {
              final store = await ref.read(storeProvider.future);
              await store.setDeadlineDone(d.id!, true);
              ref.invalidate(openDeadlinesProvider);
            },
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.title,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(
                  late
                        ? 'was due ${formatDate(d.due, DateTime.now())}'
                        : 'due ${formatDate(d.due, DateTime.now())}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: late ? KoruColors.clay : KoruColors.inkFaint,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Delete ${d.title}',
            icon: Icon(Icons.close_rounded, size: 18, color: KoruColors.inkFaint),
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
        final subtitle = last == null
            ? 'Never paid. A retainer that has not started is not income.'
            : late
                ? 'Was due ${formatDay(next, DateTime.now())} and has not landed'
                : 'Next due ${formatDay(next!, DateTime.now())}';
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: late ? KoruColors.claySoft : KoruColors.leafSoft,
            borderRadius: BorderRadius.circular(KoruRadius.card),
            border: Border.all(color: late ? KoruColors.clay : KoruColors.leaf),
          ),
          child: Row(
            children: [
              Icon(
                Icons.autorenew_rounded,
                size: 19,
                color: late ? KoruColors.clay : KoruColors.leaf,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${money(client.monthly!)} ${currency.code} per month',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: KoruColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: late ? KoruColors.clay : KoruColors.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
              if (last != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: onAddNext,
                    icon: const Icon(Icons.event_repeat_rounded, size: 17),
                    label: const Text('Add next one to my list'),
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
