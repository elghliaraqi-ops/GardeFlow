from pathlib import Path

# This script runs after install_system_alarm_bridge.py and hardens the generated
# AlarmActivity/GuardAlarmScheduler without duplicating the large Kotlin template.
# Android 14+ may deny SCHEDULE_EXACT_ALARM by default. In that case GardeFlow
# must still arm an inexact wake-up alarm instead of silently dropping it.

candidates = list(Path("android/app/src/main/kotlin").rglob("AlarmActivity.kt"))
if not candidates:
    raise SystemExit("GardeFlow alarm fallback: AlarmActivity.kt missing")

path = candidates[0]
text = path.read_text(encoding="utf-8")

exact_guard = (
    "        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && "
    "!manager.canScheduleExactAlarms()) return false\n"
)
if exact_guard not in text:
    raise SystemExit("GardeFlow alarm fallback: exact-permission guard not found")
text = text.replace(exact_guard, "", 1)

exact_call = (
    "            manager.setAlarmClock(AlarmManager.AlarmClockInfo(triggerAtMillis, operation), operation)\n"
)
fallback_call = """            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || manager.canScheduleExactAlarms()) {
                manager.setAlarmClock(
                    AlarmManager.AlarmClockInfo(triggerAtMillis, operation),
                    operation
                )
            } else {
                // Android 14+ can deny SCHEDULE_EXACT_ALARM on fresh installs.
                // Keep a real wake-up path instead of losing the reminder.
                manager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerAtMillis,
                    operation
                )
            }
"""
if exact_call not in text:
    raise SystemExit("GardeFlow alarm fallback: setAlarmClock call not found")
text = text.replace(exact_call, fallback_call, 1)

restore_guard = "        if (!canScheduleExact(context)) return\n"
if restore_guard not in text:
    raise SystemExit("GardeFlow alarm fallback: restore exact guard not found")
text = text.replace(
    restore_guard,
    "        // Restore exact alarms when allowed, otherwise restore the inexact wake-up fallback.\n",
    1,
)

path.write_text(text, encoding="utf-8")
print(f"Hardened Android alarm fallback in {path}")
