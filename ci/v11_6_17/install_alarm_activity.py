from pathlib import Path
import re
import xml.etree.ElementTree as ET

ANDROID_NS = "http://schemas.android.com/apk/res/android"
A = lambda name: f"{{{ANDROID_NS}}}{name}"
ET.register_namespace("android", ANDROID_NS)

manifest_path = Path("android/app/src/main/AndroidManifest.xml")
if not manifest_path.exists():
    raise SystemExit("V11.6.17 AlarmActivity: AndroidManifest.xml missing")

main_candidates = list(Path("android/app/src/main/kotlin").rglob("MainActivity.kt"))
if not main_candidates:
    raise SystemExit("V11.6.17 AlarmActivity: MainActivity.kt missing")

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

        window.statusBarColor = Color.rgb(246, 248, 252)
        window.navigationBarColor = Color.WHITE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {{
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility =
                window.decorView.systemUiVisibility or View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
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

        val screenBackground = Color.rgb(246, 248, 252)
        val primary = Color.rgb(37, 99, 235)
        val primaryDark = Color.rgb(30, 64, 175)
        val ink = Color.rgb(15, 23, 42)
        val muted = Color.rgb(100, 116, 139)
        val softBlue = Color.rgb(231, 238, 255)

        val root = LinearLayout(this).apply {{
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(28), dp(48), dp(28), dp(30))
            setBackgroundColor(screenBackground)
        }}

        val badge = TextView(this).apply {{
            text = "GARDEFLOW • ALARME"
            textSize = 13f
            setTextColor(primaryDark)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            background = roundedDrawable(softBlue, 999f)
            setPadding(dp(18), dp(9), dp(18), dp(9))
        }}
        root.addView(
            badge,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )

        root.addView(Space(this), LinearLayout.LayoutParams(1, dp(44)))

        val alarmType = TextView(this).apply {{
            text = title.uppercase()
            textSize = 34f
            setTextColor(ink)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setLineSpacing(0f, 1.05f)
        }}
        root.addView(
            alarmType,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )

        root.addView(Space(this), LinearLayout.LayoutParams(1, dp(22)))

        val time = TextView(this).apply {{
            text = if (body.isNotEmpty()) body else "Rappel de garde"
            textSize = if (body.length <= 24) 30f else 24f
            setTextColor(primaryDark)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setLineSpacing(dp(4).toFloat(), 1.08f)
        }}
        root.addView(
            time,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )

        root.addView(Space(this), LinearLayout.LayoutParams(1, 0, 1f))

        val helper = TextView(this).apply {{
            text = "Votre garde commence bientôt"
            textSize = 15f
            setTextColor(muted)
            gravity = Gravity.CENTER
        }}
        root.addView(
            helper,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )

        root.addView(Space(this), LinearLayout.LayoutParams(1, dp(22)))

        val buttons = LinearLayout(this).apply {{
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }}

        if (snoozeAvailable) {{
            val snooze = actionButton(
                label = "RAPPEL",
                fill = softBlue,
                textColor = primaryDark
            ) {{
                resolveAlarm(AlarmReceiver.ACTION_ALARM_SNOOZE)
            }}
            buttons.addView(
                snooze,
                LinearLayout.LayoutParams(0, dp(60), 1f).apply {{
                    marginEnd = dp(10)
                }}
            )
        }}

        val stop = actionButton(
            label = "FERMER",
            fill = primary,
            textColor = Color.WHITE
        ) {{
            resolveAlarm(AlarmReceiver.ACTION_ALARM_STOP)
        }}
        buttons.addView(
            stop,
            LinearLayout.LayoutParams(0, dp(60), 1f).apply {{
                if (snoozeAvailable) marginStart = dp(10)
            }}
        )

        root.addView(
            buttons,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
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
            background = roundedDrawable(fill, 20f)
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
    raise SystemExit("V11.6.17 AlarmActivity: <application> missing")

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

print(f"Installed native AlarmActivity at {alarm_activity_path}")
print("Registered dedicated RING activity with lock-screen display")
