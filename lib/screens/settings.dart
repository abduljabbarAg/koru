import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../guide.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'legal.dart';
import 'settings_calendar.dart';
import 'settings_cloud.dart';
import 'settings_context.dart';
import 'settings_data.dart';
import 'settings_engine.dart';
import 'settings_money.dart';
import 'settings_permissions.dart';
import 'settings_privacy.dart';

/// The Settings index.
///
/// This screen used to be all of Settings: ten sections, one ListView, every
/// card, controller and key loader mounted at once whether anyone looked at
/// them or not. It is now a list of pages, each pushed when it is opened, so
/// opening a setting costs one row of building rather than the whole screen,
/// and each setting has a page of its own that can be read on its own.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  /// Grouped the way somebody arrives here, and ordered so the question at the
  /// top is whether anything can answer at all.
  ///
  /// Twelve rows used to sit in seven groups, with three of them ("who answers",
  /// "cloud provider", "what leaves this phone") pulling on the same subject
  /// from three directions, and four legal documents as a group of their own.
  /// Now the same content reads in five groups: the model, the business, the
  /// phone, the data, and everything else behind one door.
  static const _groups = <_Group>[
    _Group('The model', [
      _Entry(
        title: 'Who answers',
        subtitle: 'Whether a model is connected, and which company answers',
        icon: Icons.cloud_outlined,
        page: EngineSettingsScreen(),
      ),
      _Entry(
        title: 'Cloud provider',
        subtitle: 'Which company answers online, its model, and the key',
        icon: Icons.key_outlined,
        page: CloudSettingsScreen(),
      ),
      _Entry(
        title: 'What leaves this phone',
        subtitle: 'The exact text the cloud model receives, and where questions go',
        icon: Icons.visibility_outlined,
        page: PrivacySettingsScreen(),
      ),
    ]),
    _Group('Your business', [
      _Entry(
        title: 'Your context',
        subtitle: 'What Koru knows about you, and the form that changes it',
        icon: Icons.person_outline_rounded,
        page: ContextSettingsScreen(),
      ),
      _Entry(
        title: 'Currency',
        subtitle: 'How amounts are written, and what the model is told',
        icon: Icons.payments_outlined,
        page: CurrencySettingsScreen(),
      ),
      _Entry(
        title: 'Capacity',
        subtitle: 'The most clients you want to carry at once',
        icon: Icons.people_outline_rounded,
        page: CapacitySettingsScreen(),
      ),
      _Entry(
        title: 'Calendar',
        subtitle: 'Copy approved entries to your phone calendar',
        icon: Icons.calendar_month_outlined,
        page: CalendarSettingsScreen(),
      ),
    ]),
    _Group('Phone permissions', [
      _Entry(
        title: 'Permissions',
        subtitle: 'Reminders, background work, your calendar, and asking again',
        icon: Icons.shield_outlined,
        page: PermissionsSettingsScreen(),
      ),
    ]),
    _Group('Data', [
      _Entry(
        title: 'Data',
        subtitle: 'Back up, restore, clear the conversation, or delete it all',
        icon: Icons.save_alt_outlined,
        page: DataSettingsScreen(),
      ),
    ]),
    _Group('About & legal', [
      _Entry(
        title: 'About & legal',
        subtitle: 'About Koru, privacy, terms and the data policy',
        icon: Icons.menu_book_outlined,
        page: LegalHubScreen(),
      ),
    ]),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guide = ref.watch(guideFactsProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: KoruPagePadding(
        bottom: KoruSpace.xxl,
        child: ListView(
          children: [
            KoruGuideBanner(
              speech: guide == null ? null : Guide.forSettings(guide),
              onTap: () {},
            ),
            for (var g = 0; g < _groups.length; g++) ...[
              SectionLabel(_groups[g].title),
              KoruCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < _groups[g].entries.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _row(context, _groups[g].entries[i]),
                    ],
                  ],
                ),
              ),
              // Space between the groups and not after the last one, because the
              // page already ends in its own tail and a trailing gap reads as a
              // card that lost its contents.
              if (g < _groups.length - 1)
                const SizedBox(height: KoruSpace.section),
            ],
          ],
        ),
      ),
    );
  }

  /// Pushes rather than replaces, so the index is still underneath when the
  /// page is closed. Same shape as the Clients tab opening a client.
  Widget _row(BuildContext context, _Entry entry) {
    return KoruRow(
      leading: KoruIconBadge(
        icon: entry.icon,
        color: KoruColors.leaf,
        background: KoruColors.leafSoft,
      ),
      title: entry.title,
      subtitle: entry.subtitle,
      trailing: Icon(
        Icons.chevron_right_rounded,
        size: KoruSize.icon,
        color: KoruColors.inkFaint,
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => entry.page),
      ),
    );
  }
}

/// One row on the index.
///
/// The page is built as a widget here and mounted only when the row is tapped,
/// which is the point of the split: the section's controllers and key reads
/// start in initState, so constructing the widget is cheap and opening Settings
/// no longer runs all of them.
class _Entry {
  const _Entry({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.page,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget page;
}

/// A labelled card of entries. Same SectionLabel-over-Card shape the old
/// single screen used for every section, kept so the index reads as the same
/// app rather than a new one.
class _Group {
  const _Group(this.title, this.entries);

  final String title;
  final List<_Entry> entries;
}
