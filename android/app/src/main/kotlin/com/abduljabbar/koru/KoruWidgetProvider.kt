package com.abduljabbar.koru

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * Koru on the home screen.
 *
 * The launcher draws this, not Flutter, so everything here is RemoteViews and
 * nothing here computes anything. What to show was decided in Dart by Attention
 * and handed over by [AttentionBridge]; this only paints it.
 *
 * That split is what keeps the widget and the app from ever disagreeing. The
 * alternative, reading the database from the broadcast receiver, would mean two
 * implementations of "who owes you money" and a home screen that disagrees with
 * the app beside it.
 *
 * The character changes with what is outstanding, which is the whole point of
 * putting it there: something to look at that is not a number.
 */
class KoruWidgetProvider : AppWidgetProvider() {

    companion object {
        const val ACTION_UPDATE = "com.abduljabbar.koru.WIDGET_UPDATE"

        /**
         * Pasted into RemoteViews.setTextViewText by AttentionBridge.
         *
         * Public because it is written from another class, and documented
         * because the alternative is a magic string in two files.
         */
        const val EXTRA_COUNT = "count"
        const val EXTRA_HEADLINE = "headline"
        const val EXTRA_TOP = "top"
        const val EXTRA_MOOD = "mood"

        /** calm, thinking, cheer, wave. Anything unrecognised falls back to calm. */
        private fun drawableFor(mood: String): Int = when (mood) {
            "thinking" -> R.drawable.koru_think
            "cheer" -> R.drawable.koru_cheer
            "wave" -> R.drawable.koru_wave
            else -> R.drawable.koru_idle
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, build(context, 0, "", "", "calm"))
        }
    }

    /**
     * Repaints every instance.
     *
     * Deliberately not saving history or any other state: the launcher can kill
     * and recreate this receiver at any time, and anything read here would have
     * to survive being read from nothing. The payload always comes with the
     * broadcast instead.
     */
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action != ACTION_UPDATE) return

        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(
            android.content.ComponentName(context, KoruWidgetProvider::class.java)
        )
        if (ids.isEmpty()) return

        val views = build(
            context,
            intent.getIntExtra(EXTRA_COUNT, 0),
            intent.getStringExtra(EXTRA_HEADLINE) ?: "",
            intent.getStringExtra(EXTRA_TOP) ?: "",
            intent.getStringExtra(EXTRA_MOOD) ?: "calm",
        )
        manager.updateAppWidget(ids, views)
    }

    private fun build(
        context: Context,
        count: Int,
        headline: String,
        top: String,
        mood: String,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.koru_widget)

        views.setImageViewResource(R.id.koru_character, drawableFor(mood))

        // Two lines, because the honest version needs both: what is going on,
        // and the single worst thing about it.
        views.setTextViewText(R.id.koru_headline, if (count == 0) "All clear" else headline)
        views.setTextViewText(R.id.koru_detail, if (count == 0) "Nothing needs you" else top)

        // The badge is the only place a count appears, and it is hidden rather
        // than zeroed when there is nothing, because "0" on a home screen reads
        // as a failure to load.
        if (count > 0) {
            views.setViewVisibility(R.id.koru_badge, android.view.View.VISIBLE)
            views.setTextViewText(R.id.koru_badge, if (count > 9) "9+" else "$count")
        } else {
            views.setViewVisibility(R.id.koru_badge, android.view.View.GONE)
        }

        views.setOnClickPendingIntent(R.id.koru_widget, openIntent(context))
        views.setOnClickPendingIntent(R.id.koru_character, openIntent(context))
        views.setOnClickPendingIntent(R.id.koru_badge, openIntent(context))
        return views
    }

    /**
     * Tapping anywhere on the widget opens the app.
     *
     * Goes to the chat rather than deep into a client or project on purpose: the
     * widget shows the headline of whatever is worst, and the worst thing
     * changes between the moment it was drawn and the moment it is tapped, so
     * landing on a specific client would be confidently wrong at least some of
     * the time. Chat is always a safe place to land.
     */
    private fun openIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            action = Intent.ACTION_VIEW
            data = android.net.Uri.parse("koru://attention/chat/chat")
        }
        return PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}