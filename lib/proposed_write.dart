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
  const ProposedClient({required this.name, this.amount, this.due});

  final String name;
  final double? amount;
  final String? due;

  @override
  String get summary => amount == null
      ? 'Add a client called $name'
      : 'Add $name, invoiced ${_plain(amount!)}';

  @override
  Future<void> apply(ProfileStore store) => store.addClient(Client(
        name: name,
        amount: amount,
        due: due,
        status: amount == null ? 'lead' : 'active',
        created: DateTime.now().toIso8601String(),
      ));
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