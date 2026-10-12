import 'package:flutter_test/flutter_test.dart';
import 'package:koru/engine.dart';
import 'package:koru/models.dart';

import 'test_store.dart';

/// Projects have been in the database since the schema landed and were in
/// nothing the model could read. It knew who owed money and nothing about what
/// any of it was for, so "where are we on the shop" had no answer.
void main() {
  test('a project reaches the model, with its target and latest note', () async {
    final store = await openTestStore();
    final id = await store.addProject(const Project(
      name: 'Bilal shop',
      kind: ProjectKind.client,
      target: 'the shop is open',
      progress: 0.4,
      progressNote: 'two rooms left',
    ));
    await store.addProjectNote(ProjectNote(
      projectId: id,
      body: 'electrician booked for Thursday',
      created: DateTime.now().toIso8601String(),
    ));

    final projects = await store.projects();
    final notes = <int, String>{};
    for (final p in projects) {
      final pid = p.id;
      if (pid == null) continue;
      final latest = await store.projectNotes(pid, limit: 1);
      if (latest.isNotEmpty) notes[pid] = latest.first.body;
    }

    final text = LocalEngineFacts(
      projects: projects,
      projectNotes: notes,
    ).renderForModel();

    expect(text, contains('Bilal shop'));
    expect(text, contains('client'), reason: 'the kind has to be legible');
    expect(text, contains('40%'));
    expect(text, contains('the shop is open'));
    expect(text, contains('electrician booked for Thursday'));
  });

  test('a personal project is marked personal and carries no money', () async {
    final store = await openTestStore();
    await store.addProject(const Project(
      name: 'Learn Arabic',
      kind: ProjectKind.personal,
      progress: 0.1,
    ));

    final text =
        LocalEngineFacts(projects: await store.projects()).renderForModel();

    expect(text, contains('Learn Arabic'));
    expect(text, contains('personal'));
    expect(text.toLowerCase(), isNot(contains('aed')));
    expect(text, isNot(contains('invoice')));
  });

  test('a project with no note is still listed', () async {
    // Omitting it would make the model believe the project does not exist,
    // which is the opposite of the awareness this is for.
    final store = await openTestStore();
    await store.addProject(const Project(name: 'Solo project', progress: 0.2));

    final text =
        LocalEngineFacts(projects: await store.projects()).renderForModel();

    expect(text, contains('Solo project'));
  });

  test('facts are not empty just because there are no clients', () async {
    final store = await openTestStore();
    await store.addProject(const Project(name: 'Anything', progress: 0.5));

    final facts = LocalEngineFacts(projects: await store.projects());
    expect(facts.isEmpty, isFalse);
  });
}
