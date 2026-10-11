import '../models.dart';

/// One line of a pasted client list, read into something structured.
///
/// Pure data with no database behind it, because the hard part of bulk import is
/// the language and the easy way to get that wrong is to make it untestable.
class ImportRow {
  final String name;
  final double? amount;

  /// Already paid up front, if the line said so.
  final double? deposit;

  /// Retainer rather than a one-off invoice.
  final bool retainer;

  /// Days to pay, when the line said "net 14".
  final int? termsDays;

  final String? due;

  const ImportRow({
    required this.name,
    this.amount,
    this.deposit,
    this.retainer = false,
    this.termsDays,
    this.due,
  });

  /// The client this row becomes.
  Client toClient({DateTime? invoicedOn}) => Client(
        name: name,
        amount: amount,
        deposit: deposit,
        status: 'active',
        created: (invoicedOn ?? DateTime.now()).toIso8601String(),
        monthly: retainer ? amount : null,
        termsDays: termsDays,
        invoicedOn: invoicedOn == null
            ? null
            : _date(DateTime(invoicedOn.year, invoicedOn.month, invoicedOn.day)),
        due: due,
      );

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// A line that could not be read, kept so it can be shown rather than lost.
///
/// Every line is either a row or a problem with a reason. A line that is silently
/// dropped is how a list of twenty becomes a list of seventeen and nobody finds
/// out for a month, which is the same failure as the client screen reading zero
/// because empty rows were accepted without complaint.
class UnreadableLine {
  final String text;
  final String reason;

  const UnreadableLine(this.text, this.reason);

  @override
  String toString() => reason;
}

/// Reads a pasted list of clients, one per line.
///
/// Written to be generous about how people actually type, because the input is
/// coming off a phone's clipboard or out of someone's head, not out of a form.
///
/// Two things are deliberately refused rather than guessed:
///
/// - **A line with no agreed amount.** A client with no amount contributes
///   nothing to owed, nothing to outstanding, and never goes overdue, which is
///   precisely how the Business page came to read zero across the board.
/// - **A line with no name.** There is nothing to attach the money to.
class BulkClientParser {
  const BulkClientParser();

  /// Separators between fields. Dashes are included because "Bilal - 3000" is
  /// how people write lists, but a leading dash is stripped as a bullet first so
  /// the two do not fight.
  static const _separators = [',', '|', '\t', '-', ' – ', ' — '];

  /// Openers that are not part of the name.
  static const _leads = [
    'called ',
    'named ',
  ];

  static final _bullet = RegExp(r'^\s*(?:[-*•–—]+|\d+[.)])\s*');
  static final _number = RegExp(r'(\d[\d,]*(?:\.\d+)?)');
  static final _isoDate = RegExp(r'(\d{4}-\d{2}-\d{2})');
  static final _net = RegExp(r'net\s*(\d+)', caseSensitive: false);
  static final _retainer = RegExp(r'\b(retainer|monthly|per month|retaining)\b',
      caseSensitive: false);
  static final _deposit = RegExp(r'\bdeposit\s*[:=]?\s*(\d[\d,]*(?:\.\d+)?)',
      caseSensitive: false);
  static final _dueWord = RegExp(r'\bdue\s*[:=]?\s*(\S+)', caseSensitive: false);

  ImportResult parse(String raw) {
    final rows = <ImportRow>[];
    final problems = <UnreadableLine>[];

    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      // A heading is not a client. "My clients:" on its own line is a person
      // setting up a list, not a row that failed to parse, so it is skipped
      // silently rather than shouted about.
      if (_looksLikeHeading(trimmed)) continue;

      final row = _row(trimmed);
      if (row != null) {
        rows.add(row);
      } else {
        problems.add(UnreadableLine(trimmed, _why(trimmed)));
      }
    }
    return ImportResult(rows: rows, problems: problems);
  }

  bool _looksLikeHeading(String line) {
    // The colon is tested on the line as typed. An earlier version stripped
    // trailing punctuation off first and then asked whether the stripped text
    // ended in a colon, which it never could, so every heading was reported as
    // an unreadable row and "My clients:" turned up in the error list next to
    // the clients it was introducing.
    return line.endsWith(':') && !_number.hasMatch(line);
  }

  ImportRow? _row(String line) {
    var text = line.replaceFirst(_bullet, '').trim();
    for (final lead in _leads) {
      if (text.toLowerCase().startsWith(lead)) {
        text = text.substring(lead.length).trim();
      }
    }

    final retainer = _retainer.hasMatch(text);
    final net = _net.firstMatch(text);
    final iso = _isoDate.firstMatch(text);
    final deposit = _deposit.firstMatch(text);
    final dueWord = _dueWord.firstMatch(text);

    // The name is whatever comes before the first figure, separator or keyword.
    // Taking it first, then the modifiers, means "Acme rebrand 5000" reads as a
    // client called "Acme rebrand" rather than as a number called Acme.
    final name = _nameOf(text);

    // Every figure on the line, minus the ones already claimed by a keyword, so
    // "net 30" does not become an amount of 30.
    final claimed = <int>{
      if (net != null) net.start,
      if (deposit != null) deposit.start,
    };
    final figures = <double>[];
    for (final m in _number.allMatches(text)) {
      if (claimed.any((start) => m.start >= start && m.start < start + 8)) continue;
      final v = double.tryParse(m.group(1)!.replaceAll(',', ''));
      if (v != null && v > 0) figures.add(v);
    }

    final amount = figures.isEmpty ? null : figures.first;
    // Anything after the agreed amount that looks like a figure is the deposit.
    final depositValue = deposit != null
        ? double.tryParse(deposit.group(1)!.replaceAll(',', ''))
        : (figures.length > 1 ? figures[1] : null);

    String? due;
    if (iso != null) {
      due = iso.group(1);
    } else if (dueWord != null && !_net.hasMatch(dueWord.group(0) ?? '')) {
      due = dueWord.group(1);
    }

    if (name == null || name.length < 2) return null;
    if (amount == null && !retainer) return null;

    return ImportRow(
      name: name,
      amount: amount,
      deposit: depositValue != null && depositValue < (amount ?? 0) ? depositValue : null,
      retainer: retainer,
      termsDays: net == null ? null : int.tryParse(net.group(1)!),
      due: due,
    );
  }

  /// The name: everything before the first figure, separator, or keyword.
  String? _nameOf(String text) {
    var cut = -1;
    for (final m in _number.allMatches(text)) {
      cut = cut < 0 ? m.start : cut;
      break;
    }
    // >= 0, not > 0. A line that *starts* with a figure gives cut == 0, and
    // the old test left the whole line in place, so a bare "3000" became a
    // client called "3000".
    var head = cut >= 0 ? text.substring(0, cut) : text;

    for (final sep in _separators) {
      final at = head.indexOf(sep);
      if (at >= 0) head = head.substring(0, at);
    }
    for (final kw in const [
      'net ', 'due ', 'deposit', 'retainer', 'monthly', 'per month', 'invoice',
    ]) {
      final at = head.toLowerCase().indexOf(kw);
      if (at >= 0) head = head.substring(0, at);
    }
    head = head.trim().replaceAll(RegExp(r'[\s,;]+$'), '');
    // A row that opens with a figure has no name, it is just a number with
    // nothing attached to it. Left alone, the empty head fell through to the
    // whole line and "3000" became a client called "3000".
    if (head.isEmpty && _number.hasMatch(text)) return null;
    // "Acme Studio" is two words. Stopping at the first one would drop half the
    // name, so only a genuinely long tail is cut.
    final words = head.split(RegExp(r'\s+'));
    if (words.length > 5) head = words.take(5).join(' ');
    return head.isEmpty ? null : head;
  }

  /// Why a line was refused, said in the user's terms.
  String _why(String line) {
    if (_number.hasMatch(line.replaceFirst(_retainer, '')) &&
        _nameOf(line) == null) {
      return 'has an amount but no name';
    }
    if (_nameOf(line) == null) return 'no name I could read';
    return 'no amount on it';
  }
}

/// What a pasted list turned into.
class ImportResult {
  final List<ImportRow> rows;
  final List<UnreadableLine> problems;

  const ImportResult({required this.rows, required this.problems});

  bool get isEmpty => rows.isEmpty && problems.isEmpty;

  /// Lines that changed, so an import that changed nothing is never worth
  /// asking the user to confirm.
  bool get hasWork => rows.isNotEmpty;
}