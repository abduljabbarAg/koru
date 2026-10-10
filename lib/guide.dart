import 'dart:math' as math;

import 'models.dart';

/// What Koru says, and when.
///
/// The mascot was only ever decorative: a sprite on the splash and in the chat
/// bar. This gives him a job. He looks at what is actually on screen and offers
/// one observation, with a comic panel beside him, the way a helper in a comic
/// leans in to say something.
///
/// Every line is chosen from real data rather than a generic encouragement. A
/// mascot that says "you've got this!" regardless of whether there are three
/// unpaid invoices is worse than no mascot, because it looks like it knows.
class Guide {
  const Guide._();

  /// The line Koru says on [screen] given [facts], or null when he has nothing
  /// worth saying.
  ///
  /// Silence is allowed on purpose. A mascot that talks every time a screen opens
  /// is noise, and people learn to ignore it, which costs the one message that
  /// would have mattered.
  static String? forBusiness(ScreenFacts f) {
    if (f.clients.isEmpty) {
      return 'No clients yet. Add one and I can start tracking what is paid and what is not.';
    }
    final owing = f.clients.where((c) => f.balanceOf(c) > 0).toList()
      ..sort((a, b) => f.balanceOf(b).compareTo(f.balanceOf(a)));

    if (owing.isNotEmpty) {
      final top = owing.first;
      if (owing.length == 1) {
        return '${top.name} owes you ${f.balanceOf(top).toStringAsFixed(0)} AED. '
            'That is the easiest money in this list.';
      }
      return '${owing.length} clients owe you ${f.outstanding.toStringAsFixed(0)} AED in '
          'total, ${top.name} most of all. Chasing that beats landing anything new.';
    }

    final pipeline = f.clients.where((c) => c.status == 'lead' || c.status == 'active').length;
    if (pipeline > 0) {
      return '$pipeline in the pipeline and nothing waiting on payment. '
          'Good place to follow up.';
    }
    final paid = f.clients.where((c) => c.status == 'paid').length;
    return '$paid settled. Nothing is waiting on you here, which is rarer than it sounds.';
  }

  static String? forSettings(ScreenFacts f) {
    if (!f.hasProfile) return null;
    if (f.clients.isEmpty) {
      return 'Your profile is set but there are no clients yet, so there is '
          'nothing for me to keep track of.';
    }
    return null;
  }

  /// Picks something for the chat screen, where there is no screen specific data
  /// to comment on yet.
  static String? forChat(ScreenFacts f) {
    if (f.hasProfile && !f.hasRecords) {
      return 'I know your goals but I have nothing to check them against yet. '
          'Add a client and I can start tracking who owes you what.';
    }
    return null;
  }

  /// Picks a line at random, so a screen that is visited often does not read like
  /// a recorded message.
  static String? vary(List<String?> options, int seed) {
    final present = options.whereType<String>().toList();
    if (present.isEmpty) return null;
    return present[math.Random(seed).nextInt(present.length)];
  }
}

/// The slice of state the guide is allowed to look at.
class ScreenFacts {
  ScreenFacts({
    this.clients = const [],
    this.received = const {},
    this.deadlines = const [],
    this.payments = const [],
    this.hasProfile = false,
  });

  final List<Client> clients;

  /// Money received per client id. Empty is treated as nothing received, so a
  /// caller that has no ledger yet still gets sensible balances.
  final Map<int, double> received;

  /// Open deadlines, soonest first.
  final List<Deadline> deadlines;

  /// Payments recorded, newest first.
  final List<Payment> payments;

  final bool hasProfile;

  /// What a client still owes. Zero for a client with no id or no amount.
  double balanceOf(Client c) => c.id == null ? 0 : c.balanceWith(received[c.id!] ?? 0);

  /// Everything anyone still owes, across all clients.
  double get outstanding => clients.fold(0.0, (a, c) => a + balanceOf(c));

  /// Deadlines are records too. Without this, a user who added their first
  /// deadline and no clients yet counted as having nothing.
  bool get hasRecords =>
      clients.isNotEmpty || deadlines.isNotEmpty || payments.isNotEmpty;
}
