package com.abduljabbar.koru

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
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
 * Holds the cloud API key in the Android keystore.
 *
 * Keys are encrypted with an AES key that never leaves the keystore, so what
 * lands in SharedPreferences is ciphertext. One entry per provider, so several
 * can coexist.
 *
 * This class used to also exec a bundled inference engine and hold its process.
 * That is gone with the engine: the app ships one model, over the internet, and
 * the 258 MB of binary and weights that the local model needed are not in the
 * package any more.
 *
 * Every method reports failure honestly. An earlier version of this class
 * swallowed its exceptions, and the UI reported a refused keystore write as a
 * successful one, which surfaced much later as "nothing responds".
 */
class MainActivity : FlutterActivity() {

    private val channelName = "koru/secure_key"
    private val attentionChannelName = "koru/attention"
    private val filesChannelName = "koru/files"

    private val prefsName = "koru_secrets"
    private val keyAlias = "koru_cloud_key"

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

        // Saving a file the user asked for. Separate channel from the keys
        // because the two have nothing to do with each other: one stores
        // secrets, the other saves a backup to Downloads.
        MethodChannel(messenger, filesChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveToDownloads" -> {
                    val name = call.argument<String>("name") ?: "koru-backup.json"
                    val content = call.argument<String>("content") ?: ""
                    result.success(saveToDownloads(name, content))
                }
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

    // ----------------------------------------------------------------- files

    /**
     * Writes the backup into the phone's Downloads folder.
     *
     * MediaStore on Android 10+, a plain file before that. Returns the
     * location it landed in, or null on failure — a save that says it worked
     * and did not is worse than one that admits it could not.
     *
     * Deliberately Downloads and not the app's private storage: a backup that
     * lives in private storage is one uninstall away from gone, and the point
     * of exporting it is that it outlives the app.
     */
    private fun saveToDownloads(name: String, content: String): String? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                    put(MediaStore.MediaColumns.MIME_TYPE, "application/json")
                    put(
                        MediaStore.MediaColumns.RELATIVE_PATH,
                        Environment.DIRECTORY_DOWNLOADS,
                    )
                }
                val uri = contentResolver.insert(
                    MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                    values,
                ) ?: return null
                contentResolver.openOutputStream(uri)?.use {
                    it.write(content.toByteArray(Charsets.UTF_8))
                } ?: return null
                "Downloads/$name"
            } else {
                val dir = Environment.getExternalStoragePublicDirectory(
                    Environment.DIRECTORY_DOWNLOADS,
                )
                if (!dir.exists()) dir.mkdirs()
                val file = File(dir, name)
                file.writeText(content, Charsets.UTF_8)
                file.absolutePath
            }
        } catch (e: Exception) {
            Log.w("KoruFiles", "could not save the backup", e)
            null
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