from pathlib import Path

EXPECTED = "version: 11.6.42+202"
TARGET = "version: 11.6.43+203"

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.43: base version mismatch")
pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))


def replace_class(source: str, class_name: str, replacement: str) -> str:
    marker = f"class {class_name} "
    start = source.find(marker)
    if start < 0:
        raise SystemExit(f"V11.6.43: {class_name} not found")
    brace = source.find("{", start)
    if brace < 0:
        raise SystemExit(f"V11.6.43: opening brace missing for {class_name}")
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
        raise SystemExit(f"V11.6.43: closing brace missing for {class_name}")
    return source[:start] + replacement.rstrip() + source[end:]


home = Path("lib/screens/home_screen.dart")
h = home.read_text()

next_guard_card = r"""class _NextGuardCard extends StatelessWidget {
  final PlanningEntry? entry;
  final VoidCallback onTap;

  const _NextGuardCard({
    required this.entry,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (entry == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: AppColors.line),
          boxShadow: AppShadow.low,
        ),
        child: const Row(
          children: [
            Icon(
              Icons.event_available_rounded,
              color: AppColors.brand,
              size: 28,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Aucune garde à venir.',
                style: TextStyle(
                  color: AppColors.inkSoft,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final current = entry!;
    final shift = ShiftCatalog.byId(current.shiftId);
    final shiftId = shift.id.toLowerCase();
    final shiftLabel = shift.label.trim();

    final isUrgence = shiftId.startsWith('urg-') ||
        shiftId.contains('urgence') ||
        shiftLabel.toLowerCase().contains('urgence');
    final is24h = shiftId.contains('24h') ||
        shiftId.contains('24-h') ||
        shiftLabel.toLowerCase().contains('24h');
    final isNight = !is24h &&
        (shiftId.contains('nuit') ||
            shiftLabel.toLowerCase().contains('nuit'));

    final category = isUrgence ? 'URGENCES' : 'SERVICE';
    final period = is24h
        ? '24H'
        : isNight
            ? 'NUIT'
            : 'JOUR';

    final date = DateTime.tryParse(current.dateStr);
    final dateLabel = date == null
        ? current.dateStr
        : DateFormat('EEE d MMMM', 'fr_FR').format(date);

    final timeLabel = is24h
        ? '08:00 → 08:00'
        : isNight
            ? '20:00 → 08:00'
            : '08:00 → 20:00';

    final guardTitle = shiftLabel.isEmpty
        ? 'Garde de \${period.toLowerCase()}'
        : shiftLabel;

    final colors = is24h
        ? const [
            Color(0xFF60CAFF),
            Color(0xFF2392EA),
            Color(0xFF173E72),
            Color(0xFF071426),
          ]
        : isNight
            ? const [
                Color(0xFF071426),
                Color(0xFF123D70),
              ]
            : const [
                Color(0xFF62CBFF),
                Color(0xFF168DE9),
              ];

    final stops = is24h
        ? const [0.0, 0.44, 0.58, 1.0]
        : null;

    final mainIcon = is24h
        ? Icons.brightness_6_rounded
        : isNight
            ? Icons.nightlight_round
            : Icons.wb_sunny_rounded;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Ink(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
              stops: stops,
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: colors.last.withOpacity(0.24),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Stack(
              children: [
                Positioned(
                  right: -12,
                  top: -16,
                  child: Icon(
                    is24h
                        ? Icons.brightness_6_rounded
                        : isNight
                            ? Icons.nightlight_round
                            : Icons.wb_sunny_rounded,
                    size: 102,
                    color: Colors.white.withOpacity(0.12),
                  ),
                ),
                if (isNight || is24h) ...[
                  const Positioned(
                    right: 86,
                    top: 20,
                    child: Icon(
                      Icons.star_rounded,
                      size: 12,
                      color: Colors.white54,
                    ),
                  ),
                  const Positioned(
                    right: 54,
                    top: 64,
                    child: Icon(
                      Icons.star_rounded,
                      size: 8,
                      color: Colors.white38,
                    ),
                  ),
                  const Positioned(
                    right: 126,
                    top: 82,
                    child: Icon(
                      Icons.star_rounded,
                      size: 7,
                      color: Colors.white38,
                    ),
                  ),
                ],
                Positioned(
                  right: -28,
                  bottom: -46,
                  child: Container(
                    width: 138,
                    height: 138,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.07),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 17, 15, 17),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 62,
                        height: 62,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(19),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.22),
                          ),
                        ),
                        child: Icon(
                          mainIcon,
                          color: Colors.white,
                          size: 31,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'PROCHAINE GARDE',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.82),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.75,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$category • $period',
                              style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'SpaceGrotesk',
                                fontSize: 22,
                                height: 1.08,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              guardTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.92),
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 13),
                            _NextGuardInfoLine(
                              icon: Icons.calendar_month_rounded,
                              text: dateLabel,
                            ),
                            const SizedBox(height: 6),
                            _NextGuardInfoLine(
                              icon: Icons.schedule_rounded,
                              text: timeLabel,
                            ),
                            const SizedBox(height: 6),
                            _NextGuardInfoLine(
                              icon: isUrgence
                                  ? Icons.emergency_rounded
                                  : Icons.medical_services_rounded,
                              text: isUrgence
                                  ? 'Garde aux urgences'
                                  : 'Garde de service',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Padding(
                        padding: const EdgeInsets.only(top: 42),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white.withOpacity(0.90),
                          size: 29,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NextGuardInfoLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _NextGuardInfoLine({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          icon,
          color: Colors.white.withOpacity(0.90),
          size: 16,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withOpacity(0.94),
              fontSize: 12.5,
              height: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
"""

h = replace_class(h, "_NextGuardCard", next_guard_card)
home.write_text(h)

print("GardeFlow V11.6.43: redesigned next-guard card with dynamic JOUR/NUIT/24H background and detailed guard info")
