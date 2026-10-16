import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../currency.dart';
import '../state.dart';
import '../theme.dart';

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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
        children: const [_CurrencyCard()],
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Everything is counted in ${current.code}.',
              style: TextStyle(fontSize: 13.5, color: KoruColors.ink, height: 1.4),
            ),
            const SizedBox(height: 4),
            Text(
              'Only how amounts are written and what the model is told. Your '
              'figures stay exactly as they are.',
              style: TextStyle(fontSize: 12.5, color: KoruColors.inkFaint, height: 1.45),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in kCurrencies)
                  InkWell(
                    onTap: () async {
                      final store = await ref.read(storeProvider.future);
                      await store.put('currency', c.code);
                      ref.invalidate(currencyProvider);
                    },
                    borderRadius: BorderRadius.circular(KoruRadius.pill),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: current == c ? KoruColors.leafSoft : KoruColors.surface,
                        borderRadius: BorderRadius.circular(KoruRadius.pill),
                        border: Border.all(
                          color: current == c ? KoruColors.leaf : KoruColors.line,
                          width: current == c ? 1.6 : 1,
                        ),
                      ),
                      child: Text(
                        c.code,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: current == c ? FontWeight.w700 : FontWeight.w500,
                          color: KoruColors.ink,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
