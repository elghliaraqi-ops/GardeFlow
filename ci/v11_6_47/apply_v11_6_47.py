from pathlib import Path
import subprocess

EXPECTED = "version: 11.6.46+206"
TARGET = "version: 11.6.47+207"

pubspec = Path("pubspec.yaml")
if EXPECTED not in pubspec.read_text():
    raise SystemExit("V11.6.47: base version mismatch")

here = Path(__file__).resolve().parent
overlay_parts = sorted(here.glob("overlay.part*"))
if not overlay_parts:
    raise SystemExit("V11.6.47: overlay parts missing")

overlay = Path("/tmp/gardeflow_v11_6_47.patch")
overlay.write_bytes(b"".join(part.read_bytes() for part in overlay_parts))
subprocess.run(
    ["patch", "-p1", "--batch", "--forward", "-i", str(overlay)],
    check=True,
)

sql_parts = sorted(here.glob("sql.part*"))
if not sql_parts:
    raise SystemExit("V11.6.47: SQL migration parts missing")
sql = "".join(part.read_text() for part in sql_parts)
Path("supabase/patch_v11_6_47_disciplinary_guards.sql").write_text(sql)

pub = pubspec.read_text()
if TARGET not in pub:
    raise SystemExit("V11.6.47: target version not applied")

checks = {
    "lib/models/planning_entry.dart": ["isDisciplinary"],
    "lib/services/supabase_backend_service.dart": ["is_disciplinary"],
    "lib/services/official_roster_import_service.dart": [
        "is_disciplinary",
        "_extractRedText",
        "page.render",
        "redText",
    ],
    "lib/state/app_state.dart": [
        "garde disciplinaire",
        "!e.isDisciplinary",
    ],
    "lib/screens/home_screen.dart": [
        "isDisciplinary",
        "suppression admin uniquement",
    ],
    "supabase/patch_v11_6_47_disciplinary_guards.sql": [
        "protect_disciplinary_guard",
        "reject_disciplinary_exchange_request",
        "v11.6.47-r1",
    ],
}
for file_name, needles in checks.items():
    text = Path(file_name).read_text()
    for needle in needles:
        if needle not in text:
            raise SystemExit(f"V11.6.47: missing {needle!r} in {file_name}")

print("GardeFlow V11.6.47: disciplinary PDF red-name detection + locked guards")
