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
