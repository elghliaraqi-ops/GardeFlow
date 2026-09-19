from pathlib import Path
import math
from PIL import Image, ImageDraw, ImageFont

signature_path = Path("assets/branding/elghali_signature.webp")

font_candidates = [
    "/usr/share/fonts/opentype/urw-base35/Z003-MediumItalic.otf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSerifCondensed-Italic.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Italic.ttf",
]
font_path = next((p for p in font_candidates if Path(p).exists()), None)
if font_path is None:
    raise SystemExit("V11.6.38 signature font unavailable")

font = ImageFont.truetype(font_path, 150)
img = Image.new("RGBA", (1000, 360), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)
ink = (18, 54, 41, 255)

draw.text((70, 45), "Elghali", font=font, fill=ink)

points = []
for index in range(121):
    t = index / 120
    points.append((170 + 650 * t, 275 + 12 * math.sin(math.pi * t) - 18 * t))
draw.line(points, fill=ink, width=5)

bbox = img.getchannel("A").getbbox()
if bbox:
    img = img.crop((
        max(0, bbox[0] - 20),
        max(0, bbox[1] - 20),
        min(img.width, bbox[2] + 20),
        min(img.height, bbox[3] + 20),
    ))

img.save(signature_path, "WEBP", lossless=True, quality=100, method=6)

# Re-open immediately: fail the build if the asset is not genuinely valid.
with Image.open(signature_path) as check:
    check.load()
    if check.width < 100 or check.height < 40:
        raise SystemExit("V11.6.38 generated signature is unexpectedly small")

profile = Path("lib/screens/profile_screen.dart")
p = profile.read_text()

old = """              Image.asset(
                'assets/branding/elghali_signature.webp',
                width: 235,
                height: 105,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                gaplessPlayback: true,
              ),
              const SizedBox(height: 2),"""

new = """              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.line),
                ),
                child: Image.asset(
                  'assets/branding/elghali_signature.webp',
                  width: 235,
                  height: 105,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  gaplessPlayback: true,
                ),
              ),
              const SizedBox(height: 4),"""

if old not in p:
    raise SystemExit("V11.6.38 profile signature block missing")

profile.write_text(p.replace(old, new, 1))
print("V11.6.38 part 3 applied")
