import 'package:flutter/material.dart';

import '../main.dart';
import '../theme.dart';
import 'settings.dart';

/// Settings, from a header rather than from a tab or the bar.
///
/// Deliberate: a new user should reach their first answer without ever opening
/// Settings, and a tab bar is the first thing a new user looks at. Settings is
/// reachable, always, from every screen they are working in.
///
/// Talk used to sit beside it as a second icon. It is the floating action now
/// — "Tell Koru" — because a verb belongs where the thumb already is, not in
/// the corner of a header where two small grey icons look the same.
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Settings',
      icon: const Icon(Icons.settings_outlined, size: KoruSize.icon),
      color: KoruColors.inkSoft,
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
      ),
    );
  }
}
/// The bar at the bottom of the app.
///
/// One widget rather than four rows written inline, for the reason
/// [SettingsButton] exists: the bar is the one piece of chrome every screen
/// shares, and a set of tab buttons that is built inside a shell cannot be
/// looked at on its own, named in a test, or reasoned about without mounting
/// the whole app to do it.
///
/// It takes the tabs as an argument rather than importing the list, so the
/// shell decides what the bar contains and this decides how it looks.
class KoruTabBar extends StatelessWidget {
  const KoruTabBar({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  /// The [KoruAppTabs.slot] currently showing.
  final int selected;

  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: KoruColors.surface,
        border: Border(top: KoruBorders.hairline()),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: KoruSpace.xxxl * 2,
          child: Row(
            children: [
              for (final tab in KoruAppTabs.values)
                _button(tab.slot, tab.iconOff, tab.iconOn, tab.label),
            ],
          ),
        ),
      ),
    );
  }

  Widget _button(int slot, IconData off, IconData on, String label) {
    final sel = selected == slot;
    return Expanded(
      child: Semantics(
        selected: sel,
        button: true,
        label: label,
        child: InkWell(
          onTap: () => onSelected(slot),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(sel ? on : off,
                  size: KoruSize.icon,
                  color: sel ? KoruColors.leaf : KoruColors.inkFaint),
              const SizedBox(height: KoruSpace.xxs),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: KoruType.tabLabel.copyWith(
                  fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                  color: sel ? KoruColors.leaf : KoruColors.inkFaint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
