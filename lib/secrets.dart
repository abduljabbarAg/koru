import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where the cloud key lives.
///
/// Settings used to say "stored on this device" while the key sat in a
/// [StateProvider], which means in memory only: it vanished on every restart,
/// and "delete all local data" did not touch it because it was never in the
/// database in the first place.
///
/// The implementation is deliberately behind an interface so tests can inject a
/// fake and so the storage choice can change without touching callers.
abstract class KeyStore {
  Future<String> readKey();

  Future<void> writeKey(String value);

  Future<void> clearKey();
}

/// Real implementation, backed by the platform keystore.
class PlatformKeyStore implements KeyStore {
  const PlatformKeyStore();

  @override
  Future<String> readKey() => SecureKeyStore.read();

  @override
  Future<void> writeKey(String value) => SecureKeyStore.write(value);

  @override
  Future<void> clearKey() => SecureKeyStore.delete();
}

/// In-memory implementation. Used by tests, and as the fallback when the
/// platform keystore is unavailable, so a keystore failure degrades to "the key
/// does not persist" instead of a crash.
class MemoryKeyStore implements KeyStore {
  String? _key;

  @override
  Future<String> readKey() async => _key ?? '';

  @override
  Future<void> writeKey(String value) async => _key = value;

  @override
  Future<void> clearKey() async => _key = null;
}

final secretsProvider = Provider<KeyStore>((ref) => const PlatformKeyStore());

/// Thin wrapper so the platform channel has exactly one call site.
///
/// Every method swallows a platform failure and returns a safe value. A keystore
/// that throws on an emulator should not take the chat screen down with it.
class SecureKeyStore {
  const SecureKeyStore._();

  static const MethodChannel _channel = MethodChannel('koru/secure_key');

  static Future<String> read() async {
    try {
      final value = await _channel.invokeMethod<String>('read');
      return value ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<void> write(String value) async {
    try {
      await _channel.invokeMethod<void>('write', value);
    } catch (_) {
      // Ignored on purpose, see above.
    }
  }

  static Future<void> delete() async {
    try {
      await _channel.invokeMethod<void>('delete');
    } catch (_) {
      // Ignored on purpose, see above.
    }
  }
}
