import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

/// Mirroring chat-created entries to the phone's own calendar.
///
/// Off by default, and the permission is asked for at the moment the switch is
/// turned on rather than at startup: an app that asks for calendar access
/// before it has shown what it wants it for is an app people say no to. The
/// in-app calendar works either way and needs no permission at all.
class CalendarSettingsScreen extends StatelessWidget {
  const CalendarSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Calendar')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
        children: const [_CalendarSyncCard()],
      ),
    );
  }
}

/// How many clients this person is willing to carry at once, on a page of its
/// own.
///
/// Set during onboarding and changeable here, because the number that was right
/// when you started is not the number that is right after a bad quarter. It is
/// stored as a plain profile value, so changing it touches no schema.
class CapacitySettingsScreen extends StatelessWidget {
  const CapacitySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Capacity')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
        children: const [_CapacityCard()],
      ),
    );
  }
}

class _CalendarSyncCard extends ConsumerStatefulWidget {
  const _CalendarSyncCard();

  @override
  ConsumerState<_CalendarSyncCard> createState() => _CalendarSyncCardState();
}

class _CalendarSyncCardState extends ConsumerState<_CalendarSyncCard> {
  bool _sync = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final store = await ref.read(storeProvider.future);
    final value = await store.get('calendar_sync') == '1';
    if (!mounted) return;
    setState(() {
      _sync = value;
      _loaded = true;
    });
  }

  Future<void> _set(bool value) async {
    // Asked here rather than on first use, so a refusal lands somewhere the
    // user can see it: the switch simply does not turn on, with a sentence
    // saying why, rather than failing silently in the background at save time.
    if (value) {
      final granted = await ref.read(calendarBridgeProvider).requestPermission();
      if (!granted) {
        if (!mounted) return;
        toast(context, 'Your phone refused calendar access, so nothing will '
            'be copied. You can allow it in Android settings.');
        return;
      }
    }
    final store = await ref.read(storeProvider.future);
    await store.put('calendar_sync', value ? '1' : '0');
    if (!mounted) return;
    setState(() => _sync = value);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SwitchListTile(
        value: _sync,
        onChanged: _loaded ? _set : null,
        activeColor: KoruColors.leaf,
        contentPadding: const EdgeInsets.fromLTRB(16, 6, 10, 6),
        title: const Text(
          'Copy new entries to my phone calendar',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        subtitle: Text(
          'When you approve a calendar entry in Talk, Koru also writes it to '
          'the calendar your phone already uses. The copy is one way: deleting '
          'it in your phone calendar does not touch Koru\u2019s.',
          style: TextStyle(fontSize: 12.5, color: KoruColors.inkFaint, height: 1.4),
        ),
      ),
    );
  }
}

class _CapacityCard extends ConsumerWidget {
  const _CapacityCard();

  static const _options = [3, 5, 8, 12];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capacity = ref.watch(capacityProvider).valueOrNull ?? defaultCapacity;
    final underway = ref.watch(clientsProvider).valueOrNull
            ?.where((c) => c.status == 'active' || c.status == 'delivered')
            .length ??
        0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You are carrying $underway.',
              style: TextStyle(fontSize: 13.5, color: KoruColors.ink, height: 1.4),
            ),
            const SizedBox(height: 4),
            Text(
              'Pick the most you can serve properly. Koru tells you when you are '
              'at it, so taking on a sixth client is a decision rather than an '
              'accident.',
              style: TextStyle(fontSize: 12.5, color: KoruColors.inkFaint, height: 1.45),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (final n in _options) ...[
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: InkWell(
                        onTap: () async {
                          final store = await ref.read(storeProvider.future);
                          await store.putNumber('capacity', n.toDouble());
                          ref.invalidate(capacityProvider);
                        },
                        borderRadius: BorderRadius.circular(KoruRadius.field),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: capacity == n ? KoruColors.leafSoft : KoruColors.surface,
                            borderRadius: BorderRadius.circular(KoruRadius.field),
                            border: Border.all(
                              color: capacity == n ? KoruColors.leaf : KoruColors.line,
                              width: capacity == n ? 1.6 : 1,
                            ),
                          ),
                          child: Text(
                            '$n',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: capacity == n ? FontWeight.w700 : FontWeight.w500,
                              color: KoruColors.ink,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
