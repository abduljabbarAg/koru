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
import 'shell_actions.dart';

/// Who you work for.
///
/// Every client, with their balance, their status and the three things that can
/// be done about them from the row. This screen used to also carry the money,
/// the deadlines and the calendar, which made it the tab people opened and then
/// scrolled past to find the thing they actually came for. It now carries the
/// people; the money is on its own tab, and the work is on the one before this.
///
/// The shape does not depend on whether the data has arrived. Each section shows
/// its own geometry while it is loading and says what is missing when there is
/// genuinely nothing to show, because a list that is "empty" until a query
/// finishes tells somebody they have no clients the first time they open the app
/// after installing it.
class ClientsScreen extends ConsumerWidget {
  const ClientsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clientsAsync = ref.watch(clientsProvider);
    final capacity = ref.watch(capacityProvider).valueOrNull ?? defaultCapacity;
    final currency = ref.watch(currencyProvider).valueOrNull ?? defaultCurrency;
    final received = ref.watch(receivedTotalsProvider).valueOrNull ??
        const <int, double>{};
    final tasks = ref.watch(tasksProvider).valueOrNull ?? const <Task>[];
    final today = DateTime.now();
    final guide = ref.watch(guideFactsProvider).valueOrNull;

    return Scaffold(
      backgroundColor: KoruColors.cream,
      appBar: AppBar(
        title: const Text('Clients'),
        // The same two controls on every tab. They used to be two of the five
        // tabs, which meant being one tap from them cost a place on the bar that
        // was not for doing anything; in the header they are one tap away from
        // wherever the person already is.
        actions: const [TalkButton(), SettingsButton()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        // Named for the same reason the one on the Tasks tab is: every tab is
        // alive at once, two buttons in one route subtree collide on the first
        // push, and a duplicate hero tag is an exception rather than a shrug.
        heroTag: 'clients.add',
        onPressed: () => editClientSheet(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Client'),
      ),
      body: clientsAsync.when(
        loading: () => const KoruLoading(label: 'Loading your clients'),
        error: (e, _) => KoruErrorView(
          onRetry: () => ref.invalidate(clientsProvider),
          what: 'load your clients',
        ),
        data: (list) {
          // Work actually under way. A lead is a hope, and a settled client is
          // history, so neither counts against the limit.
          final underway =
              list.where((c) => c.status == 'active' || c.status == 'delivered').length;
          // Leads and active work, oldest first. Sorted by age because the
          // useful question about a prospect is how long it has been sitting
          // there, and a list in creation order buries that.
          final pipeline = list
              .where((c) => c.status == 'lead' || c.status == 'active')
              .toList()
            ..sort((a, b) => a.created.compareTo(b.created));
          // Work still owed, next to the name it is owed by. On the row rather
          // than only in a total, because the number somebody wants here is
          // "how much is this one".
          final openWork = <int, int>{
            for (final t in tasks.where((t) => !t.done))
              if (t.clientId != null) t.clientId!: 0,
          };
          for (final t in tasks.where((t) => !t.done)) {
            final id = t.clientId;
            if (id != null) openWork[id] = openWork[id]! + 1;
          }

          return KoruSettle(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                KoruSpace.gutter,
                KoruSpace.sml,
                KoruSpace.gutter,
                KoruSpace.aboveFab,
              ),
              children: [
                KoruScreenHeader(
                  eyebrow: list.isEmpty
                      ? null
                      : '${list.length} ${list.length == 1 ? 'client' : 'clients'}',
                  title: 'Who you work for',
                  subtitle: list.isEmpty
                      ? null
                      : 'Tap one for their tasks, their projects and their money.',
                ),
                KoruGuideBanner(
                  speech: guide == null ? null : Guide.forClients(guide),
                  onTap: () {},
                ),
                CapacityMeter(activeCount: underway, capacity: capacity),
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
                      : 'What they owe, and the three things you can do about it.',
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
                        openTasks: openWork[c.id] ?? 0,
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
}