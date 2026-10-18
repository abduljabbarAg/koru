import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'currency.dart';
import 'mascot/mascot.dart';
import 'mascot/mascot_clips.dart';
import 'models.dart';
import 'state.dart';
import 'theme.dart';
import 'widgets.dart';

/// The first five minutes, kept to three pages and one real result.
///
/// This used to be seven pages: stage, work situation, capacity, currency,
/// goals, help focus and a review. Every answer was honest and every one was
/// asked before the app had done anything for the person. Worse, it ended on an
/// empty app — the cost of the whole interrogation was that the first thing the
/// user saw was nothing.
///
/// So it is three pages and they end with a record in the database. Page one
/// introduces Koru and takes a nickname. Page two is the one answer the rest of
/// the app genuinely cannot live without, the currency. Page three adds the
/// first client, which is what makes Today worth opening on day one. Capacity
/// stays at its default and moves into Settings; goals live in Your context
/// when somebody has a reason to state them.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  /// Number of pages. One constant rather than a 3 written in four places.
  static const _steps = 3;

  static const _last = _steps - 1;

  final _page = PageController();
  final _mascot = KoruMascotController();
  int _step = 0;

  final _nick = TextEditingController();
  final _clientName = TextEditingController();
  final _clientAmount = TextEditingController();
  String _currency = 'AED';

  @override
  void dispose() {
    _page.dispose();
    _nick.dispose();
    _clientName.dispose();
    _clientAmount.dispose();
    super.dispose();
  }

  /// The face for a step. Carries information rather than just moving: greeting
  /// on arrival, listening while the questions are answered, cheerful at the
  /// end because the work is done.
  KoruClip _clipFor(int step) => switch (step) {
        0 => KoruClip.greet,
        1 => KoruClip.wave,
        _ => KoruClip.cheer,
      };

  void _next() {
    if (_step < _last) {
      _goTo(_step + 1);
    } else {
      _save();
    }
  }

  void _back() {
    if (_step == 0) return;
    _goTo(_step - 1);
  }

  /// One place a page changes, because the page controller, the step counter and
  /// the mascot all have to agree and they used to be updated from three methods.
  void _goTo(int step) {
    setState(() => _step = step);
    _mascot.play(_clipFor(step));
    _page.animateToPage(
      step,
      duration: KoruMotion.quick + const Duration(milliseconds: 120),
      curve: KoruMotion.easeOut,
    );
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
    }
  }

  Future<void> _write() async {
    final store = await ref.read(storeProvider.future);

    await store.put(
        'nickname', _nick.text.trim().isEmpty ? 'friend' : _nick.text.trim());
    await store.put('currency', _currency);

    // The whole point of ending here: the app has something in it before the
    // person ever sees a tab. Blank name means they chose to skip, which is a
    // real answer and not an error.
    final name = _clientName.text.trim();
    if (name.isNotEmpty) {
      final amount = double.tryParse(_clientAmount.text.trim());
      await store.addClient(Client(
        name: name,
        status: 'active',
        amount: amount != null && amount > 0 ? amount : null,
        created: isoDate(DateTime.now()),
      ));
    }

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
                  KoruSpace.gutter, KoruSpace.lg, KoruSpace.gutter, KoruSpace.md),
              child: Row(
                children: [
                  const KoruMark(size: KoruSize.mark),
                  const SizedBox(width: KoruSpace.md),
                  Text('Koru', style: KoruType.title),
                  const Spacer(),
                  // A pill rather than loose text, so the position in the flow
                  // is the same kind of object as the step bar under it rather
                  // than the only loose number on the page.
                  KoruPill(
                    label: '${_step + 1} of $_steps',
                    color: KoruColors.inkSoft,
                    background: KoruColors.surfaceAlt,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: KoruSpace.gutter),
              child: KoruStepBar(step: _step, steps: _steps),
            ),
            Expanded(
              child: PageView(
                controller: _page,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _intro(),
                  _currencyStep(),
                  _firstClientStep(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  KoruSpace.gutter, KoruSpace.md, KoruSpace.gutter, KoruSpace.xl),
              child: Row(
                children: [
                  if (_step > 0) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _back,
                        child: const Text('Back'),
                      ),
                    ),
                    const SizedBox(width: KoruSpace.md),
                  ],
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

  /// The frame every step sits in.
  ///
  /// One definition rather than three: the question, one line of why it is
  /// being asked, and the control.
  Widget _body(String title, String sub, List<Widget> children,
      {bool guide = true}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          KoruSpace.gutter, KoruSpace.lg, KoruSpace.gutter, KoruSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (guide) ...[
            Row(
              children: [
                KoruMascot(size: 54, controller: _mascot, semanticLabel: 'Koru'),
                const SizedBox(width: KoruSpace.md),
                Expanded(
                  child: Text(
                    switch (_clipFor(_step)) {
                      KoruClip.cheer => 'Koru is ready to get going',
                      KoruClip.wave => 'Koru is here',
                      _ => 'Koru is listening',
                    },
                    style:
                        KoruType.bodySmall.copyWith(color: KoruColors.inkSoft),
                  ),
                ),
              ],
            ),
            const SizedBox(height: KoruSpace.md),
          ],
          Text(title, style: KoruType.display),
          const SizedBox(height: KoruSpace.sm),
          Text(sub, style: KoruType.bodyStrong),
          const SizedBox(height: KoruSpace.xl),
          ...children,
        ],
      ),
    );
  }

  Widget _intro() => _body(
        'Meet Koru.',
        'Your clients, your money and what is due — kept on this phone. No '
            'account, and nothing synced anywhere.',
        [
          ClipRRect(
            borderRadius: BorderRadius.circular(KoruRadius.card),
            child: Image.asset(
              'assets/splash/koru_splash.png',
              width: double.infinity,
              fit: BoxFit.cover,
              height: KoruSize.hero,
              excludeFromSemantics: true,
            ),
          ),
          const SizedBox(height: KoruSpace.xl),
          TextField(
            controller: _nick,
            textCapitalization: TextCapitalization.none,
            decoration: const InputDecoration(
              labelText: 'What should I call you?',
              helperText: 'Optional. A nickname, not your real name.',
              hintText: 'nickname',
            ),
          ),
        ],
        guide: false,
      );

  Widget _currencyStep() => _body(
        'What do you get paid in?',
        'Koru counts in one currency so every balance adds up. You can change '
            'it any time in Settings.',
        [
          KoruChoiceGroup(
            label: 'Paid in $_currency',
            children: [
              for (final c in kCurrencies)
                KoruSelectablePill(
                  label: c.code,
                  selected: _currency == c.code,
                  onTap: () => setState(() => _currency = c.code),
                ),
            ],
          ),
        ],
      );

  /// The step that turns onboarding into something the app can do.
  ///
  /// Blank is allowed, because forcing a client out of somebody who came to
  /// look is how an app gets closed before it gets used. But the ask sits here,
  /// where the answer is one sentence and the payoff is the entire app.
  Widget _firstClientStep() {
    final symbol =
        kCurrencies.firstWhere((c) => c.code == _currency).symbol;
    return _body(
      'Add your first client.',
      'One is enough. It puts a name and a number in today, so tomorrow the '
          'app has something to say to you.',
      [
        TextField(
          controller: _clientName,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Client name',
            hintText: 'Bilal',
          ),
        ),
        const SizedBox(height: KoruSpace.md),
        TextField(
          controller: _clientAmount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'What do they owe you?',
            helperText: 'Optional. You can add or change it later.',
            suffixText: symbol,
          ),
        ),
        const SizedBox(height: KoruSpace.lg),
        Text(
          'Nothing here is sent anywhere. No account, no upload.',
          style: KoruType.caption,
        ),
      ],
    );
  }
}
