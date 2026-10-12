package com.abduljabbar.koru

import android.content.Context
import android.content.Intent
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
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
    private val attentionChannelName = "koru/attention"

    private val prefsName = "koru_secrets"
    private val keyAlias = "koru_cloud_key"

    /** Default loopback port for the bundled engine. */
    private val enginePort = 8099

    private var engine: Process? = null

    /** Notifications and the background attention service. */
    private var attention: AttentionBridge? = null

    /**
     * A Koru link waiting to be handed to Dart.
     *
     * The tap can arrive before Flutter is ready, and quite often does, because
     * a notification tap launches a process that is not running. Holding the link
     * here and draining it once Dart asks is what makes a cold start from a
     * notification work at all; the other option is silently opening the app to
     * the home screen, which looks exactly like the tap not working.
     */
    private var pendingLink: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        val attentionService = AttentionBridge()
        attentionService.attach(applicationContext)
        attention = attentionService
        val attentionChannel = MethodChannel(messenger, attentionChannelName)
        attentionChannel.setMethodCallHandler(attentionService)
        attentionService.bind(attentionChannel)
        attentionService.onLinkReady { drainPendingLink() }
        attentionService.bindActivity(this)

        // A link that arrived with the intent that launched us.
        pendingLink = linkFrom(intent)

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
                "models" -> result.success(
                    availableModels().map { (label, file) ->
                        mapOf("label" to label, "path" to file.absolutePath)
                    }
                )
                "start" -> result.success(
                    startEngine(
                        call.argument<Int>("port") ?: enginePort,
                        call.argument<String>("modelPath"),
                    )
                )
                "stop" -> {
                    stopEngine()
                    result.success(true)
                }
                "log" -> result.success(engineLog())
                else -> result.notImplemented()
            }
        }
    }

    /**
     * A tap on a notification while the app is already running.
     *
     * singleTop in the manifest means this is called instead of the activity
     * being rebuilt, which is what keeps the current conversation instead of
     * throwing it away and showing the home screen.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        linkFrom(intent)?.let {
            pendingLink = it
            attention?.drainPendingLink()
        }
    }

    override fun onDestroy() {
        attention?.bindActivity(null)
        stopEngine()
        super.onDestroy()
    }


    // ------------------------------------------------------------- attention

    /** Our own links only. Anything else on the device is ignored. */
    private fun linkFrom(intent: Intent?): String? {
        val data = intent?.data ?: return null
        if (data.scheme != "koru" || data.host != "attention") return null
        return data.toString()
    }

    /**
     * Hands over a waiting link and clears it.
     *
     * Cleared as it is read, so one tap cannot replay the same destination every
     * time the app is next built.
     */
    private fun drainPendingLink(): String? {
        val link = pendingLink ?: return null
        pendingLink = null
        return link
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
    /**
     * Where a dropped model can be found.
     *
     * The app's private directory is not browsable from a file manager on an
     * unrooted phone, so a model a person downloaded themselves would be
     * impossible to place there. The external app directory is reachable from
     * Downloads without any permission, which is what makes "bring your own
     * model" possible at all.
     */
    private fun modelDirs(): List<File> = listOf(
        File(filesDir, "models"),
        // /sdcard/Android/data/<package>/files/models
        File(getExternalFilesDir(null) ?: filesDir, "models"),
    )

    /**
     * Every model glen could be pointed at, bundled first.
     *
     * Listed rather than hardcoded because the bundled 0.5B is no longer the
     * best thing this phone can run: a 1.7B ternary model fits in about 600 MB
     * resident and is markedly sharper, but it is 442 MB to download and putting
     * both in the APK would take it past 900 MB for every install to serve a
     * choice most people make once.
     */
    private fun availableModels(): List<Pair<String, File>> {
        val out = mutableListOf<Pair<String, File>>()
        modelFile()?.let { out.add("Qwen2.5 0.5B (bundled, fast)" to it) }
        for (dir in modelDirs()) {
            val files = dir.listFiles { f -> f.isFile && f.name.endsWith(".gguf") } ?: continue
            for (f in files.sortedBy { it.name }) {
                if (f.length() < 1_000_000) continue
                // The bundled one is already listed; do not offer it twice.
                if (out.any { pair -> pair.second.absolutePath == f.absolutePath }) continue
                val mb = f.length() / (1024 * 1024)
                out.add("${f.nameWithoutExtension} (${mb} MB)" to f)
            }
        }
        return out
    }

    private fun modelFile(): File? {
        val target = File(filesDir, "models/qwen2.5-0.5b-instruct-q4_k_m.gguf")
        if (target.exists() && target.length() > 1_000_000) return target
        // Flutter puts app assets under assets/flutter_assets/, so the asset
        // that sits at assets/flutter_assets/assets/models/ in the package is
        // reached as flutter_assets/assets/models/ here. Asking for the shorter
        // path failed quietly and the engine never launched.
        val assetNames = listOf(
            "flutter_assets/assets/models/qwen2.5-0.5b-instruct-q4_k_m.gguf",
            "assets/models/qwen2.5-0.5b-instruct-q4_k_m.gguf",
        )
        for (assetName in assetNames) {
            try {
                assets.open(assetName).use { input ->
                    target.parentFile?.mkdirs()
                    target.outputStream().use { output -> input.copyTo(output, 1 shl 16) }
                }
                if (target.exists() && target.length() > 1_000_000) return target
            } catch (e: IOException) {
                // Not at this path; try the next one.
            }
        }
        // Absent. Not an error: the app still works with an external server, it
        // just cannot start the bundled engine.
        target.delete()
        return null
    }

    /**
     * Launches glen and reports whether the process is alive.
     *
     * The first launch copies several hundred megabytes out of the APK, so it is
     * allowed to take a while. The Dart side polls /health rather than trusting
     * the return value, because a process can be alive and still be loading.
     */
    private fun startEngine(requestedPort: Int, chosenModel: String? = null): Boolean {
        val log = File(filesDir, "glen.log")

        // Every failure below writes why into the log. Returning a bare false
        // made "would not start" mean the same thing whether Android refused the
        // exec, the model was missing, or the engine exited in a millisecond,
        // which is no way to debug a launch.
        fun fail(why: String): Boolean {
            log.writeText(why)
            return false
        }

        val binary = engineBinary()
            ?: return fail("The engine binary is missing or not executable.")
        val model = modelFile()
            ?: return fail(
                "The model could not be unpacked. Free space is likely the cause:\n" +
                    File(filesDir, "models").absolutePath,
            )
        if (engine?.isAlive == true) return true
        return try {
            log.delete()
            val builder = ProcessBuilder(
                binary.absolutePath,
                "--serve",
                requestedPort.toString(),
            )
            // The chosen model if it is one we listed, otherwise the bundled one.
        // Validated against the list rather than trusted, because this path comes
        // from Dart and points at a file glen will mmap and execute maths over.
        val chosen = availableModels().firstOrNull { it.second.absolutePath == chosenModel }?.second
            ?: model
        builder.environment()["Glen_MODEL"] = chosen.absolutePath
            // Tools off: the bundled engine must not be able to run shell
            // commands or reach the network on its own.
            builder.environment()["Glen_TOOLS"] = "0"
            builder.environment()["Glen_CTX"] = "1024"
            // Measured on this phone with the bundled 0.5B, decoding one token:
            // 1 thread 412ms, 2 threads 397ms, 4 threads 255-259ms across three
            // runs, 8 threads anywhere between 213ms and 511ms. glen otherwise
            // defaults to available_parallelism().min(8), and on this memory
            // constrained device that pool contends with itself: fast on a good
            // run, slow on a bad one, which is what a caller sees as the model
            // being erratic. Four threads is both quicker on average and
            // repeatable, which matters more than a lucky best case.
            builder.environment()["Glen_THREADS"] = "4"
            builder.redirectErrorStream(true)
            builder.redirectOutput(log)
            builder.directory(filesDir)

            val started = try {
                builder.start()
            } catch (e: Exception) {
                // Most often Android refusing to exec from nativeLibraryDir.
                return fail("exec failed for ${binary.absolutePath}:\n$e")
            }
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

            if (started.isAlive) return true

            // It launched and died. The exit code separates a clean argument
            // error from a crash on load, which nothing else here can tell.
            try {
                started.waitFor(3, java.util.concurrent.TimeUnit.SECONDS)
            } catch (e: InterruptedException) {
                Thread.currentThread().interrupt()
            }
            val how = try {
                "exit code ${started.exitValue()}"
            } catch (e: IllegalThreadStateException) {
                "still running but reported dead"
            }
            engine = null
            return fail(
                "glen exited immediately ($how).\n" +
                    "model: ${model.absolutePath} (${model.length()} bytes)\n" +
                    "stderr and stdout follow:\n${log.readText()}",
            )
        } catch (e: Exception) {
            engine = null
            fail("Could not launch the engine:\n$e")
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