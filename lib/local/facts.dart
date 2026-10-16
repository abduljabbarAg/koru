/// The data the on-device assistant is allowed to see, and what it hands back.
///
/// Split out of `local_assistant.dart` so the advice modules under `replies/`
/// can take [LocalFacts] without importing the classifier, which imports them
/// back. The public API is unchanged: `local_assistant.dart` re-exports this
/// file, so everything that worked before works exactly as before.
library;

import '../models.dart';

/// The answer, plus whether it actually found something.
class LocalAnswer {
  const LocalAnswer(this.text, {this.usedData = false, this.suggestCloud = false});

  final String text;

  /// True when the answer was built from the user's own records rather than from
  /// a canned reply. The chat screen uses this to decide whether to say so.
  final bool usedData;

  /// True when the local assistant gave up, so the UI can point at the cloud key
  /// instead of pretending this was a complete answer.
  final bool suggestCloud;
}

/// Everything the assistant is allowed to know, gathered once by the caller.
class LocalFacts {
  LocalFacts({
    this.nickname = '',
    this.lifeStage = '',
    this.goals = '',
    this.clients = const [],
    this.received = const {},
    this.deadlines = const [],
    this.projects = const [],
    this.projectNotes = const {},
    this.events = const [],
    DateTime? today,
  }) : today = today ?? DateTime.now();

  final String nickname;
  final String lifeStage;
  final String goals;

  /// Newest first, which is the order the store already returns.
  final List<Client> clients;

  /// Money received per client id, so the built-in assistant quotes the same
  /// balances the screen shows rather than summing invoice amounts.
  final Map<int, double> received;
  final List<Deadline> deadlines;

  /// Projects and their latest note.
  ///
  /// Added for the same reason as in [LocalEngineFacts]: the assistant could
  /// answer "who owes me" and could not answer "what am I working on", which is
  /// the other half of the question people actually ask.
  final List<Project> projects;
  final Map<int, String> projectNotes;

  /// Calendar entries, which is what "what is on today" is asking about.
  final List<CalendarEvent> events;

  final DateTime today;

  bool get hasProfile => nickname.isNotEmpty || lifeStage.isNotEmpty || goals.isNotEmpty;
  bool get hasRecords =>
      clients.isNotEmpty ||
      deadlines.isNotEmpty ||
      received.isNotEmpty ||
      projects.isNotEmpty ||
      events.isNotEmpty;

  double balanceOf(Client c) =>
      c.id == null ? 0 : c.balanceWith(received[c.id!] ?? 0);
}
