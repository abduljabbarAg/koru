/// Dates as people say them.
///
/// "due in 3 days" answers the question; "2026-10-16" makes the reader do the
/// arithmetic to find out whether it matters. Every screen showed the raw ISO
/// date and left the counting to whoever was reading, which is exactly the work
/// the app exists to do.
///
/// The absolute form is still used where precision is the point — a due date on
/// an approval card, where the person is about to agree to it. There, "in 3
/// days" would be a claim about today that has to be trusted rather than
/// checked.
library;

/// How far away a date is, in words.
enum Horizon {
  past,
  today,
  tomorrow,
  /// Within the coming week.
  soon,
  /// Anything further, plus anything unparseable.
  later,
}

/// How a date reads on screen.
enum DateStyle {
  /// "in 3 days", "today", "2 days ago".
  relative,

  /// "Tue 16 Oct", the year added only when it is not this one.
  short,

  /// "16 October 2026".
  long,

  /// "16 Oct 2026", for a confirmation card where the exact date is the point.
  unambiguous,
}

/// Parses an ISO date, tolerating a time part.
///
/// Returns midnight local so that comparing against another midnight does not
/// drift across a day boundary because of a timezone.
DateTime? parseDay(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final d = DateTime.tryParse(raw);
  if (d == null) return null;
  return DateTime(d.year, d.month, d.day);
}

/// Whole days from [from] to [day]. Negative is in the past.
///
/// Counted in calendar days, not elapsed hours, so an entry at 23:00 tonight is
/// "today" all evening and not "in 0.3 days".
int daysBetween(DateTime from, DateTime day) {
  final a = DateTime(from.year, from.month, from.day);
  final b = DateTime(day.year, day.month, day.day);
  return b.difference(a).inDays;
}

/// Which bucket [day] falls in, relative to [from].
Horizon horizonFor(DateTime from, DateTime day) {
  final n = daysBetween(from, day);
  if (n < 0) return Horizon.past;
  if (n == 0) return Horizon.today;
  if (n == 1) return Horizon.tomorrow;
  if (n <= 7) return Horizon.soon;
  return Horizon.later;
}

const _monthsShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const _monthsLong = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

const _daysShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Formats [raw] for a person to read.
///
/// [from] is passed rather than read from the clock so the answer can be checked
/// at a known date instead of only ever being right at whichever moment the test
/// happened to run.
String formatDate(
  String? raw,
  DateTime from, {
  DateStyle style = DateStyle.relative,
}) {
  final day = parseDay(raw);
  if (day == null) return 'no date';
  return formatDay(day, from, style: style);
}

/// [formatDate] for a date already parsed.
String formatDay(
  DateTime day,
  DateTime from, {
  DateStyle style = DateStyle.relative,
}) {
  if (style == DateStyle.relative) {
    return _relative(day, from);
  }
  final m = _monthsShort[day.month - 1];
  final sameYear = day.year == from.year;
  return switch (style) {
    DateStyle.short =>
      '${_daysShort[day.weekday - 1]} ${day.day} $m${sameYear ? '' : ' ${day.year}'}',
    DateStyle.long =>
      '${day.day} ${_monthsLong[day.month - 1]} ${day.year}',
    DateStyle.unambiguous => '${day.day} $m ${day.year}',
    DateStyle.relative => throw StateError('handled above'),
  };
}

String _relative(DateTime day, DateTime from) {
  final n = daysBetween(from, day);
  if (n == 0) return 'today';
  if (n == 1) return 'tomorrow';
  if (n == -1) return 'yesterday';
  if (n < 0) return '${-n} days ago';
  if (n <= 6) return 'in $n days';
  // A week out, "in 8 days" stops being more useful than the date itself.
  if (n <= 13) return 'next week';
  if (n <= 27) return 'in ${(n / 7).round()} weeks';
  if (n <= 45) return 'in a month';
  if (n <= 300) return 'in ${(n / 30).round()} months';
  return 'in over a year';
}

/// "overdue since 3 days ago" style phrasing for a money figure.
String overdueSince(DateTime? day, DateTime from) {
  final d = parseDay(day?.toIso8601String());
  if (d == null) return 'overdue';
  final n = daysBetween(from, d);
  if (n == 0) return 'due today';
  if (n < 0) return 'overdue by ${-n} day${-n == 1 ? '' : 's'}';
  return 'due in $n days';
}