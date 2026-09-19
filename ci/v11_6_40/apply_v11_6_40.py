from pathlib import Path
from io import BytesIO
import base64
from PIL import Image

EXPECTED = "version: 11.6.39+199"
TARGET = "version: 11.6.40+200"

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.40: base version mismatch")
pub = pub.replace(EXPECTED, TARGET, 1)
asset_line = "    - assets/branding/elghali_signature.webp"
if asset_line not in pub:
    logo_line = "    - assets/branding/gardeflow_logo.png"
    if logo_line not in pub:
        raise SystemExit("V11.6.40: branding assets anchor missing")
    pub = pub.replace(logo_line, logo_line + "\n" + asset_line, 1)
pubspec.write_text(pub)

def replace_class(source: str, class_name: str, replacement: str) -> str:
    marker = f"class {class_name} "
    start = source.find(marker)
    if start < 0:
        raise SystemExit(f"V11.6.40: {class_name} not found")
    brace = source.find("{", start)
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
        raise SystemExit(f"V11.6.40: closing brace missing for {class_name}")
    return source[:start] + replacement.rstrip() + source[end:]

junior = Path("lib/screens/junior_oncall_screen.dart")
j = junior.read_text()

days = r"""class _DaySelector extends StatelessWidget {
  final DateTime weekStart;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _DaySelector({
    required this.weekStart,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 7,
        separatorBuilder: (_, __) => const SizedBox(width: 5),
        itemBuilder: (context, index) => _DayChip(
          date: weekStart.add(Duration(days: index)),
          selected: index == selectedIndex,
          onTap: () => onSelected(index),
        ),
      ),
    );
  }
}"""
j = replace_class(j, "_DaySelector", days)

day_chip = r"""class _DayChip extends StatelessWidget {
  final DateTime date;
  final bool selected;
  final VoidCallback onTap;

  const _DayChip({
    required this.date,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final day = DateFormat('EEE', 'fr_FR').format(date).replaceAll('.', '');
    final label = day.isEmpty
        ? ''
        : day[0].toUpperCase() + day.substring(1);

    return SizedBox(
      width: 47,
      child: Material(
        color: selected ? AppColors.brand : AppColors.card,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: selected ? AppColors.brand : AppColors.line,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : AppColors.inkSoft,
                  ),
                ),
                Text(
                  '${date.day}',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    color: selected ? Colors.white : AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}"""
j = replace_class(j, "_DayChip", day_chip)
junior.write_text(j)

profile = Path("lib/screens/profile_screen.dart")
p = profile.read_text()
old = """              Container(
                width: 270,
                height: 120,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.line),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Text(
                      'Elghali',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 38,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.5,
                      ),
                    ),
                    Image.asset(
                      'assets/branding/elghali_signature.webp',
                      width: 245,
                      height: 110,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),"""
new = """              Container(
                width: 280,
                height: 126,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.line),
                ),
                child: Image.asset(
                  'assets/branding/elghali_signature.webp',
                  width: 260,
                  height: 112,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  gaplessPlayback: true,
                ),
              ),"""
if old not in p:
    raise SystemExit("V11.6.40: current signature block missing")
profile.write_text(p.replace(old, new, 1))

signature_png = base64.b64decode("""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""")
signature_asset = Path("assets/branding/elghali_signature.webp")
signature_asset.parent.mkdir(parents=True, exist_ok=True)
with Image.open(BytesIO(signature_png)) as image:
    image = image.convert("RGB")
    image.save(signature_asset, "WEBP", quality=100, method=6)

with Image.open(signature_asset) as check:
    check.load()
    if check.width < 500 or check.height < 200:
        raise SystemExit("V11.6.40: signature asset unexpectedly small")

print("GardeFlow V11.6.40: compact Junior dates + real Elghali signature")
