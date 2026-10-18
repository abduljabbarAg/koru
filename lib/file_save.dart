import 'package:flutter/services.dart';

/// Saving a file the user asked for, through the Android side.
///
/// A backup used to be only shareable: the file was written to the app's own
/// temporary folder and handed to the share sheet, so the one plain option —
/// keep a copy on this phone — did not exist. This writes it to Downloads and
/// says where it landed, which is the version of "save my data" that does not
/// depend on any other app being installed.
///
/// Returns null when the save failed, rather than a guessed path. A save that
/// reports success without one is exactly how a backup ends up not existing
/// when it is needed.
class FileSave {
  const FileSave();

  static const _channel = MethodChannel('koru/files');

  /// Writes [content] to the phone's Downloads folder under [name].
  ///
  /// Null on any failure, including the platform not being Android. Callers
  /// show the outcome either way; there is nothing to retry silently.
  Future<String?> saveToDownloads(String name, String content) async {
    try {
      return await _channel.invokeMethod<String>('saveToDownloads', {
        'name': name,
        'content': content,
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      // Desktop and tests. There is no Downloads folder to write to there.
      return null;
    }
  }
}
