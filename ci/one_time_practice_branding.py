from __future__ import annotations

import base64
import re
from pathlib import Path

ROOT = Path('.')
STAGE = ROOT / 'ci' / 'original_branding_assets'
BRANDING = ROOT / 'source' / 'assets' / 'branding'
BRANDING.mkdir(parents=True, exist_ok=True)

ASSETS = {
    'practice_banner_app.b64': BRANDING / 'practice_banner.webp',
    'flowsuite_banner_app.b64': BRANDING / 'flowsuite_banner.webp',
    'practice_icon_app.b64': BRANDING / 'practice_icon.webp',
}

# These Base64 files were produced directly from the user's uploaded artwork,
# only resized/compressed for mobile delivery. They are not redraws or Flutter imitations.
for staged_name, target in ASSETS.items():
    staged = STAGE / staged_name
    if not staged.exists():
        raise SystemExit(f'missing staged branding asset: {staged}')
    data = base64.b64decode(staged.read_text().strip())
    if not data.startswith(b'RIFF') or b'WEBP' not in data[:16]:
        raise SystemExit(f'invalid WebP branding asset: {staged_name}')
    target.write_bytes(data)

# Remove temporary transport files, including any obsolete fragment.
if STAGE.exists():
    for item in STAGE.iterdir():
        if item.is_file():
            item.unlink()
    try:
        STAGE.rmdir()
    except OSError:
        pass

pubspec = ROOT / 'source' / 'pubspec.yaml'
p = pubspec.read_text()
anchor = '    - assets/branding/gardeflow_logo.png\n'
entries = [
    '    - assets/branding/practice_banner.webp\n',
    '    - assets/branding/flowsuite_banner.webp\n',
    '    - assets/branding/practice_icon.webp\n',
]
if entries[0] not in p:
    if anchor not in p:
        raise SystemExit('pubspec branding anchor missing')
    p = p.replace(anchor, anchor + ''.join(entries), 1)
pubspec.write_text(p)

practice = ROOT / 'source' / 'lib' / 'screens' / 'practice_screen.dart'
s = practice.read_text()
s = s.replace('const _PracticeBrandMark(),', 'const _PracticeOriginalLogo(),')
# Remove the previous code-generated imitation only.
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

splash = ROOT / 'source' / 'lib' / 'screens' / 'splash_screen.dart'
z = splash.read_text()
z = z.replace('const _FlowSuiteSplashBrands(),', 'const _OriginalBrandBanners(),')
# The imitation classes are at the end of the file; remove them entirely.
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

print('Practice/FlowSuite source artwork installed; Flutter-coded imitations removed.')
