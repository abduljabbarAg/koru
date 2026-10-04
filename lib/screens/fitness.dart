import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';

class FitnessScreen extends ConsumerWidget {
  const FitnessScreen({super.key});

  Future<void> _log(BuildContext context, WidgetRef ref) async {
    final w = TextEditingController();
    final waist = TextEditingController();
    final chest = TextEditingController();
    final arm = TextEditingController();
    final leg = TextEditingController();

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
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
              const Text('Log measurements',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text('Leave anything blank you did not measure.',
                  style: TextStyle(color: KoruColors.inkFaint, fontSize: 13)),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: w,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Weight', suffixText: 'kg'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: waist,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Waist', suffixText: 'cm'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: chest,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Chest', suffixText: 'cm'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: arm,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Arm', suffixText: 'cm'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: leg,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Leg', suffixText: 'cm'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );

    if (saved == true) {
      final store = await ref.read(storeProvider.future);
      final height = double.tryParse((await store.get('height')) ?? '');
      await store.addFitness(FitnessEntry(
        day: DateTime.now().toIso8601String().split('T').first,
        weight: double.tryParse(w.text.trim()),
        waist: double.tryParse(waist.text.trim()),
        chest: double.tryParse(chest.text.trim()),
        arm: double.tryParse(arm.text.trim()),
        leg: double.tryParse(leg.text.trim()),
      ));
      ref.invalidate(fitnessProvider);

      final latest = (await store.fitness(limit: 1)).first;
      final bmi = latest.bmi(height ?? 0);
      if (bmi != null) {
        await store.put('bmi', bmi.toStringAsFixed(1));
        await store.put('fitness_summary',
            'weight ${latest.weight!.toStringAsFixed(1)}kg, BMI ${bmi.toStringAsFixed(1)}');
        ref.invalidate(packetProvider);
      }
      if (context.mounted) toast(context, 'Logged');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(fitnessProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Fitness')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _log(context, ref),
        backgroundColor: KoruColors.leaf,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Log'),
      ),
      body: entries.when(
        loading: () => const Center(child: CircularProgressIndicator(color: KoruColors.leaf)),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) {
          return FutureBuilder<String?>(
            future: ref.read(storeProvider.future).then((s) async {
              final h = double.tryParse((await s.get('height')) ?? '');
              if (list.isEmpty || h == null) return null;
              return list.first.bmi(h)?.toStringAsFixed(1);
            }),
            builder: (context, snap) {
              final bmi = snap.data;
              final weight = list.isEmpty ? null : list.first.weight;
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          label: 'BMI',
                          value: bmi ?? '--',
                          sub: 'from weight + height',
                          tint: KoruColors.leaf,
                          tintBg: KoruColors.leafSoft,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: StatTile(
                          label: 'WEIGHT',
                          value: weight == null ? '--' : weight.toStringAsFixed(1),
                          sub: weight == null ? 'not logged' : 'kg latest',
                          tint: KoruColors.clay,
                          tintBg: KoruColors.claySoft,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: StatTile(
                          label: 'LOGS',
                          value: '${list.length}',
                          sub: 'entries',
                          tint: KoruColors.gold,
                          tintBg: KoruColors.goldSoft,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const SectionLabel('History'),
                  if (list.isEmpty)
                    const EmptyHint(
                      icon: Icons.straighten_rounded,
                      title: 'Nothing logged yet',
                      body: 'Log weight and waist weekly. Trends matter more than daily numbers.',
                    ),
                  ...list.take(20).map((e) => _entry(e)),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _entry(FitnessEntry e) {
    final parts = <String>[
      if (e.weight != null) '${e.weight!.toStringAsFixed(1)} kg',
      if (e.waist != null) 'waist ${e.waist!.toStringAsFixed(0)}',
      if (e.chest != null) 'chest ${e.chest!.toStringAsFixed(0)}',
      if (e.arm != null) 'arm ${e.arm!.toStringAsFixed(0)}',
      if (e.leg != null) 'leg ${e.leg!.toStringAsFixed(0)}',
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: KoruColors.surface,
        borderRadius: BorderRadius.circular(KoruRadius.field),
        border: Border.all(color: KoruColors.line),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 74,
            child: Text(e.day,
                style: const TextStyle(
                    color: KoruColors.inkFaint, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(parts.join('  ·  '),
                style: const TextStyle(color: KoruColors.ink, fontSize: 13.5)),
          ),
        ],
      ),
    );
  }
}