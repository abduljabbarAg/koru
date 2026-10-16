/// Form controls that are not a field.
///
/// Three stacks, three rows and four date buttons across the app were each built
/// by hand, and a form's rhythm is one of the few things on a phone a person
/// feels without noticing: the gap between two fields should be the same
/// wherever they are.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

/// A stack of fields with one gap between them.
///
/// Five forms across the app were stacking TextFields by hand with `md` between
/// one pair and `sm + 2` between the next, so a form's rhythm changed as you
/// scrolled down it.
class KoruFieldStack extends StatelessWidget {
  const KoruFieldStack({super.key, required this.children, this.gap = KoruSpace.md});

  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(height: gap),
          children[i],
        ],
      ],
    );
  }
}

/// A row of fields, wrapped onto a second line rather than squeezed.
///
/// Two fields side by side is right at this width; three is not, and the third
/// one used to be laid on top of the first.
class KoruFieldRow extends StatelessWidget {
  const KoruFieldRow({super.key, required this.children, this.flex = const [1, 1]});

  final List<Widget> children;

  /// How much of the width each field takes. Longer than [children] and the
  /// extra is ignored; shorter, and the surplus is shared evenly.
  final List<int> flex;

  @override
  Widget build(BuildContext context) {
    final n = children.length;
    final weights = List<int>.generate(n, (i) => i < flex.length ? flex[i] : 1);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < n; i++) ...[
          if (i > 0) const SizedBox(width: KoruSpace.md),
          Expanded(flex: weights[i], child: children[i]),
        ],
      ],
    );
  }
}

/// A control that opens a date picker and shows the date it would pick.
///
/// Four of these existed — invoice date, payment date, deadline date, event date
/// — and each one drew its own outline over the shared button, so the one field
/// that a person touches most in this app was the one with the most variation.
class KoruDateButton extends StatelessWidget {
  const KoruDateButton({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
    required this.onTap,
    this.tone,
  });

  /// What the button is choosing: "Invoiced 4 March 2026".
  final String label;

  final IconData icon;

  /// The formatted date, shown inside the button.
  final String value;

  final VoidCallback onTap;

  /// Paints the button in an accent for the version that is showing something
  /// the app worked out rather than something the user typed.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        style: tone == null
            ? null
            : OutlinedButton.styleFrom(
                foregroundColor: tone,
                side: KoruBorders.accent(tone!),
                backgroundColor: tone!.withValues(alpha: 0.06),
              ),
        icon: Icon(icon, size: KoruSize.icon),
        label: Text('$label $value'),
      ),
    );
  }
}
