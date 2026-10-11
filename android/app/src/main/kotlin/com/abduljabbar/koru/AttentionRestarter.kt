package com.abduljabbar.koru

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Puts Koru back together after the phone does what it likes.
 *
 * A foreground service is a promise the user did not make. Android stops it when
 * it wants the battery back, MIUI stops it more aggressively than that, and the
 * app being killed is not the same as the user saying no. So the app assumes it
 * will be stopped, and puts itself back on a schedule rather than trusting a
 * process to stay alive.
 *
 * Deliberately does not decide anything. What is worth saying was worked out by
 * Attention in Dart and left in shared preferences, and this only re-posts it.
 * That is the whole reason a restart is safe: a restarted Koru cannot come back
 * with a different opinion, because it has no opinion, only the last one.
 */
class AttentionRestarter : BroadcastReceiver() {

    companion object {
        private const val TAG = "KoruRestarter"
        private const val ALARM_ACTION = "com.abduljabbar.koru.CHECK"

        /**
         * How often to look.
         *
         * An hour is the coarsest interval that still feels alive. Deadlines are
         * measured in days and overdue balances do not become more overdue by
         * the minute, so checking more often buys nothing a person would notice
         * and costs a wakeup each time, which is the kind of cost that gets a
         * helper uninstalled for being wasteful.
         */
        private const val CHECK_INTERVAL_MS = 60L * 60L * 1000L

        private const val REQ_ALARM = 9101

        /** Schedules the next check. Safe to call repeatedly. */
        fun schedule(context: Context) {
            val manager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
            // Inexact on purpose. An exact alarm would wake the phone at a precise
            // minute to discover that nothing has changed, and Android 12+ treats
            // that as a misuse of a capability meant for alarms and reminders.
            manager.setInexactRepeating(
                AlarmManager.RTC_WAKEUP,
                System.currentTimeMillis() + CHECK_INTERVAL_MS,
                CHECK_INTERVAL_MS,
                alarmIntent(context),
            )
        }

        fun cancel(context: Context) {
            val manager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
            manager.cancel(alarmIntent(context))
        }

        private fun alarmIntent(context: Context): PendingIntent {
            val intent = Intent(context, AttentionRestarter::class.java).setAction(ALARM_ACTION)
            return PendingIntent.getBroadcast(
                context,
                REQ_ALARM,
                intent,
                // UPDATE_CURRENT so a re-schedule does not pile up extra alarms,
                // and IMMUTABLE so nothing else on the device can retarget it.
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        /** Brings the notification and the widget back with the last known state. */
        fun restore(context: Context) {
            try {
                val watcher = Intent(context, AttentionWatcher::class.java)
                if (android.os.Build.VERSION.SDK_INT >= 26) {
                    context.startForegroundService(watcher)
                } else {
                    context.startService(watcher)
                }
            } catch (e: Exception) {
                // On Android 12+ starting a foreground service from the
                // background is refused in most states. Failing here is expected
                // and is not worth a crash: the next alarm will try again, and
                // the app opening will sort it.
                Log.w(TAG, "could not restart the watcher yet", e)
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action == Intent.ACTION_BOOT_COMPLETED) {
            // The phone restarted, so everything the previous session had set up
            // is gone. Put the schedule back before anything else.
            schedule(context)
            restore(context)
            return
        }
        if (action == ALARM_ACTION) {
            restore(context)
            // Re-arm as well as act. setInexactRepeating should survive on its
            // own, but a device that cleared the alarm during a reboot would
            // otherwise stop checking for good and nothing would say why.
            schedule(context)
        }
    }
}
