import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../human_date.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

/// Projects, and what has happened on them.
///
/// A project is not a row in a table. It is a piece of work with a target, a
/// plan, a number between zero and one, and a running note of what actually
/// happened. The note is the part that matters: progress without a reason is a
/// guess, and the model reads the note, so the assistant can answer "where are
/// we on the shop" without inventing something encouraging.
///
/// Client and personal projects share this screen because they differ in one
/// field. Splitting them would mean two screens, two sets of empty states, and a
/// user with three personal projects and one client project calling them four
/// different things.
class ProjectsScreen extends ConsumerStatefulWidget {
  const ProjectsScreen({super.key});

  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  ProjectKind? _filter;

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(projectsProvider);
    final known = projects.valueOrNull;

    // The header is built once and given to every state, so the screen arrives
    // with its title and the count in place and the list fills in underneath.
    // A title that appears when the data does makes the whole page jump down a
    // line, which is the most noticeable kind of cheap.
    final header = KoruScreenHeader(
      eyebrow: known == null
          ? null
          : '${known.length} ${known.length == 1 ? 'project' : 'projects'}',
      title: 'What you are building',
      subtitle: known == null || known.isEmpty
          ? null
          : 'Sorted by what was touched most recently.',
    );

    return Scaffold(
      backgroundColor: KoruColors.cream,
      appBar: AppBar(title: const Text('Projects')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New project'),
      ),
      body: projects.when(
        loading: () => _page([
          header,
          const KoruLoading(label: 'Loading your projects'),
        ]),
        error: (e, _) => _page([
          header,
          KoruErrorView(
            onRetry: () => ref.invalidate(projectsProvider),
            what: 'load your projects',
          ),
        ]),
        data: (all) {
          final shown = _filter == null
              ? all
              : all.where((p) => p.kind == _filter).toList();
          // Nothing at all and nothing in this filter are different situations
          // and they get different words. An empty app needs telling how to
          // start; an empty filter needs telling how to see the rest.
          if (all.isEmpty) return _allEmpty();
          return _page([
            header,
            _FilterBar(
              selected: _filter,
              counts: {
                for (final k in ProjectKind.values)
                  k: all.where((p) => p.kind == k).length,
              },
              onChanged: (k) => setState(() => _filter = k),
            ),
            if (shown.isEmpty)
              EmptyHint(
                icon: _filter == ProjectKind.client
                    ? Icons.work_outline
                    : Icons.favorite_outline,
                title: _filter == ProjectKind.client
                    ? 'No client work yet'
                    : 'Nothing personal on the list',
                body: _filter == ProjectKind.client
                    ? 'A project belongs to a client when somebody is paying '
                        'for it. Switch back to All, or add one.'
                    : 'Personal work is anything you are doing for yourself. '
                        'Switch back to All, or add one.',
                action: OutlinedButton(
                  onPressed: () => setState(() => _filter = null),
                  child: const Text('Show everything'),
                ),
              )
            else
              for (final p in shown)
                _ProjectCard(
                  project: p,
                  onTap: () => _edit(p),
                  onNote: () => _addNote(p),
                ),
          ]);
        },
      ),
    );
  }

  /// The one scroll view, so every state is a page rather than a fragment and
  /// the footer clears the floating action button the same way in all of them.
  Widget _page(List<Widget> children) => KoruSettle(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            KoruSpace.gutter,
            KoruSpace.sml,
            KoruSpace.gutter,
            KoruSpace.aboveFab,
          ),
          children: children,
        ),
      );

  /// The first-run state. Full height rather than inside the scrolled list,
  /// because there is nothing above or below it to scroll to.
  Widget _allEmpty() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(KoruSpace.gutter),
        child: EmptyHint(
          icon: Icons.folder_open_rounded,
          title: 'No projects yet',
          body: 'A project is one piece of work with a finish line. Add the site '
              'you are building, the thing you are learning, or anything else '
              'with an end to it.',
          action: FilledButton(
            onPressed: () => _edit(null),
            child: const Text('Add a project'),
          ),
        ),
      ),
    );
  }

  Future<void> _edit(Project? existing) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ProjectSheet(project: existing),
    );
    ref.invalidate(projectsProvider);
  }

  Future<void> _addNote(Project p) async {
    final store = await ref.read(storeProvider.future);
    final id = p.id;
    if (id == null) return;
    final controller = TextEditingController();
    // Checked before the dialog: a note added and then an await can leave a
    // BuildContext that is no longer mounted, and using it then throws rather
    // than quietly doing nothing.
    if (!mounted) return;
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Note on ${p.name}'),
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
      projectId: id,
      body: text,
      created: DateTime.now().toIso8601String(),
    ));
    // Touching the project is what moves it to the top of the list. Without
    // this, a note lands somewhere invisible and the screen looks unchanged.
    await store.updateProject(p.copyWith(
      updated: DateTime.now().toIso8601String(),
    ));
    ref.invalidate(projectsProvider);
  }
}

/// The three-way filter above the list.
///
/// One row of pills rather than a dropdown, because the counts are the useful
/// part: "All (7) / Client work (2) / Personal (5)" tells somebody whether
/// switching is worth it before they switch, which a dropdown cannot.
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.selected,
    required this.counts,
    required this.onChanged,
  });

  final ProjectKind? selected;
  final Map<ProjectKind, int> counts;
  final ValueChanged<ProjectKind?> onChanged;

  @override
  Widget build(BuildContext context) {
    return KoruFilterBar(
      children: [
        KoruSelectablePill(
          label: 'All (${counts.values.fold(0, (a, b) => a + b)})',
          selected: selected == null,
          dense: true,
          onTap: () => onChanged(null),
        ),
        for (final k in ProjectKind.values)
          KoruSelectablePill(
            label: '${k == ProjectKind.client ? 'Client work' : 'Personal'} '
                '(${counts[k] ?? 0})',
            selected: selected == k,
            dense: true,
            onTap: () => onChanged(k),
          ),
      ],
    );
  }
}

/// One project: what it is, how far along, and the last note.
///
/// The note is the reason this card exists. A progress bar says how far along
/// something is and nothing about why, and the assistant reads the note rather
/// than the bar, so the note is the same weight as the title rather than the
/// small print under it.
///
/// The footer is separated by a hairline rather than more space. A card with
/// five things in it and no divisions reads as one paragraph, and the eye has to
/// work out that "Add note" is a control and not a fifth line of the description.
class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.project,
    required this.onTap,
    required this.onNote,
  });

  final Project project;
  final VoidCallback onTap;
  final VoidCallback onNote;

  @override
  Widget build(BuildContext context) {
    final personal = project.isPersonal;
    final pct = (project.progress * 100).round();
    final tone = personal ? KoruTones.clay : KoruTones.leaf;
    final touched = _lastTouched(project);

    return Padding(
      padding: const EdgeInsets.only(bottom: KoruSpace.md),
      child: KoruCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                KoruPill(
                  label: personal ? 'PERSONAL' : 'CLIENT WORK',
                  color: tone.ink,
                  background: tone.fill,
                ),
                const Spacer(),
                Text(
                  '$pct%',
                  style: KoruType.rowTitleCompact
                      .copyWith(color: KoruColors.inkSoft),
                ),
              ],
            ),
            const SizedBox(height: KoruSpace.md),
            Text(project.name, style: KoruType.rowTitleLarge),
            if (project.target != null && project.target!.isNotEmpty) ...[
              const SizedBox(height: KoruSpace.xs),
              Text('Done when ${project.target}', style: KoruType.bodyCompact),
            ],
            const SizedBox(height: KoruSpace.md),
            KoruProgressBar(value: project.progress, color: tone.ink),
            if (project.progressNote != null &&
                project.progressNote!.isNotEmpty) ...[
              const SizedBox(height: KoruSpace.md),
              Text(project.progressNote!, style: KoruType.bodyCompactStrong),
            ],
            const SizedBox(height: KoruSpace.md),
            const Divider(height: 1),
            Row(
              children: [
                if (touched != null)
                  Expanded(child: Text(touched, style: KoruType.meta)),
                const SizedBox(width: KoruSpace.sm),
                TextButton.icon(
                  onPressed: onNote,
                  icon: const Icon(Icons.note_add_outlined, size: KoruSize.iconSm),
                  label: const Text('Add note'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// When this was last moved, in words.
  ///
  /// The list is sorted by it and a card that does not say so leaves the reader
  /// guessing why one project is above another. Null rather than a placeholder
  /// when the stored value will not parse: a wrong date is worse than none.
  static String? _lastTouched(Project p) {
    final at = DateTime.tryParse(p.updated.isEmpty ? p.created : p.updated);
    if (at == null) return null;
    return 'Last touched ${formatDay(at, DateTime.now(), style: DateStyle.short)}';
  }
}

/// Create or edit a project.
///
/// Progress is a slider rather than a text box because it is the one number a
/// model will quote back, and a slider cannot produce "sixty percent" by
/// accident. The reason field is required whenever the slider moves, which is
/// the whole point: a number with no reason is the confident guess the rest of
/// this app tries not to make.
class ProjectSheet extends ConsumerStatefulWidget {
  const ProjectSheet({super.key, this.project});

  final Project? project;

  @override
  ConsumerState<ProjectSheet> createState() => _ProjectSheetState();
}

class _ProjectSheetState extends ConsumerState<ProjectSheet> {
  late final TextEditingController _name;
  late final TextEditingController _target;
  late final TextEditingController _plan;
  late final TextEditingController _note;

  late ProjectKind _kind;
  late double _progress;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.project;
    _name = TextEditingController(text: p?.name ?? '');
    _target = TextEditingController(text: p?.target ?? '');
    _plan = TextEditingController(text: p?.plan ?? '');
    _note = TextEditingController(text: p?.progressNote ?? '');
    _kind = p?.kind ?? ProjectKind.personal;
    _progress = p?.progress ?? 0;
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _plan.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.project;
    return KoruSheetBody(
      title: p == null ? 'New project' : 'Edit project',
      subtitle: 'One piece of work with a finish line.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The same pill pair as the filter above the list, rather than
          // Material's segmented control, which is the one control in the app
          // that arrives with its own shape and its own corner radius.
          KoruChoiceGroup(
            label: 'Whose work',
            children: [
              KoruSelectablePill(
                label: 'Personal',
                icon: Icons.favorite_outline,
                selected: _kind == ProjectKind.personal,
                onTap: () => setState(() => _kind = ProjectKind.personal),
              ),
              KoruSelectablePill(
                label: 'Client',
                icon: Icons.work_outline,
                selected: _kind == ProjectKind.client,
                onTap: () => setState(() => _kind = ProjectKind.client),
              ),
            ],
          ),
          const SizedBox(height: KoruSpace.lg),
          KoruFieldStack(
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
                textCapitalization: TextCapitalization.sentences,
              ),
              TextField(
                controller: _target,
                decoration: const InputDecoration(
                  labelText: 'Done when',
                  hintText: 'the shop is open',
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              TextField(
                controller: _plan,
                decoration: const InputDecoration(
                  labelText: 'How you get there',
                  hintText: 'photos first, then the build',
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
            ],
          ),
          const SizedBox(height: KoruSpace.xl),
          Row(
            children: [
              Text('How far along', style: KoruType.bodyStrong),
              const Spacer(),
              Text(
                '${(_progress * 100).round()}%',
                style: KoruType.rowTitleCompact
                    .copyWith(color: KoruColors.leaf),
              ),
            ],
          ),
          Slider(
            value: _progress.clamp(0, 1),
            onChanged: (v) => setState(() => _progress = v),
          ),
          TextField(
            controller: _note,
            decoration: const InputDecoration(
              labelText: 'Why it is there',
              hintText: 'two rooms left, both need wiring',
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: KoruSpace.xl),
          Row(
            children: [
              if (p != null)
                TextButton(
                  onPressed: _saving ? null : _delete,
                  style: TextButton.styleFrom(foregroundColor: KoruColors.clay),
                  child: const Text('Delete'),
                ),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, KoruSize.buttonInCard),
                ),
                onPressed: _saving ? null : _save,
                child: Text(p == null ? 'Add' : 'Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);

    final store = await ref.read(storeProvider.future);
    final existing = widget.project;
    final now = DateTime.now().toIso8601String();

    final project = Project(
      id: existing?.id,
      name: name,
      kind: _kind,
      clientId: _kind == ProjectKind.client ? existing?.clientId : null,
      target: _target.text.trim().isEmpty ? null : _target.text.trim(),
      plan: _plan.text.trim().isEmpty ? null : _plan.text.trim(),
      progress: _progress.clamp(0, 1),
      progressNote: _note.text.trim().isEmpty ? null : _note.text.trim(),
      status: existing?.status ?? 'active',
      created: existing?.created ?? now,
      updated: now,
    );

    if (existing?.id == null) {
      await store.addProject(project);
    } else {
      await store.updateProject(project);
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final id = widget.project?.id;
    if (id == null) return;
    final store = await ref.read(storeProvider.future);
    await store.deleteProject(id);
    if (mounted) Navigator.pop(context);
  }
}