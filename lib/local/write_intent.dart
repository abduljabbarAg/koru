// Recognising a write the user asked for in plain language.
//
// This exists so "add client Bilal for 2000" works without letting a 0.5B model
// anywhere near the write path.
//
// The alternative was tool calling: ask the model to emit a JSON call and run
// it. That was rejected for two reasons, and only one of them is about privacy.
// Privacy was never the problem, because writing to a local database needs no
// network and no token. The problem is that a 0.5B model at 4 tok/s emits
// malformed JSON and picks the wrong argument often enough to corrupt a ledger,
// and someone who trusts their own invoice figures should not get that failure
// mode. A parser here is right every time, costs nothing, and is testable
// without a device.
//
// The parser never executes anything. It returns what it believes was asked for
// and the caller shows a card the user has to approve, so a wrong guess is an
// inconvenience rather than a corrupted record.
//
// It is deliberately reluctant. "How much does Bilal owe" is not a request to
// record a payment, and a parser that fired on it would be worse than none.

/// Which kind of write a sentence is asking for.
///
/// Resolved by which cue appears earliest, not by trying one kind at a time and
/// taking the first that matches.
enum _Kind { deadline, event, payment, client, edit, delete, none }

/// What the user appears to have asked to record.
sealed class WriteIntent {
  const WriteIntent();

  /// One line saying what approving this will do, for the confirmation card.
  String get summary;
}

/// A new client, with whatever else the sentence said about them.
class AddClientIntent extends WriteIntent {
  const AddClientIntent({required this.name, this.amount, this.due});

  final String name;

  /// What they have been invoiced, if the sentence said.
  final double? amount;

  /// ISO date, if the sentence said.
  final String? due;

  @override
  String get summary => amount == null
      ? 'Add a client called $name'
      : 'Add $name, invoiced ${_plain(amount!)}';
}

/// Money arriving from someone already on file.
class RecordPaymentIntent extends WriteIntent {
  const RecordPaymentIntent({required this.clientName, this.amount, this.note});

  /// As the user typed it. The caller resolves it against the real clients and
  /// refuses if it is missing or ambiguous, so this is a proposal, not a link.
  final String clientName;
  final double? amount;
  final String? note;

  @override
  String get summary => amount == null
      ? 'Record a payment from $clientName'
      : 'Record ${_plain(amount!)} from $clientName';
}

/// Something dated that has to happen.
class AddDeadlineIntent extends WriteIntent {
  const AddDeadlineIntent({required this.title, this.due});

  final String title;
  final String? due;

  @override
  String get summary =>
      due == null ? 'Add a deadline: $title' : 'Add "$title", due $due';
}

/// A calendar entry: a moment in time, not just a date.
///
/// Separate from a deadline because the shapes are different. "Hand over the
/// site by Friday" is a deadline; "call with Bilal at 3pm" is an event, and
/// squeezing times into the deadlines table would have made both answers worse.
class AddEventIntent extends WriteIntent {
  const AddEventIntent({
    required this.title,
    required this.date,
    this.time,
    this.location,
  });

  final String title;

  /// ISO date, or null when the sentence had no date at all. The card still
  /// works: it proposes today, which is what "schedule a call with Bilal" with
  /// no date almost always means.
  final String? date;

  /// "HH:mm" when the sentence carried a time, null for an all-day entry.
  final String? time;

  final String? location;

  @override
  String get summary {
    final parts = <String>['Add "$title" to your calendar'];
    final t = time;
    parts.add(t == null ? (date ?? 'today') : '$date at $t');
    if (location != null) parts.add('at $location');
    return parts.join(', ');
  }
}

String _plain(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

/// A change to a client already on file.
///
/// Every field is optional and null means "leave it alone", which is what makes
/// "bilal now owes 3000" safe: the name and amount change and nothing else does.
/// A null cannot mean "clear it" on purpose. Clearing a field is rare enough and
/// destructive enough that it should be a deliberate action in the app rather
/// than something a sentence can do by accident.
class EditClientIntent extends WriteIntent {
  const EditClientIntent({
    required this.clientName,
    this.amount,
    this.due,
    this.status,
  });

  /// Who to change, as typed. Resolved against the real clients later.
  final String clientName;
  final double? amount;
  final String? due;
  final String? status;

  bool get changesAnything => amount != null || due != null || status != null;

  @override
  String get summary {
    final parts = <String>[];
    if (amount != null) parts.add('amount ${amount!.toStringAsFixed(0)}');
    if (due != null) parts.add('due $due');
    if (status != null) parts.add('status $status');
    return 'Change ${parts.isEmpty ? 'nothing' : parts.join(', ')}';
  }
}

/// Removes a client and everything recorded against them.
class DeleteClientIntent extends WriteIntent {
  const DeleteClientIntent({required this.clientName});

  final String clientName;

  @override
  String get summary => 'Delete $clientName';
}

/// A write that was asked for but is missing the one thing it needs.
///
/// "add an entry" is an instruction to record something. It carries no name, so
/// there is nothing to write yet, but it is emphatically not a question for the
/// model. Falling through is what let the model answer "I have added it": it had
/// a sentence it could not act on and no way to say so, so it invented a
/// result. Answering here instead means the user gets the one question that
/// unblocks them.
class IncompleteWriteIntent extends WriteIntent {
  const IncompleteWriteIntent({required this.kind, required this.askedFor});

  /// What they were trying to add: a client, a payment or a deadline.
  final WriteKind kind;

  /// The part they gave, kept so the follow up can quote it back.
  final String askedFor;

  /// What to ask, since the answer is not a question.
  String get question => switch (kind) {
        WriteKind.client =>
          'Who should I add? Give me a name, like "add client Bilal for 2000".',
        WriteKind.payment =>
          'Which client paid, and how much? Like "Bilal paid 500".',
        WriteKind.deadline =>
          'What is the deadline for? Like "Bilal due Friday".',
      };

  /// Never reaches a card, but the getter is part of the sealed contract.
  @override
  String get summary => question;

  @override
  String toString() => 'IncompleteWriteIntent(${kind.name}, "$askedFor")';
}

/// The three kinds of write the parser recognises.
enum WriteKind { client, payment, deadline }

/// Turns a sentence into a [WriteIntent], or null when it is not asking for one.
///
/// Pure and synchronous, so the whole grammar is testable without a database, a
/// widget tree, or a model.
class WriteIntentParser {
  const WriteIntentParser();

  /// Phrases that end a name. Without these a name runs to the end of the
  /// sentence and "Bilal for the website" becomes a client called "Bilal for
  /// the website".
  static const _nameStops = [
    ' as ',
    ' for ',
    ' with ',
    ' worth ',
    ' invoiced ',
    ' needing ',
    ' who ',
    ' that ',
    ' due ',
    ' on ',
    ' at ',
    ' paid ',
    ' owes ',
  ];

  /// Cue phrases that introduce each kind of write. Matched on word boundaries
  /// rather than padded with spaces, so a sentence that starts with the verb
  /// counts and "add clientXyz" does not.
  static const _clientCues = [
    'add a new client',
    'add new client',
    'add a client',
    'add client',
    'new client',
    'log a client',
    'log client',
    'create a client',
    'create client',
    'create a new client',
    'create new client',
    'create a customer',
    'create customer',
    'create a new customer',
    'create new customer',
    'make a new client',
    'make new client',
    'make a client',
    'register a client',
    'register a customer',
    'add a customer',
    'add customer',
    'new customer',
    'add a new customer',
    'add new customer',
    // "entry", "record" and "contact" are how people actually say this. Without
    // them, "add an entry" matched nothing, fell through to the model, and the
    // model then said it had done it. It cannot have: it emits text and nothing
    // else.
    'new entry',
    'add an entry',
    'add entry',
    'create an entry',
    'create entry',
    'add a record',
    'new record',
    'add a contact',
    'new contact',
    'log an entry',
  ];

  /// Edits and deletes are separate kinds rather than variants of adding,
  /// because "change the amount on bilal" must never be read as adding a second
  /// client, and a delete must never be something a loosened parser produces.
  static const _editCues = [
    'change client',
    'change the client',
    'change the amount on',
    'update client',
    'update the client',
    'edit client',
    'edit the client',
    'set client',
    'client now owes',
    'client now pays',
    'client is now',
    'client is worth',
    'now owes',
    'now pays',
    'raise the amount',
    'lower the amount',
  ];

  static const _deleteCues = [
    'delete client',
    'delete the client',
    'remove client',
    'remove the client',
  ];

  static const _paymentCues = [
    'mark as paid',
    'mark paid',
    'record a payment',
    'record payment',
    'log a payment',
    'log payment',
  ];

  static const _deadlineCues = [
    'add a deadline to',
    'add a deadline',
    'add deadline to',
    'add deadline',
    'set a deadline',
    'set deadline',
    'new deadline',
    'add a reminder to',
    'add a reminder',
    'add reminder',
    'remind me to',
    'add a task',
    'add task',
  ];

  /// Calendar cues. Kept after the deadline cues in the list only for
  /// readability: [parse] takes whichever cue appears earliest in the sentence,
  /// so list order decides nothing except ties at the same position.
  static const _eventCues = [
    'add to my calendar',
    'put in my calendar',
    'put it in my calendar',
    'in my calendar',
    'calendar entry',
    'calendar reminder',
    'add a calendar entry',
    'add calendar entry',
    'add an event',
    'add a calendar reminder',
    'add event',
    'new calendar entry',
    'schedule a meeting',
    'schedule a call',
    'schedule an appointment',
    'schedule a',
    'schedule an',
    'schedule a session',
    'schedule meeting',
    'schedule call',
    'schedule appointment',
    'schedule the',
    'set up a meeting',
    'set up a call',
    'set up an appointment',
    'set up a session',
    'book a meeting',
    'book a call',
    'book an appointment',
    'book a session',
    'book a table',
    'book the',
    'book a',
    'make an appointment',
    'add an appointment',
    'add a meeting',
    'add a call',
    'add meeting',
    'fix a meeting',
    'fix a call',
    'organise a meeting',
    'organize a meeting',
  ];

  /// Words that make a sentence a question rather than an instruction.
  static const _interrogatives = [
    'how much', 'how many', 'how long', 'what', 'when', 'where', 'who ',
    'why', 'did ', 'does ', 'do i', 'is ', 'are ', 'was ', 'were ', 'have i',
    'should i', 'can i', 'could i', 'am i', 'which ',
  ];

  static final _number = RegExp(r'(\d[\d,]*(?:\.\d+)?)');
  static final _isoDate = RegExp(r'\b(\d{4}-\d{2}-\d{2})\b');
  static final _inDays = RegExp(r'\bin (\d+) days?\b');

  /// A clock time, in either 12-hour or 24-hour form.
  ///
  /// A bare number is never a time: "meeting with 3 clients" must not become a
  /// 3am appointment. It has to be "at 3pm", "at 3:30 pm", "at 15:00" or the
  /// same without "at", and the am/pm or the colon is what says so.
  static final _timeRe = RegExp(
    r'\b(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b'
    r'|\bat\s+(\d{1,2}):(\d{2})\b',
  );

  static const _weekdays = <String, int>{
    'monday': 1, 'tuesday': 2, 'wednesday': 3, 'thursday': 4,
    'friday': 5, 'saturday': 6, 'sunday': 7,
  };

  /// Parses [input], or returns null when nothing in it asks for a write.
  WriteIntent? parse(String input) {
    // Checked before normalisation, which would turn the mark into a space.
    if (input.contains('?')) return null;

    final clean = input
        .replaceAll(RegExp(r'[^\w\s.,\-:/]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (clean.isEmpty) return null;

    // Comparisons happen on a lower case copy while slicing uses the original,
    // so a name keeps its capitals on the confirmation card. \w is ASCII in
    // Dart, so both strings stay the same length and the indices line up.
    final lower = clean.toLowerCase();

    // A question is not an instruction, checked before anything else so
    // "how much did bilal pay" cannot read as a payment arriving.
    if (_interrogatives.any(lower.contains)) return null;

    // Earliest cue wins, across all three kinds at once.
    //
    // This used to try deadlines, then payments, then clients, in that fixed
    // order, which meant a sentence carrying more than one cue was always
    // classified as whichever kind happened to be checked first. "create new
    // client Primedose" contains no payment cue and was fine, but anything
    // mentioning a payment and a client together became a payment, and the user
    // was told a client they had just asked to create could not be found.
    //
    // The verb position is the signal: whichever intent's cue appears earliest
    // in the sentence is the one being asked for.
    final kind = _kindFor(lower);
    switch (kind) {
      case _Kind.deadline:
        return _deadline(clean, lower);
      case _Kind.event:
        return _event(clean, lower);
      case _Kind.payment:
        return _payment(clean, lower);
      case _Kind.client:
        return _client(clean, lower);
      case _Kind.edit:
        return _edit(clean, lower);
      case _Kind.delete:
        return _delete(clean, lower);
      case _Kind.none:
        // No write cue anywhere. A sentence that merely mentions "client" is a
        // question for the model, not an instruction, and guessing here is how
        // "tell me about Acme" ends up trying to create a client called it.
        return null;
    }
  }

  _Kind _kindFor(String lower) {
    final d = _earliestCue(lower, _deadlineCues);
    final v = _earliestCue(lower, _eventCues);
    final p = _earliestCue(lower, _paymentCues);
    final c = _earliestCue(lower, _clientCues);
    final e = _earliestCue(lower, _editCues);
    final x = _earliestCue(lower, _deleteCues);
    // The "X paid N" shape has no cue phrase at all, it is its own pattern, so
    // it is detected separately and only when no explicit cue beat it.
    final paidAt = lower.indexOf(' paid');

    var best = _Kind.none;
    var bestAt = 1 << 30;
    void offer(_Kind k, int? at) {
      if (at == null || at < 0 || at >= bestAt) return;
      best = k;
      bestAt = at;
    }

    offer(_Kind.deadline, d?.$1);
    offer(_Kind.event, v?.$1);
    offer(_Kind.payment, p?.$1);
    offer(_Kind.client, c?.$1);
    // An edit or delete must never win on position alone. "delete bilal, then
    // add a client called Bilal" carries both, and quietly treating the second
    // half as an add while the first half was meant as a delete is how a record
    // gets lost. They are only taken when nothing else claimed the sentence.
    offer(_Kind.delete, x?.$1);
    offer(_Kind.edit, e?.$1);
    if (best == _Kind.none && paidAt >= 0) best = _Kind.payment;
    return best;
  }

  bool _isWordChar(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 48 && code <= 57) ||
        (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122) ||
        code == 95;
  }

  /// Index of [cue] in [lower] where it stands alone as whole words, or -1.
  ///
  /// Same word boundary rule the output guard uses, so "add client" cannot fire
  /// on "add clientXyz" and does fire at the very start of a sentence.
  int _findCue(String lower, String cue) {
    var from = 0;
    while (true) {
      final at = lower.indexOf(cue, from);
      if (at < 0) return -1;
      final beforeOk = at == 0 || !_isWordChar(lower[at - 1]);
      final end = at + cue.length;
      final afterOk = end >= lower.length || !_isWordChar(lower[end]);
      if (beforeOk && afterOk) return at;
      from = at + 1;
    }
  }

  /// The earliest cue in [cues], longest first at the same position, so
  /// "add a deadline to" wins over "add a deadline".
  (int, String)? _earliestCue(String lower, List<String> cues) {
    (int, String)? best;
    for (final cue in cues) {
      final at = _findCue(lower, cue);
      if (at < 0) continue;
      if (best == null || at < best.$1 || (at == best.$1 && cue.length > best.$2.length)) {
        best = (at, cue);
      }
    }
    return best;
  }

  bool _hasCue(String lower, List<String> cues) => _earliestCue(lower, cues) != null;

  /// Everything after the first cue, up to the first name stop.
  /// Trims a name down to just the name.
  ///
  /// Stops are space delimited on purpose, so they are found with a plain
  /// search rather than the word boundary rule used for cues. That rule wants
  /// non-word characters either side of a match, and a stop ends in a space
  /// followed by a word, so it never qualifies.
  String? _trimName(String clean, String lower) {
    if (clean.isEmpty) return null;
    // The earliest stop is the boundary, and it is cut once. Cutting at every
    // stop in turn reuses an index measured against the original string, so the
    // second cut lands past the end of the already shortened one and throws.
    var cut = -1;
    for (final stop in _nameStops) {
      final at = lower.indexOf(stop);
      if (at > 0 && (cut < 0 || at < cut)) cut = at;
    }
    var rest = cut > 0 ? clean.substring(0, cut) : clean;
    rest = _dropTrailingStops(rest.split(RegExp(r'[.,]')).first);
    if (rest.isEmpty) return null;
    return _shortenName(rest);
  }

  /// Removes trailing function words, repeated until none are left.
  ///
  /// Cutting only removes stops that are followed by something. The match in
  /// "mark Acme as paid" ends at "acme as", with the stop word hanging off the
  /// end where no cut can reach it, so it has to be trimmed off the tail.
  String _dropTrailingStops(String s) {
    var out = s.trim();
    var changed = true;
    while (changed) {
      changed = false;
      final lower = out.toLowerCase();
      for (final stop in _nameStops) {
        final bare = stop.trim();
        if (out.length > bare.length && lower.endsWith(bare)) {
          out = out.substring(0, out.length - bare.length).trim();
          changed = true;
          break;
        }
      }
    }
    return out;
  }

  String? _tailAfterCue(String clean, String lower, List<String> cues) {
    final found = _earliestCue(lower, cues);
    if (found == null) return null;
    var rest = clean.substring(found.$1 + found.$2.length).trim();
    // "add a client called X" and "add client named X" both introduce a name.
    for (final lead in const ['called ', 'named ']) {
      if (rest.toLowerCase().startsWith(lead)) {
        rest = rest.substring(lead.length).trim();
      }
    }
    if (rest.isEmpty) return null;
    return _trimName(rest, rest.toLowerCase());
  }

  double? _amountIn(String lower) {
    // A date is not money. Stripped first or "2026-03-01" reads as 2026.
    final scrubbed = lower.replaceAll(_isoDate, ' ');
    final match = _number.firstMatch(scrubbed);
    if (match == null) return null;
    final value = double.tryParse(match.group(1)!.replaceAll(',', ''));
    return (value == null || value <= 0) ? null : value;
  }

  String? _dateIn(String lower) {
    final iso = _isoDate.firstMatch(lower);
    if (iso != null) return iso.group(1);

    final offset = _inDays.firstMatch(lower);
    if (offset != null) {
      final days = int.tryParse(offset.group(1)!);
      if (days != null) return _iso(DateTime.now().add(Duration(days: days)));
    }
    if (lower.contains('tomorrow')) {
      return _iso(DateTime.now().add(const Duration(days: 1)));
    }
    if (lower.contains('today')) return _iso(DateTime.now());

    for (final entry in _weekdays.entries) {
      if (!lower.contains(entry.key)) continue;
      // The next one, today included. "Due Friday" said on a Friday means
      // Friday, not a week from Friday.
      final today = DateTime.now();
      var delta = entry.value - today.weekday;
      if (delta < 0) delta += 7;
      return _iso(today.add(Duration(days: delta)));
    }
    return null;
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  WriteIntent? _client(String clean, String lower) {
    if (!_hasCue(lower, _clientCues)) return null;
    final name = _tailAfterCue(clean, lower, _clientCues);
    if (name == null || name.length < 2 || _number.hasMatch(name)) {
      // The cue is there and the name is not. That is an instruction to record
      // something that cannot be recorded yet, so it becomes a question rather
      // than falling through to a model that would invent a result.
      return IncompleteWriteIntent(kind: WriteKind.client, askedFor: clean);
    }
    return AddClientIntent(
      name: name,
      amount: _amountIn(lower),
      due: _dateIn(lower),
    );
  }

  /// "change the amount on bilal to 3000", "bilal now owes 4000".
  ///
  /// Refuses when no field is actually named. "change bilal" says what it wants
  /// to touch but not what to change it to, and answering it with a card would
  /// train the user to approve cards without reading them.
  WriteIntent? _edit(String clean, String lower) {
    if (!_hasCue(lower, _editCues)) return null;

    // The name is what sits before the cue for "now owes", and after it for
    // "change the amount on", so both shapes are read and the longer match wins.
    final amount = _amountIn(lower);
    final due = _dateIn(lower);
    final status = _statusIn(lower);

    final name = _editTarget(clean, lower);
    if (name == null) {
      return IncompleteWriteIntent(kind: WriteKind.client, askedFor: clean);
    }
    if (amount == null && due == null && status == null) {
      return IncompleteWriteIntent(kind: WriteKind.client, askedFor: clean);
    }
    return EditClientIntent(
      clientName: name,
      amount: amount,
      due: due,
      status: status,
    );
  }

  /// The client an edit is about, read from either word order.
  String? _editTarget(String clean, String lower) {
    final found = _earliestCue(lower, _editCues);
    if (found == null) return null;
    // After the cue: "change the amount on bilal".
    final after = clean.substring(found.$1 + found.$2.length).trim();
    // Before it: "bilal now owes 4000".
    final before = clean.substring(0, found.$1).trim();

    for (final lead in const [' to ', ' from ']) {
      // "change ... to" introduces the new value, not the name, so it ends the
      // name rather than being part of it.
      final at = after.toLowerCase().indexOf(lead);
      if (at > 0) {
        final head = after.substring(0, at);
        final cut = _trimName(head, head.toLowerCase());
        if (cut != null && cut.length >= 2) return cut;
      }
    }
    // A tail of "4000" is the new amount, not the client's name. "bilal now
    // owes 4000" has its name before the cue and its value after it, so a tail
    // with no letters in it is never a name.
    final tail = _trimName(after, after.toLowerCase());
    if (tail != null && tail.length >= 2 && _hasLetter(tail)) return tail;

    final head = _trimName(before, before.toLowerCase());
    if (head != null && head.length >= 2 && _hasLetter(head)) return head;
    return null;
  }

  /// True when [s] contains at least one letter.
  ///
  /// Deliberately not a number check: "4000" is not a name, and neither is
  /// "1,200" or "20%". A name is words.
  static bool _hasLetter(String s) => RegExp('[a-z]').hasMatch(s.toLowerCase());

  String? _statusIn(String lower) {
    for (final pair in const <(String, String)>[
      ('mark as active', 'active'),
      ('mark as paid', 'paid'),
      ('mark as lead', 'lead'),
      ('status active', 'active'),
      ('status paid', 'paid'),
      ('status lead', 'lead'),
      ('set to active', 'active'),
      ('set to paid', 'paid'),
    ]) {
      if (lower.contains(pair.$1)) return pair.$2;
    }
    return null;
  }

  /// "delete bilal", "remove client bilal".
  WriteIntent? _delete(String clean, String lower) {
    if (!_hasCue(lower, _deleteCues)) return null;
    final found = _earliestCue(lower, _deleteCues);
    if (found == null) return null;
    final rest = clean.substring(found.$1 + found.$2.length).trim();
    final name = _trimName(rest, rest.toLowerCase());
    if (name == null || name.length < 2 || _number.hasMatch(name)) {
      return IncompleteWriteIntent(kind: WriteKind.client, askedFor: clean);
    }
    return DeleteClientIntent(clientName: name);
  }

  RecordPaymentIntent? _payment(String clean, String lower) {
    // "recorded a payment of 500 from bilal", the explicit and least ambiguous
    // shape. Tried first because it names the client unambiguously.
    final from = RegExp(
      r'(?:payment|payments)\s+(?:of\s+)?(\d[\d,]*(?:\.\d+)?)\s*(?:aed)?\s+from\s+(.+)',
    ).firstMatch(lower);
    if (from != null) {
      final name = _trimName(
        clean.substring(lower.indexOf(from.group(2)!)),
        from.group(2)!,
      );
      if (name != null) {
        return RecordPaymentIntent(
          clientName: name,
          amount: double.tryParse(from.group(1)!.replaceAll(',', '')),
        );
      }
    }

    // "bilal paid", "bilal paid me", "acme studio paid 1200", "mark acme as paid".
    final paid = RegExp(r'\b([\w]+(?: [\w]+)?) paid(?: me)?\s*(\d[\d,]*(?:\.\d+)?)?')
        .firstMatch(lower);
    if (paid != null) {
      final raw = double.tryParse((paid.group(2) ?? '').replaceAll(',', ''));
      // The trailing "as" in "mark Acme as paid" rides along when a second word
      // is allowed, so the name is trimmed like any other rather than trusted
      // to the regex.
      final name = _trimName(_slice(clean, lower, paid.group(1)!), paid.group(1)!);
      if (name == null || name.length < 2) return null;
      return RecordPaymentIntent(
        clientName: name,
        amount: (raw == null || raw <= 0) ? null : raw,
      );
    }

    if (_hasCue(lower, _paymentCues)) {
      final name = _tailAfterCue(clean, lower, _paymentCues);
      if (name != null && name.length >= 2 && !_number.hasMatch(name)) {
        return RecordPaymentIntent(clientName: name, amount: _amountIn(lower));
      }
    }
    return null;
  }

  AddDeadlineIntent? _deadline(String clean, String lower) {
    final found = _earliestCue(lower, _deadlineCues);
    if (found == null) return null;

    var rest = clean.substring(found.$1 + found.$2.length).trim();
    final restLower = rest.toLowerCase();

    // The date phrase belongs to the due date, not to the title. Not a const list
    // because _inDays is a compiled pattern rather than a literal.
    for (final pattern in <RegExp>[
      RegExp(r'\s+(on|by|due|before)\s'),
      _inDays,
      RegExp(r'\s+(today|tomorrow)\b'),
    ]) {
      final m = pattern.firstMatch(restLower);
      if (m != null && m.start > 0) {
        rest = rest.substring(0, m.start);
        break;
      }
    }

    final title = rest.trim();
    if (title.isEmpty) return null;
    // No client is guessed at here. Free text after "for" is far more often
    // "for the invoice" than a name, and the confirmation card offers the real
    // list anyway, so a wrong guess here would only create something to undo.
    return AddDeadlineIntent(title: title, due: _dateIn(lower));
  }

  /// "schedule a call with Bilal tomorrow at 3pm at the studio".
  ///
  /// Reads the time, then the location, then what is left becomes the title, in
  /// that order, because both of the extra pieces can only be recognised once
  /// the piece before them has been taken out of the sentence.
  AddEventIntent? _event(String clean, String lower) {
    final found = _earliestCue(lower, _eventCues);
    if (found == null) return null;

    var rest = clean.substring(found.$1 + found.$2.length).trim();
    if (rest.isEmpty) return null;

    final time = _timeIn(rest.toLowerCase());

    // Whatever the date phrase was, it belongs to the date, not the title.
    // Weekdays are cut too, since _dateIn already read them from the whole
    // sentence and a title of "call with Bilal on Friday" is the parser failing
    // to separate the two.
    final restLower = rest.toLowerCase();
    for (final pattern in <RegExp>[
      RegExp(r'\s+(on|by|due|before)\s'),
      _inDays,
      RegExp(r'\s+(today|tomorrow)\b'),
      RegExp(r'\s+(next|this)\s+(week|month|monday|tuesday|wednesday|'
          r'thursday|friday|saturday|sunday|weekend)\b'),
      for (final day in _weekdays.keys) RegExp('\\s+$day\\b'),
      _isoDate,
      _timeRe,
    ]) {
      final m = pattern.firstMatch(restLower);
      if (m != null && m.start > 0) {
        rest = '${rest.substring(0, m.start)} ${rest.substring(m.end)}';
        rest = rest.replaceAll(RegExp(r'\s+'), ' ').trim();
      } else if (m != null && m.start == 0) {
        rest = rest.substring(m.end).trim();
      }
    }

    // A location is "at the studio" where "at" is followed by words rather
    // than by a clock, and only at the very end: "call with Bilal at Acme" is
    // far more often about the client than about a venue, and the ones that
    // are about a venue are easy to retype.
    String? location;
    final place = RegExp(r'\s+(?:at|in)\s+((?:the\s+)?[a-z][a-z\s]{0,24})$')
        .firstMatch(rest.toLowerCase());
    if (place != null && !_number.hasMatch(place.group(1)!)) {
      // Indices from the lower-case match line up with the original because
      // both strings came from the same slice and folding only changes case.
      final start = rest.toLowerCase().indexOf(place.group(1)!, place.start);
      location = _titleCase(rest.substring(start));
      rest = rest.substring(0, place.start).trim();
    }

    final title = rest.trim();
    if (title.isEmpty || title.length < 2) return null;
    // No date at all: today is what "schedule a call" almost always means, and
    // the card shows the date before anything is saved, so a wrong guess is
    // visible rather than silent.
    return AddEventIntent(
      title: title,
      date: _dateIn(lower) ?? _iso(DateTime.now()),
      time: time,
      location: location,
    );
  }

  /// The clock time in [lower] as "HH:mm", or null when it carries none.
  String? _timeIn(String lower) {
    final m = _timeRe.firstMatch(lower);
    if (m == null) return null;
    int? hour;
    int minute = 0;
    if (m.group(1) != null) {
      hour = int.tryParse(m.group(1)!);
      minute = int.tryParse(m.group(2) ?? '0') ?? 0;
      final meridiem = m.group(3);
      if (hour == null || hour > 12 || hour < 1) return null;
      if (meridiem == 'pm' && hour != 12) hour += 12;
      if (meridiem == 'am' && hour == 12) hour = 0;
    } else {
      hour = int.tryParse(m.group(4) ?? '');
      minute = int.tryParse(m.group(5) ?? '') ?? 0;
      if (hour == null || hour > 23 || minute > 59) return null;
    }
    return '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}';
  }

  /// "the studio" -> "The studio", so a location on the card reads as a phrase
  /// rather than a fragment left over from a sentence.
  String _titleCase(String s) {
    final t = s.trim();
    if (t.isEmpty) return t;
    return t[0].toUpperCase() + t.substring(1);
  }

  /// Slices the case preserved [clean] using a match found in [lower].
  ///
  /// The needle came out of [lower], so it is always present; the fallback is
  /// here so a future change cannot turn a miss into a range error.
  String _slice(String clean, String lower, String needle) {
    final at = lower.indexOf(needle);
    if (at < 0) return '';
    return clean.substring(at, at + needle.length);
  }

  /// Keeps at most three words, so "bilal studio ltd" survives but a trailing
  /// clause does not become part of the name.
  String _shortenName(String s) {
    final words = s.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    return words.take(3).join(' ');
  }
}