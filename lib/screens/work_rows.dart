import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../human_date.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import '../work_queue.dart';

/// One task in a list, with the tick that finishes it.
///
/// The tick is on the row rather than behind a tap. Finishing a thing is the
/// most common thing anybody does with a list, and this app had nowhere to do it
/// from the list at all: a task could only be marked done by opening the project
/// it belonged to, which meant a chore belonging to no project could not be
/// marked done at all. A list you cannot tick off is a to-do written down and
/// then ignored.
///
/// Shown on every surface that lists a task — the Tasks tab, a project, a client
/// — so the same line of work behaves the same way in three places rather than
/// being one editable row on one screen and read-only text on the other two.
class TaskRow extends ConsumerWidget {
  const TaskRow({
    super.key,
    required this.task,
    this.clientName,
    this.onTap,
    this.today,
  });

  final Task task;

  /// Shown beside the date. Passed in rather than looked up so that a list does
  /// not read the clients table once per row.
  final String? clientName;

  /// Opens the thing, when there is one. Null on a list that is for acting on
  /// rather than editing.
  final VoidCallback? onTap;

  /// Passed in so a whole list reads the same day.
  final DateTime? today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = today ?? DateTime.now();
    final late = task.isOverdueOn(now);
    final parts = <String>[
      if (clientName != null) clientName!,
      if (task.due != null) formatDate(task.due, now),
    ];
    if (task.done) parts.add(_doneWhen(task, now));

    return KoruRow(
      onTap: onTap,
      title: task.title,
      subtitle: parts.isEmpty ? null : parts.join('  ·  '),
      subtitleIn: late ? KoruColors.clay : null,
      accent: late ? KoruColors.clay : null,
      body: _PriorityPill(priority: task.priority),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          KoruRowAction(
            // The tooltip names the task, because a screen with six of these
            // has six identical labels and a screen reader reads the label, not
            // the row it is on.
            tooltip: task.done
                ? 'Put ${task.title} back on the list'
                : 'Mark ${task.title} done',
            icon: task.done
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            color: task.done ? KoruColors.leaf : KoruColors.inkFaint,
            onPressed: () => _toggle(ref),
          ),
          if (task.done)
            KoruRowAction(
              tooltip: 'Delete ${task.title}',
              icon: Icons.close_rounded,
              color: KoruColors.inkFaint,
              onPressed: () async {
                final store = await ref.read(storeProvider.future);
                await store.deleteTask(task.id!);
                invalidateWorkData(ref);
              },
            ),
        ],
      ),
    );
  }

  /// One write, and one refresh, for both directions.
  ///
  /// [ProfileStore.setTaskDone] moves the flag and the moment together, so the
  /// archive can say when something was finished rather than only that it is not
  /// here any more.
  Future<void> _toggle(WidgetRef ref) async {
    final store = await ref.read(storeProvider.future);
    await store.setTaskDone(task.id!, !task.done);
    invalidateWorkData(ref);
  }

  static String _doneWhen(Task t, DateTime now) {
    final at = DateTime.tryParse(t.completedAt ?? '');
    return at == null
        ? 'Done'
        : 'Done ${formatDate(at.toIso8601String(), now)}';
  }
}

/// The priority, said out loud only when somebody said something.
///
/// Nothing is drawn for the middle, because three pills on every row of a list is
/// a wall, and the middle is what most rows are already. The ordering of the list
/// is what makes the middle legible.
class _PriorityPill extends StatelessWidget {
  const _PriorityPill({required this.priority});

  final TaskPriority priority;

  @override
  Widget build(BuildContext context) {
    if (priority == TaskPriority.normal) return const SizedBox.shrink();
    final tone = priority == TaskPriority.high ? KoruTones.clay : KoruTones.neutral;
    return Row(
      children: [
        KoruPill(
          label: priority.label.toUpperCase(),
          color: tone.ink,
          background: tone.fill,
          icon: priority == TaskPriority.high
              ? Icons.keyboard_double_arrow_up_rounded
              : Icons.keyboard_double_arrow_down_rounded,
        ),
      ],
    );
  }
}

/// The order a list of tasks is shown in.
///
/// The same ordering as the morning queue, so a task that is at the top of Today
/// is also at the top of the list it belongs to. [WorkQueue.compare] does the
/// ranking and this only turns a task into the queue shape it ranks, because the
/// queue weighs money and calendar entries too and a list of tasks ranked by a
/// second set of rules is how two screens start disagreeing about what matters.
List<Task> orderedTasks(List<Task> tasks, DateTime today) {
  final out = [...tasks];
  out.sort((a, b) => WorkQueue.compare(_asItem(a, today), _asItem(b, today)));
  return out;
}

/// A task as the queue sees it. The one place the two shapes meet.
WorkItem _asItem(Task t, DateTime today) => WorkItem(
      kind: WorkKind.task,
      id: t.id,
      title: t.title,
      priority: t.priority,
      daysOut: t.daysUntilDue(today),
      overdue: t.isOverdueOn(today),
    );
