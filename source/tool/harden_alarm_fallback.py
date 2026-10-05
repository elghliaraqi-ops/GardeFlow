from pathlib import Path
import re
import xml.etree.ElementTree as ET

# GardeFlow Android alarm hardening.
#
# Final native chain:
# AlarmManager -> BroadcastReceiver -> foreground alarm Service -> WakeLock
# -> CATEGORY_ALARM full-screen notification -> AlarmActivity.
#
# The foreground service owns sound/vibration. This keeps the alarm ringing
# even when Android decides to show a heads-up notification instead of
# immediately bringing AlarmActivity in front of the current app.

ANDROID_NS = "http://schemas.android.com/apk/res/android"
A = lambda name: f"{{{ANDROID_NS}}}{name}"
ET.register_namespace("android", ANDROID_NS)

alarm_candidates = list(Path("android/app/src/main/kotlin").rglob("AlarmActivity.kt"))
main_candidates = list(Path("android/app/src/main/kotlin").rglob("MainActivity.kt"))
manifest_path = Path("android/app/src/main/AndroidManifest.xml")

if not alarm_candidates:
    raise SystemExit("GardeFlow alarm hardening: AlarmActivity.kt missing")
if not main_candidates:
    raise SystemExit("GardeFlow alarm hardening: MainActivity.kt missing")
if not manifest_path.exists():
    raise SystemExit("GardeFlow alarm hardening: AndroidManifest.xml missing")

alarm_path = alarm_candidates[0]
main_path = main_candidates[0]
text = alarm_path.read_text(encoding="utf-8")
main_text = main_path.read_text(encoding="utf-8")
package_match = re.search(r"^package\s+([\w.]+)", text, re.MULTILINE)
package_name = package_match.group(1) if package_match else "com.huim6.huim6_planning"


def replace_once(source: str, old: str, new: str, label: str) -> str:
    if old not in source:
        raise SystemExit(f"GardeFlow alarm hardening: {label} not found")
    return source.replace(old, new, 1)


# Foreground alarm service dependencies.
text = replace_once(
    text,
    """import android.app.Activity
import android.app.AlarmManager
import android.app.PendingIntent
""",
    """import android.app.Activity
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
""",
    "Android app imports",
)
text = replace_once(
    text,
    "import android.content.Intent\n",
    """import android.content.Intent
import android.content.pm.ServiceInfo
""",
    "Intent import",
)
text = replace_once(
    text,
    "import android.os.Build\n",
    """import android.os.Build
import android.os.IBinder
import android.os.PowerManager
""",
    "Build import",
)

# Once the alarm has fired, the Service owns persistence + ringing.
text = replace_once(
    text,
    "        GuardAlarmScheduler.removePersisted(this, alarmId)\n",
    "",
    "Activity persisted-alarm removal",
)

# Normal full-screen Activity: no second MediaPlayer. If starting the foreground
# service itself is rejected by an OEM, the receiver opens this Activity with
# standaloneSignal=true and this old signal path remains as a last fallback.
text = replace_once(
    text,
    """        configureAlarmWindow()
        renderAlarm()
        startSignal()
""",
    """        configureAlarmWindow()
        renderAlarm()
        if (intent.getBooleanExtra("standaloneSignal", false)) startSignal()
""",
    "Activity signal startup",
)

old_snooze = """    private fun snoozeAlarm() {
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
"""
new_snooze = """    private fun snoozeAlarm() {
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
        GuardAlarmService.dismissCurrent(this, alarmId)
        finishAndRemoveTask()
    }
"""
text = replace_once(text, old_snooze, new_snooze, "Activity snooze")

old_stop = """    private fun stopAlarm() {
        stopSignal()
        GuardAlarmScheduler.cancel(this, alarmId, true)
        finishAndRemoveTask()
    }
"""
new_stop = """    private fun stopAlarm() {
        stopSignal()
        GuardAlarmScheduler.cancel(this, alarmId, true)
        GuardAlarmService.dismissCurrent(this, alarmId)
        finishAndRemoveTask()
    }
"""
text = replace_once(text, old_stop, new_stop, "Activity stop")

service_code = r'''
class GuardAlarmTriggerReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent == null) return
        try {
            GuardAlarmService.startRinging(context, intent)
        } catch (_: Throwable) {
            // Last OEM fallback: surface the dedicated alarm Activity and let
            // it own the signal if the foreground service cannot be started.
            try {
                context.startActivity(
                    Intent(context, AlarmActivity::class.java).apply {
                        putExtras(intent)
                        putExtra("standaloneSignal", true)
                        addFlags(
                            Intent.FLAG_ACTIVITY_NEW_TASK or
                                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                                Intent.FLAG_ACTIVITY_SINGLE_TOP
                        )
                    }
                )
            } catch (_: Throwable) {}
        }
    }
}

class GuardAlarmService : Service() {
    companion object {
        const val ACTION_RING = "__PACKAGE__.action.GUARD_ALARM_RING"
        const val ACTION_STOP = "__PACKAGE__.action.GUARD_ALARM_STOP"
        const val ACTION_SNOOZE = "__PACKAGE__.action.GUARD_ALARM_SNOOZE"
        const val ACTION_DISMISS = "__PACKAGE__.action.GUARD_ALARM_DISMISS"

        private const val CHANNEL_ID = "gardeflow_guard_alarm_fsi_v1"
        private const val NOTIFICATION_ID = 0x4752464

        fun startRinging(context: Context, source: Intent) {
            val serviceIntent = Intent(context, GuardAlarmService::class.java).apply {
                action = ACTION_RING
                putExtras(source)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
        }

        fun dismissCurrent(context: Context, alarmId: Int) {
            val intent = Intent(context, GuardAlarmService::class.java).apply {
                action = ACTION_DISMISS
                putExtra("alarmId", alarmId)
            }
            try {
                context.startService(intent)
            } catch (_: Throwable) {
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        context.startForegroundService(intent)
                    }
                } catch (_: Throwable) {}
            }
        }
    }

    private var currentAlarmId = -1
    private var currentTitle = "Garde à venir"
    private var currentBody = ""
    private var currentPayload = ""
    private var currentVibration = true
    private var wakeLock: PowerManager.WakeLock? = null
    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createAlarmChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action ?: ACTION_RING) {
            ACTION_STOP -> {
                val id = intent?.getIntExtra("alarmId", currentAlarmId)
                    ?: currentAlarmId
                GuardAlarmScheduler.cancel(this, id, true)
                stopRingingAndSelf()
                return START_NOT_STICKY
            }

            ACTION_SNOOZE -> {
                val id = intent?.getIntExtra("alarmId", currentAlarmId)
                    ?: currentAlarmId
                val title = intent?.getStringExtra("alarmTitle") ?: currentTitle
                val body = intent?.getStringExtra("alarmBody") ?: currentBody
                val payload =
                    intent?.getStringExtra("alarmPayload") ?: currentPayload
                val vibration =
                    intent?.getBooleanExtra("vibration", currentVibration)
                        ?: currentVibration
                GuardAlarmScheduler.schedule(
                    this,
                    id,
                    System.currentTimeMillis() + 9L * 60L * 1000L,
                    title,
                    body,
                    vibration,
                    payload,
                    true
                )
                stopRingingAndSelf()
                return START_NOT_STICKY
            }

            ACTION_DISMISS -> {
                stopRingingAndSelf()
                return START_NOT_STICKY
            }

            else -> {
                if (intent == null) {
                    stopRingingAndSelf()
                    return START_NOT_STICKY
                }
                return try {
                    beginRinging(intent)
                    START_REDELIVER_INTENT
                } catch (_: Throwable) {
                    // If Android/OEM rejects a foreground-service detail,
                    // preserve the old Activity-owned alarm as the final path.
                    try {
                        startActivity(
                            Intent(this, AlarmActivity::class.java).apply {
                                putExtras(intent)
                                putExtra("standaloneSignal", true)
                                addFlags(
                                    Intent.FLAG_ACTIVITY_NEW_TASK or
                                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                                )
                            }
                        )
                    } catch (_: Throwable) {}
                    stopSelf()
                    START_NOT_STICKY
                }
            }
        }
    }

    override fun onDestroy() {
        stopSignal()
        releaseWakeLock()
        super.onDestroy()
    }

    private fun beginRinging(source: Intent) {
        val id = source.getIntExtra("alarmId", -1)
        if (id <= 0) {
            stopRingingAndSelf()
            return
        }

        if (currentAlarmId != -1 && currentAlarmId != id) {
            stopSignal()
            releaseWakeLock()
        }

        currentAlarmId = id
        currentTitle = source.getStringExtra("alarmTitle")
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?: "Garde à venir"
        currentBody = source.getStringExtra("alarmBody")?.trim().orEmpty()
        currentPayload = source.getStringExtra("alarmPayload").orEmpty()
        currentVibration = source.getBooleanExtra("vibration", true)

        GuardAlarmScheduler.removePersisted(this, currentAlarmId)
        acquireWakeLock()

        val notification = buildAlarmNotification()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        if (mediaPlayer == null) startSignal()

        // Same aggressive alarm-clock behavior when Android permits a direct
        // background Activity start. On newer Android versions this may be
        // blocked; the full-screen intent remains the official guaranteed path.
        try {
            startActivity(alarmActivityIntent())
        } catch (_: Throwable) {}
    }

    private fun buildAlarmNotification(): Notification {
        val fullScreenPending = PendingIntent.getActivity(
            this,
            currentAlarmId,
            alarmActivityIntent(),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val snooze = PendingIntent.getService(
            this,
            currentAlarmId xor 0x22000000,
            commandIntent(ACTION_SNOOZE),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val stop = PendingIntent.getService(
            this,
            currentAlarmId xor 0x33000000,
            commandIntent(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setSmallIcon(R.drawable.ic_stat_huim6)
            .setContentTitle(currentTitle)
            .setContentText(
                currentBody.ifBlank { "Garde à venir · action requise" }
            )
            .setCategory(Notification.CATEGORY_ALARM)
            .setPriority(Notification.PRIORITY_MAX)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(fullScreenPending)
            .setFullScreenIntent(fullScreenPending, true)
            .addAction(
                Notification.Action.Builder(0, "Rappel 9 min", snooze).build()
            )
            .addAction(
                Notification.Action.Builder(0, "Arrêter", stop).build()
            )
            .build()
    }

    private fun alarmActivityIntent(): Intent =
        Intent(this, AlarmActivity::class.java).apply {
            putExtra("alarmId", currentAlarmId)
            putExtra("alarmTitle", currentTitle)
            putExtra("alarmBody", currentBody)
            putExtra("alarmPayload", currentPayload)
            putExtra("vibration", currentVibration)
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            )
        }

    private fun commandIntent(actionName: String): Intent =
        Intent(this, GuardAlarmService::class.java).apply {
            action = actionName
            putExtra("alarmId", currentAlarmId)
            putExtra("alarmTitle", currentTitle)
            putExtra("alarmBody", currentBody)
            putExtra("alarmPayload", currentPayload)
            putExtra("vibration", currentVibration)
        }

    private fun createAlarmChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager =
            getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Alarmes de garde GardeFlow",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Alarmes plein écran avant les gardes validées"
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            setSound(null, null)
            enableVibration(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        try {
            val power =
                getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = power.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "$packageName:GardeFlowGuardAlarm"
            ).apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (_: Throwable) {
            wakeLock = null
        }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Throwable) {}
        wakeLock = null
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
                        .setContentType(
                            AudioAttributes.CONTENT_TYPE_SONIFICATION
                        )
                        .build()
                )
                setDataSource(this@GuardAlarmService, alarmUri)
                isLooping = true
                prepare()
                start()
            }
        } catch (_: Throwable) {
            mediaPlayer = null
        }

        if (!currentVibration) return
        try {
            vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                getSystemService(VibratorManager::class.java)?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            }
            val pattern = longArrayOf(0, 700, 350, 700, 350)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(
                    VibrationEffect.createWaveform(pattern, 0)
                )
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

    private fun stopRingingAndSelf() {
        stopSignal()
        releaseWakeLock()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }
}

'''.replace("__PACKAGE__", package_name)

scheduler_marker = "object GuardAlarmScheduler {"
if scheduler_marker not in text:
    raise SystemExit("GardeFlow alarm hardening: scheduler marker missing")
text = text.replace(scheduler_marker, service_code + scheduler_marker, 1)

# Android 14+ may deny exact-alarm access on a fresh install. Never silently
# drop a user's guard reminder: exact setAlarmClock when allowed, otherwise a
# RTC_WAKEUP setAndAllowWhileIdle fallback.
exact_guard = (
    "        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && "
    "!manager.canScheduleExactAlarms()) return false\n"
)
text = replace_once(text, exact_guard, "", "exact-alarm guard")

exact_call = (
    "            manager.setAlarmClock("
    "AlarmManager.AlarmClockInfo(triggerAtMillis, operation), operation)\n"
)
fallback_call = """            if (
                Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
                manager.canScheduleExactAlarms()
            ) {
                manager.setAlarmClock(
                    AlarmManager.AlarmClockInfo(
                        triggerAtMillis,
                        showAlarmPendingIntent(context, id)
                    ),
                    operation
                )
            } else {
                manager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerAtMillis,
                    operation
                )
            }
"""
text = replace_once(text, exact_call, fallback_call, "setAlarmClock call")

restore_guard = "        if (!canScheduleExact(context)) return\n"
text = replace_once(
    text,
    restore_guard,
    "        // Restore exact alarms or the inexact wake-up fallback.\n",
    "restore exact guard",
)

old_cancel = """        val intent = Intent(context, AlarmActivity::class.java).apply {
            action = "__PACKAGE__.GUARD_ALARM.$id"
        }
        val pending = PendingIntent.getActivity(
""".replace("__PACKAGE__", package_name)
new_cancel = """        val intent = Intent(
            context,
            GuardAlarmTriggerReceiver::class.java
        ).apply {
            action = "__PACKAGE__.GUARD_ALARM.$id"
        }
        val pending = PendingIntent.getBroadcast(
""".replace("__PACKAGE__", package_name)
text = replace_once(text, old_cancel, new_cancel, "scheduler cancellation")

old_operation = """        val intent = Intent(context, AlarmActivity::class.java).apply {
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
""".replace("__PACKAGE__", package_name)
new_operation = """        val intent = Intent(
            context,
            GuardAlarmTriggerReceiver::class.java
        ).apply {
            action = "__PACKAGE__.GUARD_ALARM.$id"
            putExtra("alarmId", id)
            putExtra("alarmTitle", title)
            putExtra("alarmBody", body)
            putExtra("alarmPayload", payload)
            putExtra("vibration", vibration)
        }
        return PendingIntent.getBroadcast(
""".replace("__PACKAGE__", package_name)
text = replace_once(text, old_operation, new_operation, "alarm PendingIntent")

show_intent = """
    private fun showAlarmPendingIntent(
        context: Context,
        id: Int
    ): PendingIntent {
        return PendingIntent.getActivity(
            context,
            id xor 0x11000000,
            Intent(context, MainActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP
                )
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
"""
boot_marker = "\n}\n\nclass GuardAlarmBootReceiver"
if boot_marker not in text:
    raise SystemExit("GardeFlow alarm hardening: scheduler end marker missing")
text = text.replace(
    boot_marker,
    show_intent + "\n}\n\nclass GuardAlarmBootReceiver",
    1,
)

# The settings-screen test must exercise the real foreground-service path,
# not just open the Activity.
old_test = """                "openAlarmActivity" -> {
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
"""
new_test = """                "openAlarmActivity" -> {
                    val alarmId = call.argument<Int>("alarmId") ?: -1
                    val title = call.argument<String>("alarmTitle")
                        ?: "Test alarme de garde"
                    val body = call.argument<String>("alarmBody").orEmpty()
                    val vibration = call.argument<Boolean>("vibration") ?: true
                    val ringIntent = Intent(
                        this,
                        GuardAlarmTriggerReceiver::class.java
                    ).apply {
                        putExtra("alarmId", alarmId)
                        putExtra("alarmTitle", title)
                        putExtra("alarmBody", body)
                        putExtra("alarmPayload", "guard:test")
                        putExtra("vibration", vibration)
                    }
                    GuardAlarmService.startRinging(this, ringIntent)
                    startActivity(
                        Intent(this, AlarmActivity::class.java).apply {
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
                        }
                    )
                    result.success(true)
                }
"""
main_text = replace_once(
    main_text,
    old_test,
    new_test,
    "MainActivity alarm test",
)

alarm_path.write_text(text, encoding="utf-8")
main_path.write_text(main_text, encoding="utf-8")

# Android 14+ requires a foreground service type. `specialUse` has no runtime
# prerequisite and this subtype is explicit for Play review.
tree = ET.parse(manifest_path)
root = tree.getroot()
application = root.find("application")
if application is None:
    raise SystemExit("GardeFlow alarm hardening: <application> missing")

permission = "android.permission.FOREGROUND_SERVICE_SPECIAL_USE"
if not any(
    node.get(A("name")) == permission
    for node in root.findall("uses-permission")
):
    root.insert(0, ET.Element("uses-permission", {A("name"): permission}))

for receiver in list(application.findall("receiver")):
    name = receiver.get(A("name"), "")
    if name in {
        ".GuardAlarmTriggerReceiver",
        f"{package_name}.GuardAlarmTriggerReceiver",
    }:
        application.remove(receiver)
application.append(
    ET.Element(
        "receiver",
        {
            A("name"): ".GuardAlarmTriggerReceiver",
            A("enabled"): "true",
            A("exported"): "false",
        },
    )
)

for service in list(application.findall("service")):
    name = service.get(A("name"), "")
    if name in {
        ".GuardAlarmService",
        f"{package_name}.GuardAlarmService",
    }:
        application.remove(service)

service = ET.Element(
    "service",
    {
        A("name"): ".GuardAlarmService",
        A("enabled"): "true",
        A("exported"): "false",
        A("stopWithTask"): "false",
        A("foregroundServiceType"): "specialUse",
    },
)
ET.SubElement(
    service,
    "property",
    {
        A("name"): "android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE",
        A("value"):
            "Rings user-configured medical duty alarms until stop or snooze",
    },
)
application.append(service)

tree.write(manifest_path, encoding="utf-8", xml_declaration=True)

# Fail CI immediately if a future refactor removes a required alarm layer.
required_kotlin = [
    "class GuardAlarmTriggerReceiver",
    "class GuardAlarmService : Service()",
    "PowerManager.PARTIAL_WAKE_LOCK",
    "setFullScreenIntent(fullScreenPending, true)",
    "Notification.CATEGORY_ALARM",
    "startForeground(",
    "setAlarmClock(",
    "setAndAllowWhileIdle(",
    "PendingIntent.getBroadcast(",
]
generated = alarm_path.read_text(encoding="utf-8")
missing = [marker for marker in required_kotlin if marker not in generated]
if missing:
    raise SystemExit(
        "GardeFlow alarm hardening: generated bridge incomplete: "
        + ", ".join(missing)
    )

print(f"Hardened GardeFlow alarm-clock architecture in {alarm_path}")
