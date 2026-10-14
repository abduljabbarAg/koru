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
/// field. Splitting them would mean two screens, two sets of empty states, and
/// a user with three personal projects and one client project calling them four
/// different things.
class ProjectsScreen extends ConsumerStatefulWidget {
  ProjectsScreen({super.key});

  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  ProjectKind? _filter;

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(projectsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Projects'),
        backgroundColor: KoruColors.cream,
        surfaceTintColor: Colors.transparent,
      ),
      backgroundColor: KoruColors.cream,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: KoruColors.leaf,
        foregroundColor: Colors.white,
        onPressed: () => _edit(null),
        icon: Icon(Icons.add),
        label: Text('New project'),
      ),
      body: projects.when(
        loading: () => Center(child: CircularProgressIndicator()),
        error: (e, _) => KoruErrorView(
          onRetry: () => ref.invalidate(projectsProvider),
          what: 'load your projects',
        ),
        data: (all) {
          final shown = _filter == null
              ? all
              : all.where((p) => p.kind == _filter).toList();
          if (all.isEmpty) {
            return const _Empty(
              icon: Icons.folder_open,
              title: 'No projects yet',
              body: 'A project is one piece of work with a finish line. Add '
                  'the site you are building, the thing you are learning, or '
                  'anything else with an end to it.',
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
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
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: Text('Nothing in this list yet.')),
                ),
              for (final p in shown)
                _ProjectCard(
                  project: p,
                  onTap: () => _edit(p),
                  onNote: () => _addNote(p),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _edit(Project? existing) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: KoruColors.surface,
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
          decoration: InputDecoration(
            hintText: 'What happened since the last update?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text('Add'),
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 8,
        children: [
          _chip(context, null, 'All', counts.values.fold(0, (a, b) => a + b)),
          for (final k in ProjectKind.values)
            _chip(
              context,
              k,
              k == ProjectKind.client ? 'Client work' : 'Personal',
              counts[k] ?? 0,
            ),
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context,
    ProjectKind? kind,
    String label,
    int count,
  ) {
    final on = selected == kind;
    return ChoiceChip(
      label: Text('$label ($count)'),
      selected: on,
      onSelected: (_) => onChanged(kind),
      selectedColor: KoruColors.leafSoft,
      labelStyle: TextStyle(
        color: on ? KoruColors.leaf : KoruColors.inkSoft,
        fontWeight: on ? FontWeight.w700 : FontWeight.w500,
      ),
      side: BorderSide(color: on ? KoruColors.leaf : KoruColors.line),
      backgroundColor: KoruColors.surface,
      showCheckmark: false,
    );
  }
}

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

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: KoruColors.line),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    personal ? Icons.favorite_outline : Icons.work_outline,
                    size: 16,
                    color: personal ? KoruColors.clay : KoruColors.leaf,
                  ),
                  SizedBox(width: 6),
                  Text(
                    personal ? 'Personal' : 'Client work',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: personal ? KoruColors.clay : KoruColors.leaf,
                    ),
                  ),
                  Spacer(),
                  Text('$pct%',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: KoruColors.inkSoft,
                      )),
                ],
              ),
              SizedBox(height: 6),
              Text(project.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: KoruColors.ink,
                  )),
              if (project.target != null && project.target!.isNotEmpty) ...[
                SizedBox(height: 3),
                Text('Done when ${project.target}',
                    style: TextStyle(
                        fontSize: 13, color: KoruColors.inkSoft)),
              ],
              SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: project.progress.clamp(0, 1),
                  minHeight: 6,
                  backgroundColor: KoruColors.line,
                  valueColor: AlwaysStoppedAnimation(
                    personal ? KoruColors.clay : KoruColors.leaf,
                  ),
                ),
              ),
              if (project.progressNote != null &&
                  project.progressNote!.isNotEmpty) ...[
                SizedBox(height: 8),
                Text(project.progressNote!,
                    style: TextStyle(
                        fontSize: 13, color: KoruColors.inkSoft)),
              ],
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onNote,
                  icon: Icon(Icons.note_add_outlined, size: 18),
                  label: Text('Add note'),
                ),
              ),
            ],
          ),
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
  ProjectSheet({super.key, this.project});

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
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p == null ? 'New project' : 'Edit project',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            SizedBox(height: 12),
            SegmentedButton<ProjectKind>(
              segments: const [
                ButtonSegment(
                  value: ProjectKind.personal,
                  label: Text('Personal'),
                  icon: Icon(Icons.favorite_outline, size: 18),
                ),
                ButtonSegment(
                  value: ProjectKind.client,
                  label: Text('Client'),
                  icon: Icon(Icons.work_outline, size: 18),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: InputDecoration(labelText: 'Name'),
              textCapitalization: TextCapitalization.sentences,
            ),
            SizedBox(height: 10),
            TextField(
              controller: _target,
              decoration: InputDecoration(
                labelText: 'Done when',
                hintText: 'the shop is open',
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            SizedBox(height: 10),
            TextField(
              controller: _plan,
              decoration: InputDecoration(
                labelText: 'How you get there',
                hintText: 'photos first, then the build',
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            SizedBox(height: 16),
            Text('${(_progress * 100).round()}% along',
                style: TextStyle(fontWeight: FontWeight.w600)),
            Slider(
              value: _progress.clamp(0, 1),
              onChanged: (v) => setState(() => _progress = v),
            ),
            TextField(
              controller: _note,
              decoration: InputDecoration(
                labelText: 'Why it is there',
                hintText: 'two rooms left, both need wiring',
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            SizedBox(height: 16),
            Row(
              children: [
                if (p != null)
                  TextButton(
                    onPressed: _saving ? null : _delete,
                    style: TextButton.styleFrom(
                        foregroundColor: KoruColors.clay),
                    child: Text('Delete'),
                  ),
                Spacer(),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(p == null ? 'Add' : 'Save'),
                ),
              ],
            ),
          ],
        ),
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

class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: KoruColors.inkFaint),
            SizedBox(height: 12),
            Text(title,
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700)),
            SizedBox(height: 6),
            Text(body,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14, color: KoruColors.inkSoft)),
          ],
        ),
      ),
    );
  }
}