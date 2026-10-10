import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'mascot/mascot.dart';
import 'onboarding.dart';
import 'screens/business.dart';
import 'screens/chat.dart';
import 'screens/settings.dart';
import 'state.dart';
import 'theme.dart';

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

/// Decides once, at startup, between the splash, onboarding and the app.
///
/// The splash used to be a bare spinner with a glyph in it. It now shows Koru
/// himself, because the first thing a person sees should be the thing they are
/// about to talk to.
class RootGate extends ConsumerStatefulWidget {
  const RootGate({super.key});

  @override
  ConsumerState<RootGate> createState() => _RootGateState();
}

class _RootGateState extends ConsumerState<RootGate> {
  bool? _ready;
  bool _splashDone = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final store = await ref.read(storeProvider.future);
    final done = await store.onboarded;
    if (!mounted) return;
    setState(() => _ready = true);
    ref.read(onboardedProvider.notifier).state = done;
  }

  void _leaveSplash() {
    if (_splashDone) return;
    setState(() => _splashDone = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_ready == null) {
      return SplashScreen(onDone: _leaveSplash);
    }
    if (!_splashDone) {
      // The store opened faster than the minimum splash time. Keep showing it so
      // the intro never flashes past.
      return SplashScreen(onDone: _leaveSplash);
    }
    // Watched, not cached in a field. Onboarding flips this provider when the
    // user presses Start, and watching it is the only thing that swaps the tree
    // over to the app. Holding a copy in a field meant the last button on the
    // last screen did nothing at all.
    final onboarded = ref.watch(onboardedProvider);
    return onboarded ? const HomeShell() : const OnboardingScreen();
  }
}

/// Koru's own splash.
///
/// Held for a minimum time so the character gets a few idle cycles and a blink
/// in, which is the whole point of animating it. Long enough to read, short
/// enough not to be in the way.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.onDone, this.minimum = const Duration(milliseconds: 1500)});

  final VoidCallback? onDone;
  final Duration minimum;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _fade;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.onDone?.call();
      });

    Future.delayed(widget.minimum, () {
      if (!mounted || _leaving) return;
      setState(() => _leaving = true);
      _fade.forward();
    });
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = CurvedAnimation(parent: _fade, curve: Curves.easeOutCubic);
    return Scaffold(
      backgroundColor: KoruColors.cream,
      body: AnimatedBuilder(
        animation: t,
        builder: (context, child) => Opacity(opacity: 1 - (t.value * 0.85), child: child),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const KoruMascot(size: 148, semanticLabel: 'Koru, your helper'),
              const SizedBox(height: 22),
              Text('Koru', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 6),
              const Text(
                'An assistant that knows your life',
                style: TextStyle(color: KoruColors.inkFaint, fontSize: 14.5),
              ),
              const SizedBox(height: 28),
              const SizedBox(
                width: 120,
                child: LinearProgressIndicator(
                  minHeight: 3,
                  backgroundColor: KoruColors.line,
                  valueColor: AlwaysStoppedAnimation(KoruColors.leaf),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _tab = 0;

  static const _pages = [
    ChatScreen(),
    BusinessScreen(),
    SettingsScreen(),
  ];

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
                _tabButton(2, Icons.settings_outlined, Icons.settings_rounded, 'Settings'),
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
      child: Semantics(
        selected: sel,
        button: true,
        label: label,
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
                    fontSize: 10.5,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                    color: sel ? KoruColors.leaf : KoruColors.inkFaint,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
