import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../attention.dart';
import '../currency.dart';
import '../human_date.dart';
import '../mascot/mascot.dart';
import '../models.dart';
import '../motivation.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

/// How far a row's separators start from the left edge, so they line up under
/// the text rather than under the icon beside it: row padding, badge, gap.
///
/// Named as the three tokens it is rather than as the sum, because a sum is
/// three numbers that have to be found again by anyone who wants to know why it
/// is that wide.
const double _rowTextInset = KoruSpace.row + KoruSize.badge + KoruSpace.md;

/// How far the follow-up button on an attention row is indented.
///
/// The sum of the three things in front of it rather than a number of its own,
/// so moving any of them moves this with it instead of leaving a button sitting
/// half under the text above it.
const double _followUpInset = KoruSize.badge + KoruSpace.md + KoruSpace.lg;

/// What needs doing today.
///
/// The screen the app exists for. Everything else is a place to look at the
/// records; this is the one that answers "what should I do right now" without
/// the user having to open anything.
///
/// Built on [attentionProvider] rather than recomputing. The same list already
/// feeds the notification, the widget and the launcher badge, so the three can
/// never disagree about what is urgent, and every write invalidates one
/// provider rather than three computations.
///
/// The shape is the shape of the morning: a greeting and the date, what the
/// day is worth in money, then the work in the order it should be done, then
/// the projects that have gone quiet, and one line to close on. Every state —
/// waiting, broken, empty, full — keeps the same frame so the screen never
/// rearranges itself under the reader.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(attentionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Today'),
        backgroundColor: KoruColors.cream,
        surfaceTintColor: KoruColors.nothing,
      ),
      backgroundColor: KoruColors.cream,
      body: KoruSettle(
        child: items.when(
          loading: () => _scroll(ref, const [
            _HeroHeader(),
            _Waiting(),
          ]),
          error: (e, _) => _scroll(ref, [
            const _HeroHeader(),
            _Broken(onRetry: () => ref.invalidate(attentionProvider)),
          ]),
          data: (list) {
            if (list.isEmpty) {
              return _scroll(ref, [_HeroHeader(items: list), const _AllClear()]);
            }
            final overdue =
                list.where((i) => i.kind == AttentionKind.overdueMoney);
            final dueToday = list.where((i) => i.kind == AttentionKind.dueToday);
            final events =
                list.where((i) => i.kind == AttentionKind.eventToday);
            final rest = list
                .where((i) =>
                    i.kind != AttentionKind.overdueMoney &&
                    i.kind != AttentionKind.dueToday &&
                    i.kind != AttentionKind.eventToday)
                .toList();

            return _scroll(ref, [
              _HeroHeader(items: list),
              _Summary(items: list),
              const SizedBox(height: 24),
              if (overdue.isNotEmpty)
                KoruSection(
                  label: 'Overdue',
                  hint: 'Past its date and still unpaid.',
                  dividerIndent: _rowTextInset,
                  children: [
                    for (final i in overdue) _AttentionRow(item: i),
                  ],
                ),
              if (dueToday.isNotEmpty)
                KoruSection(
                  label: 'Due today',
                  hint: 'Finish these today.',
                  dividerIndent: _rowTextInset,
                  children: [
                    for (final i in dueToday) _AttentionRow(item: i),
                  ],
                ),
              if (events.isNotEmpty)
                KoruSection(
                  label: 'Happening today',
                  hint: 'Places to be.',
                  dividerIndent: _rowTextInset,
                  children: [
                    for (final i in events) _AttentionRow(item: i),
                  ],
                ),
              if (rest.isNotEmpty)
                KoruSection(
                  label: 'Coming up',
                  hint: 'Not urgent yet.',
                  dividerIndent: _rowTextInset,
                  children: [
                    for (final i in rest) _AttentionRow(item: i),
                  ],
                ),
              const _ProjectGlance(),
              const _MorningLine(),
            ]);
          },
        ),
      ),
    );
  }

  /// The one scroll view, so every state pulls down to refresh the same way.
  ///
  /// Always scrollable even when the content is short, because a list that
  /// fits on the screen cannot otherwise be dragged far enough to reach the
  /// refresh — and the empty morning is exactly when a pull to check again is
  /// most likely.
  Widget _scroll(WidgetRef ref, List<Widget> children) {
    return RefreshIndicator(
      onRefresh: () async {
        ref
          ..invalidate(attentionProvider)
          ..invalidate(clientsProvider)
          ..invalidate(openDeadlinesProvider);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        // The shared page padding, rather than the same four numbers written
        // out here. It was already 20/10/20/40, so nothing moved.
        padding: const EdgeInsets.fromLTRB(
          KoruSpace.gutter,
          KoruSpace.sml,
          KoruSpace.gutter,
          KoruSpace.tail,
        ),
        children: children,
      ),
    );
  }
}

/// The greeting, the date, and where the day stands.
///
/// The header is the one part of the screen that does not change between
/// states, which is the point: the date is known while the list is still being
/// worked out, so the screen arrives whole and the data catches up underneath
/// it. The brief under the greeting is the same sentence the notification uses,
/// so what the user was told outside the app and what they read inside it can
/// never disagree.
class _HeroHeader extends StatelessWidget {
  const _HeroHeader({this.items});

  /// Null while the attention list is still loading.
  final List<AttentionItem>? items;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final known = items;
    final brief = known == null ? '' : Attention.headline(known);
    return KoruScreenHeader(
      eyebrow: formatDay(now, now, style: DateStyle.short),
      title: _greetingFor(now),
      subtitle: brief.isEmpty ? null : brief,
      trailing: const KoruMascot(size: 54),
    );
  }

  /// Time of day, in the register the rest of the app talks in.
  static String _greetingFor(DateTime at) {
    if (at.hour < 12) return 'Good morning';
    if (at.hour < 18) return 'Good afternoon';
    return 'Good evening';
  }
}

/// The wait, said out loud rather than shown as a bare ring.
class _Waiting extends StatelessWidget {
  const _Waiting();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: KoruSpace.xxxl * 2),
      child: KoruLoading(label: 'Working out what is due'),
    );
  }
}

/// A failure the user can retry from, with the same retry the error view has
/// always had — plus the pull-down, which now reaches every state.
class _Broken extends StatelessWidget {
  const _Broken({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: KoruSpace.xxxl),
      child: KoruErrorView(onRetry: onRetry, what: 'work out what is due'),
    );
  }
}

/// The one figure worth looking at before anything else: what is still owed,
/// and how much of it is late.
class _Summary extends ConsumerWidget {
  const _Summary({required this.items});

  final List<AttentionItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clients = ref.watch(clientsProvider).valueOrNull ?? const <Client>[];
    final received =
        ref.watch(receivedTotalsProvider).valueOrNull ?? const <int, double>{};
    final overdue =
        items.where((i) => i.kind == AttentionKind.overdueMoney).length;

    double owed = 0;
    for (final c in clients) {
      final id = c.id;
      if (id == null) continue;
      final balance = c.balanceWith(received[id] ?? 0);
      if (balance > 0) owed += balance;
    }
    final symbol = ref.watch(currencyProvider).valueOrNull?.symbol ?? 'AED';

    return KoruCard(
      padding: const EdgeInsets.all(KoruSpace.card),
      child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('STILL OWED', style: KoruType.label),
                  const SizedBox(height: KoruSpace.xsm),
                  Text(
                    '$symbol ${_plain(owed)}',
                    style: KoruType.stat,
                  ),
                ],
              ),
            ),
            if (overdue > 0)
              KoruPill(
                label: '$overdue overdue',
                color: KoruColors.clay,
                background: KoruColors.claySoft,
                icon: Icons.error_outline,
              ),
          ],
      ),
    );
  }

  static String _plain(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}

/// One thing that needs doing, and the way to do it.
///
/// Rows sit on one surface with hairlines between them rather than each in a
/// box of its own: a stack of outlined cards makes every item look like a
/// separate decision, and a morning with six of them reads as six problems
/// instead of one list. The icon says what kind of thing it is — late money in
/// clay, today's work in gold, a place to be in leaf, and the quiet greys for
/// anything that can wait — so the eye can sort the list before reading it.
class _AttentionRow extends ConsumerWidget {
  const _AttentionRow({required this.item});

  final AttentionItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tone = _toneFor(item.kind);
    final link = _followUpLink(ref);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KoruSpace.row,
        vertical: KoruSpace.mdl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KoruIconBadge(
                icon: tone.icon,
                color: tone.tint,
                background: tone.fill,
              ),
              const SizedBox(width: KoruSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title, style: KoruType.rowTitle),
                    const SizedBox(height: KoruSpace.xxs),
                    Text(item.detail, style: KoruType.bodyCompact),
                  ],
                ),
              ),
            ],
          ),
          if (link != null) ...[
            const SizedBox(height: KoruSpace.xs),
            // Indented to the text, not the icon, so the button reads as part
            // of this row's words rather than as a new item in the list.
            Padding(
              padding: const EdgeInsets.only(left: _followUpInset),
              child: _FollowUpButton(link: link),
            ),
          ],
        ],
      ),
    );
  }

  /// What a row of this kind looks like: the icon and the pair of colours
  /// behind it. Measured pairs from the palette, so both brightnesses hold.
  static ({IconData icon, Color tint, Color fill}) _toneFor(
          AttentionKind kind) =>
      switch (kind) {
        AttentionKind.overdueMoney => (
            icon: Icons.account_balance_wallet_outlined,
            tint: KoruColors.clay,
            fill: KoruColors.claySoft,
          ),
        AttentionKind.dueToday => (
            icon: Icons.flag_outlined,
            tint: KoruColors.gold,
            fill: KoruColors.goldSoft,
          ),
        AttentionKind.eventToday => (
            icon: Icons.event_outlined,
            tint: KoruColors.leaf,
            fill: KoruColors.leafSoft,
          ),
        AttentionKind.dueSoon => (
            icon: Icons.schedule,
            tint: KoruColors.inkSoft,
            fill: KoruColors.surfaceAlt,
          ),
        AttentionKind.eventSoon => (
            icon: Icons.event_outlined,
            tint: KoruColors.inkSoft,
            fill: KoruColors.surfaceAlt,
          ),
        AttentionKind.stalledProject => (
            icon: Icons.work_outline,
            tint: KoruColors.inkSoft,
            fill: KoruColors.surfaceAlt,
          ),
      };

  /// The WhatsApp link for this item, or null when there is nothing to send.
  Client? _client(AttentionItem i, WidgetRef ref) {
    if (i.clientId == null) return null;
    final list = ref.watch(clientsProvider).valueOrNull ?? const <Client>[];
    for (final c in list) {
      if (c.id == i.clientId) return c;
    }
    return null;
  }

  String? _followUpLink(WidgetRef ref) {
    final c = _client(item, ref);
    if (c == null) return null;
    return c.whatsappLink(message: followUpMessage(c, item.owing));
  }
}

/// The polite-but-clear message, built once so the wording is testable rather
/// than living inside a widget.
///
/// Two rules. It names the figure, because "about the invoice" makes the user
/// look it up and a chase that needs preparation never happens. And it does not
/// apologise, because an apology for being owed money is a strange thing to send.
String followUpMessage(Client c, double? owing) {
  final who = c.name.trim();
  if (owing == null || owing <= 0) {
    return 'Hi $who, a quick one about an outstanding invoice.';
  }
  final money = owing.toStringAsFixed(2);
  return 'Hi $who, a quick reminder that \u{00A3}$money is still outstanding. '
      'Happy to resend the invoice if useful.';
}

class _FollowUpButton extends StatelessWidget {
  const _FollowUpButton({required this.link});

  /// Built by the row, which already has the client in hand.
  final String link;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => _open(context, link),
      icon: const Icon(Icons.chat_bubble_outline_rounded,
          size: KoruSize.iconSm),
      label: const Text('Follow up on WhatsApp'),
      style: TextButton.styleFrom(
        backgroundColor: KoruColors.leafSoft,
        foregroundColor: KoruColors.leaf,
        padding: const EdgeInsets.symmetric(
          horizontal: KoruSpace.mdl,
          vertical: KoruSpace.xsm,
        ),
        visualDensity: VisualDensity.compact,
        textStyle: KoruType.badge.copyWith(fontWeight: FontWeight.w700),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(KoruRadius.pill)),
        ),
      ),
    );
  }

  /// Opens WhatsApp with the message typed out; the user presses send.
  ///
  /// The app never sends anything itself. That is why this needs no API key,
  /// no business account and no network permission of its own — the same deal
  /// as tapping an email address.
  Future<void> _open(BuildContext context, String link) async {
    final uri = Uri.parse(link);
    var launched = false;
    try {
      launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WhatsApp is not installed on this device.')),
      );
    }
  }
}

/// The projects, at a glance.
///
/// Here because the user's own framing was clients, payments and projects, and a
/// Today screen that only counts money would answer half the question. Sorted so
/// the thing that has not moved comes first, which is the one worth looking at.
class _ProjectGlance extends ConsumerWidget {
  const _ProjectGlance();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsProvider).valueOrNull ?? const <Project>[];
    if (projects.isEmpty) return const SizedBox.shrink();

    final stalled = projects.where((p) => _isStalled(p)).toList();
    final shown = stalled.isEmpty ? projects.take(3).toList() : stalled.take(3).toList();

    return KoruSection(
      label: 'Projects going quiet',
      hint: stalled.isEmpty ? 'Nothing has gone stale.' : 'Not touched in a while.',
      dividerIndent: _rowTextInset,
      children: [
        for (final p in shown) _ProjectRow(project: p),
      ],
    );
  }

  /// Not touched for a fortnight.
  ///
  /// Chosen rather than a week because a project somebody works on every Sunday
  /// would otherwise be shouted at every Monday.
  static bool _isStalled(Project p) {
    final updated = DateTime.tryParse(p.updated.isEmpty ? p.created : p.updated);
    if (updated == null) return false;
    return DateTime.now().difference(updated).inDays >= 14;
  }
}

/// One project on the glance: what it is, the last note, how far along.
class _ProjectRow extends StatelessWidget {
  const _ProjectRow({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    final personal = project.isPersonal;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KoruSpace.row,
        vertical: KoruSpace.mdl,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KoruIconBadge(
            icon: personal ? Icons.favorite_outline : Icons.work_outline,
            color: personal ? KoruColors.clay : KoruColors.leaf,
            background: personal ? KoruColors.claySoft : KoruColors.leafSoft,
          ),
          const SizedBox(width: KoruSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(project.name, style: KoruType.rowTitle),
                if (project.progressNote != null &&
                    project.progressNote!.isNotEmpty) ...[
                  const SizedBox(height: KoruSpace.xxs),
                  Text(
                    project.progressNote!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: KoruType.caption,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: KoruSpace.md),
          Text(
            '${(project.progress * 100).round()}%',
            style: KoruType.rowTitleCompact.copyWith(
              color: KoruColors.inkSoft,
            ),
          ),
        ],
      ),
    );
  }
}

/// The all-clear, on the same surface the rest of the app uses for an empty
/// state, and in the green that means settled rather than the grey that means
/// nothing was ever here.
class _AllClear extends StatelessWidget {
  const _AllClear();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: KoruSpace.xs),
      child: EmptyHint(
        icon: Icons.check_circle_outline,
        tint: KoruColors.leaf,
        tintBg: KoruColors.leafSoft,
        title: 'Nothing needs you today',
        body: 'Nothing overdue, nothing due, no calls. Say "add client Bilal '
            'for 2000" in Talk when something comes in.',
      ),
    );
  }
}

/// The one quiet line at the foot of the morning.
///
/// Last rather than first, on purpose. The reason to open this app is what is
/// overdue, and a quote in the opening position pushes that down the screen;
/// down here it reads as a closing thought, seen once the work has been. Italic
/// and low-contrast so it reads as an aside rather than another task, and it
/// carries no interaction because there is nothing to do with it.
class _MorningLine extends StatelessWidget {
  const _MorningLine();

  @override
  Widget build(BuildContext context) {
    final q = quoteFor(DateTime.now());
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: KoruSpace.xxs),
      padding: const EdgeInsets.only(top: KoruSpace.xl),
      decoration: BoxDecoration(
        border: Border(top: KoruBorders.hairline()),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            q.text,
            style: KoruType.bodyCompact.copyWith(
              fontStyle: FontStyle.italic,
              height: 1.55,
            ),
          ),
          const SizedBox(height: KoruSpace.xsm),
          Text(q.by, style: KoruType.micro),
        ],
      ),
    );
  }
}
