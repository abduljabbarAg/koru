package com.abduljabbar.koru

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Holds the cloud API key in the Android keystore.
 *
 * The key is encrypted with an AES key that never leaves the keystore, so what
 * lands in SharedPreferences is ciphertext. This is the piece that makes the
 * Settings copy honest: the previous implementation kept the key in a
 * StateProvider, which is memory only.
 *
 * The interface is deliberately three methods, and every one of them returns
 * safely rather than throwing, so a keystore that is unavailable degrades to "the
 * key does not persist" instead of taking the app down.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "koru/secure_key"
    private val prefsName = "koru_secrets"
    private val keyAlias = "koru_cloud_key"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "read" -> result.success(readSecret())
                    "write" -> result.success(writeSecret(call.arguments as? String ?: ""))
                    "delete" -> {
                        prefs().edit().remove("cloud_key").apply()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun prefs() = getSharedPreferences(prefsName, Context.MODE_PRIVATE)

    private fun readSecret(): String {
        val stored = prefs().getString("cloud_key", null) ?: return ""
        return try {
            decrypt(stored) ?: ""
        } catch (e: Exception) {
            // A key that cannot be decrypted, for example after the keystore was
            // invalidated by a reinstall, is treated as absent.
            prefs().edit().remove("cloud_key").apply()
            ""
        }
    }

    private fun writeSecret(value: String): Boolean {
        if (value.isEmpty()) {
            prefs().edit().remove("cloud_key").apply()
            return true
        }
        return try {
            val encrypted = encrypt(value)
            prefs().edit().putString("cloud_key", encrypted).apply()
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun secretKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = keyStore.getKey(keyAlias, null)
        if (existing is SecretKey) return existing

        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                keyAlias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build()
        )
        return generator.generateKey()
    }

    private fun encrypt(value: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        val payload = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        // iv and ciphertext are stored together: base64(iv || ciphertext).
        val combined = cipher.iv + payload
        return Base64.encodeToString(combined, Base64.NO_WRAP)
    }

    private fun decrypt(stored: String): String? {
        val combined = Base64.decode(stored, Base64.NO_WRAP)
        if (combined.size <= 12) return null
        val iv = combined.copyOfRange(0, 12)
        val payload = combined.copyOfRange(12, combined.size)

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(128, iv))
        return String(cipher.doFinal(payload), Charsets.UTF_8)
    }
}
