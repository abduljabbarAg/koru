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
    // Started here rather than from the chat screen. The splash is where the
    // model is actually being unpacked, so it is the only place that can show
    // progress for it, and waiting until the chat screen meant the splash was
    // already gone by the time the slow part began.
    if (done) ref.read(chatProvider.notifier).load();
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
    if (!onboarded) return const OnboardingScreen();
    // Watched from here so the notification is kept up to date for the whole
    // time the app is open, not only while a particular screen happens to be
    // mounted. Watching it inside the chat screen meant the badge went stale the
    // moment the user went to look at their clients.
    ref.watch(attentionPublisher);
    return const HomeShell();
  }
}

/// Koru's own splash.
///
/// Held for a minimum time so the character gets a few idle cycles and a blink
/// in, which is the whole point of animating it. Long enough to read, short
/// enough not to be in the way.
///
/// It is also held while the local engine is actually starting, because that
/// takes tens of seconds on a cold install and the splash is the only honest
/// place to say so. Capped, so a model that never arrives still lets the user in
/// to read the error rather than stranding them on a progress bar forever.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({
    super.key,
    this.onDone,
    this.minimum = const Duration(milliseconds: 1500),
    this.holdForEngine = const Duration(seconds: 25),
  });

  final VoidCallback? onDone;
  final Duration minimum;

  /// Longest the splash will stay for the engine before giving up on it.
  final Duration holdForEngine;

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade;
  bool _leaving = false;
  Duration _waited = Duration.zero;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.onDone?.call();
      });

    _tick();
  }

  /// Waits for the minimum, then for the engine if one is warming.
  void _tick() {
    Future.delayed(widget.minimum, () => _ready());
  }

  /// Leaves once the engine has finished, or once the cap is reached.
  void _ready() {
    if (!mounted || _leaving) return;
    final progress = ref.read(chatProvider).engineProgress;
    if (progress != null && _waited < widget.holdForEngine) {
      _waited += const Duration(milliseconds: 400);
      Future.delayed(const Duration(milliseconds: 400), _ready);
      return;
    }
    setState(() => _leaving = true);
    _fade.forward();
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
              // Determinate when there is real progress to report, and honest
              // about what it is. The old bar swept forever regardless of
              // whether anything was happening, which is a bar that tells you
              // nothing while the app is doing its slowest work.
              _EngineLoadingBar(progress: ref.watch(chatProvider).engineProgress),
            ],
          ),
        ),
      ),
    );
  }
}

/// The splash's loading bar, which knows what it is loading.
class _EngineLoadingBar extends StatelessWidget {
  const _EngineLoadingBar({this.progress});

  final int? progress;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 120,
          child: LinearProgressIndicator(
            minHeight: 3,
            // Null value means the bar sweeps, which is right when nothing is
            // being reported yet and wrong once it is.
            value: p == null ? null : (p / 100).clamp(0.0, 1.0),
            backgroundColor: KoruColors.line,
            valueColor: const AlwaysStoppedAnimation(KoruColors.leaf),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 16,
          child: Text(
            switch (p) {
              null => 'Getting things ready',
              // Copying half a gigabyte out of the APK is the slow part and it
              // is not obvious why, so say what is happening.
              <8 => 'Unpacking the model on this phone',
              _ => 'Waking the model up  $p%',
            },
            style: const TextStyle(color: KoruColors.inkFaint, fontSize: 12),
          ),
        ),
      ],
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
