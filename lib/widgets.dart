/// The app's shared UI vocabulary.
///
/// One import for a screen, and every primitive behind it in one place. The
/// parts are split by what they are rather than by which screen first needed
/// them — surfaces, page chrome, approval cards, the conversation thread, the
/// shapes a list wears while it is still loading — so a new screen reaches for
/// what already exists instead of drawing its own.
///
/// Five rules hold the whole thing together, and all of them are enforced by
/// naming something rather than by a review:
///
///  * Every gap, corner and depth is a member of `KoruSpace`, `KoruRadius` or
///    `KoruElevation`. A number written in a screen is a number that will be
///    written a different way somewhere else.
///  * Every piece of text asks for a role — `KoruType.rowTitle`, `meta`,
///    `metric` — and every colour asks the palette. Nothing in a build method
///    picks its own size, and nothing picks its own `Color`.
///  * One card, one row, one pill, one button. A screen that needs to be
///    different says so through an accent or a tone, never through geometry.
///  * A screen has the same shape whether it is loading, broken, empty or full.
///    The page does not rearrange itself under the reader.
///  * An empty state says what belongs here and what to do next. "No data" is a
///    bug report from the person reading it.
///
/// Nothing here holds state that belongs to a screen, and nothing here knows
/// about providers, so every widget in this library can be built and looked at
/// on its own.
library;

export 'ui/choice.dart';
export 'ui/chrome.dart';
export 'ui/engine_notice.dart';
export 'ui/fields.dart';
export 'ui/format.dart';
export 'ui/marks.dart';
export 'ui/proposals.dart';
export 'ui/states.dart';
export 'ui/surfaces.dart';
export 'ui/thread.dart';

/// Whole units, no decimals.
///
/// Balances are compared and summed constantly and a stray cent should never be
/// the reason two figures that are the same money look different.
String money(double v) {
  if (v.abs() >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
  if (v.abs() >= 10000) return '${(v / 1000).toStringAsFixed(0)}k';
  return v.toStringAsFixed(0);
}