import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

    return Scaffold(
      backgroundColor: KoruColors.cream,
      appBar: AppBar(title: const Text('Projects')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New project'),
      ),
      body: projects.when(
        loading: () => const KoruLoading(label: 'Loading your projects'),
        error: (e, _) => KoruErrorView(
          onRetry: () => ref.invalidate(projectsProvider),
          what: 'load your projects',
        ),
        data: (all) {
          final shown = _filter == null
              ? all
              : all.where((p) => p.kind == _filter).toList();
          if (all.isEmpty) {
            return const Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(KoruSpace.gutter),
                child: EmptyHint(
                  icon: Icons.folder_open_rounded,
                  title: 'No projects yet',
                  body: 'A project is one piece of work with a finish line. Add '
                      'the site you are building, the thing you are learning, or '
                      'anything else with an end to it.',
                ),
              ),
            );
          }
          return KoruSettle(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                KoruSpace.gutter,
                KoruSpace.sm,
                KoruSpace.gutter,
                KoruSpace.aboveFab,
              ),
              children: [
                KoruScreenHeader(
                  eyebrow: '${all.length} ${all.length == 1 ? 'project' : 'projects'}',
                  title: 'What you are building',
                  subtitle: shown.isEmpty
                      ? null
                      : 'Sorted by what was touched most recently.',
                ),
                _FilterBar(
                  selected: _filter,
                  counts: {
                    for (final k in ProjectKind.values)
                      k: all.where((p) => p.kind == k).length,
                  },
                  onChanged: (k) => setState(() => _filter = k),
                ),
                if (shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: KoruSpace.xxxl),
                    child: Center(
                      child: Text(
                        'Nothing in this list yet.',
                        style: KoruType.bodyStrong.copyWith(
                          fontSize: 14,
                          color: KoruColors.inkFaint,
                        ),
                      ),
                    ),
                  )
                else
                  for (final p in shown)
                    _ProjectCard(
                      project: p,
                      onTap: () => _edit(p),
                      onNote: () => _addNote(p),
                    ),
              ],
            ),
          );
        },
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
    return Padding(
      padding: const EdgeInsets.only(bottom: KoruSpace.lg),
      child: Wrap(
        spacing: KoruSpace.sm,
        runSpacing: KoruSpace.sm,
        children: [
          KoruSelectablePill(
            label: 'All (${counts.values.fold(0, (a, b) => a + b)})',
            selected: selected == null,
            dense: true,
            onTap: () => onChanged(null),
          ),
          for (final k in ProjectKind.values)
            KoruSelectablePill(
              label:
                  '${k == ProjectKind.client ? 'Client work' : 'Personal'} (${counts[k] ?? 0})',
              selected: selected == k,
              dense: true,
              onTap: () => onChanged(k),
            ),
        ],
      ),
    );
  }
}

/// One project: what it is, how far along, and the last note.
///
/// The note is the reason this card exists. A progress bar says how far along
/// something is and nothing about why, and the assistant reads the note rather
/// than the bar, so the note is the same weight as the title rather than the
/// small print under it.
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
                  style: KoruType.body.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: KoruColors.inkSoft,
                  ),
                ),
              ],
            ),
            const SizedBox(height: KoruSpace.md),
            Text(project.name, style: KoruType.rowTitle.copyWith(fontSize: 17)),
            if (project.target != null && project.target!.isNotEmpty) ...[
              const SizedBox(height: KoruSpace.xs),
              Text('Done when ${project.target}', style: KoruType.body),
            ],
            const SizedBox(height: KoruSpace.md + 2),
            KoruProgressBar(value: project.progress, color: tone.ink),
            if (project.progressNote != null &&
                project.progressNote!.isNotEmpty) ...[
              const SizedBox(height: KoruSpace.md),
              Text(project.progressNote!, style: KoruType.body),
            ],
            const SizedBox(height: KoruSpace.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onNote,
                icon: const Icon(Icons.note_add_outlined, size: KoruSize.icon),
                label: const Text('Add note'),
              ),
            ),
          ],
        ),
      ),
    );
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
          SegmentedButton<ProjectKind>(
            segments: const [
              ButtonSegment(
                value: ProjectKind.personal,
                label: Text('Personal'),
                icon: Icon(Icons.favorite_outline, size: KoruSize.icon),
              ),
              ButtonSegment(
                value: ProjectKind.client,
                label: Text('Client'),
                icon: Icon(Icons.work_outline, size: KoruSize.icon),
              ),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: KoruSpace.md),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: KoruSpace.sm + 2),
          TextField(
            controller: _target,
            decoration: const InputDecoration(
              labelText: 'Done when',
              hintText: 'the shop is open',
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: KoruSpace.sm + 2),
          TextField(
            controller: _plan,
            decoration: const InputDecoration(
              labelText: 'How you get there',
              hintText: 'photos first, then the build',
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: KoruSpace.lg),
          Text(
            '${(_progress * 100).round()}% along',
            style: KoruType.bodyStrong.copyWith(fontWeight: FontWeight.w600),
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
          const SizedBox(height: KoruSpace.lg),
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