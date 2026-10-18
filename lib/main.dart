import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'attention.dart';
import 'attention_bridge.dart';
import 'deep_link.dart';
import 'mascot/mascot.dart';
import 'onboarding.dart';
import 'permission_consent.dart';
import 'screens/chat.dart';
import 'screens/client_detail.dart';
import 'screens/clients.dart';
import 'screens/permissions_intro.dart';
import 'screens/project_detail.dart';
import 'screens/revenue.dart';
import 'screens/shell_actions.dart';
import 'screens/tasks.dart';
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

class _RootGateState extends ConsumerState<RootGate> {
  bool? _ready;
  bool _splashDone = false;

  /// Whether the permission explanation still owes this person a look. Null
  /// until the store and the platform have both answered, because deciding this
  /// from the stored flag alone is what hid the screen from every upgrading
  /// user, and because a first run has to decide it again the moment onboarding
  /// finishes rather than carrying the answer it gave before onboarding existed.
  bool? _oweConsent;

  /// Whether a decision is already on its way, so the launch path and the
  /// onboarding path cannot both start one.
  bool _deciding = false;

  /// How long the consent read is given before the person is let in anyway.
  /// Cancelled with the gate rather than left running behind it.
  Timer? _patience;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    _patience?.cancel();
    _patience = null;
    super.dispose();
  }

  Future<void> _check() async {
    final store = await ref.read(storeProvider.future);
    final done = await store.onboarded;
    if (!mounted) return;
    ref.read(onboardedProvider.notifier).state = done;
    setState(() => _ready = true);
    // Asked, not recorded: what the person actually holds is the only honest
    // answer to whether the screen is still worth showing. See
    // [PermissionConsent.shouldOffer] for why the old flag is not consulted.
    //
    // Only for somebody who is already through onboarding, and only decided once.
    // It used to be decided here for everybody, with everybody who had not
    // onboarded answered "nothing to ask about" — and this field is never
    // recomputed. So a genuine first run carried that answer for the rest of
    // the session: onboarding finished, the gate rebuilt, `onboarded` was true
    // and the consent screen was already ruled out. The reported symptom was
    // "I have to close the app and start again then i see the permission
    // screen", which is exactly it: the second launch is the first one where
    // the question is asked with onboarding already behind it.
    if (done) {
      unawaited(_decideConsent());
      // The stored conversation, once the gate knows who this is.
      ref.read(chatProvider.notifier).load();
    }
  }

  /// Asks what is genuinely still missing and records whether to offer the
  /// explanation.
  ///
  /// Fired the moment the person finishes onboarding rather than at launch,
  /// because before that there is nothing to ask: a half-built app asking for
  /// notifications is the thing the explanation exists to argue against.
  Future<void> _decideConsent() async {
    if (_oweConsent != null || _deciding) return;
    _deciding = true;
    bool offer;
    // Bounded, because this decides whether the person is let into their own
    // app. It is normally a couple of round trips to the platform and nothing
    // more, and a read that never finishes — a plugin that never answers, a
    // channel that is gone — must not leave somebody standing on a loading
    // screen with no way past it. Running out of patience here means the same
    // thing as "nothing to ask about": in, with Settings still offering the
    // prompts for as long as the app exists.
    //
    // A timer of this class's own rather than Future.timeout, so disposing the
    // gate cancels it instead of leaving one pending behind a screen that has
    // gone.
    final patience = Completer<PermissionConsent>();
    _patience = Timer(const Duration(seconds: 3), () {
      if (!patience.isCompleted) {
        patience.complete(PermissionConsent.nothingToAskAbout);
      }
    });
    try {
      final consent = await Future.any<PermissionConsent>([
        ref.read(permissionConsentProvider.future),
        patience.future,
      ]);
      offer = consent.shouldOffer;
    } catch (_) {
      // A read that could not finish is not a reason to strand somebody outside
      // their own app. Nothing granted is not the same as nothing readable, and
      // Settings still offers the same prompts for as long as the app exists.
      offer = false;
    } finally {
      _patience?.cancel();
      _patience = null;
    }
    if (!mounted) return;
    setState(() {
      _oweConsent = offer;
      _deciding = false;
    });
  }

  /// Lets the splash go, once. On a timer rather than on a task finishing,
  /// because a start screen that can be starved by a system dialog or a slow
  /// keystore read is how this deadlocked before.
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
      // Long enough to read and to let the character get a few idle cycles. The
      // bar underneath sweeps rather than pretending to a number, because there
      // is no counted work left to report — the store opens and the app draws.
      return SplashScreen(onDone: _leaveSplash);
    }
    // Watched, not cached in a field. Onboarding flips this provider when the
    // user presses Start, and watching it is the only thing that swaps the tree
    // over to the app. Holding a copy in a field meant the last button on the
    // last screen did nothing at all.
    final onboarded = ref.watch(onboardedProvider);
    // Watched, so the moment onboarding writes the flag is the moment the
    // permission question is asked. Deciding it once at launch is what made a
    // fresh install never see the screen until it was restarted: see [_check].
    ref.listen<bool>(onboardedProvider, (previous, next) {
      if (previous == true || next != true) return;
      unawaited(_decideConsent());
    });
    if (!onboarded) return const OnboardingScreen();
    // Decided, but not yet decided. Two platform round trips, and showing the
    // app for them and then replacing it with the explanation is a flash of
    // the wrong screen rather than a wait.
    if (_oweConsent == null) return const ConsentCheckScreen();
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

/// Shown for the moment it takes to find out what is already allowed.
///
/// Two platform round trips, once, between onboarding finishing and the app.
/// It exists so the wait is a wait and not a flash of the app that is then
/// pulled out from under the reader and replaced by the explanation.
class ConsentCheckScreen extends StatelessWidget {
  const ConsentCheckScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KoruColors.cream,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: KoruSpace.gutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const KoruMascot(size: 96, semanticLabel: 'Koru, your helper'),
              const SizedBox(height: KoruSpace.xl),
              Text(
                'Checking what is already allowed',
                textAlign: TextAlign.center,
                style: KoruType.bodyCompactStrong,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Koru's own splash.
///
/// Held for a minimum time so the character gets a few idle cycles and a blink
/// in, which is the whole point of animating it. Long enough to read, short
/// enough not to be in the way.
///
/// It used to also be held while the local model was unpacked and warmed, which
/// took tens of seconds on a cold install. There is no local model and nothing
/// left to wait for, so the splash is a timer and no longer a hostage.
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
    // The splash used to poll the model engine's progress and hold until it had
    // finished starting. That made the start screen hostage to work happening
    // behind it: a system dialog for battery optimisation, a model copy that
    // took longer than expected, or a health check that never answered, and the
    // app sat there with no way forward and nothing to tap.
    //
    // There is no engine to poll now, and the rule is worth keeping anyway: the
    // splash leaves on a timer that nothing can starve.
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
              // Sweeps, because nothing here is a counted task any more and a
              // bar pinned at zero for the length of the splash is a bar telling
              // the reader the app is stuck. What it can report honestly is what
              // Android still has not granted, which is the health line under it.
              const _EngineLoadingBar(),
            ],
          ),
        ),
      ),
    );
  }
}

/// The splash's loading bar, and what it knows.
///
/// Sweeps rather than counting, because there is no counted work left to report:
/// the store opening and the first frame are the only things it waits on, and a
/// determinate bar over those is a bar inventing a number. What it does carry is
/// the health check, which is real and actionable — each problem named
/// separately, because each can be refused on its own and "something is not set
/// up" gives the reader nothing to do.
class _EngineLoadingBar extends ConsumerWidget {
  const _EngineLoadingBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(healthProvider).valueOrNull;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 120,
          child: LinearProgressIndicator(
            minHeight: 3,
            value: null,
            backgroundColor: KoruColors.line,
            valueColor: AlwaysStoppedAnimation(KoruColors.leaf),
          ),
        ),
        const SizedBox(height: KoruSpace.sml),
        Text('Getting things ready', style: KoruType.caption),
        if (health != null && !health.complete) ...[
          const SizedBox(height: KoruSpace.mdl),
          ...health.problems.map(
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

/// The four tabs, in the order they are worth having.
///
/// Named rather than a bare list of numbers because the numbers are the one thing
/// in this file that has no meaning of its own: the deep links and the taps in
/// [_HomeShellState] all address a screen by index, and a screen that moved
/// silently turns every one of those into a link that lands somewhere else.
/// Four, not five. Talk and Settings are in the header of the two screens
/// somebody opens to get something done — a person arriving for the first time
/// should meet their work before they meet configuration.
enum KoruAppTabs {
  today(0, Icons.today_outlined, Icons.today_rounded, 'Today'),
  tasks(1, Icons.checklist_rounded, Icons.checklist_rtl_rounded, 'Tasks'),
  clients(2, Icons.people_outline_rounded, Icons.people_rounded, 'Clients'),
  revenue(3, Icons.payments_outlined, Icons.payments_rounded, 'Revenue');

  const KoruAppTabs(this.slot, this.iconOff, this.iconOn, this.label);

  /// Where this tab sits in the bar. Read through here rather than written at
  /// each call site, because a number written next to a screen is a number that
  /// survives the screen moving.
  final int slot;

  /// Shown while another tab is showing.
  final IconData iconOff;

  /// Shown while this one is.
  final IconData iconOn;

  final String label;

  /// The tab a link target opens on.
  ///
  /// Written here rather than at the call site because this is the one place
  /// that has to be right when the bar changes shape. It used to be a bare number
  /// beside each `setState`, and reordering the tabs turned every notification
  /// that had ever been posted into a link that opened something else — which is
  /// invisible until somebody taps one and cannot work out why they are looking
  /// at a balance sheet instead of at their work.
  static KoruAppTabs tabFor(AttentionTarget target) => switch (target) {
        AttentionTarget.client => KoruAppTabs.clients,
        // A deadline and an entry are both about today, and the queue is where
        // they are read now. Before this they landed on the page of balances,
        // which has never been where a deadline was.
        AttentionTarget.deadline => KoruAppTabs.today,
        AttentionTarget.event => KoruAppTabs.today,
        AttentionTarget.task => KoruAppTabs.tasks,
        // Projects are listed on the work tab, and the tap pushes the project
        // itself, which has a screen of its own now.
        AttentionTarget.project => KoruAppTabs.tasks,
        AttentionTarget.chat => KoruAppTabs.today,
      };
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  /// Which of the four screens is showing.
  ///
  /// Indexed rather than named because the whole point of the order is what
  /// comes first: Today, the Tasks, the Clients, the Money. Every deep link in
  /// the app resolves through [KoruAppTabs] so that a notification written
  /// against the old five-tab order cannot land on whatever happens to sit at
  /// that number now.
  int _tab = 0;

  /// Opens whatever a notification tap asked for.
  ///
  /// Notification taps used to be parsed, tested and then dropped on the floor:
  /// [AttentionBridge.takeLink] existed and had no callers, so tapping a
  /// notification opened the app and did nothing else. The user could not tell
  /// that from the notification not having worked at all.
  Future<void> _openPendingLink(KoruDeepLink? link) async {
    if (link == null) return;
    // The tab comes from one table for every kind of link, so a link cannot
    // land on the wrong screen because one case was written differently.
    setState(() => _tab = KoruAppTabs.tabFor(link.target).slot);
    final navigator = Navigator.of(context);
    switch (link.target) {
      case AttentionTarget.client:
        // A client link with no id cannot name a screen, and guessing which
        // client was meant is worse than landing on the list.
        if (link.id != null) {
          await navigator.push(MaterialPageRoute<void>(
            builder: (_) => ClientDetailScreen(clientId: link.id!),
          ));
        }
      // A deadline, an entry and a task all land on their own screen rather
      // than on a detail page, because there is no detail screen for them and
      // the queue is where they are read.
      case AttentionTarget.event:
      case AttentionTarget.deadline:
      case AttentionTarget.task:
        break;
      case AttentionTarget.project:
        if (link.id != null) {
          await navigator.push(MaterialPageRoute<void>(
            builder: (_) => ProjectScreen(projectId: link.id!),
          ));
        }
      case AttentionTarget.chat:
        await navigator.push(MaterialPageRoute<void>(
          builder: (_) => const ChatScreen(),
        ));
    }
    // Cleared last, so a rebuild mid-navigation cannot re-enter this.
    ref.read(pendingLinkProvider.notifier).clear();
  }

  // Not const: the screens read the palette, which is resolved per brightness.
  static final _pages = [
    const TodayScreen(),
    const TasksScreen(),
    const ClientsScreen(),
    const RevenueScreen(),
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
      bottomNavigationBar: KoruTabBar(
        selected: _tab,
        onSelected: (slot) {
          // A tick, not a buzz. It confirms the tap landed without becoming the
          // thing you notice while switching tabs.
          HapticFeedback.selectionClick();
          setState(() => _tab = slot);
        },
      ),
    );
  }
}
