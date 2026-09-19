from pathlib import Path

EXPECTED = "version: 11.6.56+216"
TARGET = "version: 11.6.57+217"

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.57: base version mismatch")
pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

junior = Path("lib/screens/junior_oncall_screen.dart")
s = junior.read_text()

old_build = """  @override
  Widget build(BuildContext context) {
    final body = Column("""
new_build = """  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = Column("""
if old_build not in s:
    raise SystemExit("V11.6.57: Junior build anchor missing")
s = s.replace(old_build, new_build, 1)

s = s.replace(
"""      return ColoredBox(
        color: AppColors.paper,
        child: body,
      );""",
"""      return ColoredBox(
        color: theme.scaffoldBackgroundColor,
        child: body,
      );""",
1)

s = s.replace(
"""    return Scaffold(
      backgroundColor: AppColors.paper,""",
"""    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,""",
1)

if "dropdownColor: Colors.white," not in s:
    raise SystemExit("V11.6.57: Junior dropdown white anchor missing")
s = s.replace(
    "dropdownColor: Colors.white,",
    "dropdownColor: Theme.of(context).colorScheme.surface,",
    1,
)

old_local = """      result.add(_JuniorOnCallRow(
        dateStr: entry.dateStr,
        shiftId: entry.shiftId,
        ownerName: entry.ownerName,
        service: isUrgences ? 'Urgences' : user.service,
        hospital: user.hospital,
      ));"""
new_local = """      result.add(_JuniorOnCallRow(
        dateStr: entry.dateStr,
        shiftId: entry.shiftId,
        ownerName: entry.ownerName,
        ownerPhone: user.phone,
        service: isUrgences ? 'Urgences' : user.service,
        hospital: user.hospital,
      ));"""
if old_local not in s:
    raise SystemExit("V11.6.57: local Junior row anchor missing")
s = s.replace(old_local, new_local, 1)

old_imports = """import 'package:provider/provider.dart';"""
new_imports = """import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';"""
if old_imports not in s:
    raise SystemExit("V11.6.57: provider import anchor missing")
s = s.replace(old_imports, new_imports, 1)

old_fields = """  final String shiftId;
  final String ownerName;
  final String service;
  final String hospital;

  const _JuniorOnCallRow({
    required this.dateStr,
    required this.shiftId,
    required this.ownerName,
    required this.service,
    required this.hospital,
  });"""
new_fields = """  final String shiftId;
  final String ownerName;
  final String ownerPhone;
  final String service;
  final String hospital;

  const _JuniorOnCallRow({
    required this.dateStr,
    required this.shiftId,
    required this.ownerName,
    required this.ownerPhone,
    required this.service,
    required this.hospital,
  });"""
if old_fields not in s:
    raise SystemExit("V11.6.57: Junior row fields anchor missing")
s = s.replace(old_fields, new_fields, 1)

old_rpc = """        shiftId: json['shift_id'] as String,
        ownerName: json['owner_name'] as String,
        service: json['service'] as String,
        hospital: json['hospital'] as String,"""
new_rpc = """        shiftId: json['shift_id'] as String,
        ownerName: json['owner_name'] as String,
        ownerPhone: (json['owner_phone'] as String?) ?? '',
        service: json['service'] as String,
        hospital: json['hospital'] as String,"""
if old_rpc not in s:
    raise SystemExit("V11.6.57: Junior row RPC anchor missing")
s = s.replace(old_rpc, new_rpc, 1)

old_duty_class = """class _JuniorDutyLine extends StatelessWidget {
  final _JuniorOnCallRow row;
  const _JuniorDutyLine({required this.row});

  String _timeLabel(ShiftType shift) {"""
new_duty_class = """class _JuniorDutyLine extends StatelessWidget {
  final _JuniorOnCallRow row;
  const _JuniorDutyLine({required this.row});

  Future<void> _callDoctor(BuildContext context) async {
    final phone = row.ownerPhone.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Numéro de téléphone indisponible pour ce médecin.'),
        ),
      );
      return;
    }

    final uri = Uri(scheme: 'tel', path: phone);
    final launched = await launchUrl(uri);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Impossible d’ouvrir l’appel vers $phone.'),
        ),
      );
    }
  }

  String _timeLabel(ShiftType shift) {"""
if old_duty_class not in s:
    raise SystemExit("V11.6.57: JuniorDutyLine class anchor missing")
s = s.replace(old_duty_class, new_duty_class, 1)

old_line_end = """          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.ownerName,
                  style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.ink),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 2),
                Text(
                  row.shiftId.startsWith('urg-') ? 'Junior · Urgences' : 'Junior',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
        ],"""
new_line_end = """          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.ownerName,
                  style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.ink),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 2),
                Text(
                  row.shiftId.startsWith('urg-') ? 'Junior · Urgences' : 'Junior',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
          SizedBox(width: 8),
          Tooltip(
            message: row.ownerPhone.trim().isEmpty
                ? 'Numéro indisponible'
                : 'Appeler \${row.ownerName}',
            child: Material(
              color: AppColors.brandSoft,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: row.ownerPhone.trim().isEmpty
                    ? null
                    : () => _callDoctor(context),
                child: SizedBox(
                  width: 42,
                  height: 42,
                  child: Icon(
                    Icons.phone_rounded,
                    color: row.ownerPhone.trim().isEmpty
                        ? AppColors.inkFaint
                        : AppColors.brand,
                    size: 21,
                  ),
                ),
              ),
            ),
          ),
        ],"""
if old_line_end not in s:
    raise SystemExit("V11.6.57: Junior duty line tail anchor missing")
s = s.replace(old_line_end, new_line_end, 1)

junior.write_text(s)

source_sql = Path(__file__).resolve().parent / "junior_oncall_phone.sql"
if not source_sql.exists():
    raise SystemExit("V11.6.57: SQL migration source missing")
target_sql = Path("supabase/patch_v11_6_57_junior_oncall_phone.sql")
target_sql.write_text(source_sql.read_text())

checks = {
    "lib/screens/junior_oncall_screen.dart": [
        "theme.scaffoldBackgroundColor",
        "colorScheme.surface",
        "ownerPhone",
        "Uri(scheme: 'tel'",
        "Icons.phone_rounded",
    ],
    "supabase/patch_v11_6_57_junior_oncall_phone.sql": [
        "owner_phone text",
        "pr.phone",
        "junior_oncall_roster",
    ],
}
for file_name, needles in checks.items():
    text = Path(file_name).read_text()
    for needle in needles:
        if needle not in text:
            raise SystemExit(f"V11.6.57: missing {needle!r} in {file_name}")

print("GardeFlow V11.6.57: Astreinte Junior dark-mode surfaces fixed + direct phone buttons")
