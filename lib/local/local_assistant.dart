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
/// calendar, their goals. That is exactly the class of question a memory-based
/// companion should be good at, and doing it locally is what makes the privacy
/// claim true rather than aspirational.
///
/// Deliberately much wider than a keyword lookup over the database. Most of
/// what people type at a assistant is not a database question at all: it is
/// "how are you", "thanks", "what is 15% of 2000", "what day is it". A
/// responder that shrugs at all of that is technically correct and feels like a
/// form, so every one of those has an answer here, computed without a model.
///
/// Pure Dart and side-effect free: every method takes plain data and returns a
/// string, so the whole thing is testable without a database or a widget tree.
class LocalAssistant {
  const LocalAssistant();

  /// The answer, plus whether it actually found something.
  LocalAnswer answer({
    required String question,
    required LocalFacts facts,

    /// The question before this one, if there was one.
    ///
    /// Needed because "what about next week?" has no subject of its own. It is
    /// not passed in by the caller as a string of history because the assistant
    /// only ever needs the one previous turn; threading a list through would
    /// make every call site responsible for a rule that is not theirs.
    String? previousQuestion,
  }) {
    final q = RoutingDecisionNormaliser.fold(
      previousQuestion == null
          ? question
          // The previous subject is carried forward so "what about next week"
          // still knows it was asked about Bilal, while the new question
          // supplies the rest. Prepended, not appended, so an explicit name in
          // the new question wins the match on word count.
          : '$previousQuestion $question',
    );
    // Arithmetic is matched against the raw words rather than the folded ones:
    // folding turns "2000 plus 500"'s operators into spaces and "15% of 2000"
    // into "15 of 2000", and a sum with its signs taken out is not a sum.
    final raw = question.toLowerCase();
    if (_looksLikeMath(raw)) return LocalAnswer(_math(raw), usedData: false);
    final intent = _classify(q, facts);

    switch (intent) {
      case _Intent.greeting:
        return LocalAnswer(_greeting(facts, q), usedData: facts.hasProfile);
      case _Intent.howAreYou:
        return LocalAnswer(_howAreYou(facts), usedData: false);
      case _Intent.thanks:
        return LocalAnswer(_thanks(facts), usedData: false);
      case _Intent.goodbye:
        return LocalAnswer(_goodbye(facts), usedData: false);
      case _Intent.praise:
        return LocalAnswer(_praise(facts), usedData: false);
      case _Intent.status:
        return LocalAnswer(_status(facts), usedData: facts.hasRecords);
      case _Intent.due:
        return LocalAnswer(_due(facts), usedData: facts.hasRecords);
      case _Intent.chase:
        return LocalAnswer(_chase(facts), usedData: facts.clients.isNotEmpty);
      case _Intent.clientLookup:
        return LocalAnswer(
          _clientDetail(facts, _clientNamedIn(q, facts)!),
          usedData: true,
        );      case _Intent.calendar:
        return LocalAnswer(_calendar(facts), usedData: facts.hasRecords);
      case _Intent.dateInfo:
        return LocalAnswer(_dateInfo(facts, q), usedData: false);
      case _Intent.business:
        return LocalAnswer(_business(facts), usedData: facts.clients.isNotEmpty);
      case _Intent.counts:
        return LocalAnswer(_counts(facts), usedData: facts.hasRecords);
      case _Intent.project:
        return LocalAnswer(_projects(facts), usedData: facts.projects.isNotEmpty);
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

  // -- talking, rather than answering ---------------------------------
  //
  // The half of a conversation that is not a question about the database. Each
  // one has a small set of variants picked off the question itself, so the
  // second "thanks" does not read like a recording, while staying fully
  // deterministic: the same input always gives the same reply, which is what
  // keeps this testable without a model.

  String _greeting(LocalFacts f, String q) {
    final who = f.nickname.isEmpty ? '' : ', ${f.nickname}';
    final variants = f.hasRecords
        ? <String>[
            'Hello$who. What are we looking at?',
            'Hi$who. Your records are right here, ask away.',
            'Hey$who. What do you need?',
          ]
        : <String>[
            'Hello$who. I am running entirely on this phone, so I can '
                'already see your profile. Add a client and I can start '
                'telling you who owes you what.',
            'Hi$who. Nothing is on file yet. Say "add client Bilal for 2000" '
                'and I will set you up.',
          ];
    return _pick(variants, q);
  }

  String _howAreYou(LocalFacts f) {
    if (!f.hasRecords) {
      return 'Running quietly on your phone, with nothing to keep track of '
          'yet. Add a client and I will have something to be busy with.';
    }
    final owing = f.clients.where((c) => f.balanceOf(c) > 0).length;
    if (owing > 0) {
      return 'Here and keeping watch. $owing '
          '${owing == 1 ? 'client owes' : 'clients owe'} you money right now, '
          'so that is what I am thinking about.';
    }
    return 'Here and idle. Nothing is owed to you at the moment, which means '
        'everything you have recorded is settled.';
  }

  String _thanks(LocalFacts f) {
    final who = f.nickname.isEmpty ? '' : ' $f.nickname'.trimRight();
    return _pick([
      'Anytime$who. Ask again whenever.',
      'You are welcome. That is what I am here for.',
      'Of course. I am on this phone, so I am always here.',
    ], who.isEmpty ? 'thanks' : who);
  }

  String _goodbye(LocalFacts f) => _pick([
        'See you. Everything stays on this phone until you are back.',
        'Goodbye. I will be here, and nothing leaves the device.',
      ], f.nickname);

  String _praise(LocalFacts f) => _pick([
        'Thank you. I will keep watching the invoices.',
        'That is kind. Ask me again when the money comes in.',
      ], f.nickname);

  // -- answers from records -------------------------------------------

  /// Projects, described from the records rather than from the name.
  String _projects(LocalFacts f) {
    if (f.projects.isEmpty) {
      return 'You have not added any projects yet. Add one from the Projects '
          'tab, and it will show up here with its progress and your last note.';
    }
    final out = <String>[];
    for (final pr in f.projects.take(6)) {
      final pct = (pr.progress * 100).round();
      final kind = pr.isPersonal ? 'Personal' : 'Client work';
      final note = f.projectNotes[pr.id]?.trim();
      final bits = <String>['$pct% along'];
      if (pr.target != null && pr.target!.isNotEmpty) {
        bits.add('done when ${pr.target}');
      }
      if (note != null && note.isNotEmpty) bits.add('latest: $note');
      out.add('${pr.name} ($kind, ${bits.join(', ')})');
    }
    if (f.projects.length > 6) {
      out.add('and ${f.projects.length - 6} more.');
    }
    return 'Here is what you are working on.\n${out.join('\n')}';
  }

  _Intent _classify(String q, LocalFacts f) {
    bool has(List<String> words) => words.any(q.contains);

    // Talking first. None of these mentions a record, so they are checked
    // before anything that does, and a "hi, how are you" cannot be pulled into
    // the business intent by the word "how".
    if (has(const [
      'thank you', 'thanks', 'thankyou', 'jazakallah', 'jazak', 'shukran',
      'appreciate it', 'appreciated', 'cheers', 'much obliged',
    ])) {
      return _Intent.thanks;
    }
    if (has(const [
      'goodbye', 'good bye', 'see you', 'catch you later', 'good night',
      'goodnight', 'talk later', 'gotta go', 'got to go', 'bye for now',
    ])) {
      return _Intent.goodbye;
    }
    if (has(const [
      'how are you', "how're you", 'how r u', 'how is it going',
      'how is it going', 'hows it going', 'whats up', 'what is up',
      'you ok', 'you good', 'how do you feel', 'you alright', 'all good',
    ])) {
      return _Intent.howAreYou;
    }
    if (has(const [
      'you are great', 'youre great', 'you are good', 'youre good',
      'love the app', 'love this app', 'good job', 'well done', 'nice one',
      'you are amazing', 'youre amazing', 'brilliant', 'perfect, thanks',
    ])) {
      return _Intent.praise;
    }
    // Word boundaries, not substring: bare "hi" matches inside "this", which
    // would turn "is this working" into a greeting.
    if (RegExp(r'\b(hello|hi|hey|yo|salam|assalam)\b').hasMatch(q) ||
        has(const ['good morning', 'good evening', 'good afternoon'])) {
      return _Intent.greeting;
    }

    if (has(const ['who are you', 'what are you', 'your name', 'about you'])) {
      return _Intent.identity;
    }
    if (has(const [
      'what can you do', 'help me with', 'how do i use', 'what do you know',
      'commands', 'what should i ask', 'what questions', 'menu',
    ])) {
      return _Intent.capabilities;
    }

    // The date and the clock, asked the way people actually ask.
    if (has(const [
      'what day is it', 'what day is today', 'what is the date',
      'whats the date', 'what date is it', 'todays date', "today's date",
      'what time is it', 'the time now', 'what month is it',
      'what year is it', 'how long until',
    ])) {
      return _Intent.dateInfo;
    }
    if (has(const [
      'what am i working on',
      'what am i doing',
      'my project',
      'my projects',
      'which project',
      'how is the project',
      'how far along',
      'progress on',
      'tell me about the project',
    ])) {
      return _Intent.project;
    }
    if (has(const [
      'how many clients', 'how many project', 'how many deadline',
      'how many payment', 'how many people', 'how many customer',
      'count my', 'number of clients',
    ])) {
      return _Intent.counts;
    }
    if (has(const ['how am i', 'how are we', 'status', 'update', 'where do i stand', 'summary',
        'how are things', 'how is everything', 'my business'])) {
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
      'am i behind', 'behind on', 'whos late', 'who is late',
    ])) {
      return _Intent.due;
    }
    // One named client, asked about money. Checked before the general business
    // intent so "how much does Bilal owe" is about Bilal and not about
    // everybody at once.
    if (_clientNamedIn(q, f) != null &&
        has(const [
          'owe', 'owes', 'owed', 'balance', 'paid', 'pay', 'chase',
          'settle', 'settled', ' invoice', 'still to pay', 'much left',
        ])) {
      return _Intent.clientLookup;
    }
    if (has(const [
      'who should i chase', 'who to chase', 'chase first', 'chasing',
      'biggest debt', 'worst payer', 'who hasnt paid', 'who has not paid',
      'who owes the most', 'whos late', 'not paying', 'nudging',
    ])) {
      return _Intent.chase;
    }
    // The calendar, claimed before the general business intent so "what is on
    // my schedule" does not get a pipeline report.
    if (has(const [
      'my calendar', 'on my calendar', 'my schedule', 'my meetings',
      'my appointments', 'am i meeting', 'do i have any meetings',
      'any meetings', 'what meetings', 'schedule for', 'agenda',
      'what is on today', 'whats on today', 'what am i doing today',
      'meet me', 'coffee with', 'call with', 'lunch with',
    ])) {
      return _Intent.calendar;
    }
    if (has(const [
      'client', 'invoice', 'payment', 'paid', 'pipeline', 'revenue', 'lead',
      'money', 'business', 'sale', 'quote', 'price', 'pricing',
      // Deadlines are part of the same loop, and "what is coming up" is one of
      // the suggestions the chat itself offers, so it has to land somewhere.
      'deadline', 'coming up', 'upcoming', 'schedule', 'this week',
      'next week', 'chase', 'owe', 'owed', 'outstanding', 'balance',
      'retainer', 'deposit', 'terms', 'rate', 'charge', 'earning', 'income',
    ])) {
      return _Intent.business;
    }
    if (has(const ['goal', 'goals', 'target', 'plan for', 'three months'])) {
      return _Intent.goals;
    }
    return _Intent.unknown;
  }

  // -- arithmetic ------------------------------------------------------

  /// True when [q] is asking for a sum rather than mentioning numbers.
  ///
  /// The expression has to be the whole question once the asking words are
  /// taken off. "What is 15% of 2000" qualifies; "Bilal paid 500 for the
  /// logo" does not, and must never be evaluated as arithmetic.
  ///
  /// [q] arrives lower case and un-folded: this is matched against the raw
  /// words, because folding takes the operators out.
  bool _looksLikeMath(String q) {
    if (!RegExp(r'\d').hasMatch(q)) return false;
    // Percentages are unambiguous: nobody writes "% of" in prose.
    if (RegExp(r'\d\s*%').hasMatch(q)) return true;
    final stripped = _stripAsk(q);
    // Only an expression is left, and it carries an operator.
    return RegExp(r'^[\d\s()+\-*/.]+$').hasMatch(stripped) &&
        RegExp(r'[+\-*/]').hasMatch(stripped);
  }

  /// Removes the asking words from the front of a lower-case question, leaving
  /// whatever was asked about.
  String _stripAsk(String raw) => raw
      .replaceAll(RegExp(
          r'^\s*(?:what is|what.s|whats|calculate|compute|how much is|'
          r'solve|work out|equals|=)\s*'),
          '')
      .replaceAll(RegExp(r'\s*\?\s*$'), '')
      .replaceAll('plus', '+')
      .replaceAll('minus', '-')
      .replaceAll('multiplied by', '*')
      .replaceAll('divided by', '/')
      .replaceAll('times', '*')
      .replaceAll(',', '')
      .trim();

  String _math(String q) {
    final percent = RegExp(r'(\d+(?:\.\d+)?)\s*%\s*of\s*(\d[\d,]*(?:\.\d+)?)');
    final p = percent.firstMatch(q);
    if (p != null) {
      final pct = double.parse(p.group(1)!);
      final of = double.parse(p.group(2)!.replaceAll(',', ''));
      return '${_num(pct / 100 * of)} is $pct% of ${_num(of)}.';
    }

    final raw = _stripAsk(q);
    final value = _evaluate(raw);
    if (value == null) {
      return 'I could not read that as a sum. I handle things like "what is '
          '15% of 2000" or "2000 plus 500".';
    }
    return '${_num(value)}.';
  }

  /// Left-to-right with * and / binding tighter than + and -, which is what
  /// the questions people actually ask need and nothing more.
  double? _evaluate(String expression) {
    final tokens = <String>[];
    final scanner = RegExp(r'\d+(?:\.\d+)?|[()+\-*/]');
    var index = 0;
    while (index < expression.length) {
      if (expression[index] == ' ') {
        index++;
        continue;
      }
      final m = scanner.matchAsPrefix(expression, index);
      if (m == null) return null;
      tokens.add(m.group(0)!);
      index = m.end;
    }
    if (tokens.isEmpty) return null;
    return _ExprParser(tokens).parse();
  }

  /// "2000" rather than "2000.0", because a sum answered with floating point
  /// noise is worse than no sum.
  String _num(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  // -- date and calendar ----------------------------------------------

  String _dateInfo(LocalFacts f, String q) {
    final now = f.today;
    const days = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
      'Sunday',
    ];
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June', 'July',
      'August', 'September', 'October', 'November', 'December',
    ];
    final day = days[now.weekday - 1];
    final month = months[now.month - 1];
    final hour = now.hour;
    final minute = now.minute.toString().padLeft(2, '0');
    final meridiem = hour >= 12 ? 'pm' : 'am';
    final twelve = hour % 12 == 0 ? 12 : hour % 12;
    // The clock only rides along when the question was about the clock.
    // "What day is it" answered with the minute is the app showing off.
    final wantsTime =
        RegExp(r'\btime\b|o ?clock').hasMatch(q);
    final clock = wantsTime ? ' It is $twelve:$minute $meridiem.' : '';
    return 'It is $day, ${now.day} $month ${now.year}.$clock';
  }

  /// What is on the calendar, merged with what is due.
  ///
  /// Merged on purpose. A person asking "what is on today" wants both the call
  /// at 3pm and the invoice that has to go out, and making them ask twice is
  /// the app being correct about its own tables instead of helpful.
  String _calendar(LocalFacts f) {
    final now = f.today;
    final midnight = DateTime(now.year, now.month, now.day);

    final entries = <({int days, String line})>[];
    for (final e in f.events) {
      final starts = e.startsAt;
      if (starts == null) continue;
      final day = DateTime(starts.year, starts.month, starts.day)
          .difference(midnight)
          .inDays;
      if (day < 0 || day > 7) continue;
      final when = day == 0
          ? 'Today'
          : day == 1
              ? 'Tomorrow'
              : 'In $day days';
      entries.add((
        days: day,
        line: '$when, ${e.timeLabel} \u2014 ${e.title}'
            '${e.location == null ? '' : ' (${e.location})'}',
      ));
    }
    for (final d in f.deadlines) {
      if (d.done) continue;
      final due = DateTime.tryParse(d.due);
      if (due == null) continue;
      final day =
          DateTime(due.year, due.month, due.day).difference(midnight).inDays;
      if (day < 0 || day > 7) continue;
      final when = day == 0 ? 'Due today' : 'Due in $day day${day == 1 ? '' : 's'}';
      entries.add((days: day, line: '$when \u2014 ${d.title}'));
    }

    if (entries.isEmpty) {
      final anyEvents = f.events.isNotEmpty;
      return anyEvents
          ? 'Nothing on your calendar in the next seven days. The next thing '
              'on file is later than that.'
          : 'Your calendar is empty for the next seven days. Say "schedule a '
              'call with Bilal tomorrow at 3pm" and I will put it here.';
    }

    entries.sort((a, b) => a.days.compareTo(b.days));
    final lines = entries.take(8).map((e) => '  ${e.line}').toList();
    if (entries.length > 8) {
      lines.add('  and ${entries.length - 8} more this week');
    }
    final header = entries.first.days == 0
        ? 'Today, and the next seven days:'
        : 'Coming up in the next seven days:';
    return '$header\n${lines.join('\n')}';
  }

  // -- money ------------------------------------------------------------

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

  /// Who to chase, in the order worth chasing them.
  ///
  /// Late money first, then the largest balance, because the second is nearly
  /// always the same list in a slightly different order, and a person asking
  /// this wants a name to act on rather than a table.
  String _chase(LocalFacts f) {
    if (f.clients.isEmpty) {
      return 'Nobody yet: there are no clients on file. Say "add client Bilal '
          'for 2000" and I will start tracking what they owe.';
    }
    // Worth chasing means late, or owed with no date to wait for. A client
    // whose terms still have a week to run is not being chased, however large
    // the balance, and putting them on this list would make the list noise.
    //
    // A client with no id has no ledger, so their balance reads as zero even
    // though the invoice amount is real. The invoiced figure is used for those
    // rather than telling someone with one freshly added client that nobody
    // needs chasing.
    double owedOf(Client c) => c.id == null ? (c.amount ?? 0) : f.balanceOf(c);
    bool worthChasing(Client c) {
      if (owedOf(c) <= 0) return false;
      if (c.isOverdueOn(f.today)) return true;
      return c.dueDate == null;
    }

    final owing = f.clients.where(worthChasing).toList()
      ..sort((a, b) {
        final aLate = a.isOverdueOn(f.today) ? 1 : 0;
        final bLate = b.isOverdueOn(f.today) ? 1 : 0;
        if (aLate != bLate) return bLate - aLate;
        return owedOf(b).compareTo(owedOf(a));
      });
    if (owing.isEmpty) {
      return 'Nobody right now. Nothing is past its date, so the list of '
          'people to chase is empty. That is the good kind of empty.';
    }
    final lines = <String>[];
    for (final c in owing.take(4)) {
      final days = c.daysUntilDue(f.today);
      final late = (days != null && days < 0)
          ? ', ${-days} day${days == -1 ? '' : 's'} late'
          : (days == null ? '' : ', due in $days day${days == 1 ? '' : 's'}');
      lines.add('  ${c.name} \u2014 ${owedOf(c).toStringAsFixed(0)}$late');
    }
    if (owing.length > 4) lines.add('  and ${owing.length - 4} more');
    return 'Chase these first:\n${lines.join('\n')}';
  }

  /// The client a sentence names, longest name first, or null.
  ///
  /// Matches on every word of the client's name appearing in the question,
  /// which handles "bilal", "bilal studio" and "the thing for Bilal Studio"
  /// with one rule. Ties go to the longer name, so "Bilal Studio" wins over a
  /// second client called "Bilal" when both are on file.
  Client? _clientNamedIn(String q, LocalFacts? f, {List<Client>? clients}) {
    final list = clients ?? f?.clients ?? const <Client>[];
    Client? best;
    var bestWords = 0;
    for (final c in list) {
      final words = c.name
          .toLowerCase()
          .split(RegExp(r'\s+'))
          .where((w) => w.length > 1)
          .toList();
      if (words.isEmpty) continue;
      if (!words.every(q.contains)) continue;
      if (words.length >= bestWords) {
        best = c;
        bestWords = words.length;
      }
    }
    if (best != null) return best;

    // Nothing matched exactly. Before answering "I do not have a client called
    // Bial", try to work out who was meant: people type names into speech and
    // it comes out wrong far more often than it comes out right, and "no such
    // client" is a confidently wrong answer to "how much does Bilal owe".
    return _closestClient(q, list);
  }

  /// The client whose name is nearest to something in [q], if one is close
  /// enough to be worth guessing.
  ///
  /// Bounded on purpose. An unbounded nearest-neighbour answers *something* for
  /// every input, so "what is the weather" eventually returns a client's
  /// balance. Past the threshold the honest answer is that no client matched.
  static const _typoTolerance = 2;

  Client? _closestClient(String q, List<Client> clients) {
    if (clients.isEmpty) return null;
    // Longest run of letters in the question, which is far more likely to be a
    // name than any single word is.
    final words = RegExp(r'[a-z]{3,}')
        .allMatches(q.toLowerCase())
        .map((m) => m.group(0)!)
        .toList();
    if (words.isEmpty) return null;

    Client? best;
    var bestDistance = 1 << 30;
    for (final c in clients) {
      final target = c.name.toLowerCase();
      for (final w in words) {
        // Compared against the whole name and each of its parts, because
        // "acme" should find "Acme Studio" and not only an exact full match.
        for (final candidate in [target, ...target.split(RegExp(r'\s+'))]) {
          final d = _editDistance(w, candidate, _typoTolerance + 1);
          if (d == null) continue;
          if (d < bestDistance) {
            bestDistance = d;
            best = c;
          }
        }
      }
    }
    // A total of zero was handled by the exact pass, so anything within the
    // tolerance is a genuine near miss rather than a second look at a match.
    if (best == null || bestDistance > _typoTolerance) return null;
    return best;
  }

  /// Levenshtein distance, or null once [limit] is exceeded.
  ///
  /// Bailing out early matters: this runs over every client for every word in
  /// the question, and the full matrix for a long name is wasted work the
  /// moment the answer is known to be "too far".
  static int? _editDistance(String a, String b, int limit) {
    if ((a.length - b.length).abs() > limit) return null;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    var cur = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      cur[0] = i;
      var rowMin = cur[0];
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        cur[j] = [cur[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost]
            .reduce((x, y) => x < y ? x : y);
        if (cur[j] < rowMin) rowMin = cur[j];
      }
      if (rowMin > limit) return null;
      final t = prev;
      prev = cur;
      cur = t;
    }
    return prev[b.length] > limit ? null : prev[b.length];
  }

  /// Everything about one named client.
  String _clientDetail(LocalFacts f, Client c) {
    final balance = f.balanceOf(c);
    final received = f.received[c.id] ?? 0;
    final status = switch (c.status) {
      'paid' => 'settled',
      'delivered' => 'delivered and waiting on payment',
      'active' => 'work in progress',
      'lost' => 'lost',
      _ => 'still a lead',
    };
    final bits = <String>['${c.name} is $status.'];
    if (c.amount != null) {
      bits.add('Agreed ${c.amount!.toStringAsFixed(0)}, '
          'received ${received.toStringAsFixed(0)}, '
          'so ${balance.toStringAsFixed(0)} is still owed.');
    } else {
      bits.add('No amount is agreed yet, so there is nothing to be owed.');
    }
    final days = c.daysUntilDue(f.today);
    if (days != null && balance > 0) {
      bits.add(days < 0
          ? 'That is ${-days} day${days == -1 ? '' : 's'} past the due date.'
          : 'Due in $days day${days == 1 ? '' : 's'} (${c.termsLabel}).');
    }
    if (c.isRetainer) {
      bits.add('Retainer: ${c.monthly!.toStringAsFixed(0)} a month.');
    }
    return bits.join(' ');
  }

  String _counts(LocalFacts f) {
    final owing = f.clients.where((c) => f.balanceOf(c) > 0).length;
    final parts = <String>[
      '${f.clients.length} client${f.clients.length == 1 ? '' : 's'}',
      '$owing owing a balance',
      '${f.deadlines.length} open deadline${f.deadlines.length == 1 ? '' : 's'}',
      '${f.events.length} calendar '
          'entr${f.events.length == 1 ? 'y' : 'ies'}',
      '${f.projects.length} project${f.projects.length == 1 ? '' : 's'}',
    ];
    return 'On file: ${parts.join(', ')}.';
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

  String _identity(LocalFacts f) => _pick([
        'I am Koru. I run on this phone and read nothing you have not put '
            'here yourself. Questions about faith, health, medicine or law '
            'get sent to a frontier model with a pseudonymous summary '
            'attached, and nothing else leaves the device.',
        'I am Koru, your business buddy. Everything I know about your '
            'clients and your money lives on this phone, in your own '
            'database. I answer from it, and I say where every answer came '
            'from.',
      ], f.nickname);

  String _capabilities() => 'On this device I can tell you:\n'
      '\n'
      '  - who owes you money, and how much each of them\n'
      '  - who to chase first, and what is overdue\n'
      '  - what is on your calendar, and what is coming up\n'
      '  - what is stale in the pipeline and how far along projects are\n'
      '  - sums like "what is 15% of 2000", and what the date is\n'
      '  - the goals you set in onboarding\n'
      '\n'
      'I can also record things for you. Say "add client Bilal for 2000", '
      '"Bilal paid 500", or "schedule a call with Bilal tomorrow at 3pm" and '
      'I will show you exactly what I understood before anything is saved.\n'
      '\n'
      'Anything about faith, health, medicine or law goes to a stronger model '
      'instead, and anything urgent goes to a person.';

  String _fallback(LocalFacts f) {
    final suggestions = <String>[
      if (f.clients.isNotEmpty) '"who owes me money?"',
      if (f.deadlines.isNotEmpty || f.events.isNotEmpty) '"what is due today?"',
      if (f.projects.isNotEmpty) '"what am I working on?"',
      '"what can you do?"',
    ];
    final tail = suggestions.isEmpty
        ? '"what can you do?"'
        : suggestions.take(3).join(', ');
    if (!f.hasRecords) {
      return 'I could not answer that from what is on this phone. On device I '
          'answer questions about your clients, your money, your calendar and '
          'your deadlines, and I do sums like "what is 15% of 2000". Try one '
          'of: $tail\n\n'
          'For anything else, add a cloud key in Settings and I will send it '
          'upstream with a pseudonymous summary.';
    }
    return 'I could not match that to anything I keep locally. I can answer '
        'from your clients, your money, your calendar and your deadlines, and '
        'I do sums. Try one of: $tail\n\n'
        'For anything else, add a cloud key in Settings and I will send a '
        'pseudonymous summary with the question.';
  }

  /// Deterministic variation: the same question always gives the same answer,
  /// and two different questions can get two different phrasings.
  String _pick(List<String> options, String seed) {
    var hash = 0x811c9dc5;
    for (final unit in seed.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    return options[hash % options.length];
  }
}

/// A tiny arithmetic parser for the sums people actually ask a business
/// assistant: single lines of +, -, *, / and brackets, with no variables and no
/// surprises. A class rather than nested closures because the grammar is
/// mutually recursive and Dart will not let a local function call one declared
/// after it.
class _ExprParser {
  _ExprParser(this.tokens);

  final List<String> tokens;
  int _pos = 0;

  double? parse() {
    final value = _additive();
    if (_pos != tokens.length || value.isNaN || value.isInfinite) return null;
    return value;
  }

  double _primary() {
    if (_pos >= tokens.length) return double.nan;
    if (tokens[_pos] == '(') {
      _pos++;
      final value = _additive();
      if (_pos < tokens.length && tokens[_pos] == ')') _pos++;
      return value;
    }
    final value = double.tryParse(tokens[_pos]);
    _pos++;
    return value ?? double.nan;
  }

  double _multiplicative() {
    var value = _primary();
    while (_pos < tokens.length &&
        (tokens[_pos] == '*' || tokens[_pos] == '/')) {
      final op = tokens[_pos];
      _pos++;
      final rhs = _primary();
      value = op == '*' ? value * rhs : value / rhs;
    }
    return value;
  }

  double _additive() {
    var value = _multiplicative();
    while (_pos < tokens.length &&
        (tokens[_pos] == '+' || tokens[_pos] == '-')) {
      final op = tokens[_pos];
      _pos++;
      final rhs = _multiplicative();
      value = op == '+' ? value + rhs : value - rhs;
    }
    return value;
  }
}

enum _Intent {
  greeting,
  howAreYou,
  thanks,
  goodbye,
  praise,
  identity,
  capabilities,
  status,
  due,
  chase,
  clientLookup,
  calendar,
  dateInfo,
  business,
  counts,
  project,
  goals,
  unknown,
}

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
