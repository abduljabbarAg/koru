import 'models.dart';

/// Something worth interrupting the user about.
///
/// One list, computed the same way every time, because the widget, the
/// notification and the badge all have to agree. Three surfaces showing three
/// different ideas of "what needs you" is worse than one surface showing the
/// right thing, and it is the kind of drift that only shows up once a client has
/// been overdue for a month and the launcher says one number while the app says
/// another.
enum AttentionKind {
  /// Money owed, past its date.
  overdueMoney,

  /// Work due today.
  dueToday,

  /// Work due soon, not yet urgent.
  dueSoon,

  /// A project that has not been touched in a while.
  stalledProject,
}

/// Why this matters, in one sentence, written to be read on a lock screen.
class AttentionItem {
  final AttentionKind kind;
  final String title;
  final String detail;

  /// Where tapping should land.
  final AttentionTarget target;

  /// How pressing this is, 0 to 1. Used to sort, not to colour anything: the
  /// worst thing is always first.
  final double weight;

  const AttentionItem({
    required this.kind,
    required this.title,
    required this.detail,
    required this.target,
    this.weight = 0.5,
  });
}

/// Where the app should open when a thing is tapped.
///
/// Plain data rather than a callback, because the notification that fires while
/// the app is closed has to survive the process being killed and rebuilt. It
/// carries this across that boundary; it cannot carry a closure.
enum AttentionTarget {
  client,
  deadline,
  project,
  chat,
}

/// Decides what is worth saying out loud.
///
/// Pure and synchronous, so every rule here is testable without a database, a
/// widget tree, a notification channel or a device clock. [today] is passed in
/// for the same reason the rest of the app passes it around: the answer must be
/// checkable at a known date rather than only ever "correct" at whichever
/// moment the test happened to run.
class Attention {
  const Attention._();

  /// A project untouched for this long is probably stuck rather than quiet.
  static const stalledAfter = Duration(days: 14);

  /// How far ahead counts as "soon".
  static const soonWindow = Duration(days: 3);

  static List<AttentionItem> build({
    required List<Client> clients,
    required List<Deadline> deadlines,
    required Map<int, double> received,
    List<Project> projects = const [],
    DateTime? today,
  }) {
    final now = today ?? DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    final out = <AttentionItem>[];

    double balanceOf(Client c) =>
        c.id == null ? 0 : c.balanceWith(received[c.id!] ?? 0);

    // Money first, and overdue money before merely due money.
    for (final c in clients) {
      if (!c.isOverdueOn(now)) continue;
      final owing = balanceOf(c);
      if (owing <= 0) continue;
      out.add(AttentionItem(
        kind: AttentionKind.overdueMoney,
        title: '${c.name} owes you',
        detail: '${owing.toStringAsFixed(0)} overdue since ${c.parsedDue?.toIso8601String().substring(0, 10) ?? 'its due date'}',
        target: AttentionTarget.client,
        weight: 1.0,
      ));
    }

    for (final d in deadlines) {
      if (d.done) continue;
      final due = DateTime.tryParse(d.due);
      if (due == null) continue;
      final dueMidnight = DateTime(due.year, due.month, due.day);
      final days = dueMidnight.difference(midnight).inDays;

      if (days < 0) {
        out.add(AttentionItem(
          kind: AttentionKind.dueToday,
          title: d.title,
          detail: '${-days} day${days == -1 ? '' : 's'} overdue',
          target: AttentionTarget.deadline,
          weight: 0.95,
        ));
      } else if (days == 0) {
        out.add(AttentionItem(
          kind: AttentionKind.dueToday,
          title: d.title,
          detail: 'Due today',
          target: AttentionTarget.deadline,
          weight: 0.9,
        ));
      } else if (days <= soonWindow.inDays) {
        out.add(AttentionItem(
          kind: AttentionKind.dueSoon,
          title: d.title,
          detail: 'Due in $days day${days == 1 ? '' : 's'}',
          target: AttentionTarget.deadline,
          weight: 0.4 + (days / soonWindow.inDays) * 0.2,
        ));
      }
    }

    for (final p in projects) {
      if (p.status != 'active') continue;
      final touched = DateTime.tryParse(p.updated);
      if (touched == null) continue;
      final quiet = midnight.difference(
              DateTime(touched.year, touched.month, touched.day))
          .inDays;
      if (quiet < stalledAfter.inDays) continue;
      out.add(AttentionItem(
        kind: AttentionKind.stalledProject,
        title: p.name,
        detail: 'No note for $quiet days',
        target: AttentionTarget.project,
        // Deliberately below money and deadlines. A quiet project is a
        // thought, not a problem, and interrupting the user about one is how a
        // helper starts getting swiped away.
        weight: 0.2,
      ));
    }

    out.sort((a, b) => b.weight.compareTo(a.weight));
    return out;
  }

  /// One line for a notification.
  ///
  /// Counts rather than lists, on purpose: a notification that names five people
  /// is unread on arrival, and a notification that says "3 people owe you money"
  /// gets acted on. The app is one tap away for the detail.
  static String headline(List<AttentionItem> items) {
    if (items.isEmpty) return '';
    final overdue = items.where((i) => i.kind == AttentionKind.overdueMoney).length;
    final dueToday = items.where((i) => i.kind == AttentionKind.dueToday).length;
    final other = items.length - overdue - dueToday;

    final parts = <String>[];
    if (overdue > 0) {
      parts.add('$overdue client${overdue == 1 ? '' : 's'} owe${overdue == 1 ? 's' : ''} you');
    }
    if (dueToday > 0) {
      parts.add('$dueToday thing${dueToday == 1 ? '' : 's'} due now');
    }
    if (other > 0) parts.add('$other more');
    return parts.join(' · ');
  }

  /// The one line shown on a lock screen, and the most useful thing on it.
  static String top(List<AttentionItem> items) =>
      items.isEmpty ? '' : '${items.first.title}: ${items.first.detail}';
}