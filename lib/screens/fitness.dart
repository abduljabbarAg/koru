import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../guide.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

class FitnessScreen extends ConsumerWidget {
  const FitnessScreen({super.key});

  Future<void> _log(BuildContext context, WidgetRef ref, {FitnessEntry? existing}) async {
    final w = TextEditingController(text: existing?.weight?.toString() ?? '');
    final waist = TextEditingController(text: existing?.waist?.toString() ?? '');
    final chest = TextEditingController(text: existing?.chest?.toString() ?? '');
    final arm = TextEditingController(text: existing?.arm?.toString() ?? '');
    final leg = TextEditingController(text: existing?.leg?.toString() ?? '');
    var day = existing?.parsedDay ?? DateTime.now();

    final saved = await showKoruSheet<bool>(
      context,
      title: existing == null ? 'Log measurements' : 'Edit log',
      subtitle: 'Leave anything blank you did not measure.',
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await showDatePicker(
                context: ctx,
                firstDate: DateTime.now().subtract(const Duration(days: 365 * 3)),
                lastDate: DateTime.now(),
                initialDate: day,
              );
              if (picked != null) day = picked;
            },
            icon: const Icon(Icons.event_outlined, size: 18),
            label: Text('${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(existing == null ? 'Save' : 'Save changes'),
          ),
        ],
      ),
    );

    if (saved != true) return;
    final store = await ref.read(storeProvider.future);
    final entry = FitnessEntry(
      id: existing?.id,
      day: _fmtDay(day),
      weight: double.tryParse(w.text.trim()),
      waist: double.tryParse(waist.text.trim()),
      chest: double.tryParse(chest.text.trim()),
      arm: double.tryParse(arm.text.trim()),
      leg: double.tryParse(leg.text.trim()),
    );
    if (existing == null) {
      await store.addFitness(entry);
    } else {
      await store.updateFitness(entry);
    }
    // Keep the packet in step with the logs, otherwise a cloud answer would
    // quote a weight the user already changed.
    await store.refreshFitnessSummary();
    ref.invalidate(fitnessProvider);
    ref.invalidate(packetProvider);
    if (context.mounted) toast(context, existing == null ? 'Logged' : 'Log updated');
  }

  static String _fmtDay(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(fitnessProvider);
    final height = ref.watch(heightProvider);
    final guide = ref.watch(guideFactsProvider).valueOrNull;

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
          final bmi = height.value == null ? null : _latestBmi(list, height.value!);
          final weight = list.isEmpty ? null : list.first.weight;
          final trend = _trendPerWeek(list);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
            children: [
              KoruGuideBanner(
                speech: guide == null ? null : Guide.forFitness(guide),
                onTap: () {},
              ),
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      label: 'BMI',
                      value: bmi?.toStringAsFixed(1) ?? '--',
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
                      label: 'TREND',
                      value: trend == null
                          ? '--'
                          : '${trend > 0 ? '+' : ''}${trend.toStringAsFixed(2)}',
                      sub: trend == null ? 'need 2 logs' : 'kg per week',
                      tint: KoruColors.gold,
                      tintBg: KoruColors.goldSoft,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (list.length >= 2) ...[
                const SectionLabel('Weight trend'),
                Container(
                  height: 150,
                  padding: const EdgeInsets.fromLTRB(8, 14, 14, 6),
                  decoration: BoxDecoration(
                    color: KoruColors.surface,
                    borderRadius: BorderRadius.circular(KoruRadius.card),
                    border: Border.all(color: KoruColors.line),
                  ),
                  child: TrendChart(entries: list),
                ),
                const SizedBox(height: 20),
              ],
              const SectionLabel('History'),
              if (list.isEmpty)
                EmptyHint(
                  icon: Icons.straighten_rounded,
                  title: 'Nothing logged yet',
                  body: 'Log weight and waist weekly. Trends matter more than daily numbers.',
                  action: FilledButton(
                    onPressed: () => _log(context, ref),
                    child: const Text('Log the first one'),
                  ),
                ),
              ...list.take(30).map((e) => _entry(context, ref, e, height.value)),
            ],
          );
        },
      ),
    );
  }

  static double? _latestBmi(List<FitnessEntry> list, double heightM) {
    for (final e in list) {
      final b = e.bmi(heightM);
      if (b != null) return b;
    }
    return null;
  }

  /// Weight change per week across the whole log, or null when the history is too
  /// short or too compressed to mean anything.
  static double? _trendPerWeek(List<FitnessEntry> list) {
    final points = <({DateTime day, double kg})>[];
    for (final e in list) {
      final kg = e.weight;
      final day = e.parsedDay;
      if (kg == null || day == null) continue;
      points.add((day: day, kg: kg));
    }
    if (points.length < 2) return null;
    final newest = points.first;
    final oldest = points.last;
    final days = newest.day.difference(oldest.day).inDays;
    if (days < 3) return null;
    return (newest.kg - oldest.kg) / (days / 7.0);
  }

  Widget _entry(BuildContext context, WidgetRef ref, FitnessEntry e, double? height) {
    final parts = <String>[
      if (e.weight != null) '${e.weight!.toStringAsFixed(1)} kg',
      if (e.waist != null) 'waist ${e.waist!.toStringAsFixed(0)}',
      if (e.chest != null) 'chest ${e.chest!.toStringAsFixed(0)}',
      if (e.arm != null) 'arm ${e.arm!.toStringAsFixed(0)}',
      if (e.leg != null) 'leg ${e.leg!.toStringAsFixed(0)}',
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
      decoration: BoxDecoration(
        color: KoruColors.surface,
        borderRadius: BorderRadius.circular(KoruRadius.field),
        border: Border.all(color: KoruColors.line),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(e.day,
                style: const TextStyle(
                    color: KoruColors.inkFaint, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(parts.join('  ·  '),
                style: const TextStyle(color: KoruColors.ink, fontSize: 13.5)),
          ),
          if (height != null && e.bmi(height) != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: KoruPill(
                label: e.bmi(height)!.toStringAsFixed(1),
                color: KoruColors.leaf,
                background: KoruColors.leafSoft,
              ),
            ),
          IconButton(
            tooltip: 'Edit log from ${e.day}',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.edit_outlined, size: 17, color: KoruColors.inkFaint),
            onPressed: () => _log(context, ref, existing: e),
          ),
          IconButton(
            tooltip: 'Delete log from ${e.day}',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.delete_outline_rounded, size: 17, color: KoruColors.inkFaint),
            onPressed: () async {
              final store = await ref.read(storeProvider.future);
              await store.deleteFitness(e.id!);
              ref.invalidate(fitnessProvider);
              ref.invalidate(packetProvider);
              if (context.mounted) toast(context, 'Log deleted');
            },
          ),
        ],
      ),
    );
  }
}

/// Weight over time.
///
/// Deliberately hand drawn rather than pulled from a charting package: it is one
/// polyline, and the app should not take a dependency to render it.
class TrendChart extends StatelessWidget {
  const TrendChart({super.key, required this.entries});

  /// Newest first, the order the store returns.
  final List<FitnessEntry> entries;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _TrendPainter(entries: entries),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({required this.entries});

  final List<FitnessEntry> entries;

  @override
  void paint(Canvas canvas, Size size) {
    final ordered = entries.where((e) => e.weight != null).toList().reversed.toList();
    if (ordered.length < 2) return;
    final values = ordered.map((e) => e.weight!).toList();
    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final span = (maxV - minV).abs() < 0.1 ? 1.0 : maxV - minV;

    const left = 34.0;
    const top = 8.0;
    final right = size.width - 8;
    final bottom = size.height - 18;

    // Grid and axis labels.
    final grid = Paint()
      ..color = KoruColors.line
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final y = top + (bottom - top) * (i / 2);
      canvas.drawLine(Offset(left, y), Offset(right, y), grid);
      final labelValue = maxV - span * (i / 2);
      _text(canvas, labelValue.toStringAsFixed(1), Offset(2, y - 7),
          const TextStyle(fontSize: 10, color: KoruColors.inkFaint));
    }

    final path = Path();
    for (var i = 0; i < ordered.length; i++) {
      final x = ordered.length == 1
          ? left
          : left + (right - left) * (i / (ordered.length - 1));
      final t = (values[i] - minV) / span;
      final y = bottom - (bottom - top) * t;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 3.2, Paint()..color = KoruColors.leaf);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = KoruColors.leaf
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final first = ordered.first;
    final last = ordered.last;
    _text(canvas, first.day.substring(5), Offset(left, bottom + 4),
        const TextStyle(fontSize: 10, color: KoruColors.inkFaint));
    _text(canvas, last.day.substring(5), Offset(right - 26, bottom + 4),
        const TextStyle(fontSize: 10, color: KoruColors.inkFaint));
  }

  void _text(Canvas canvas, String value, Offset at, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_TrendPainter old) => old.entries != entries;
}
