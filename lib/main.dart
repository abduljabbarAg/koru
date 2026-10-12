import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'attention_bridge.dart';
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
    // Permissions are asked here, on the splash, before onboarding is ever
    // shown. Asking them after onboarding finished meant a first run that ended
    // with no prompt at all.
    //
    // Deliberately not awaited past the health read, and bounded. A permission
    // prompt opens a system Activity that a person can leave open indefinitely,
    // and holding the start screen hostage to that is exactly how this deadlocked
    // before. The prompts are raised, the flag is written, and the app carries on
    // whatever was granted.
    if (await store.get('asked_permissions') != '1') {
      // Nothing is awaited here at all. requestHealthPermissions reads the
      // health itself, and reading it twice on the way in only added a wait
      // that the splash did not need and, being a timeout, a timer that could
      // outlive the screen asking it.
      unawaited(requestHealthPermissions(ref));
      await store.put('asked_permissions', '1');
    }

    if (done) ref.read(chatProvider.notifier).load();
  }

  /// Checks permissions on first run after an upgrade, and never nags again.
  ///
  /// Asked once, and recorded as asked. A permission prompt that returns on
  /// every launch is how an app teaches people to dismiss dialogs without
  /// reading them, which costs the permission that actually mattered the first
  /// time it came up.
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
  });

  final VoidCallback? onDone;
  final Duration minimum;

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
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

    // One timer, one hard deadline. Deliberately not a chain that waits for
    // anything.
    //
    // The splash used to poll the engine's progress and hold until the model had
    // finished starting. That made the start screen hostage to work happening
    // behind it: a system dialog for battery optimisation, a model copy that
    // took longer than expected, or a health check that never answered, and the
    // app sat there with no way forward and nothing to tap.
    //
    // The splash now leaves on a timer that cannot be starved by any of it, and
    // the engine reports its progress inside the chat instead, where being slow
    // is fine because there is other work to do.
    _timer = Timer(widget.minimum + const Duration(milliseconds: 250), _leave);
  }

  Timer? _timer;

  void _leave() {
    if (!mounted || _leaving) return;
    setState(() => _leaving = true);
    _fade.forward();
  }

  @override
  void dispose() {
    // Cancelled, because a timer that fires after dispose is exactly the kind of
    // thing that logs an exception on a slow start.
    _timer?.cancel();
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
              _EngineLoadingBar(
                progress: ref.watch(chatProvider).engineProgress,
                health: ref.watch(healthProvider).valueOrNull,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The splash's loading bar, which knows what it is loading.
class _EngineLoadingBar extends StatelessWidget {
  const _EngineLoadingBar({this.progress, this.health});

  final int? progress;

  /// Shown only once there is something worth saying about it.
  final KoruHealth? health;

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
        if (health != null && !health!.complete) ...[
          const SizedBox(height: 18),
          // Named individually, because each of these can be refused on its own
          // and "something is not set up" gives the reader nothing to do.
          ...health!.problems.map(
            (problem) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 13, color: KoruColors.gold),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      problem,
                      style: const TextStyle(
                          color: KoruColors.inkSoft, fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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
