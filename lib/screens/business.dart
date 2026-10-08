import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../guide.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

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
          ? 'Amounts are in AED.'
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
                  decoration: const InputDecoration(labelText: 'Amount', suffixText: 'AED'),
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
      ref.invalidate(clientsProvider);
      if (context.mounted) {
        toast(context, existing == null ? 'Client added' : 'Client updated');
      }
    }
  }

  static String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _takePayment(BuildContext context, WidgetRef ref, Client c) async {
    final paid = double.tryParse(c.amount?.toStringAsFixed(2) ?? '');
    final controller = TextEditingController(
      text: paid == null ? '' : paid.toStringAsFixed(0),
    );
    final ok = await showKoruSheet<bool>(
      context,
      title: 'Mark ${c.name} paid',
      subtitle: 'Updates the record and the totals straight away.',
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount received', suffixText: 'AED'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mark as paid'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final store = await ref.read(storeProvider.future);
    final amount = double.tryParse(controller.text.trim());
    await store.updateClient(c.copyWith(
      status: 'paid',
      amount: amount ?? c.amount,
    ));
    ref.invalidate(clientsProvider);
    if (context.mounted) toast(context, '${c.name} marked paid');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clients = ref.watch(clientsProvider);
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
          final paid = list.where((c) => c.status == 'paid').length;
          final pending = list.where((c) => c.status == 'delivered').length;
          final pipeline = list.where((c) => c.status == 'lead' || c.status == 'active').length;
          final overdue = list.where((c) => c.isOverdueOn(today)).toList();

          double sum(Iterable<Client> xs) => xs.fold(0.0, (a, c) => a + (c.amount ?? 0));

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
                      label: 'PAID',
                      value: '$paid',
                      sub: 'settled',
                      tint: KoruColors.leaf,
                      tintBg: KoruColors.leafSoft,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StatTile(
                      label: 'PENDING',
                      value: '$pending',
                      sub: 'delivered, unpaid',
                      tint: KoruColors.clay,
                      tintBg: KoruColors.claySoft,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StatTile(
                      label: 'PIPELINE',
                      value: '$pipeline',
                      sub: 'leads + active',
                      tint: KoruColors.gold,
                      tintBg: KoruColors.goldSoft,
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
                          '${overdue.length} past the due date: ${overdue.map((c) => c.name).join(', ')}',
                          style: const TextStyle(fontSize: 13.5, color: KoruColors.ink, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 4, top: 4),
                child: Text(
                  'Open ${sum(list.where((c) => c.status != 'paid' && c.status != 'lost')).toStringAsFixed(0)} AED across pending work.',
                  style: const TextStyle(color: KoruColors.inkSoft, fontSize: 13.5),
                ),
              ),
              const SizedBox(height: 14),
              if (list.isEmpty)
                EmptyHint(
                  icon: Icons.folder_open_rounded,
                  title: 'No clients yet',
                  body: 'Add your first client to start tracking delivered versus pending.',
                  action: FilledButton(
                    onPressed: () => _edit(context, ref),
                    child: const Text('Add a client'),
                  ),
                ),
              ...list.map((c) => _row(context, ref, c, today, statusColor, statusBg)),
            ],
          );
        },
      ),
    );
  }

  Widget _row(
    BuildContext context,
    WidgetRef ref,
    Client c,
    DateTime today,
    Color Function(String) sc,
    Color Function(String) sb,
  ) {
    final overdue = c.isOverdueOn(today);
    final meta = <String>[
      if (c.amount != null) '${c.amount!.toStringAsFixed(0)} AED',
      if (c.leadSource != null) 'via ${c.leadSource}',
      if (c.parsedDue != null) 'due ${c.due}',
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: KoruColors.surface,
        borderRadius: BorderRadius.circular(KoruRadius.card),
        border: Border.all(color: overdue ? KoruColors.clay : KoruColors.line),
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
                  if (v == 'paid' && c.status != 'paid') {
                    await _takePayment(context, ref, c);
                    return;
                  }
                  final store = await ref.read(storeProvider.future);
                  await store.setClientStatus(c.id!, v);
                  ref.invalidate(clientsProvider);
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
          if (overdue) ...[
            const SizedBox(height: 8),
            const KoruPill(
              label: 'OVERDUE',
              color: KoruColors.clay,
              background: KoruColors.claySoft,
              icon: Icons.error_outline_rounded,
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
              if (c.status != 'paid' && c.status != 'lost')
                TextButton.icon(
                  onPressed: () => _takePayment(context, ref, c),
                  icon: const Icon(Icons.payments_outlined, size: 16),
                  label: const Text('Mark paid'),
                ),
              const Spacer(),
              IconButton(
                tooltip: 'Delete ${c.name}',
                icon: const Icon(Icons.delete_outline_rounded, size: 19, color: KoruColors.inkFaint),
                onPressed: () async {
                  final store = await ref.read(storeProvider.future);
                  await store.deleteClient(c.id!);
                  ref.invalidate(clientsProvider);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
