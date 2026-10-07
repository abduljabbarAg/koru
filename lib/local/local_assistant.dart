import '../models.dart';

/// The on-device half of Koru.
///
/// This is what actually runs for every question the router does not send
/// upstream, and until now that half did not exist: [RoutingDecision.useCloud]
/// was computed, displayed in Settings, and then ignored, so every question went
/// to a paid API and the "answered on device" promise was decoration.
///
/// It is a deterministic assistant, not a language model, and the UI says so. It
/// answers from the user's own records: their profile, their weight, their
/// clients, their goals. That is exactly the class of question a memory-based
/// companion should be good at, and doing it locally is what makes the privacy
/// claim true rather than aspirational.
///
/// Pure Dart and side-effect free: every method takes plain data and returns a
/// string, so the whole thing is testable without a database or a widget tree.
class LocalAssistant {
  const LocalAssistant();

  /// The answer, plus whether it actually found something.
  LocalAnswer answer({
    required String question,
    required LocalFacts facts,
  }) {
    final q = RoutingDecisionNormaliser.fold(question);
    final intent = _classify(q);

    switch (intent) {
      case _Intent.greeting:
        return LocalAnswer(
          _greeting(facts),
          usedData: facts.hasProfile,
        );
      case _Intent.status:
        return LocalAnswer(_status(facts), usedData: facts.hasRecords);
      case _Intent.fitness:
        return LocalAnswer(_fitness(facts), usedData: facts.fitness.isNotEmpty);
      case _Intent.business:
        return LocalAnswer(_business(facts), usedData: facts.clients.isNotEmpty);
      case _Intent.goals:
        return LocalAnswer(_goals(facts), usedData: facts.goals.isNotEmpty);
      case _Intent.identity:
        return LocalAnswer(_identity(facts), usedData: true);
      case _Intent.capabilities:
        return LocalAnswer(_capabilities(), usedData: false);
      case _Intent.unknown:
        return LocalAnswer(
          _fallback(facts),
          usedData: facts.hasRecords,
          suggestCloud: true,
        );
    }
  }

  _Intent _classify(String q) {
    bool has(List<String> words) => words.any(q.contains);

    if (has(const ['hello', 'hi ', 'hey', 'good morning', 'good evening', 'assalam', 'salam'])) {
      return _Intent.greeting;
    }
    if (has(const ['who are you', 'what are you', 'your name', 'about you'])) {
      return _Intent.identity;
    }
    if (has(const [
      'what can you do',
      'help me with',
      'how do i use',
      'what do you know',
      'commands',
    ])) {
      return _Intent.capabilities;
    }
    if (has(const ['how am i', 'how are we', 'status', 'update', 'where do i stand', 'summary'])) {
      return _Intent.status;
    }
    if (has(const [
      'bmi', 'weight', 'weigh', 'waist', 'measure', 'body fat',
      'fitness', 'training', 'workout', 'gym',
    ])) {
      return _Intent.fitness;
    }
    if (has(const [
      'client', 'invoice', 'payment', 'paid', 'pipeline', 'revenue', 'lead',
      'money', 'business', 'sale', 'quote', 'price', 'pricing',
    ])) {
      return _Intent.business;
    }
    if (has(const ['goal', 'goals', 'target', 'plan for', 'three months'])) {
      return _Intent.goals;
    }
    return _Intent.unknown;
  }

  String _greeting(LocalFacts f) {
    final who = f.nickname.isEmpty ? '' : ', ${f.nickname}';
    if (!f.hasRecords) {
      return 'Hello$who. I am running entirely on this phone, so I can already '
          'see your profile. Add a client or log a measurement and I can start '
          'answering properly.';
    }
    return 'Hello$who. Everything I know is on this device.';
  }

  String _identity(LocalFacts f) =>
      'I am Koru. I run on this phone and read nothing you have not put here '
      'yourself. Questions about faith, health, medicine or law get sent to a '
      'frontier model with a pseudonymous summary attached, and nothing else '
      'leaves the device.';

  String _capabilities() => 'On this device I can tell you:\n'
      '\n'
      '  - how you are doing, across work and training\n'
      '  - your latest weight, your BMI, and whether the trend is up or down\n'
      '  - your client pipeline, what is unpaid, and what is overdue\n'
      '  - the goals you set in onboarding\n'
      '\n'
      'Anything about faith, health, medicine or law goes to a stronger model '
      'instead, and anything urgent goes to a person.';

  String _status(LocalFacts f) {
    final lines = <String>[];
    if (f.nickname.isNotEmpty) {
      lines.add('Signed in as ${f.nickname}${f.lifeStage.isEmpty ? '' : ', ${f.lifeStage}'}.');
    }
    if (f.goals.isNotEmpty) {
      lines.add('You said this is what you want to be true in three months: ${f.goals}');
    }

    final biz = _businessLines(f);
    if (biz.isNotEmpty) lines.addAll(biz);

    final fit = _fitnessLines(f);
    if (fit.isNotEmpty) lines.addAll(fit);

    if (lines.isEmpty) {
      return 'Not much to report yet. Log a measurement or add a client and I '
          'will have something to say.';
    }
    return lines.join('\n');
  }

  List<String> _businessLines(LocalFacts f) {
    if (f.clients.isEmpty) return const [];
    final total = f.clients.fold<double>(0, (a, c) => a + (c.amount ?? 0));
    final paid = f.clients.where((c) => c.status == 'paid').length;
    final waiting = f.clients.where((c) => c.status == 'delivered').length;
    final pipeline = f.clients.where((c) => c.status == 'lead' || c.status == 'active').length;
    final out = ['Business: $paid paid, $waiting delivered and waiting, '
        '$pipeline still in the pipeline, ${total.toStringAsFixed(0)} AED booked.'];
    final overdue = f.clients.where((c) => c.isOverdueOn(f.today)).toList();
    if (overdue.isNotEmpty) {
      out.add('Overdue: ${overdue.map((c) => c.name).join(', ')}.');
    }
    return out;
  }

  List<String> _fitnessLines(LocalFacts f) {
    if (f.fitness.isEmpty) return const [];
    final latest = f.fitness.first;
    final parts = <String>[];
    if (latest.weight != null) parts.add('${latest.weight!.toStringAsFixed(1)}kg');
    if (f.bmi != null) parts.add('BMI ${f.bmi!.toStringAsFixed(1)}');
    final trend = f.weightTrendPerWeek;
    if (trend != null) {
      final word = trend > 0.05
          ? 'up ${trend.toStringAsFixed(2)}kg a week'
          : trend < -0.05
              ? 'down ${trend.abs().toStringAsFixed(2)}kg a week'
              : 'holding steady';
      parts.add('trend $word');
    }
    return ['Fitness: ${parts.join(', ')} across ${f.fitness.length} log${f.fitness.length == 1 ? '' : 's'}.'];
  }

  String _fitness(LocalFacts f) {
    if (f.fitness.isEmpty) {
      return 'No measurements logged yet. Log weight and waist from the Fitness '
          'tab and I will track the trend, not just the number.';
    }
    final lines = _fitnessLines(f);
    final latest = f.fitness.first;
    final extras = <String>[];
    if (latest.waist != null) extras.add('waist ${latest.waist!.toStringAsFixed(0)}cm');
    if (latest.chest != null) extras.add('chest ${latest.chest!.toStringAsFixed(0)}cm');
    if (latest.arm != null) extras.add('arm ${latest.arm!.toStringAsFixed(0)}cm');
    if (latest.leg != null) extras.add('leg ${latest.leg!.toStringAsFixed(0)}cm');
    if (extras.isNotEmpty) lines.add('Latest log (${latest.day}): ${extras.join(', ')}.');

    if (f.weightTrendPerWeek != null && f.fitness.length > 1) {
      lines.add('That is a trend, not a single reading. Judge it over weeks, '
          'not days.');
    }
    return lines.join('\n');
  }

  String _business(LocalFacts f) {
    if (f.clients.isEmpty) {
      return 'No clients yet. Add one from the Business tab and I can track '
          'delivered versus paid, and flag anything overdue.';
    }
    final lines = _businessLines(f);
    final needsFollowUp = f.clients
        .where((c) => c.status == 'lead' || c.status == 'active')
        .toList();
    if (needsFollowUp.isNotEmpty) {
      lines.add('Worth a nudge: ${needsFollowUp.map((c) => c.name).join(', ')}.');
    }
    final unpaid = f.clients.where((c) => c.status == 'delivered').toList();
    if (unpaid.isNotEmpty) {
      final sum = unpaid.fold<double>(0, (a, c) => a + (c.amount ?? 0));
      lines.add('Chasing ${sum.toStringAsFixed(0)} AED is the single highest '
          'value thing on this list.');
    }
    return lines.join('\n');
  }

  String _goals(LocalFacts f) {
    if (f.goals.isEmpty) {
      return 'You have not set a goal yet. Add one in Settings and I will hold '
          'you to it.';
    }
    return 'You told me: ${f.goals}\n\n'
        'On the next status check I will compare that against your logs and '
        'your pipeline.';
  }

  String _fallback(LocalFacts f) {
    if (!f.hasRecords) {
      return 'I could not answer that from what is on this phone. On device I '
          'can only work with your profile, your logs and your clients. Add a '
          'cloud key in Settings if you want me to send this one upstream.';
    }
    return 'I could not match that to anything I keep locally. I can answer '
        'from your profile, your logs and your clients. For anything else, add '
        'a cloud key in Settings and I will send a pseudonymous summary with '
        'the question.';
  }
}

enum _Intent { greeting, identity, capabilities, status, fitness, business, goals, unknown }

/// Case folds a question without importing the routing layer, so this file can
/// be unit tested on its own.
class RoutingDecisionNormaliser {
  const RoutingDecisionNormaliser._();

  static String fold(String input) =>
      input.toLowerCase().replaceAll(RegExp(r"[^a-z0-9' ]"), ' ');
}

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
  const LocalFacts({
    this.nickname = '',
    this.lifeStage = '',
    this.goals = '',
    this.height,
    this.bmi,
    this.fitness = const [],
    this.clients = const [],
    DateTime? today,
  }) : today = today ?? DateTime.now();

  final String nickname;
  final String lifeStage;
  final String goals;
  final double? height;
  final double? bmi;

  /// Newest first, which is the order the store already returns.
  final List<FitnessEntry> fitness;
  final List<Client> clients;
  final DateTime today;

  bool get hasProfile => nickname.isNotEmpty || lifeStage.isNotEmpty || goals.isNotEmpty;
  bool get hasRecords => fitness.isNotEmpty || clients.isNotEmpty;

  /// Weight change per week, or null when there is not enough history to say.
  /// Needs at least two readings at least three days apart, otherwise every
  /// session reports a wild number from overnight water retention.
  double? get weightTrendPerWeek {
    final dated = <({DateTime day, double kg})>[];
    for (final e in fitness) {
      final kg = e.weight;
      if (kg == null) continue;
      final day = DateTime.tryParse(e.day);
      if (day == null) continue;
      dated.add((day: day, kg: kg));
    }
    if (dated.length < 2) return null;
    final newest = dated.first;
    final older = dated.last;
    final days = newest.day.difference(older.day).inDays;
    if (days < 3) return null;
    return (newest.kg - older.kg) / (days / 7.0);
  }
}
