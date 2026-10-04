import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state.dart';
import 'theme.dart';
import 'widgets.dart';

/// Onboarding is the highest-leverage screen in the product: without context a
/// memory-based companion has nothing to remember against. Kept to 8 taps.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _page = PageController();
  int _step = 0;

  final _nick = TextEditingController();
  String? _stage;
  String? _biz;
  final _goals = TextEditingController();
  final _weight = TextEditingController();
  final _height = TextEditingController();
  String? _help;

  static const _stages = ['Student', 'Early career', 'Mid career', 'Senior', 'Running a business'];
  static const _bizs = [
    'Solo / freelancer',
    'Small company',
    'Employee',
    'No business yet',
  ];
  static const _helps = ['Career', 'Business growth', 'Fitness', 'Learning', 'All of it'];

  @override
  void dispose() {
    _page.dispose();
    _nick.dispose();
    _goals.dispose();
    _weight.dispose();
    _height.dispose();
    super.dispose();
  }

  void _next() {
    if (_step < 5) {
      setState(() => _step++);
      _page.animateToPage(_step,
          duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
    } else {
      _save();
    }
  }

  void _back() {
    if (_step == 0) return;
    setState(() => _step--);
    _page.animateToPage(_step,
        duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
  }

  Future<void> _save() async {
    final store = await ref.read(storeProvider.future);
    final w = double.tryParse(_weight.text.trim());
    final h = double.tryParse(_height.text.trim());
    final bmi = (w != null && h != null && h > 0) ? w / (h * h) : null;

    await store.put('nickname', _nick.text.trim().isEmpty ? 'friend' : _nick.text.trim());
    await store.put('stage', _stage ?? '');
    await store.put('business', _biz ?? '');
    await store.put('goals', _goals.text.trim());
    await store.put('help_focus', _help ?? '');
    if (w != null) await store.put('weight', '$w');
    if (h != null) await store.put('height', '$h');
    if (bmi != null) await store.put('bmi', bmi.toStringAsFixed(1));
    await store.put(
      'fitness_summary',
      bmi == null
          ? 'no measurements yet'
          : 'weight ${w.toStringAsFixed(1)}kg, height ${h.toStringAsFixed(2)}m, BMI ${bmi.toStringAsFixed(1)}',
    );
    await store.completeOnboarding();
    ref.invalidate(packetProvider);
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
                  Text('${_step + 1} of 6',
                      style: const TextStyle(color: KoruColors.inkFaint, fontSize: 13)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: List.generate(6, (i) {
                  return Expanded(
                    child: Container(
                      height: 4,
                      margin: EdgeInsets.only(right: i == 5 ? 0 : 6),
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
                  _measures(),
                  _goalsScreen(),
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
                      child: Text(_step == 5 ? 'Start' : 'Continue'),
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

  Widget _body(String title, String sub, List<Widget> children) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
        'An assistant that remembers you.',
        'Your life, your work, your training. Everything stays on this phone. '
            'No account, no real name.',
        [
          const SizedBox(height: 8),
          const KoruFeature(icon: Icons.lock_outline_rounded, title: 'Local by default',
              body: 'Your data never leaves this device.'),
          const KoruFeature(icon: Icons.drafts_outlined, title: 'Drafts, never sends',
              body: 'Messages are written for you to approve.'),
          const KoruFeature(icon: Icons.people_outline_rounded, title: 'Knows when to step aside',
              body: 'Some questions deserve a real person.'),
        ],
      );

  Widget _nickName() => _body(
        'What should I call you?',
        'A nickname only. It stays on this device and is never sent anywhere.',
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

  Widget _measures() => _body(
        'Your starting numbers.',
        'Weight and height give me a BMI baseline. Add waist, chest, arms and legs '
            'as you go and I can track progress properly.',
        [
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _weight,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Weight', suffixText: 'kg'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _height,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Height', suffixText: 'm'),
                ),
              ),
            ],
          ),
        ],
      );

  Widget _goalsScreen() => _body(
        'Last one. What do you want to be true in three months?',
        'Be specific. This is what I will hold you to.',
        [
          const SizedBox(height: 8),
          TextField(
            controller: _goals,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'e.g. two more clients, train 3x a week, finish the course',
            ),
          ),
          const SizedBox(height: 18),
          const SectionLabel('I want most help with'),
          ..._helps.map((h) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ChoiceChip(
                  label: Text(h),
                  selected: _help == h,
                  onSelected: (s) => setState(() => _help = s ? h : null),
                  selectedColor: KoruColors.leafSoft,
                  side: const BorderSide(color: KoruColors.line),
                  labelStyle: TextStyle(
                      color: KoruColors.ink, fontWeight: _help == h ? FontWeight.w600 : FontWeight.w500),
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