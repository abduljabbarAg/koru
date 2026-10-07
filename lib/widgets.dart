import 'package:flutter/material.dart';

import 'handoff.dart';
import 'theme.dart';

class KoruMark extends StatelessWidget {
  const KoruMark({super.key, this.size = 28});

  /// Static mark for places with no room to animate, such as a dense list row.
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: KoruColors.leaf,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(Icons.spa_rounded, color: Colors.white, size: size * 0.6),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 2),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
          color: KoruColors.inkFaint,
        ),
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.sub,
    required this.tint,
    required this.tintBg,
  });

  final String label;
  final String value;
  final String? sub;
  final Color tint;
  final Color tintBg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KoruColors.surface,
        borderRadius: BorderRadius.circular(KoruRadius.card),
        border: Border.all(color: KoruColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: tintBg,
              borderRadius: BorderRadius.circular(KoruRadius.pill),
            ),
            child: Text(
              label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: tint),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: KoruColors.ink,
              letterSpacing: -0.6,
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(sub!, style: const TextStyle(fontSize: 13, color: KoruColors.inkFaint)),
          ],
        ],
      ),
    );
  }
}

class EmptyHint extends StatelessWidget {
  const EmptyHint({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: KoruColors.surface,
        borderRadius: BorderRadius.circular(KoruRadius.card),
        border: Border.all(color: KoruColors.line),
      ),
      child: Column(
        children: [
          Icon(icon, size: 30, color: KoruColors.inkFaint),
          const SizedBox(height: 10),
          Text(title,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: KoruColors.ink)),
          const SizedBox(height: 4),
          Text(body,
              textAlign: TextAlign.center,
              style: const TextStyle(color: KoruColors.inkFaint, fontSize: 13, height: 1.4)),
          if (action != null) ...[
            const SizedBox(height: 16),
            action!,
          ],
        ],
      ),
    );
  }
}

/// The escalation card shown when Koru decides a person should answer.
///
/// This replaces a line of text in the chat bubble. The routing layer already
/// knew when to step aside; now there is somewhere to step aside to.
class HandoffCard extends StatelessWidget {
  const HandoffCard({super.key, required this.plan, this.onDismiss});

  final HandoffPlan plan;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final accent = plan.urgent ? KoruColors.clay : KoruColors.gold;
    final accentBg = plan.urgent ? KoruColors.claySoft : KoruColors.goldSoft;

    return Semantics(
      liveRegion: true,
      container: true,
      label: '${plan.headline}. ${plan.body}',
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: KoruColors.surface,
          borderRadius: BorderRadius.circular(KoruRadius.card),
          border: Border.all(color: accent, width: 1.4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: accentBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    plan.urgent ? Icons.emergency_share_rounded : Icons.pan_tool_alt_rounded,
                    size: 19,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    plan.headline,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: KoruColors.ink,
                    ),
                  ),
                ),
                if (onDismiss != null)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded, size: 18, color: KoruColors.inkFaint),
                    onPressed: onDismiss,
                    tooltip: 'Dismiss',
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              plan.body,
              style: const TextStyle(fontSize: 13.5, color: KoruColors.inkSoft, height: 1.45),
            ),
            const SizedBox(height: 14),
            ...plan.resources.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 5, right: 9),
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13.5, color: KoruColors.ink),
                            ),
                            Text(
                              r.detail,
                              style: const TextStyle(fontSize: 12.5, color: KoruColors.inkFaint, height: 1.35),
                            ),
                            Text(
                              '${r.number} - ${r.hours}',
                              style: TextStyle(fontSize: 12.5, color: accent, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

/// Small pill used for statuses and routing badges.
class KoruPill extends StatelessWidget {
  const KoruPill({
    super.key,
    required this.label,
    required this.color,
    required this.background,
    this.icon,
  });

  final String label;
  final Color color;
  final Color background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(KoruRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

/// A titled sheet body used by every add/edit flow, so the five forms in the app
/// stop looking like five different apps.
Future<T?> showKoruSheet<T>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext) builder,
  String? subtitle,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: const BoxDecoration(
          color: KoruColors.cream,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                    color: KoruColors.line, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle,
                  style: const TextStyle(fontSize: 13, color: KoruColors.inkFaint, height: 1.4)),
            ],
            const SizedBox(height: 18),
            Flexible(child: SingleChildScrollView(child: builder(ctx))),
          ],
        ),
      ),
    ),
  );
}

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: KoruColors.ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
}
