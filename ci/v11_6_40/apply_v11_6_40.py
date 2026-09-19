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
pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

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
