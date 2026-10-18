import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../currency.dart';
import '../human_date.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'project_detail.dart';
import 'task_sheet.dart';
import 'work_rows.dart';

/// The first match, or null.
///
/// Written out rather than using firstOrNull, which lives in package:collection
/// and is not a dependency here. Reaching for it through a transitive one works
/// until it does not.
Client? _firstClient(Iterable<Client> xs) => xs.isEmpty ? null : xs.first;

/// Everything about one client, in one place.
///
/// The Clients tab is a list to scan, and that is the right shape for "who is
/// late". It is the wrong shape for "what is actually going on with Acme", which
/// is per client and spread across three tables: the invoice, the ledger and the
/// deadlines. Until this screen existed the app had the data and nowhere to show
/// it, which is also why asking the model about a specific client was a guess.
///
/// The order is the order the questions get asked: what do they owe, is that
/// overdue, is there a standing arrangement, what was agreed, what came in,
/// what is still open. The ledger is below the list of payments rather than
/// folded into the headline, because a balance you cannot trace back to the
/// rows that made it is not a balance anybody trusts.
///
/// Their work is on this screen too, not only on the Tasks tab. "What is
/// actually going on with Acme" is one question, and it is spread across three
/// tables: the invoice, the ledger, and now the tasks and projects attached to
/// them. A client is the unit people think in, so this is where their work
/// belongs.
///
/// The bar carries no title. Everywhere else in the app a bar names the screen
/// and the page says whose it is; here the page is one client, and putting the
/// name in both places would say it twice. So the name is the one display line
/// on the page and the bar is left to the back arrow.
class ClientDetailScreen extends ConsumerWidget {
  const ClientDetailScreen({super.key, required this.clientId});

  final int clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clientsAsync = ref.watch(clientsProvider);
    final clients = clientsAsync.valueOrNull;
    final received =
        ref.watch(receivedTotalsProvider).valueOrNull ?? const <int, double>{};
    final paymentsAsync = ref.watch(paymentsProvider);
    final payments = paymentsAsync.valueOrNull
            ?.where((p) => p.clientId == clientId)
            .toList() ??
        const <Payment>[];
    final deadlinesAsync = ref.watch(openDeadlinesProvider);
    final deadlines = deadlinesAsync.valueOrNull
            ?.where((d) => d.clientId == clientId)
            .toList() ??
        const <Deadline>[];
    final projects = ref.watch(projectsProvider).valueOrNull ?? const <Project>[];

    final client =
        clients == null ? null : _firstClient(clients.where((c) => c.id == clientId));
    if (client == null) {
      // Three different situations, three different answers. A failed read used
      // to look like a slow one: the spinner went round forever because the
      // screen had no way of telling that the query had already given up.
      final failed = clientsAsync.hasError && clients == null;
      return Scaffold(
        backgroundColor: KoruColors.cream,
        appBar: AppBar(),
        body: failed
            ? KoruErrorView(
                onRetry: () => ref.invalidate(clientsProvider),
                what: 'open this client',
              )
            : clients == null
                ? const KoruLoading(label: 'Opening this client')
                : const Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(KoruSpace.gutter),
                      child: EmptyHint(
                        icon: Icons.person_off_outlined,
                        title: 'That client is gone',
                        body: 'They were deleted from the list, so there is no '
                            'history left to show. Go back to Clients to see '
                            'who is on it now.',
                      ),
                    ),
                  ),
      );
    }

    final currency = ref.watch(currencyProvider).valueOrNull ?? defaultCurrency;
    final balance = client.balanceWith(received[clientId] ?? 0);
    final today = DateTime.now();

    return Scaffold(
      backgroundColor: KoruColors.cream,
      appBar: AppBar(),
      body: KoruSettle(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            KoruSpace.gutter,
            KoruSpace.sml,
            KoruSpace.gutter,
            KoruSpace.tail,
          ),
          children: [
            KoruScreenHeader(
              eyebrow: 'Client',
              title: client.name,
              subtitle: 'What they owe, what has come in, and what is still open.',
            ),
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
              KoruCard(child: Text(client.note!, style: KoruType.bodyCompact)),
            ],
            _Work(
              clientId: clientId,
              clientName: client.name,
              projects: projects
                  .where((p) => p.clientId == clientId)
                  .toList(),
              today: today,
            ),
            KoruSection(
              label: 'Payments',
              hint: payments.isEmpty ? null : '${payments.length} recorded',
              dividerIndent: KoruSpace.row,
              empty: paymentsAsync.isLoading && payments.isEmpty
                  ? const KoruListSkeleton(rows: 2, badge: false)
                  : const EmptyHint(
                      icon: Icons.payments_outlined,
                      title: 'Nothing recorded yet',
                      body: 'Money only lands here once it is recorded. Say '
                          '"Bilal paid 500" in Talk, or use Record payment on '
                          'the Revenue tab, and the balance follows.',
                    ),
              children: [
                for (final p in payments) _paymentRow(ref, p, currency),
              ],
            ),
            KoruSection(
              label: 'Deadlines',
              hint: 'Still open for this client.',
              dividerIndent: KoruSpace.row,
              empty: deadlinesAsync.isLoading && deadlines.isEmpty
                  ? const KoruListSkeleton(rows: 2)
                  : const EmptyHint(
                      icon: Icons.event_available_rounded,
                      title: 'Nothing scheduled',
                      body: 'Nothing open for this client. Say "add deadline" '
                          'in Talk to put one on the list.',
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

  /// The three facts that decide what happens next, as pills.
  ///
  /// Wraps rather than a Row: a long status, an outstanding balance and a
  /// retainer badge overflowed off the right edge of a narrow phone, and the
  /// rightmost one is the one that got cut.
  Widget _statusPill(Client c, double balance, Currency currency) {
    final tone = KoruTones.status(c.status);
    final late = c.isOverdueOn(DateTime.now());
    return Wrap(
      spacing: KoruSpace.sm,
      runSpacing: KoruSpace.sm,
      children: [
        KoruPill(
          label: c.status.toUpperCase(),
          color: tone.ink,
          background: tone.fill,
        ),
        if (balance > 0)
          KoruPill(
            label: late
                ? '${money(balance)} ${currency.code} OVERDUE'
                : '${money(balance)} ${currency.code} OUTSTANDING',
            color: late ? KoruColors.clay : KoruColors.gold,
            background: late ? KoruColors.claySoft : KoruColors.goldSoft,
            icon: late ? Icons.error_outline_rounded : null,
          ),
        if (c.isRetainer)
          KoruPill(
            label: 'RETAINER',
            color: KoruColors.leaf,
            background: KoruColors.leafSoft,
          ),
      ],
    );
  }

  /// The one figure, and the facts it can be checked against.
  ///
  /// The metadata sits beside the figure rather than under it because these are
  /// the details somebody checks the number against — the invoice it came from,
  /// the number already received, where they came from, how to reach them.
  /// Underneath, they read as a footnote to a total instead of as the evidence
  /// for it.
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
    return KoruMetric(
      label: balance > 0 ? 'Still owed' : 'Received',
      value: money(balance > 0 ? balance : received),
      sub: balance > 0
          ? '${currency.code}, of ${money(c.amount ?? 0)} invoiced'
          : '${currency.code} received, nothing outstanding',
      trailing: meta.isEmpty
          ? null
          : Text(
              meta.join('\n'),
              textAlign: TextAlign.right,
              style: KoruType.meta,
            ),
    );
  }

  Widget _paymentRow(WidgetRef ref, Payment p, Currency currency) {
    return KoruRow(
      title: '${money(p.amount)} ${currency.code}',
      subtitle: p.note == null
          ? formatDate(p.date, DateTime.now())
          : '${formatDate(p.date, DateTime.now())}  ·  ${p.note}',
      trailing: KoruRowAction(
        tooltip: 'Undo this payment',
        icon: Icons.undo_rounded,
        onPressed: () async {
          final store = await ref.read(storeProvider.future);
          await store.deletePayment(p.id!);
          invalidateWorkData(ref);
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
          KoruRowAction(
            tooltip: 'Mark ${d.title} done',
            icon: Icons.radio_button_unchecked_rounded,
            color: KoruColors.inkFaint,
            onPressed: () async {
              final store = await ref.read(storeProvider.future);
              await store.setDeadlineDone(d.id!, true);
              ref.invalidate(openDeadlinesProvider);
            },
          ),
          KoruRowAction(
            tooltip: 'Delete ${d.title}',
            icon: Icons.close_rounded,
            color: KoruColors.inkFaint,
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
    final stamp = isoDate(next);
    if (open.any((d) => d.due == stamp && d.title.contains('Retainer'))) {
      if (context.mounted) toast(context, 'Already on the calendar for ${readableDate(next)}');
      return;
    }
    await store.addDeadline(Deadline(
      clientId: client.id,
      title: '${client.name} retainer',
      due: stamp,
    ));
    ref.invalidate(openDeadlinesProvider);
    if (context.mounted) toast(context, 'Retainer due ${readableDate(next)} added');
  }

}

/// The work being done for this client: their tasks and their projects.
///
/// Two sections rather than one merged list, because a project is a piece of work
/// with a finish line and a task is a step on it, and merging them produced the
/// confusion the task table exists to remove — a 40% project and a single
/// deadline reading as two entries in one list of "things".
///
/// Nothing here opens a project to get at its tasks: the tick is on the row, so
/// finishing a piece of work never means going somewhere else first.
class _Work extends ConsumerWidget {
  const _Work({
    required this.clientId,
    required this.clientName,
    required this.projects,
    required this.today,
  });

  final int clientId;
  final String clientName;
  final List<Project> projects;
  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(tasksProvider);
    final tasks = tasksAsync.valueOrNull
            ?.where((t) => t.clientId == clientId)
            .toList() ??
        const <Task>[];
    final waiting = tasksAsync.isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KoruSection(
          label: 'Tasks',
          hint: 'Open work for ${clientName.replaceAll('  ', ' ')}.',
          dividerIndent: KoruSpace.row,
          action: TextButton.icon(
            onPressed: () => taskSheet(context, ref, clientId: clientId),
            icon: const Icon(Icons.add_rounded, size: KoruSize.icon),
            label: const Text('Add'),
          ),
          empty: waiting && tasks.isEmpty
              ? const KoruListSkeleton(rows: 2)
              : const EmptyHint(
                  icon: Icons.task_alt_rounded,
                  title: 'Nothing open for them',
                  body: 'Work with no client is on the Tasks tab. This is the '
                      'work that belongs to this one.',
                ),
          children: [
            for (final t in orderedTasks(tasks, today))
              TaskRow(
                task: t,
                today: today,
                onTap: () => taskSheet(context, ref, existing: t),
              ),
          ],
        ),
        if (projects.isNotEmpty)
          KoruSection(
            label: 'Projects',
            hint: 'The pieces of work the tasks belong to.',
            dividerIndent: KoruSpace.row,
            children: [
              for (final p in projects) ProjectLineRow(project: p),
            ],
          ),
      ],
    );
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
                      style: KoruType.bodyCompact.copyWith(
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
}