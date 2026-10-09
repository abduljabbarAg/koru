import 'models.dart';
import 'packet.dart';

/// Which engine answers a question.
///
/// The default is [builtIn], and deliberately so: it needs no model, no RAM and
/// no round trip, so the app is useful the moment it opens. The other two are
/// opt-in, because both cost something real, a cloud key or a few hundred
/// megabytes of RAM.
enum KoruEngine {
  /// Deterministic answers from the user's own records. Not a language model,
  /// and the UI says so.
  builtIn,

  /// A model served on this device over loopback. Real generation, no network.
  onDevice,

  /// A frontier model over the internet.
  cloud;

  String get label => switch (this) {
        KoruEngine.builtIn => 'Built-in',
        KoruEngine.onDevice => 'On-device model',
        KoruEngine.cloud => 'Cloud model',
      };

  String get blurb => switch (this) {
        KoruEngine.builtIn =>
          'Instant answers from your records. No model, no RAM, no network.',
        KoruEngine.onDevice =>
          'A real model running on this phone. Slower, and it wants memory.',
        KoruEngine.cloud => 'A frontier model over the internet. Needs a key.',
      };

  static KoruEngine parse(String? value) => KoruEngine.values.firstWhere(
        (e) => e.name == value,
        orElse: () => KoruEngine.builtIn,
      );
}

/// Builds the system prompt for a small on-device model.
///
/// A 0.5B model needs a narrower brief than a frontier one. Long instructions
/// wash out, so this is short, concrete, and repeats the one rule that matters
/// most: do not invent a diagnosis or a ruling.
class LocalModelPrompt {
  static String build({
    required ContextPacket packet,
    required String question,
    required LocalEngineFacts facts,
  }) {
    final buffer = StringBuffer()
      ..writeln('You are Koru, a personal assistant running on this phone.')
      ..writeln('Answer in at most three short sentences. Plain text, no markdown.')
      ..writeln('Be concrete. Never invent a name, a number, or a date that is not given below.')
      ..writeln('If the answer is not in the context, say what you do not know.')
      ..writeln('Never give a diagnosis, a dose, or a legal ruling.');

    // The cloud packet is deliberately not sent to a model running on this
    // phone. renderForCloud is documented as what goes upstream, it duplicates
    // the goals and the body logs that LocalEngineFacts already carries, and
    // every duplicated token is prefill the user sits through before the first
    // word appears. It is used only as a fallback for when there are no local
    // facts at all, so a fresh install still says something useful.
    if (facts.isEmpty) {
      final cloud = packet.renderForCloud();
      if (cloud.isNotEmpty) buffer.writeln(cloud);
    }

    // The model cannot see the database, so anything it should reason over has
    // to be spelled out here. This is the whole value of a local model: it can
    // answer questions the built-in engine cannot phrase-match.
    final context = facts.renderForModel();
    if (context.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('What you know right now:')
        ..writeln(context);
    }

    buffer
      ..writeln()
      ..writeln('User question: $question');
    return buffer.toString();
  }
}

/// The slice of the user's data a small model is allowed to reason over.
///
/// Deliberately small. Everything here is already on the device, but a 0.5B
/// model has a short effective context, so it gets a short, dense brief rather
/// than the whole database.
class LocalEngineFacts {
  final String nickname;
  final String goals;
  final String focus;
  final double? height;
  final double? bmi;
  final List<FitnessEntry> fitness;
  final List<Client> clients;

  const LocalEngineFacts({
    this.nickname = '',
    this.goals = '',
    this.focus = '',
    this.height,
    this.bmi,
    this.fitness = const [],
    this.clients = const [],
  });

  bool get isEmpty => fitness.isEmpty && clients.isEmpty;

  /// Compact, roughly one line per fact.
  String renderForModel() {
    final lines = <String>[];
    if (goals.isNotEmpty) lines.add('Their goal: $goals');
    if (focus.isNotEmpty) lines.add('They want help with: $focus');

    if (fitness.isNotEmpty) {
      final latest = fitness.first;
      final parts = <String>[];
      if (latest.weight != null) parts.add('weight ${latest.weight!.toStringAsFixed(1)}kg');
      if (height != null) parts.add('height ${height!.toStringAsFixed(2)}m');
      if (bmi != null) parts.add('BMI ${bmi!.toStringAsFixed(1)}');
      if (parts.isNotEmpty) lines.add('Latest body log: ${parts.join(', ')}');
      if (fitness.length > 1) {
        final previous = fitness[1];
        if (latest.weight != null && previous.weight != null) {
          final change = latest.weight! - previous.weight!;
          lines.add(
            'Change since the previous log: ${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)}kg',
          );
        }
      }
      lines.add('Body logs recorded: ${fitness.length}');
    }

    if (clients.isNotEmpty) {
      // Only delivered work is owed money. Summing every client counted money
      // that had already been paid, and money for work not finished yet, as
      // "unpaid", so the model was told to chase money it already had.
      final unpaidValue = clients
          .where((c) => c.status == 'delivered')
          .fold<double>(0, (a, c) => a + (c.amount ?? 0));
      final paid = clients.where((c) => c.status == 'paid').length;
      final delivered = clients.where((c) => c.status == 'delivered').length;
      final overdue = clients.where((c) => c.isOverdueOn(DateTime.now())).length;
      lines.add('Clients: ${clients.length}, paid $paid, delivered but unpaid $delivered');
      lines.add('Unpaid value across clients: ${unpaidValue.toStringAsFixed(0)} AED');
      if (overdue > 0) lines.add('$overdue client(s) are past their due date');
    }

    return lines.join('\n');
  }
}

/// Re-checks what a model returned before it is shown.
///
/// The routing gate already stops sensitive questions reaching any engine, and
/// that is the real control. This is defence in depth, and it exists because of
/// something measured rather than imagined: asked about doubling a blood
/// pressure dose, Qwen2.5-0.5B on the target phone answered with dose advice.
/// Asked whether breaking a contract was allowed, it ruled on it. A small model
/// has no reliable notion of where its competence ends, so the answer is
/// checked instead of trusted.
///
/// Pure and synchronous so the rules are unit testable without a model.
class ModelOutputGuard {
  const ModelOutputGuard._();

  /// Advice that should only come from a clinician or a lawyer. Matched on
  /// word boundaries, so "illegalise this contract" is not treated as a ruling.
  static const _clinical = [
    'take double', 'double your dose', 'double the dose', 'twice the dose',
    'increase your dose', 'stop taking', 'skip the dose',
    'you have a rash', 'this is cancer', 'this is diabetes',
    'you should stop taking', 'safe to take', 'safe dosage',
  ];

  static const _legal = [
    'is illegal', 'is legal', 'you can sue', 'you cannot sue',
    'is unlawful', 'is lawful', 'you would win the case', 'grounds to sue',
  ];

  static const _crisis = [
    'when not alive', 'not be alive', 'melancholy question', 'feel a void',
  ];

  /// Returns true when [answer] says something that needs a person instead.
  static bool needsHuman(String answer) {
    final q = answer.toLowerCase().replaceAll(RegExp(r"[^a-z0-9' ]"), ' ');
    if (q.trim().isEmpty) return false;
    for (final term in [..._clinical, ..._legal, ..._crisis]) {
      if (_contains(q, term)) return true;
    }
    return false;
  }

  static bool _contains(String haystack, String needle) {
    var from = 0;
    while (true) {
      final at = haystack.indexOf(needle, from);
      if (at < 0) return false;
      final beforeOk = at == 0 || !_isWordChar(haystack[at - 1]);
      final end = at + needle.length;
      final afterOk = end >= haystack.length || !_isWordChar(haystack[end]);
      if (beforeOk && afterOk) return true;
      from = at + 1;
    }
  }

  static bool _isWordChar(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 48 && code <= 122) || code == 39;
  }
}
