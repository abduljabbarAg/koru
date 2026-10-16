import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'currency.dart';
import 'mascot/mascot.dart';
import 'mascot/mascot_clips.dart';
import 'state.dart';
import 'theme.dart';
import 'widgets.dart';

/// Onboarding is the highest-leverage screen in the product: without context
/// there is nothing to answer questions about. Kept to 8 taps.
///
/// It asks for a client capacity because that is the one number the rest of the
/// product measures itself against, and asking once here is better than nagging
/// later about a limit the user never chose.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  /// Number of screens, including the review.
  ///
  /// One constant rather than a 6 written in four places. It was 6 in the page
  /// bar, the counter, the Continue label and the bounds of _next, and those
  /// drifting apart is how a flow ends up able to reach a step that does not
  /// exist.
  static const _steps = 7;

  static const _last = _steps - 1;

  final _page = PageController();
  final _mascot = KoruMascotController();
  int _step = 0;

  final _nick = TextEditingController();
  String? _stage;
  String? _biz;
  final _goals = TextEditingController();

  /// How many clients this person is willing to carry at once. Set on the first
  /// run because it is the number every other part of the product measures
  /// against, and guessing it later feels like the app nagging.
  int _capacity = 5;
  String _currency = 'AED';

  /// Multi-select: people usually want help with more than one thing, and
  /// forcing a single pick quietly threw the rest away.
  final Set<String> _help = <String>{};

  static const _stages = ['Just starting', 'A few years in', 'Established', 'Running a business'];
  static const _bizs = ['Solo / freelancer', 'Small company', 'Employee', 'No business yet'];
  static const _helps = [
    'Finding clients',
    'Getting paid',
    'Pricing',
    'Staying organised',
    'All of it',
  ];

  /// Presets rather than a free-form number, because the honest answer to "how
  /// many clients can you serve well" is a feeling and three options capture it
  /// better than a text field.
  static const _capacityOptions = [3, 5, 8, 12];

  @override
  void dispose() {
    _page.dispose();
    _nick.dispose();
    _goals.dispose();
    super.dispose();
  }

  /// The face for a step.
  ///
  /// Waiting while something is unanswered, thinking on the two questions that
  /// take a moment, cheerful once the money and the goals are in. Carries
  /// information rather than just moving.
  KoruClip _clipFor(int step) => switch (step) {
        0 => KoruClip.greet,
        1 => KoruClip.wave,
        2 => KoruClip.idle,
        3 => KoruClip.think,
        4 => KoruClip.idle,
        5 => KoruClip.cheer,
        6 => KoruClip.cheer,
        _ => KoruClip.idle,
      };

  void _next() {
    if (_step < _last) {
      setState(() => _step++);
      _mascot.play(_clipFor(_step + 1));
      _page.animateToPage(_step,
          duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
    } else {
      _save();
    }
  }

  void _back() {
    if (_step == 0) return;
    setState(() => _step--);
    _mascot.play(_clipFor(_step - 1));
    _page.animateToPage(_step,
        duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
  }

  /// Writes the profile and finishes onboarding.
  ///
  /// Any failure here used to surface as nothing at all: the button was tapped,
  /// a write threw, and the screen simply stayed put. A silent failure on the
  /// one button that ends onboarding is worse than an ugly one, so it reports.
  Future<void> _save() async {
    try {
      await _write();
    } catch (e) {
      if (mounted) toast(context, 'Could not save: $e');
      return;
    }
  }

  Future<void> _write() async {
    final store = await ref.read(storeProvider.future);

    await store.put('nickname', _nick.text.trim().isEmpty ? 'friend' : _nick.text.trim());
    await store.put('stage', _stage ?? '');
    await store.put('business', _biz ?? '');
    await store.put('goals', _goals.text.trim());
    await store.put('help_focus', _help.join(', '));
    await store.putNumber('capacity', _capacity.toDouble());
    await store.put('currency', _currency);
    await store.completeOnboarding();
    ref.invalidate(packetProvider);
    ref.invalidate(guideFactsProvider);
    ref.read(onboardedProvider.notifier).state = true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KoruColors.cream,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  KoruSpace.xxl, KoruSpace.lg, KoruSpace.xxl, KoruSpace.sm),
              child: Row(
                children: [
                  const KoruMark(size: 30),
                  const SizedBox(width: KoruSpace.md),
                  Text('Koru', style: KoruType.title.copyWith(fontSize: 19)),
                  const Spacer(),
                  Text('${_step + 1} of $_steps', style: KoruType.caption),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: KoruSpace.xxl),
              child: Row(
                children: List.generate(_steps, (i) {
                  return Expanded(
                    child: Container(
                      height: 4,
                      margin: EdgeInsets.only(
                          right: i == _last ? 0 : KoruSpace.sm - 2),
                      decoration: BoxDecoration(
                        color: i <= _step ? KoruColors.leaf : KoruColors.line,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _page,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _intro(),
                  _nickName(),
                  _choice('What best describes where you are?', _stages, _stage,
                      (v) => setState(() => _stage = v)),
                  _choice('What is your work situation?', _bizs, _biz,
                      (v) => setState(() => _biz = v)),
                  _capacityStep(),
                  _goalsScreen(),
                  _review(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  KoruSpace.xxl, KoruSpace.sm, KoruSpace.xxl, KoruSpace.xxl),
              child: Row(
                children: [
                  if (_step > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _back,
                        child: const Text('Back'),
                      ),
                    ),
                  if (_step > 0) const SizedBox(width: KoruSpace.md),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _next,
                      child: Text(_step == _last ? 'Start' : 'Continue'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Koru alongside the question.
  ///
  /// He was only on the intro screen before, so the character introduced himself
  /// and then vanished for the five screens where the user was actually filling
  /// things in. A character that is present during setup is a guide; one that is
  /// only present to say hello is decoration.
  ///
  /// The expression follows the step, so the face carries information rather
  /// than just moving: waiting while a question is unanswered, thinking on the
  /// harder ones, cheerful once the details are in.
  Widget _guide(KoruClip clip) {
    return Padding(
      padding: const EdgeInsets.only(bottom: KoruSpace.xs),
      child: Row(
        children: [
          KoruMascot(size: 54, controller: _mascot, semanticLabel: 'Koru'),
          const SizedBox(width: KoruSpace.md),
          Expanded(
            child: Text(
              switch (clip) {
                KoruClip.think => 'Koru is thinking this one over',
                KoruClip.cheer => 'Koru is ready to get going',
                KoruClip.wave => 'Koru is here',
                _ => 'Koru is listening',
              },
              style: KoruType.bodySmall.copyWith(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  /// The frame every step sits in.
  ///
  /// One definition rather than seven: the mascot, the question, one line of
  /// why it is being asked, and the control. Every onboarding step used to lay
  /// itself out by hand, which is how the seven pages came to have seven
  /// different question sizes.
  Widget _body(String title, String sub, List<Widget> children, {KoruClip clip = KoruClip.idle}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          KoruSpace.xxl, KoruSpace.xl, KoruSpace.xxl, KoruSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _guide(clip),
          const SizedBox(height: KoruSpace.md),
          Text(title, style: KoruType.display.copyWith(fontSize: 27, letterSpacing: -0.6)),
          const SizedBox(height: KoruSpace.sm),
          Text(sub, style: KoruType.bodyStrong.copyWith(color: KoruColors.inkSoft)),
          const SizedBox(height: KoruSpace.xl),
          ...children,
        ],
      ),
    );
  }

  Widget _intro() => _body(
        'A business partner that keeps the books.',
        'Your clients, your money and what is due. It runs on this phone. '
            'No account, no real name.',
        [
          const SizedBox(height: KoruSpace.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(KoruRadius.card),
            child: Image.asset(
              'assets/splash/koru_splash.png',
              width: double.infinity,
              fit: BoxFit.cover,
              height: 190,
              excludeFromSemantics: true,
            ),
          ),
          const SizedBox(height: KoruSpace.xl),
          const KoruFeature(
              icon: Icons.lock_outline_rounded,
              title: 'Local by default',
              body: 'Your clients and your money are answered here, without a network call.'),
          const KoruFeature(
              icon: Icons.payments_outlined,
              title: 'Knows what you are owed',
              body: 'Clients, payments and deadlines, so asking about money gets an answer.'),
          const KoruFeature(
              icon: Icons.edit_note_rounded,
              title: 'Writes when you say so',
              body: 'Say "add client Bilal for 2000". Nothing is saved until you approve it.'),
          const KoruFeature(
              icon: Icons.people_outline_rounded,
              title: 'Knows when to step aside',
              body: 'Some questions deserve a real person, not a model.'),
        ],
      );

  /// What Koru will actually know, before it is asked to remember it.
  ///
  /// Added because the old flow went straight from the last question to the
  /// home screen, and the first thing anybody learns about their own assistant
  /// is by it being wrong later. Six answers, silently stored, with no chance to
  /// see them.
  ///
  /// Missing answers are shown as missing rather than quietly defaulted. That
  /// matters: the client screen had a bug where nothing defaulted to a real
  /// value and every total read zero, and the same silence here would just look
  /// like the app ignoring what was typed.
  Widget _review() {
    final rows = <(String, String)>[
      ('Calls you', _nick.text.trim().isEmpty ? 'not set' : _nick.text.trim()),
      ('Where you are', _stage ?? 'not set'),
      ('Your work', _biz ?? 'not set'),
      ('How much you can carry', '$_capacity ${_capacity == 1 ? 'client' : 'clients'} at a time'),
      ('Paid in', _currency),
      ('What you want help with', _goals.text.trim().isEmpty ? 'not set' : _goals.text.trim()),
    ];
    final missing = rows.where((r) => r.$2 == 'not set').length;

    return _body(
      clip: KoruClip.cheer,
      'This is what Koru will know',
      missing == 0
          ? 'Check it over. Everything here stays on this phone, and you can '
              'change any of it later in Settings.'
          : 'Check it over. $missing ${missing == 1 ? 'answer is' : 'answers are'} '
              'empty and Koru will say so rather than guess.',
      [
        const SizedBox(height: KoruSpace.sm + 2),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: KoruSpace.sm + 2),
            child: KoruCard(
              padding: const EdgeInsets.symmetric(
                horizontal: KoruSpace.lg,
                vertical: KoruSpace.md,
              ),
              background: row.$2 == 'not set' ? KoruColors.goldSoft : null,
              accent: row.$2 == 'not set' ? KoruColors.gold : null,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.$1.toUpperCase(),
                          style: KoruType.label.copyWith(fontSize: 10.5),
                        ),
                        const SizedBox(height: KoruSpace.xs),
                        Text(
                          row.$2,
                          style: KoruType.bodyStrong.copyWith(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: row.$2 == 'not set'
                                ? KoruColors.inkFaint
                                : KoruColors.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (row.$2 == 'not set')
                    IconButton(
                      tooltip: 'Answer this',
                      iconSize: KoruSize.icon,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _jumpTo(row.$1),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Sends the user back to the answer they left empty.
  int _stepFor(String label) => switch (label) {
        'Calls you' => 1,
        'Where you are' => 2,
        'Your work' => 3,
        'How much you can carry' => 4,
        'What you want help with' => 5,
        _ => 0,
      };

  void _jumpTo(String label) {
    final target = _stepFor(label);
    if (target >= _step) return;
    setState(() => _step = target);
    _mascot.play(_clipFor(target));
    _page.animateToPage(target,
        duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
  }

  Widget _nickName() => _body(
        clip: KoruClip.wave,
        'What should I call you?',
        'A nickname, not a name. It stays on this device and is never attached '
            'to anything sent to a cloud model.',
        [
          const SizedBox(height: KoruSpace.sm),
          TextField(
            controller: _nick,
            textCapitalization: TextCapitalization.none,
            decoration: const InputDecoration(hintText: 'nickname'),
          ),
        ],
      );

  Widget _choice(String title, List<String> opts, String? sel, void Function(String) onPick) =>
      _body(title, 'Pick one. You can change this later in Settings.', [
        const SizedBox(height: KoruSpace.xs),
        for (final o in opts)
          KoruSelectableTile(
            label: o,
            selected: sel == o,
            onTap: () => setState(() => onPick(o)),
          ),
      ]);

  Widget _capacityStep() => _body(
        'How many clients can you serve well?',
        'Not how many you can juggle, how many you can do properly. Koru keeps '
            'this number so it can tell you when you are full instead of letting '
            'you quietly take on work you have no room for.',
        [
          const SizedBox(height: KoruSpace.sm),
          Row(
            children: [
              for (final n in _capacityOptions)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                        right: n == _capacityOptions.last ? 0 : KoruSpace.sm),
                    child: _NumberChoice(
                      label: '$n',
                      selected: _capacity == n,
                      onTap: () => setState(() => _capacity = n),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: KoruSpace.xl),
          Text(
            'And what are you paid in?',
            style: KoruType.bodyStrong.copyWith(color: KoruColors.inkSoft),
          ),
          const SizedBox(height: KoruSpace.md),
          Wrap(
            spacing: KoruSpace.sm,
            runSpacing: KoruSpace.sm,
            children: [
              for (final c in kCurrencies)
                KoruSelectablePill(
                  label: c.code,
                  selected: _currency == c.code,
                  onTap: () => setState(() => _currency = c.code),
                ),
            ],
          ),
          const SizedBox(height: KoruSpace.md),
          Text(
            'You can change this any time in Settings.',
            style: KoruType.caption,
          ),
        ],
      );

  /// 'All of it' is a shortcut, so picking it clears the rest, and picking
  /// anything else clears the shortcut. Otherwise you end up with 'All of it'
  /// stored alongside one specific topic, which is noise.
  void _toggleHelp(String value, bool selected) {
    if (value == 'All of it') {
      _help
        ..clear()
        ..add('All of it');
      return;
    }
    _help.remove('All of it');
    if (selected) {
      _help.add(value);
    } else {
      _help.remove(value);
    }
  }

  Widget _goalsScreen() => _body(
        'Last one. What do you want to be true in three months?',
        'Be specific. This is what I will hold you to.',
        [
          const SizedBox(height: KoruSpace.sm),
          TextField(
            controller: _goals,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'e.g. get paid by 5 clients, stop taking work I cannot finish',
            ),
          ),
          const SizedBox(height: KoruSpace.xl),
          const SectionLabel('I want help with', padding: EdgeInsets.only(bottom: KoruSpace.xs)),
          Text('Pick as many as apply.', style: KoruType.caption),
          const SizedBox(height: KoruSpace.sm + 2),
          Wrap(
            spacing: KoruSpace.sm,
            runSpacing: KoruSpace.sm,
            children: [
              for (final h in _helps)
                KoruSelectablePill(
                  label: h,
                  selected: _help.contains(h),
                  onTap: () => setState(() => _toggleHelp(h, !_help.contains(h))),
                ),
            ],
          ),
        ],
      );
}

class KoruFeature extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const KoruFeature({super.key, required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: KoruSpace.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KoruIconBadge(
            icon: icon,
            color: KoruColors.leaf,
            background: KoruColors.leafSoft,
          ),
          const SizedBox(width: KoruSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: KoruType.bodyStrong.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: KoruSpace.xxs),
                Text(body, style: KoruType.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One of the capacity numbers.
///
/// The same selectable tile as the stage and work lists, centred, because
/// capacity is picked the same way and had to look like it.
class _NumberChoice extends StatelessWidget {
  const _NumberChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KoruRadius.field),
        child: AnimatedContainer(
          duration: KoruMotion.quick,
          curve: KoruMotion.easeOut,
          padding: const EdgeInsets.symmetric(vertical: KoruSpace.lg + 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? KoruColors.leafSoft : KoruColors.surface,
            borderRadius: BorderRadius.circular(KoruRadius.field),
            border: Border.fromBorderSide(
              selected ? KoruBorders.selected() : KoruBorders.hairline(),
            ),
            boxShadow: selected ? KoruElevation.pressed : KoruElevation.none,
          ),
          child: Text(
            label,
            style: KoruType.bodyStrong.copyWith(
              fontSize: 19,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}