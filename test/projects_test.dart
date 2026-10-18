import 'package:flutter_test/flutter_test.dart';
import 'package:koru/models.dart';
import 'package:koru/packet.dart';

import 'test_store.dart';

/// Projects have been in the database since the schema landed and were in
/// nothing the model could read. It knew who owed money and nothing about what
/// any of it was for, so "where are we on the shop" had no answer.
///
/// What reaches a model is [ProfileStore.packet], which is the only constructor
/// for the context that leaves the phone. Projects had to be added to it, and
/// this is what stops that being undone: the dense per-record renderer that fed
/// the removed on-device model is gone, and these tests now assert against the
/// one path that is left.
void main() {
  test('a client project reaches the model as what the work is, not whose',
      () async {
    final store = await openTestStore();
    await store.addProject(const Project(
      name: 'Bilal shop',
      kind: ProjectKind.client,
      target: 'the shop is open',
      progress: 0.4,
      progressNote: 'two rooms left',
    ));

    final text = (await store.packet()).renderForCloud();

    expect(text, contains('the shop is open'));
    expect(text, contains('client'), reason: 'the kind has to be legible');
    expect(text, contains('40%'));
    expect(text, isNot(contains('Bilal shop')),
        reason: 'the project is named by its owner on a client project, and the '
            'owner is a person, and this leaves the phone');
  });

  test('a personal project is marked personal and carries no money', () async {
    final store = await openTestStore();
    await store.addProject(const Project(
      name: 'Learn Arabic',
      kind: ProjectKind.personal,
      progress: 0.1,
    ));

    final text = (await store.packet()).renderForCloud();

    expect(text, contains('Learn Arabic'));
    expect(text, contains('personal'));
    expect(text.toLowerCase(), isNot(contains('aed')));
    expect(text, isNot(contains('invoice')));
  });

  test("a client project's line is named by the work, not the owner", () async {
    // The project text goes upstream described by what the work is — that is
    // the whole point of carrying projects at all. The client's name does travel
    // in the packet now, but on the client's own record line, where it is a
    // fact about money rather than a label on somebody's project; the policy
    // screens say so.
    final store = await openTestStore();
    final id = await store.addClient(
      const Client(name: 'Bilal', amount: 2000, status: 'delivered'),
    );
    await store.addProject(Project(
      name: 'the rebrand',
      kind: ProjectKind.client,
      clientId: id,
      target: 'the new site is live',
      progress: 0.5,
    ));

    final text = (await store.packet()).renderForCloud();

    expect(text, contains('the new site is live'));
    // Everything before the record lines is the profile and the projects; the
    // name belongs only to the record line, where the balance is spoken about.
    final projectPart = text.substring(0, text.indexOf('record:'));
    expect(projectPart, isNot(contains('Bilal')),
        reason: 'the project is named by its owner on a client project, and the '
            'owner is a person, so the project line does not carry the name');
  });

  test('a client project with no target is still listed', () async {
    // Omitting it would make the model believe the project does not exist,
    // which is the opposite of the awareness this is for. With nothing to
    // describe it by, the line falls back to saying it is client work.
    final store = await openTestStore();
    await store.addProject(const Project(name: 'Solo project', progress: 0.2));

    expect((await store.packet()).renderForCloud(), contains('client work'));
  });

  test('a personal project is named, because there is nobody to protect',
      () async {
    // The other half of the rule: a personal project's owner is the user, and
    // the packet already speaks about them in the third person. Naming it is
    // what makes "what am I working on" answerable at all.
    final store = await openTestStore();
    await store.addProject(const Project(
      name: 'Solo project',
      kind: ProjectKind.personal,
      progress: 0.2,
    ));

    expect((await store.packet()).renderForCloud(), contains('Solo project'));
  });

  test('the packet stays inside its word budget with projects in it', () async {
    final store = await openTestStore();
    for (var i = 0; i < 12; i++) {
      await store.addProject(Project(name: 'Project $i', progress: 0.1));
    }

    final packet = await store.packet();
    // The project lines are capped rather than the packet being allowed to grow:
    // a long project list spends the budget the question itself needs.
    expect(packet.wordCount, lessThanOrEqualTo(ContextPacket.maxCloudWords));
    expect(packet.renderForCloud(), contains('and 8 more project(s)'));
  });
}
