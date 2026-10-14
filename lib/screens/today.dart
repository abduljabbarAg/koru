import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../attention.dart';
import '../attention_bridge.dart';
import '../currency.dart';
import '../human_date.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

/// What needs doing today.
///
/// The screen the app exists for. Everything else is a place to look at the
/// records; this is the one that answers "what should I do right now" without
/// the user having to open anything.
///
/// Built on [attentionProvider] rather than recomputing. The same list already
/// feeds the notification, the widget and the launcher badge, so the three can
/// never disagree about what is urgent, and every write invalidates one
/// provider rather than three computations.
class TodayScreen extends ConsumerWidget {
  TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(attentionProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Today'),
        backgroundColor: KoruColors.cream,
        surfaceTintColor: Colors.transparent,
      ),
      backgroundColor: KoruColors.cream,
      body: items.when(
        loading: () => Center(child: CircularProgressIndicator()),
        error: (e, _) => KoruErrorView(
          onRetry: () => ref.invalidate(attentionProvider),
          what: 'work out what is due',
        ),
        data: (list) {
          if (list.isEmpty) return const _AllClear();
          final overdue = list.where((i) => i.kind == AttentionKind.overdueMoney);
          final dueToday = list.where((i) => i.kind == AttentionKind.dueToday);
          final events = list.where((i) => i.kind == AttentionKind.eventToday);
          final rest = list
              .where((i) =>
                  i.kind != AttentionKind.overdueMoney &&
                  i.kind != AttentionKind.dueToday &&
                  i.kind != AttentionKind.eventToday)
              .toList();

          return RefreshIndicator(
            onRefresh: () async {
              ref
                ..invalidate(attentionProvider)
                ..invalidate(clientsProvider)
                ..invalidate(openDeadlinesProvider);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _Summary(items: list),
                SizedBox(height: 18),
                if (overdue.isNotEmpty) ...[
                  _Section(
                    label: 'Overdue',
                    hint: 'Past its date and still unpaid.',
                    children: [
                      for (final i in overdue) _AttentionRow(item: i),
                    ],
                  ),
                ],
                if (dueToday.isNotEmpty) ...[
                  _Section(
                    label: 'Due today',
                    hint: 'Finish these today.',
                    children: [
                      for (final i in dueToday) _AttentionRow(item: i),
                    ],
                  ),
                ],
                if (events.isNotEmpty) ...[
                  _Section(
                    label: 'Happening today',
                    hint: 'Places to be.',
                    children: [
                      for (final i in events) _AttentionRow(item: i),
                    ],
                  ),
                ],
                if (rest.isNotEmpty) ...[
                  _Section(
                    label: 'Coming up',
                    hint: 'Not urgent yet.',
                    children: [
                      for (final i in rest) _AttentionRow(item: i),
                    ],
                  ),
                ],
                SizedBox(height: 8),
                _ProjectGlance(),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The one line at the top: how much is late and how much is owed.
class _Summary extends ConsumerWidget {
  const _Summary({required this.items});

  final List<AttentionItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clients = ref.watch(clientsProvider).valueOrNull ?? const <Client>[];
    final received =
        ref.watch(receivedTotalsProvider).valueOrNull ?? const <int, double>{};
    final overdue =
        items.where((i) => i.kind == AttentionKind.overdueMoney).length;

    double owed = 0;
    for (final c in clients) {
      final id = c.id;
      if (id == null) continue;
      final balance = c.balanceWith(received[id] ?? 0);
      if (balance > 0) owed += balance;
    }
    final symbol = ref.watch(currencyProvider).valueOrNull?.symbol ?? 'AED';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: KoruColors.line),
      ),
      color: KoruColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Still owed',
                      style: TextStyle(
                          fontSize: 12.5, color: KoruColors.inkFaint)),
                  SizedBox(height: 3),
                  Text(
                    '${symbol} ${_plain(owed)}',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: KoruColors.ink),
                  ),
                ],
              ),
            ),
            if (overdue > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: KoruColors.claySoft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$overdue overdue',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: KoruColors.clay),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _plain(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}

class _Section extends StatelessWidget {
  const _Section({
    required this.label,
    required this.hint,
    required this.children,
  });

  final String label;
  final String hint;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 2, left: 2),
          child: Text(label,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700)),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 2),
          child: Text(hint,
              style: TextStyle(
                  fontSize: 12, color: KoruColors.inkFaint)),
        ),
        ...children,
        SizedBox(height: 14),
      ],
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({required this.item});

  final AttentionItem item;

  @override
  Widget build(BuildContext context) {
    final urgent = item.kind == AttentionKind.overdueMoney ||
        item.kind == AttentionKind.dueToday ||
        item.kind == AttentionKind.eventToday;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
      decoration: BoxDecoration(
        color: KoruColors.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: urgent ? KoruColors.clay.withValues(alpha: 0.35) : KoruColors.line,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.title,
              style: TextStyle(
                  fontSize: 14.5, fontWeight: FontWeight.w600)),
          SizedBox(height: 2),
          Text(item.detail,
              style: TextStyle(
                  fontSize: 12.5, color: KoruColors.inkFaint)),
        ],
      ),
    );
  }
}

/// The projects, at a glance.
///
/// Here because the user's own framing was clients, payments and projects, and a
/// Today screen that only counts money would answer half the question. Sorted so
/// the thing that has not moved comes first, which is the one worth looking at.
class _ProjectGlance extends ConsumerWidget {
  const _ProjectGlance();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsProvider).valueOrNull ?? const <Project>[];
    if (projects.isEmpty) return const SizedBox.shrink();

    final stalled = projects.where((p) => _isStalled(p)).toList();
    final shown = stalled.isEmpty ? projects.take(3).toList() : stalled.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Projects going quiet',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 2),
          child: Text(
            stalled.isEmpty
                ? 'Nothing has gone stale.'
                : 'Not touched in a while.',
            style: TextStyle(fontSize: 12, color: KoruColors.inkFaint),
          ),
        ),
        for (final p in shown)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
            decoration: BoxDecoration(
              color: KoruColors.surface,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: KoruColors.line),
            ),
            child: Row(
              children: [
                Icon(
                  p.isPersonal
                      ? Icons.favorite_outline
                      : Icons.work_outline,
                  size: 16,
                  color: p.isPersonal ? KoruColors.clay : KoruColors.leaf,
                ),
                SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name,
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w500)),
                      if (p.progressNote != null &&
                          p.progressNote!.isNotEmpty)
                        Text(
                          p.progressNote!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, color: KoruColors.inkFaint),
                        ),
                    ],
                  ),
                ),
                SizedBox(width: 8),
                Text('${(p.progress * 100).round()}%',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: KoruColors.inkSoft)),
              ],
            ),
          ),
        SizedBox(height: 8),
      ],
    );
  }

  /// Not touched for a fortnight.
  ///
  /// Chosen rather than a week because a project somebody works on every Sunday
  /// would otherwise be shouted at every Monday.
  static bool _isStalled(Project p) {
    final updated = DateTime.tryParse(p.updated.isEmpty ? p.created : p.updated);
    if (updated == null) return false;
    return DateTime.now().difference(updated).inDays >= 14;
  }
}

class _AllClear extends StatelessWidget {
  const _AllClear();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline,
                size: 44, color: KoruColors.leaf),
            SizedBox(height: 12),
            Text('Nothing needs you today',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            SizedBox(height: 6),
            Text(
              'Nothing overdue, nothing due, no calls. Say "add client Bilal '
              'for 2000" in Talk when something comes in.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: KoruColors.inkSoft),
            ),
          ],
        ),
      ),
    );
  }
}