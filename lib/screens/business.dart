import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../attention_bridge.dart';
import '../currency.dart';
import '../guide.dart';
import '../human_date.dart';
import '../local/write_intent.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'client_detail.dart';

/// Clients, money, and deadlines.
///
/// The screen is the freelancer loop end to end: who owes you, what has come
/// in, and what is due next. Money is a ledger rather than a status, because
/// "they paid 500 of 2000 today" is the normal case and a single amount plus a
/// settled flag cannot say it. Every figure on screen comes from that ledger,
/// so a balance here and a balance in the store cannot drift apart.
class BusinessScreen extends ConsumerWidget {
  const BusinessScreen({super.key});

  Color statusColor(String s) => switch (s) {
        'paid' => KoruColors.leaf,
        'active' => KoruColors.gold,
        'delivered' => KoruColors.clay,
        'lost' => KoruColors.inkFaint,
        _ => KoruColors.inkSoft,
      };

  Color statusBg(String s) => switch (s) {
        'paid' => KoruColors.leafSoft,
        'active' => KoruColors.goldSoft,
        'delivered' => KoruColors.claySoft,
        'lost' => KoruColors.surfaceAlt,
        _ => KoruColors.surfaceAlt,
      };

  Future<void> _edit(BuildContext context, WidgetRef ref, {Client? existing}) async {
    // Read before the sheet opens, because the sheet is shown with this context
    // and using it after an await is exactly the thing the linter warns about.
    final currency = ref.read(currencyProvider).valueOrNull ?? defaultCurrency;
    final name = TextEditingController(text: existing?.name ?? '');
    final amount = TextEditingController(text: existing?.amount?.toStringAsFixed(0) ?? '');
    final source = TextEditingController(text: existing?.leadSource ?? '');
    final phone = TextEditingController(text: existing?.phone ?? '');
    final note = TextEditingController(text: existing?.note ?? '');
    final monthly = TextEditingController(text: existing?.monthly?.toStringAsFixed(0) ?? '');
    final deposit =
        TextEditingController(text: existing?.deposit?.toStringAsFixed(0) ?? '');
    var status = existing?.status ?? 'lead';
    // Terms, not a due date. The date is worked out from these two, which is
    // the whole point: typing "due in 14 days" by hand is a thing nobody does,
    // and it is why nothing was ever overdue.
    var invoicedOn = existing?.invoicedOn == null
        ? DateTime.now()
        : DateTime.tryParse(existing!.invoicedOn!) ?? DateTime.now();
    int terms = existing?.termsDays ?? 14;
    // Null means "work out the date for me". A date here overrides the terms,
    // because an explicit date is the one thing the user is certain of.
    DateTime? overrideDue = existing?.termsDays == null ? existing?.parsedDue : null;

    final saved = await showKoruSheet<bool>(
      context,
      title: existing == null ? 'New client' : 'Edit client',
      subtitle: existing == null
          ? 'Amounts are in ${currency.code}. This is what you invoiced them.'
          : 'Changes are kept on this device.',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Name or company')),
          const SizedBox(height: KoruSpace.md),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'Invoiced', suffixText: currency.symbol),
                ),
              ),
              const SizedBox(width: KoruSpace.md),
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String>(
                  value: status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: kClientStatuses
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => status = v ?? 'lead',
                ),
              ),
            ],
          ),
          const SizedBox(height: KoruSpace.md),
          TextField(
            controller: monthly,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Monthly retainer',
              suffixText: currency.symbol,
              helperText: 'Only if they pay you the same amount every month.',
            ),
          ),
          const SizedBox(height: KoruSpace.md),
          TextField(
            controller: source,
            decoration: const InputDecoration(
                labelText: 'Lead source', hintText: 'referral, twitter, ads...'),
          ),
          const SizedBox(height: KoruSpace.md),
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone',
              hintText: '07700 900123',
              helperText: 'Used only to open WhatsApp when you tap follow up.',
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: KoruSpace.md),
          TextField(
            controller: note,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Note', hintText: 'What was agreed?'),
          ),
          const SizedBox(height: KoruSpace.lg),
          const Divider(height: 1),
          const SizedBox(height: KoruSpace.lg),
          const SectionLabel('Payment terms', padding: EdgeInsets.zero),
          const SizedBox(height: KoruSpace.sm + 2),
          TextField(
            controller: deposit,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Deposit already paid',
              suffixText: currency.symbol,
              helperText: 'Only if they paid something up front.',
            ),
          ),
          const SizedBox(height: KoruSpace.md),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: ctx,
                  firstDate: DateTime.now().subtract(const Duration(days: 365 * 2)),
                  lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                  initialDate: invoicedOn,
                  helpText: 'When did you invoice them?',
                );
                if (picked != null) setSheetState(() => invoicedOn = picked);
              },
              icon: const Icon(Icons.receipt_long_outlined, size: KoruSize.icon),
              label: Text('Invoiced ${_fmtDate(invoicedOn)}'),
            ),
          ),
          const SizedBox(height: KoruSpace.md),
          Wrap(
            spacing: KoruSpace.sm,
            runSpacing: KoruSpace.sm,
            children: [
              for (final option in const [
                (label: 'On completion', days: 0),
                (label: 'Net 7', days: 7),
                (label: 'Net 14', days: 14),
                (label: 'Net 30', days: 30),
              ])
                KoruSelectablePill(
                  label: option.label,
                  selected: overrideDue == null && terms == option.days,
                  onTap: () => setSheetState(() {
                    terms = option.days;
                    overrideDue = null;
                  }),
                ),
              KoruSelectablePill(
                label: 'Exact date',
                selected: overrideDue != null,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    firstDate: DateTime.now().subtract(const Duration(days: 365 * 2)),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                    initialDate: overrideDue ?? DateTime.now().add(Duration(days: terms)),
                  );
                  if (picked != null) {
                    setSheetState(() => overrideDue = picked);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: KoruSpace.md),
          // The date the rest of the app will use, shown rather than typed. A
          // figure the app worked out and the user can see is a figure they can
          // catch; a figure they had to type is one they will get wrong.
          Builder(builder: (_) {
            final computed = overrideDue ??
                DateTime(invoicedOn.year, invoicedOn.month, invoicedOn.day + terms);
            return KoruCard(
              padding: const EdgeInsets.all(KoruSpace.md),
              background: KoruColors.leafSoft,
              accent: KoruColors.leaf,
              elevated: false,
              child: Row(
                children: [
                  Icon(
                    Icons.event_available_rounded,
                    size: KoruSize.icon,
                    color: KoruColors.leaf,
                  ),
                  const SizedBox(width: KoruSpace.sm + 2),
                  Expanded(
                    child: Text(
                      overrideDue == null
                          ? 'Due ${_fmtDate(computed)} (${terms == 0 ? 'on completion' : 'net $terms days'})'
                          : 'Due ${_fmtDate(computed)}',
                      style: KoruType.bodyStrong.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: KoruSpace.xl),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(existing == null ? 'Save client' : 'Save changes'),
          ),
        ],
        ),
      ),
    );

    if (saved == true && name.text.trim().isNotEmpty) {
      final store = await ref.read(storeProvider.future);
      final agreed = double.tryParse(amount.text.trim());

      // An agreed amount is required, not optional.
      //
      // Every total on this screen is agreed minus received, so a client saved
      // without one contributes zero to owed, zero to outstanding, and never
      // goes overdue. That is not an edge case, it was the normal outcome of
      // the old form, and it is why the Business page read zero across the
      // board and the notifications had nothing to ever say.
      if (agreed == null || agreed <= 0) {
        if (context.mounted) {
          toast(context, 'Put the amount you agreed with them');
        }
        return;
      }

      final depositValue = double.tryParse(deposit.text.trim()) ?? 0;
      final record = Client(
        id: existing?.id,
        name: name.text.trim(),
        status: status,
        amount: agreed,
        due: overrideDue == null ? null : _fmtDate(overrideDue!),
        leadSource: source.text.trim().isEmpty ? null : source.text.trim(),
        phone: phone.text.trim().isEmpty ? null : phone.text.trim(),
        note: note.text.trim().isEmpty ? null : note.text.trim(),
        created: existing?.created ?? DateTime.now().toIso8601String(),
        monthly: double.tryParse(monthly.text.trim()),
        deposit: depositValue > 0 ? depositValue : null,
        termsDays: overrideDue == null ? terms : null,
        invoicedOn: _fmtDate(invoicedOn),
      );

      int? clientId;
      if (existing == null) {
        clientId = await store.addClient(record);
      } else {
        await store.updateClient(record);
        clientId = existing.id;
      }

      // The deposit goes into the ledger rather than being subtracted from the
      // amount. One place holds money: agreed minus received. A deposit held
      // only on the client row would be a second opinion, and the two would
      // disagree the first time somebody paid something else too.
      if (depositValue > 0 && clientId != null) {
        await store.addPayment(Payment(
          clientId: clientId,
          amount: depositValue,
          date: _fmtDate(invoicedOn),
          note: 'Deposit',
        ));
      }

      _invalidateMoney(ref);
      if (context.mounted) {
        toast(context, existing == null ? 'Client added' : 'Client updated');
      }
    }
  }

  static String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Drops the derived data whenever something that feeds it changes.
  ///
  /// Clients, payments and deadlines all feed the same totals, so one place
  /// lists them. Missing one here is how a screen ends up showing a balance
  /// that was correct a minute ago.
  static void _invalidateMoney(WidgetRef ref) {
    ref.invalidate(clientsProvider);
    ref.invalidate(paymentsProvider);
    ref.invalidate(receivedTotalsProvider);
    ref.invalidate(openDeadlinesProvider);
    ref.invalidate(guideFactsProvider);
  }

  /// Records money arriving, in whole or in part.
  ///
  /// This used to set the client's status to paid and overwrite the invoiced
  /// amount with whatever was typed in, which silently destroyed the original
  /// figure and could not express a part payment at all. It now appends to the
  /// ledger and leaves the invoice alone; the status only moves to paid when
  /// the balance actually reaches zero.
  Future<void> _recordPayment(
    BuildContext context,
    WidgetRef ref,
    Client c,
    double alreadyReceived,
  ) async {
    // Read synchronously: the sheet below is shown with this context, and
    // awaiting anything first is exactly what the linter is warning about.
    final currency = ref.read(currencyProvider).valueOrNull ?? defaultCurrency;
    final balance = c.balanceWith(alreadyReceived);

    // Defaults to what is outstanding, not to the invoice. Offering the full
    // invoice as the default made a second part payment pre-fill with the
    // original figure, which is exactly the number the user did not want.
    final controller = TextEditingController(
      text: balance > 0 ? balance.toStringAsFixed(0) : '',
    );
    final note = TextEditingController();
    var date = DateTime.now();

    final ok = await showKoruSheet<bool>(
      context,
      title: 'Payment from ${c.name}',
      subtitle: balance > 0
          ? '${money(balance)} ${currency.code} still outstanding of ${money(c.amount ?? 0)} invoiced.'
          : 'Nothing outstanding. Recording more will show as overpaid.',
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Amount received',
              suffixText: currency.symbol,
              helperText: 'Part payments are fine.',
            ),
          ),
          const SizedBox(height: KoruSpace.md),
          TextField(
            controller: note,
            decoration: const InputDecoration(
                labelText: 'Note', hintText: 'Invoice 3, transfer, cash...'),
          ),
          const SizedBox(height: KoruSpace.md),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: ctx,
                  firstDate: DateTime.now().subtract(const Duration(days: 365 * 3)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  initialDate: date,
                );
                if (picked != null) date = picked;
              },
              icon: const Icon(Icons.event_outlined, size: KoruSize.icon),
              label: Text(_fmtDate(date)),
            ),
          ),
          const SizedBox(height: KoruSpace.xl),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Record payment'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final amount = double.tryParse(controller.text.trim());
    // A blank or malformed box used to fall back to writing the invoice as
    // received. Silently inventing a payment is worse than refusing it.
    if (amount == null || amount <= 0) {
      if (context.mounted) toast(context, 'Enter an amount first');
      return;
    }

    final store = await ref.read(storeProvider.future);
    await store.addPayment(Payment(
      clientId: c.id!,
      amount: amount,
      date: _fmtDate(date),
      note: note.text.trim().isEmpty ? null : note.text.trim(),
    ));

    // Settles only when the ledger says it is settled. A lost client stays lost
    // even if a payment lands, because resurrecting it is not a payment's job.
    final settled = c.balanceWith(alreadyReceived + amount) <= 0;
    if (settled && c.status != 'paid' && c.status != 'lost') {
      await store.setClientStatus(c.id!, 'paid');
    }

    _invalidateMoney(ref);
    if (!context.mounted) return;
    final left = c.balanceWith(alreadyReceived + amount);
    toast(
      context,
      settled
          ? '${c.name} settled'
          : '${c.name}: ${money(left)} ${currency.code} still outstanding',
    );
  }

  Future<void> _addDeadline(BuildContext context, WidgetRef ref, List<Client> clients) async {
    final title = TextEditingController();
    Client? client;
    var date = DateTime.now().add(const Duration(days: 7));

    final ok = await showKoruSheet<bool>(
      context,
      title: 'New deadline',
      subtitle: 'Something that has to happen, on a date.',
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: title,
            autofocus: true,
            decoration: const InputDecoration(
                labelText: 'What', hintText: 'Send invoice, deliver the site...'),
          ),
          const SizedBox(height: KoruSpace.md),
          if (clients.isNotEmpty)
            DropdownButtonFormField<Client>(
              decoration: const InputDecoration(labelText: 'For which client'),
              items: clients
                  .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
                  .toList(),
              onChanged: (v) => client = v,
            ),
          const SizedBox(height: KoruSpace.md),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: ctx,
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                  initialDate: date,
                );
                if (picked != null) date = picked;
              },
              icon: const Icon(Icons.event_outlined, size: KoruSize.icon),
              label: Text(_fmtDate(date)),
            ),
          ),
          const SizedBox(height: KoruSpace.xl),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Add deadline'),
          ),
        ],
      ),
    );

    if (ok != true || title.text.trim().isEmpty) return;
    final store = await ref.read(storeProvider.future);
    await store.addDeadline(Deadline(
      clientId: client?.id,
      title: title.text.trim(),
      due: _fmtDate(date),
    ));
    _invalidateMoney(ref);
    if (context.mounted) toast(context, 'Deadline added');
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

  Future<void> _completeDeadline(WidgetRef ref, Deadline d) async {
    final store = await ref.read(storeProvider.future);
    await store.setDeadlineDone(d.id!, true);
    ref.invalidate(openDeadlinesProvider);
    ref.invalidate(guideFactsProvider);
  }

  Future<void> _deleteDeadline(WidgetRef ref, Deadline d) async {
    final store = await ref.read(storeProvider.future);
    await store.deleteDeadline(d.id!);
    ref.invalidate(openDeadlinesProvider);
  }

  Future<void> _undoPayment(WidgetRef ref, Payment p) async {
    final store = await ref.read(storeProvider.future);
    await store.deletePayment(p.id!);
    _invalidateMoney(ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clients = ref.watch(clientsProvider);
    final received = ref.watch(receivedTotalsProvider).valueOrNull ?? const <int, double>{};
    final payments = ref.watch(paymentsProvider).valueOrNull ?? const <Payment>[];
    final deadlines = ref.watch(openDeadlinesProvider).valueOrNull ?? const <Deadline>[];
    final events = ref.watch(eventsProvider).valueOrNull ?? const <CalendarEvent>[];
    final capacity = ref.watch(capacityProvider).valueOrNull ?? defaultCapacity;
    final currency = ref.watch(currencyProvider).valueOrNull ?? defaultCurrency;
    final today = DateTime.now();
    final guide = ref.watch(guideFactsProvider).valueOrNull;

    return Scaffold(
      backgroundColor: KoruColors.cream,
      appBar: AppBar(title: const Text('Business')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref),
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
          double balanceOf(Client c) => c.id == null ? 0 : c.balanceWith(received[c.id!] ?? 0);
          final outstanding = list.fold(0.0, (a, c) => a + balanceOf(c));
          final receivedTotal =
              received.values.fold(0.0, (a, v) => a + v);
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

          return KoruSettle(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                KoruSpace.gutter,
                KoruSpace.sm,
                KoruSpace.gutter,
                KoruSpace.aboveFab,
              ),
              children: [
                KoruGuideBanner(
                  speech: guide == null ? null : Guide.forBusiness(guide),
                  onTap: () {},
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: StatTile(
                        label: 'OWED',
                        value: money(outstanding),
                        sub: owing.isEmpty ? '${currency.code}, all clear' : '${currency.code}, ${owing.length} to chase',
                        tint: KoruColors.clay,
                        tintBg: KoruColors.claySoft,
                      ),
                    ),
                    const SizedBox(width: KoruSpace.sm),
                    Expanded(
                      child: StatTile(
                        label: 'RECEIVED',
                        value: money(receivedTotal),
                        sub: '${currency.code}, all time',
                        tint: KoruColors.leaf,
                        tintBg: KoruColors.leafSoft,
                      ),
                    ),
                    const SizedBox(width: KoruSpace.sm),
                    Expanded(
                      child: StatTile(
                        label: 'OVERDUE',
                        value: '${overdue.length}',
                        sub: overdue.isEmpty ? 'nothing late' : 'past due date',
                        tint: overdue.isEmpty ? KoruColors.gold : KoruColors.clay,
                        tintBg: overdue.isEmpty ? KoruColors.goldSoft : KoruColors.claySoft,
                      ),
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
                _capacityBar(underway, capacity),
                // The rules between rows line up under the text rather than
                // running the full width of the card, which is what a list is
                // supposed to do.
                KoruSection(
                  label: 'Deadlines',
                  hint: 'What has to happen next, soonest first.',
                  dividerIndent: KoruSpace.row,
                  action: TextButton.icon(
                    onPressed: () => _addDeadline(context, ref, list),
                    icon: const Icon(Icons.add_rounded, size: KoruSize.icon),
                    label: const Text('Add'),
                  ),
                  empty: const EmptyHint(
                    icon: Icons.event_available_rounded,
                    title: 'Nothing scheduled',
                    body: 'Add what has to happen next and it sorts itself by urgency.',
                  ),
                  children: [
                    for (final d in deadlines)
                      _deadlineRow(context, ref, d, today, byId[d.clientId]),
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
                  empty: const EmptyHint(
                    icon: Icons.event_rounded,
                    title: 'Nothing on the calendar',
                    body: 'Say "schedule a call with Bilal tomorrow at 3pm" in '
                        'Talk and it lands here, with an option to mirror it to '
                        'your phone calendar.',
                  ),
                  children: [
                    for (final e in events.take(6)) _eventRow(context, ref, e),
                  ],
                ),
                if (payments.isNotEmpty)
                  KoruSection(
                    label: 'Recent payments',
                    hint: 'Money in, newest first.',
                    dividerIndent: KoruSpace.row,
                    children: [
                      for (final p in payments)
                        _paymentRow(ref, p, byId[p.clientId], currency),
                    ],
                  ),
                if (pipeline.isNotEmpty)
                  KoruSection(
                    label: 'Pipeline (${pipeline.length})',
                    hint: 'Leads and active work, oldest first.',
                    dividerIndent: KoruSpace.row,
                    children: [
                      for (final c in pipeline)
                        _pipelineRow(context, ref, c, today, currency),
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
                    body: 'Add your first client to start tracking who owes you what.',
                    action: FilledButton(
                      onPressed: () => _edit(context, ref),
                      child: const Text('Add a client'),
                    ),
                  ),
                  children: [
                    for (final c in list)
                      _row(context, ref, c, today, currency,
                          received[c.id] ?? 0, statusColor, statusBg),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
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
  Widget _capacityBar(int activeCount, int capacity) {
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
                Text('$activeCount of $capacity', style: KoruType.rowTitle.copyWith(color: tone.ink)),
                const Spacer(),
                Text(
                  full ? 'at capacity' : '$room free',
                  style: KoruType.meta.copyWith(color: KoruColors.inkSoft),
                ),
              ],
            ),
            const SizedBox(height: KoruSpace.md),
            Row(
              children: [
                for (var i = 0; i < capacity && i < 20; i++) ...[
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: i == capacity - 1 ? 0 : KoruSpace.xs),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          height: 6,
                          color: i < activeCount
                              ? tone.ink
                              : KoruColors.surface.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: KoruSpace.md),
            Text(
              message,
              style: KoruType.body.copyWith(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  /// A prospect, with how long it has been sitting.
  Widget _pipelineRow(
    BuildContext context,
    WidgetRef ref,
    Client c,
    DateTime today,
    Currency currency,
  ) {
    final born = DateTime.tryParse(c.created);
    final days = born == null ? null : today.difference(born).inDays;
    final stale = days != null && days >= 21;
    return KoruRow(
      title: c.name,
      subtitle: [
        if (c.amount != null) '${money(c.amount!)} ${currency.code}',
        if (days != null) days == 0 ? 'added today' : 'added $days days ago',
      ].join('  ·  '),
      subtitleIn: stale ? KoruColors.gold : null,
      onTap: c.id == null
          ? null
          : () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ClientDetailScreen(clientId: c.id!),
                ),
              ),
      trailing: stale
          ? KoruPill(
              label: 'GOING COLD',
              color: KoruColors.gold,
              background: KoruColors.goldSoft,
            )
          : null,
    );
  }

  Widget _deadlineRow(
    BuildContext context,
    WidgetRef ref,
    Deadline d,
    DateTime today,
    Client? client,
  ) {
    final late = d.isOverdueOn(today);
    final label = client == null ? d.title : '${d.title}  ·  ${client.name}';
    return KoruRow(
      title: label,
      subtitle: late
          ? 'was due ${formatDate(d.due, DateTime.now())}'
          : 'due ${formatDate(d.due, DateTime.now())}',
      subtitleIn: late ? KoruColors.clay : null,
      accent: late ? KoruColors.clay : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _rowAction(
            tooltip: 'Mark ${d.title} done',
            icon: Icons.radio_button_unchecked_rounded,
            color: KoruColors.inkFaint,
            onPressed: () => _completeDeadline(ref, d),
          ),
          _rowAction(
            tooltip: 'Put ${d.title} in the calendar',
            icon: Icons.event_outlined,
            onPressed: () => _toCalendar(context, ref, d, client),
          ),
          _rowAction(
            tooltip: 'Delete ${d.title}',
            icon: Icons.close_rounded,
            color: KoruColors.inkFaint,
            onPressed: () => _deleteDeadline(ref, d),
          ),
        ],
      ),
    );
  }

  /// One calendar entry. A time on the left, the thing itself in the middle,
  /// and whether the phone's calendar has a copy on the right.
  Widget _eventRow(BuildContext context, WidgetRef ref, CalendarEvent e) {
    final starts = e.startsAt;
    final dayLabel = starts == null
        ? e.date
        : '${_weekdayShort(starts.weekday)} ${starts.day} ${_monthShort(starts.month)}';
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KoruSpace.row,
        vertical: KoruSpace.md + 2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dayLabel, style: KoruType.rowTitleCompact),
                Text(e.timeLabel, style: KoruType.meta.copyWith(fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: KoruSpace.sm + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.title, style: KoruType.rowTitleCompact),
                if (e.location != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(e.location!, style: KoruType.meta),
                  ),
                if (e.durationMin != null || e.recurrence != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      [
                        if (e.durationMin != null) '${e.durationMin} min',
                        if (e.recurrence != null) e.recurrence!.phrase,
                      ].join(' · '),
                      style: KoruType.meta.copyWith(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          _rowAction(
            tooltip: e.synced
                ? 'Already in your phone calendar'
                : 'Copy to your phone calendar',
            icon: e.synced ? Icons.check_rounded : Icons.event_outlined,
            color: e.synced ? KoruColors.leaf : null,
            onPressed: e.synced ? null : () => _syncEvent(context, ref, e),
          ),
          _rowAction(
            tooltip: 'Change ${e.title}',
            icon: Icons.edit_outlined,
            color: KoruColors.inkFaint,
            onPressed: () => _editEvent(context, ref, e),
          ),
          _rowAction(
            tooltip: 'Delete ${e.title}',
            icon: Icons.close_rounded,
            color: KoruColors.inkFaint,
            onPressed: () => _deleteEvent(ref, e),
          ),
        ],
      ),
    );
  }

  Future<void> _editEvent(
    BuildContext context,
    WidgetRef ref,
    CalendarEvent e,
  ) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EventSheet(event: e),
    );
    if (!context.mounted || changed != true) return;
    ref.invalidate(eventsProvider);
  }

  /// Points at the chat rather than opening a half-featured form: the parser
  /// already understands "schedule a call tomorrow at 3pm", and a second way to
  /// say it is a second thing to keep correct.
  void _addEventHint(BuildContext context) {
    toast(context, 'In Talk, say "schedule a call with Bilal tomorrow at 3pm" '
        'and approve the card.');
  }

  /// Copies one entry to the phone's own calendar, through the same bridge the
  /// chat uses, so an entry created in either place can be mirrored.
  Future<void> _syncEvent(
      BuildContext context, WidgetRef ref, CalendarEvent e) async {
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

  Future<void> _deleteEvent(WidgetRef ref, CalendarEvent e) async {
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

  Widget _paymentRow(WidgetRef ref, Payment p, Client? client, Currency currency) {
    return KoruRow(
      title: '${money(p.amount)} ${currency.code}  ·  ${client?.name ?? 'unknown'}',
      subtitle: p.note == null ? p.date : '${p.date}  ·  ${p.note}',
      trailing: _rowAction(
        tooltip: 'Undo this payment',
        icon: Icons.undo_rounded,
        color: KoruColors.inkFaint,
        onPressed: () => _undoPayment(ref, p),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    WidgetRef ref,
    Client c,
    DateTime today,
    Currency currency,
    double alreadyReceived,
    Color Function(String) sc,
    Color Function(String) sb,
  ) {
    final balance = c.balanceWith(alreadyReceived);
    final late = c.isOverdueOn(today);
    final meta = <String>[
      if (c.amount != null) '${money(c.amount!)} ${currency.code} invoiced',
      if (alreadyReceived > 0) '${money(alreadyReceived)} received',
      if (c.leadSource != null) 'via ${c.leadSource}',
      if (c.parsedDue != null) 'due ${formatDate(c.due, DateTime.now())}',
    ];

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: c.id == null
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ClientDetailScreen(clientId: c.id!),
                  ),
                ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            KoruSpace.row,
            KoruSpace.md,
            KoruSpace.sm,
            KoruSpace.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.name,
                          style: KoruType.rowTitle.copyWith(
                            color: late ? KoruColors.clay : KoruColors.ink,
                          ),
                        ),
                        const SizedBox(height: KoruSpace.xs),
                        Text(
                          meta.join('  ·  '),
                          style: KoruType.meta,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: KoruSpace.sm),
                  PopupMenuButton<String>(
                    initialValue: c.status,
                    onSelected: (v) async {
                      final store = await ref.read(storeProvider.future);
                      await store.setClientStatus(c.id!, v);
                      _invalidateMoney(ref);
                    },
                    itemBuilder: (_) => kClientStatuses
                        .map((s) => PopupMenuItem(value: s, child: Text(s)))
                        .toList(),
                    child: KoruPill(
                      label: c.status.toUpperCase(),
                      color: sc(c.status),
                      background: sb(c.status),
                      icon: Icons.arrow_drop_down_rounded,
                    ),
                  ),
                ],
              ),
              if (balance > 0) ...[
                const SizedBox(height: KoruSpace.sm + 2),
                Row(
                  children: [
                    KoruPill(
                      label: '${money(balance)} ${currency.code} OUTSTANDING',
                      color: late ? KoruColors.clay : KoruColors.gold,
                      background: late ? KoruColors.claySoft : KoruColors.goldSoft,
                    ),
                    if (late) ...[
                      const SizedBox(width: KoruSpace.sm),
                      KoruPill(
                        label: 'OVERDUE',
                        color: KoruColors.clay,
                        background: KoruColors.claySoft,
                        icon: Icons.error_outline_rounded,
                      ),
                    ],
                  ],
                ),
              ],
              if (c.note != null) ...[
                const SizedBox(height: KoruSpace.sm + 2),
                Text(
                  c.note!,
                  style: KoruType.body.copyWith(fontSize: 13),
                ),
              ],
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => _edit(context, ref, existing: c),
                    icon: const Icon(Icons.edit_outlined, size: KoruSize.iconSm),
                    label: const Text('Edit'),
                  ),
                  if (c.status != 'lost')
                    TextButton.icon(
                      onPressed: () => _recordPayment(context, ref, c, alreadyReceived),
                      icon: const Icon(Icons.payments_outlined, size: KoruSize.iconSm),
                      label: Text(alreadyReceived > 0 ? 'Add payment' : 'Mark paid'),
                    ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Delete ${c.name}',
                    icon: const Icon(Icons.delete_outline_rounded, size: KoruSize.icon),
                    onPressed: () async {
                      final store = await ref.read(storeProvider.future);
                      await store.deleteClient(c.id!);
                      _invalidateMoney(ref);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The small icon control at the right of a row.
  ///
  /// Pulled out because a list of deadlines had one set at 18, the calendar had
  /// one at 18 in a different colour and the clients had one at 19. Three sizes
  /// for the same control.
  static Widget _rowAction({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
    Color? color,
  }) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: KoruSize.icon, color: color),
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
    );
  }
}

/// Changes an entry that already exists.
///
/// Every field is filled in with what is already stored, so opening and
/// cancelling cannot half-erase a meeting. The repeat rule is a dropdown rather
/// than a free field because "every week" and "weekly" have to mean one thing
/// between the parser and the form, and a typo in a recurring rule is a meeting
/// that quietly stops repeating.
class _EventSheet extends ConsumerStatefulWidget {
  const _EventSheet({required this.event});

  final CalendarEvent event;

  @override
  ConsumerState<_EventSheet> createState() => _EventSheetState();
}

class _EventSheetState extends ConsumerState<_EventSheet> {
  late final TextEditingController _title;
  late final TextEditingController _location;
  late final TextEditingController _date;
  late final TextEditingController _time;
  late final TextEditingController _duration;
  EventRecurrence? _recurrence;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.event;
    _title = TextEditingController(text: e.title);
    _location = TextEditingController(text: e.location ?? '');
    _date = TextEditingController(text: e.date);
    _time = TextEditingController(text: e.time ?? '');
    _duration = TextEditingController(
      text: e.durationMin == null ? '' : '${e.durationMin}',
    );
    _recurrence = e.recurrence;
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _date.dispose();
    _time.dispose();
    _duration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KoruSheetBody(
      title: 'Change entry',
      subtitle: 'Everything is stored on this phone.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: KoruSpace.sm + 2),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _date,
                  decoration:
                      const InputDecoration(labelText: 'Date (YYYY-MM-DD)'),
                ),
              ),
              const SizedBox(width: KoruSpace.sm + 2),
              Expanded(
                child: TextField(
                  controller: _time,
                  decoration: const InputDecoration(labelText: 'Time (HH:mm)'),
                ),
              ),
            ],
          ),
          const SizedBox(height: KoruSpace.sm + 2),
          TextField(
            controller: _location,
            decoration: const InputDecoration(labelText: 'Where'),
          ),
          const SizedBox(height: KoruSpace.sm + 2),
          TextField(
            controller: _duration,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Length in minutes',
              hintText: 'leave empty for the default',
            ),
          ),
          const SizedBox(height: KoruSpace.md),
          DropdownButtonFormField<EventRecurrence?>(
            value: _recurrence,
            decoration: const InputDecoration(labelText: 'Repeats'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Once')),
              for (final r in EventRecurrence.values)
                DropdownMenuItem(value: r, child: Text(_titleCase(r.phrase))),
            ],
            onChanged: (v) => setState(() => _recurrence = v),
          ),
          const SizedBox(height: KoruSpace.xl),
          Row(
            children: [
              TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, KoruSize.buttonInCard),
                ),
                onPressed: _saving ? null : _save,
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _titleCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Future<void> _save() async {
    setState(() => _saving = true);
    final store = await ref.read(storeProvider.future);
    final e = widget.event;
    final mins = int.tryParse(_duration.text.trim());

    await store.updateEvent(CalendarEvent(
      id: e.id,
      title: _title.text.trim().isEmpty ? e.title : _title.text.trim(),
      date: _date.text.trim(),
      time: _time.text.trim().isEmpty ? null : _time.text.trim(),
      location: _location.text.trim().isEmpty ? null : _location.text.trim(),
      durationMin: mins,
      recurrence: _recurrence,
      note: e.note,
      clientId: e.clientId,
      // A changed date or time means the phone's copy is out of date. Left
      // set, the entry would never sync again and the two calendars would
      // quietly disagree.
      synced: (_date.text.trim() == e.date &&
              (_time.text.trim().isEmpty ? null : _time.text.trim()) == e.time)
          ? e.synced
          : false,
      created: e.created,
    ));
    if (mounted) Navigator.pop(context, true);
  }
}