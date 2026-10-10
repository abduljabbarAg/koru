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

String _plain(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

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
    'create a customer',
    'create customer',
    'register a client',
    'register a customer',
    'add a customer',
    'add customer',
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

  /// Words that make a sentence a question rather than an instruction.
  static const _interrogatives = [
    'how much', 'how many', 'how long', 'what', 'when', 'where', 'who ',
    'why', 'did ', 'does ', 'do i', 'is ', 'are ', 'was ', 'were ', 'have i',
    'should i', 'can i', 'could i', 'am i', 'which ',
  ];

  static final _number = RegExp(r'(\d[\d,]*(?:\.\d+)?)');
  static final _isoDate = RegExp(r'\b(\d{4}-\d{2}-\d{2})\b');
  static final _inDays = RegExp(r'\bin (\d+) days?\b');

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

    // Deadlines first: "add a deadline to call Bilal about the invoice" also
    // contains a name and a number, and is about neither.
    final deadline = _deadline(clean, lower);
    if (deadline != null) return deadline;

    final payment = _payment(clean, lower);
    if (payment != null) return payment;

    return _client(clean, lower);
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

  AddClientIntent? _client(String clean, String lower) {
    if (!_hasCue(lower, _clientCues)) return null;
    final name = _tailAfterCue(clean, lower, _clientCues);
    if (name == null || name.length < 2 || _number.hasMatch(name)) return null;
    return AddClientIntent(
      name: name,
      amount: _amountIn(lower),
      due: _dateIn(lower),
    );
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