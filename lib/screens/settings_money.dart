import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../currency.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

/// Which money the app counts in, on a page of its own.
///
/// Display and prompt only. Amounts are stored as bare doubles, so switching
/// this changes no stored value and no balance, and there is no migration to
/// think about before someone can change it.
class CurrencySettingsScreen extends StatelessWidget {
  const CurrencySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Currency')),
      body: KoruPagePadding(
        bottom: KoruSpace.xxl,
        child: ListView(children: const [_CurrencyCard()]),
      ),
    );
  }
}

/// The picker itself, unchanged from the old Settings list: a sentence saying
/// what is counted in, then the codes as pills.
class _CurrencyCard extends ConsumerWidget {
  const _CurrencyCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(currencyProvider).valueOrNull ?? defaultCurrency;
    return KoruCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Everything is counted in ${current.code}.',
            style: KoruType.bodyCompactStrong,
          ),
          const SizedBox(height: KoruSpace.xs),
          Text(
            'Only how amounts are written and what the model is told. Your '
            'figures stay exactly as they are.',
            style: KoruType.bodySmall,
          ),
          const SizedBox(height: KoruSpace.mdl),
          // The app's own selectable pill rather than a hand-built one. This was
          // a fourth way of drawing a chosen chip: a 12/9 padding and a 1.6
          // border written out beside the three that already existed.
          KoruFilterBar(
            children: [
              for (final c in kCurrencies)
                KoruSelectablePill(
                  label: c.code,
                  selected: current == c,
                  onTap: () async {
                    final store = await ref.read(storeProvider.future);
                    await store.put('currency', c.code);
                    ref.invalidate(currencyProvider);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}
