package com.abduljabbar.koru

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Holds the cloud API key in the Android keystore, and runs the bundled
 * inference engine.
 *
 * Keys are encrypted with an AES key that never leaves the keystore, so what
 * lands in SharedPreferences is ciphertext. One entry per provider, so several
 * can coexist.
 *
 * The engine section is the awkward part and needs explaining, because it is not
 * a stylistic choice:
 *
 * Since Android 10, an app targeting API 29 or newer is not allowed to exec a
 * file it wrote itself. Anything unpacked into the app's data directory is off
 * limits. Files extracted from the APK into nativeLibraryDir are still
 * executable, which is why glen ships as a native library rather than as an
 * asset, and why it is launched from there instead of being copied somewhere
 * more convenient.
 *
 * Every method reports failure honestly. An earlier version of this class
 * swallowed its exceptions, and the UI reported a refused keystore write as a
 * successful one, which surfaced much later as "nothing responds".
 */
class MainActivity : FlutterActivity() {

    private val channelName = "koru/secure_key"
    private val engineChannelName = "koru/local_engine"
    private val prefsName = "koru_secrets"
    private val keyAlias = "koru_cloud_key"

    /** Default loopback port for the bundled engine. */
    private val enginePort = 8099

    private var engine: Process? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "read" -> result.success(readSecret(call.arguments as? String ?: ""))
                "write" -> {
                    val id = call.argument<String>("id") ?: ""
                    val value = call.argument<String>("value") ?: ""
                    result.success(writeSecret(id, value))
                }
                "delete" -> {
                    prefs().edit().remove(storedKey(call.arguments as? String ?: "")).apply()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, engineChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(engineStatus())
                "start" -> result.success(startEngine(call.argument<Int>("port") ?: enginePort))
                "stop" -> {
                    stopEngine()
                    result.success(true)
                }
                "log" -> result.success(engineLog())
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        stopEngine()
        super.onDestroy()
    }

    // ---------------------------------------------------------------- engine

    /**
     * The bundled glen binary.
     *
     * Lives in nativeLibraryDir because that is the only place this app can
     * still exec from on a modern Android. null when the APK was built without
     * it, which the Dart side treats as "no bundled engine" rather than an error.
     */
    private fun engineBinary(): File? {
        val candidate = File(applicationInfo.nativeLibraryDir, "libglen.so")
        return if (candidate.exists() && candidate.canExecute()) candidate else null
    }

    /**
     * A diagnostic map rather than a bare boolean.
     *
     * The binary was present in the APK and the app still said "no bundled
     * model", because modern Android maps native libraries straight out of the
     * package instead of extracting them, so the file this app looks for was
     * never created. A boolean cannot tell you that; these fields can.
     */
    private fun engineStatus(): Map<String, Any?> {
        val candidate = File(applicationInfo.nativeLibraryDir, "libglen.so")
        val usable = candidate.exists() && candidate.canExecute()
        val model = modelFile()
        // modelFile() has already been called above, so a first run has
        // materialised it.
        val reason = when {
            usable -> null
            !candidate.exists() ->
                "libglen.so is not in ${applicationInfo.nativeLibraryDir}. " +
                    "Native libraries were probably not extracted, so there is " +
                    "nothing on disk to run."
            !candidate.canExecute() ->
                "libglen.so is at ${candidate.absolutePath} but is not marked executable."
            else -> "unknown"
        }
        return mapOf(
            "available" to usable,
            "path" to candidate.absolutePath,
            "exists" to candidate.exists(),
            "executable" to candidate.canExecute(),
            "modelPath" to model?.absolutePath,
            "modelAvailable" to (model != null),
            "reason" to reason,
        )
    }

    /**
     * The model, copied out of the APK's assets on first use.
     *
     * Assets cannot be mmapped directly out of the compressed APK, so the file is
     * materialised into the app's own storage where glen's mmap loader can use
     * it.
     */
    private fun modelFile(): File? {
        val target = File(filesDir, "models/qwen2.5-0.5b-instruct-q4_k_m.gguf")
        if (target.exists() && target.length() > 1_000_000) return target
        val assetName = "assets/models/qwen2.5-0.5b-instruct-q4_k_m.gguf"
        return try {
            assets.open(assetName).use { input ->
                target.parentFile?.mkdirs()
                target.outputStream().use { output -> input.copyTo(output, 1 shl 16) }
            }
            if (target.exists() && target.length() > 1_000_000) target else null
        } catch (e: Exception) {
            // Asset absent. Not an error: the app still works with an external
            // server, it just cannot start the bundled engine.
            target.delete()
            null
        }
    }

    /**
     * Launches glen and reports whether the process is alive.
     *
     * The first launch copies several hundred megabytes out of the APK, so it is
     * allowed to take a while. The Dart side polls /health rather than trusting
     * the return value, because a process can be alive and still be loading.
     */
    private fun startEngine(requestedPort: Int): Boolean {
        val binary = engineBinary() ?: return false
        val model = modelFile() ?: return false
        if (engine?.isAlive == true) return true

        val log = File(filesDir, "glen.log")
        return try {
            log.delete()
            val builder = ProcessBuilder(
                binary.absolutePath,
                "--serve",
                requestedPort.toString(),
            )
            builder.environment()["Glen_MODEL"] = model.absolutePath
            // Tools off: the bundled engine must not be able to run shell
            // commands or reach the network on its own.
            builder.environment()["Glen_TOOLS"] = "0"
            builder.environment()["Glen_CTX"] = "1024"
            builder.redirectErrorStream(true)
            builder.redirectOutput(log)
            builder.directory(filesDir)

            val started = builder.start()
            engine = started
            // Deliberately not waited on: the process outlives this call, and a
            // reaper thread would race with onDestroy.
            Thread {
                try {
                    started.waitFor()
                } catch (e: InterruptedException) {
                    Thread.currentThread().interrupt()
                }
            }.apply { isDaemon = true }.start()
            started.isAlive
        } catch (e: Exception) {
            engine = null
            false
        }
    }

    private fun stopEngine() {
        engine?.let { running ->
            try {
                running.destroy()
                if (!running.waitFor(3, java.util.concurrent.TimeUnit.SECONDS)) {
                    running.destroyForcibly()
                }
            } catch (e: Exception) {
                // Already gone.
            }
        }
        engine = null
    }

    private fun engineLog(): String {
        val log = File(filesDir, "glen.log")
        if (!log.exists()) return ""
        return try {
            log.readText().takeLast(4000)
        } catch (e: Exception) {
            ""
        }
    }

    // ----------------------------------------------------------------- keys

    /** One encrypted entry per provider, so several keys can coexist. */
    private fun storedKey(providerId: String) = "cloud_key_$providerId"

    private fun readSecret(providerId: String): String {
        val stored = prefs().getString(storedKey(providerId), null) ?: return ""
        return try {
            decrypt(stored) ?: ""
        } catch (e: Exception) {
            // A key that cannot be decrypted, for example after the keystore was
            // invalidated by a reinstall, is treated as absent.
            prefs().edit().remove(storedKey(providerId)).apply()
            ""
        }
    }

    /**
     * Reports honestly.
     *
     * This used to swallow the outcome and the UI toasted success regardless,
     * so a refused write looked exactly like a good one and the symptom was
     * "nothing responds" much later.
     */
    private fun writeSecret(providerId: String, value: String): Boolean {
        if (value.isEmpty()) {
            prefs().edit().remove(storedKey(providerId)).apply()
            return true
        }
        return try {
            val encrypted = encrypt(value)
            prefs().edit().putString(storedKey(providerId), encrypted).apply()
            // Confirm it landed rather than assuming it did.
            prefs().getString(storedKey(providerId), null) == encrypted
        } catch (e: Exception) {
            false
        }
    }

    private fun prefs() = getSharedPreferences(prefsName, Context.MODE_PRIVATE)

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