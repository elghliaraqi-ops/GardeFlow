from __future__ import annotations

import base64
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path('.')
STAGE = ROOT / 'ci' / 'original_branding_assets'
BRANDING = ROOT / 'source' / 'assets' / 'branding'
BRANDING.mkdir(parents=True, exist_ok=True)

ASSETS = {
    'practice_banner_app.b64': BRANDING / 'practice_banner.webp',
    'practice_icon_app.b64': BRANDING / 'practice_icon.webp',
}

# Install only image files derived from the user's uploaded originals.
for staged_name, target in ASSETS.items():
    staged = STAGE / staged_name
    if staged.exists():
        encoded = ''.join(staged.read_text().split())
        data = base64.b64decode(encoded, validate=True)
        if not data.startswith(b'RIFF') or b'WEBP' not in data[:16]:
            raise SystemExit(f'invalid WebP branding asset: {staged_name}')
        target.write_bytes(data)
    elif not target.exists():
        raise SystemExit(f'missing Practice branding asset: {target}')

# Remove staging payloads after successful decode.
if STAGE.exists():
    for item in STAGE.iterdir():
        if item.is_file():
            item.unlink()
    try:
        STAGE.rmdir()
    except OSError:
        pass

# Practice body: the game/progression card must be first again.
practice = ROOT / 'source' / 'lib' / 'screens' / 'practice_screen.dart'
s = practice.read_text()
s = s.replace(
    '              const _PracticeOriginalLogo(),\n              const SizedBox(height: 12),\n',
    '',
)
s = s.replace('              const _PracticeOriginalLogo(),\n', '')
s = re.sub(
    r'\nclass _PracticeOriginalLogo extends StatelessWidget \{.*?\n\}\n\n(?=class _QcmCanonicalStatsStrip)',
    '\n',
    s,
    flags=re.S,
)
if '_PracticeOriginalLogo' in s:
    raise SystemExit('old Practice body logo placement still present')
practice.write_text(s)

# Global top bar: keep GardeFlow everywhere except on Practice.
home = ROOT / 'source' / 'lib' / 'screens' / 'home_screen.dart'
h = home.read_text()
old = '''          GardeFlowLogo(size: 38),
          SizedBox(width: 10),'''
new = '''          if (title == 'Practice')
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'assets/branding/practice_icon.webp',
                width: 38,
                height: 38,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
              ),
            )
          else
            GardeFlowLogo(size: 38),
          SizedBox(width: 10),'''
if "assets/branding/practice_icon.webp" not in h:
    if old not in h:
        raise SystemExit('global top bar logo anchor missing')
    h = h.replace(old, new, 1)
home.write_text(h)

# Splash continues to use actual image assets only; no Flutter-drawn logo imitation.
splash = ROOT / 'source' / 'lib' / 'screens' / 'splash_screen.dart'
z = splash.read_text()
for required in (
    'assets/branding/flowsuite_banner.webp',
    'assets/branding/practice_banner.webp',
):
    if required not in z:
        raise SystemExit(f'missing splash image asset reference: {required}')
for banned in ('_SplashBrandChip', '_FlowSuiteSplashBrands'):
    if banned in z:
        raise SystemExit(f'Flutter splash imitation still present: {banned}')

# Apply the current one-time Practice information architecture cleanup using the
# already-approved repository patch workflow.
subprocess.run(
    [sys.executable, 'ci/one_time_practice_hub_reorg.py'],
    cwd=ROOT,
    check=True,
)

print('Practice fixed: clean image assets, Practice icon in top bar, game card restored to top, hub hierarchy reorganized.')
