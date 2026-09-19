from pathlib import Path

EXPECTED = "version: 11.6.29+189"
TARGET = "version: 11.6.30+190"

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.30: base version mismatch")
pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

home = Path("lib/screens/home_screen.dart")
text = home.read_text()

def replace_class(source: str, class_name: str, replacement: str) -> str:
    marker = f"class {class_name} "
    start = source.find(marker)
    if start < 0:
        raise SystemExit(f"V11.6.30: {class_name} not found")
    brace = source.find("{", start)
    if brace < 0:
        raise SystemExit(f"V11.6.30: opening brace missing for {class_name}")
    depth = 0
    end = None
    for i in range(brace, len(source)):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                end = i + 1
                break
    if end is None:
        raise SystemExit(f"V11.6.30: closing brace missing for {class_name}")
    return source[:start] + replacement.rstrip() + source[end:]

shift_tray = r"""class _ShiftTray extends StatelessWidget {
  final bool enabled;

  const _ShiftTray({required this.enabled});

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return Container(
        height: 42,
        margin: const EdgeInsets.fromLTRB(8, 2, 8, 5),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line),
          boxShadow: [
            BoxShadow(
              color: AppColors.navy.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 15,
              color: AppColors.inkSoft,
            ),
            SizedBox(width: 7),
            Text(
              'Planning validé · tuiles verrouillées',
              style: TextStyle(
                color: AppColors.inkSoft,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      height: 92,
      padding: const EdgeInsets.fromLTRB(7, 6, 7, 7),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(22),
        ),
        border: const Border(
          top: BorderSide(color: AppColors.line),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _PlanningShiftGroup(
              title: 'SERVICE',
              icon: Icons.local_hospital_outlined,
              accent: AppColors.brand,
              shifts: const [
                ShiftCatalog.serviceJour,
                ShiftCatalog.service24h,
                ShiftCatalog.serviceNuit,
              ],
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: _PlanningShiftGroup(
              title: 'URGENCES',
              icon: Icons.emergency_rounded,
              accent: AppColors.danger,
              shifts: const [
                ShiftCatalog.urgJour,
                ShiftCatalog.urg24h,
                ShiftCatalog.urgNuit,
              ],
            ),
          ),
          const SizedBox(width: 5),
          SizedBox(
            width: 54,
            child: Container(
              padding: const EdgeInsets.fromLTRB(4, 5, 4, 5),
              decoration: BoxDecoration(
                color: AppColors.conge.withOpacity(0.42),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: AppColors.congeText.withOpacity(0.13),
                ),
              ),
              child: Column(
                children: [
                  const Text(
                    'CONGÉ',
                    maxLines: 1,
                    style: TextStyle(
                      color: AppColors.congeText,
                      fontSize: 8,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.25,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: _CompactShiftTile(
                      shift: ShiftCatalog.conge,
                      enabled: true,
                      showLabel: false,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanningShiftGroup extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accent;
  final List<ShiftType> shifts;

  const _PlanningShiftGroup({
    required this.title,
    required this.icon,
    required this.accent,
    required this.shifts,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(5, 4, 5, 5),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.055),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: accent.withOpacity(0.18),
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 15,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 10, color: accent),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: accent,
                      fontSize: 8.2,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.28,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          Expanded(
            child: Row(
              children: [
                for (var i = 0; i < shifts.length; i++) ...[
                  if (i > 0) const SizedBox(width: 3),
                  Expanded(
                    child: _CompactShiftTile(
                      shift: shifts[i],
                      enabled: true,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
"""

compact_tile = r"""class _CompactShiftTile extends StatelessWidget {
  final ShiftType shift;
  final bool enabled;
  final bool showLabel;

  const _CompactShiftTile({
    required this.shift,
    required this.enabled,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    final tile = Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
      decoration: BoxDecoration(
        color: shift.color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: shift.textColor.withOpacity(0.11),
        ),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              shift.icon,
              size: showLabel ? 14 : 19,
              color: shift.textColor,
            ),
            if (showLabel) ...[
              const SizedBox(height: 2),
              Text(
                shift.label,
                maxLines: 1,
                style: TextStyle(
                  color: shift.textColor,
                  fontFamily: 'SpaceGrotesk',
                  fontSize: 9.2,
                  height: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return Draggable<String>(
      data: shift.id,
      maxSimultaneousDrags: enabled ? 1 : 0,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 56,
          height: 58,
          child: tile,
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.28,
        child: tile,
      ),
      child: tile,
    );
  }
}
"""

text = replace_class(text, "_ShiftTray", shift_tray)
text = replace_class(text, "_CompactShiftTile", compact_tile)

home.write_text(text)

print("GardeFlow V11.6.30: tuiles Planning regroupées Service/Urgences + Congé séparé")
