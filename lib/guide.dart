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

  static String? forFitness(ScreenFacts f) {
    if (f.fitness.isEmpty) {
      return 'Nothing logged yet. One weight reading gives me a baseline, two give me a trend.';
    }
    final trend = f.weightTrendPerWeek;
    final latest = f.fitness.first;
    if (trend == null) {
      return 'One reading is a number, not a trend. Log again next week and I can say something useful.';
    }
    final weight = latest.weight;
    final weightText = weight == null ? '' : ' You are ${weight.toStringAsFixed(1)} kg.';

    if (f.bmi != null) {
      final bmi = f.bmi!;
      final band = bmi < 18.5
          ? 'under the healthy range'
          : bmi < 25
              ? 'in the healthy range'
              : bmi < 30
                  ? 'in the overweight range, which is a rough label not a verdict'
                  : 'above the healthy range';
      return 'Your BMI is ${bmi.toStringAsFixed(1)}, $band.$weightText '
          'Trend is ${trend >= 0 ? '+' : ''}${trend.toStringAsFixed(2)} kg a week.';
    }
    return 'Tracking ${f.fitness.length} logs.$weightText '
        'Trend is ${trend >= 0 ? '+' : ''}${trend.toStringAsFixed(2)} kg a week.';
  }

  static String? forSettings(ScreenFacts f) {
    if (!f.hasProfile) return null;
    if (f.fitness.isEmpty && f.clients.isEmpty) {
      return 'Your context is set but there is nothing to learn from yet. '
          'A measurement or a client is what makes this useful.';
    }
    return null;
  }

  /// Picks something for the chat screen, where there is no screen specific data
  /// to comment on yet.
  static String? forChat(ScreenFacts f) {
    if (f.hasProfile && !f.hasRecords) {
      return 'I know your goals but I have nothing to check them against yet. '
          'Log a measurement or add a client.';
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
    this.fitness = const [],
    this.received = const {},
    this.bmi,
    this.hasProfile = false,
  });

  final List<Client> clients;
  final List<FitnessEntry> fitness;

  /// Money received per client id. Empty is treated as nothing received, so a
  /// caller that has no ledger yet still gets sensible balances.
  final Map<int, double> received;
  final double? bmi;
  final bool hasProfile;

  /// What a client still owes. Zero for a client with no id or no amount.
  double balanceOf(Client c) => c.id == null ? 0 : c.balanceWith(received[c.id!] ?? 0);

  /// Everything anyone still owes, across all clients.
  double get outstanding => clients.fold(0.0, (a, c) => a + balanceOf(c));

  bool get hasRecords => fitness.isNotEmpty || clients.isNotEmpty;

  /// Weight change per week, or null when there is not enough history. Needs two
  /// readings at least three days apart, otherwise every visit reports a wild
  /// number from overnight water retention.
  double? get weightTrendPerWeek {
    final dated = <({DateTime day, double kg})>[];
    for (final e in fitness) {
      final kg = e.weight;
      final day = e.parsedDay;
      if (kg == null || day == null) continue;
      dated.add((day: day, kg: kg));
    }
    if (dated.length < 2) return null;
    final newest = dated.first;
    final oldest = dated.last;
    final days = newest.day.difference(oldest.day).inDays;
    if (days < 3) return null;
    return (newest.kg - oldest.kg) / (days / 7.0);
  }
}
