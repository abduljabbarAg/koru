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
    required LocalEngineFacts facts,
    String currency = 'AED',
  }) {
    // Short, and about what this app is rather than about rules.
    //
    // The previous prompt led with six prohibitions. A small model reads a list
    // of "never do this" as a list of things it is unwilling to do, and then
    // refuses the ordinary things too: asked to add a client it would answer
    // that it cannot help with that request. Leading with what the app does and
    // what it can record gets a useful answer; leading with rules gets a shrug.
    final buffer = StringBuffer()
      ..writeln('You are Koru, an assistant for a freelancer. Answer from the')
      ..writeln('facts below. Be brief and concrete. If a figure is not in the')
      ..writeln('facts, say so rather than guessing.')
      ..writeln()
      ..writeln('This app keeps clients, money owed to you, deadlines and your')
      ..writeln('own projects. Koru can record any of those. To record something,')
      ..writeln('say it plainly, like "add client Bilal for 2000", and the app will')
      ..writeln('show what it understood before saving.')
      ..writeln('All amounts below are in $currency.')
      // One line, not three. The clinical, legal and crisis rules used to be
      // spelled out in the prompt as well as enforced by ModelOutputGuard and
      // the routing gate. Keeping one plain sentence and relying on the
      // deterministic layers is defence in depth rather than three ways of
      // saying the same thing to a model that struggles with long rules.
      ..writeln('Never give a medical or legal opinion; say who should decide.');

    // Rendered before the fallback check on purpose. isEmpty only looks at
    // clients and deadlines, so a user with goals set and no records yet counts
    // as empty, and asking that question is exactly the case where duplicating
    // the goals into the prompt costs prefill for nothing.
    final context = facts.renderForModel();

    // The cloud packet is deliberately not sent to a model running on this
    // phone. renderForCloud is documented as what goes upstream, it duplicates
    // the goals and the body logs that the facts above already carry, and every
    // duplicated token is prefill the user sits through before the first word
    // appears. It is used only when the facts render to nothing at all, so a
    // fresh install still says something useful.
    if (context.isEmpty) {
      final cloud = packet.renderForCloud();
      if (cloud.isNotEmpty) buffer.writeln(cloud);
    }

    // The model cannot see the database, so anything it should reason over has
    // to be spelled out here. This is the whole value of a local model: it can
    // answer questions the built-in engine cannot phrase-match.
    if (context.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('What you know right now:')
        ..writeln(context);
    }

    // The question is NOT in this prompt either. It travels as the user message,
    // and repeating it here would cost a second copy of every question on the
    // most expensive machine in the app.
    //
    // Earlier turns are NOT written into this prompt either.
    //
    // They travel as real chat messages instead, and that is not a style
    // choice. glen reuses the longest common token prefix between turns, so a
    // system prompt that changes on every turn means every turn is a full
    // prefill again. Prefill costs about 7 tokens a second on this phone: a
    // 754-token prompt measured 106 seconds cold and 1.2 seconds when the prefix
    // was already cached. Flattening the conversation into the system prompt
    // would have thrown that away and made every follow-up take a minute and a
    // half.
    //
    // So the system prompt stays byte-identical turn to turn, and the history
    // rides along in the messages array where the chat template puts it.

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
  final List<Client> clients;

  /// Money received per client id, so a balance can be stated without the model
  /// having to do arithmetic on numbers it was handed as loose text.
  final Map<int, double> received;

  /// Open deadlines, soonest first.
  final List<Deadline> deadlines;

  const LocalEngineFacts({
    this.nickname = '',
    this.goals = '',
    this.focus = '',
    this.clients = const [],
    this.received = const {},
    this.deadlines = const [],
  });

  bool get isEmpty => clients.isEmpty && deadlines.isEmpty;

  double balanceOf(Client c) =>
      c.id == null ? 0 : c.balanceWith(received[c.id!] ?? 0);

  /// Compact, roughly one line per fact.
  ///
  /// Every line is prefill the user waits through before the first word appears,
  /// so the budget is enforced rather than assumed: clients who owe money are
  /// named individually because that is the question actually asked, and
  /// everything past a handful is counted instead of listed.
  String renderForModel() {
    final lines = <String>[];
    if (goals.isNotEmpty) lines.add('Their goal: $goals');
    if (focus.isNotEmpty) lines.add('They want help with: $focus');

    if (clients.isNotEmpty) {
      // Balances come from the ledger, not from the status. Summing every
      // client counted money that had already been paid, and money for work not
      // finished yet, as "unpaid", so the model was told to chase money it
      // already had.
      final owing = clients.where((c) => balanceOf(c) > 0).toList()
        ..sort((a, b) => balanceOf(b).compareTo(balanceOf(a)));
      final outstanding = owing.fold<double>(0, (a, c) => a + balanceOf(c));
      final paid = clients.where((c) => c.status == 'paid').length;
      final overdue = clients.where((c) => c.isOverdueOn(DateTime.now())).length;

      lines.add('Clients: ${clients.length}, $paid settled');
      lines.add('Still owed in total: ${outstanding.toStringAsFixed(0)} across ${owing.length} client(s)');
      for (final c in owing.take(4)) {
        lines.add('${c.name} owes ${balanceOf(c).toStringAsFixed(0)}');
      }
      if (owing.length > 4) {
        lines.add('and ${owing.length - 4} more client(s) with a balance');
      }
      if (overdue > 0) lines.add('$overdue client(s) are past their due date');
    }

    if (deadlines.isNotEmpty) {
      final items = deadlines.take(4).map((d) => '${d.title} (due ${d.due})').join('; ');
      lines.add('Deadlines coming up: $items');
      if (deadlines.length > 4) {
        lines.add('and ${deadlines.length - 4} more after those');
      }
    }

    return lines.join('\n');
  }
}

/// One earlier turn, carried into the model prompt.
class ChatTurn {
  const ChatTurn(this.role, this.text);

  final ChatRole role;
  final String text;
}

enum ChatRole { user, koru }

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
