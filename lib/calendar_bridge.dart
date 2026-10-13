import 'package:device_calendar/device_calendar.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Hands a calendar entry to the phone's own calendar.
///
/// The in-app calendar is always the truth: it works with no permission, no
/// plugin and no account. This bridge only mirrors an entry outward, so every
/// failure here is swallowed into a `false` rather than thrown, because a
/// calendar the user cannot see on their phone is a missing convenience and a
/// crashed save is a missing record.
///
/// Deliberately thin. There is no background sync, no two-way merge and no
/// deletion mirroring: an entry is copied once, at the moment the user approves
/// it, and the phone's copy is then the phone's business. Two calendars trying
/// to be each other is how a meeting ends up in neither.
class CalendarBridge {
  const CalendarBridge();

  static final DeviceCalendarPlugin _plugin = DeviceCalendarPlugin();
  static bool _tzLoaded = false;

  /// The phone's own time zone, so an entry written at 3pm reads as 3pm.
  ///
  /// The tz database is bundled with the timezone package and loaded once per
  /// process; a phone that will not name its zone falls back to UTC, which is
  /// still a real moment rather than a crash.
  static Future<tz.Location> _deviceZone() async {
    if (!_tzLoaded) {
      tzdata.initializeTimeZones();
      _tzLoaded = true;
    }
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      final identifier = info.identifier;
      final named = tz.timeZoneDatabase.locations[identifier];
      if (named != null) tz.setLocalLocation(named);
    } catch (_) {
      // Nothing to surface. The event still lands at the instant the user
      // meant; only the label could be off on a phone that refuses to say.
    }
    return tz.local;
  }

  /// Whether the app may write to the phone's calendar. Never throws: a plugin
  /// that cannot answer counts as "no".
  Future<bool> get hasPermission async {
    try {
      final result = await _plugin.hasPermissions();
      return result.isSuccess && (result.data ?? false);
    } catch (_) {
      return false;
    }
  }

  /// Asks for the permission. Returns whether it was granted.
  Future<bool> requestPermission() async {
    try {
      final result = await _plugin.requestPermissions();
      return result.isSuccess && (result.data ?? false);
    } catch (_) {
      return false;
    }
  }

  /// Copies one event to the phone's calendar.
  ///
  /// [start] must be non-null: the calendar on the phone has no concept of an
  /// entry with no moment, so an all-day entry gets its date at midnight and
  /// runs for an hour. Returns whether the copy landed, and never throws.
  Future<bool> addEvent({
    required String title,
    required DateTime start,
    DateTime? end,
    String? location,
  }) async {
    try {
      if (!await hasPermission && !await requestPermission()) return false;

      // The first writable calendar. A phone with several accounts and no
      // obvious primary still gets the first one that says it accepts events,
      // which is the one the user sees by default on almost every device.
      final calendars = await _plugin.retrieveCalendars();
      final list = calendars.data;
      if (!calendars.isSuccess || list == null || list.isEmpty) return false;
      Calendar? target;
      for (final c in list) {
        // null counts as writable: some providers simply do not say.
        if (c.id != null && c.isReadOnly != true) {
          target = c;
          break;
        }
      }
      final calendarId = target?.id;
      if (calendarId == null) return false;

      final zone = await _deviceZone();
      final since = tz.TZDateTime.from(start, zone);
      final until = tz.TZDateTime.from(
          end ?? start.add(const Duration(hours: 1)), zone);
      final result = await _plugin.createOrUpdateEvent(Event(
        calendarId,
        title: title,
        start: since,
        end: until,
        location: location,
      ));
      return result != null && result.isSuccess;
    } catch (_) {
      return false;
    }
  }
}
