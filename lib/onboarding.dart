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
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Row(
                children: [
                  const KoruMark(),
                  const SizedBox(width: 12),
                  Text('Koru', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  Text('${_step + 1} of $_steps',
                      style: const TextStyle(color: KoruColors.inkFaint, fontSize: 13)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: List.generate(_steps, (i) {
                  return Expanded(
                    child: Container(
                      height: 4,
                      margin: EdgeInsets.only(right: i == _last ? 0 : 6),
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
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Row(
                children: [
                  if (_step > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _back,
                        child: const Text('Back'),
                      ),
                    ),
                  if (_step > 0) const SizedBox(width: 12),
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
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          KoruMascot(size: 54, controller: _mascot, semanticLabel: 'Koru'),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              switch (clip) {
                KoruClip.think => 'Koru is thinking this one over',
                KoruClip.cheer => 'Koru is ready to get going',
                KoruClip.wave => 'Koru is here',
                _ => 'Koru is listening',
              },
              style: const TextStyle(color: KoruColors.inkFaint, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(String title, String sub, List<Widget> children, {KoruClip clip = KoruClip.idle}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _guide(clip),
          const SizedBox(height: 14),
          Text(title,
              style: const TextStyle(
                  fontSize: 27, fontWeight: FontWeight.w700, height: 1.2, letterSpacing: -0.6)),
          const SizedBox(height: 8),
          Text(sub,
              style: const TextStyle(
                  fontSize: 15, color: KoruColors.inkSoft, height: 1.45)),
          const SizedBox(height: 24),
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
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.asset(
              'assets/splash/koru_splash.png',
              width: double.infinity,
              fit: BoxFit.cover,
              height: 190,
              excludeFromSemantics: true,
            ),
          ),
          const SizedBox(height: 20),
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
        const SizedBox(height: 10),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: row.$2 == 'not set' ? KoruColors.goldSoft : KoruColors.surface,
                borderRadius: BorderRadius.circular(KoruRadius.field),
                border: Border.all(
                  color: row.$2 == 'not set' ? KoruColors.gold : KoruColors.line,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(row.$1,
                            style: const TextStyle(
                                fontSize: 11.5, color: KoruColors.inkFaint)),
                        const SizedBox(height: 2),
                        Text(row.$2,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: row.$2 == 'not set'
                                  ? KoruColors.inkFaint
                                  : KoruColors.ink,
                            )),
                      ],
                    ),
                  ),
                  if (row.$2 == 'not set')
                    IconButton(
                      tooltip: 'Answer this',
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.edit_outlined, color: KoruColors.gold),
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
          const SizedBox(height: 8),
          TextField(
            controller: _nick,
            textCapitalization: TextCapitalization.none,
            decoration: const InputDecoration(hintText: 'nickname'),
          ),
        ],
      );

  Widget _choice(String title, List<String> opts, String? sel, void Function(String) onPick) =>
      _body(title, 'Pick one. You can change this later in Settings.', [
        const SizedBox(height: 4),
        ...opts.map((o) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                onTap: () => setState(() => onPick(o)),
                borderRadius: BorderRadius.circular(KoruRadius.field),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(
                    color: sel == o ? KoruColors.leafSoft : KoruColors.surface,
                    borderRadius: BorderRadius.circular(KoruRadius.field),
                    border: Border.all(
                      color: sel == o ? KoruColors.leaf : KoruColors.line,
                      width: sel == o ? 1.6 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(o,
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: sel == o ? FontWeight.w600 : FontWeight.w500,
                                color: KoruColors.ink)),
                      ),
                      if (sel == o)
                        const Icon(Icons.check_circle_rounded,
                            color: KoruColors.leaf, size: 21),
                    ],
                  ),
                ),
              ),
            )),
      ]);

  Widget _capacityStep() => _body(
        'How many clients can you serve well?',
        'Not how many you can juggle, how many you can do properly. Koru keeps '
            'this number so it can tell you when you are full instead of letting '
            'you quietly take on work you have no room for.',
        [
          const SizedBox(height: 8),
          Row(
            children: [
              for (final n in _capacityOptions) ...[
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: () => setState(() => _capacity = n),
                      borderRadius: BorderRadius.circular(KoruRadius.field),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _capacity == n ? KoruColors.leafSoft : KoruColors.surface,
                          borderRadius: BorderRadius.circular(KoruRadius.field),
                          border: Border.all(
                            color: _capacity == n ? KoruColors.leaf : KoruColors.line,
                            width: _capacity == n ? 1.6 : 1,
                          ),
                        ),
                        child: Text(
                          '$n',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: _capacity == n ? FontWeight.w700 : FontWeight.w500,
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
          const SizedBox(height: 18),
          const Text(
            'And what are you paid in?',
            style: TextStyle(fontSize: 15, color: KoruColors.inkSoft, height: 1.4),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in kCurrencies)
                InkWell(
                  onTap: () => setState(() => _currency = c.code),
                  borderRadius: BorderRadius.circular(KoruRadius.pill),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: _currency == c.code ? KoruColors.leafSoft : KoruColors.surface,
                      borderRadius: BorderRadius.circular(KoruRadius.pill),
                      border: Border.all(
                        color: _currency == c.code ? KoruColors.leaf : KoruColors.line,
                        width: _currency == c.code ? 1.6 : 1,
                      ),
                    ),
                    child: Text(
                      c.code,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: _currency == c.code ? FontWeight.w700 : FontWeight.w500,
                        color: KoruColors.ink,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'You can change this any time in Settings.',
            style: TextStyle(fontSize: 13, color: KoruColors.inkFaint),
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
          const SizedBox(height: 8),
          TextField(
            controller: _goals,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'e.g. get paid by 5 clients, stop taking work I cannot finish',
            ),
          ),
          const SizedBox(height: 18),
          const SectionLabel('I want help with'),
          const Text(
            'Pick as many as apply.',
            style: TextStyle(fontSize: 13, color: KoruColors.inkFaint),
          ),
          const SizedBox(height: 10),
          ..._helps.map((h) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ChoiceChip(
                  label: Text(h),
                  selected: _help.contains(h),
                  onSelected: (s) => setState(() => _toggleHelp(h, s)),
                  selectedColor: KoruColors.leafSoft,
                  side: const BorderSide(color: KoruColors.line),
                  labelStyle: TextStyle(
                      color: KoruColors.ink,
                      fontWeight: _help.contains(h) ? FontWeight.w600 : FontWeight.w500),
                ),
              )),
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
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: KoruColors.leaf, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15.5, color: KoruColors.ink)),
                const SizedBox(height: 2),
                Text(body,
                    style: const TextStyle(
                        color: KoruColors.inkFaint, fontSize: 13.5, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}