from pathlib import Path
import re

PATH = Path('source/lib/screens/home_screen.dart')
text = PATH.read_text(encoding='utf-8')

if 'class _HomeHospitalSkyPainter' in text:
    print('Home hospital visuals v2 already applied.')
    raise SystemExit(0)


def sub_once(pattern: str, repl: str, label: str, flags=re.S):
    global text
    new_text, count = re.subn(pattern, repl, text, count=1, flags=flags)
    if count != 1:
        raise SystemExit(f'Expected exactly one replacement for {label}, got {count}')
    text = new_text


hero_pattern = r"class _HomeHeroCard extends StatelessWidget \{.*?\n\}\n\nclass _HomeStatPill"
hero_replacement = r'''class _HomeHospitalSkyPainter extends CustomPainter {
  final bool isNight;

  const _HomeHospitalSkyPainter({required this.isNight});

  @override
  void paint(Canvas canvas, Size size) {
    final glowPaint = Paint()
      ..color = Colors.white.withOpacity(isNight ? 0.06 : 0.10)
      ..style = PaintingStyle.fill;

    if (isNight) {
      final starPaint = Paint()..color = Colors.white.withOpacity(0.46);
      final stars = <Offset>[
        Offset(size.width * .08, size.height * .16),
        Offset(size.width * .18, size.height * .10),
        Offset(size.width * .31, size.height * .21),
        Offset(size.width * .48, size.height * .12),
        Offset(size.width * .64, size.height * .19),
        Offset(size.width * .78, size.height * .10),
        Offset(size.width * .90, size.height * .25),
      ];
      for (var i = 0; i < stars.length; i++) {
        canvas.drawCircle(stars[i], i.isEven ? 1.25 : .8, starPaint);
      }
    } else {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(size.width * .27, size.height * .17),
          width: size.width * .27,
          height: size.height * .10,
        ),
        glowPaint,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(size.width * .67, size.height * .13),
          width: size.width * .20,
          height: size.height * .075,
        ),
        glowPaint,
      );
    }

    final ecgPaint = Paint()
      ..color = Colors.white.withOpacity(isNight ? 0.11 : 0.15)
      ..strokeWidth = 1.35
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final y = size.height * .49;
    final ecg = Path()
      ..moveTo(size.width * .03, y)
      ..lineTo(size.width * .17, y)
      ..lineTo(size.width * .205, y - 5)
      ..lineTo(size.width * .235, y + 7)
      ..lineTo(size.width * .275, y - 19)
      ..lineTo(size.width * .31, y + 11)
      ..lineTo(size.width * .35, y)
      ..lineTo(size.width * .52, y)
      ..lineTo(size.width * .555, y - 4)
      ..lineTo(size.width * .59, y + 6)
      ..lineTo(size.width * .625, y - 15)
      ..lineTo(size.width * .66, y + 8)
      ..lineTo(size.width * .70, y)
      ..lineTo(size.width * .97, y);
    canvas.drawPath(ecg, ecgPaint);

    final hospitalPaint = Paint()
      ..color = Colors.black.withOpacity(isNight ? 0.18 : 0.10)
      ..style = PaintingStyle.fill;
    final baseline = size.height * .88;
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * .55,
        size.height * .68,
        size.width * .27,
        baseline - size.height * .68,
      ),
      hospitalPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * .61,
        size.height * .59,
        size.width * .14,
        baseline - size.height * .59,
      ),
      hospitalPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * .49,
        size.height * .75,
        size.width * .08,
        baseline - size.height * .75,
      ),
      hospitalPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * .82,
        size.height * .77,
        size.width * .10,
        baseline - size.height * .77,
      ),
      hospitalPaint,
    );

    final crossPaint = Paint()
      ..color = Colors.white.withOpacity(isNight ? 0.10 : 0.15)
      ..style = PaintingStyle.fill;
    final cx = size.width * .68;
    final cy = size.height * .665;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: 22, height: 7),
        const Radius.circular(3),
      ),
      crossPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: 7, height: 22),
        const Radius.circular(3),
      ),
      crossPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _HomeHospitalSkyPainter oldDelegate) =>
      oldDelegate.isNight != isNight;
}

class _HomeHeroCard extends StatelessWidget {
  final AppUser user;
  final String greeting;
  final String dateLabel;
  final String timeLabel;
  final bool isNight;
  final PlanningEntry? guardEntry;
  final int monthlyCount;
  final int urgenceCount;
  final int serviceCount;

  const _HomeHeroCard({
    required this.user,
    required this.greeting,
    required this.dateLabel,
    required this.timeLabel,
    required this.isNight,
    required this.guardEntry,
    required this.monthlyCount,
    required this.urgenceCount,
    required this.serviceCount,
  });

  @override
  Widget build(BuildContext context) {
    final heroColors = isNight
        ? const [Color(0xFF020B22), Color(0xFF082E70), Color(0xFF0B65BD)]
        : const [Color(0xFF147FD1), Color(0xFF39B4F5), Color(0xFF9CE4FF)];
    final heroGlow = isNight
        ? const Color(0xFF1C78E8)
        : const Color(0xFF54C7FF);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: heroColors,
          stops: const [0.0, 0.56, 1.0],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.white.withOpacity(isNight ? 0.10 : 0.20),
        ),
        boxShadow: [
          BoxShadow(
            color: heroGlow.withOpacity(isNight ? 0.22 : 0.28),
            blurRadius: 30,
            spreadRadius: 1,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _HomeHospitalSkyPainter(isNight: isNight),
            ),
          ),
          Positioned(
            right: -28,
            top: -38,
            child: Container(
              width: 146,
              height: 146,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.white.withOpacity(isNight ? 0.15 : 0.26),
                    Colors.white.withOpacity(0.02),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 17,
            top: 18,
            child: Container(
              width: 62,
              height: 62,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(isNight ? 0.10 : 0.18),
                border: Border.all(
                  color: Colors.white.withOpacity(isNight ? 0.14 : 0.28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: (isNight
                            ? Colors.white
                            : const Color(0xFFFFD84A))
                        .withOpacity(0.18),
                    blurRadius: 18,
                  ),
                ],
              ),
              child: _GuardPeriodGlyph(
                isNight: isNight,
                is24h: false,
                size: 35,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 17),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 78),
                  child: Text(
                    '$greeting Dr ${user.nom}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'SpaceGrotesk',
                      fontSize: 25,
                      height: 1.04,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.65,
                    ),
                  ),
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      color: Colors.white.withOpacity(0.90),
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '$dateLabel · $timeLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.92),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 17),
                Row(
                  children: [
                    Expanded(
                      child: _HomeStatPill(
                        icon: Icons.calendar_month_rounded,
                        value: monthlyCount,
                        label: 'Ce mois',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _HomeStatPill(
                        icon: Icons.emergency_rounded,
                        value: urgenceCount,
                        label: 'Urgences',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _HomeStatPill(
                        icon: Icons.medical_services_rounded,
                        value: serviceCount,
                        label: 'Service',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeStatPill'''
sub_once(hero_pattern, hero_replacement, 'home hero card')

stat_pattern = r"class _HomeStatPill extends StatelessWidget \{.*?\n\}\n\nclass _HomeQuickRow"
stat_replacement = r'''class _HomeStatPill extends StatelessWidget {
  final IconData icon;
  final int value;
  final String label;

  const _HomeStatPill({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 57),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.18),
            Colors.white.withOpacity(0.085),
          ],
        ),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 29,
            height: 29,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.13),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$value',
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'SpaceGrotesk',
                    fontSize: 18,
                    height: 1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.86),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeQuickRow'''
sub_once(stat_pattern, stat_replacement, 'home stat pill')

replacements = {
    "dutyColors: [Color(0xFF360611), Color(0xFF8B1730)],\n        glow: Color(0xFFD92A4A),": "dutyColors: [Color(0xFF420516), Color(0xFFA10D3D), Color(0xFFE72B62)],\n        glow: Color(0xFFFF3B6A),",
    "dutyColors: [Color(0xFF9A3A09), Color(0xFFF47B18)],\n        glow: Color(0xFFFFA23D),": "dutyColors: [Color(0xFF9C3300), Color(0xFFF26B06), Color(0xFFFFB020)],\n        glow: Color(0xFFFFA534),",
    "dutyColors: [Color(0xFFB51630), Color(0xFFF34052)],\n        glow: Color(0xFFFF6272),": "dutyColors: [Color(0xFFB80D2B), Color(0xFFF43F5E), Color(0xFFFF7586)],\n        glow: Color(0xFFFF5570),",
    "dutyColors: [Color(0xFF06172F), Color(0xFF15559C)],\n        glow: Color(0xFF388DDF),": "dutyColors: [Color(0xFF051841), Color(0xFF0C46A0), Color(0xFF1976D2)],\n        glow: Color(0xFF2C8DFF),",
    "dutyColors: [Color(0xFF0B83C0), Color(0xFF38BDE9)],\n        glow: Color(0xFF72D8F8),": "dutyColors: [Color(0xFF087CBF), Color(0xFF28B6EE), Color(0xFF7FDBFF)],\n        glow: Color(0xFF54CCFF),",
    "dutyColors: [Color(0xFF0F7DCE), Color(0xFF48BAF1)],\n      glow: Color(0xFF58C8FF),": "dutyColors: [Color(0xFF0B82DC), Color(0xFF37B7F8), Color(0xFF91DEFF)],\n      glow: Color(0xFF54C8FF),",
}
for old, new in replacements.items():
    if old not in text:
        raise SystemExit(f'Missing palette anchor: {old[:70]}')
    text = text.replace(old, new, 1)

painter_pattern = r"class _GuardSkyPainter extends CustomPainter \{.*?\n\}\n\nclass _HomeHospitalSkyPainter"
painter_replacement = r'''class _GuardSkyPainter extends CustomPainter {
  final _GuardVisualTheme theme;
  final bool compact;

  const _GuardSkyPainter({required this.theme, this.compact = false});

  @override
  void paint(Canvas canvas, Size size) {
    if (theme.isNight) {
      final starPaint = Paint()..color = Colors.white.withOpacity(0.44);
      final stars = <Offset>[
        Offset(size.width * .08, size.height * .17),
        Offset(size.width * .19, size.height * .09),
        Offset(size.width * .34, size.height * .22),
        Offset(size.width * .51, size.height * .13),
        Offset(size.width * .66, size.height * .20),
        Offset(size.width * .79, size.height * .10),
        Offset(size.width * .91, size.height * .24),
      ];
      for (var i = 0; i < stars.length; i++) {
        canvas.drawCircle(stars[i], i.isEven ? 1.2 : .75, starPaint);
      }
    } else {
      final cloudPaint = Paint()..color = Colors.white.withOpacity(0.11);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(size.width * .26, size.height * .18),
          width: size.width * .24,
          height: size.height * .09,
        ),
        cloudPaint,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(size.width * .72, size.height * .14),
          width: size.width * .20,
          height: size.height * .075,
        ),
        cloudPaint,
      );
    }

    final ecgPaint = Paint()
      ..color = Colors.white.withOpacity(theme.isNight ? 0.13 : 0.17)
      ..strokeWidth = compact ? 1.2 : 1.45
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final y = size.height * (compact ? .54 : .51);
    final ecg = Path()
      ..moveTo(size.width * .03, y)
      ..lineTo(size.width * .18, y)
      ..lineTo(size.width * .215, y - 4)
      ..lineTo(size.width * .245, y + 6)
      ..lineTo(size.width * .28, y - (compact ? 14 : 18))
      ..lineTo(size.width * .315, y + 9)
      ..lineTo(size.width * .355, y)
      ..lineTo(size.width * .55, y)
      ..lineTo(size.width * .58, y - 3)
      ..lineTo(size.width * .61, y + 5)
      ..lineTo(size.width * .645, y - (compact ? 11 : 15))
      ..lineTo(size.width * .68, y + 7)
      ..lineTo(size.width * .72, y)
      ..lineTo(size.width * .97, y);
    canvas.drawPath(ecg, ecgPaint);

    final hospitalPaint = Paint()
      ..color = Colors.black.withOpacity(theme.isNight ? 0.23 : 0.14)
      ..style = PaintingStyle.fill;
    final baseline = size.height * .98;
    final centerX = size.width * .70;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          centerX - size.width * .13,
          size.height * .64,
          size.width * .26,
          baseline - size.height * .64,
        ),
        const Radius.circular(5),
      ),
      hospitalPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          centerX - size.width * .07,
          size.height * .53,
          size.width * .14,
          baseline - size.height * .53,
        ),
        const Radius.circular(5),
      ),
      hospitalPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        centerX - size.width * .22,
        size.height * .75,
        size.width * .09,
        baseline - size.height * .75,
      ),
      hospitalPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        centerX + size.width * .13,
        size.height * .72,
        size.width * .10,
        baseline - size.height * .72,
      ),
      hospitalPaint,
    );

    final crossPaint = Paint()
      ..color = Colors.white.withOpacity(theme.isNight ? 0.17 : 0.23)
      ..style = PaintingStyle.fill;
    final cx = centerX;
    final cy = size.height * .60;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: 22, height: 7),
        const Radius.circular(3),
      ),
      crossPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: 7, height: 22),
        const Radius.circular(3),
      ),
      crossPaint,
    );

    final arcPaint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(size.width * .92, size.height * .06),
        radius: size.width * .18,
      ),
      .7,
      1.8,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GuardSkyPainter oldDelegate) =>
      oldDelegate.theme != theme || oldDelegate.compact != compact;
}

class _HomeHospitalSkyPainter'''
sub_once(painter_pattern, painter_replacement, 'guard sky painter')

old_card_decoration = """borderRadius: BorderRadius.circular(26),\n            border: Border.all(color: Colors.white.withOpacity(0.10)),\n            boxShadow: [\n              BoxShadow(\n                color: visual.glow.withOpacity(0.16),\n                blurRadius: 22,\n                offset: const Offset(0, 10),\n              ),\n            ],"""
new_card_decoration = """borderRadius: BorderRadius.circular(28),\n            border: Border.all(color: Colors.white.withOpacity(0.16)),\n            boxShadow: [\n              BoxShadow(\n                color: visual.glow.withOpacity(0.24),\n                blurRadius: 28,\n                spreadRadius: 1,\n                offset: const Offset(0, 12),\n              ),\n            ],"""
if old_card_decoration not in text:
    raise SystemExit('Missing duty-card decoration anchor')
text = text.replace(old_card_decoration, new_card_decoration, 1)

text = text.replace(
    "borderRadius: BorderRadius.circular(26),\n            child: Stack(",
    "borderRadius: BorderRadius.circular(28),\n            child: Stack(",
    1,
)

old_ann_decoration = """gradient: const LinearGradient(\n          begin: Alignment.topLeft,\n          end: Alignment.bottomRight,\n          colors: [Color(0xFF071A18), Color(0xFF0B302A)],\n        ),\n        borderRadius: BorderRadius.circular(24),\n        border: Border.all(color: Colors.white.withOpacity(0.08)),\n        boxShadow: [\n          BoxShadow(\n            color: const Color(0xFF00C389).withOpacity(0.08),\n            blurRadius: 20,\n            offset: const Offset(0, 8),\n          ),\n        ],"""
new_ann_decoration = """gradient: const LinearGradient(\n          begin: Alignment.topLeft,\n          end: Alignment.bottomRight,\n          colors: [Color(0xFF061D1A), Color(0xFF0A3A32), Color(0xFF0E5142)],\n        ),\n        borderRadius: BorderRadius.circular(26),\n        border: Border.all(color: Colors.white.withOpacity(0.11)),\n        boxShadow: [\n          BoxShadow(\n            color: const Color(0xFF19D99A).withOpacity(0.15),\n            blurRadius: 26,\n            spreadRadius: 1,\n            offset: const Offset(0, 10),\n          ),\n        ],"""
if old_ann_decoration not in text:
    raise SystemExit('Missing announcements decoration anchor')
text = text.replace(old_ann_decoration, new_ann_decoration, 1)

text = text.replace(
    "colors: [\n                      AppColors.brand.withOpacity(0.22),\n                      AppColors.brandBright.withOpacity(0.10),\n                    ],",
    "colors: [\n                      const Color(0xFF28E7A5).withOpacity(0.32),\n                      const Color(0xFF0E9E78).withOpacity(0.14),\n                    ],",
    1,
)
text = text.replace(
    "color: AppColors.brandBright,\n                  size: 23,",
    "color: const Color(0xFF63F4C0),\n                  size: 24,",
    1,
)

old_button = """style: TextButton.styleFrom(\n                  foregroundColor: const Color(0xFF43E6A0),\n                  padding: const EdgeInsets.symmetric(horizontal: 8),\n                  textStyle: const TextStyle(\n                    fontSize: 11,\n                    fontWeight: FontWeight.w900,\n                  ),\n                ),"""
new_button = """style: TextButton.styleFrom(\n                  foregroundColor: const Color(0xFF79FFD0),\n                  backgroundColor: Colors.white.withOpacity(0.07),\n                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),\n                  shape: RoundedRectangleBorder(\n                    borderRadius: BorderRadius.circular(999),\n                    side: BorderSide(color: Colors.white.withOpacity(0.09)),\n                  ),\n                  textStyle: const TextStyle(\n                    fontSize: 11,\n                    fontWeight: FontWeight.w900,\n                  ),\n                ),"""
if old_button not in text:
    raise SystemExit('Missing announcements button anchor')
text = text.replace(old_button, new_button, 1)

text = text.replace(
    "color: Colors.white.withOpacity(0.035),\n          borderRadius: BorderRadius.circular(17),\n          border: Border.all(color: Colors.white.withOpacity(0.07)),",
    "gradient: LinearGradient(\n            begin: Alignment.topLeft,\n            end: Alignment.bottomRight,\n            colors: [\n              Colors.white.withOpacity(0.075),\n              const Color(0xFF18C991).withOpacity(0.055),\n            ],\n          ),\n          borderRadius: BorderRadius.circular(18),\n          border: Border.all(color: Colors.white.withOpacity(0.10)),",
    1,
)
text = text.replace(
    "color: const Color(0xFF20C986).withOpacity(0.08),\n                borderRadius: BorderRadius.circular(13),",
    "gradient: LinearGradient(\n                  begin: Alignment.topLeft,\n                  end: Alignment.bottomRight,\n                  colors: [\n                    const Color(0xFF2FE4A5).withOpacity(0.18),\n                    const Color(0xFF0D8A69).withOpacity(0.08),\n                  ],\n                ),\n                borderRadius: BorderRadius.circular(14),\n                border: Border.all(\n                  color: const Color(0xFF5EF1BE).withOpacity(0.14),\n                ),",
    1,
)
text = text.replace(
    "color: Colors.white.withOpacity(0.58),\n                size: 21,",
    "color: const Color(0xFF72F4C3),\n                size: 22,",
    1,
)
text = text.replace(
    "color: Colors.white.withOpacity(0.70),\n                  fontSize: 11.5,",
    "color: Colors.white.withOpacity(0.82),\n                  fontSize: 11.7,",
    1,
)

PATH.write_text(text, encoding='utf-8')
print('Applied home visuals v2: blue hero, hospital duty styling, upgraded announcements.')
