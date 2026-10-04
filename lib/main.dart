import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'onboarding.dart';
import 'screens/business.dart';
import 'screens/chat.dart';
import 'screens/fitness.dart';
import 'screens/settings.dart';
import 'state.dart';
import 'theme.dart';
import 'widgets.dart';

void main() {
  runApp(const ProviderScope(child: KoruApp()));
}

class KoruApp extends ConsumerWidget {
  const KoruApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Koru',
      debugShowCheckedModeBanner: false,
      theme: buildKoruTheme(),
      home: const RootGate(),
    );
  }
}

/// Decides once, at startup, between onboarding and the app.
class RootGate extends ConsumerStatefulWidget {
  const RootGate({super.key});

  @override
  ConsumerState<RootGate> createState() => _RootGateState();
}

class _RootGateState extends ConsumerState<RootGate> {
  bool? _ready;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final store = await ref.read(storeProvider.future);
    final done = await store.onboarded;
    if (!mounted) return;
    setState(() {
      _ready = true;
      _done = done;
    });
    ref.read(onboardedProvider.notifier).state = done;
  }

  @override
  Widget build(BuildContext context) {
    if (_ready == null) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              KoruMark(size: 46),
              SizedBox(height: 20),
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: KoruColors.leaf),
              ),
            ],
          ),
        ),
      );
    }
    if (!_done) return const OnboardingScreen();
    return const HomeShell();
  }
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _tab = 0;

  static const _pages = [ChatScreen(), BusinessScreen(), FitnessScreen(), SettingsScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _tab, children: _pages),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: KoruColors.surface,
          border: Border(top: BorderSide(color: KoruColors.line)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 62,
            child: Row(
              children: [
                _tabButton(0, Icons.forum_outlined, Icons.forum_rounded, 'Talk'),
                _tabButton(1, Icons.work_outline_rounded, Icons.work_rounded, 'Business'),
                _tabButton(2, Icons.fitness_center_outlined, Icons.fitness_center_rounded, 'Fitness'),
                _tabButton(3, Icons.settings_outlined, Icons.settings_rounded, 'Settings'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabButton(int i, IconData off, IconData on, String label) {
    final sel = _tab == i;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tab = i),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(sel ? on : off,
                size: 22, color: sel ? KoruColors.leaf : KoruColors.inkFaint),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                  color: sel ? KoruColors.leaf : KoruColors.inkFaint,
                )),
          ],
        ),
      ),
    );
  }
}