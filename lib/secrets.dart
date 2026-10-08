import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where API keys live, one per provider.
///
/// A key that fails to save used to be reported as saved. The UI toasted
/// "Key saved to the keystore" no matter what happened underneath, so a
/// keystore that refused the write looked identical to one that worked, and the
/// next symptom was "nothing responds". [KeyStore.write] now returns whether it
/// actually worked.
abstract class KeyStore {
  Future<String> readKey(String providerId);

  /// Returns true only when the value is durably stored.
  Future<bool> writeKey(String providerId, String value);

  Future<bool> clearKey(String providerId);
}

/// Real implementation, backed by the platform keystore.
class PlatformKeyStore implements KeyStore {
  const PlatformKeyStore();

  @override
  Future<String> readKey(String providerId) => SecureKeyStore.read(providerId);

  @override
  Future<bool> writeKey(String providerId, String value) =>
      SecureKeyStore.write(providerId, value);

  @override
  Future<bool> clearKey(String providerId) => SecureKeyStore.delete(providerId);
}

/// In-memory implementation, used by tests.
class MemoryKeyStore implements KeyStore {
  final Map<String, String> _keys = {};

  @override
  Future<String> readKey(String providerId) async => _keys[providerId] ?? '';

  @override
  Future<bool> writeKey(String providerId, String value) async {
    if (value.isEmpty) {
      _keys.remove(providerId);
    } else {
      _keys[providerId] = value;
    }
    return true;
  }

  @override
  Future<bool> clearKey(String providerId) async {
    _keys.remove(providerId);
    return true;
  }
}

final secretsProvider = Provider<KeyStore>((ref) => const PlatformKeyStore());

/// Thin wrapper so the platform channel has exactly one call site.
///
/// Reads return empty rather than throwing when the keystore is unavailable, so
/// an emulator without a keystore degrades to "no key saved" instead of a crash.
/// Writes return false instead of throwing, so the UI can say so.
class SecureKeyStore {
  const SecureKeyStore._();

  static const MethodChannel channel = MethodChannel('koru/secure_key');

  static Future<String> read(String providerId) async {
    try {
      return await channel.invokeMethod<String>('read', providerId) ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<bool> write(String providerId, String value) async {
    try {
      final ok = await channel.invokeMethod<bool>('write', <String, String>{
        'id': providerId,
        'value': value,
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> delete(String providerId) async {
    try {
      final ok = await channel.invokeMethod<bool>('delete', providerId);
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }
}
