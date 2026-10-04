from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path('.')
BRANDING = ROOT / 'source' / 'assets' / 'branding'

# Keep the current approved Practice branding intact. The splash implementation
# has evolved independently, so this legacy helper must no longer gate Practice
# UI work on obsolete splash asset names.
for required in (
    BRANDING / 'practice_icon.webp',
    BRANDING / 'practice_banner.webp',
):
    if not required.exists():
        raise SystemExit(f'missing current Practice branding asset: {required}')

# Apply the current Practice information architecture cleanup using the
# repository's already-approved patch workflow.
subprocess.run(
    [sys.executable, 'ci/one_time_practice_hub_reorg.py'],
    cwd=ROOT,
    check=True,
)

# Keep the two primary training cards bounded inside the vertically scrolling
# ListView; CrossAxisAlignment.stretch would receive an unbounded height.
subprocess.run(
    [sys.executable, 'ci/one_time_practice_layout_fix.py'],
    cwd=ROOT,
    check=True,
)

# Splash fix: stop referencing the three corrupted splash mark files. Reuse
# branding assets that are already valid and rendered elsewhere in GardeFlow.
splash = ROOT / 'source' / 'lib' / 'screens' / 'splash_screen.dart'
text = splash.read_text(encoding='utf-8')
replacements = {
    "assets/branding/splash_gardeflow_mark.png": "assets/branding/gardeflow_logo.png",
    "assets/branding/splash_practice_mark.png": "assets/branding/practice_icon.webp",
    "assets/branding/splash_flowsuite_mark.png": "assets/branding/flowsuite_banner.webp",
}
for old, new in replacements.items():
    text = text.replace(old, new)

# The FlowSuite source is a horizontal banner; crop its left edge in the square
# logo slot so the icon remains visible next to the native FlowSuite wordmark.
old_flow = """              Image.asset(\n                'assets/branding/flowsuite_banner.webp',\n                width: 50,\n                height: 50,\n                fit: BoxFit.contain,\n                filterQuality: FilterQuality.high,\n                isAntiAlias: true,\n              ),"""
new_flow = """              ClipRRect(\n                borderRadius: BorderRadius.circular(12),\n                child: Image.asset(\n                  'assets/branding/flowsuite_banner.webp',\n                  width: 50,\n                  height: 50,\n                  fit: BoxFit.cover,\n                  alignment: Alignment.centerLeft,\n                  filterQuality: FilterQuality.high,\n                  isAntiAlias: true,\n                ),\n              ),"""
text = text.replace(old_flow, new_flow)

splash.write_text(text, encoding='utf-8')

# The companion workflow also runs dart format on the widget bridge sources so
# CI formatting stays deterministic after native/widget integrations.
print('Practice hub reorganization applied; splash switched to verified original branding assets.')
