import '../models.dart';

/// The on-device half of Koru.
///
/// This is what actually runs for every question the router does not send
/// upstream, and until now that half did not exist: [RoutingDecision.useCloud]
/// was computed, displayed in Settings, and then ignored, so every question went
/// to a paid API and the "answered on device" promise was decoration.
///
/// It is a deterministic assistant, not a language model, and the UI says so. It
/// answers from the user's own records: their profile, their clients, their
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
      'client', 'invoice', 'payment', 'paid', 'pipeline', 'revenue', 'lead',
      'money', 'business', 'sale', 'quote', 'price', 'pricing',
      // Deadlines are part of the same loop, and "what is coming up" is one of
      // the suggestions the chat itself offers, so it has to land somewhere.
      'deadline', 'coming up', 'upcoming', 'schedule', 'this week',
      'next week', 'chase', 'owe', 'owed', 'outstanding', 'balance',
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
          'see your profile. Add a client and I can start telling you who owes '
          'you what.';
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
      '  - who owes you money, and how much each of them\n'
      '  - what is overdue and worth chasing first\n'
      '  - what is coming up, and what is stale in the pipeline\n'
      '  - the goals you set in onboarding\n'
      '\n'
      'I can also record things for you. Say "add client Bilal for 2000" or '
      '"Bilal paid 500" and I will show you exactly what I understood before '
      'anything is saved.\n'
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

    // A profile on its own is not a status report. Say what is missing rather
    // than returning just a greeting echoed back.
    if (biz.isEmpty && f.goals.isEmpty) {
      lines.add('Nothing on file yet. Add a client and I will have something '
          'real to say.');
    }
    return lines.join('\n');
  }

  List<String> _businessLines(LocalFacts f) {
    if (f.clients.isEmpty) return const [];
    // Balances, not invoice amounts. Summing `amount` counted money already in
    // the bank as still owed, so this assistant used to tell someone to chase
    // money they had already been paid.
    final owing = f.clients.where((c) => f.balanceOf(c) > 0).toList()
      ..sort((a, b) => f.balanceOf(b).compareTo(f.balanceOf(a)));
    final outstanding = owing.fold<double>(0, (a, c) => a + f.balanceOf(c));
    final received = f.received.values.fold<double>(0, (a, v) => a + v);
    final pipeline = f.clients.where((c) => c.status == 'lead' || c.status == 'active').length;

    final out = [
      '${f.clients.length} client${f.clients.length == 1 ? '' : 's'}, '
      '${owing.length} owing a balance, $pipeline still in the pipeline.',
      'Received ${received.toStringAsFixed(0)}, still owed '
      '${outstanding.toStringAsFixed(0)}.',
    ];
    if (owing.isNotEmpty) {
      out.add('Biggest: ${owing.first.name} at '
          '${f.balanceOf(owing.first).toStringAsFixed(0)}.');
    }
    final overdue = f.clients.where((c) => c.isOverdueOn(f.today)).toList();
    if (overdue.isNotEmpty) {
      out.add('Past the due date: ${overdue.map((c) => c.name).join(', ')}.');
    }
    final due = f.deadlines.take(3).map((d) => d.title).toList();
    if (due.isNotEmpty) {
      out.add('Coming up: ${due.join(', ')}.');
    }
    return out;
  }

  String _business(LocalFacts f) {
    if (f.clients.isEmpty && f.deadlines.isEmpty) {
      return 'No clients yet. Say "add client Bilal for 2000" and I will set '
          'them up, then track what they owe you.';
    }
    final lines = _businessLines(f);
    final stale = f.clients
        .where((c) => c.status == 'lead' || c.status == 'active')
        .toList();
    if (stale.isNotEmpty) {
      lines.add('Still open with no movement: '
          '${stale.map((c) => c.name).join(', ')}. Those are the ones going cold.');
    }
    return lines.join('\n');
  }

  String _goals(LocalFacts f) {
    if (f.goals.isEmpty) {
      return 'You have not set a goal yet. Add one in Settings and I will hold '
          'you to it.';
    }
    return 'You told me: ${f.goals}\n\n'
        'On the next status check I will compare that against your pipeline and '
        'what you are owed.';
  }

  String _fallback(LocalFacts f) {
    if (!f.hasRecords) {
      return 'I could not answer that from what is on this phone. On device I '
          'can only work with your clients, your money and your deadlines. Add a '
          'cloud key in Settings if you want me to send this one upstream.';
    }
    return 'I could not match that to anything I keep locally. I can answer '
        'from your clients, your money and your deadlines. For anything else, '
        'add a cloud key in Settings and I will send a pseudonymous summary '
        'with the question.';
  }
}

enum _Intent { greeting, identity, capabilities, status, business, goals, unknown }

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
  LocalFacts({
    this.nickname = '',
    this.lifeStage = '',
    this.goals = '',
    this.clients = const [],
    this.received = const {},
    this.deadlines = const [],
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
  final DateTime today;

  bool get hasProfile => nickname.isNotEmpty || lifeStage.isNotEmpty || goals.isNotEmpty;
  bool get hasRecords =>
      clients.isNotEmpty || deadlines.isNotEmpty || received.isNotEmpty;

  double balanceOf(Client c) =>
      c.id == null ? 0 : c.balanceWith(received[c.id!] ?? 0);
}
