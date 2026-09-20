from pathlib import Path

EXPECTED = "version: 11.6.66+226"
TARGET = "version: 11.6.67+227"


def replace_once(path: str, old: str, new: str, label: str) -> None:
    p = Path(path)
    text = p.read_text()
    if old not in text:
        if new in text:
            return
        raise SystemExit(f"V11.6.67: {label} anchor missing in {path}")
    p.write_text(text.replace(old, new, 1))


pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    if TARGET not in pub:
        raise SystemExit("V11.6.67: base version mismatch")
else:
    pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

# Past months are consultation-only:
# - no validation status/button/automatic-validation text
# - no shift tray at all
# - calendar remains visible and read-only
replace_once(
    "lib/screens/home_screen.dart",
    """        _ShiftTray(
          enabled: !isPastMonth &&
              appState.canEditMyPlanningMonth(appState.visibleMonth),
        ),
""",
    """        if (!isPastMonth)
          _ShiftTray(
            enabled: appState.canEditMyPlanningMonth(appState.visibleMonth),
          ),
""",
    "hide past-month tile tray",
)

replace_once(
    "lib/screens/home_screen.dart",
    """    final monthLabel = _capitalize(DateFormat.yMMMM('fr_FR').format(month));

    String statusLabel;
""",
    """    final monthLabel = _capitalize(DateFormat.yMMMM('fr_FR').format(month));
    final now = DateTime.now();
    final isPastMonth = DateTime(month.year, month.month, 1)
        .isBefore(DateTime(now.year, now.month, 1));

    String statusLabel;
""",
    "month bar past-month state",
)

replace_once(
    "lib/screens/home_screen.dart",
    """    final canSubmit = status != PlanningMonthStatus.approved;
""",
    """    final canSubmit =
        !isPastMonth && status != PlanningMonthStatus.approved;
""",
    "disable validation submission for past months",
)

replace_once(
    "lib/screens/home_screen.dart",
    """          SizedBox(height: 3),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () => _showMonthInfo(
                  context,
                  status,
                  reopenReason,
                ),
                child: Container(
                  height: 30,
                  padding: EdgeInsets.symmetric(horizontal: 11),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 15, color: statusFg),
                      SizedBox(width: 5),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusFg,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (canSubmit) ...[
                SizedBox(width: 8),
                _ValidateButton(appState: appState, month: month),
              ],
            ],
          ),
          if (canSubmit) ...[
            SizedBox(height: 5),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'Validation automatique : 7 jours après la publication ou le remplacement du planning officiel.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.inkSoft,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
            ),
          ],
""",
    """          if (!isPastMonth) ...[
            SizedBox(height: 3),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () => _showMonthInfo(
                    context,
                    status,
                    reopenReason,
                  ),
                  child: Container(
                    height: 30,
                    padding: EdgeInsets.symmetric(horizontal: 11),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 15, color: statusFg),
                        SizedBox(width: 5),
                        Text(
                          statusLabel,
                          style: TextStyle(
                            color: statusFg,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (canSubmit) ...[
                  SizedBox(width: 8),
                  _ValidateButton(appState: appState, month: month),
                ],
              ],
            ),
            if (canSubmit) ...[
              SizedBox(height: 5),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'Validation automatique : 7 jours après la publication ou le remplacement du planning officiel.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.inkSoft,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ],
""",
    "hide validation UI for past months",
)

home = Path("lib/screens/home_screen.dart").read_text()
checks = [
    "if (!isPastMonth)\n          _ShiftTray(",
    "final canSubmit =\n        !isPastMonth && status != PlanningMonthStatus.approved;",
    "if (!isPastMonth) ...[",
]
for needle in checks:
    if needle not in home:
        raise SystemExit(f"V11.6.67: missing {needle!r}")

if TARGET not in pubspec.read_text():
    raise SystemExit("V11.6.67: version bump missing")

print("GardeFlow V11.6.67: past months are consultation-only, without validation UI or shift tiles")
