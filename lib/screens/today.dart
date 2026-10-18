import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
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
import 'tasks.dart';
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
class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  /// The one scroll view's controller, kept here so the morning card's
  /// "Show me" can bring the work section into view.
  final _list = ScrollController();

  /// Marks the work section, so "Show me" has somewhere exact to go.
  final _workKey = GlobalKey();

  @override
  void dispose() {
    _list.dispose();
    super.dispose();
  }

  /// What "Show me" on the morning card does: put the queue on screen.
  ///
  /// The button used to only dismiss the card, which read as the card being
  /// the whole point — the quote was shown and nothing followed it. What the
  /// person actually asked for by tapping was the work, so the page travels to
  /// the queue once the card has collapsed.
  Future<void> _revealWork() async {
    // One beat, so the card has collapsed and the scroll extent is settled
    // before ensureVisible measures the section.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    final section = _workKey.currentContext;
    // Mounted of the section itself, which is the context being handed over:
    // the page can outlive the section on a rebuild, and scrolling to a
    // context that is no longer in the tree throws.
    if (section == null || !section.mounted) return;
    await Scrollable.ensureVisible(
      section,
      duration: KoruMotion.settle,
      curve: KoruMotion.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final queue = ref.watch(workQueueProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Today'),
        backgroundColor: KoruColors.cream,
        surfaceTintColor: KoruColors.nothing,
        // The app's chrome rather than this screen's. Settings used to be the
        // last tab and Talk the middle one; Talk is the floating action and
        // Settings lives here, because both are things a person reaches for
        // without thinking about where they are. A new user gets to their first
        // answer without ever opening Settings.
        actions: const [SettingsButton()],
      ),
      backgroundColor: KoruColors.cream,
      body: KoruSettle(
        child: queue.when(
          loading: () => _scroll(const [
            _HeroHeader(),
            _Waiting(),
          ]),
          error: (e, _) => _scroll([
            const _HeroHeader(),
            _Broken(onRetry: () => ref.invalidate(workQueueProvider)),
          ]),
          data: (items) => _scroll([
            const _HeroHeader(),
            // The once-a-day moment. Renders nothing until the store has
            // answered, nothing on a day it has already been dismissed, and
            // nothing ever again after the person taps it.
            _MorningRitual(items: items, onShowMe: _revealWork),
            _Summary(items: items),
            // One section, always. It used to appear only once the queue had
            // something in it, which left the emptiest day — a new install, a
            // cleared list — with no way at all to put work on it: the add
            // button and the browse view both lived inside the section that
            // only existed if work already did. This is the app's front door,
            // so adding a task and seeing all of them are reachable from it
            // before anything else is.
            //
            // The section holds work and only work — tasks, deadlines, places
            // to be. Money and quiet projects moved to Notices below, because a
            // list where a late invoice and "call the accountant" sat in the
            // same column asked the reader to work out which was theirs to do.
            KoruSection(
              key: _workKey,
              label: 'Do this next',
              hint: items.isEmpty
                  ? null
                  : 'Late first, then what you said matters, then the '
                      'soonest date.',
              // Add is the everyday action; All work is the browse view. Every
              // task, deadline, place to be and project lives one tap behind
              // the queue that ranks them.
              action: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(
                    onPressed: () => taskSheet(context, ref),
                    icon: const Icon(Icons.add_rounded, size: KoruSize.iconSm),
                    label: const Text('Add'),
                  ),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const TasksScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.checklist_rounded,
                        size: KoruSize.iconSm),
                    label: const Text('All work'),
                  ),
                ],
              ),
              dividerIndent: KoruSize.badge + KoruSpace.md,
              empty: items.isEmpty
                  ? const _AllClear()
                  : _NoTasks(onAdd: () => taskSheet(context, ref)),
              children: [
                for (final item in items)
                  if (_isWork(item)) _queueRow(context, item),
              ],
            ),
            if (items.any((i) => !_isWork(i)))
              KoruSection(
                label: 'Notices',
                hint: 'Money and projects, watched for you. Nothing to tick '
                    'off — they have their own pages.',
                dividerIndent: KoruSize.badge + KoruSpace.md,
                empty: const SizedBox.shrink(),
                children: [
                  for (final item in items)
                    if (!_isWork(item)) _queueRow(context, item),
                ],
              ),
          ]),
        ),
      ),
    );
  }

  /// Whether a queue item is the user's own work.
  ///
  /// Work is what somebody can pick up and do: a task, a deadline they agreed
  /// to, a place to be. Money and projects are things to be aware of rather
  /// than things to tick off, so they are notices.
  static bool _isWork(WorkItem item) =>
      item.kind == WorkKind.task ||
      item.kind == WorkKind.deadline ||
      item.kind == WorkKind.event;

  /// One row, with the three things that can happen to it: open it, tick it off,
  /// or nothing at all because there is nowhere to go yet.
  Widget _queueRow(BuildContext context, WorkItem item) {
    final currency = ref.watch(currencyProvider).valueOrNull?.code ?? 'AED';

    return QueueRow(
      item: item,
      currency: currency,
      onOpen: () => _open(context, ref, item),
      onDone: item.kind == WorkKind.task || item.kind == WorkKind.deadline
          ? () => _done(context, ref, item)
          : null,
    );
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
  Widget _scroll(List<Widget> children) {
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
        controller: _list,
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

/// The greeting, the date, and the face that says this is your app.
///
/// The header is the one part of the screen that does not change between
/// states, which is the point: the date is known while the queue is still being
/// worked out, so the screen arrives whole and the data catches up underneath
/// it. The brief lives in the morning card instead of here, so that it is said
/// once — loudly, on arrival — rather than repeated all day in three-point type.
class _HeroHeader extends StatelessWidget {
  const _HeroHeader();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return KoruScreenHeader(
      eyebrow: formatDay(now, now, style: DateStyle.short),
      title: _greetingFor(now),
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
                // The figure leads the card: bigger than the rest of the page
                // and the one green on it, so the money on a screen full of
                // work is legible at a glance rather than one line among many.
                Text(
                  '$symbol ${_plain(owed)}',
                  style: KoruType.metric.copyWith(color: KoruColors.leaf),
                ),
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

/// The all-clear, with a small celebration attached.
///
/// The state people come back for, so it arrives like one: Koru cheers, the
/// card grows in, and the phone gives one soft thump. The copy says what to do
/// next — add a task, or tell Koru when money lands — because an empty screen
/// with nothing to do is a dead end, and the button is the way out of it
/// without hunting for one.
class _AllClear extends ConsumerStatefulWidget {
  const _AllClear();

  @override
  ConsumerState<_AllClear> createState() => _AllClearState();
}

class _AllClearState extends ConsumerState<_AllClear> {
  final _mascot = KoruMascotController();

  @override
  void initState() {
    super.initState();
    // Asked for before the first frame so the clip is queued the moment the
    // sprite mounts, rather than one frame late.
    _mascot.cheer();
    // A celebration you can feel. It fires once, when the state appears, and
    // never on a rebuild.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      HapticFeedback.mediumImpact();
    });
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: KoruMotion.settle,
      curve: KoruMotion.easeOut,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: KoruSpace.sm),
        child: Column(
          children: [
            KoruMascot(
              size: 92,
              controller: _mascot,
              semanticLabel: 'Koru, happy the day is clear',
            ),
            const SizedBox(height: KoruSpace.md),
            EmptyHint(
              icon: Icons.check_circle_outline,
              tint: KoruColors.leaf,
              tintBg: KoruColors.leafSoft,
              title: 'Done for today',
              body: 'Nothing late, nothing due, nowhere to be. Add a task, or '
                  'tell Koru — "remind me to send the quote tomorrow".',
              action: FilledButton.icon(
                onPressed: () => taskSheet(context, ref),
                icon: const Icon(Icons.add_rounded, size: KoruSize.iconSm),
                label: const Text('Add a task'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The state between "all clear" and a full queue: nothing of the user's own
/// to do, but the notices below still have something to say.
///
/// Distinct from [_AllClear] on purpose. A day with a late invoice on it is not
/// a clear day, and the celebration card would have been congratulating
/// somebody for work that only moved into another column.
class _NoTasks extends StatelessWidget {
  const _NoTasks({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return EmptyHint(
      icon: Icons.task_alt_rounded,
      tint: KoruColors.leaf,
      tintBg: KoruColors.leafSoft,
      title: 'Nothing of your own waiting',
      body: 'Money and projects are further down, watched for you. Add a task '
          'when you think of one.',
      action: FilledButton.icon(
        onPressed: onAdd,
        icon: const Icon(Icons.add_rounded, size: KoruSize.iconSm),
        label: const Text('Add a task'),
      ),
    );
  }
}

/// The morning moment: one card, once a day, the first time Today is in view.
///
/// The first thing anybody wants from this app in the morning is a quick read
/// of the day and a nudge that it is being watched. So the mascot says good
/// morning by name, the line counts rather than lists, and the quote-of-the-day
/// rides inside the same card — one artefact, read in five seconds, dismissed
/// with one tap. Nothing here is a modal: a card in the page can be scrolled
/// past, and a dialog that appears before the person has read anything is the
/// most-hated screen in any app.
///
/// Once per day, remembered on the phone. The flag is a date, not a boolean,
/// so tomorrow it is genuinely a new morning rather than a session artefact.
/// A store that cannot be read shows nothing at all: the quote is the one thing
/// on this screen nobody needs twice.
class _MorningRitual extends ConsumerStatefulWidget {
  const _MorningRitual({required this.items, this.onShowMe});

  final List<WorkItem> items;

  /// Runs after the card dismisses itself. The screen uses it to bring the
  /// work section into view, so "Show me" shows something.
  final VoidCallback? onShowMe;

  @override
  ConsumerState<_MorningRitual> createState() => _MorningRitualState();
}

class _MorningRitualState extends ConsumerState<_MorningRitual> {
  /// Null until the store has answered, so the card cannot flash on a day it
  /// has already been dismissed.
  bool? _show;
  String _nickname = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Today as a date string. Local, not UTC, because the morning happens where
  /// the person is standing.
  static String _todayKey(DateTime now) =>
      '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    try {
      final store = await ref.read(storeProvider.future);
      final seen = await store.get('morning_seen');
      final nick = await store.get('nickname');
      if (!mounted) return;
      setState(() {
        _show = seen != _todayKey(DateTime.now());
        _nickname = (nick ?? '').trim();
      });
    } catch (_) {
      // A store that cannot be read is not a reason to greet somebody twice.
      if (mounted) setState(() => _show = false);
    }
  }

  Future<void> _dismiss() async {
    HapticFeedback.selectionClick();
    setState(() => _show = false);
    try {
      final store = await ref.read(storeProvider.future);
      await store.put('morning_seen', _todayKey(DateTime.now()));
    } catch (_) {
      // Nothing to recover: worst case the card says good morning again.
    }
  }

  /// The opening line, by name when there is one and quietly when there is not.
  String get _greeting {
    final name = _nickname;
    if (name.isEmpty || name == 'friend') return 'Good morning';
    return 'Good morning, $name';
  }

  @override
  Widget build(BuildContext context) {
    if (_show != true) return const SizedBox.shrink();

    final quote = quoteFor(DateTime.now());
    final line = widget.items.isEmpty
        ? 'Nothing is waiting on you today.'
        : WorkQueue.brief(widget.items);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: KoruMotion.settle,
      curve: KoruMotion.easeOut,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child:
            Transform.translate(offset: Offset(0, (1 - t) * 14), child: child),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: KoruSpace.md),
        child: KoruCard(
          accent: KoruColors.leaf,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const KoruMascot(size: 48, semanticLabel: 'Koru'),
                  const SizedBox(width: KoruSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_greeting, style: KoruType.rowTitle),
                        const SizedBox(height: KoruSpace.xxs),
                        Text(line, style: KoruType.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: KoruSpace.md),
              // The quote is part of the moment, not a second moment. One
              // card, one read, one tap to move on.
              Text(
                '“${quote.text}”',
                style: KoruType.bodyCompact.copyWith(
                  fontStyle: FontStyle.italic,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: KoruSpace.xs),
              Text('— ${quote.by}', style: KoruType.micro),
              const SizedBox(height: KoruSpace.md),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () {
                    _dismiss();
                    widget.onShowMe?.call();
                  },
                  child: const Text('Show me'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}