import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

/// The polite-but-clear message, built once so the wording is testable rather
/// than living inside a widget.
///
/// Two rules. It names the figure, because "about the invoice" makes the user
/// look it up and a chase that needs preparation never happens. And it does not
/// apologise, because an apology for being owed money is a strange thing to send.
///
/// Lives here rather than on the Today screen because two screens now offer it:
/// the morning queue and the money tab. A chase worded one way on one screen
/// and another way on the other is the kind of small difference nobody notices
/// until two clients are sent two different messages.
String followUpMessage(Client c, double? owing) {
  final who = c.name.trim();
  if (owing == null || owing <= 0) {
    return 'Hi $who, a quick one about an outstanding invoice.';
  }
  final money = owing.toStringAsFixed(2);
  return 'Hi $who, a quick reminder that £$money is still outstanding. '
      'Happy to resend the invoice if useful.';
}

/// The one-tap chase.
///
/// Opens WhatsApp with the message typed out; the user presses send. The app
/// never sends anything itself, which is why this needs no API key, no business
/// account and no network permission of its own — the same deal as tapping an
/// email address.
class FollowUpButton extends StatelessWidget {
  const FollowUpButton({super.key, required this.link});

  /// Built by the row, which already has the client and the figure in hand.
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

  /// Opens WhatsApp with the message ready. Returns nothing and says why it
  /// could not, rather than failing silently: a button that appears to work and
  /// does not is worse than one that says WhatsApp is not installed.
  static Future<void> _open(BuildContext context, String link) async {
    final uri = Uri.parse(link);
    var launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }
    if (!launched && context.mounted) {
      toast(
        context,
        'WhatsApp is not installed on this device.',
      );
    }
  }
}