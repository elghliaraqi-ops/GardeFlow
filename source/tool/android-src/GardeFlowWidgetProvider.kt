package com.huim6.huim6_planning

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.view.View
import android.widget.RemoteViews
import java.util.Calendar
import kotlin.math.max

class GardeFlowWidgetProvider : AppWidgetProvider() {
    companion object {
        const val PREFS_NAME = "gardeflow_widget"
        private const val EXTRA_WIDGET_ACTION = "gardeflow_widget_action"

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, GardeFlowWidgetProvider::class.java)
            val ids = manager.getAppWidgetIds(component)
            ids.forEach { updateWidget(context, manager, it) }
        }

        private fun updateWidget(
            context: Context,
            manager: AppWidgetManager,
            appWidgetId: Int,
        ) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val views = RemoteViews(context.packageName, R.layout.gardeflow_widget)

            val hour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
            val greeting = if (hour >= 18 || hour < 6) "Bonsoir" else "Bonjour"
            val doctor = prefs.getString("doctor_name", "Docteur").orEmpty()
            val today = prefs.getString(
                "today_status",
                "Ouvrez GardeFlow pour synchroniser",
            ).orEmpty()
            val dateLabel = prefs.getString("date_label", "").orEmpty()
            val nextTitle = prefs.getString("next_title", "Prochaine garde").orEmpty()
            val nextDetail = prefs.getString(
                "next_detail",
                "Planning non synchronisé",
            ).orEmpty()
            val shiftId = prefs.getString("next_shift_id", "none").orEmpty()

            views.setTextViewText(R.id.widget_greeting, "$greeting $doctor")
            views.setTextViewText(R.id.widget_today_status, today)
            views.setTextViewText(R.id.widget_date, dateLabel)
            views.setTextViewText(R.id.widget_next_title, nextTitle)
            views.setTextViewText(R.id.widget_next_detail, nextDetail)

            val countdown = countdownLabel(prefs)
            views.setTextViewText(R.id.widget_next_countdown, countdown)
            views.setViewVisibility(
                R.id.widget_next_countdown,
                if (countdown.isBlank()) View.GONE else View.VISIBLE,
            )

            views.setTextViewText(
                R.id.widget_planning_detail,
                prefs.getString("planning_detail", "Voir le mois").orEmpty(),
            )
            setOptionalLine(
                views,
                R.id.widget_planning_line_1,
                prefs.getString("planning_line_1", "").orEmpty(),
            )
            setOptionalLine(
                views,
                R.id.widget_planning_line_2,
                prefs.getString("planning_line_2", "").orEmpty(),
            )
            setOptionalLine(
                views,
                R.id.widget_planning_line_3,
                prefs.getString("planning_line_3", "").orEmpty(),
            )

            views.setTextViewText(
                R.id.widget_astreintes_detail,
                prefs.getString("astreintes_detail", "Aujourd’hui").orEmpty(),
            )
            views.setTextViewText(
                R.id.widget_astreintes_subdetail,
                prefs.getString(
                    "astreintes_subdetail",
                    "Juniors + séniors · accès direct",
                ).orEmpty(),
            )
            views.setTextViewText(
                R.id.widget_practice_detail,
                prefs.getString("practice_detail", "Ce mois · QCM").orEmpty(),
            )
            views.setTextViewText(
                R.id.widget_practice_subdetail,
                prefs.getString(
                    "practice_subdetail",
                    "Ouvrir Practice",
                ).orEmpty(),
            )

            val visual = visualFor(shiftId)
            views.setInt(R.id.widget_next_card, "setBackgroundResource", visual.background)
            views.setTextViewText(R.id.widget_next_icon, visual.icon)
            views.setTextColor(R.id.widget_next_title, Color.WHITE)
            views.setTextColor(R.id.widget_next_detail, visual.detailColor)

            views.setOnClickPendingIntent(
                R.id.widget_next_card,
                openApp(context, "next_guard", 11),
            )
            views.setOnClickPendingIntent(
                R.id.widget_planning_card,
                openApp(context, "planning", 12),
            )
            views.setOnClickPendingIntent(
                R.id.widget_astreintes_card,
                openApp(context, "astreintes", 13),
            )
            views.setOnClickPendingIntent(
                R.id.widget_practice_card,
                openApp(context, "practice", 14),
            )
            views.setOnClickPendingIntent(
                R.id.widget_header,
                openApp(context, "home", 15),
            )

            manager.updateAppWidget(appWidgetId, views)
        }

        private fun setOptionalLine(views: RemoteViews, id: Int, text: String) {
            views.setTextViewText(id, text)
            views.setViewVisibility(id, if (text.isBlank()) View.GONE else View.VISIBLE)
        }

        private fun countdownLabel(
            prefs: android.content.SharedPreferences,
        ): String {
            val start = prefs.getString("next_start_ms", "")?.toLongOrNull() ?: return ""
            val end = prefs.getString("next_end_ms", "")?.toLongOrNull() ?: return ""
            val now = System.currentTimeMillis()
            return when {
                now in start until end -> "En cours · finit dans ${formatDuration(end - now)}"
                start > now -> "Dans ${formatDuration(start - now)}"
                else -> ""
            }
        }

        private fun formatDuration(milliseconds: Long): String {
            val totalMinutes = max(0L, milliseconds / 60_000L)
            val days = totalMinutes / (24L * 60L)
            val hours = (totalMinutes % (24L * 60L)) / 60L
            val minutes = totalMinutes % 60L
            return when {
                days > 0L && hours > 0L -> "$days j $hours h"
                days > 0L -> "$days j"
                hours > 0L && minutes > 0L -> "$hours h $minutes min"
                hours > 0L -> "$hours h"
                else -> "$minutes min"
            }
        }

        private fun openApp(context: Context, action: String, requestCode: Int): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra(EXTRA_WIDGET_ACTION, action)
            }
            return PendingIntent.getActivity(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private data class WidgetVisual(
            val background: Int,
            val icon: String,
            val detailColor: Int = Color.WHITE,
        )

        private fun visualFor(shiftId: String): WidgetVisual = when (shiftId) {
            "urg-jour" -> WidgetVisual(
                R.drawable.bg_widget_urg_day,
                "☀",
                Color.rgb(255, 245, 245),
            )
            "urg-nuit" -> WidgetVisual(
                R.drawable.bg_widget_urg_night,
                "☾",
                Color.rgb(255, 238, 238),
            )
            "urg-24h" -> WidgetVisual(
                R.drawable.bg_widget_urg_24,
                "☀  ☾",
                Color.rgb(255, 250, 238),
            )
            "service-jour" -> WidgetVisual(
                R.drawable.bg_widget_service_day,
                "☀",
                Color.rgb(241, 249, 255),
            )
            "service-nuit" -> WidgetVisual(
                R.drawable.bg_widget_service_night,
                "☾",
                Color.rgb(235, 244, 255),
            )
            "service-24h" -> WidgetVisual(
                R.drawable.bg_widget_service_24,
                "☀  ☾",
                Color.rgb(239, 250, 255),
            )
            else -> WidgetVisual(
                R.drawable.bg_widget_next_default,
                "＋",
                Color.rgb(210, 225, 239),
            )
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { updateWidget(context, appWidgetManager, it) }
    }

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        updateAll(context)
    }
}
