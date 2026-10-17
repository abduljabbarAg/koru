import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'attention.dart';
import 'attention_bridge.dart';
import 'deep_link.dart';
import 'engine.dart';
import 'engine_launch.dart';
import 'mascot/mascot.dart';
import 'onboarding.dart';
import 'permission_consent.dart';
import 'screens/business.dart';
import 'screens/chat.dart';
import 'screens/client_detail.dart';
import 'screens/permissions_intro.dart';
import 'screens/projects.dart';
import 'screens/settings.dart';
import 'screens/today.dart';
import 'state.dart';
import 'theme.dart';

void main() {
  // Read before the first frame rather than inside it, so nothing is ever
  // painted light and then repainted dark a frame later.
  WidgetsFlutterBinding.ensureInitialized();
  KoruColors.setBrightness(PlatformDispatcher.instance.platformBrightness);
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
      darkTheme: buildKoruTheme(brightness: Brightness.dark),
      // Follows the system. A phone set to dark is telling the app something
      // about the hour it is being used in, and making somebody override that
      // every launch is friction for nobody.
      themeMode: ThemeMode.system,
      // Keeps [KoruColors] in step when the phone is switched while the app is
      // open. The palette is app-wide state rather than something read from a
      // context, so nothing else would notice the change.
      builder: (context, child) {
        KoruColors.setBrightness(
          Theme.of(context).brightness == Brightness.dark
              ? Brightness.dark
              : Brightness.light,
        );
        return child ?? const SizedBox.shrink();
      },
      home: const RootGate(),
    );
  }
}

/// Decides once, at startup, between the splash, onboarding, the permission
/// explanation and the app.
///
/// The splash used to be a bare spinner with a glyph in it. It now shows Koru
/// himself, because the first thing a person sees should be the thing they are
/// about to talk to.
class RootGate extends ConsumerStatefulWidget {
  const RootGate({super.key});

  @override
  ConsumerState<RootGate> createState() => _RootGateState();
}

class _RootGateState extends ConsumerState<RootGate> with WidgetsBindingObserver {
  bool? _ready;
  bool _splashDone = false;

  /// Whether the permission explanation still owes this person a look. Null
  /// until the store and the platform have both answered, because deciding this
  /// from the stored flag alone is what hid the screen from every upgrading
  /// user.
  bool? _oweConsent;

  /// Whether the app is currently in the background.
  ///
  /// Tracked rather than acted on directly, because the only thing worth doing
  /// is what happens on the way *back*. Nothing is stopped on the way out: see
  /// [resumeLocalEngine], which is where that decision is written down.
  bool _away = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // First thing in the app, before anything that has to be awaited.
    //
    // The warm-up used to be reached through chatProvider.load(), which could not
    // run until the store was open, onboarding had been checked, and the
    // permission consent had been resolved — three platform round trips before a
    // single byte of engine start. None of that has anything to do with bringing
    // a model up, and all of it happens on every launch. About 3 seconds of
    // engine spawn plus, on a first run, a 248 MB unpack, all of it now spent
    // while the user is reading the splash rather than after they press send.
    //
    // Fire and forget on purpose. Nothing in the UI waits on this; the only
    // thing it delays is the first question, and only for as long as the engine
    // really takes.
    unawaited(ref.read(engineWarmUpProvider.future));

    _check();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final away = state != AppLifecycleState.resumed;
    if (away == _away) return;
    _away = away;
    // Nothing is stopped on the way out. See [resumeLocalEngine] for why, and for
    // what is done instead on the way back in.
    if (away || !mounted) return;
    resumeLocalEngine(ref);
  }

  @override
  void dispose() {
    // Removed before the super call, because the observer list outlives this
    // state object and a late lifecycle change into a disposed gate is an
    // exception in the log of every app switch on the way out.
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _check() async {
    final store = await ref.read(storeProvider.future);
    final done = await store.onboarded;
    if (!mounted) return;
    // Asked, not recorded: what the person actually holds is the only honest
    // answer to whether the screen is still worth showing. See
    // [PermissionConsent.shouldOffer] for why the old flag is not consulted.
    final consent = done
        ? await ref.read(permissionConsentProvider.future)
        : PermissionConsent.nothingToAskAbout;
    if (!mounted) return;
    setState(() {
      _ready = true;
      _oweConsent = consent.shouldOffer;
    });
    ref.read(onboardedProvider.notifier).state = done;
    // The stored conversation, once the gate knows who this is. The engine is
    // not started here: that moved to initState, ahead of every await in this
    // method, so it no longer waits on the store, on onboarding and on the
    // permission consent in turn.
    if (done) ref.read(chatProvider.notifier).load();
  }

  /// Lets the splash go, once. Not tied to the engine: the loading bar under it
  /// reports real progress, and a start screen that can be starved by a system
  /// dialog or a slow model copy is how this deadlocked before.
  void _leaveSplash() {
    if (_splashDone) return;
    setState(() => _splashDone = true);
  }

  /// Records how the explanation was answered, and lets the person in.
  ///
  /// Both answers stop the screen coming back on the next launch, and neither
  /// one stops it being reachable: Settings offers the same prompts again for
  /// as long as the app exists.
  Future<void> _answered(ConsentOutcome outcome) async {
    if (!mounted) return;
    setState(() => _oweConsent = false);
    final store = ref.read(storeProvider).value;
    if (store == null) return;
    await store.put(permissionConsentKey, outcome.name);
    // So Settings reads the answer back rather than the pre-consent state.
    ref.invalidate(permissionConsentProvider);
  }

  @override
  Widget build(BuildContext context) {
    if (_ready == null || !_splashDone) {
      // Five seconds, first run or not, because the loading bar underneath it
      // is real: it reports the model actually being unpacked and warmed, and a
      // flash of a bar going nowhere is worse than a few seconds of honesty. The
      // bar still moves with real engine progress, not a timer.
      return SplashScreen(onDone: _leaveSplash);
    }
    // Watched, not cached in a field. Onboarding flips this provider when the
    // user presses Start, and watching it is the only thing that swaps the tree
    // over to the app. Holding a copy in a field meant the last button on the
    // last screen did nothing at all.
    final onboarded = ref.watch(onboardedProvider);
    if (!onboarded) return const OnboardingScreen();
    // The permission explanation, once, before the app itself, and only when
    // there is still something to ask for. Asked from a screen a person chose to
    // leave, and every line on it says what refusing costs.
    if (_oweConsent == true) {
      return PermissionsIntroScreen(onAnswered: _answered);
    }
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
    this.minimum = const Duration(seconds: 5),
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
              const SizedBox(height: KoruSpace.xl),
              Text('Koru', style: KoruType.stat),
              const SizedBox(height: KoruSpace.xsm),
              Text(
                'An assistant that knows your life',
                style: KoruType.bodyCompactStrong,
              ),
              const SizedBox(height: KoruSpace.xxl),
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

  /// What the engine is doing, as [EngineProgress] describes it. Null while it
  /// is not doing anything, which is not the same as doing nothing.
  final int? progress;

  /// Shown only once there is something worth saying about it.
  final KoruHealth? health;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    // No percentage exists for the copy out of the APK, so the bar sweeps rather
    // than lying about being stuck at zero.
    final copying = p == EngineProgress.unpacking;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 120,
          child: LinearProgressIndicator(
            minHeight: 3,
            // Null value means the bar sweeps, which is right when nothing is
            // being reported yet, right while the copy is running because there
            // is no percentage to report, and wrong once there is one.
            value: (p == null || copying) ? null : (p / 100).clamp(0.0, 1.0),
            backgroundColor: KoruColors.line,
            valueColor: AlwaysStoppedAnimation(KoruColors.leaf),
          ),
        ),
        const SizedBox(height: KoruSpace.sml),
        SizedBox(
          child: Text(
            switch (p) {
              // Copying 248 MB out of the APK is the slowest thing this app ever
              // does, and it is not obvious why. Named, given its size, and put
              // here rather than after the first question: this is a splash, and
              // the user has nothing else to read yet.
              EngineProgress.unpacking =>
                'Unpacking the local model, 248 MB. Once, on first use.',
              null => 'Getting things ready',
              _ => 'Starting the local model  $p%',
            },
            textAlign: TextAlign.center,
            style: KoruType.caption,
          ),
        ),
        if (health != null && !health!.complete) ...[
          const SizedBox(height: KoruSpace.mdl),
          // Named individually, because each of these can be refused on its own
          // and "something is not set up" gives the reader nothing to do.
          ...health!.problems.map(
            (problem) => Padding(
              padding: const EdgeInsets.only(bottom: KoruSpace.xs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: KoruSize.iconSm, color: KoruColors.gold),
                  const SizedBox(width: KoruSpace.xsm),
                  Flexible(
                    child: Text(problem, style: KoruType.badge),
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

  /// Opens whatever a notification tap asked for.
  ///
  /// Notification taps used to be parsed, tested and then dropped on the floor:
  /// [AttentionBridge.takeLink] existed and had no callers, so tapping a
  /// notification opened the app and did nothing else. The user could not tell
  /// that from the notification not having worked at all.
  Future<void> _openPendingLink(KoruDeepLink? link) async {
    if (link == null) return;
    switch (link.target) {
      case AttentionTarget.client:
        // A client link with no id cannot name a screen, and guessing which
        // client was meant is worse than landing on the list.
        if (link.id == null) {
          setState(() => _tab = 2);
        } else {
          final navigator = Navigator.of(context);
          setState(() => _tab = 2);
          await navigator.push(MaterialPageRoute<void>(
            builder: (_) => ClientDetailScreen(clientId: link.id!),
          ));
        }
      case AttentionTarget.event:
      // There is no event detail screen yet, so land on the calendar section.
        setState(() => _tab = 2);
      case AttentionTarget.deadline:
        setState(() => _tab = 2);
      case AttentionTarget.project:
        // No detail screen for a project yet, so land where the list is.
        setState(() => _tab = 3);
      case AttentionTarget.chat:
        setState(() => _tab = 1);
    }
    // Cleared last, so a rebuild mid-navigation cannot re-enter this.
    ref.read(pendingLinkProvider.notifier).clear();
  }

  // Not const: the screens read the palette, which is resolved per brightness.
  static final _pages = [
    const TodayScreen(),
    const ChatScreen(),
    const BusinessScreen(),
    const ProjectsScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    // Listen rather than read, so a link that arrives while the app is already
    // open is handled too.
    ref.listen<KoruDeepLink?>(pendingLinkProvider, (prev, next) {
      if (next != null) _openPendingLink(next);
    });
    // Covers the cold start, where the link was already taken before this
    // widget existed and so no transition will ever fire. `ref.listen` has no
    // fireImmediately in riverpod 2.x, so it is done by hand after the first
    // frame, when a navigator actually exists to push onto.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pending = ref.read(pendingLinkProvider);
      if (pending != null) _openPendingLink(pending);
    });
    ref.read(pendingLinkProvider.notifier).listenOnOpen();

    return Scaffold(
      body: IndexedStack(index: _tab, children: _pages),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: KoruColors.surface,
          border: Border(top: KoruBorders.hairline()),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            // Grown from 62 for the fifth tab. Labels are kept rather than
            // dropped: an icon with no name is a worse affordance than a
            // slightly shorter row.
            height: KoruSpace.xxxl * 2,
            child: Row(
              children: [
                _tabButton(0, Icons.today_outlined, Icons.today_rounded, 'Today'),
                _tabButton(1, Icons.forum_outlined, Icons.forum_rounded, 'Talk'),
                _tabButton(2, Icons.work_outline_rounded, Icons.work_rounded, 'Business'),
                _tabButton(3, Icons.folder_outlined, Icons.folder_rounded, 'Projects'),
                _tabButton(4, Icons.settings_outlined, Icons.settings_rounded, 'Settings'),
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
          onTap: () {
            // A tick, not a buzz. It confirms the tap landed without becoming
            // the thing you notice while switching tabs.
            HapticFeedback.selectionClick();
            setState(() => _tab = i);
          },
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
