package com.abduljabbar.koru

import android.app.Notification
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log

/**
 * The long-lived half of Koru's attention checking.
 *
 * Deliberately empty of decisions. It exists because Android will not let an app
 * keep checking for overdue work once it is closed without a foreground service,
 * and a foreground service must keep a notification up. Everything it knows, it
 * was told by [AttentionBridge], which was told by Dart.
 *
 * Why a service at all rather than just letting the notification sit there: the
 * notification is the thing the user sees, but re-evaluating what belongs in it
 * needs a scheduled job, and on Android that job has to be anchored to a
 * foreground service or it is simply not run once the app is closed.
 */
class AttentionWatcher : Service() {

    companion object {
        private const val TAG = "KoruWatcher"
        private const val CHANNEL_ID = "koru.attention"
        private const val ONGOING_ID = 1

        /** android.app.NotificationManager.IMPORTANCE_LOW, which is hidden. */
        private const val IMPORTANCE_LOW = 2
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Android 14+ requires the type to be declared here as well as in the
        // manifest, and throws if it is missing.
        try {
            val notification = buildNotification()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(ONGOING_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            } else {
                startForeground(ONGOING_ID, notification)
            }
        } catch (e: Exception) {
            // Failing to get in front of the system means this service is not
            // allowed to run. Stopping cleanly is the only correct outcome;
            // crash-looping here would drain the battery for nothing.
            Log.w(TAG, "the system refused the foreground notification", e)
            stopSelf()
        }
        // START_STICKY so the system brings this back after a low-memory kill.
        // Without it, a reboot or an aggressive task clear silently ends all
        // attention checking until the user happens to open the app.
        //
        // And the alarm is (re)armed on every start, so the hourly tick exists
        // as soon as the service has ever run once, without the app having to
        // schedule it separately and possibly forgetting.
        try {
            AttentionRestarter.schedule(this)
        } catch (e: Exception) {
            Log.w(TAG, "could not schedule the hourly check", e)
        }
        return START_STICKY
    }

    override fun onDestroy() {
        Log.i(TAG, "attention watcher stopped")
        super.onDestroy()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = android.app.NotificationChannel(
            CHANNEL_ID,
            "Deadlines and balances",
            IMPORTANCE_LOW,
        ).apply {
            description = "Deadlines, overdue balances and quiet projects."
            setShowBadge(true)
        }
        val nm = getSystemService(NOTIFICATION_SERVICE) as android.app.NotificationManager
        nm.createNotificationChannel(channel)
    }

    /**
     * Mirrors whatever Dart last published.
     *
     * Built by the same [OngoingNotification] the bridge uses, reading the same
     * shared preferences the bridge writes, so the two can never disagree about
     * what Koru is saying: there is one copy of the truth and one definition of
     * the notification. An earlier version drew its own version here, which had
     * no tap target — so after a restart, tapping the notification did nothing.
     */
    private fun buildNotification(): Notification = OngoingNotification.build(this)
}