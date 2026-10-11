import 'dart:convert';

import 'package:flutter/services.dart';

import 'attention.dart';
import 'deep_link.dart';

/// Talks to the Android side about notifications and the background watcher.
///
/// The split is deliberate. Everything about *what* is worth saying is Dart, in
/// [Attention], where it can be tested without a device. Everything about
/// *showing* it is Kotlin. Neither half is allowed to decide anything the other
/// half already knows, because two implementations of "who owes you money" is
/// how a notification and the app end up disagreeing in front of the user.
class AttentionBridge {
  const AttentionBridge();

  static const _channel = MethodChannel('koru/attention');

  /// Whether the system will actually show anything.
  ///
  /// False on Android 13+ until notifications are granted, and false whenever
  /// the user has turned them off in settings. Both look identical from inside
  /// the app otherwise, and the honest thing to do about that is say so rather
  /// than appear to be working.
  Future<bool> canPost() async {
    try {
      return await _channel.invokeMethod<bool>('canPost') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      // Desktop and tests. No notifications there, which is correct.
      return false;
    }
  }

  /// Starts or updates the foreground service with what is worth saying.
  ///
  /// Passing an empty list is not an error and not a special case: it is the
  /// normal state of a person who is on top of things, and it must actively
  /// clear the badge rather than leave yesterday's count on the icon.
  Future<bool> publish(List<AttentionItem> items, {KoruDeepLink? link}) async {
    try {
      final ok = await _channel.invokeMethod<bool>('update', {
        'payload': _encode(items, link),
      });
      return ok ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> start() async {
    try {
      return await _channel.invokeMethod<bool>('start', {
        'payload': _encode(const [], null),
      }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Repaints the home screen widget, if one is placed.
  ///
  /// Returns false when there is no widget, which is the common case. Callers
  /// ignore it: not having placed a widget is not an error, it is just nobody
  /// having asked for one yet.
  Future<bool> updateWidget(List<AttentionItem> items) async {
    try {
      return await _channel.invokeMethod<bool>('updateWidget', {
        'count': items.length,
        'headline': Attention.headline(items),
        'top': Attention.top(items),
        'mood': moodFor(items),
      }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Which face the character wears.
  ///
  /// Derived from the same list that drives the notification, because a widget
  /// showing a calm character next to an overdue invoice is worse than no
  /// character at all. Deliberately only four states: a face that changes with
  /// every possible situation stops being readable, and the point is that it
  /// means something.
  ///
  /// Nothing outstanding is cheer, not idle. There is a difference between
  /// "nothing is wrong" and "I do not know what is going on", and showing the
  /// same calm face for both throws away the one time the character is actually
  /// saying something good.
  static String moodFor(List<AttentionItem> items) {
    if (items.isEmpty) return 'cheer';
    final urgent = items.any((i) =>
        i.kind == AttentionKind.overdueMoney ||
        i.kind == AttentionKind.dueToday ||
        i.kind == AttentionKind.dueSoon);
    return urgent ? 'thinking' : 'wave';
  }

  /// Stops the service and removes the ongoing notification.
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<bool>('stop');
    } on PlatformException {
      // Already gone, or never started. Either way there is nothing to undo.
    } on MissingPluginException {
      // Not a platform with notifications.
    }
  }

  Future<bool> clear() async {
    try {
      return await _channel.invokeMethod<bool>('clear') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Takes a link that was waiting for Dart to be ready.
  ///
  /// Read once, on a cold start, because a notification tap usually gets there
  /// before Flutter has finished booting. Without this the app opens to the home
  /// screen and the tap looks like it did nothing.
  Future<KoruDeepLink?> takeLink() async {
    try {
      final raw = await _channel.invokeMethod<String>('takeLink');
      return KoruDeepLink.decode(raw);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Listens for a link arriving while the app is already open.
  void listen(void Function(KoruDeepLink link) onLink) {
    try {
      _channel.setMethodCallHandler((call) async {
        if (call.method != 'openLink') return null;
        final link = KoruDeepLink.decode(call.arguments as String?);
        if (link != null) onLink(link);
        return null;
      });
    } on MissingPluginException {
      // No platform side, nothing to listen to.
    }
  }

  /// JSON rather than a map.
  ///
  /// The Kotlin side reads this with JSONObject, and the two have to agree: a
  /// Map crossing a method channel arrives as a map on the other end, not as the
  /// string the parser is waiting for, so sending the nicer-looking type would
  /// have failed at runtime and in a way no Dart test could see. JSON is an
  /// explicit contract between the two halves instead.
  String _encode(List<AttentionItem> items, KoruDeepLink? link) => jsonEncode({
        'count': items.length,
        'headline': Attention.headline(items),
        'top': Attention.top(items),
        // Null rather than an empty string when there is nothing to open: a
        // notification with nowhere to go is worse than one that just opens the
        // app, because it looks broken rather than empty.
        'link': link?.encode(),
      });
}

/// What the app needs from the system to keep an eye on things, and whether it
/// has it.
///
/// Deliberately not a single "is everything fine" boolean. Each of these can be
/// refused independently, and a person who declined one needs to be told which
/// one, because "Koru cannot notify you" is not actionable while "Koru cannot
/// post notifications, and its background checks will be stopped by the system"
/// is.
class KoruHealth {
  /// Whether the system will show a notification at all.
  ///
  /// The one that matters most. Everything else is an optimisation; without this
  /// the whole feature is silent and there is no sign of why.
  final bool notifications;

  /// Whether the app is exempt from battery optimisation.
  ///
  /// Without it the system stops the background checks to save power, which is
  /// reasonable behaviour and the single most common reason Koru goes quiet after
  /// a day of not opening the app.
  final bool batteryExempt;

  /// Whether the manufacturer will restart the app by itself.
  ///
  /// Null means the question does not apply, which is every phone that is not
  /// running MIUI or one of its cousins. Shown as "not needed" rather than as a
  /// failed check, because telling someone on a Pixel that autostart is broken
  /// is just wrong.
  final bool? autostart;

  const KoruHealth({
    required this.notifications,
    required this.batteryExempt,
    this.autostart,
  });

  /// The things that would stop Koru working, worst first.
  List<String> get problems => [
        if (!notifications) 'Koru cannot show notifications',
        if (!batteryExempt) 'The system will stop background checks to save power',
        if (autostart == false) 'This phone does not let Koru restart itself',
      ];

  /// True when everything that can be granted has been, or does not apply.
  bool get complete =>
      notifications && batteryExempt && (autostart ?? true);
}

/// Reads and repairs the permissions Koru needs to work when the app is closed.
class HealthBridge {
  const HealthBridge();

  static const _channel = MethodChannel('koru/attention');

  Future<KoruHealth> check() async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('health');
      if (raw == null) return const KoruHealth(notifications: false, batteryExempt: false);
      return KoruHealth(
        notifications: raw['notifications'] == true,
        batteryExempt: raw['batteryExempt'] == true,
        // Deliberately tri-state. "not applicable" has to survive the trip over
        // the channel, and a missing key is how that is expressed.
        autostart: raw.containsKey('autostart') && raw['autostart'] != null
            ? raw['autostart'] == true
            : null,
      );
    } on PlatformException {
      return const KoruHealth(notifications: false, batteryExempt: false);
    } on MissingPluginException {
      // No platform, so nothing to be unhealthy about. Claiming failure here
      // would put three red crosses on screen in every test and on desktop.
      return const KoruHealth(notifications: true, batteryExempt: true);
    }
  }

  /// Asks for battery optimisation exemption.
  ///
  /// Opens the system's own dialog. It cannot be granted silently, and any code
  /// that tries is abusing an install-time permission, so this is a request and
  /// nothing more.
  Future<bool> requestBatteryExempt() =>
      _invokeFlag('requestBatteryExempt');

  /// Opens the notification permission prompt.
  Future<bool> requestNotifications() => _invokeFlag('requestNotifications');

  /// Opens the manufacturer's autostart screen, where such a thing exists.
  ///
  /// Returns false when there is no such screen, which is the normal case off
  /// MIUI and is not an error.
  Future<bool> openAutostartSettings() => _invokeFlag('openAutostartSettings');

  /// Opens the system's app info page, as a way out of anything above.
  Future<bool> openAppSettings() => _invokeFlag('openAppSettings');

  Future<bool> _invokeFlag(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
