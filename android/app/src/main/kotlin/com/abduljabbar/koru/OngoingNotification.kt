package com.abduljabbar.koru

import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat

/**
 * The one definition of the ongoing notification.
 *
 * Two classes post this notification — [AttentionBridge], which pushes the
 * state Dart computed while the app is up, and [AttentionWatcher], which
 * re-posts it when the system restarts the service on its own. They used to
 * build it twice and the copies drifted: the bridge's copy carried a tap
 * target and the watcher's did not, and since the watcher is what runs after
 * a reboot, the notification most people actually saw was the one that did
 * nothing when tapped. One builder, reading the same preferences the bridge
 * writes, so the summary and the tap target cannot disagree again.
 */
object OngoingNotification {
    const val CHANNEL_ID = "koru.attention"
    const val ONGOING_ID = 1
    const val PREFS = "koru_attention"

    fun build(ctx: Context): Notification {
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val count = prefs.getInt("count", 0)
        val headline = prefs.getString("headline", "") ?: ""
        val top = prefs.getString("top", "") ?: ""
        val link = prefs.getString("link", "")?.ifEmpty { null }
        val lines = prefs.getString("lines", "")
            ?.split("\n")
            ?.filter { it.isNotBlank() }
            ?: emptyList()

        val body = when {
            count == 0 -> "Nothing needs you right now."
            top.isNotEmpty() -> top
            else -> "$count thing${if (count == 1) "" else "s"} need you"
        }

        val builder = NotificationCompat.Builder(ctx, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_koru)
            .setContentTitle(if (count > 0) "Koru: $headline" else "Koru")
            .setContentText(body)
            .setOngoing(true)
            .setSilent(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setContentIntent(openIntent(ctx, link))

        // The expanded view. Collapsed, the notification is one summary line;
        // pulled open, it is the actual work — which is what somebody pulling
        // the shade down is asking for. It said only the summary before, so a
        // count of four things never named one of them.
        if (lines.isNotEmpty()) {
            builder.setStyle(
                NotificationCompat.BigTextStyle().bigText(lines.joinToString("\n"))
            )
        }
        return builder.build()
    }

    /**
     * The tap target.
     *
     * An explicit activity intent, so it opens Koru even when there is no
     * deep link to carry — a notification that does nothing when tapped reads
     * as the app being broken. FLAG_IMMUTABLE because the intent can carry a
     * link into the app, and an immutable intent cannot have that rewritten by
     * anything else on the device.
     */
    private fun openIntent(ctx: Context, link: String?): PendingIntent {
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
