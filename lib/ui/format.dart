/// Two date formats, and the one place either of them is allowed to be written.
///
/// The store speaks ISO and always will: it is what gets compared, what gets
/// sorted and what gets parsed back. A date a person reads is a different thing
/// entirely, and the app used to show the raw ISO string in three places — a
/// date button in a form, a toast after a write, and a retainer panel.
///
/// Both lived as private helpers in whichever screen needed them first, which is
/// how "04/03/2026" and "4 Mar 2026" and "2026-03-04" all ended up on the same
/// screen.
library;

/// The date in the format the store speaks.
///
/// Always this, at every boundary. Never a formatted string.
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// The date as a person reads it: "4 Mar 2026".
///
/// Day first and month abbreviated, because that is the order the app has used
/// everywhere else for years and changing it now would make this one control
/// disagree with the deadline rows above it.
String readableDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}