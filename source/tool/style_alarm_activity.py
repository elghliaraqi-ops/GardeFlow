"""Presentation-only refinement after the existing AlarmActivity installer.
Intents, alarm ID, snooze duration, actions and receiver are not changed.
"""
from pathlib import Path
p = next(Path('android/app/src/main/kotlin').rglob('AlarmActivity.kt'))
s = p.read_text()
replacements = {
    'import android.widget.Space': 'import android.widget.Space\nimport android.widget.ScrollView',
    'Color.rgb(78, 190, 255)': 'Color.rgb(27, 46, 39)',
    'Color.rgb(4, 119, 226)': 'Color.rgb(27, 46, 39)',
    'Color.rgb(4, 15, 34)': 'Color.rgb(19, 29, 40)',
    'Color.rgb(15, 55, 103)': 'Color.rgb(19, 29, 40)',
    'text = "GardeFlow"': 'text = ""',
    'textSize = 18f\n            setTextColor(Color.WHITE)': 'textSize = 0f\n            setTextColor(Color.WHITE)',
    'text = "✦   ☾   ·   ✦"': 'text = "☾"',
    'text = shiftKind': 'text = if (is24h) "GARDE DE 24 HEURES" else "GARDE DE $shiftKind"',
    'textSize = 62f': 'textSize = 28f',
    'textSize = if (is24h) 48f else 60f': 'textSize = if (is24h) 40f else 44f',
    'setPadding(dp(28), dp(42), dp(28), dp(28))': 'setPadding(dp(24), dp(24), dp(24), dp(24))',
    'label = "Rappel dans…"': 'label = "Rappel dans 9 min"',
    'label = "Fermer"': 'label = "Arrêter"',
    'dp(62)': 'ViewGroup.LayoutParams.WRAP_CONTENT',
    'textSize = 16f': 'textSize = 18f\n            minHeight = dp(64)',
    'setContentView(root)': '''val scroll = ScrollView(this).apply {
            isFillViewport = true
            addView(root, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        }
        setContentView(scroll)''',
}
for old, new in replacements.items():
    if old not in s:
        if old == 'text = "✦   ☾   ·   ✦"':
            continue  # Existing code uses a when expression for this value.
        raise SystemExit(f'Alarm UI anchor missing: {old}')
    s = s.replace(old, new)
s = s.replace('"✦   ☾   ·   ✦"', '"☾"')
# Reclaim the old branding header so both actions stay within easy reach.
brand_start = s.index('        val brand = TextView(this)')
sky_start = s.index('        val sky = TextView(this)', brand_start)
s = s[:brand_start] + s[sky_start:]
# The time is extracted from the existing reminder body, never invented.
anchor = '        if (body.isNotEmpty()) {'
time = '''        val startTime = Regex("\\\\b(?:[01]?\\\\d|2[0-3]):[0-5]\\\\d\\\\b").find(body)?.value
        if (startTime != null) {
            val clock = TextView(this).apply {
                text = startTime
                textSize = 52f
                setTextColor(Color.WHITE)
                typeface = Typeface.DEFAULT_BOLD
                gravity = Gravity.CENTER
            }
            root.addView(clock, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        }
'''
if anchor not in s:
    raise SystemExit('Alarm body anchor missing')
s = s.replace(anchor, time + anchor, 1)
p.write_text(s)
print('Alarm visual layout updated; receiver and action methods preserved.')
