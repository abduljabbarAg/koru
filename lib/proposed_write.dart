import 'local/bulk_import.dart';
import 'local/write_intent.dart';
import 'models.dart';
import 'store.dart';

/// A write the user asked for, resolved against the real records and waiting to
/// be approved.
///
/// Nothing here runs until [apply] is called, and [apply] is only called from a
/// button. The parser can therefore be wrong without consequence, which is the
/// whole reason it is allowed to guess at all.
sealed class ProposedWrite {
  const ProposedWrite();

  /// One line for the card, saying what approving will do.
  String get summary;

  Future<void> apply(ProfileStore store);
}

class ProposedClient extends ProposedWrite {
  const ProposedClient({
    required this.name,
    this.amount,
    this.due,
    this.deposit,
    this.retainer = false,
    this.termsDays,
    this.invoicedOn,
  });

  final String name;
  final double? amount;
  final String? due;

  /// Paid up front. Applied as a ledger payment, never subtracted here.
  final double? deposit;

  final bool retainer;
  final int? termsDays;
  final DateTime? invoicedOn;

  @override
  String get summary {
    final parts = <String>['Add $name'];
    if (retainer) {
      parts.add('${_plain(amount ?? 0)} a month');
    } else if (amount != null) {
      parts.add('invoiced ${_plain(amount!)}');
    }
    if (deposit != null) parts.add('${_plain(deposit!)} paid up front');
    if (due != null) {
      parts.add('due $due');
    } else if (termsDays != null) {
      parts.add(termsDays == 0 ? 'due on completion' : 'net $termsDays');
    }
    return parts.join(', ');
  }

  @override
  Future<void> apply(ProfileStore store) async {
    final on = invoicedOn ?? DateTime.now();
    final id = await store.addClient(Client(
      name: name,
      amount: amount,
      due: due,
      deposit: deposit,
      monthly: retainer ? amount : null,
      termsDays: termsDays,
      invoicedOn: _dateOf(on),
      status: amount == null ? 'lead' : 'active',
      created: on.toIso8601String(),
    ));
    // Copied to a local first. Dart promotes local variables but not fields, so
    // checking `deposit` and then using `deposit` leaves the type nullable and
    // every use below is a cast the compiler rightly refuses.
    final paid = deposit;
    // addClient returns a non-nullable id, so there is no "did it save" case to
    // handle here: either the insert succeeded or it threw and the surrounding
    // transaction rolled the whole plan back.
    if (paid != null && paid > 0) {
      await store.addPayment(Payment(
        clientId: id,
        amount: paid,
        date: _dateOf(on),
        note: 'Deposit',
      ));
    }
  }

  static String _dateOf(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

class ProposedPayment extends ProposedWrite {
  const ProposedPayment({required this.client, this.amount, this.note});

  final Client client;
  final double? amount;
  final String? note;

  @override
  String get summary => amount == null
      ? 'Record a payment from ${client.name}'
      : 'Record ${_plain(amount!)} from ${client.name}';

  @override
  Future<void> apply(ProfileStore store) async {
    await store.addPayment(Payment(
      clientId: client.id!,
      amount: amount!,
      date: DateTime.now().toIso8601String().substring(0, 10),
      note: note,
    ));
    // Settles only when the ledger says it is settled, the same rule the
    // Business screen uses. Two places deciding this differently is how a
    // client's status and their balance drift apart.
    if (client.balanceWith(await store.receivedFor(client.id!) + amount!) <= 0) {
      await store.setClientStatus(client.id!, 'paid');
    }
  }
}

class ProposedDeadline extends ProposedWrite {
  const ProposedDeadline({required this.title, this.due, this.client});

  final String title;
  final String? due;
  final Client? client;

  @override
  String get summary => due == null
      ? 'Add a deadline: $title'
      : 'Add "$title", due $due';

  @override
  Future<void> apply(ProfileStore store) => store.addDeadline(Deadline(
        clientId: client?.id,
        title: title,
        due: due ?? DateTime.now().toIso8601String().substring(0, 10),
      ));
}

/// A list of writes, shown to the user as numbered steps and applied together.
///
/// The shape a multi step task needs, and the one Gemini-style interfaces get
/// right: the user sees exactly what is going to happen, in what order, before
/// any of it happens. Nothing is written by showing it.
///
/// Atomic on purpose. Part of an import landing is worse than none of it,
/// because there is then no way to tell what went in from what did not.
class ProposedPlan extends ProposedWrite {
  const ProposedPlan({required this.steps, this.problems = const []});

  final List<ProposedWrite> steps;

  /// Lines that could not be read, carried through to the card.
  ///
  /// Never discarded. A list of twenty that silently becomes seventeen is the
  /// same failure as the Business page reading zero, at a scale where it takes
  /// a month to notice.
  final List<UnreadableLine> problems;

  @override
  String get summary => switch (steps.length) {
        0 => 'Nothing to add',
        1 => steps.first.summary,
        _ => '${steps.length} things to add',
      };

  @override
  Future<void> apply(ProfileStore store) async {
    if (steps.isEmpty) return;
    await store.transaction((scoped) async {
      for (final step in steps) {
        await step.apply(scoped);
      }
    });
  }
}

/// A proposed import, tied to the text it came from.
///
/// The fingerprint is what stops the same list being pasted twice and quietly
/// doubling everyone's balance. It is stored rather than checked against the
/// client names, because a second paste of a corrected list is a legitimate
/// thing to want and a name match would refuse it.
class ProposedImport extends ProposedPlan {
  ProposedImport({
    required super.steps,
    super.problems,
    required this.source,
    required this.fingerprint,
  });

  /// The text the user pasted, kept so the card can show them what it read.
  final String source;
  final String fingerprint;

  /// True when this exact text has already been imported.
  Future<bool> alreadyImported(ProfileStore store) async =>
      await store.get('import:$fingerprint').then((v) => v != null);

  /// Records the text so a second paste of it is refused.
  Future<void> rememberImport(ProfileStore store) =>
      store.put('import:$fingerprint', DateTime.now().toIso8601String());

  /// A stable id for a block of text, so the same paste is recognised.
  ///
  /// FNV-1a rather than SHA-256, and deliberately so. This is not a security
  /// boundary, it is a "have I seen this exact text before" check on one device
  /// holding a handful of imports, and adding a crypto dependency for it would
  /// be paying a supply chain cost for something a wrong answer cannot exploit.
  /// A collision would refuse an import the user wanted, and re-pasting with a
  /// space added produces a different fingerprint, so it is recoverable rather
  /// than a trap.
  static String fingerprintOf(String text) {
    // 64 bit FNV-1a over the trimmed text.
    const offset = 0xcbf29ce484222325;
    const prime = 0x100000001b3;
    var hash = offset;
    for (final byte in text.trim().codeUnits) {
      hash = (hash ^ (byte & 0xff)) * prime;
      hash = hash & 0xffffffffffffffff;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}

/// Turns parsed rows into steps, posting any deposit into the ledger.
///
/// A deposit is a payment, not a subtraction, for the same reason the client
/// form does it that way: money is computed from the ledger everywhere and a
/// second copy that only affects one screen eventually disagrees with it.
List<ProposedWrite> stepsForImport(List<ImportRow> rows, {DateTime? invoicedOn}) {
  final on = invoicedOn ?? DateTime.now();
  final out = <ProposedWrite>[];
  for (final row in rows) {
    out.add(ProposedClient(
      name: row.name,
      amount: row.amount,
      due: row.due,
      deposit: row.deposit,
      retainer: row.retainer,
      termsDays: row.termsDays,
      invoicedOn: on,
    ));
  }
  return out;
}

/// The outcome of turning a sentence into something the app can act on.
///
/// Either a write, or a plain sentence saying why there is not one. Kept as a
/// result rather than an exception because being unable to resolve a name is an
/// ordinary answer, not a failure.
class WriteResolution {
  const WriteResolution.proposed(ProposedWrite this.write) : problem = null;

  const WriteResolution.problem(this.problem) : write = null;

  final ProposedWrite? write;

  /// Said back to the user when nothing could be proposed.
  final String? problem;

  bool get isWrite => write != null;
}

String _plain(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

/// Turns a parsed intent into a write that points at real records.
///
/// Refuses rather than guesses. A payment for a client who does not exist, or
/// for one of two clients with the same name, is exactly the case where
/// recording something plausible would be worse than saying nothing.
class WriteResolver {
  const WriteResolver();

  Future<WriteResolution> resolve(WriteIntent intent, ProfileStore store) async {
    switch (intent) {
      case AddClientIntent():
        return WriteResolution.proposed(
          ProposedClient(name: intent.name, amount: intent.amount, due: intent.due),
        );

      case RecordPaymentIntent():
        final clients = await store.clients();
        final match = _match(clients, intent.clientName);
        if (match.isEmpty) {
          return WriteResolution.problem(
            'I do not have a client called ${intent.clientName}. '
            'Say "add client ${intent.clientName}" and I will.',
          );
        }
        if (match.length > 1) {
          final names = match.map((c) => c.name).join(' and ');
          return WriteResolution.problem(
            'More than one client matches ${intent.clientName}: $names. '
            'Tell me which one.',
          );
        }
        return WriteResolution.proposed(
          ProposedPayment(client: match.single, amount: intent.amount, note: intent.note),
        );

      case AddDeadlineIntent():
        return WriteResolution.proposed(
          ProposedDeadline(title: intent.title, due: intent.due),
        );
    }
  }

  /// Clients whose name matches [typed], nearest match first.
  ///
  /// Exact before prefix before contains, because "Bilal" should find "Bilal"
  /// even when "Bilal Studio" is also on file, and the ambiguity is reported
  /// rather than picked.
  List<Client> _match(List<Client> clients, String typed) {
    final needle = typed.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    final exact = clients.where((c) => c.name.toLowerCase() == needle).toList();
    if (exact.isNotEmpty) return exact;
    final prefix =
        clients.where((c) => c.name.toLowerCase().startsWith(needle)).toList();
    if (prefix.isNotEmpty) return prefix;
    return clients.where((c) => c.name.toLowerCase().contains(needle)).toList();
  }
}