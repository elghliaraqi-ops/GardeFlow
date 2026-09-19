from pathlib import Path

EXPECTED = "version: 11.6.44+204"
TARGET = "version: 11.6.45+205"

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.45: base version mismatch")
pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

home = Path("lib/screens/home_screen.dart")
s = home.read_text()

anchor = """        _NextGuardCard(
          entry: next,
          onTap: onOpenPlanning,
        ),
        const SizedBox(height: 28),
        const DailyNewsSection(),"""

replacement = """        _NextGuardCard(
          entry: next,
          onTap: onOpenPlanning,
        ),
        const SizedBox(height: 14),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 13,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: AppColors.brandSoft,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: AppColors.brand.withOpacity(0.12),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Actualités plus bas',
                  style: TextStyle(
                    color: AppColors.brandDark,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(width: 6),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: AppColors.brand,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        const DailyNewsSection(),"""

if anchor not in s:
    raise SystemExit("V11.6.45: dashboard news anchor missing")

home.write_text(s.replace(anchor, replacement, 1))

print("GardeFlow V11.6.45: added clear downward cue toward Actualités on the home screen")
