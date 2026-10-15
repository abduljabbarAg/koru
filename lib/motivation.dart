/// One line for the morning, chosen by the date.
///
/// Deliberately not a notification and not a card. A quote that arrives as a
/// push is decoration competing with the overdue invoice it sits next to, and
/// the moment it becomes noise the user swipes it away forever. One quiet line
/// at the top of Today, underneath everything that actually needs doing, costs
/// nothing and gets read when the user is already here.
///
/// Chosen by date rather than at random so it does not change every rebuild:
/// scrolling, switching tabs and hot reload all recompute this screen, and a
/// quote that reshuffles on each one reads as a glitch.
library;

class Quote {
  const Quote(this.text, this.by);

  final String text;
  final String by;
}

/// Freelancer-relevant, and short enough to read without thinking about it.
///
/// Kept here rather than fetched, because the app is local-first and this must
/// not be the one thing on the screen that depends on a network.
const List<Quote> _quotes = [
  Quote('Do the hard thing first while you are still awake for it.', 'Koru'),
  Quote(
    'An invoice sent is worth more than an invoice perfect.',
    'Freelance wisdom',
  ),
  Quote('Nobody is coming. Send it.', 'Freelance wisdom'),
  Quote('Scope creep begins as a favour.', 'Freelance wisdom'),
  Quote('Paid today is better than apologised for tomorrow.', 'Freelance wisdom'),
  Quote('You are not behind. You are working.', 'Koru'),
  Quote('The quiet hour before the inbox is yours.', 'Koru'),
  Quote('Say the number out loud before you type it.', 'Freelance wisdom'),
  Quote('Finished and sent beats perfect and pending.', 'Freelance wisdom'),
  Quote('Your rate is not negotiable just because they are nervous.', 'Freelance wisdom'),
  Quote('Chasing early is a habit, not a personality.', 'Koru'),
  Quote('The best project you have is the one that is not over.', 'Koru'),
];

/// The quote for [day], stable for that day.
///
/// Days since the epoch, so the list rotates every [List] days rather than
/// sitting on one quote for a month because somebody opened it on day one.
Quote quoteFor(DateTime day) {
  final epoch = DateTime.utc(2024, 1, 1);
  final d = DateTime.utc(day.year, day.month, day.day);
  final n = d.difference(epoch).inDays;
  // Guard the negative side: a clock set before 2024 would otherwise index
  // backwards and panic on a fresh install.
  final i = n.abs() % _quotes.length;
  return _quotes[i];
}