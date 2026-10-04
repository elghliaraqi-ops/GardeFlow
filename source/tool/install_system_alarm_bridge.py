from pathlib import Path
import re
import xml.etree.ElementTree as ET

ANDROID_NS = "http://schemas.android.com/apk/res/android"
A = lambda name: f"{{{ANDROID_NS}}}{name}"
ET.register_namespace("android", ANDROID_NS)

manifest_path = Path("android/app/src/main/AndroidManifest.xml")
if not manifest_path.exists():
    raise SystemExit("GardeFlow system alarm bridge: AndroidManifest.xml missing")

main_candidates = list(Path("android/app/src/main/kotlin").rglob("MainActivity.kt"))
if not main_candidates:
    raise SystemExit("GardeFlow system alarm bridge: MainActivity.kt missing")

main_activity = main_candidates[0]
main_text = main_activity.read_text(encoding="utf-8")
package_match = re.search(r"^package\s+([\w.]+)", main_text, re.MULTILINE)
package_name = package_match.group(1) if package_match else "com.huim6.huim6_planning"
alarm_activity_path = main_activity.parent / "AlarmActivity.kt"

kotlin = r'''package __PACKAGE__

import android.app.Activity
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.Space
import android.widget.TextClock
import android.widget.TextView
import org.json.JSONObject

class AlarmActivity : Activity() {
    private var alarmId: Int = -1
    private var vibrationEnabled = true
    private var alarmTitle = "Garde à venir"
    private var alarmBody = ""
    private var alarmPayload = ""
    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        alarmId = intent.getIntExtra("alarmId", -1)
        vibrationEnabled = intent.getBooleanExtra("vibration", true)
        alarmTitle = intent.getStringExtra("alarmTitle")?.trim()?.takeIf { it.isNotEmpty() }
            ?: "Garde à venir"
        alarmBody = intent.getStringExtra("alarmBody")?.trim().orEmpty()
        alarmPayload = intent.getStringExtra("alarmPayload").orEmpty()

        GuardAlarmScheduler.removePersisted(this, alarmId)
        configureAlarmWindow()
        renderAlarm()
        startSignal()
    }

    private fun configureAlarmWindow() {
        window.addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_ALLOW_LOCK_WHILE_SCREEN_ON
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }
        enterImmersiveMode()
    }

    @Suppress("DEPRECATION")
    private fun enterImmersiveMode() {
        window.decorView.systemUiVisibility =
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                View.SYSTEM_UI_FLAG_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) enterImmersiveMode()
    }

    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        // Une alarme de garde doit être arrêtée ou reportée explicitement.
    }

    override fun onDestroy() {
        if (isFinishing) stopSignal()
        super.onDestroy()
    }

    private fun startSignal() {
        try {
            val alarmUri = RingtoneManager.getActualDefaultRingtoneUri(
                this,
                RingtoneManager.TYPE_ALARM
            ) ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            mediaPlayer = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                setDataSource(this@AlarmActivity, alarmUri)
                isLooping = true
                prepare()
                start()
            }
        } catch (_: Throwable) {
            mediaPlayer = null
        }

        if (!vibrationEnabled) return
        try {
            vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                getSystemService(VibratorManager::class.java)?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            }
            val pattern = longArrayOf(0, 700, 350, 700, 350)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(pattern, 0)
            }
        } catch (_: Throwable) {
            vibrator = null
        }
    }

    private fun stopSignal() {
        try { mediaPlayer?.stop() } catch (_: Throwable) {}
        try { mediaPlayer?.release() } catch (_: Throwable) {}
        mediaPlayer = null
        try { vibrator?.cancel() } catch (_: Throwable) {}
        vibrator = null
    }

    private fun renderAlarm() {
        val semantic = "$alarmTitle $alarmBody"
            .lowercase()
            .replace('\n', ' ')
            .replace(Regex("\\s+"), " ")
        val is24h = semantic.contains("24h") || semantic.contains("24 h")
        val isNight = !is24h && semantic.contains("nuit")
        val isUrgences = semantic.contains("urgence") || semantic.contains("urg-")
        val category = if (isUrgences) "URGENCES" else "SERVICE"
        val shiftKind = when {
            is24h -> "24H"
            isNight -> "NUIT"
            else -> "JOUR"
        }

        val dayTop = Color.rgb(66, 183, 255)
        val dayBottom = Color.rgb(0, 106, 214)
        val nightTop = Color.rgb(3, 11, 27)
        val nightBottom = Color.rgb(14, 47, 91)
        val colors = when {
            is24h -> intArrayOf(dayTop, dayBottom, nightTop, nightBottom)
            isNight -> intArrayOf(nightTop, nightBottom)
            else -> intArrayOf(dayTop, dayBottom)
        }

        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(26), dp(34), dp(26), dp(26))
            background = GradientDrawable(GradientDrawable.Orientation.TL_BR, colors)
        }

        root.addView(label("GardeFlow", 18f, true, 1f))
        root.addView(Space(this), LinearLayout.LayoutParams(1, dp(14)))
        root.addView(chip("ALARME SYSTÈME DE GARDE"), LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, dp(34)))
        root.addView(Space(this), LinearLayout.LayoutParams(1, dp(14)))
        root.addView(TextClock(this).apply {
            format12Hour = "HH:mm"
            format24Hour = "HH:mm"
            textSize = 44f
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
        }, fullWidthWrap())
        root.addView(Space(this), LinearLayout.LayoutParams(1, dp(12)))
        root.addView(label(if (isNight) "✦   ☾   ✦" else if (is24h) "☀     ☾" else "☀", 48f, false, 0.96f))
        root.addView(Space(this), LinearLayout.LayoutParams(1, dp(12)))
        root.addView(label(category, 22f, true, 1f))
        root.addView(label(shiftKind, 64f, true, 1f))
        root.addView(Space(this), LinearLayout.LayoutParams(1, dp(8)))
        root.addView(label(alarmTitle, if (alarmTitle.length <= 30) 20f else 17f, true, 0.98f))
        if (alarmBody.isNotEmpty()) {
            root.addView(Space(this), LinearLayout.LayoutParams(1, dp(8)))
            root.addView(label(alarmBody, if (alarmBody.length <= 60) 17f else 15f, false, 0.88f).apply { maxLines = 4 })
        }
        root.addView(Space(this), LinearLayout.LayoutParams(1, 0, 1f))
        root.addView(label("Alarme programmée par Android · elle sonne jusqu’à votre action", 12f, false, 0.78f))
        root.addView(Space(this), LinearLayout.LayoutParams(1, dp(12)))
        root.addView(
            actionButton("RAPPEL 9 MIN", Color.argb(238, 255, 255, 255), Color.rgb(14, 44, 78)) { snoozeAlarm() },
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(62))
        )
        root.addView(Space(this), LinearLayout.LayoutParams(1, dp(10)))
        root.addView(
            actionButton("J’AI VU — ARRÊTER", Color.argb(48, 255, 255, 255), Color.WHITE) { stopAlarm() },
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(62))
        )
        setContentView(root)
    }

    private fun snoozeAlarm() {
        stopSignal()
        GuardAlarmScheduler.schedule(
            this,
            alarmId,
            System.currentTimeMillis() + 9L * 60L * 1000L,
            alarmTitle,
            alarmBody,
            vibrationEnabled,
            alarmPayload,
            true
        )
        finishAndRemoveTask()
    }

    private fun stopAlarm() {
        stopSignal()
        GuardAlarmScheduler.cancel(this, alarmId, true)
        finishAndRemoveTask()
    }

    private fun label(textValue: String, size: Float, bold: Boolean, opacity: Float): TextView =
        TextView(this).apply {
            text = textValue
            textSize = size
            setTextColor(Color.WHITE)
            typeface = if (bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
            gravity = Gravity.CENTER
            alpha = opacity
        }

    private fun chip(textValue: String): TextView = TextView(this).apply {
        text = textValue
        textSize = 11f
        setTextColor(Color.WHITE)
        typeface = Typeface.DEFAULT_BOLD
        gravity = Gravity.CENTER
        setPadding(dp(16), 0, dp(16), 0)
        letterSpacing = 0.08f
        background = GradientDrawable().apply {
            setColor(Color.argb(40, 255, 255, 255))
            cornerRadius = dp(999).toFloat()
            setStroke(dp(1), Color.argb(70, 255, 255, 255))
        }
    }

    private fun actionButton(textValue: String, fill: Int, textColor: Int, onClick: () -> Unit): Button =
        Button(this).apply {
            text = textValue
            textSize = 16f
            setTextColor(textColor)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            isAllCaps = false
            background = GradientDrawable().apply {
                setColor(fill)
                cornerRadius = dp(22).toFloat()
            }
            backgroundTintList = ColorStateList.valueOf(fill)
            stateListAnimator = null
            setOnClickListener { onClick() }
        }

    private fun fullWidthWrap() = LinearLayout.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT,
        ViewGroup.LayoutParams.WRAP_CONTENT
    )

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
}

object GuardAlarmScheduler {
    private const val PREFS = "gardeflow_system_alarms"
    private const val KEY_PREFIX = "alarm_"

    fun canScheduleExact(context: Context): Boolean {
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.S || manager.canScheduleExactAlarms()
    }

    fun schedule(
        context: Context,
        id: Int,
        triggerAtMillis: Long,
        title: String,
        body: String,
        vibration: Boolean,
        payload: String,
        persist: Boolean
    ): Boolean {
        if (id <= 0 || triggerAtMillis <= System.currentTimeMillis()) return false
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !manager.canScheduleExactAlarms()) return false
        val operation = alarmPendingIntent(context, id, title, body, vibration, payload)
        return try {
            manager.setAlarmClock(AlarmManager.AlarmClockInfo(triggerAtMillis, operation), operation)
            if (persist) persist(context, id, triggerAtMillis, title, body, vibration, payload)
            true
        } catch (_: SecurityException) {
            false
        } catch (_: Throwable) {
            false
        }
    }

    fun cancel(context: Context, id: Int, removePersisted: Boolean) {
        if (id <= 0) return
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, AlarmActivity::class.java).apply {
            action = "__PACKAGE__.GUARD_ALARM.$id"
        }
        val pending = PendingIntent.getActivity(
            context,
            id,
            intent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        )
        if (pending != null) {
            try { manager.cancel(pending) } catch (_: Throwable) {}
            try { pending.cancel() } catch (_: Throwable) {}
        }
        if (removePersisted) removePersisted(context, id)
    }

    fun cancelByPayloadPrefix(context: Context, prefix: String) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val ids = prefs.all.values.mapNotNull { rawAny ->
            val raw = rawAny as? String ?: return@mapNotNull null
            try {
                val obj = JSONObject(raw)
                if (obj.optString("payload").startsWith(prefix)) obj.optInt("id") else null
            } catch (_: Throwable) { null }
        }
        ids.forEach { cancel(context, it, true) }
    }

    fun cancelAll(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val ids = prefs.all.values.mapNotNull { rawAny ->
            val raw = rawAny as? String ?: return@mapNotNull null
            try { JSONObject(raw).optInt("id") } catch (_: Throwable) { null }
        }
        ids.forEach { cancel(context, it, false) }
        prefs.edit().clear().apply()
    }

    fun restoreAll(context: Context) {
        if (!canScheduleExact(context)) return
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        val stale = mutableListOf<String>()
        prefs.all.forEach { (key, rawAny) ->
            val raw = rawAny as? String ?: return@forEach
            try {
                val obj = JSONObject(raw)
                val trigger = obj.getLong("trigger")
                if (trigger <= now) {
                    stale.add(key)
                } else {
                    schedule(
                        context,
                        obj.getInt("id"),
                        trigger,
                        obj.optString("title", "Garde à venir"),
                        obj.optString("body", ""),
                        obj.optBoolean("vibration", true),
                        obj.optString("payload", ""),
                        false
                    )
                }
            } catch (_: Throwable) {
                stale.add(key)
            }
        }
        if (stale.isNotEmpty()) {
            val editor = prefs.edit()
            stale.forEach { editor.remove(it) }
            editor.apply()
        }
    }

    fun removePersisted(context: Context, id: Int) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().remove("$KEY_PREFIX$id").apply()
    }

    private fun persist(
        context: Context,
        id: Int,
        triggerAtMillis: Long,
        title: String,
        body: String,
        vibration: Boolean,
        payload: String
    ) {
        val obj = JSONObject()
            .put("id", id)
            .put("trigger", triggerAtMillis)
            .put("title", title)
            .put("body", body)
            .put("vibration", vibration)
            .put("payload", payload)
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString("$KEY_PREFIX$id", obj.toString()).apply()
    }

    private fun alarmPendingIntent(
        context: Context,
        id: Int,
        title: String,
        body: String,
        vibration: Boolean,
        payload: String
    ): PendingIntent {
        val intent = Intent(context, AlarmActivity::class.java).apply {
            action = "__PACKAGE__.GUARD_ALARM.$id"
            putExtra("alarmId", id)
            putExtra("alarmTitle", title)
            putExtra("alarmBody", body)
            putExtra("alarmPayload", payload)
            putExtra("vibration", vibration)
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            )
        }
        return PendingIntent.getActivity(
            context,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}

class GuardAlarmBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        when (intent?.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED ->
                GuardAlarmScheduler.restoreAll(context)
        }
    }
}
'''.replace("__PACKAGE__", package_name)

alarm_activity_path.write_text(kotlin, encoding="utf-8")

main_kotlin = r'''package __PACKAGE__

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val WIDGET_CHANNEL = "com.huim6.huim6_planning/widget"
        private const val EXTRA_WIDGET_ACTION = "gardeflow_widget_action"
    }

    private var widgetChannel: MethodChannel? = null
    private var pendingWidgetAction: String? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingWidgetAction = intent?.getStringExtra(EXTRA_WIDGET_ACTION)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "gardeflow/fullscreen_alarm"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isSystemAlarmBridgeAvailable" -> result.success(true)
                "scheduleSystemAlarm" -> {
                    val alarmId = call.argument<Int>("alarmId") ?: -1
                    val triggerAtMillis = call.argument<Number>("triggerAtMillis")?.toLong() ?: 0L
                    val title = call.argument<String>("alarmTitle") ?: "Garde à venir"
                    val body = call.argument<String>("alarmBody").orEmpty()
                    val vibration = call.argument<Boolean>("vibration") ?: true
                    val payload = call.argument<String>("alarmPayload").orEmpty()
                    result.success(
                        GuardAlarmScheduler.schedule(
                            this, alarmId, triggerAtMillis, title, body,
                            vibration, payload, true
                        )
                    )
                }
                "cancelSystemGuardAlarms" -> {
                    val prefix = call.argument<String>("payloadPrefix").orEmpty()
                    if (prefix.isNotEmpty()) GuardAlarmScheduler.cancelByPayloadPrefix(this, prefix)
                    result.success(true)
                }
                "cancelAllSystemGuardAlarms" -> {
                    GuardAlarmScheduler.cancelAll(this)
                    result.success(true)
                }
                "openAlarmActivity" -> {
                    val alarmId = call.argument<Int>("alarmId") ?: -1
                    val title = call.argument<String>("alarmTitle") ?: "Test alarme de garde"
                    val body = call.argument<String>("alarmBody").orEmpty()
                    val vibration = call.argument<Boolean>("vibration") ?: true
                    startActivity(Intent(this, AlarmActivity::class.java).apply {
                        putExtra("alarmId", alarmId)
                        putExtra("alarmTitle", title)
                        putExtra("alarmBody", body)
                        putExtra("alarmPayload", "guard:test")
                        putExtra("vibration", vibration)
                        addFlags(
                            Intent.FLAG_ACTIVITY_NEW_TASK or
                                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                                Intent.FLAG_ACTIVITY_SINGLE_TOP
                        )
                    })
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        widgetChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            WIDGET_CHANNEL
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialWidgetAction" -> {
                        val value = pendingWidgetAction
                        pendingWidgetAction = null
                        result.success(value)
                    }
                    "updateWidgetData" -> {
                        @Suppress("UNCHECKED_CAST")
                        val values = call.arguments as? Map<String, Any?> ?: emptyMap()
                        val prefs = getSharedPreferences(GardeFlowWidgetProvider.PREFS_NAME, MODE_PRIVATE)
                        val editor = prefs.edit()
                        values.forEach { (key, value) ->
                            editor.putString(key, value?.toString().orEmpty())
                        }
                        editor.apply()
                        GardeFlowWidgetProvider.updateAll(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val action = intent.getStringExtra(EXTRA_WIDGET_ACTION)
        if (!action.isNullOrBlank()) {
            pendingWidgetAction = action
            widgetChannel?.invokeMethod("widgetAction", action)
        }
    }
}
'''.replace("__PACKAGE__", package_name)
main_activity.write_text(main_kotlin, encoding="utf-8")

tree = ET.parse(manifest_path)
root = tree.getroot()
application = root.find("application")
if application is None:
    raise SystemExit("GardeFlow system alarm bridge: <application> missing")

for receiver in list(application.findall("receiver")):
    name = receiver.get(A("name"), "")
    if name in {".GuardAlarmBootReceiver", f"{package_name}.GuardAlarmBootReceiver"}:
        application.remove(receiver)

receiver = ET.Element(
    "receiver",
    {
        A("name"): ".GuardAlarmBootReceiver",
        A("enabled"): "true",
        A("exported"): "false",
    },
)
intent_filter = ET.SubElement(receiver, "intent-filter")
for action in [
    "android.intent.action.BOOT_COMPLETED",
    "android.intent.action.MY_PACKAGE_REPLACED",
    "android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED",
]:
    ET.SubElement(intent_filter, "action", {A("name"): action})
application.append(receiver)

tree.write(manifest_path, encoding="utf-8", xml_declaration=True)

print(f"Installed native Android AlarmManager bridge in {main_activity}")
print(f"Installed native system AlarmActivity in {alarm_activity_path}")
