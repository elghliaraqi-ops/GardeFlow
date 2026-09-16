from pathlib import Path
import argparse
import json
from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument('--android', action='store_true')
parser.add_argument('--ios', action='store_true')
args = parser.parse_args()
if not args.android and not args.ios:
    raise SystemExit('Use --android or --ios')

root = Path('.')
source = root / 'tool/android-res/drawable-nodpi/gardeflow_logo.png'
if not source.is_file():
    raise SystemExit(f'Logo source introuvable: {source}')

img = Image.open(source).convert('RGB')
width, height = img.size
mask = Image.new('1', img.size, 0)
mask_px = mask.load()
src_px = img.load()
for y in range(height):
    for x in range(width):
        r, g, b = src_px[x, y]
        if min(r, g, b) < 185 and (max(r, g, b) - min(r, g, b)) > 45:
            mask_px[x, y] = 1
bbox = mask.getbbox()
if bbox is None:
    raise SystemExit('Impossible de détecter le symbole du logo.')
left, top, right, bottom = bbox
pad = max(8, int(min(width, height) * 0.01))
symbol = img.crop((max(0, left-pad), max(0, top-pad), min(width, right+pad), min(height, bottom+pad)))

def centered_master(symbol_img, canvas_size, symbol_size):
    canvas = Image.new('RGB', (canvas_size, canvas_size), 'white')
    sw, sh = symbol_img.size
    scale = min(symbol_size / sw, symbol_size / sh)
    nw, nh = max(1, round(sw * scale)), max(1, round(sh * scale))
    resized = symbol_img.resize((nw, nh), Image.Resampling.LANCZOS)
    canvas.paste(resized, ((canvas_size-nw)//2, (canvas_size-nh)//2))
    return canvas

if args.android:
    legacy = centered_master(symbol, 1024, 655)
    adaptive = centered_master(symbol, 1024, 440)
    adaptive_path = root / 'tool/android-res/drawable-nodpi/gardeflow_launcher_logo.png'
    adaptive_path.parent.mkdir(parents=True, exist_ok=True)
    adaptive.save(adaptive_path, 'PNG', optimize=True)
    for density, size in {'mdpi':48,'hdpi':72,'xhdpi':96,'xxhdpi':144,'xxxhdpi':192}.items():
        target = root / f'tool/android-res/mipmap-{density}/ic_launcher.png'
        target.parent.mkdir(parents=True, exist_ok=True)
        legacy.resize((size,size), Image.Resampling.LANCZOS).save(target, 'PNG', optimize=True)
    foreground = root / 'tool/android-res/drawable/gardeflow_launcher_foreground.xml'
    text = foreground.read_text(encoding='utf-8').replace('@drawable/gardeflow_logo', '@drawable/gardeflow_launcher_logo')
    foreground.write_text(text, encoding='utf-8')

if args.ios:
    master = centered_master(symbol, 1024, 655)
    appicon_dir = root / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    contents_path = appicon_dir / 'Contents.json'
    data = json.loads(contents_path.read_text())
    written = 0
    for item in data.get('images', []):
        filename, size_str, scale_str = item.get('filename'), item.get('size'), item.get('scale')
        if not filename or not size_str or not scale_str:
            continue
        pixels = round(float(size_str.split('x')[0]) * float(scale_str.rstrip('x')))
        master.resize((pixels,pixels), Image.Resampling.LANCZOS).save(appicon_dir / filename, 'PNG', optimize=True)
        written += 1
    if written == 0:
        raise SystemExit('Aucune icône iOS générée.')

print('Launcher icon generated:', bbox)
