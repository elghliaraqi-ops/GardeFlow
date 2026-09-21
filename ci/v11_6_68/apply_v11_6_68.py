from pathlib import Path
import re

def replace_once(path, old, new, label):
    p = Path(path)
    s = p.read_text()
    if old not in s:
        raise SystemExit(f"V11.6.68: {label} anchor missing in {path}")
    p.write_text(s.replace(old, new, 1))
    print(f"V11.6.68: {label} applied")

replace_once(
    "pubspec.yaml",
    "version: 11.6.67+227",
    "version: 11.6.68+228",
    "version bump",
)

# Multi-account hardening: the current device token must be detached from
# the signed-in account before the Supabase session disappears.
p = Path("lib/state/app_state.dart")
s = p.read_text()
marker = "// V11.6.68 account-isolation cleanup"
if marker not in s:
    match = re.search(r"(?m)^(\s*)Future<void>\s+logout\s*\(\s*\)\s+async\s*\{\s*$", s)
    if not match:
        raise SystemExit("V11.6.68: AppState logout() async method not found")
    indent = match.group(1) + "  "
    block = (
        "\n"
        f"{indent}{marker}\n"
        f"{indent}if (backendEnabled && currentUser != null) {{\n"
        f"{indent}  try {{\n"
        f"{indent}    await PushNotificationService.instance.unregisterCurrentDevice();\n"
        f"{indent}  }} catch (_) {{}}\n"
        f"{indent}}}\n"
        f"{indent}try {{\n"
        f"{indent}  await NotificationService.instance.cancelAll();\n"
        f"{indent}}} catch (_) {{}}\n"
        f"{indent}_dismissedNotificationKeys.clear();\n"
        f"{indent}_reminders.clear();\n"
        f"{indent}await _persistNow();\n"
    )
    s = s[:match.end()] + block + s[match.end():]
    p.write_text(s)
    print("V11.6.68: logout FCM/local-notification isolation applied")
else:
    print("V11.6.68: logout isolation already present")

# PDF import safety: an ambiguous cell must never create several guards.
p = Path("lib/services/official_roster_import_service.dart")
s = p.read_text()
old = """        if (matched.isEmpty) {
          unmatched.add({
            'date': dateStr,
            'shift_id': cell.shiftId,
            'text': cell.text,
          });
          continue;
        }
        for (final profile in matched) {
          rawAssignments.add(OfficialRosterAssignment(
            profileId: profile.id,
            dateStr: dateStr,
            shiftId: cell.shiftId,
          ));
        }
"""
new = """        if (matched.length != 1) {
          unmatched.add({
            'date': dateStr,
            'shift_id': cell.shiftId,
            'text': cell.text,
            'reason': matched.isEmpty ? 'no_match' : 'ambiguous_match',
            if (matched.length > 1)
              'candidate_profile_ids': matched.map((p) => p.id).toList(),
          });
          continue;
        }
        final profile = matched.single;
        rawAssignments.add(OfficialRosterAssignment(
          profileId: profile.id,
          dateStr: dateStr,
          shiftId: cell.shiftId,
        ));
"""
if old not in s:
    raise SystemExit("V11.6.68: official PDF match loop anchor missing")
p.write_text(s.replace(old, new, 1))
print("V11.6.68: ambiguous PDF doctor matching blocked")

checks = {
    "pubspec.yaml": ["version: 11.6.68+228"],
    "lib/state/app_state.dart": [
        "V11.6.68 account-isolation cleanup",
        "await PushNotificationService.instance.unregisterCurrentDevice();",
        "_dismissedNotificationKeys.clear();",
    ],
    "lib/services/official_roster_import_service.dart": [
        "matched.length != 1",
        "'ambiguous_match'",
        "matched.single",
    ],
}
for file_name, needles in checks.items():
    text = Path(file_name).read_text()
    for needle in needles:
        if needle not in text:
            raise SystemExit(
                f"V11.6.68 validation failed: {needle!r} missing in {file_name}"
            )

print("GardeFlow V11.6.68 P0/P1 client hardening applied successfully")
