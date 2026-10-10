import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state.dart';

/// The money the app counts in.
///
/// Amounts are stored as bare doubles, so this is a display and prompt concern
/// only. Nothing here needs a migration, and nothing stored changes meaning if
/// the user switches: 2000 is 2000 in every currency, it is the label and the
/// model that need to be right.
///
/// The full set of currencies is deliberately small. A freelancer is almost
/// certainly paid in their own currency or in dollars, and a list of forty
/// options is a list where nobody finds theirs.
class Currency {
  const Currency(this.code, this.symbol, this.label);

  /// Three letter code, which is also what the model is told to use.
  final String code;

  /// What the amount field shows.
  final String symbol;

  final String label;

  @override
  bool operator ==(Object other) => other is Currency && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => code;
}

const kCurrencies = <Currency>[
  Currency('AED', 'AED', 'UAE dirham'),
  Currency('USD', r'$', 'US dollar'),
  Currency('EUR', '€', 'Euro'),
  Currency('GBP', '£', 'Pound sterling'),
  Currency('PKR', 'Rs', 'Pakistani rupee'),
  Currency('INR', '₹', 'Indian rupee'),
  Currency('NGN', '₦', 'Nigerian naira'),
  Currency('KES', 'KSh', 'Kenyan shilling'),
  Currency('ZAR', 'R', 'South African rand'),
  Currency('CAD', r'C$', 'Canadian dollar'),
  Currency('AUD', r'A$', 'Australian dollar'),
];

const defaultCurrency = Currency('AED', 'AED', 'UAE dirham');

Currency currencyFromCode(String? code) {
  if (code == null) return defaultCurrency;
  for (final c in kCurrencies) {
    if (c.code == code) return c;
  }
  return defaultCurrency;
}

/// The currency in use, read once so every screen agrees.
final currencyProvider = FutureProvider<Currency>((ref) async {
  final store = await ref.watch(storeProvider.future);
  return currencyFromCode(await store.get('currency'));
});
