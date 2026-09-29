from pathlib import Path
import re
import xml.etree.ElementTree as ET

ANDROID_NS = "http://schemas.android.com/apk/res/android"
A = lambda name: f"{{{ANDROID_NS}}}{name}"
ET.register_namespace("android", ANDROID_NS)

manifest_path = Path("android/app/src/main/AndroidManifest.xml")
if not manifest_path.exists():
    raise SystemExit("V12 AlarmActivity: AndroidManifest.xml missing")

main_candidates = list(Path("android/app/src/main/kotlin").rglob("MainActivity.kt"))
if not main_candidates:
    raise SystemExit("V12 AlarmActivity: MainActivity.kt missing")

main_activity = main_candidates[0]
main_text = main_activity.read_text(encoding="utf-8")
match = re.search(r"^package\s+([\w.]+)", main_text, re.MULTILINE)
package_name = match.group(1) if match else "com.huim6.huim6_planning"
alarm_activity_path = main_activity.parent / "AlarmActivity.kt"

kotlin = f'''package {package_name}

import android.app.Activity
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.Space
import android.widget.TextClock
import android.widget.TextView
import com.gdelataillade.alarm.alarm.AlarmReceiver

class AlarmActivity : Activity() {{
    private var alarmId: Int = -1

    override fun onCreate(savedInstanceState: Bundle?) {{
        super.onCreate(savedInstanceState)

        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        val fullScreenEnabled = prefs.getBoolean("flutter.guard_fullscreen_alarm", true)
        val forceFullScreen = intent.getBooleanExtra("forceFullScreen", false)
        if (!forceFullScreen && !fullScreenEnabled) {{
            finish()
            return
        }}

        window.addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_ALLOW_LOCK_WHILE_SCREEN_ON
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {{
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }} else {{
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }}

        alarmId = intent.getIntExtra("alarmId", -1)
        enterImmersiveMode()
        renderAlarm()
    }}

    override fun onWindowFocusChanged(hasFocus: Boolean) {{
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) enterImmersiveMode()
    }}

    @Suppress("DEPRECATION")
    override fun onBackPressed() {{
        // Intentionally disabled: the user must STOP or SNOOZE the alarm.
    }}

    @Suppress("DEPRECATION")
    private fun enterImmersiveMode() {{
        window.decorView.systemUiVisibility =
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                View.SYSTEM_UI_FLAG_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE
    }}

    private fun renderAlarm() {{
        val title = intent.getStringExtra("alarmTitle")
            ?.trim()
            ?.takeIf {{ it.isNotEmpty() }}
            ?: "Garde à venir"
        val body = intent.getStringExtra("alarmBody")?.trim().orEmpty()
        val snoozeAvailable = !intent.getStringExtra("alarmSnoozeLabel").isNullOrBlank()

        val semantic = "$title $body"
            .lowercase()
            .replace("\\n", " ")
            .replace(Regex("\\\\s+"), " ")

        val is24h = semantic.contains("24h") ||
            semantic.contains("24 h") ||
            Regex("0?8[:h]?00.*0?8[:h]?00").containsMatchIn(semantic)
        val isNight = !is24h && (
            semantic.contains("nuit") ||
                Regex("20[:h]?00.*0?8[:h]?00").containsMatchIn(semantic)
            )
        val isUrgences = semantic.contains("urgence") || semantic.contains("urg-")

        val category = if (isUrgences) "URGENCES" else "SERVICE"
        val shiftKind = when {{
            is24h -> "24H"
            isNight -> "NUIT"
            else -> "JOUR"
        }}

        val dayTop = Color.rgb(66, 183, 255)
        val dayBottom = Color.rgb(0, 106, 214)
        val nightTop = Color.rgb(3, 11, 27)
        val nightBottom = Color.rgb(14, 47, 91)
        val colors = when {{
            is24h -> intArrayOf(dayTop, dayBottom, nightTop, nightBottom)
            isNight -> intArrayOf(nightTop, nightBottom)
            else -> intArrayOf(dayTop, dayBottom)
        }}

        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT

        val root = LinearLayout(this).apply {{
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(26), dp(34), dp(26), dp(26))
            background = GradientDrawable(
                GradientDrawable.Orientation.TL_BR,
                colors
            )
        }}

        root.addView(TextView(this).apply {{
            text = "GardeFlow"
            textSize = 18f
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            alpha = 0.96f
        }}, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ))

        root.addView(Space(this), LinearLayout.LayoutParams(1, dp(14)))

        root.addView(chip("ALARME DE GARDE"), LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            dp(34)
        ))

        root.addView(Space(this), LinearLayout.LayoutParams(1, dp(16)))

        root.addView(TextClock(this).apply {{
            format12Hour = "HH:mm"
            format24Hour = "HH:mm"
            textSize = 44f
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
        }}, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ))

        root.addView(Space(this), LinearLayout.LayoutParams(1, dp(14)))

        root.addView(TextView(this).apply {{
            text = when {{
                is24h -> "☀     ☾"
                isNight -> "✦   ☾   ·   ✦"
                else -> "☀"
            }}
            textSize = if (is24h) 42f else 52f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            alpha = 0.96f
        }}, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ))

        root.addView(Space(this), LinearLayout.LayoutParams(1, dp(16)))

        root.addView(TextView(this).apply {{
            text = category
            textSize = 22f
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            letterSpacing = 0.05f
        }}, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ))

        root.addView(TextView(this).apply {{
            text = shiftKind
            textSize = 64f
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
        }}, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ))

        root.addView(Space(this), LinearLayout.LayoutParams(1, dp(8)))

        root.addView(TextView(this).apply {{
            text = title
            textSize = if (title.length <= 30) 20f else 17f
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            alpha = 0.98f
        }}, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ))

        if (body.isNotEmpty()) {{
            root.addView(Space(this), LinearLayout.LayoutParams(1, dp(8)))
            root.addView(TextView(this).apply {{
                text = body
                textSize = if (body.length <= 60) 17f else 15f
                setTextColor(Color.WHITE)
                gravity = Gravity.CENTER
                alpha = 0.88f
                maxLines = 4
            }}, LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ))
        }}

        root.addView(Space(this), LinearLayout.LayoutParams(1, 0, 1f))

        root.addView(TextView(this).apply {{
            text = "La sonnerie reste active jusqu’à votre action."
            textSize = 12f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            alpha = 0.78f
        }}, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ))

        root.addView(Space(this), LinearLayout.LayoutParams(1, dp(12)))

        if (snoozeAvailable) {{
            root.addView(
                actionButton(
                    "RAPPEL 9 MIN",
                    Color.argb(238, 255, 255, 255),
                    Color.rgb(14, 44, 78)
                ) {{
                    resolveAlarm(AlarmReceiver.ACTION_ALARM_SNOOZE)
                }},
                LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    dp(62)
                )
            )
            root.addView(Space(this), LinearLayout.LayoutParams(1, dp(10)))
        }}

        root.addView(
            actionButton(
                "J’AI VU — ARRÊTER",
                Color.argb(48, 255, 255, 255),
                Color.WHITE
            ) {{
                resolveAlarm(AlarmReceiver.ACTION_ALARM_STOP)
            }},
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(62)
            )
        )

        setContentView(root)
    }}

    private fun resolveAlarm(actionName: String) {{
        if (alarmId > 0) {{
            sendBroadcast(Intent(this, AlarmReceiver::class.java).apply {{
                action = actionName
                putExtra("id", alarmId)
            }})
        }}
        finishAndRemoveTask()
    }}

    private fun chip(label: String): TextView {{
        return TextView(this).apply {{
            text = label
            textSize = 11f
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(dp(16), 0, dp(16), 0)
            letterSpacing = 0.08f
            background = GradientDrawable().apply {{
                shape = GradientDrawable.RECTANGLE
                setColor(Color.argb(40, 255, 255, 255))
                cornerRadius = dp(999).toFloat()
                setStroke(dp(1), Color.argb(70, 255, 255, 255))
            }}
        }}
    }}

    private fun actionButton(
        label: String,
        fill: Int,
        textColor: Int,
        onClick: () -> Unit
    ): Button {{
        return Button(this).apply {{
            text = label
            textSize = 16f
            setTextColor(textColor)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            isAllCaps = false
            background = GradientDrawable().apply {{
                shape = GradientDrawable.RECTANGLE
                setColor(fill)
                cornerRadius = dp(22).toFloat()
            }}
            backgroundTintList = ColorStateList.valueOf(fill)
            stateListAnimator = null
            setOnClickListener {{ onClick() }}
        }}
    }}

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()
}}
'''

alarm_activity_path.write_text(kotlin, encoding="utf-8")

# Le bouton de test Flutter doit ouvrir AlarmActivity directement lorsque
# GardeFlow est déjà au premier plan. Cela évite que le test soit réduit à une
# simple heads-up notification sur Android 14+.
bridge_channel = "gardeflow/fullscreen_alarm"
if bridge_channel not in main_text:
    import_block = '''import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel'''
    package_match = re.search(r"^package\s+[\w.]+\s*$", main_text, re.MULTILINE)
    if package_match is None:
        raise SystemExit("V12 AlarmActivity: package MainActivity introuvable")
    main_text = (
        main_text[: package_match.end()]
        + "\n\n"
        + import_block
        + main_text[package_match.end() :]
    )

    main_class = re.compile(
        r"class\s+MainActivity\s*:\s*FlutterActivity\(\)\s*\{?\s*\}?\s*$",
        re.MULTILINE,
    )
    replacement = f'''class MainActivity : FlutterActivity() {{
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {{
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "{bridge_channel}"
        ).setMethodCallHandler {{ call, result ->
            when (call.method) {{
                "openAlarmActivity" -> {{
                    val alarmId = call.argument<Int>("alarmId") ?: -1
                    val alarmTitle = call.argument<String>("alarmTitle")
                        ?: "Test alarme de garde"
                    val alarmBody = call.argument<String>("alarmBody").orEmpty()
                    val alarmSnoozeLabel = call.argument<String>("alarmSnoozeLabel")
                    val forceFullScreen = call.argument<Boolean>("forceFullScreen") ?: false

                    startActivity(Intent(this, AlarmActivity::class.java).apply {{
                        putExtra("alarmId", alarmId)
                        putExtra("alarmTitle", alarmTitle)
                        putExtra("alarmBody", alarmBody)
                        putExtra("alarmSnoozeLabel", alarmSnoozeLabel)
                        putExtra("forceFullScreen", forceFullScreen)
                        addFlags(
                            Intent.FLAG_ACTIVITY_NEW_TASK or
                                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                                Intent.FLAG_ACTIVITY_SINGLE_TOP
                        )
                    }})
                    result.success(true)
                }}
                else -> result.notImplemented()
            }}
        }}
    }}
}}
'''
    main_text, replacements = main_class.subn(replacement, main_text, count=1)
    if replacements != 1:
        raise SystemExit(
            "V12 AlarmActivity: structure MainActivity non reconnue pour le bridge plein écran"
        )
    main_activity.write_text(main_text, encoding="utf-8")

tree = ET.parse(manifest_path)
root = tree.getroot()
application = root.find("application")
if application is None:
    raise SystemExit("V12 AlarmActivity: <application> missing")

ring_action = "com.gdelataillade.alarm.action.RING"

for activity in list(application.findall("activity")):
    name = activity.get(A("name"), "")
    if name in {".AlarmActivity", f"{package_name}.AlarmActivity"}:
        application.remove(activity)
        continue

    for intent_filter in list(activity.findall("intent-filter")):
        actions = [
            node.get(A("name"), "")
            for node in intent_filter.findall("action")
        ]
        if ring_action in actions:
            activity.remove(intent_filter)

activity = ET.Element(
    "activity",
    {
        A("name"): ".AlarmActivity",
        A("exported"): "false",
        A("launchMode"): "singleInstance",
        A("taskAffinity"): f"{package_name}.alarm",
        A("excludeFromRecents"): "true",
        A("showWhenLocked"): "true",
        A("turnScreenOn"): "true",
        A("theme"): "@android:style/Theme.Material.Light.NoActionBar",
    },
)

intent_filter = ET.SubElement(activity, "intent-filter")
ET.SubElement(intent_filter, "action", {A("name"): ring_action})
ET.SubElement(
    intent_filter,
    "category",
    {A("name"): "android.intent.category.DEFAULT"},
)

application.append(activity)
tree.write(
    manifest_path,
    encoding="utf-8",
    xml_declaration=True,
)

print(f"Installed V12 foreground AlarmActivity at {alarm_activity_path}")
print(f"Installed direct Flutter bridge in {main_activity}")
