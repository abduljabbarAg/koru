import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../currency.dart';
import '../guide.dart';
import '../human_date.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'business_rows.dart';
import 'business_sheets.dart';
import 'follow_up.dart';
import 'shell_actions.dart';

/// Money: what is owed, by whom, and what has come in.
///
/// The third of the old Business screen, and the reason that screen could never
/// be scanned. Who you work for and what you owe them are two different
/// questions, and they were interleaved on one long page, so "who owes me" and
/// "who do I work for" could not both be the thing you saw first.
///
/// Today is not here. It is the first tab, it answers a different question, and
/// putting a morning's work inside a page about money is how it stopped being
/// read.
class RevenueScreen extends ConsumerWidget {
  const RevenueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clientsAsync = ref.watch(clientsProvider);
    final paymentsAsync = ref.watch(paymentsProvider);
    final payments = paymentsAsync.valueOrNull ?? const <Payment>[];
    final currency = ref.watch(currencyProvider).valueOrNull ?? defaultCurrency;
    final today = DateTime.now();
    final guide = ref.watch(guideFactsProvider).valueOrNull;

    return Scaffold(
      backgroundColor: KoruColors.cream,
      appBar: AppBar(
        title: const Text('Money'),
        // Settings only; "Tell Koru" floats on the bar, and recording a
        // payment keeps its own button on the row it belongs to.
        actions: const [SettingsButton()],
      ),
      body: clientsAsync.when(
        loading: () => const KoruLoading(label: 'Loading what is owed'),
        error: (e, _) => KoruErrorView(
          onRetry: () => ref.invalidate(clientsProvider),
          what: 'work out what you are owed',
        ),
        data: (list) {
          final received = ref.watch(receivedTotalsProvider).valueOrNull ??
              const <int, double>{};
          double balanceOf(Client c) =>
              c.id == null ? 0 : c.balanceWith(received[c.id] ?? 0);
          final outstanding = list.fold(0.0, (a, c) => a + balanceOf(c));
          final receivedTotal = received.values.fold(0.0, (a, v) => a + v);
          // Biggest first. The question on this page is who to chase, and the
          // answer is not the alphabetically first one.
          final owing = list.where((c) => balanceOf(c) > 0).toList()
            ..sort((a, b) => balanceOf(b).compareTo(balanceOf(a)));
          final overdue = owing.where((c) => c.isOverdueOn(today)).toList();
          final byId = {for (final c in list) if (c.id != null) c.id!: c};
          // Every client with a figure on the invoice. This is the invoice list,
          // and it is deliberately not the same list as the one above: what is
          // outstanding can empty over months while the invoices that produced
          // it are still the record of what was agreed.
          final invoiced = list.where((c) => (c.amount ?? 0) > 0).toList()
            ..sort((a, b) => balanceOf(b).compareTo(balanceOf(a)));
          final paymentsWaiting = paymentsAsync.isLoading && payments.isEmpty;

          return KoruSettle(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                KoruSpace.gutter,
                KoruSpace.sml,
                KoruSpace.gutter,
                KoruSpace.tail,
              ),
              children: [
                const KoruScreenHeader(
                  title: 'What you are owed',
                  subtitle: 'Agreed minus received, for everybody. Nothing here '
                      'is a status somebody set by hand.',
                ),
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
                      tint:
                          overdue.isEmpty ? KoruColors.leaf : KoruColors.clay,
                      tintBg: overdue.isEmpty
                          ? KoruColors.leafSoft
                          : KoruColors.claySoft,
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
                KoruSection(
                  label: 'Who owes you',
                  hint: 'Biggest first.',
                  dividerIndent: KoruSpace.row,
                  empty: EmptyHint(
                    icon: Icons.payments_outlined,
                    tint: KoruColors.leaf,
                    tintBg: KoruColors.leafSoft,
                    title: 'Nothing outstanding',
                    body: 'Every client here is settled up. That is rarer than it '
                        'sounds.',
                  ),
                  children: [
                    for (final c in owing)
                      _MoneyRow(
                        client: c,
                        owing: balanceOf(c),
                        currency: currency,
                        today: today,
                      ),
                  ],
                ),
                KoruSection(
                  label: 'Invoices',
                  hint: 'What was agreed, and by when it is due.',
                  dividerIndent: KoruSpace.row,
                  empty: const EmptyHint(
                    icon: Icons.receipt_long_outlined,
                    title: 'No invoices yet',
                    body: 'An invoice is a client with an agreed amount on them. '
                        'Koru works the due date out from the terms you set.',
                  ),
                  children: [
                    for (final c in invoiced)
                      KoruRow(
                        title: c.name,
                        subtitle: [
                          '${money(c.amount!)} ${currency.code} invoiced',
                          if (received[c.id] != null &&
                              received[c.id]! > 0)
                            '${money(received[c.id]!)} received',
                          if (c.daysUntilDue(today) != null)
                            c.isOverdueOn(today)
                                ? 'overdue by ${-c.daysUntilDue(today)!} days'
                                : 'due ${formatDate(c.due, today)}',
                        ].join('  ·  '),
                        accent:
                            c.isOverdueOn(today) ? KoruColors.clay : null,
                        onTap: c.id == null ? null : () => openClient(context, c.id!),
                        body: Row(
                          children: [
                            if (c.id != null &&
                                (c.monthly == null || c.monthly! <= 0) &&
                                c.status != 'lost')
                              TextButton.icon(
                                onPressed: () => recordPaymentSheet(
                                  context,
                                  ref,
                                  c,
                                  received[c.id] ?? 0,
                                ),
                                icon: const Icon(Icons.payments_outlined,
                                    size: KoruSize.iconSm),
                                label: Text(
                                  (received[c.id] ?? 0) > 0
                                      ? 'Add payment'
                                      : 'Mark paid',
                                ),
                              ),
                          ],
                        ),
                      ),
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
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One chase: who, how much, by when, and the one tap that starts it.
///
/// The figure and the client are in the row rather than behind a tap, because a
/// person deciding whether to chase needs to know both before deciding, and the
/// message that goes out has to name the number anyway.
class _MoneyRow extends StatelessWidget {
  const _MoneyRow({
    required this.client,
    required this.owing,
    required this.currency,
    required this.today,
  });

  final Client client;
  final double owing;
  final Currency currency;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final c = client;
    final late = c.isOverdueOn(today);
    final link = c.whatsappLink(message: followUpMessage(c, owing));
    final when = c.daysUntilDue(today);

    return KoruRow(
      onTap: c.id == null ? null : () => openClient(context, c.id!),
      title: c.name,
      subtitle: [
        '${money(owing)} ${currency.code} outstanding',
        if (late)
          'overdue by ${-when!} days'
        else if (when != null)
          'due ${formatDate(c.due, today)}',
      ].join('  ·  '),
      subtitleIn: late ? KoruColors.clay : null,
      accent: late ? KoruColors.clay : null,
      // Indented to the text, not the icon, so the button reads as part of this
      // row's words rather than as a new item in the list.
      body: link == null
          ? null
          : Align(
              alignment: Alignment.centerLeft,
              child: FollowUpButton(link: link),
            ),
    );
  }
}