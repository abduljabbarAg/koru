import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../permission_consent.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'permissions_intro.dart';

/// Where permissions live once they have been answered once.
///
/// This page exists because the other half of "asked once, never again" is
/// "and forever after, here". The consent screen is offered at most once per
/// install, which is the right amount of asking and also means that anybody who
/// said no — or who said yes and has since revoked it in system settings — has
/// nowhere in the app to change their mind. That is the dead end this removes.
///
/// It lives in Settings under its own name rather than folded into Privacy,
/// because "what leaves this phone" is a different question from "what is Koru
/// allowed to do on it", and the answer to the second is a set of toggles rather
/// than a page of prose.
class PermissionsSettingsScreen extends ConsumerWidget {
  const PermissionsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final consent = ref.watch(permissionConsentProvider).valueOrNull;
    final health = ref.watch(healthProvider).valueOrNull;
    final calendar = ref.watch(calendarPermissionProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Permissions')),
      body: KoruPagePadding(
        bottom: KoruSpace.xxl,
        child: ListView(
        children: [
          if (consent != null) ...[
            KoruNotice(
              title: 'Where you left off',
              message: consent.summary,
              icon: switch (consent.outcome) {
                ConsentOutcome.granted => Icons.check_circle_rounded,
                ConsentOutcome.declined => Icons.do_not_disturb_on_outlined,
                ConsentOutcome.notAsked => Icons.help_outline_rounded,
              },
              tone: switch (consent.outcome) {
                ConsentOutcome.granted => KoruTones.leaf,
                ConsentOutcome.declined => KoruTones.neutral,
                ConsentOutcome.notAsked => KoruTones.gold,
              },
            ),
          ],
          // About permissions on this device. Deliberately not the engine's
          // name: these are Android grants, and "Local model" above a list of
          // notification toggles would read as a claim about which model is
          // running.
          const SectionLabel('On this device'),
          KoruCard(
            padding: const EdgeInsets.symmetric(vertical: KoruSpace.xsm),
            child: Column(
                children: [
                  _Row(
                    icon: Icons.notifications_outlined,
                    title: 'Reminders',
                    detail: 'A morning line and a nudge before a deadline passes. '
                        'Without this Koru is silent when the app is closed.',
                    granted: health?.notifications,
                  ),
                  const Divider(height: 1),
                  _Row(
                    icon: Icons.battery_saver_outlined,
                    title: 'Background work',
                    detail: 'Stops the system ending Koru in the background to '
                        'save power, which is the usual reason reminders stop.',
                    granted: health?.batteryExempt,
                  ),
                  const Divider(height: 1),
                  _Row(
                    icon: Icons.restart_alt_rounded,
                    title: 'Restart itself',
                    detail: 'Some manufacturers only let Koru start again by '
                        'hand. Phones that do not need this say so.',
                    granted: health?.autostart,
                  ),
                  const Divider(height: 1),
                  _Row(
                    icon: Icons.calendar_today_outlined,
                    title: 'Your calendar',
                    detail: 'Optional. Only so an approved entry can also land '
                        'on the phone\'s own calendar.',
                    granted: calendar,
                  ),
              ],
            ),
          ),
          const SizedBox(height: KoruSpace.section),
          const SectionLabel('Ask again'),
          // The button the whole page is for, and the reason this screen can be
          // found at all. Present whether or not anything is missing, because
          // somebody who has just revoked a permission in system settings is
          // exactly the person who needs it and would not know to look for it.
          KoruCard(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Koru asks once and then stops. Nothing here is lost by '
                    'refusing, and the app works fully without all of it.',
                    style: KoruType.bodyCompact,
                  ),
                  const SizedBox(height: KoruSpace.mdl),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(KoruSize.button),
                    ),
                    onPressed: () => _ask(ref),
                    icon: const Icon(Icons.notifications_active_outlined,
                        size: KoruSize.icon),
                    label: const Text('Ask for what Koru needs'),
                  ),
                  const SizedBox(height: KoruSpace.sm),
                  // The same three pages the first-run screen is made of, so the
                  // reason is never something you have to have already seen to
                  // find. Reading it again is what makes a later yes an informed
                  // one.
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(KoruSize.buttonInCard),
                    ),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PermissionsIntroScreen(
                          onAnswered: (outcome) async {
                            await ref
                                .read(storeProvider)
                                .value
                                ?.put(permissionConsentKey, outcome.name);
                            ref.invalidate(permissionConsentProvider);
                            if (context.mounted) Navigator.of(context).pop();
                          },
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.menu_book_outlined,
                        size: KoruSize.icon),
                    label: const Text('Read what Koru needs, and why'),
                  ),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }

  /// Raises the prompts again, from a place somebody chose to come to.
  ///
  /// Deliberately not gated on anything being missing. A person who has just
  /// turned a permission off in system settings, and a person who wants to hear
  /// the request again, are both answered the same way: the prompts appear.
  Future<void> _ask(WidgetRef ref) async {
    final messenger = ScaffoldMessenger.maybeOf(ref.context);
    await requestHealthPermissions(ref, messenger: messenger);
    ref.invalidate(permissionConsentProvider);
  }
}

/// One permission, and whether it is actually granted right now.
///
/// Null while the platform is still being asked, which is shown as neither
/// granted nor refused. Flashing "Not granted" for the second before the system
/// has answered is how a settings screen teaches people to distrust it.
class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.detail,
    required this.granted,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool? granted;

  @override
  Widget build(BuildContext context) {
    final state = granted == null
        ? 'Checking'
        : granted!
            ? 'On'
            : 'Off';
    final tone = switch (granted) {
      null => KoruTones.neutral,
      true => KoruTones.leaf,
      false => KoruTones.gold,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KoruSpace.row,
        vertical: KoruSpace.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: KoruSize.icon, color: KoruColors.leaf),
          const SizedBox(width: KoruSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: KoruType.rowTitleLarge),
                const SizedBox(height: KoruSpace.xxs),
                Text(detail, style: KoruType.caption),
              ],
            ),
          ),
          const SizedBox(width: KoruSpace.sml),
          KoruPill(
            label: state.toUpperCase(),
            color: tone.ink,
            background: tone.fill,
          ),
        ],
      ),
    );
  }
}
