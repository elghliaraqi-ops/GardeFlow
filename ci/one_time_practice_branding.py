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

# Install the image assets from the user's original uploaded artwork when staged.
# On later clean-up runs, keep the already-installed files rather than redrawing anything.
for staged_name, target in ASSETS.items():
    staged = STAGE / staged_name
    if staged.exists():
        encoded = staged.read_text().strip()
        if len(encoded) % 4 == 1:
            encoded = encoded[:-1]
        data = base64.b64decode(encoded)
        if not data.startswith(b'RIFF') or b'WEBP' not in data[:16]:
            raise SystemExit(f'invalid WebP branding asset: {staged_name}')
        target.write_bytes(data)
    elif not target.exists():
        raise SystemExit(f'missing original branding asset: {target}')

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

# Never keep the former Flutter-drawn Practice imitation.
s = s.replace('const _PracticeBrandMark(),', 'const _PracticeOriginalLogo(),')
s = re.sub(
    r'\nclass _PracticeBrandMark extends StatelessWidget \{.*?\n\}\n\n(?=class _QcmCanonicalStatsStrip)',
    '\n',
    s,
    flags=re.S,
)

# Remove the old mid-page placement, then put the real image logo at the top of Practice.
old_mid = '''              const SizedBox(height: 20),
              const _PracticeOriginalLogo(),
              const SizedBox(height: 16),
              const _PracticeHubSectionHeader(
                icon: Icons.sports_esports_rounded,'''
new_mid = '''              const SizedBox(height: 20),
              const _PracticeHubSectionHeader(
                icon: Icons.sports_esports_rounded,'''
s = s.replace(old_mid, new_mid, 1)

# Remove any remaining layout call before inserting one canonical top placement.
s = s.replace('              const _PracticeOriginalLogo(),\n', '')
top_anchor = '''            children: [
              _PracticeGameHeader('''
top_with_logo = '''            children: [
              const _PracticeOriginalLogo(),
              const SizedBox(height: 12),
              _PracticeGameHeader('''
if top_anchor not in s:
    raise SystemExit('Practice top layout anchor missing')
s = s.replace(top_anchor, top_with_logo, 1)

# Normalize the mini logo widget: image asset only, no gradient/icon/text reconstruction.
logo_start = s.find('class _PracticeOriginalLogo extends StatelessWidget')
logo_end_marker = 'class _QcmCanonicalStatsStrip extends StatelessWidget {'
logo_end = s.find(logo_end_marker, logo_start)
if logo_start == -1 or logo_end == -1:
    raise SystemExit('Practice original logo widget marker missing')
logo_widget = '''class _PracticeOriginalLogo extends StatelessWidget {
  const _PracticeOriginalLogo();

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Semantics(
      label: 'Practice',
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.asset(
          'assets/branding/practice_icon.webp',
          width: 52,
          height: 52,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
        ),
      ),
    ),
  );
}

'''
s = s[:logo_start] + logo_widget + s[logo_end:]
if '_PracticeBrandMark' in s:
    raise SystemExit('Flutter Practice imitation still present')
practice.write_text(s)

splash = ROOT / 'source' / 'lib' / 'screens' / 'splash_screen.dart'
z = splash.read_text()
z = z.replace('const _FlowSuiteSplashBrands(),', 'const _OriginalBrandBanners(),')

# Remove any former code-generated FlowSuite/Practice imitation widgets if present.
z = re.sub(
    r'\nclass _FlowSuiteSplashBrands extends StatelessWidget \{.*\Z',
    '\n',
    z,
    flags=re.S,
)

banner_start = z.find('class _OriginalBrandBanners extends StatelessWidget')
if banner_start != -1:
    z = z[:banner_start]

z += '''class _OriginalBrandBanners extends StatelessWidget {
  const _OriginalBrandBanners();

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        height: 92,
        width: 350,
        child: Image.asset(
          'assets/branding/flowsuite_banner.webp',
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      ),
      const SizedBox(height: 8),
      SizedBox(
        height: 118,
        width: 350,
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

for banned in ('_SplashBrandChip', '_FlowSuiteSplashBrands'):
    if banned in z:
        raise SystemExit(f'Flutter splash imitation still present: {banned}')
for required in (
    'assets/branding/flowsuite_banner.webp',
    'assets/branding/practice_banner.webp',
):
    if required not in z:
        raise SystemExit(f'missing splash image asset: {required}')
splash.write_text(z)

print('Original Practice/FlowSuite image assets active; all Flutter logo imitations removed.')
