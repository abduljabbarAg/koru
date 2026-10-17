package com.abduljabbar.koru

import android.content.Context
import android.os.StatFs
import android.util.Log
import android.content.Intent
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import io.flutter.plugin.common.TaskQueues
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
 * executable, which is why the engine ships as a native library rather than as an
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

        // A serial background queue, which is not a detail.
        //
        // Every engine method can end up copying the model out of the APK, and
        // that is a couple of hundred megabytes. Method channel handlers run on
        // the platform thread unless a task queue is given, so `status` — which
        // the chat screen watches just to decide what its badge should say — was
        // doing a 248 MB asset copy on the main thread and freezing the app
        // during launch. A phone that showed "Koru isn't responding" on a first
        // run had been told nothing about why, and no model was the obvious
        // suspect for the wrong reason.
        //
        // Serial rather than fixed-thread, so the copy cannot run twice at once:
        // serialising the engine's own calls is what the platform did with them
        // before this queue existed.
        val engineQueue =
            TaskQueues.make(TaskQueues.TaskQueueType.SERIAL_BACKGROUND)
        MethodChannel(
            messenger,
            engineChannelName,
            StandardMethodCodec.INSTANCE,
            engineQueue,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(engineStatus())
                "diagnose" -> result.success(
                    mapOf(
                        "alive" to (engine?.isAlive == true),
                        "log" to engineLog(),
                    )
                )
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
                "importModel" -> result.success(
                    importModel(call.argument<String>("path").orEmpty())
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
     * The bundled engine binary.
     *
     * Lives in nativeLibraryDir because that is the only place this app can
     * still exec from on a modern Android. null when the APK was built without
     * it, which the Dart side treats as "no bundled engine" rather than an error.
     */
    private fun engineBinary(): File? {
        val candidate = File(applicationInfo.nativeLibraryDir, "libllama-server.so")
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
        val candidate = File(applicationInfo.nativeLibraryDir, "libllama-server.so")
        val usable = candidate.exists() && candidate.canExecute()
        // Only what is already on disk. This used to call modelFile(), so the
        // cheapest possible question — "is there a bundled model" — was also the
        // one that copied 248 MB out of the APK. The chat screen watches the
        // status to decide what its badge should say, so a launch could freeze
        // on a question nobody asked for.
        val model = modelOnDisk()
        val reason = when {
            usable -> null
            !candidate.exists() ->
                "libllama-server.so is not in ${applicationInfo.nativeLibraryDir}. " +
                    "Native libraries were probably not extracted, so there is " +
                    "nothing on disk to run."
            !candidate.canExecute() ->
                "libllama-server.so is at ${candidate.absolutePath} but is not marked executable."
            else -> "unknown"
        }
        return mapOf(
            "available" to usable,
            "path" to candidate.absolutePath,
            "exists" to candidate.exists(),
            "executable" to candidate.canExecute(),
            "modelPath" to model?.absolutePath,
            "modelAvailable" to (model != null),
            "modelBytes" to (model?.length() ?: 0L),
            "modelProblem" to modelProblem,
            "reason" to reason,
        )
    }

    /**
     * Why the bundled model is not on disk, in numbers a person can act on.
     *
     * Null whenever the model is fine or has simply not been unpacked yet. Set
     * by [modelFile] on the way to giving up, and read by the status call and by
     * the failure message, because "the model could not be unpacked" on its own
     * sent people looking for a missing file rather than for a full disk.
     */
    @Volatile
    private var modelProblem: String? = null

    /**
     * Headroom left on top of the model itself.
     *
     * The copy is 248 MB and the engine mmaps it while running, so a disk that
     * passes the copy can still fail to load it. 120 MB is enough that the
     * system keeps room to breathe, and the APK itself has already been written
     * by this point, so this is checked against space genuinely available now.
     */
    private const val MODEL_HEADROOM = 120L * 1024 * 1024

    /**
     * How big the bundled model is, mirroring BundledEngine.bundledModelBytes.
     *
     * Only used to phrase a failure, and only for the one message that cannot be
     * phrased from a measurement: when the asset is stored compressed there is
     * no file descriptor to take a length from, so the copy runs and discovers
     * the disk is full the only way it can. Duplicated here rather than passed
     * over the channel because it is a sentence, not a decision.
     */
    private const val BUNDLED_MODEL_BYTES = 248302272L

    /** What is left to unpack into, in bytes. */
    private fun freeBytes(): Long =
        try {
            StatFs(filesDir.absolutePath).availableBytes
        } catch (e: Exception) {
            // A device that will not answer cannot be promised anything, but it
            // must not stop the app trying: the copy itself is the real test.
            Long.MAX_VALUE
        }

    private fun megabytes(bytes: Long): String = "${bytes / (1024 * 1024)} MB"

    /**
     * The bundled model, if it is already on disk. Never copies anything.
     */
    private fun modelOnDisk(): File? {
        for (name in bundledModelNames) {
            val target = File(filesDir, "models/$name")
            if (target.exists() && target.length() > 1_000_000) return target
        }
        return null
    }

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
     * Every model the engine could be pointed at, bundled first.
     *
     * Listed rather than hardcoded because the bundled Bonsai is not the only
     * thing this phone can run: a bigger model dropped into the app's own
     * models folder shows up here and can be picked. Putting both in the APK
     * would take every install past 600 MB to serve a choice most people make
     * once, which is why only one ships and the other has to be brought.
     */
    private fun availableModels(): List<Pair<String, File>> {
        val out = mutableListOf<Pair<String, File>>()
        modelFile()?.let { out.add("${it.nameWithoutExtension} (bundled)" to it) }
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

    /**
     * The bundled model's filename, tried in order.
     *
     * Bonsai-1.7B-Q1_0 is what ships now: 231 MB, and markedly sharper than the
     * Qwen 0.5B it replaces, at the same resident size the old one had. The old
     * name stays in the list because an install that already unpacked it should
     * not unpack a second model it will never offer.
     */
    private val bundledModelNames = listOf(
        "Bonsai-1.7B-Q1_0.gguf",
        "qwen2.5-0.5b-instruct-q4_k_m.gguf",
    )

    /**
     * The bundled model, copied out of the APK's assets on first use.
     *
     * Assets cannot be mmapped directly out of the compressed APK, so the file is
     * materialised into the app's own storage where the engine's mmap loader can
     * use it.
     *
     * Returns the file already on disk when there is one, so this is safe to ask
     * repeatedly. Runs on the engine thread rather than the platform thread,
     * because the copy is a couple of hundred megabytes. When it cannot produce
     * a model it leaves [modelProblem] saying why, in numbers where numbers help,
     * rather than returning null and letting the caller guess.
     */
    private fun modelFile(): File? {
        modelOnDisk()?.let { return it }
        // Flutter puts app assets under assets/flutter_assets/, so the asset
        // that sits at assets/flutter_assets/assets/models/ in the package is
        // reached as flutter_assets/assets/models/ here. Asking for the shorter
        // path failed quietly and the engine never launched.
        val assetNames = bundledModelNames.flatMap { name ->
            listOf(
                "flutter_assets/assets/models/$name",
                "assets/models/$name",
            )
        }
        for (assetName in assetNames) {
            val name = assetName.substringAfterLast('/')
            val target = File(filesDir, "models/$name")
            // Reported while nothing has gone wrong yet, so a status call made
            // during the copy does not claim a fault that has not happened.
            modelProblem = null
            val needed = try {
                assets.openFd(assetName).use { it.length }
            } catch (e: Exception) {
                // Not at this path, or stored compressed with no descriptor.
                // Fall through to the streaming copy, which can still read it.
                -1L
            }
            if (needed > 0) {
                val free = freeBytes()
                val want = needed + MODEL_HEADROOM
                if (free < want) {
                    // Checked before the copy rather than reported afterwards,
                    // because a copy that runs out of room leaves a truncated
                    // file behind, and the next launch happily accepts a
                    // half-written model because it is bigger than the length
                    // check below. The numbers are the diagnosis: "free space is
                    // likely the cause" asked the user to go and find out.
                    modelProblem =
                        "There is not enough room to unpack the model. It needs " +
                            "${megabytes(want)} free (${megabytes(needed)} for the model, " +
                            "plus ${megabytes(MODEL_HEADROOM)} kept spare) and this phone has " +
                            "${megabytes(free)}. Free some space and try again — the model " +
                            "unpacks once, not every launch."
                    return null
                }
            }
            try {
                val partial = File(target.parentFile, "$name.part")
                target.parentFile?.mkdirs()
                // Written aside and renamed, never straight onto the real name.
                // A copy interrupted by a full disk or a killed process used to
                // leave the truncated file in place under the name everything
                // else looks for, so the engine would go on to load half a model
                // and report a tensor missing rather than a disk that was full.
                partial.outputStream().use { output ->
                    assets.open(assetName).use { input ->
                        input.copyTo(output, 1 shl 20)
                    }
                    output.fd.sync()
                }
                if (partial.length() > 1_000_000 && !partial.renameTo(target)) {
                    modelProblem = "The model was copied but could not be moved into place."
                    partial.delete()
                    return null
                }
                partial.delete()
                if (target.exists() && target.length() > 1_000_000) {
                    modelProblem = null
                    return target
                }
            } catch (e: Exception) {
                partial.delete()
                // Kept rather than swallowed, and a full disk gets the same
                // numbers the preflight would have given. An asset stored
                // compressed has no length to take before the copy, so this is
                // the only place that failure can be caught, and "No space left
                // on device" on its own sends people looking for a missing file.
                modelProblem =
                    if (e.message?.contains("space", ignoreCase = true) == true) {
                        "There is not enough room to unpack the model. It needs " +
                            "${megabytes(BUNDLED_MODEL_BYTES + MODEL_HEADROOM)} free and this " +
                            "phone has ${megabytes(freeBytes())}. Free some space and try " +
                            "again — the model unpacks once, not every launch. ($e)"
                    } else {
                        "The model could not be unpacked: $e"
                    }
                return null
            }
        }
        // Absent. Not an error: the app still works with an external server, it
        // just cannot start the bundled engine.
        modelProblem = "This build does not contain a model."
        return null
    }

    /**
     * Launches the engine and reports whether the process is alive.
     *
     * The first launch copies several hundred megabytes out of the APK, so it is
     * allowed to take a while. The Dart side polls /health rather than trusting
     * the return value, because a process can be alive and still be loading.
     */
    private fun startEngine(requestedPort: Int, chosenModel: String? = null): Boolean {
        val log = File(filesDir, "llama-server.log")

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
            // The real reason, with the numbers, rather than a guess. This is
            // what the app shows the user and the user copies into a bug report.
            modelProblem
                ?: "The model could not be unpacked into " +
                    "${File(filesDir, "models").absolutePath}",
        )
        if (engine?.isAlive == true) return true
        return try {
            log.delete()
            val builder = ProcessBuilder(
                binary.absolutePath,
                "--port",
                requestedPort.toString(),
                "--host",
                "127.0.0.1",
            )
            // The chosen model if it is one we listed, otherwise the bundled one.
            // Validated against the list rather than trusted, because this path
            // comes from Dart and points at a file the engine will mmap and run
            // arithmetic over. It goes on the command line rather than in the
            // environment.
            val chosen = availableModels().firstOrNull { it.second.absolutePath == chosenModel }
                ?.second ?: model
        builder.command(binary.absolutePath, "--model", chosen.absolutePath,
            "--port", requestedPort.toString(), "--host", "127.0.0.1",
            // Two threads, and that is measured rather than guessed: on this
            // phone, decoding one token of the 1.7B Bonsai runs 3.87 t/s on one
            // thread and 4.65 t/s on two, then collapses to 0.13 t/s on four.
            // The extra threads do not help this CPU; they contend for the same
            // cores the model is already using.
            "--threads", "2",
            // The single most important line in this file, and it was missing for
            // weeks. Without an explicit context size the server allocates a KV
            // cache for whatever context the model advertises, which for Bonsai is
            // far larger than this phone has memory for. The kernel SIGKILLs the
            // process partway through load, before llama.cpp can print a single
            // word of error — so the log just stopped at "n_threads = 2" and the
            // app could only say "would not start". Measured here: the same
            // binary and model die silently at the default size, and load and
            // answer with 2048.
            //
            // 2048 is comfortably more than the ~1200 characters of history the
            // app sends, so nothing is truncated in normal use.
            "--ctx-size", "2048",
            // 256 rather than the default 2048. Prompt processing mmaps the
            // batch, and on a phone a large batch is the difference between
            // loading and being killed.
            "--batch-size", "256",
            "--parallel", "1",
            "--no-warmup")
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
                "the engine exited immediately ($how).\n" +
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
        val log = File(filesDir, "llama-server.log")
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
    /**
     * Copies a .gguf the person picked into the app's own models folder.
     *
     * Dropping a file into Android/data by hand works but nobody does it, and
     * telling somebody to edit a path in a file manager is not something an app
     * can honestly ask of them. So the picker hands us a path and we do the copy.
     *
     * Copies rather than moves: the source is usually in Downloads, and taking
     * their file away to make a model available is a surprise.
     */
    private fun importModel(source: String): Map<String, Any?> {
        val from = File(source)
        if (!from.exists()) return mapOf("ok" to false, "error" to "That file is not there any more.")
        if (!from.name.endsWith(".gguf")) {
            return mapOf("ok" to false, "error" to "A model file has to end in .gguf.")
        }
        if (from.length() < 1_000_000) {
            return mapOf("ok" to false, "error" to "That file is too small to be a model.")
        }
        return try {
            val dir = File(getExternalFilesDir(null) ?: filesDir, "models")
            dir.mkdirs()
            val to = File(dir, from.name)
            // 64 MB buffer, because a model is a few hundred megabytes and
            // byte-by-byte would take minutes.
            from.inputStream().use { input ->
                to.outputStream().use { output -> input.copyTo(output, 1 shl 26) }
            }
            mapOf("ok" to true, "label" to "${from.nameWithoutExtension} (${from.length() / (1024 * 1024)} MB)")
        } catch (e: Exception) {
            Log.w("Koru", "could not import the model", e)
            mapOf("ok" to false, "error" to "Could not copy that file: $e")
        }
    }

}
