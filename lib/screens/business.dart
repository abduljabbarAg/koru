import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';

class BusinessScreen extends ConsumerWidget {
  const BusinessScreen({super.key});

  static const _statuses = ['lead', 'active', 'delivered', 'paid', 'lost'];

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

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final amount = TextEditingController();
    String status = 'lead';
    String source = '';

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            decoration: const BoxDecoration(
              color: KoruColors.cream,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                        color: KoruColors.line, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const Text('New client',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Name or company'),
                ),
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
                        initialValue: status,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: _statuses
                            .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                            .toList(),
                        onChanged: (v) => setSheet(() => status = v ?? 'lead'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  onChanged: (v) => source = v,
                  decoration: const InputDecoration(
                      labelText: 'Lead source', hintText: 'referral, twitter, ads...'),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Save client'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (saved == true && name.text.trim().isNotEmpty) {
      final store = await ref.read(storeProvider.future);
      await store.addClient(Client(
        name: name.text.trim(),
        status: status,
        amount: double.tryParse(amount.text.trim()),
        leadSource: source.trim().isEmpty ? null : source.trim(),
        created: DateTime.now().toIso8601String(),
      ));
      ref.invalidate(clientsProvider);
      if (context.mounted) toast(context, 'Client added');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clients = ref.watch(clientsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Business')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context, ref),
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

          double sum(Iterable<Client> xs) =>
              xs.fold(0.0, (a, c) => a + (c.amount ?? 0));

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
            children: [
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
                const EmptyHint(
                  icon: Icons.folder_open_rounded,
                  title: 'No clients yet',
                  body: 'Add your first client to start tracking delivered versus pending.',
                ),
              ...list.map((c) => _row(context, ref, c, statusColor, statusBg)),
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
    Color Function(String) sc,
    Color Function(String) sb,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
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
                Text(c.name,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(height: 3),
                Text(
                  [
                    if (c.amount != null) '${c.amount!.toStringAsFixed(0)} AED',
                    if (c.leadSource != null) 'via ${c.leadSource}',
                  ].join('  ·  '),
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
              ref.invalidate(clientsProvider);
            },
            itemBuilder: (_) => _statuses
                .map((s) => PopupMenuItem(
                      value: s,
                      child: Text(s),
                    ))
                .toList(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: sb(c.status),
                borderRadius: BorderRadius.circular(KoruRadius.pill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(c.status,
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700, color: sc(c.status))),
                  const Icon(Icons.arrow_drop_down_rounded, size: 17, color: KoruColors.inkFaint),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 19, color: KoruColors.inkFaint),
            onPressed: () async {
              final store = await ref.read(storeProvider.future);
              await store.deleteClient(c.id!);
              ref.invalidate(clientsProvider);
            },
          ),
        ],
      ),
    );
  }
}