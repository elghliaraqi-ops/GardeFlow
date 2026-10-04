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

# Apply the current one-time Practice information architecture cleanup using the
# repository's already-approved patch workflow.
subprocess.run(
    [sys.executable, 'ci/one_time_practice_hub_reorg.py'],
    cwd=ROOT,
    check=True,
)

print('Practice hub reorganization applied; current branding assets preserved.')
