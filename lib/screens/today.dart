import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../currency.dart';
import '../human_date.dart';
import '../mascot/mascot.dart';
import '../models.dart';
import '../motivation.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import '../work_queue.dart';
import 'business_rows.dart' show openClient;
import 'project_detail.dart';
import 'shell_actions.dart';
import 'task_sheet.dart';
import 'today_rows.dart';

/// What needs doing today.
///
/// The screen the app exists for, and the only one most people open. It used to
/// be a brief: totals, four sections grouped by kind, the projects going quiet,
/// and a line about the weather of the day. All of that is true and none of it
/// is a list of things to do, which is why opening it in the morning produced a
/// feeling of reading a report rather than a feeling of getting on with it.
///
/// So it is one ranked queue now. Every row is a thing that needs doing — money
/// that is late, a task, a deadline, a place to be, a project that has gone
/// quiet — in one order that puts the worst first, and every row opens the thing
/// or ticks it off without going anywhere. The records behind it were all already
/// here; what was missing was the ranking and a way to act.
///
/// Built on [workQueueProvider] so that the list here, the badge on the phone and
/// the notification are reading the same records rather than three answers to
/// the same question.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(workQueueProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Today'),
        backgroundColor: KoruColors.cream,
        surfaceTintColor: KoruColors.nothing,
        // The app's chrome rather than this screen's. Talk and Settings used to
        // be the middle and last tabs, and both of them are things a person
        // reaches for without thinking about where they are, so they live in the
        // header of the screen they will always be able to get back to. A new
        // user gets to their first answer without ever opening Settings.
        actions: const [TalkButton(), SettingsButton()],
      ),
      backgroundColor: KoruColors.cream,
      body: KoruSettle(
        child: queue.when(
          loading: () => _scroll(ref, const [
            _HeroHeader(),
            _Waiting(),
          ]),
          error: (e, _) => _scroll(ref, [
            const _HeroHeader(),
            _Broken(onRetry: () => ref.invalidate(workQueueProvider)),
          ]),
          data: (items) => _scroll(ref, [
            _HeroHeader(brief: WorkQueue.brief(items)),
            _Summary(items: items),
            if (items.isEmpty)
              const _AllClear()
            else
              KoruSection(
                label: 'Do this next',
                hint: 'Late first, then by how pressing it is, then by when '
                    'it is due. Tap a row to open it.',
                dividerIndent: KoruSize.badge + KoruSpace.md,
                children: [
                  for (final item in items) _queueRow(context, ref, item),
                ],
              ),
            const _MorningLine(),
          ]),
        ),
      ),
    );
  }

  /// One row, with the three things that can happen to it: open it, tick it off,
  /// or nothing at all because there is nowhere to go yet.
  Widget _queueRow(BuildContext context, WidgetRef ref, WorkItem item) {
    final clientName = _clientName(ref, item.clientId);
    final currency = ref.watch(currencyProvider).valueOrNull?.code ?? 'AED';

    return QueueRow(
      item: item,
      clientName: clientName,
      currency: currency,
      onOpen: () => _open(context, ref, item),
      onDone: item.kind == WorkKind.task || item.kind == WorkKind.deadline
          ? () => _done(context, ref, item)
          : null,
    );
  }

  /// The client's name, from the list the screen has already loaded.
  ///
  /// Null rather than a lookup that could fail: a queue row about deleted work
  /// still has to say what the work is.
  String? _clientName(WidgetRef ref, int? clientId) {
    if (clientId == null) return null;
    final clients = ref.read(clientsProvider).valueOrNull ?? const <Client>[];
    for (final c in clients) {
      if (c.id == clientId) return c.name;
    }
    return null;
  }

  /// Takes the row to the thing it is about.
  ///
  /// A deadline has no screen of its own to go to, so one that belongs to a
  /// client opens that client, where the deadline is listed. Opening a list when
  /// the row is about one line of it would be worse than the row not being
  /// tappable at all, which is why this is null rather than a guess.
  Future<void> _open(BuildContext context, WidgetRef ref, WorkItem item) async {
    switch (item.kind) {
      case WorkKind.money:
      case WorkKind.deadline:
        final id = item.clientId;
        if (id != null && context.mounted) openClient(context, id);
      case WorkKind.task:
        final task = await _taskFor(ref, item);
        if (task == null || !context.mounted) return;
        await taskSheet(context, ref, existing: task);
      case WorkKind.event:
        // No detail screen for an entry yet; the calendar lives on the Tasks
        // tab, which is where a row about a place to be is edited.
        break;
      case WorkKind.project:
        final id = item.id;
        if (id != null && context.mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ProjectScreen(projectId: id),
            ),
          );
        }
    }
  }

  Future<Task?> _taskFor(WidgetRef ref, WorkItem item) async {
    final store = await ref.read(storeProvider.future);
    final id = item.id;
    return id == null ? null : store.task(id);
  }

  /// Ticks the row off without leaving the screen.
  ///
  /// Both kinds write the same two things — the flag and the moment — so the
  /// archive on the Tasks tab can say when something was finished rather than
  /// only that it is not here any more.
  Future<void> _done(BuildContext context, WidgetRef ref, WorkItem item) async {
    final store = await ref.read(storeProvider.future);
    final id = item.id;
    if (id == null) return;
    if (item.kind == WorkKind.task) {
      await store.setTaskDone(id, true);
    } else {
      await store.setDeadlineDone(id, true);
    }
    invalidateWorkData(ref);
    if (!context.mounted) return;
    toast(context, 'Done: ${item.title}');
  }

  /// The one scroll view, so every state pulls down to refresh the same way.
  ///
  /// Always scrollable even when the content is short, because a list that
  /// fits on the screen cannot otherwise be dragged far enough to reach the
  /// refresh — and an empty morning is exactly when a pull to check again is
  /// most likely.
  Widget _scroll(WidgetRef ref, List<Widget> children) {
    return RefreshIndicator(
      onRefresh: () async {
        ref
          ..invalidate(workQueueProvider)
          ..invalidate(clientsProvider)
          ..invalidate(receivedTotalsProvider)
          ..invalidate(openDeadlinesProvider)
          ..invalidate(tasksProvider);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          KoruSpace.gutter,
          KoruSpace.sml,
          KoruSpace.gutter,
          KoruSpace.tail,
        ),
        children: children,
      ),
    );
  }
}

/// The greeting, the date, and where the day stands.
///
/// The header is the one part of the screen that does not change between
/// states, which is the point: the date is known while the queue is still being
/// worked out, so the screen arrives whole and the data catches up underneath
/// it. The brief under the greeting counts rather than lists, because a greeting
/// that names five things is a list the reader has to read twice.
class _HeroHeader extends StatelessWidget {
  const _HeroHeader({this.brief = ''});

  /// Empty while the queue is still loading, which leaves the line out rather
  /// than reserving space for a sentence that does not exist yet.
  final String brief;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return KoruScreenHeader(
      eyebrow: formatDay(now, now, style: DateStyle.short),
      title: _greetingFor(now),
      subtitle: brief.isEmpty ? null : brief,
      trailing: const KoruMascot(size: 54),
    );
  }

  /// Time of day, in the register the rest of the app talks in.
  static String _greetingFor(DateTime at) {
    if (at.hour < 12) return 'Good morning';
    if (at.hour < 18) return 'Good afternoon';
    return 'Good evening';
  }
}

/// The wait, said out loud rather than shown as a bare ring.
class _Waiting extends StatelessWidget {
  const _Waiting();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: KoruSpace.xxxl * 2),
      child: KoruLoading(label: 'Working out what needs doing'),
    );
  }
}

/// A failure the user can retry from, with the same retry the error view has
/// always had — plus the pull-down, which reaches every state.
class _Broken extends StatelessWidget {
  const _Broken({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: KoruSpace.xxxl),
      child: KoruErrorView(onRetry: onRetry, what: 'work out what needs doing'),
    );
  }
}

/// The one figure worth looking at before anything else: what is still owed,
/// and how much of it is late.
///
/// Above the queue rather than inside it, because it is the answer to "how is
/// this month going" and that is a different question from "what do I do next",
/// which the queue answers one row at a time.
class _Summary extends ConsumerWidget {
  const _Summary({required this.items});

  final List<WorkItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clients = ref.watch(clientsProvider).valueOrNull ?? const <Client>[];
    final received =
        ref.watch(receivedTotalsProvider).valueOrNull ?? const <int, double>{};
    final late = items.where((i) => i.overdue).length;

    double owed = 0;
    for (final c in clients) {
      final id = c.id;
      if (id == null) continue;
      final balance = c.balanceWith(received[id] ?? 0);
      if (balance > 0) owed += balance;
    }
    final symbol = ref.watch(currencyProvider).valueOrNull?.symbol ?? 'AED';

    return KoruCard(
      padding: const EdgeInsets.all(KoruSpace.card),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('STILL OWED', style: KoruType.label),
                const SizedBox(height: KoruSpace.xsm),
                Text('$symbol ${_plain(owed)}', style: KoruType.stat),
              ],
            ),
          ),
          if (late > 0)
            KoruPill(
              label: '$late late',
              color: KoruColors.clay,
              background: KoruColors.claySoft,
              icon: Icons.error_outline,
            ),
        ],
      ),
    );
  }

  static String _plain(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}

/// The all-clear, on the same surface the rest of the app uses for an empty
/// state, and in the green that means settled rather than the grey that means
/// nothing was ever here.
class _AllClear extends StatelessWidget {
  const _AllClear();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: KoruSpace.xs),
      child: EmptyHint(
        icon: Icons.check_circle_outline,
        tint: KoruColors.leaf,
        tintBg: KoruColors.leafSoft,
        title: 'Nothing needs you today',
        body: 'Nothing late, nothing due, no calls. Say "add client Bilal '
            'for 2000" in Talk, or add a task for work that is only yours.',
      ),
    );
  }
}

/// The one quiet line at the foot of the morning.
///
/// Last rather than first, on purpose. The reason to open this app is what is
/// overdue, and a quote in the opening position pushes that down the screen;
/// down here it reads as a closing thought, seen once the work has been. Italic
/// and low-contrast so it reads as an aside rather than another task, and it
/// carries no interaction because there is nothing to do with it.
class _MorningLine extends StatelessWidget {
  const _MorningLine();

  @override
  Widget build(BuildContext context) {
    final q = quoteFor(DateTime.now());
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: KoruSpace.xxs),
      padding: const EdgeInsets.only(top: KoruSpace.xl),
      decoration: BoxDecoration(
        border: Border(top: KoruBorders.hairline()),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            q.text,
            style: KoruType.bodyCompact.copyWith(
              fontStyle: FontStyle.italic,
              height: 1.55,
            ),
          ),
          const SizedBox(height: KoruSpace.xsm),
          Text(q.by, style: KoruType.micro),
        ],
      ),
    );
  }
}