import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../currency.dart';
import '../guide.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'business_rows.dart';
import 'business_sheets.dart';

/// Opens a client. Re-exported because this is where the call lived before the
/// rows moved, and anything that imported it from here keeps working.
export 'business_rows.dart' show openClient;

/// Clients, money, and deadlines.
///
/// The screen is the freelancer loop end to end: who owes you, what has come
/// in, and what is due next. Money is a ledger rather than a status, because
/// "they paid 500 of 2000 today" is the normal case and a single amount plus a
/// settled flag cannot say it. Every figure on screen comes from that ledger,
/// so a balance here and a balance in the store cannot drift apart.
///
/// The order down the page is the order the questions get asked in: how much is
/// owed, what is late, how full is the month, what has to happen next, what
/// came in, what is in the pipeline, and then the full list. Everything above
/// the client list is a summary of it, never a separate source.
///
/// The shape of the page does not depend on whether the data has arrived. Each
/// section shows its own geometry while it is loading and says what is missing
/// when there is genuinely nothing to show, because a list that is "empty"
/// until a query finishes will tell somebody they have no deadlines the first
/// time they open the app after installing it.
class BusinessScreen extends ConsumerWidget {
  const BusinessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clients = ref.watch(clientsProvider);
    final received = ref
            .watch(receivedTotalsProvider).valueOrNull ??
        const <int, double>{};
    final paymentsAsync = ref.watch(paymentsProvider);
    final payments = paymentsAsync.valueOrNull ?? const <Payment>[];
    final deadlinesAsync = ref.watch(openDeadlinesProvider);
    final deadlines = deadlinesAsync.valueOrNull ?? const <Deadline>[];
    final eventsAsync = ref.watch(eventsProvider);
    final events = eventsAsync.valueOrNull ?? const <CalendarEvent>[];
    final capacity = ref.watch(capacityProvider).valueOrNull ?? defaultCapacity;
    final currency = ref.watch(currencyProvider).valueOrNull ?? defaultCurrency;
    final today = DateTime.now();
    final guide = ref.watch(guideFactsProvider).valueOrNull;

    return Scaffold(
      backgroundColor: KoruColors.cream,
      appBar: AppBar(title: const Text('Business')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => editClientSheet(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Client'),
      ),
      body: clients.when(
        loading: () => const KoruLoading(label: 'Loading your clients'),
        error: (e, _) => KoruErrorView(
          onRetry: () => ref.invalidate(clientsProvider),
          what: 'load your clients',
        ),
        data: (list) {
          double balanceOf(Client c) =>
              c.id == null ? 0 : c.balanceWith(received[c.id!] ?? 0);
          final outstanding = list.fold(0.0, (a, c) => a + balanceOf(c));
          final receivedTotal = received.values.fold(0.0, (a, v) => a + v);
          final owing = list.where((c) => balanceOf(c) > 0).toList()
            ..sort((a, b) => balanceOf(b).compareTo(balanceOf(a)));
          // Work actually under way. A lead is a hope, and a settled client is
          // history, so neither counts against the limit.
          final underway = list
              .where((c) => c.status == 'active' || c.status == 'delivered')
              .length;
          // Leads and active work, oldest first. Sorted by age because the
          // useful question about a prospect is how long it has been sitting
          // there, and a list in creation order buries that.
          final pipeline = list
              .where((c) => c.status == 'lead' || c.status == 'active')
              .toList()
            ..sort((a, b) => a.created.compareTo(b.created));
          final overdue = owing.where((c) => c.isOverdueOn(today)).toList();
          final byId = {for (final c in list) if (c.id != null) c.id!: c};
          // A section with nothing in it and a section still being fetched look
          // identical from here, so each one is asked which it is.
          final deadlinesWaiting = deadlinesAsync.isLoading && deadlines.isEmpty;
          final eventsWaiting = eventsAsync.isLoading && events.isEmpty;
          final paymentsWaiting = paymentsAsync.isLoading && payments.isEmpty;

          return KoruSettle(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                KoruSpace.gutter,
                KoruSpace.sml,
                KoruSpace.gutter,
                KoruSpace.aboveFab,
              ),
              children: [
                KoruGuideBanner(
                  speech: guide == null ? null : Guide.forBusiness(guide),
                  onTap: () {},
                ),
                KoruStatRow(
                  children: [
                    StatTile(
                      label: 'OWED',
                      value: money(outstanding),
                      sub: owing.isEmpty
                          ? '${currency.code}, all clear'
                          : '${currency.code}, ${owing.length} to chase',
                      tint: KoruColors.clay,
                      tintBg: KoruColors.claySoft,
                    ),
                    StatTile(
                      label: 'RECEIVED',
                      value: money(receivedTotal),
                      sub: '${currency.code}, all time',
                      tint: KoruColors.leaf,
                      tintBg: KoruColors.leafSoft,
                    ),
                    StatTile(
                      label: 'OVERDUE',
                      value: '${overdue.length}',
                      sub: overdue.isEmpty ? 'nothing late' : 'past due date',
                      tint: overdue.isEmpty
                          ? KoruColors.leaf
                          : KoruColors.clay,
                      tintBg:
                          overdue.isEmpty ? KoruColors.leafSoft : KoruColors.claySoft,
                    ),
                  ],
                ),
                if (overdue.isNotEmpty)
                  KoruNotice(
                    icon: Icons.schedule_rounded,
                    tone: KoruTones.clay,
                    title: 'Behind on payment',
                    message: '${money(overdue.fold(0.0, (a, c) => a + balanceOf(c)))} ${currency.code} is late: '
                        '${overdue.take(3).map((c) => c.name).join(', ')}',
                  ),
                CapacityMeter(activeCount: underway, capacity: capacity),
                // The rules between rows line up under the text rather than
                // running the full width of the card, which is what a list is
                // supposed to do.
                KoruSection(
                  label: 'Deadlines',
                  hint: 'What has to happen next, soonest first.',
                  dividerIndent: KoruSpace.row,
                  action: TextButton.icon(
                    onPressed: () => addDeadlineSheet(context, ref, list),
                    icon: const Icon(Icons.add_rounded, size: KoruSize.icon),
                    label: const Text('Add'),
                  ),
                  empty: deadlinesWaiting
                      ? const KoruListSkeleton(rows: 2)
                      : const EmptyHint(
                          icon: Icons.event_available_rounded,
                          title: 'Nothing scheduled',
                          body: 'Add what has to happen next and it sorts '
                              'itself by urgency.',
                        ),
                  children: [
                    for (final d in deadlines)
                      DeadlineRow(
                        deadline: d,
                        today: today,
                        client: byId[d.clientId],
                      ),
                  ],
                ),
                KoruSection(
                  label: 'Calendar',
                  hint: 'Meetings you have asked Koru to keep.',
                  dividerIndent: KoruSpace.row,
                  action: TextButton.icon(
                    onPressed: () => _addEventHint(context),
                    icon: const Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: KoruSize.iconSm,
                    ),
                    label: const Text('Ask Koru'),
                  ),
                  empty: eventsWaiting
                      ? const KoruListSkeleton(rows: 2, badge: false)
                      : const EmptyHint(
                          icon: Icons.event_rounded,
                          title: 'Nothing on the calendar',
                          body: 'Say "schedule a call with Bilal tomorrow at 3pm" in '
                              'Talk and it lands here, with an option to mirror it to '
                              'your phone calendar.',
                        ),
                  children: [
                    for (final e in events.take(6)) EventRow(event: e),
                  ],
                ),
                if (paymentsWaiting || payments.isNotEmpty)
                  KoruSection(
                    label: 'Recent payments',
                    hint: 'Money in, newest first.',
                    dividerIndent: KoruSpace.row,
                    empty: const KoruListSkeleton(rows: 2, badge: false),
                    children: [
                      for (final p in payments)
                        PaymentRow(
                          payment: p,
                          currency: currency,
                          client: byId[p.clientId],
                        ),
                    ],
                  ),
                if (pipeline.isNotEmpty)
                  KoruSection(
                    label: 'Pipeline (${pipeline.length})',
                    hint: 'Leads and active work, oldest first.',
                    dividerIndent: KoruSpace.row,
                    children: [
                      for (final c in pipeline)
                        PipelineRow(
                          client: c,
                          today: today,
                          currency: currency,
                        ),
                    ],
                  ),
                KoruSection(
                  label: 'Clients',
                  hint: list.isEmpty
                      ? null
                      : 'Tap a client for the whole history and the ledger.',
                  dividerIndent: KoruSpace.row,
                  empty: EmptyHint(
                    icon: Icons.folder_open_rounded,
                    title: 'No clients yet',
                    body: 'Add your first client to start tracking who owes you '
                        'what. Koru can add one for you from Talk.',
                    action: FilledButton(
                      onPressed: () => editClientSheet(context, ref),
                      child: const Text('Add a client'),
                    ),
                  ),
                  children: [
                    for (final c in list)
                      ClientRow(
                        client: c,
                        today: today,
                        currency: currency,
                        received: received[c.id] ?? 0,
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Points at the chat rather than opening a half-featured form: the parser
  /// already understands "schedule a call tomorrow at 3pm", and a second way to
  /// say it is a second thing to keep correct.
  void _addEventHint(BuildContext context) {
    toast(context, 'In Talk, say "schedule a call with Bilal tomorrow at 3pm" '
        'and approve the card.');
  }
}