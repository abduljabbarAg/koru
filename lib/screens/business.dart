import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../guide.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

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
        'lost' => const Color(0xFFEFEBE7),
        _ => const Color(0xFFEFEBE7),
      };

  Future<void> _edit(BuildContext context, WidgetRef ref, {Client? existing}) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final amount = TextEditingController(text: existing?.amount?.toStringAsFixed(0) ?? '');
    final source = TextEditingController(text: existing?.leadSource ?? '');
    final note = TextEditingController(text: existing?.note ?? '');
    var status = existing?.status ?? 'lead';
    DateTime? due = existing?.parsedDue;

    final saved = await showKoruSheet<bool>(
      context,
      title: existing == null ? 'New client' : 'Edit client',
      subtitle: existing == null
          ? 'Amounts are in AED. This is what you invoiced them.'
          : 'Changes are kept on this device.',
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Name or company')),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Invoiced', suffixText: 'AED'),
                ),
              ),
              const SizedBox(width: 12),
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
          const SizedBox(height: 12),
          TextField(
            controller: source,
            decoration: const InputDecoration(
                labelText: 'Lead source', hintText: 'referral, twitter, ads...'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: note,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Note', hintText: 'What was agreed?'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                      initialDate: due ?? DateTime.now().add(const Duration(days: 14)),
                    );
                    if (picked != null) due = picked;
                  },
                  icon: const Icon(Icons.event_outlined, size: 18),
                  label: Text(due == null ? 'Add a due date' : _fmtDate(due!)),
                ),
              ),
              if (due != null)
                IconButton(
                  tooltip: 'Clear due date',
                  icon: const Icon(Icons.close_rounded, size: 18, color: KoruColors.inkFaint),
                  onPressed: () => due = null,
                ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(existing == null ? 'Save client' : 'Save changes'),
          ),
        ],
      ),
    );

    if (saved == true && name.text.trim().isNotEmpty) {
      final store = await ref.read(storeProvider.future);
      final record = Client(
        id: existing?.id,
        name: name.text.trim(),
        status: status,
        amount: double.tryParse(amount.text.trim()),
        due: due == null ? null : _fmtDate(due!),
        leadSource: source.text.trim().isEmpty ? null : source.text.trim(),
        note: note.text.trim().isEmpty ? null : note.text.trim(),
        created: existing?.created ?? DateTime.now().toIso8601String(),
      );
      if (existing == null) {
        await store.addClient(record);
      } else {
        await store.updateClient(record);
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
    final store = await ref.read(storeProvider.future);
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
          ? '${money(balance)} AED still outstanding of ${money(c.amount ?? 0)} invoiced.'
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
              suffixText: 'AED',
              helperText: 'Part payments are fine.',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: note,
            decoration: const InputDecoration(
                labelText: 'Note', hintText: 'Invoice 3, transfer, cash...'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await showDatePicker(
                context: ctx,
                firstDate: DateTime.now().subtract(const Duration(days: 365 * 3)),
                lastDate: DateTime.now().add(const Duration(days: 365)),
                initialDate: date,
              );
              if (picked != null) date = picked;
            },
            icon: const Icon(Icons.event_outlined, size: 18),
            label: Text(_fmtDate(date)),
          ),
          const SizedBox(height: 20),
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
          : '${c.name}: ${money(left)} AED still outstanding',
    );
  }

  Future<void> _addDeadline(BuildContext context, WidgetRef ref, List<Client> clients) async {
    final title = TextEditingController();
    final store = await ref.read(storeProvider.future);
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
          const SizedBox(height: 12),
          if (clients.isNotEmpty)
            DropdownButtonFormField<Client>(
              decoration: const InputDecoration(labelText: 'For which client'),
              items: clients
                  .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
                  .toList(),
              onChanged: (v) => client = v,
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await showDatePicker(
                context: ctx,
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                initialDate: date,
              );
              if (picked != null) date = picked;
            },
            icon: const Icon(Icons.event_outlined, size: 18),
            label: Text(_fmtDate(date)),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Add deadline'),
          ),
        ],
      ),
    );

    if (ok != true || title.text.trim().isEmpty) return;
    await store.addDeadline(Deadline(
      clientId: client?.id,
      title: title.text.trim(),
      due: _fmtDate(date),
    ));
    _invalidateMoney(ref);
    if (context.mounted) toast(context, 'Deadline added');
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
    final today = DateTime.now();
    final guide = ref.watch(guideFactsProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Business')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref),
        backgroundColor: KoruColors.leaf,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Client'),
      ),
      body: clients.when(
        loading: () => const Center(child: CircularProgressIndicator(color: KoruColors.leaf)),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) {
          double balanceOf(Client c) => c.id == null ? 0 : c.balanceWith(received[c.id!] ?? 0);
          final outstanding = list.fold(0.0, (a, c) => a + balanceOf(c));
          final receivedTotal =
              received.values.fold(0.0, (a, v) => a + v);
          final owing = list.where((c) => balanceOf(c) > 0).toList()
            ..sort((a, b) => balanceOf(b).compareTo(balanceOf(a)));
          final overdue = owing.where((c) => c.isOverdueOn(today)).toList();
          final byId = {for (final c in list) if (c.id != null) c.id!: c};

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
            children: [
              KoruGuideBanner(
                speech: guide == null ? null : Guide.forBusiness(guide),
                onTap: () {},
              ),
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      label: 'OWED',
                      value: money(outstanding),
                      sub: owing.isEmpty ? 'AED, all clear' : 'AED, ${owing.length} to chase',
                      tint: KoruColors.clay,
                      tintBg: KoruColors.claySoft,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StatTile(
                      label: 'RECEIVED',
                      value: money(receivedTotal),
                      sub: 'AED, all time',
                      tint: KoruColors.leaf,
                      tintBg: KoruColors.leafSoft,
                    ),
                  ),
                  const SizedBox(width: 10),
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
              if (overdue.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: KoruColors.claySoft,
                    borderRadius: BorderRadius.circular(KoruRadius.card),
                    border: Border.all(color: KoruColors.clay),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.schedule_rounded, size: 19, color: KoruColors.clay),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${money(overdue.fold(0.0, (a, c) => a + balanceOf(c)))} AED is late: '
                          '${overdue.take(3).map((c) => c.name).join(', ')}',
                          style: const TextStyle(fontSize: 13.5, color: KoruColors.ink, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Expanded(child: SectionLabel('Deadlines')),
                  TextButton.icon(
                    onPressed: () => _addDeadline(context, ref, list),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Add'),
                  ),
                ],
              ),
              if (deadlines.isEmpty)
                const EmptyHint(
                  icon: Icons.event_available_rounded,
                  title: 'Nothing scheduled',
                  body: 'Add what has to happen next and it sorts itself by urgency.',
                )
              else
                ...deadlines.map((d) => _deadlineRow(context, ref, d, today, byId[d.clientId])),
              const SizedBox(height: 18),
              if (payments.isNotEmpty) ...[
                const SectionLabel('Recent payments'),
                const SizedBox(height: 8),
                ...payments.map((p) => _paymentRow(ref, p, byId[p.clientId])),
              ],
              const SizedBox(height: 18),
              const SectionLabel('Clients'),
              const SizedBox(height: 8),
              if (list.isEmpty)
                EmptyHint(
                  icon: Icons.folder_open_rounded,
                  title: 'No clients yet',
                  body: 'Add your first client to start tracking who owes you what.',
                  action: FilledButton(
                    onPressed: () => _edit(context, ref),
                    child: const Text('Add a client'),
                  ),
                )
              else
                ...list.map((c) => _row(context, ref, c, today, received[c.id] ?? 0,
                    statusColor, statusBg)),
            ],
          );
        },
      ),
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
            icon: const Icon(Icons.radio_button_unchecked_rounded, color: KoruColors.inkFaint),
            onPressed: () => _completeDeadline(ref, d),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => _completeDeadline(ref, d),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(
                    late ? 'was due ${d.due}' : 'due ${d.due}',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: late ? KoruColors.clay : KoruColors.inkFaint,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Delete ${d.title}',
            icon: const Icon(Icons.close_rounded, size: 18, color: KoruColors.inkFaint),
            onPressed: () => _deleteDeadline(ref, d),
          ),
        ],
      ),
    );
  }

  Widget _paymentRow(WidgetRef ref, Payment p, Client? client) {
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
                  '${money(p.amount)} AED  ·  ${client?.name ?? 'unknown'}',
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  p.note == null ? p.date : '${p.date}  ·  ${p.note}',
                  style: const TextStyle(fontSize: 12.5, color: KoruColors.inkFaint),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Undo this payment',
            icon: const Icon(Icons.undo_rounded, size: 18, color: KoruColors.inkFaint),
            onPressed: () => _undoPayment(ref, p),
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    WidgetRef ref,
    Client c,
    DateTime today,
    double alreadyReceived,
    Color Function(String) sc,
    Color Function(String) sb,
  ) {
    final balance = c.balanceWith(alreadyReceived);
    final late = c.isOverdueOn(today);
    final meta = <String>[
      if (c.amount != null) '${money(c.amount!)} AED invoiced',
      if (alreadyReceived > 0) '${money(alreadyReceived)} received',
      if (c.leadSource != null) 'via ${c.leadSource}',
      if (c.parsedDue != null) 'due ${c.due}',
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: KoruColors.surface,
        borderRadius: BorderRadius.circular(KoruRadius.card),
        border: Border.all(color: late ? KoruColors.clay : KoruColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 3),
                    Text(
                      meta.join('  ·  '),
                      style: const TextStyle(color: KoruColors.inkFaint, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                initialValue: c.status,
                color: KoruColors.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
            const SizedBox(height: 8),
            Row(
              children: [
                KoruPill(
                  label: '${money(balance)} AED OUTSTANDING',
                  color: late ? KoruColors.clay : KoruColors.gold,
                  background: late ? KoruColors.claySoft : KoruColors.goldSoft,
                ),
                if (late) ...[
                  const SizedBox(width: 8),
                  const KoruPill(
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
            const SizedBox(height: 8),
            Text(c.note!,
                style: const TextStyle(fontSize: 12.5, color: KoruColors.inkSoft, height: 1.4)),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _edit(context, ref, existing: c),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit'),
              ),
              if (c.status != 'lost')
                TextButton.icon(
                  onPressed: () => _recordPayment(context, ref, c, alreadyReceived),
                  icon: const Icon(Icons.payments_outlined, size: 16),
                  label: Text(alreadyReceived > 0 ? 'Add payment' : 'Mark paid'),
                ),
              const Spacer(),
              IconButton(
                tooltip: 'Delete ${c.name}',
                icon: const Icon(Icons.delete_outline_rounded, size: 19, color: KoruColors.inkFaint),
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
    );
  }
}

/// Whole units, no decimals.
///
/// Balances are compared and summed constantly and a stray cent should never be
/// the reason two figures that are the same money look different.
String money(double v) {
  if (v.abs() >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
  if (v.abs() >= 10000) return '${(v / 1000).toStringAsFixed(0)}k';
  return v.toStringAsFixed(0);
}