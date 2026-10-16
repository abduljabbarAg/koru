import '../models.dart';
import 'facts.dart';
import 'replies/advice.dart';

export 'facts.dart';

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

  /// The advice half, one domain per method. Kept out of this file so the
  /// classifier can sit next to the answers it dispatches to and still leave
  /// each body of advice readable on its own.
  static const _advice = BusinessAdvice();

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

    // The folded question carries the previous turn; the raw one does not. Both
    // are classified: a follow-up like "what about the VAT" has no subject of
    // its own, and the subject it borrows must not drag the answer back to the
    // previous topic when this turn names a new one.
    final intent = raw == q ? _classify(q, facts) : _classifyTurn(q, raw, facts);

    var text = switch (intent) {
      _Intent.greeting => _greeting(facts, q),
      _Intent.agree => _agree(facts, q),
      _Intent.disagree => _disagree(facts),
      _Intent.more => _more(facts, q),
      _Intent.vagueFollowUp => _vagueFollowUp(facts, q),
      _Intent.yesNoAboutRecords => _yesNoAboutRecords(facts, q),
      _Intent.howAreYou => _howAreYou(facts),
      _Intent.thanks => _thanks(facts),
      _Intent.goodbye => _goodbye(facts),
      _Intent.praise => _praise(facts),
      _Intent.frustration => _frustration(facts, q),
      _Intent.smallTalk => _smallTalk(facts, q),
      _Intent.unclear => _unclear(facts, q),
      _Intent.status => _status(facts),
      _Intent.due => _due(facts),
      _Intent.chase => _chase(facts),
      _Intent.clientLookup => _clientDetail(facts, _clientNamedIn(q, facts)!),
      _Intent.calendar => _calendar(facts),
      _Intent.dateInfo => _dateInfo(facts, q),
      _Intent.business => _business(facts),
      _Intent.counts => _counts(facts),
      _Intent.project => _projects(facts),
      _Intent.goals => _goals(facts),
      _Intent.identity => _identity(facts),
      _Intent.capabilities => _capabilities(),
      _Intent.appHelp => _appHelp(),
      // The advice half. Each of these answers with a rule, a number and a
      // sentence the user can send, and quotes their own records when the
      // records say something about the question.
      _Intent.quote => _advice.quote(facts, q),
      _Intent.rate => _advice.rate(facts, q),
      _Intent.invoiceAdvice => _advice.invoice(facts, q),
      _Intent.latePay => _advice.latePayment(facts, q),
      _Intent.vat => _advice.vat(facts, q),
      _Intent.cashflow => _advice.cashflow(facts, q),
      _Intent.deposit => _advice.deposit(facts, q),
      _Intent.retainerAdvice => _advice.retainer(facts, q),
      _Intent.scopeCreep => _advice.scopeCreep(facts, q),
      _Intent.sayNo => _advice.sayNo(facts, q),
      _Intent.negotiate => _advice.negotiate(facts, q),
      _Intent.explainCharge => _advice.explainCharge(facts, q),
      _Intent.refund => _advice.refund(facts, q),
      _Intent.cancel => _advice.cancellation(facts, q),
      _Intent.contract => _advice.contract(facts, q),
      _Intent.onboard => _advice.onboarding(facts, q),
      _Intent.timeline => _advice.timeline(facts, q),
      _Intent.workload => _advice.workload(facts, q),
      _Intent.hiring => _advice.hiring(facts, q),
      _Intent.tools => _advice.tools(facts, q),
      _Intent.messageDraft => _advice.draftMessage(facts, q),
      _Intent.unknown => _fallback(facts),
    };

    // A question with two halves gets an answer with two halves: the primary
    // intent in full, then one short note from the other domain it mentioned.
    // "What should I charge, and should I take a deposit?" is one question to
    // whoever typed it and must not be answered as one of the two.
    final extra = _secondNote(q, intent, facts);
    if (extra != null) text = '$text\n\n$extra';

    // When the question names a client, the record comes with the advice —
    // "what should I charge Bilal" wants the price talk and Bilal's figures.
    if (_namesClientWith(intent)) {
      final named = _clientNamedIn(q, facts);
      if (named != null) {
        text = '$text\n\nAbout ${named.name}: ${_clientDetail(facts, named)}';
      }
    }

    return LocalAnswer(
      text,
      usedData: _usedData(intent, facts),
      suggestCloud: intent == _Intent.unknown,
    );
  }

  /// Intents whose answer is built from the records, with the same conditions
  /// the one-by-one dispatch used to spell out — a chip claiming "from your
  /// records" on a reply that never opened them would be a small lie.
  static const _adviceIntents = <_Intent>{
    _Intent.quote, _Intent.rate, _Intent.invoiceAdvice, _Intent.latePay,
    _Intent.vat, _Intent.cashflow, _Intent.deposit, _Intent.retainerAdvice,
    _Intent.scopeCreep, _Intent.sayNo, _Intent.negotiate, _Intent.explainCharge,
    _Intent.refund, _Intent.cancel, _Intent.contract, _Intent.onboard,
    _Intent.timeline, _Intent.workload, _Intent.hiring, _Intent.tools,
    _Intent.messageDraft,
  };

  /// Advice that actually quotes the files back when there are files to quote.
  static const _adviceFromRecords = <_Intent>{
    _Intent.quote, _Intent.invoiceAdvice, _Intent.latePay, _Intent.cashflow,
    _Intent.retainerAdvice, _Intent.timeline, _Intent.workload,
    _Intent.messageDraft,
  };

  /// Intents where naming the client in the question deserves their record
  /// appended to the advice.
  static bool _namesClientWith(_Intent i) =>
      i == _Intent.quote ||
      i == _Intent.negotiate ||
      i == _Intent.explainCharge ||
      i == _Intent.contract ||
      i == _Intent.timeline;

  bool _usedData(_Intent i, LocalFacts f) => switch (i) {
        _Intent.greeting => f.hasProfile,
        _Intent.status ||
        _Intent.due ||
        _Intent.calendar ||
        _Intent.counts ||
        _Intent.more ||
        _Intent.vagueFollowUp ||
        _Intent.yesNoAboutRecords ||
        _Intent.unknown =>
          f.hasRecords,
        _Intent.chase || _Intent.business => f.clients.isNotEmpty,
        _Intent.clientLookup || _Intent.identity => true,
        _Intent.goals => f.goals.isNotEmpty,
        _Intent.project => f.projects.isNotEmpty,
        _ => _adviceFromRecords.contains(i) && f.hasRecords,
      };

  /// The second half of a multi-part question, as one short added note.
  ///
  /// Returns null unless the question genuinely carried two domains: the
  /// primary intent, plus one other. Only the pairs people actually combine
  /// are wired up, because a generic "also you asked about X" from a domain
  /// nobody asked about would be worse than silence.
  String? _secondNote(String q, _Intent primary, LocalFacts f) {
    final matched = _matchedAdvice(q);
    _Intent? second;
    for (final i in matched) {
      if (i != primary) {
        second = i;
        break;
      }
    }
    if (second == null) return null;
    return switch (second) {
      _Intent.deposit =>
        'Since you asked: take a deposit for new clients — half up front is '
            'the usual split, and it separates the serious from the curious.',
      _Intent.vat =>
        'Since you asked about tax: move about a fifth of everything that '
            'lands into a separate account the day it lands, and it stops '
            'being a crisis in March.',
      _Intent.invoiceAdvice =>
        'Since you asked about invoicing: put the due date on the invoice '
            'itself and diarise the follow-up for the morning after it falls '
            'due.',
      _Intent.contract =>
        'Since you asked about paperwork: one email listing scope, price, '
            'timeline and terms, replied to with "confirmed", does most of '
            'the job a contract would.',
      _Intent.latePay =>
        'Since you asked about getting paid: the nudge that works is short, '
            'friendly and asks for a date rather than apologising for '
            'asking.',
      _Intent.cashflow =>
        'Since you asked about cash flow: keep two months of basic outgoings '
            'aside and refill it whenever a large payment lands.',
      _Intent.scopeCreep =>
        'Since you asked about extras: price every one as a change order, '
            'even the small ones — unpriced extras are how the edges go '
            'soft.',
      _Intent.retainerAdvice =>
        'Since you asked about retainers: define the monthly unit in '
            'writing, expire unused hours at month end, and review the '
            'price every six months.',
      _Intent.timeline =>
        'Since you asked about dates: estimate from the day count, add a '
            'buffer you do not mention, and send dates in halves.',
      _Intent.rate =>
        'Since you asked about rates: raise new-client prices first — it is '
            'the cheapest raise you will ever give yourself.',
      _Intent.sayNo =>
        'Since you said no: keep it warm, keep it short, and send it in '
            'reply to their thread rather than as silence.',
      _Intent.messageDraft =>
        'And if you want the actual words, say "draft a chase message" (or '
            'price, deposit, decline) and I will write the whole thing for '
            'you to copy.',
      _ => null,
    };
  }

  /// Every advice domain this question mentions, most specific first.
  List<_Intent> _matchedAdvice(String q) {
    bool has(List<String> phrases) => phrases.any(q.contains);
    bool hasWord(List<String> words) =>
        words.any((w) => RegExp('\\b${RegExp.escape(w)}\\b').hasMatch(q));
    final out = <_Intent>[];
    void add(bool matches, _Intent i) {
      if (matches) out.add(i);
    }

    add(has(BusinessAdvice.draftPhrases), _Intent.messageDraft);
    add(has(BusinessAdvice.quotePhrases) || hasWord(BusinessAdvice.quoteWords),
        _Intent.quote);
    add(has(BusinessAdvice.ratePhrases) || hasWord(BusinessAdvice.rateWords),
        _Intent.rate);
    add(has(BusinessAdvice.invoicePhrases), _Intent.invoiceAdvice);
    add(has(BusinessAdvice.latePhrases), _Intent.latePay);
    add(has(BusinessAdvice.vatPhrases) || hasWord(BusinessAdvice.vatWords),
        _Intent.vat);
    add(has(BusinessAdvice.cashflowPhrases), _Intent.cashflow);
    add(has(BusinessAdvice.depositPhrases) ||
        hasWord(BusinessAdvice.depositWords), _Intent.deposit);
    add(has(BusinessAdvice.retainerPhrases), _Intent.retainerAdvice);
    add(has(BusinessAdvice.scopePhrases), _Intent.scopeCreep);
    add(has(BusinessAdvice.noPhrases), _Intent.sayNo);
    add(has(BusinessAdvice.negotiatePhrases), _Intent.negotiate);
    add(has(BusinessAdvice.explainPhrases), _Intent.explainCharge);
    add(has(BusinessAdvice.refundPhrases) || hasWord(BusinessAdvice.refundWords),
        _Intent.refund);
    add(has(BusinessAdvice.cancelPhrases), _Intent.cancel);
    add(has(BusinessAdvice.contractPhrases) ||
        hasWord(BusinessAdvice.contractWords), _Intent.contract);
    add(has(BusinessAdvice.onboardPhrases), _Intent.onboard);
    add(has(BusinessAdvice.timelinePhrases), _Intent.timeline);
    add(has(BusinessAdvice.workloadPhrases), _Intent.workload);
    add(has(BusinessAdvice.hiringPhrases), _Intent.hiring);
    add(has(BusinessAdvice.toolsPhrases), _Intent.tools);
    return out;
  }

  /// Classifies a turn that has a previous question folded into it.
  ///
  /// The folded form decides everything except one thing: if this turn alone
  /// raises a new piece of advice — "what about the VAT" — that is what was
  /// asked, not the subject borrowed from the turn before.
  _Intent _classifyTurn(String folded, String fresh, LocalFacts f) {
    final primary = _classify(folded, f);
    final alone = _classify(fresh, f);
    if (alone != primary && _adviceIntents.contains(alone)) return alone;
    return primary;
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
      'Glad it helped. I will keep the figures straight while you get on.',
    ], who.isEmpty ? 'thanks' : who);
  }

  String _goodbye(LocalFacts f) => _pick([
        'See you. Everything stays on this phone until you are back.',
        'Goodbye. I will be here, and nothing leaves the device.',
        'Later. Your invoices and I will be waiting.',
      ], f.nickname);

  String _praise(LocalFacts f) => _pick([
        'Thank you. I will keep watching the invoices.',
        'That is kind. Ask me again when the money comes in.',
        'Cheers. Flattery does not get anyone paid, but I will take it.',
      ], f.nickname);

  /// Anger at something — the app, a client, the day.
  ///
  /// Acknowledged, never matched in tone. The useful move is to find out which
  /// of the three it is and hand back the one thing that would help, so a
  /// frustrated person gets a next step instead of a mirror.
  String _frustration(LocalFacts f, String q) {
    final isClient = f.clients.any((c) => c.name.toLowerCase().split(' ')
        .any(q.contains));
    final late = f.clients.where((c) => f.balanceOf(c) > 0).toList()
      ..sort((a, b) => f.balanceOf(b).compareTo(f.balanceOf(a)));
    if (isClient) {
      return 'That sounds properly annoying. If it is a client being '
          'difficult, tell me which one and we will deal with it '
          'concretely — what they owe, what has been said, and what the '
          'next message should be.';
    }
    if (late.isNotEmpty) {
      return 'Fair enough — that is worth being annoyed about. On file '
          '${late.first.name} is holding ${_num(f.balanceOf(late.first))}, '
          'which is probably the largest single annoyance available to you. '
          'Say "chase" and I will draft the message; or tell me what else '
          'went wrong and we will take it from the top.';
    }
    return _pick([
      'Understood, and I will not take it personally. Tell me what went '
          'wrong — if it is the app, say what you were trying to do; if it '
          'is a client or a job, name it and we will work out the next '
          'move together.',
      'Right. Deep breath, then: what actually went wrong? Half of these '
          'have a five-minute fix once they are said out loud, and I am '
          'good at the boring half of that.',
      'Noted, without the defensiveness. If it is about this app, say what '
          'you expected to happen; if it is about the work, say who it is '
          'and I will pull up whatever we know about them.',
    ], q);
  }

  /// Chat that is not a business question: weather, jokes, boredom.
  ///
  /// Answered as itself rather than bounced back with a menu, then steered —
  /// gently, once — towards the thing on this phone that would actually be
  /// useful. Redirecting everything to features is how an assistant sounds
  /// like a settings screen.
  String _smallTalk(LocalFacts f, String q) {
    if (RegExp(r'weather|rain|sunny|cold outside').hasMatch(q)) {
      return 'No idea — I live in this phone and the curtains are drawn. '
          'What I can see is your diary: '
          '${f.events.isEmpty ? 'nothing booked in the next week.' : '${f.events.length} thing${f.events.length == 1 ? '' : 's'} booked in, next one being ${f.events.first.title}.'}';
    }
    if (RegExp(r'joke|laugh|funny|riddle').hasMatch(q)) {
      return _pick([
        'A client who pays on time. ... Sorry, that is the only joke in '
            'this business and you have heard it.',
        'What is the difference between a freelancer and a large pizza? The '
            'pizza can feed a family. Ask me something painful like "who '
            'owes me money" and we will both feel better.',
      ], q);
    }
    if (RegExp(r'bored|boring|nothing to do|procrastinat').hasMatch(q)) {
      if (f.clients.where((c) => f.balanceOf(c) > 0).isNotEmpty) {
        return 'Bored is fixable in one move: someone owes you money. Ask '
            '"who should I chase" and you will have a job for the next '
            'quarter of an hour.';
      }
      return 'Then let us spend five minutes on something that pays later: '
          'tell me about a project you want, and I will help you price it — '
          '"how much should I charge for a logo" is a fine place to start.';
    }
    return _pick([
      'I am real enough to know your figures, which is more than most '
          'assistants manage. The weather and my inner life are above my '
          'pay grade, though — ask me about your clients, your money or '
          'your deadlines and I will be genuinely useful.',
      'Straight answer: I am a program on your phone, and quite happy '
          'being one. What I am good at is the boring half of running a '
          'business — who owes you what, what is due, what to charge next '
          '— so point me at any of that.',
      'Ha. Ask me whether you can afford to say yes to the next job and I '
          'will give you a proper answer; ask me about my dreams and you '
          'will get silence. I know which one pays.',
    ], q);
  }

  /// Too little to go on. Never a dead end: the question comes back with the
  /// options that fit the records, so a shrug becomes a menu.
  String _unclear(LocalFacts f, String q) {
    final options = <String>[
      if (f.clients.isNotEmpty && f.clients.any((c) => f.balanceOf(c) > 0))
        'who owes you money, and who to chase first',
      if (f.clients.isNotEmpty) 'how ${f.clients.first.name} is doing',
      if (f.deadlines.isNotEmpty || f.events.isNotEmpty) 'what is due today',
      if (f.clients.isEmpty) 'adding your first client',
      'advice on quoting, deposits or getting paid',
      'a sum, like "what is 15% of 2000"',
    ];
    final list = options.take(3).map((o) => '"$o"').join(', ');
    final said = q.trim();
    return said.isEmpty
        ? 'I did not get that. Try me on: $list?'
        : 'I did not quite catch "$said". Did you mean one of these: $list?';
  }

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
      'goodbye', 'good bye', 'bye bye', 'see you', 'see ya', 'catch you later',
      'good night', 'goodnight', 'talk later', 'gotta go', 'got to go',
      'bye for now', 'ttyl', 'night night',
    ]) ||
        RegExp(r'\bbye\b').hasMatch(q)) {
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
    // Frustration, before anything else can claim it. Someone typing "this is
    // rubbish" does not want a business report; they want it acknowledged and
    // a next step offered.
    if (has(const [
      'wtf', 'the hell', 'damn', 'dammit', 'damn it', 'useless', 'rubbish',
      'hate this', 'hate you', 'stupid', 'waste of time', 'so annoying',
      'annoying', 'ugh', 'this sucks', 'not helpful', 'shut up',
      'are you stupid', 'bloody hell', "for god's sake", 'for gods sake',
      'ffs', 'pissed off', 'fed up', 'sick of this', 'what a joke',
      'ridiculous', 'doesnt work', "doesn't work", 'not working', 'broken',
      'useless app', 'what is wrong with', 'whats wrong with',
    ])) {
      return _Intent.frustration;
    }
    // Word boundaries, not substring: bare "hi" matches inside "this", which
    // would turn "is this working" into a greeting.
    if (RegExp(r'\b(hello|hi|hey|yo|salam|assalam)\b').hasMatch(q) ||
        has(const ['good morning', 'good evening', 'good afternoon'])) {
      return _Intent.greeting;
    }

    // Short replies to whatever Koru just said.
    //
    // Matched against the whole sentence being almost nothing, because "yes"
    // after an offer means something and "yes, and add a client called Bilal"
    // does not. Stripped of punctuation first so "Yes!" and "yes." land here too.
    final bare = q.replaceAll(RegExp(r'[^a-z\s]'), '').trim();
    if (RegExp(r'^(yes|yeah|yep|yup|sure|ok|okay|alright|right|will do|'
                r'sounds good|please do|go ahead|fine|cool|great|nice|'
                r'perfect|exactly|indeed|of course|absolutely|'
                r'yep i do|thats right)$').hasMatch(bare)) {
      return _Intent.agree;
    }
    // "Don't invoice yet" is longer than this and reaches the advice half with
    // its negation intact; a bare "don't" is just a no.
    if (RegExp(r'^(no|nope|nah|not now|maybe later|never mind|nevermind|'
                r'cancel|stop|dont|do not|leave it|not today|no thanks|'
                r'ilpass|pass on it)$').hasMatch(bare)) {
      return _Intent.disagree;
    }
    if (RegExp(r'^(and then|what else|anything else|what now|what next|'
                r'what should i do|where do i start|anything|go on|keep going|'
                r'what do i do|so what do i do|im stuck|now what)$')
        .hasMatch(bare)) {
      return _Intent.more;
    }

    // "and him", "what about her", "the other one". A pronoun with no subject,
    // which is most of how people talk to something that already knows them.
    if (RegExp(r'^(and )?(him|her|them|that one|the other one|the other|'
                r'that client|that person)$').hasMatch(bare)) {
      return _Intent.vagueFollowUp;
    }

    // The advice half, before the record queries: quoting, invoicing, VAT,
    // scope, contracts and the rest all mention words the generic intents
    // also claim ("rate", "charge", "deposit", "late"), and a person asking
    // "should I take a deposit" must not get a pipeline report. It also comes
    // before the yes/no half, because "they haven't paid me, what do I do?"
    // contains an auxiliary and the word paid and is a plea, not a yes/no.
    // The cue lists live next to the replies in replies/advice.dart.
    final advice = _matchedAdvice(q);
    if (advice.isNotEmpty) return advice.first;

    // Yes/no questions about the records. Answerable, and refusing them is what
    // makes an assistant feel like a search box.
    if (RegExp(r'\b(is|are|was|were|does|do|did|has|have|am)\b').hasMatch(q) &&
        (q.contains('owe') || q.contains('paid') || q.contains('late') ||
         q.contains('behind') || q.contains('up to date') ||
         q.contains('still waiting') || q.contains('received'))) {
      return _Intent.yesNoAboutRecords;
    }

    if (has(const ['who are you', 'what are you', 'your name', 'about you',
        'who is koru', 'what is koru'])) {
      return _Intent.identity;
    }
    if (has(const [
      'what can you do', 'help me with', 'how do i use', 'what do you know',
      'commands', 'what should i ask', 'what questions', 'menu',
      'help me', 'how does this app', 'how does this work', 'app features',
      'what features', 'what is this app',
    ])) {
      return _Intent.capabilities;
    }
    // Operating the app rather than asking what it does: adding, editing,
    // exporting, changing engines. A person who asks "how do I add a client"
    // wants the button, not the philosophy.
    if (has(const [
      'how do i add', 'how to add', 'how do i record', 'how do i edit',
      'how do i delete', 'how do i change', 'where do i find',
      'how do i export', 'export my', 'back up', 'backup', 'import my',
      'notification', 'engine', 'settings', 'how do i turn',
      'how do i set', 'where is the', 'how do i get',
    ])) {
      return _Intent.appHelp;
    }

    // Chat that is not about the records: weather, jokes, boredom, the
    // occasional probe at whether there is anyone in there.
    if (has(const [
      'whats the weather', 'what is the weather', 'the weather',
      'weather forecast', 'tell me a joke', 'make me laugh',
      'are you real', 'are you human', 'are you a bot', 'do you dream',
      'i am bored', 'im bored', 'bored', 'what should i eat', 'love you',
      'miss you', 'how old are you', 'your favourite', 'your favorite',
      'keep me company',
    ])) {
      return _Intent.smallTalk;
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
    // "should I hold off on chasing them?" is a question about whether to
    // chase, not a request for the list, and the negation reaches the advice
    // half intact.
    final negatedChase =
        RegExp(r"\b(hold off|hold it|wait|stop|dont|don't|do not|not|pause|"
                r'leave it)\b')
            .hasMatch(q) &&
        RegExp(r'\b(chase|chasing|remind|nudge)\b').hasMatch(q);
    if (!negatedChase &&
        has(const [
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

    // Too little to go on: a lone "huh", a question mark, something typed and
    // abandoned. A clarifying question beats a fallback nobody reads.
    if (bare.replaceAll(' ', '').length <= 4) return _Intent.unclear;
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
      'I also give the business talk itself, no model needed: quoting and '
      'rate-setting, deposits, payment terms, VAT and tax, scope creep, '
      'contracts, negotiation, saying no, cash flow, workload. Ask me '
      '"should I take a deposit?" or "how do I chase a late payer" and you '
      'get the rule, the number and a sentence you can send.\n'
      '\n'
      'I can also record things for you. Say "add client Bilal for 2000", '
      '"Bilal paid 500", or "schedule a call with Bilal tomorrow at 3pm" and '
      'I will show you exactly what I understood before anything is saved.\n'
      '\n'
      'Anything about faith, health, medicine or law goes to a stronger model '
      'instead, and anything urgent goes to a person.';

  /// Operating the app, rather than describing it: the buttons, the phrasing,
  /// where things live. Distinct from [_capabilities], which is the tour.
  String _appHelp() => 'The working parts:\n'
      '\n'
      '  - add a client: "add client Bilal for 2000"\n'
      '  - money in: "Bilal paid 500" — partial payments count, the balance '
      'works itself out\n'
      '  - a deadline: "send invoice due Friday"\n'
      '  - an appointment: "schedule a call with Bilal tomorrow at 3pm"\n'
      '  - a project: add it in the Projects tab; progress and notes live '
      'there\n'
      '  - who owes what: the Business tab, or just ask me here\n'
      '  - profile, currency, backup and any cloud key: Settings\n'
      '\n'
      'Every instruction comes back as a card to approve first, so nothing '
      'saves by accident. And since everything lives on this phone, an '
      'occasional export from Settings is the one chore worth doing. Ask '
      '"what can you do?" for the short tour instead.';

  /// A yes. There is never a question on screen when this is said, so the
  /// honest answer is to take it as "go on" and offer the next useful thing
  /// rather than to pretend something was asked.
  String _agree(LocalFacts f, String q) =>
      _pick([
        'Good.',
        'Will do.',
        'Okay.',
        'Right.',
        'Done when you say so.',
      ], q) +
      (f.hasRecords ? ' ${_nextMove(f)}' : _capabilities());

  /// The single most useful thing on the records right now, in one sentence.
  String _nextMove(LocalFacts f) {
    final late = f.clients.where((c) => f.balanceOf(c) > 0).toList()
      ..sort((a, b) => f.balanceOf(b).compareTo(f.balanceOf(a)));
    if (late.isNotEmpty) {
      return 'Biggest lever right now: ${late.first.name} and '
          '${_num(f.balanceOf(late.first))} — say "chase" and I will draft '
          'the message.';
    }
    if (f.deadlines.isNotEmpty) {
      return 'What would you like next — what is due, or a status check?';
    }
    if (f.clients.any((c) => c.status == 'lead')) {
      return 'There is a lead still waiting on a number: say "quote" and I '
          'will walk you through pricing it.';
    }
    return 'What would you like to do next?';
  }

  /// A no. Taken at face value and left alone.
  String _disagree(LocalFacts f) => _pick([
        'Okay, leaving it there.',
        'No problem.',
        'Fair enough.',
        'Understood.',
        'Noted — nothing sent, nothing saved.',
      ], 'no');

  /// "anything else", "what should I do". Offers the thing that is actually
  /// true right now rather than a menu, because a menu is a form and the
  /// person is talking. The priority is deliberate: late money first, because
  /// it is the only item here that is costing something by waiting.
  String _more(LocalFacts f, String q) {
    final lines = <String>[];
    final late = f.clients.where((c) => f.balanceOf(c) > 0).toList()
      ..sort((a, b) => f.balanceOf(b).compareTo(f.balanceOf(a)));
    if (late.isNotEmpty) {
      lines.add('${late.first.name} is still holding '
          '${_num(f.balanceOf(late.first))}, which is the largest '
          'outstanding.');
      lines.add('Next move: say "chase" and I will draft the follow-up, or '
          'ask "who should I chase" for the whole list in order.');
    }
    if (f.deadlines.isNotEmpty) {
      lines.add('You have ${f.deadlines.length} deadline'
          '${f.deadlines.length == 1 ? '' : 's'} on file'
          '${f.deadlines.where((d) => !d.done).length == f.deadlines.length
              ? ', none of them done yet'
              : ''}.');
    }
    if (f.events.isNotEmpty) {
      lines.add('Next up: ${f.events.first.title}.');
    }
    final leads = f.clients.where((c) => c.status == 'lead').toList();
    if (leads.isNotEmpty) {
      lines.add('${leads.first.name} is still a lead with no number against '
          'it — a quote is the thing that moves that.');
    }
    if (lines.isEmpty) {
      if (f.clients.isEmpty) {
        return 'Nothing is on file yet, so there is nothing waiting — which '
            'is the good version of an empty afternoon. Say "add client '
            'Bilal for 2000" and I start tracking what they owe, or ask me '
            '"should I take a deposit?" for something useful in the '
            'meantime.';
      }
      return 'Nothing is waiting on you that I can see: nobody owes you, and '
          'no deadline is close. That is the quiet kind of good news. Ask me '
          'for a status check, or get ahead of the next job — "how much '
          'should I charge for a website?" is a fine use of five minutes.';
    }
    return lines.take(4).join('\n');
  }

  /// "and him?" with no name in it.
  ///
  /// The previous question is already folded into [q] by the caller, so if a
  /// client is named anywhere it is answered normally. This is only reached when
  /// nothing is named, and the useful thing to do is guess the subject from the
  /// records and ask, rather than shrugging.
  String _vagueFollowUp(LocalFacts f, String q) {
    if (f.clients.isEmpty) {
      return 'Who did you mean? I do not have any clients on file yet.';
    }
    if (f.clients.length == 1) {
      return _clientDetail(f, f.clients.first);
    }
    final named = _clientNamedIn(q, f);
    if (named != null) return _clientDetail(f, named);
    final late = f.clients.where((c) => f.balanceOf(c) > 0).toList()
      ..sort((a, b) => f.balanceOf(b).compareTo(f.balanceOf(a)));
    if (late.isNotEmpty && late.length == 1) {
      return _clientDetail(f, late.first);
    }
    final names = f.clients.take(4).map((c) => c.name).join(', ');
    return 'Who did you mean? I have ${f.clients.length} clients: $names.';
  }

  /// "is Bilal late?", "did I get paid this month?"
  ///
  /// Answered yes or no, with the number attached, because a bare yes to "am I
  /// behind" is not useful and a bare no is worse.
  String _yesNoAboutRecords(LocalFacts f, String q) {
    final named = _clientNamedIn(q, f);
    if (named != null) {
      final outstanding = f.balanceOf(named);
      if (outstanding > 0) {
        final invoiced = named.invoicedOn;
        return '${named.name} has not paid in full. ${_num(outstanding)} '
            'outstanding${invoiced == null ? '' : ', invoiced on $invoiced'}.';
      }
      return '${named.name} is settled. Nothing outstanding.';
    }

    final owing = f.clients.where((c) => f.balanceOf(c) > 0).toList();
    if (owing.isEmpty) {
      return f.clients.isEmpty
          ? 'I do not have any clients on file yet, so there is nobody owing you.'
          : 'Nobody owes you anything. Every client on file is settled.';
    }
    final total = owing.fold<double>(0, (sum, c) => sum + f.balanceOf(c));
    if (q.contains('paid') || q.contains('received')) {
      return 'Not everything. ${owing.length} of your ${f.clients.length} '
          'clients still owe money, ${_num(total)} in total. '
          '${owing.map((c) => c.name).take(3).join(', ')} are the ones.';
    }
    return 'Yes, you are behind on ${owing.length} '
        '${owing.length == 1 ? 'client' : 'clients'}, ${_num(total)} in total. '
        'Say "chase" and I will draft the follow-ups.';
  }

  /// The honest miss: nothing matched, and no part of it is guessed at.
  ///
  /// Still a dead end only on the question — never on the conversation. It
  /// names what this half of the assistant is good at, offers the three most
  /// relevant next questions from the records, and points at the cloud key for
  /// the rest, so the reply always contains somewhere to go.
  String _fallback(LocalFacts f) {
    final suggestions = <String>[
      if (f.clients.isNotEmpty) '"who owes me money?"',
      if (f.deadlines.isNotEmpty || f.events.isNotEmpty) '"what is due today?"',
      if (f.projects.isNotEmpty) '"what am I working on?"',
      if (f.clients.where((c) => c.status == 'lead').isNotEmpty)
        '"how much should I charge?"',
      '"what can you do?"',
    ];
    final tail = suggestions.take(3).join(', ');
    const advice = 'I do answer the business talk itself, though — quoting, '
        'deposits, payment terms, VAT, scope creep, contracts, chasing '
        'money. Try "should I take a deposit?"';
    if (!f.hasRecords) {
      return 'I could not answer that one from what is on this phone, and I '
          'would rather say so than improvise. On device I cover your '
          'clients, money, calendar and deadlines, plus sums like "what is '
          '15% of 2000". Try one of: $tail\n\n$advice\n\n'
          'For anything outside that, add a cloud key in Settings and the '
          'question goes upstream with a pseudonymous summary.';
    }
    return 'I could not match that to anything I keep locally, so I am not '
        'going to invent an answer about your business. What I do have: '
        '$tail\n\n$advice\n\nFor the rest, add a cloud key in Settings and '
        'it goes upstream with a pseudonymous summary.';
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
  // Talking and turn-taking.
  greeting,
  agree,
  disagree,
  more,
  vagueFollowUp,
  yesNoAboutRecords,
  howAreYou,
  thanks,
  goodbye,
  praise,
  frustration,
  smallTalk,
  unclear,
  // From the records.
  identity,
  capabilities,
  appHelp,
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
  // The advice half: running the business rather than reading the database.
  quote,
  rate,
  invoiceAdvice,
  latePay,
  vat,
  cashflow,
  deposit,
  retainerAdvice,
  scopeCreep,
  sayNo,
  negotiate,
  explainCharge,
  refund,
  cancel,
  contract,
  onboard,
  timeline,
  workload,
  hiring,
  tools,
  messageDraft,
  // Nothing matched.
  unknown,
}

/// Case folds a question without importing the routing layer, so this file can
/// be unit tested on its own.
class RoutingDecisionNormaliser {
  const RoutingDecisionNormaliser._();

  static String fold(String input) =>
      input.toLowerCase().replaceAll(RegExp(r"[^a-z0-9' ]"), ' ');
}
