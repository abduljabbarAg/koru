import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../human_date.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'projects.dart';
import 'task_sheet.dart';
import 'work_rows.dart';

/// One project, with everything hanging off it.
///
/// Projects were a list, a filter bar and a progress slider, and the work inside
/// them was invisible from anywhere: a project could say it was 40% along and
/// there was nowhere on the screen that said what the 40% was. A task attached to
/// a project is what makes that number mean something, so this screen puts the
/// tasks and the running note under the progress bar, in that order — the claim,
/// then the evidence.
///
/// Reached from the morning queue, from the Tasks tab and from a client's page,
/// because a project is a thing several places need to link to and one of them
/// should not have to know about the others.
class ProjectScreen extends ConsumerWidget {
  const ProjectScreen({super.key, required this.projectId});

  final int projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsProvider).valueOrNull;
    final clients = ref.watch(clientsProvider).valueOrNull ?? const <Client>[];
    final tasksAsync = ref.watch(tasksProvider);
    final today = DateTime.now();

    Project? project;
    for (final p in projects ?? const <Project>[]) {
      if (p.id == projectId) project = p;
    }
    if (project == null) {
      // Three situations, three answers, the same as the client screen. A
      // deleted project used to look like a slow one.
      final failed = ref.watch(projectsProvider).hasError && projects == null;
      return Scaffold(
        backgroundColor: KoruColors.cream,
        appBar: AppBar(),
        body: failed
            ? KoruErrorView(
                onRetry: () => ref.invalidate(projectsProvider),
                what: 'open this project',
              )
            : projects == null
                ? const KoruLoading(label: 'Opening this project')
                : const Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(KoruSpace.gutter),
                      child: EmptyHint(
                        icon: Icons.folder_off_outlined,
                        title: 'That project is gone',
                        body: 'It was deleted, so there is nothing left to show. '
                            'The Tasks tab still lists the rest.',
                      ),
                    ),
                  ),
      );
    }

    final p = project;
    final client = _clientNamed(clients, p.clientId);
    final tasks = tasksAsync.valueOrNull
            ?.where((t) => t.projectId == p.id)
            .toList() ??
        const <Task>[];

    return Scaffold(
      backgroundColor: KoruColors.cream,
      appBar: AppBar(
        // No title. Everywhere else a bar names the screen; this one is a single
        // project whose name is the display line on the page, and putting it in
        // both places would say it twice.
        actions: [
          IconButton(
            tooltip: 'Edit ${p.name}',
            icon: const Icon(Icons.edit_outlined, size: KoruSize.icon),
            onPressed: () async {
              await showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => ProjectSheet(project: p),
              );
              ref.invalidate(projectsProvider);
            },
          ),
        ],
      ),
      body: KoruSettle(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            KoruSpace.gutter,
            KoruSpace.sml,
            KoruSpace.gutter,
            KoruSpace.tail,
          ),
          children: [
            KoruScreenHeader(
              eyebrow: client?.name ??
                  (p.isPersonal ? 'Your own work' : 'Client work'),
              title: p.name,
              subtitle: p.target == null || p.target!.isEmpty
                  ? null
                  : 'Done when ${p.target}',
            ),
            _ProgressCard(project: p),
            if (p.plan != null && p.plan!.isNotEmpty) ...[
              const SizedBox(height: KoruSpace.md),
              const SectionLabel('How you get there'),
              KoruCard(child: Text(p.plan!, style: KoruType.bodyCompact)),
            ],
            KoruSection(
              label: 'Tasks',
              hint: 'What is left on this one.',
              dividerIndent: KoruSpace.row,
              action: TextButton.icon(
                onPressed: () => taskSheet(
                  context,
                  ref,
                  projectId: p.id,
                  clientId: p.clientId,
                ),
                icon: const Icon(Icons.add_rounded, size: KoruSize.icon),
                label: const Text('Add'),
              ),
              empty: tasksAsync.isLoading && tasks.isEmpty
                  ? const KoruListSkeleton(rows: 2)
                  : const EmptyHint(
                      icon: Icons.playlist_add_check_rounded,
                      title: 'No tasks on this yet',
                      body: 'A project with no tasks is a progress bar and a '
                          'guess. Add the pieces and the percentage means '
                          'something.',
                    ),
              children: [
                for (final t in orderedTasks(tasks, today))
                  TaskRow(
                    task: t,
                    today: today,
                    onTap: () => taskSheet(context, ref, existing: t),
                  ),
              ],
            ),
            _Notes(projectId: projectId),
          ],
        ),
      ),
    );
  }
}

/// How far along, and why.
///
/// The reason sits above the number rather than under it. A progress bar on its
/// own is a confident claim, and this app has been bitten by exactly that shape
/// of claim before: it is what the model reads instead of the notes, and a bare
/// percentage is what it will quote back.
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    final p = project;
    final tone = p.isPersonal ? KoruTones.clay : KoruTones.leaf;
    final pct = (p.progress * 100).round();

    return KoruCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('HOW FAR ALONG', style: KoruType.label),
              const Spacer(),
              Text('$pct%',
                  style: KoruType.rowTitleCompact.copyWith(color: tone.ink)),
            ],
          ),
          const SizedBox(height: KoruSpace.md),
          KoruProgressBar(value: p.progress, color: tone.ink),
          if (p.progressNote != null && p.progressNote!.isNotEmpty) ...[
            const SizedBox(height: KoruSpace.md),
            Text(p.progressNote!, style: KoruType.bodyCompactStrong),
          ],
        ],
      ),
    );
  }
}

/// The running note: what actually happened, oldest first.
///
/// Kept in full and read in order, because that is what it is for — the model
/// reads it to work out where a project has got to, which is only possible if
/// the notes accumulate rather than being replaced by the latest one.
class _Notes extends ConsumerStatefulWidget {
  const _Notes({required this.projectId});

  final int projectId;

  @override
  ConsumerState<_Notes> createState() => _NotesState();
}

class _NotesState extends ConsumerState<_Notes> {
  List<ProjectNote>? _notes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = await ref.read(storeProvider.future);
    try {
      final notes = await store.projectNotes(widget.projectId);
      if (!mounted) return;
      setState(() => _notes = notes);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notes = _notes;
    if (_failed) {
      return KoruErrorView(onRetry: _load, what: 'load these notes');
    }
    if (notes == null) {
      return const KoruListSkeleton(rows: 2, badge: false);
    }
    return KoruSection(
      label: 'Notes',
      hint: 'What actually happened, oldest first.',
      dividerIndent: KoruSpace.row,
      action: TextButton.icon(
        onPressed: _add,
        icon: const Icon(Icons.note_add_outlined, size: KoruSize.iconSm),
        label: const Text('Add note'),
      ),
      empty: const EmptyHint(
        icon: Icons.notes_outlined,
        title: 'Nothing written down',
        body: 'A note is how the assistant answers "where are we on this" '
            'without guessing.',
      ),
      children: [
        for (final n in notes.reversed)
          KoruRow(
            title: n.body,
            subtitle: formatDate(n.created, DateTime.now()),
            trailing: KoruRowAction(
              tooltip: 'Delete this note',
              icon: Icons.close_rounded,
              color: KoruColors.inkFaint,
              onPressed: () async {
                final store = await ref.read(storeProvider.future);
                await store.deleteProjectNote(n.id!);
                await _load();
                invalidateWorkData(ref);
              },
            ),
          ),
      ],
    );
  }

  /// Adds a note, and touches the project so it moves to the top of its list.
  ///
  /// Touching it is not decoration: a note that lands without moving the project
  /// leaves the screen looking exactly as it did, which is how a person stops
  /// believing the note was saved.
  Future<void> _add() async {
    final store = await ref.read(storeProvider.future);
    final project = await store.project(widget.projectId);
    if (project == null) return;
    final controller = TextEditingController();
    if (!mounted) return;
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Note on ${project.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'What happened since the last update?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (text == null || text.isEmpty) return;
    await store.addProjectNote(ProjectNote(
      projectId: project.id!,
      body: text,
      created: DateTime.now().toIso8601String(),
    ));
    await store.updateProject(
      project.copyWith(updated: DateTime.now().toIso8601String()),
    );
    await _load();
    invalidateWorkData(ref);
  }
}

/// One project in a list: what it is, who it is for, how far along.
///
/// Deliberately shorter than the card on the Projects screen. These are rows
/// under a heading on a screen that is mostly about tasks, so the note and the
/// plan stay on the project itself; what a scanning row needs is the name, whose
/// it is and the number.
class ProjectLineRow extends StatelessWidget {
  const ProjectLineRow({super.key, required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    final p = project;
    final tone = p.isPersonal ? KoruTones.clay : KoruTones.leaf;
    return KoruRow(
      leading: KoruIconBadge(
        icon: p.isPersonal ? Icons.favorite_outline : Icons.work_outline,
        color: tone.ink,
        background: tone.fill,
      ),
      title: p.name,
      subtitle: p.progressNote == null || p.progressNote!.isEmpty
          ? null
          : p.progressNote!,
      trailing: Text(
        '${(p.progress * 100).round()}%',
        style: KoruType.rowTitleCompact.copyWith(color: KoruColors.inkSoft),
      ),
      onTap: p.id == null
          ? null
          : () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ProjectScreen(projectId: p.id!),
                ),
              ),
    );
  }
}

/// The first client with this id, or null.
Client? _clientNamed(List<Client> clients, int? id) {
  if (id == null) return null;
  for (final c in clients) {
    if (c.id == id) return c;
  }
  return null;
}