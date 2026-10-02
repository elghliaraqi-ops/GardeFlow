from __future__ import annotations

import base64
import hashlib
import re
from pathlib import Path

ROOT = Path('.')
STAGE = ROOT / 'ci' / 'original_branding_assets'
BRANDING = ROOT / 'source' / 'assets' / 'branding'
BRANDING.mkdir(parents=True, exist_ok=True)

ASSETS = {
    'practice_banner_app.b64': (
        BRANDING / 'practice_banner.webp',
        'ea79fa374cbed514d9b53d78a305793294d5f9eda3fcdb84342fe3dc80fffe4f',
    ),
    'flowsuite_banner_app.b64': (
        BRANDING / 'flowsuite_banner.webp',
        'ed3b35ac2d72833173d274eb20b9b7701944ce3281e96111b609c2a25bbe5606',
    ),
    'practice_icon_app.b64': (
        BRANDING / 'practice_icon.webp',
        '72204e7abe24566ab175dfd46f31dcd3e9a0b76420053b6c7d91251dd669a567',
    ),
}

for staged_name, (target, expected_sha) in ASSETS.items():
    staged = STAGE / staged_name
    if not staged.exists():
        raise SystemExit(f'missing staged original branding asset: {staged}')
    data = base64.b64decode(staged.read_text().strip(), validate=True)
    actual_sha = hashlib.sha256(data).hexdigest()
    if actual_sha != expected_sha:
        raise SystemExit(
            f'asset checksum mismatch for {staged_name}: {actual_sha} != {expected_sha}'
        )
    target.write_bytes(data)

# Assets were staged only to bridge the original uploaded files into the repository.
# Remove every staging fragment so no Base64 payload remains in the final tree.
if STAGE.exists():
    for item in STAGE.iterdir():
        if item.is_file():
            item.unlink()
    try:
        STAGE.rmdir()
    except OSError:
        pass

# Declare the three real/source-derived image assets.
pubspec = ROOT / 'source' / 'pubspec.yaml'
p = pubspec.read_text()
anchor = '    - assets/branding/gardeflow_logo.png\n'
asset_lines = ''.join(
    f'    - assets/branding/{name}\n'
    for name in ('practice_banner.webp', 'flowsuite_banner.webp', 'practice_icon.webp')
)
if 'assets/branding/practice_icon.webp' not in p:
    if anchor not in p:
        raise SystemExit('pubspec branding anchor missing')
    p = p.replace(anchor, anchor + asset_lines, 1)
pubspec.write_text(p)

# Practice: remove the coded imitation and show only the real logo image.
practice = ROOT / 'source' / 'lib' / 'screens' / 'practice_screen.dart'
s = practice.read_text()
s = s.replace('const _PracticeBrandMark(),', 'const _PracticeOriginalLogo(),')
s = re.sub(
    r'\nclass _PracticeBrandMark extends StatelessWidget \{.*?\n\}\n\n(?=class _QcmCanonicalStatsStrip)',
    '\n',
    s,
    flags=re.S,
)
if 'class _PracticeOriginalLogo extends StatelessWidget' not in s:
    marker = 'class _QcmCanonicalStatsStrip extends StatelessWidget {'
    if marker not in s:
        raise SystemExit('QCM stats strip marker missing')
    widget = '''class _PracticeOriginalLogo extends StatelessWidget {
  const _PracticeOriginalLogo();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Align(
      alignment: Alignment.centerLeft,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.asset(
          'assets/branding/practice_icon.webp',
          width: 58,
          height: 58,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
        ),
      ),
    ),
  );
}

'''
    s = s.replace(marker, widget + marker, 1)
practice.write_text(s)

# Splash: remove both coded imitation chips and replace them with the two actual banners.
splash = ROOT / 'source' / 'lib' / 'screens' / 'splash_screen.dart'
z = splash.read_text()
z = z.replace('const _FlowSuiteSplashBrands(),', 'const _OriginalBrandBanners(),')
z = re.sub(
    r'\nclass _FlowSuiteSplashBrands extends StatelessWidget \{.*\Z',
    '\n',
    z,
    flags=re.S,
)
if 'class _OriginalBrandBanners extends StatelessWidget' not in z:
    z += '''
class _OriginalBrandBanners extends StatelessWidget {
  const _OriginalBrandBanners();

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        height: 72,
        width: 330,
        child: Image.asset(
          'assets/branding/flowsuite_banner.webp',
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      ),
      const SizedBox(height: 8),
      SizedBox(
        height: 88,
        width: 330,
        child: Image.asset(
          'assets/branding/practice_banner.webp',
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      ),
    ],
  );
}
'''
splash.write_text(z)

print('Original/source-derived FlowSuite + Practice assets installed; Flutter imitations removed.')
