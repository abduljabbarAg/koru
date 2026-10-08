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
    final today = f.today;
    final overdue = f.clients.where((c) => c.isOverdueOn(today)).toList();
    if (overdue.isNotEmpty) {
      final names = overdue.take(2).map((c) => c.name).join(' and ');
      return overdue.length == 1
          ? '$names is past the due date. That is the easiest money in this list.'
          : '${overdue.length} are past the due date, starting with $names.';
    }

    final unpaid = f.clients.where((c) => c.status == 'delivered').toList();
    if (unpaid.isNotEmpty) {
      final sum = unpaid.fold<double>(0, (a, c) => a + (c.amount ?? 0));
      return 'Work is delivered and ${sum.toStringAsFixed(0)} AED is still unpaid. '
          'Chasing it is worth more than landing anything new right now.';
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

  static String? forLearn(ScreenFacts f) {
    if (f.topics.isEmpty) {
      return 'Nothing on the list. Add whatever you are working through and I will keep it in front of you.';
    }
    final done = f.topics.where((t) => t.progress >= 1).length;
    final active = f.topics.where((t) => t.progress > 0 && t.progress < 1).toList();
    if (active.isEmpty) {
      return '$done finished. Nothing in progress, which is a good moment to start one.';
    }
    // Descending, so "furthest along" means what it says. Sorting ascending
    // here made Koru tell you to start with the topic you had barely touched.
    active.sort((a, b) => b.progress.compareTo(a.progress));
    final leader = active.first;
    return '${active.length} in progress. "${leader.topic}" is furthest along at '
        '${leader.percent}%. Finish that one before starting another.';
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
    this.topics = const [],
    this.bmi,
    this.hasProfile = false,
    DateTime? today,
  }) : today = today ?? DateTime.now();

  final List<Client> clients;
  final List<FitnessEntry> fitness;
  final List<KnowledgeTopic> topics;
  final double? bmi;
  final bool hasProfile;
  final DateTime today;

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
