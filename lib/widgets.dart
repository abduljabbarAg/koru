import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

class KoruMark extends StatelessWidget {
  final double size;
  const KoruMark({super.key, this.size = 28});

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
  final String text;
  const SectionLabel(this.text, {super.key});

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
  final String label;
  final String value;
  final String? sub;
  final Color tint;
  final Color tintBg;

  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.sub,
    required this.tint,
    required this.tintBg,
  });

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
  final IconData icon;
  final String title;
  final String body;

  const EmptyHint({super.key, required this.icon, required this.title, required this.body});

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
              style: const TextStyle(fontWeight: FontWeight.w600, color: KoruColors.ink, fontSize: 15)),
          const SizedBox(height: 4),
          Text(body,
              textAlign: TextAlign.center,
              style: const TextStyle(color: KoruColors.inkFaint, fontSize: 13, height: 1.4)),
        ],
      ),
    );
  }
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