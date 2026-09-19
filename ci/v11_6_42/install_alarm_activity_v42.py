from pathlib import Path
import re
import xml.etree.ElementTree as ET

ANDROID_NS = "http://schemas.android.com/apk/res/android"
A = lambda name: f"{{{ANDROID_NS}}}{name}"
ET.register_namespace("android", ANDROID_NS)

manifest_path = Path("android/app/src/main/AndroidManifest.xml")
if not manifest_path.exists():
    raise SystemExit("V11.6.42 AlarmActivity: AndroidManifest.xml missing")

main_candidates = list(Path("android/app/src/main/kotlin").rglob("MainActivity.kt"))
if not main_candidates:
    raise SystemExit("V11.6.42 AlarmActivity: MainActivity.kt missing")

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
import android.widget.TextView
import com.gdelataillade.alarm.alarm.AlarmReceiver

class AlarmActivity : Activity() {{
    private var alarmId: Int = -1

    override fun onCreate(savedInstanceState: Bundle?) {{
        super.onCreate(savedInstanceState)

        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        val fullScreenEnabled = prefs.getBoolean("flutter.guard_fullscreen_alarm", true)
        if (!fullScreenEnabled) {{
            finish()
            return
        }}

        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
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
        renderAlarm()
    }}

    private fun renderAlarm() {{
        val title = intent.getStringExtra("alarmTitle")
            ?.trim()
            ?.takeIf {{ it.isNotEmpty() }}
            ?: "GARDE"

        val body = intent.getStringExtra("alarmBody")
            ?.trim()
            .orEmpty()

        val snoozeAvailable =
            !intent.getStringExtra("alarmSnoozeLabel").isNullOrBlank()

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

        val dayTop = Color.rgb(78, 190, 255)
        val dayBottom = Color.rgb(4, 119, 226)
        val nightTop = Color.rgb(4, 15, 34)
        val nightBottom = Color.rgb(15, 55, 103)

        val colors = when {{
            is24h -> intArrayOf(dayTop, dayBottom, nightTop, nightBottom)
            isNight -> intArrayOf(nightTop, nightBottom)
            else -> intArrayOf(dayTop, dayBottom)
        }}

        window.statusBarColor = colors.first()
        window.navigationBarColor = colors.last()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {{
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = 0
        }}

        val root = LinearLayout(this).apply {{
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(28), dp(42), dp(28), dp(28))
            background = GradientDrawable(
                GradientDrawable.Orientation.TL_BR,
                colors
            )
        }}

        val brand = TextView(this).apply {{
            text = "GardeFlow"
            textSize = 18f
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
        }}
        root.addView(
            brand,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )

        root.addView(Space(this), LinearLayout.LayoutParams(1, dp(24)))

        val sky = TextView(this).apply {{
            text = when {{
                is24h -> "☀     ☾"
                isNight -> "✦   ☾   ·   ✦"
                else -> "☀"
            }}
            textSize = if (is24h) 48f else 60f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            alpha = 0.96f
        }}
        root.addView(
            sky,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )

        root.addView(Space(this), LinearLayout.LayoutParams(1, dp(22)))

        val categoryView = TextView(this).apply {{
            text = category
            textSize = 24f
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            letterSpacing = 0.04f
        }}
        root.addView(
            categoryView,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )

        val shiftView = TextView(this).apply {{
            text = shiftKind
            textSize = 62f
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setLineSpacing(0f, 1.0f)
        }}
        root.addView(
            shiftView,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )

        if (body.isNotEmpty()) {{
            root.addView(Space(this), LinearLayout.LayoutParams(1, dp(12)))
            val details = TextView(this).apply {{
                text = body
                textSize = if (body.length <= 36) 22f else 18f
                setTextColor(Color.WHITE)
                typeface = Typeface.DEFAULT_BOLD
                gravity = Gravity.CENTER
                setLineSpacing(dp(4).toFloat(), 1.08f)
                alpha = 0.94f
            }}
            root.addView(
                details,
                LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT
                )
            )
        }}

        root.addView(Space(this), LinearLayout.LayoutParams(1, 0, 1f))

        if (snoozeAvailable) {{
            val snooze = actionButton(
                label = "Rappel dans…",
                fill = Color.argb(235, 255, 255, 255),
                textColor = Color.rgb(15, 47, 83)
            ) {{
                resolveAlarm(AlarmReceiver.ACTION_ALARM_SNOOZE)
            }}
            root.addView(
                snooze,
                LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    dp(62)
                )
            )
            root.addView(Space(this), LinearLayout.LayoutParams(1, dp(11)))
        }}

        val stop = actionButton(
            label = "Fermer",
            fill = Color.argb(48, 255, 255, 255),
            textColor = Color.WHITE
        ) {{
            resolveAlarm(AlarmReceiver.ACTION_ALARM_STOP)
        }}
        root.addView(
            stop,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(62)
            )
        )

        setContentView(root)
    }}

    private fun resolveAlarm(actionName: String) {{
        if (alarmId > 0) {{
            sendBroadcast(
                Intent(this, AlarmReceiver::class.java).apply {{
                    action = actionName
                    putExtra("id", alarmId)
                }}
            )
        }}
        finishAndRemoveTask()
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
            background = roundedDrawable(fill, 22f)
            backgroundTintList = ColorStateList.valueOf(fill)
            stateListAnimator = null
            setOnClickListener {{ onClick() }}
        }}
    }}

    private fun roundedDrawable(color: Int, radiusDp: Float): GradientDrawable {{
        return GradientDrawable().apply {{
            shape = GradientDrawable.RECTANGLE
            setColor(color)
            cornerRadius = dp(radiusDp.toInt()).toFloat()
        }}
    }}

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()
}}
'''
alarm_activity_path.write_text(kotlin, encoding="utf-8")

tree = ET.parse(manifest_path)
root = tree.getroot()
application = root.find("application")
if application is None:
    raise SystemExit("V11.6.42 AlarmActivity: <application> missing")

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

tree.write(manifest_path, encoding="utf-8", xml_declaration=True)

print(f"Installed V11.6.42 dynamic AlarmActivity at {alarm_activity_path}")
print("Full-screen alarm follows the user preference and renders JOUR / NUIT / 24H")
