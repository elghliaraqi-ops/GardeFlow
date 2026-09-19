from pathlib import Path

EXPECTED = "version: 11.6.47+207"
TARGET = "version: 11.6.48+208"

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.48: base version mismatch")
pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

source_sql = Path(__file__).resolve().parent / "auto_validate_plannings.sql"
if not source_sql.exists():
    raise SystemExit("V11.6.48: SQL migration source missing")

target_sql = Path("supabase/patch_v11_6_48_auto_validate_plannings.sql")
target_sql.write_text(source_sql.read_text())

required = [
    "planning_auto_validation_events",
    "process_due_planning_auto_validations",
    "interval '7 days'",
    "gardeflow-auto-validate-plannings",
]
text_sql = target_sql.read_text()
for needle in required:
    if needle not in text_sql:
        raise SystemExit(f"V11.6.48: missing {needle!r}")

print("GardeFlow V11.6.48: automatic planning validation 7 days after official PDF + push notification backend")
