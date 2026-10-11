package com.abduljabbar.koru

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/**
 * The method channel Dart talks to about notifications.
 *
 * Not a Service, despite doing the work a Service is wanted for: the class that
 * actually runs in the background is [AttentionWatcher], which the manifest
 * declares. This one only marshals. It was originally called AttentionService,
 * which is exactly the kind of name that ends up wired into the manifest by
 * mistake and fails the build for a reason that has nothing to do with what the
 * code was trying to do.
 *
 * The important thing to understand about the design here is that the service
 * does not do any thinking. It cannot: this codebase's logic is Dart, and a
 * Kotlin service reaching into a sqflite database to decide who owes money would
 * be a second implementation of rules that already exist, which is how two
 * answers start disagreeing. So Dart computes what matters, hands it over as
 * JSON, and this side is only the delivery mechanism.
 *
 * The service itself exists to satisfy one platform rule rather than to compute
 * anything: Android will not let an app check for overdue work while closed
 * unless it holds a foreground service, and a foreground service must show a
 * permanent notification. That permanent notification is the ongoing one below.
 * It is not a nag, it does not vibrate, and it cannot be dismissed by swiping,
 * which is the honest cost of "Koru keeps an eye on things for me".
 */
class AttentionBridge : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "KoruAttention"
        private const val CHANNEL_ID = "koru.attention"
        private const val URGENT_CHANNEL_ID = "koru.urgent"
        private const val ONGOING_ID = 1

        /** Separate from the ongoing one: different behaviour, different channel. */
        private const val URGENT_ID = 2
        private const val ALERT_BASE = 100
        private const val METHOD_CHANNEL = "koru/attention"
        private const val PREFS = "koru_attention"

        /** Request code for the notification permission prompt. */
        private const val REQ_NOTIFICATIONS = 4711

        /**
         * NotificationManager.IMPORTANCE_LOW, written out.
         *
         * The constant is hidden in the public Android SDK, so naming it does
         * not compile, and a literal 2 with the meaning spelled out is clearer
         * than reaching around the SDK to find it. Importance 2 is LOW: no
         * sound, no heads-up, and it still shows in the shade.
         */
        private const val IMPORTANCE_LOW = 2

        /**
         * IMPORTANCE_DEFAULT, written out for the same reason as [IMPORTANCE_LOW].
         *
         * This one makes a sound. It is a second channel rather than a louder
         * setting on the first, because the two kinds of alert need genuinely
         * different behaviour and a channel is immutable once created: a silent
         * channel made loud afterwards is not possible, and one channel cannot be
         * both.
         */
        private const val IMPORTANCE_DEFAULT = 3
    }

    private var context: Context? = null
    private var channel: MethodChannel? = null

    private fun pendingLink(): String? = takeLink?.invoke()

    /** Set from MainActivity so a tap can be pushed to Dart. */
    fun bind(ch: MethodChannel) {
        channel = ch
    }

    /** Set by Dart. Replaces the previous summary rather than adding to it. */
    private var headline: String = ""
    private var topLine: String = ""
    private var count: Int = 0
    private var link: String? = null

    /** Titles of whatever is genuinely urgent, used to decide whether to speak. */
    private var urgent: List<String> = emptyList()

    /** Whether anything urgent is new since the last time Koru said so. */
    private var changed: Boolean = true

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val ctx = context
        if (ctx == null) {
            result.error("no_context", "the attention bridge has no context", null)
            return
        }
        when (call.method) {
            "canPost" -> result.success(canPost(ctx))
            "start" -> {
                applyPayload(ctx, call.argument<String>("payload"))
                result.success(startForeground(ctx))
            }
            "stop" -> {
                result.success(stop(ctx))
            }
            "takeLink" -> {
                // Asked once Dart is listening. Null means nothing is waiting,
                // which is the ordinary case and not an error.
                result.success(pendingLink())
            }
            "health" -> result.success(health(ctx))
            "requestBatteryExempt" -> result.success(requestBatteryExempt(ctx))
            "requestNotifications" -> result.success(requestNotifications(ctx))
            "openAutostartSettings" -> result.success(openAutostartSettings(ctx))
            "openAppSettings" -> result.success(openAppSettings(ctx))
            "updateWidget" -> {
                result.success(updateWidget(
                    ctx,
                    call.argument<Int>("count") ?: 0,
                    call.argument<String>("headline") ?: "",
                    call.argument<String>("top") ?: "",
                    call.argument<String>("mood") ?: "calm",
                ))
            }
            "clear" -> {
                // Everything dealt with. Cleared rather than set to a
                // placeholder so the badge genuinely clears instead of showing
                // a cheerful nothing until the next check.
                headline = ""
                topLine = ""
                count = 0
                link = null
                urgent = emptyList()
                changed = false
                persist(ctx)
                NotificationManagerCompat.from(ctx).cancel(URGENT_ID)
                result.success(startForeground(ctx))
            }
            "update" -> {
                applyPayload(ctx, call.argument<String>("payload"))
                if (startForeground(ctx)) {
                    result.success(true)
                } else {
                    // Not a failure: the service may simply not be running, and
                    // the right response is to start it, not to shout.
                    result.success(startForeground(ctx))
                }
            }
            else -> result.notImplemented()
        }
    }

    fun attach(ctx: Context) {
        context = ctx.applicationContext
        ensureChannel(ctx)
    }

    /**
     * Lets MainActivity register the channel so a pending link can be pushed.
     *
     * Dart is not necessarily listening yet when a notification is tapped,
     * particularly on a cold start, so the link is held rather than dropped.
     * Once Dart is ready it calls "takeLink" and gets whatever is waiting.
     */
    private var takeLink: (() -> String?)? = null

    fun onLinkReady(block: () -> String?) {
        takeLink = block
    }

    fun drainPendingLink() {
        takeLink?.invoke()?.let { link ->
            // Null result means Dart was not listening yet, which happens on a
            // cold start. It will ask for the link itself once it is up.
            channel?.invokeMethod("openLink", link)
        }
    }

    // -- health ----------------------------------------------------------

    /**
     * What the app currently has permission to do.
     *
     * Asked separately for each grant rather than as one "ok" because they are
     * granted independently, can be withdrawn independently, and telling someone
     * "Koru has a problem" without saying which one is not something they can
     * act on.
     */
    private fun health(ctx: Context): Map<String, Any?> {
        val pm = ctx.getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
        val batteryExempt = pm.isIgnoringBatteryOptimizations(ctx.packageName)
        val autostart = manufacturerSupportsAutostart()
        return mapOf(
            "notifications" to canPost(ctx),
            "batteryExempt" to batteryExempt,
            // Null, not false, when the question does not apply. Reporting false
            // on a phone with no autostart screen would show a red cross for a
            // setting the user does not have and cannot turn on.
            "autostart" to if (autostart == null) null else isAutostartAllowed(ctx),
        )
    }

    private fun requestBatteryExempt(ctx: Context): Boolean {
        return try {
            val pm = ctx.getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
            if (pm.isIgnoringBatteryOptimizations(ctx.packageName)) return true
            val intent = Intent(android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                .setData(android.net.Uri.parse("package:${ctx.packageName}"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            ctx.startActivity(intent)
            true
        } catch (e: Exception) {
            Log.w(TAG, "no battery optimisation screen", e)
            false
        }
    }

    private fun requestNotifications(ctx: Context): Boolean {
        val activity = activity ?: return false
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                activity.requestPermissions(
                    arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                    REQ_NOTIFICATIONS,
                )
            }
            true
        } catch (e: Exception) {
            Log.w(TAG, "could not ask for notification permission", e)
            false
        }
    }

    /** The activity, when there is one. Null in a background service. */
    private var activity: android.app.Activity? = null

    fun bindActivity(a: android.app.Activity?) {
        activity = a
    }

    /**
     * Whether this phone has an autostart screen worth opening.
     *
     * Null means it does not, which is every stock Android phone. Guessing a
     * manufacturer list is how an app ends up offering a setting that does not
     * exist, so this asks the package manager whether the activity is really
     * there rather than checking a brand string.
     */
    private fun manufacturerSupportsAutostart(): Boolean? {
        val pm = context?.packageManager ?: return null
        val intent = Intent().setComponent(
            android.content.ComponentName(
                "com.miui.securitycenter",
                "com.miui.permcenter.autostart.AutoStartManagementActivity",
            )
        )
        return if (pm.resolveActivity(intent, 0) != null) true else null
    }

    /**
     * MIUI's autostart state.
     *
     * Read through AppOpsManager, which is where MIUI actually records it, so
     * this reports what the system will really do rather than what it says on
     * the settings page. Null when the reading is not available, which is
     * treated as "unknown" rather than "off".
     */
    private fun isAutostartAllowed(ctx: Context): Boolean? {
        if (manufacturerSupportsAutostart() == null) return null
        return try {
            val ops = ctx.getSystemService(Context.APP_OPS_SERVICE)
                as android.app.AppOpsManager
            val mode = ops.unsafeCheckOpNoThrow(
                "android:op_run_in_background",
                android.os.Process.myUid(),
                ctx.packageName,
            )
            // MODE_ALLOWED is 0. Anything else means the system is refusing to
            // let the app start by itself.
            mode == android.app.AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            Log.w(TAG, "could not read autostart state", e)
            null
        }
    }

    private fun openAutostartSettings(ctx: Context): Boolean {
        return try {
            val intent = Intent().setComponent(
                android.content.ComponentName(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.autostart.AutoStartManagementActivity",
                )
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            ctx.startActivity(intent)
            true
        } catch (e: Exception) {
            Log.w(TAG, "no autostart screen on this phone", e)
            false
        }
    }

    private fun openAppSettings(ctx: Context): Boolean {
        return try {
            val intent = Intent(
                android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                android.net.Uri.parse("package:${ctx.packageName}"),
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            ctx.startActivity(intent)
            true
        } catch (e: Exception) {
            Log.w(TAG, "no app settings screen", e)
            false
        }
    }

    // -- payload ---------------------------------------------------------

    /**
     * Reads what Dart decided is worth saying.
     *
     * Defensive throughout. This arrives as a JSON string over a platform
     * channel, which is exactly the sort of boundary where a malformed value
     * turns into an exception inside a service that Android will then keep
     * restarting. It has to fail soft and leave whatever was there before.
     */
    private fun applyPayload(ctx: Context, payload: String?) {
        if (payload == null) return
        try {
            val json = JSONObject(payload)
            headline = json.optString("headline", "")
            topLine = json.optString("top", "")
            count = json.optInt("count", 0)
            link = json.optString("link", "").ifEmpty { null }
            changed = json.optBoolean("changed", true)
            urgent = json.optJSONArray("urgent")?.let { array ->
                (0 until array.length()).mapNotNull { array.optString(it) }
            } ?: emptyList()
            persist(ctx)
        } catch (e: Exception) {
            Log.w(TAG, "ignoring an unreadable attention payload", e)
        }
    }

    /**
     * Writes the payload where the service can read it back.
     *
     * Needed because the system can kill and restart the watcher at any time,
     * including on boot, and a restarted service that has forgotten what it was
     * saying would post an empty notification over the top of a correct one.
     * One stored copy, written here and read there, so the two cannot disagree.
     */
    /**
     * Repaints every placed widget.
     *
     * Returns false when nothing is placed, which is the normal case and not a
     * failure. The broadcast is only sent if there is something to receive it,
     * so adding a widget does not mean paying for a broadcast that lands
     * nowhere.
     */
    private fun updateWidget(
        ctx: Context,
        count: Int,
        headline: String,
        top: String,
        mood: String,
    ): Boolean {
        val manager = android.appwidget.AppWidgetManager.getInstance(ctx)
        val ids = manager.getAppWidgetIds(
            android.content.ComponentName(ctx, KoruWidgetProvider::class.java)
        )
        if (ids.isEmpty()) return false
        val intent = Intent(ctx, KoruWidgetProvider::class.java).apply {
            action = KoruWidgetProvider.ACTION_UPDATE
            putExtra(KoruWidgetProvider.EXTRA_COUNT, count)
            putExtra(KoruWidgetProvider.EXTRA_HEADLINE, headline)
            putExtra(KoruWidgetProvider.EXTRA_TOP, top)
            putExtra(KoruWidgetProvider.EXTRA_MOOD, mood)
        }
        ctx.sendBroadcast(intent)
        return true
    }

    private fun persist(ctx: Context) {
        try {
            ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putString("headline", headline)
                .putString("top", topLine)
                .putInt("count", count)
                .putString("urgent", urgent.joinToString("~"))
                .apply()
        } catch (e: Exception) {
            Log.w(TAG, "could not persist the attention payload", e)
        }
    }

    // -- foreground ------------------------------------------------------

    private fun canPost(ctx: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ctx.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        return NotificationManagerCompat.from(ctx).areNotificationsEnabled()
    }

    private fun ensureChannel(ctx: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // Money that is already late, or work due today. Sound, because a silent
        // deadline is a deadline that gets missed, and the consequence lands on
        // the user rather than on us.
        nm.createNotificationChannel(
            NotificationChannel(
                URGENT_CHANNEL_ID,
                "Overdue and due today",
                IMPORTANCE_DEFAULT,
            ).apply {
                description = "Money already late and work due today."
                enableVibration(true)
                setShowBadge(true)
            }
        )

        // Everything else, and the ongoing status. Silent on purpose: a quiet
        // project is worth mentioning and not worth a sound, and a status line
        // that makes a noise every hour would be intolerable.
        nm.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                // Shown in Android's own settings under Notifications. Named for
                // what it carries rather than for the app, because a user looking
                // at this list is trying to work out why they got a notification
                // and "Koru" alone does not answer that.
                "Deadlines and balances",
                IMPORTANCE_LOW,
            ).apply {
                description = "Deadlines, overdue balances and quiet projects."
                setShowBadge(true)
            }
        )
    }

    /**
     * Starts or updates the foreground notification.
     *
     * Idempotent on purpose, because this is called on every update and a
     * service that restarted each time would burn battery for nothing.
     */
    private fun startForeground(ctx: Context): Boolean {
        ensureChannel(ctx)
        val notification = buildOngoing(ctx)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ctx.startForegroundService(Intent(ctx, AttentionWatcher::class.java))
            } else {
                ctx.startService(Intent(ctx, AttentionWatcher::class.java))
            }
            // Post directly rather than relying on the service to do it, so the
            // notification is up before onStartForeground returns.
            NotificationManagerCompat.from(ctx)
                .notify(ONGOING_ID, notification)
            postUrgentIfChanged(ctx)
            return true
        } catch (e: Exception) {
            // Android 12+ throws if a foreground service is started from the
            // background. The app starting it from the foreground is the
            // supported path; this is the failure to report, not to swallow.
            Log.w(TAG, "could not start the attention watcher", e)
            return false
        }
    }

    private fun stop(ctx: Context): Boolean {
        return try {
            ctx.stopService(Intent(ctx, AttentionWatcher::class.java))
            NotificationManagerCompat.from(ctx).cancel(ONGOING_ID)
            true
        } catch (e: Exception) {
            Log.w(TAG, "could not stop the attention watcher", e)
            false
        }
    }

    /**
     * The alert that makes a sound, posted only when something urgent is new.
     *
     * The rule is *sound on change*, not sound on every check. The hourly alarm
     * re-posts state, and an alert that sounds every hour for a deadline that has
     * not moved is the thing that trains someone to swipe Koru away without
     * reading. So it speaks when a new overdue balance or a new due-today item
     * appears, and is silent when the same ones are still outstanding.
     *
     * A distinct id from the ongoing one, because they are different notifications
     * with different behaviour, and replacing a silent status with a loud alert
     * would make the status itself noisy.
     */
    private fun postUrgentIfChanged(ctx: Context) {
        if (urgent.isEmpty() || !changed) return
        val notification = NotificationCompat.Builder(ctx, URGENT_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(if (urgent.size == 1) "Koru: something is due" else "Koru: ${urgent.size} things are due")
            .setContentText(urgent.take(3).joinToString("\n"))
            .setStyle(
                NotificationCompat.BigTextStyle().bigText(urgent.joinToString("\n"))
            )
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setContentIntent(openIntent(ctx))
            .build()
        try {
            NotificationManagerCompat.from(ctx).notify(URGENT_ID, notification)
        } catch (e: SecurityException) {
            // POST_NOTIFICATIONS refused. The ongoing status still shows if it is
            // allowed, and nothing here is worth crashing over.
            Log.w(TAG, "not allowed to post the urgent alert", e)
        }
    }

    private fun buildOngoing(ctx: Context): Notification {
        val body = when {
            count == 0 -> "Nothing needs you right now."
            topLine.isNotEmpty() -> topLine
            else -> "$count thing${if (count == 1) "" else "s"} need you"
        }
        return NotificationCompat.Builder(ctx, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(if (count > 0) "Koru: $headline" else "Koru")
            .setContentText(body)
            .setOngoing(true)
            .setSilent(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setContentIntent(openIntent(ctx))
            .build()
    }

    /**
     * The tap target.
     *
     * FLAG_IMMUTABLE because the intent carries a link into the app and an
     * immutable intent cannot have that rewritten by anything else on the
     * device. Without it this is a way for another app to say where Koru opens.
     */
    private fun openIntent(ctx: Context): PendingIntent {
        val intent = Intent(ctx, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            action = Intent.ACTION_VIEW
            link?.let { data = android.net.Uri.parse(it) }
        }
        return PendingIntent.getActivity(
            ctx,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}