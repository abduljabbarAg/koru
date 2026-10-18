import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

/// Create or edit a task.
///
/// Everything on it is optional except the title. That is the whole point of the
/// form: an earlier version of this app could only record work that belonged to
/// a client, so a task like "renew the domain" or "call the accountant" had
/// nowhere to go at all and simply did not get written down. A task with a title
/// and nothing else is a complete and useful record.
///
/// The form does not ask which client a task is for. The user is the one doing
/// the work, so a picker that asked whose task it was read backwards — as if the
/// client were meant to do it. Work started from inside a client's page still
/// carries that client, but it is set by the caller, quietly.
///
/// The date is a button plus a way to take it back off, rather than a field. A
/// task with no date is a real state here and one the rest of the app handles,
/// so it has to be reachable on the form; a date field that can only be filled
/// in cannot express it.
Future<void> taskSheet(
  BuildContext context,
  WidgetRef ref, {
  Task? existing,
  int? clientId,
  int? projectId,
}) async {
  final projects = ref.read(projectsProvider).valueOrNull ?? const <Project>[];

  final title = TextEditingController(text: existing?.title ?? '');
  final note = TextEditingController(text: existing?.note ?? '');
  var priority = existing?.priority ?? TaskPriority.normal;
  var due = existing?.parsedDue;
  var project = existing?.projectId ?? projectId;

  final outcome = await showKoruSheet<_Outcome>(
    context,
    title: existing == null ? 'New task' : 'Edit task',
    subtitle: existing == null
        ? 'One thing to do. A title is the whole thing.'
        : 'Changes are kept on this device.',
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KoruFieldStack(
            children: [
              TextField(
                controller: title,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'What needs doing',
                  hintText: 'Send the revised quote',
                ),
              ),
              KoruDateButton(
                label: 'Due',
                icon: Icons.event_outlined,
                value: due == null ? 'no date' : readableDate(due!),
                tone: due == null ? null : KoruColors.leaf,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    firstDate: DateTime.now().subtract(const Duration(days: 365 * 2)),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                    initialDate: due ?? DateTime.now(),
                    helpText: 'When does it have to be done?',
                  );
                  if (picked != null) setSheetState(() => due = picked);
                },
              ),
              if (due != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setSheetState(() => due = null),
                    icon: const Icon(Icons.close_rounded,
                        size: KoruSize.iconSm),
                    label: const Text('No date'),
                  ),
                ),
            ],
          ),
          const SizedBox(height: KoruSpace.xl),
          // Priority as three pills rather than a field, because the question is
          // "how does this sit against the rest of the week" and a number in a
          // box makes it look like a measurement.
          KoruChoiceGroup(
            label: 'How pressing',
            caption: 'High first, then by date. Everything is normal until you '
                'say otherwise.',
            children: [
              for (final p in TaskPriority.values)
                KoruSelectablePill(
                  label: p.label,
                  icon: switch (p) {
                    TaskPriority.high => Icons.keyboard_double_arrow_up_rounded,
                    TaskPriority.normal => Icons.remove_rounded,
                    TaskPriority.low => Icons.keyboard_double_arrow_down_rounded,
                  },
                  selected: priority == p,
                  onTap: () => setSheetState(() => priority = p),
                ),
            ],
          ),
          const SizedBox(height: KoruSpace.xl),
          // No "who is it for". A task is the user's own work — they are the
          // one doing it — and asking which client it belongs to read as if the
          // client were expected to do the job. Work created from inside a
          // client's page still carries that client, silently, because there
          // the context is already on screen.
          if (projects.isNotEmpty)
            KoruChoiceGroup(
              label: 'Under which project',
              caption: 'Optional.',
              children: [
                for (final p in projects)
                  KoruSelectablePill(
                    label: p.name,
                    icon: p.isPersonal
                        ? Icons.favorite_outline
                        : Icons.folder_outlined,
                    selected: project == p.id,
                    onTap: () => setSheetState(() => project = p.id),
                  ),
              ],
            ),
          if (projects.isNotEmpty) const SizedBox(height: KoruSpace.xl),
          TextField(
            controller: note,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Note',
              hintText: 'Anything worth remembering about it',
            ),
          ),
          const SizedBox(height: KoruSpace.xl),
          Row(
            children: [
              if (existing != null)
                TextButton(
                  onPressed: () => Navigator.pop(ctx, _Outcome.delete),
                  style: TextButton.styleFrom(foregroundColor: KoruColors.clay),
                  child: const Text('Delete'),
                ),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, KoruSize.buttonInCard),
                ),
                onPressed: () => Navigator.pop(ctx, _Outcome.save),
                child: Text(existing == null ? 'Add task' : 'Save'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  if (outcome == null) return;
  final store = await ref.read(storeProvider.future);
  final previous = existing;

  if (outcome == _Outcome.delete) {
    final id = previous?.id;
    if (id != null) await store.deleteTask(id);
    invalidateWorkData(ref);
    if (context.mounted) toast(context, 'Task deleted');
    return;
  }

  // An empty title is refused rather than saved as a blank row. A list of blank
  // rows is what happens when a form is allowed to be submitted empty, and every
  // one of them is then something that has to be cleaned up by hand.
  final what = title.text.trim();
  if (what.isEmpty) return;

  if (previous == null) {
    await store.addTask(Task(
      title: what,
      clientId: clientId,
      projectId: project,
      due: due == null ? null : isoDate(due!),
      priority: priority,
      note: note.text.trim().isEmpty ? null : note.text.trim(),
      created: DateTime.now().toIso8601String(),
    ));
  } else {
    await store.updateTask(Task(
      id: previous.id,
      title: what,
      clientId: previous.clientId,
      projectId: project,
      due: due == null ? null : isoDate(due!),
      priority: priority,
      // Done stays done. Editing the wording of a finished task is not how it
      // becomes unfinished, and silently reopening it would make the archive
      // depend on how carefully somebody edits.
      done: previous.done,
      completedAt: previous.completedAt,
      note: note.text.trim().isEmpty ? null : note.text.trim(),
      created: previous.created,
    ));
  }
  invalidateWorkData(ref);
  if (context.mounted) {
    toast(context, previous == null ? 'Task added' : 'Task saved');
  }
}
/// Which button closed the sheet.
///
/// Two outcomes rather than a boolean, because a delete and a save that returns
/// the same value is exactly how a form ends up deleting a task somebody was
/// only renaming.
enum _Outcome { save, delete }
