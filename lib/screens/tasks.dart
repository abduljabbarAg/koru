import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'business_rows.dart' show DeadlineRow, EventRow;
import 'business_sheets.dart' show addDeadlineSheet;
import 'project_detail.dart';
import 'projects.dart';
import 'shell_actions.dart';
import 'task_sheet.dart';
import 'work_rows.dart';

/// Everything that is work, in one list.
///
/// One list split in two rather than four lists, because that is what somebody
/// means when they open it: what is outstanding, and what I already did.
/// Everything here used to be a tab bar of its own — tasks on one, projects on
/// another, calendar on a third, deadlines inside a page called Business — and a
/// week of work was spread across three of them with no way to see it whole.
///
/// It is the deepest page of the app now, one tap past the morning queue behind
/// "All work", so the bar keeps three moving parts instead of five. The work
/// somebody has to look at first is the queue on Today, which is drawn from
/// these same rows; this page is for when they want the whole week at once.
///
/// The sections under the two lists are the things that are dated or bigger than
/// a task: deadlines somebody agreed to, places to be, and the projects the work
/// belongs to. They are here rather than on their own tabs because they are all
/// work in progress, and a tab bar of three has no room left for "the rest".
class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(tasksProvider);
    final clients = ref.watch(clientsProvider).valueOrNull ?? const <Client>[];
    final deadlinesAsync = ref.watch(openDeadlinesProvider);
    final deadlines = deadlinesAsync.valueOrNull ?? const <Deadline>[];
    final eventsAsync = ref.watch(eventsProvider);
    final events = eventsAsync.valueOrNull ?? const <CalendarEvent>[];
    final projectsAsync = ref.watch(projectsProvider);
    final projects = projectsAsync.valueOrNull ?? const <Project>[];
    final today = DateTime.now();

    return Scaffold(
      backgroundColor: KoruColors.cream,
      appBar: AppBar(
        // Named for how the morning links to it. The old title, "Tasks", named
        // a fifth of what the page holds and made the queue's own link —
        // "All work" — open something with a different name.
        title: const Text('All work'),
        backgroundColor: KoruColors.cream,
        surfaceTintColor: KoruColors.nothing,
        actions: const [SettingsButton()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        // The one-off case. Work with no client and no project used to have
        // nowhere to go, and the floating button is where somebody looks when
        // they have just thought of something to do.
        //
        // Tagged by name rather than left on the shared default: the bar's own
        // "Tell Koru" button keeps the default tag, and two floating buttons
        // meet during the push transition — when Flutter collects the heroes in
        // both routes at once and throws on the duplicate. It only shows up on
        // the first push, which is why it needed naming rather than debugging.
        heroTag: 'tasks.add',
        onPressed: () => taskSheet(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Task'),
      ),
      body: KoruSettle(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            KoruSpace.gutter,
            KoruSpace.sml,
            KoruSpace.gutter,
            KoruSpace.aboveFab,
          ),
          children: [
            _Header(tasks: tasksAsync.valueOrNull),
            if (tasksAsync.hasError && tasksAsync.valueOrNull == null)
              KoruErrorView(
                onRetry: () => ref.invalidate(tasksProvider),
                what: 'load your tasks',
              )
            else ...[
              _pending(tasksAsync.valueOrNull, today, () => taskSheet(context, ref)),
              _done(tasksAsync.valueOrNull, today),
            ],
            KoruSection(
              label: 'Deadlines',
              hint: 'What has to happen next, soonest first.',
              dividerIndent: KoruSpace.row,
              action: TextButton.icon(
                onPressed: () => addDeadlineSheet(context, ref, clients),
                icon: const Icon(Icons.add_rounded, size: KoruSize.icon),
                label: const Text('Add'),
              ),
              empty: deadlinesAsync.isLoading && deadlines.isEmpty
                  ? const KoruListSkeleton(rows: 2)
                  : const EmptyHint(
                      icon: Icons.event_available_rounded,
                      title: 'Nothing scheduled',
                      body: 'A deadline is a thing somebody agreed to by a date. '
                          'The task list above is for what you decided to do; '
                          'this is for what was promised.',
                    ),
              children: [
                for (final d in deadlines)
                  DeadlineRow(
                    deadline: d,
                    today: today,
                    client: _clientNamed(clients, d.clientId),
                  ),
              ],
            ),
            KoruSection(
              label: 'Calendar',
              hint: 'Meetings you have asked Koru to keep.',
              dividerIndent: KoruSpace.row,
              empty: eventsAsync.isLoading && events.isEmpty
                  ? const KoruListSkeleton(rows: 2, badge: false)
                  : const EmptyHint(
                      icon: Icons.event_rounded,
                      title: 'Nothing on the calendar',
                      body: 'Say "schedule a call with Bilal tomorrow at 3pm" to '
                          'Koru and it lands here, with an option to mirror it '
                          'to your phone calendar.',
                    ),
              children: [
                for (final e in events.take(6)) EventRow(event: e),
              ],
            ),
            KoruSection(
              label: 'Projects',
              hint: 'The bigger pieces of work these tasks belong to.',
              dividerIndent: KoruSpace.row,
              action: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ProjectsScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.folder_outlined,
                        size: KoruSize.iconSm),
                    label: const Text('All'),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      await showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => const ProjectSheet(),
                      );
                      // The sheet writes straight to the store, and a project
                      // that has just been created but is not in the list reads
                      // as the save having failed.
                      ref.invalidate(projectsProvider);
                    },
                    icon: const Icon(Icons.add_rounded, size: KoruSize.icon),
                    label: const Text('New'),
                  ),
                ],
              ),
              empty: projectsAsync.isLoading && projects.isEmpty
                  ? const KoruListSkeleton(rows: 2, badge: false)
                  : const EmptyHint(
                      icon: Icons.folder_open_rounded,
                      title: 'No projects yet',
                      body: 'A project is one piece of work with a finish line. '
                          'Tasks hang off it, so it says when the whole thing is '
                          'done rather than leaving you to infer it.',
                    ),
              children: [
                for (final p in projects) ProjectLineRow(project: p),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// What is outstanding, worst first.
  Widget _pending(List<Task>? tasks, DateTime today, VoidCallback onAdd) {
    final waiting = tasks == null;
    final open = orderedTasks(
      tasks?.where((t) => !t.done).toList() ?? const <Task>[],
      today,
    );
    return KoruSection(
      label: waiting ? 'Pending' : 'Pending (${open.length})',
      hint: 'Late first, then by priority, then by how soon it is due.',
      dividerIndent: KoruSpace.row,
      empty: waiting
          ? const KoruListSkeleton(rows: 3)
          : EmptyHint(
              icon: Icons.playlist_add_check_rounded,
              title: 'Nothing outstanding',
              body: 'Work with no client and no project belongs here too. A '
                  'title and a date is the whole thing.',
              action: FilledButton(
                onPressed: onAdd,
                child: const Text('Add a task'),
              ),
            ),
      children: [
        for (final t in open) TaskRow(task: t, today: today),
      ],
    );
  }

  /// What has been finished, kept rather than thrown away.
  ///
  /// The archive is on the same screen on purpose. Deleting a finished task was
  /// the only option before, which meant that ticking something off and
  /// mis-tapping was unrecoverable, and that a week of work left no trace at
  /// all — so there was no way to answer "what did I actually get done this
  /// week", which is the question a person opens this screen on a Friday for.
  Widget _done(List<Task>? tasks, DateTime today) {
    final waiting = tasks == null;
    final finished = <Task>[if (tasks != null) ...tasks.where((t) => t.done)];
    // Newest first, because the thing somebody wants to check is whether
    // something they think they did actually landed.
    finished.sort((a, b) => (b.completedAt ?? '').compareTo(a.completedAt ?? ''));
    if (waiting && finished.isEmpty) return const SizedBox.shrink();
    return KoruSection(
      label: waiting ? 'Done' : 'Done (${finished.length})',
      hint: 'Kept, not deleted. Tap the tick to put one back.',
      dividerIndent: KoruSpace.row,
      empty: const SizedBox.shrink(),
      children: [
        for (final t in finished) TaskRow(task: t, today: today),
      ],
    );
  }
}

/// The client a deadline belongs to, or null when it belongs to nobody.
///
/// Written out rather than through `firstOrNull`, which lives in
/// package:collection and is not a dependency here.
Client? _clientNamed(List<Client> clients, int? id) {
  if (id == null) return null;
  for (final c in clients) {
    if (c.id == id) return c;
  }
  return null;
}

/// The count, said above the list rather than in the bar.
///
/// The bar carries no count because the number that matters changes as
/// somebody works, and a title that updates while they are reading it is one
/// more thing moving.
class _Header extends StatelessWidget {
  const _Header({required this.tasks});

  /// Null while the list is still loading, which leaves the count out rather
  /// than printing a zero that reads as "you have nothing to do".
  final List<Task>? tasks;

  @override
  Widget build(BuildContext context) {
    final known = tasks;
    final open = known?.where((t) => !t.done).length;
    return KoruScreenHeader(
      eyebrow: open == null ? null : '$open outstanding',
      title: 'What needs doing',
      subtitle: 'Everything you have on, in the order it should be done.',
    );
  }
}