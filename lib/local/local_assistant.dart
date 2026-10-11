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
      case _Intent.due:
        return LocalAnswer(_due(facts), usedData: facts.hasRecords);
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
    // Due-specific questions come first because the sentence usually also
    // contains a word the business intent matches: "what is due today" contains
    // neither 'client' nor 'money', so it used to fall all the way through to
    // the fallback and the user was told Koru could not help with its own
    // deadlines. That is the single most likely question anyone asks this app.
    if (has(const [
      'due today', 'due this week', 'due soon', 'due now', 'whats due', 'what is due',
      'what are due', 'due tomorrow', 'what do i owe', 'what do they owe',
      'anything due', 'due next', 'not due yet', 'late', 'overdue', 'past due',
    ])) {
      return _Intent.due;
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

  /// What is due, and when.
  ///
  /// Split into three lists on purpose: already late, due today, and coming up.
  /// A single merged list has to be read for the answer, and the first item is
  /// the one that was left out of the thing people actually open this app to
  /// see, which is what is due right now.
  String _due(LocalFacts f) {
    final now = f.today;
    final midnight = DateTime(now.year, now.month, now.day);

    // Money late, from the clients themselves, using the derived due date so
    // agreed terms count without anyone having typed a date.
    final lateMoney = <String>[];
    for (final c in f.clients) {
      final owing = f.balanceOf(c);
      if (owing <= 0) continue;
      final days = c.daysUntilDue(now);
      if (days == null || days >= 0) continue;
      lateMoney.add('${c.name}, ${owing.toStringAsFixed(0)} ${-days} day'
          '${days == -1 ? '' : 's'} late');
    }

    final lateWork = <String>[];
    final todayWork = <String>[];
    final soonWork = <String>[];
    for (final d in f.deadlines) {
      if (d.done) continue;
      final due = DateTime.tryParse(d.due);
      if (due == null) continue;
      final days = DateTime(due.year, due.month, due.day).difference(midnight).inDays;
      if (days < 0) {
        lateWork.add('${d.title} (${-days} day${days == -1 ? '' : 's'} late)');
      } else if (days == 0) {
        todayWork.add(d.title);
      } else if (days <= 7) {
        soonWork.add('${d.title} (in $days day${days == 1 ? '' : 's'})');
      }
    }

    if (lateMoney.isEmpty && lateWork.isEmpty && todayWork.isEmpty &&
        soonWork.isEmpty) {
      return 'Nothing is due. No money is late and no deadline is inside a '
          'week. Add a client with an agreed amount and terms, or a deadline, '
          'and I will start tracking them.';
    }

    final out = StringBuffer();
    if (lateMoney.isNotEmpty) {
      out.writeln('Money you are owed and already late:');
      for (final line in lateMoney.take(4)) {
        out.writeln('  $line');
      }
      if (lateMoney.length > 4) out.writeln('  and ${lateMoney.length - 4} more');
    }
    if (lateWork.isNotEmpty) {
      out.writeln('Work already late:');
      for (final line in lateWork.take(4)) {
        out.writeln('  $line');
      }
      if (lateWork.length > 4) out.writeln('  and ${lateWork.length - 4} more');
    }
    if (todayWork.isNotEmpty) {
      out.writeln('Due today:');
      for (final line in todayWork.take(4)) {
        out.writeln('  $line');
      }
      if (todayWork.length > 4) out.writeln('  and ${todayWork.length - 4} more');
    }
    if (soonWork.isNotEmpty) {
      out.writeln('Coming up in the next week:');
      for (final line in soonWork.take(4)) {
        out.writeln('  $line');
      }
      if (soonWork.length > 4) out.writeln('  and ${soonWork.length - 4} more');
    }
    return out.toString().trimRight();
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

enum _Intent { greeting, identity, capabilities, status, due, business, goals, unknown }

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
