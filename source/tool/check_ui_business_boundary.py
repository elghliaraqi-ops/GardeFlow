"""Fail if the UI refactor changes a baseline model, service, state or SQL file."""
from pathlib import Path
import hashlib, json
root = Path(__file__).resolve().parents[2]
baseline = json.loads((root / 'docs/ux-business-baseline.json').read_text())
changed = [name for name, digest in baseline.items()
           if not (root / name).exists() or hashlib.sha256((root / name).read_bytes()).hexdigest() != digest]
if changed:
    raise SystemExit('Business boundary changed: ' + ', '.join(changed))
print(f'{len(baseline)} business/backend files unchanged.')
