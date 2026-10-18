import 'package:flutter/material.dart';

import '../main.dart';
import '../theme.dart';
import 'chat.dart';
import 'settings.dart';

/// The app's two standing header controls.
///
/// Talk and Settings used to be the second and fifth tabs. Both are things a
/// person reaches for without first deciding where they are — "ask Koru" and
/// "change a setting" — and putting them in the tab bar spent two of the four
/// slots on chrome while the work itself had nowhere to go. They now sit in the
/// header of the two screens somebody opens to get something done.
///
/// Shared rather than written per screen so that they cannot drift into two
/// icons that mean the same thing on two pages.
class TalkButton extends StatelessWidget {
  const TalkButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Talk to Koru',
      icon: const Icon(Icons.forum_outlined, size: KoruSize.icon),
      color: KoruColors.inkSoft,
      // Pushed rather than swapped in. Talk used to be a tab, and swapping meant
      // leaving the queue to ask a question and losing your place in it; a push
      // leaves the queue underneath, which is what somebody opening the chat from
      // the middle of their day actually wanted.
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const ChatScreen()),
      ),
    );
  }
}

/// Settings, from a header rather than from the tab bar.
///
/// Deliberate: a new user should reach their first answer without ever opening
/// Settings, and a tab bar is the first thing a new user looks at. Settings is
/// reachable, always, from the two screens they are working in.
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
/// One widget rather than four rows written inline, for the reason [TalkButton]
/// exists: the bar is the one piece of chrome every screen shares, and a set of
/// tab buttons that is built inside a shell cannot be looked at on its own, named
/// in a test, or reasoned about without mounting the whole app to do it.
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
