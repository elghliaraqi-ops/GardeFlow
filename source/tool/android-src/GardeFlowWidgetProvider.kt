package com.huim6.huim6_planning

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.util.TypedValue
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
            val nextTitle = prefs.getString("next_title", "Aucune garde à venir").orEmpty()
            val nextDetail = prefs.getString(
                "next_detail",
                "Votre planning est à jour",
            ).orEmpty()
            val shiftId = prefs.getString("next_shift_id", "none").orEmpty()
            val hasGuard = shiftId != "none" && shiftId.isNotBlank()

            val titleParts = nextTitle.split(" · ", limit = 2)
            val rawCategory = titleParts.firstOrNull().orEmpty()
            val category = when {
                !hasGuard -> "AUCUNE GARDE"
                rawCategory == "URGENCES" -> "URGENCE"
                rawCategory.isBlank() -> if (shiftId.startsWith("urg")) "URGENCE" else "SERVICE"
                else -> rawCategory
            }
            val period = if (hasGuard) {
                titleParts.getOrNull(1)?.trim().orEmpty().ifBlank { periodFor(shiftId) }
            } else {
                ""
            }

            val detailParts = nextDetail.split(" · ", limit = 2)
            val nextDate = if (hasGuard) {
                detailParts.firstOrNull().orEmpty().ifBlank { "Prochaine garde" }
            } else {
                "Planning synchronisé"
            }
            val nextTime = if (hasGuard) detailParts.getOrNull(1)?.trim().orEmpty() else ""

            views.setTextViewText(R.id.widget_greeting, "$greeting $doctor")
            views.setTextViewText(R.id.widget_today_status, today)
            views.setTextViewText(R.id.widget_date, dateLabel)
            views.setTextViewText(R.id.widget_next_category, category)
            views.setTextViewText(R.id.widget_next_period, period)
            views.setTextViewText(
                R.id.widget_next_title,
                if (hasGuard) "" else "Aucune garde à venir",
            )
            views.setViewVisibility(
                R.id.widget_next_title,
                if (hasGuard) View.GONE else View.VISIBLE,
            )
            views.setTextViewText(R.id.widget_next_date, nextDate)
            views.setTextViewText(R.id.widget_next_time, nextTime)
            views.setViewVisibility(
                R.id.widget_next_time,
                if (nextTime.isBlank()) View.GONE else View.VISIBLE,
            )
            views.setTextViewText(
                R.id.widget_next_detail,
                if (hasGuard) "Touchez pour ouvrir GardeFlow" else nextDetail,
            )

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
                compactPracticeLabel(
                    prefs.getString("practice_detail", "QCM & cas cliniques").orEmpty(),
                ),
            )
            views.setTextViewText(
                R.id.widget_practice_subdetail,
                prefs.getString("practice_subdetail", "Ouvrir Practice").orEmpty(),
            )

            val visual = visualFor(shiftId)
            views.setInt(R.id.widget_next_card, "setBackgroundResource", visual.background)
            views.setTextViewText(R.id.widget_next_icon, visual.icon)
            views.setTextColor(R.id.widget_next_icon, visual.iconColor)
            views.setTextColor(R.id.widget_next_category, visual.primaryTextColor)
            views.setTextColor(R.id.widget_next_period, visual.primaryTextColor)
            views.setTextColor(R.id.widget_next_date, visual.secondaryTextColor)
            views.setTextColor(R.id.widget_next_time, visual.secondaryTextColor)
            views.setTextColor(R.id.widget_next_detail, visual.secondaryTextColor)
            views.setTextColor(R.id.widget_next_countdown, visual.primaryTextColor)
            views.setViewVisibility(
                R.id.widget_next_period,
                if (period.isBlank()) View.GONE else View.VISIBLE,
            )

            applyResponsiveLayout(manager, appWidgetId, views, hasGuard)

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
            views.setOnClickPendingIntent(
                R.id.widget_root,
                openApp(context, "home", 16),
            )

            manager.updateAppWidget(appWidgetId, views)
        }

        private fun applyResponsiveLayout(
            manager: AppWidgetManager,
            appWidgetId: Int,
            views: RemoteViews,
            hasGuard: Boolean,
        ) {
            val options = manager.getAppWidgetOptions(appWidgetId)
            val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 250)
            val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 220)

            val compact = minHeight < 155 || minWidth < 215
            val large = minHeight >= 205 && minWidth >= 245

            views.setViewVisibility(
                R.id.widget_header,
                if (compact) View.GONE else View.VISIBLE,
            )
            views.setViewVisibility(
                R.id.widget_secondary_group,
                if (large) View.VISIBLE else View.GONE,
            )
            views.setViewVisibility(
                R.id.widget_next_detail,
                if (compact) View.GONE else View.VISIBLE,
            )
            views.setViewPadding(
                R.id.widget_root,
                if (compact) 8 else 12,
                if (compact) 8 else 12,
                if (compact) 8 else 12,
                if (compact) 8 else 12,
            )
            views.setTextViewTextSize(
                R.id.widget_next_category,
                TypedValue.COMPLEX_UNIT_SP,
                if (compact) 16f else 18f,
            )
            if (compact && !hasGuard) {
                views.setViewVisibility(R.id.widget_next_detail, View.VISIBLE)
            }
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
                now in start until end -> "EN COURS · finit dans ${formatDuration(end - now)}"
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

        private fun periodFor(shiftId: String): String = when {
            shiftId.endsWith("jour") -> "JOUR"
            shiftId.endsWith("nuit") -> "NUIT"
            shiftId.endsWith("24h") -> "24H"
            else -> ""
        }

        private fun compactPracticeLabel(value: String): String {
            return value
                .replace("Ce mois · ", "")
                .replace(" répondus", "")
                .replace("aucun QCM", "0 QCM")
                .take(24)
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
            val iconColor: Int,
            val primaryTextColor: Int = Color.WHITE,
            val secondaryTextColor: Int = Color.rgb(240, 246, 243),
        )

        private fun visualFor(shiftId: String): WidgetVisual = when (shiftId) {
            "urg-jour" -> WidgetVisual(
                R.drawable.bg_widget_urg_day,
                "☀",
                Color.rgb(255, 219, 77),
            )
            "urg-nuit" -> WidgetVisual(
                R.drawable.bg_widget_urg_night,
                "☾",
                Color.WHITE,
                secondaryTextColor = Color.rgb(255, 232, 235),
            )
            "urg-24h" -> WidgetVisual(
                R.drawable.bg_widget_urg_24,
                "☀  ☾",
                Color.WHITE,
                secondaryTextColor = Color.rgb(255, 241, 232),
            )
            "service-jour" -> WidgetVisual(
                R.drawable.bg_widget_service_day,
                "☀",
                Color.rgb(255, 219, 77),
                secondaryTextColor = Color.rgb(239, 248, 255),
            )
            "service-nuit" -> WidgetVisual(
                R.drawable.bg_widget_service_night,
                "☾",
                Color.WHITE,
                secondaryTextColor = Color.rgb(231, 241, 255),
            )
            "service-24h" -> WidgetVisual(
                R.drawable.bg_widget_service_24,
                "☀  ☾",
                Color.WHITE,
                secondaryTextColor = Color.rgb(236, 248, 255),
            )
            else -> WidgetVisual(
                R.drawable.bg_widget_next_default,
                "✓",
                Color.WHITE,
                secondaryTextColor = Color.rgb(218, 233, 226),
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

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: android.os.Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        updateWidget(context, appWidgetManager, appWidgetId)
    }

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        updateAll(context)
    }
}
