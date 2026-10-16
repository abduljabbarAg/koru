import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

/// The first screen a returning user sees: why the app wants anything at all.
///
/// A permission prompt with no explanation reads as an app asking for things it
/// has not earned. The system dialog is also a dead end — decline, and there is
/// no second chance to find out what was lost. This is the screen that says it
/// first, in plain words, before any system dialog appears.
///
/// Every permission here is optional. The app records work, money and messages
/// fully without one of them, and the worst outcome is a reminder that never
/// arrives — which is said out loud rather than implied.
class PermissionsIntroScreen extends ConsumerStatefulWidget {
  const PermissionsIntroScreen({required this.onDone, super.key});

  final VoidCallback onDone;

  @override
  ConsumerState<PermissionsIntroScreen> createState() =>
      _PermissionsIntroScreenState();
}

class _PermissionsIntroScreenState
    extends ConsumerState<PermissionsIntroScreen> {
  final PageController _pages = PageController();
  final int _page = 0;

  static const _asks = [
    _Ask(
      icon: Icons.notifications_outlined,
      title: 'Reminders',
      subtitle: 'Not in your face',
      body:
          'A morning line — who is overdue, what is due today — and a nudge before '
          'a deadline passes. That is all it is used for.',
      priceOfNo: 'No reminders. You check the app yourself, as you do now.',
    ),
    _Ask(
      icon: Icons.calendar_today_outlined,
      title: 'Calendar',
      subtitle: 'Optional',
      body:
          'If you want it, due dates and milestones can be mirrored into your '
          "phone's own calendar, so your week shows the work as well as the money.",
      priceOfNo:
          'Nothing. The calendar inside Koru is the real one and works without this.',
    ),
    _Ask(
      icon: Icons.event_available_outlined,
      title: 'Staying awake',
      subtitle: 'Some phones, not all',
      body:
          'Phone makers vary. On some models the system quietly stops background '
          'apps, which silences any reminder you have not opened. Two settings stop '
          'that happening.',
      priceOfNo:
          'Reminders arrive only while the app is open. Mostly fine, occasionally not.',
    ),
  ];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < _asks.length - 1) {
      _pages.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    _continue();
  }

  Future<void> _continue() async {
    // Asked here, from a screen a person chose to leave. The old flow fired them
    // four seconds after the splash, by snackbar, which is both easy to miss and
    // impossible to understand as a reason: the explanation was gone by the time
    // the dialog opened on top of it.
    final messenger = ScaffoldMessenger.maybeOf(context);
    await requestHealthPermissions(ref, messenger: messenger);
    if (!mounted) return;
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final ask = _asks[_page];
    final last = _page == _asks.length - 1;

    return Scaffold(
      backgroundColor: KoruColors.cream,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              KoruSpace.xxl, KoruSpace.xl, KoruSpace.xxl, KoruSpace.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const KoruMark(size: 30),
                  const Spacer(),
                  Text('${_page + 1} of ${_asks.length}', style: KoruType.caption),
                ],
              ),
              const Spacer(flex: 2),
              Container(
                padding: const EdgeInsets.all(KoruSpace.lg),
                decoration: BoxDecoration(
                  color: KoruColors.leafSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  ask.icon,
                  size: 46,
                  color: KoruColors.leaf,
                ),
              ),
              const SizedBox(height: KoruSpace.xxl),
              Text(ask.subtitle.toUpperCase(), style: KoruType.label),
              const SizedBox(height: KoruSpace.sm),
              Text(ask.title, style: KoruType.display.copyWith(fontSize: 26)),
              const SizedBox(height: KoruSpace.md),
              Text(ask.body, style: KoruType.bodyStrong),
              const SizedBox(height: KoruSpace.lg),
              // What refusing actually costs. A prompt that never says this is
              // the reason people decline and then wonder later what broke.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                        top: 3, right: KoruSpace.sm + 2),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: KoruColors.inkFaint,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(ask.priceOfNo, style: KoruType.bodySmall),
                  ),
                ],
              ),
              const Spacer(flex: 3),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _next,
                      child: Text(last ? 'Turn on what I need' : 'Next'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: KoruSpace.xs),
              Center(
                child: TextButton(
                  onPressed: () {
                    // Not now is a real answer. Recorded so the app stops asking,
                    // and the permission can still be granted later from Settings.
                    widget.onDone();
                  },
                  style: TextButton.styleFrom(foregroundColor: KoruColors.inkFaint),
                  child: const Text('Not now'),
                ),
              ),
              const SizedBox(height: KoruSpace.xs),
              Center(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: KoruSpace.sm),
                  child: Text(
                    'The app works fully without any of this.',
                    textAlign: TextAlign.center,
                    style: KoruType.bodySmall.copyWith(fontSize: 12.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Ask {
  const _Ask({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.priceOfNo,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String body;

  /// What happens if the answer is no, stated plainly.
  final String priceOfNo;
}
