from pathlib import Path
import base64
import io
import tarfile

EXPECTED = "version: 11.6.17+177"
TARGET = "version: 11.6.18+178"

pubspec = Path("pubspec.yaml")
text = pubspec.read_text()
if EXPECTED not in text:
    raise SystemExit("V11.6.18: base version mismatch")
pubspec.write_text(text.replace(EXPECTED, TARGET, 1))

base = Path(__file__).parent
parts = sorted(base.glob("payload.part*.b64"))
if not parts:
    raise SystemExit("V11.6.18: payload chunks missing")

payload = "".join(part.read_text().strip() for part in parts)
archive = base64.b64decode(payload, validate=True)
with tarfile.open(fileobj=io.BytesIO(archive), mode="r:gz") as tf:
    tf.extractall(".", filter="data")

print(f"GardeFlow V11.6.18 complete main-interface redesign applied ({len(parts)} chunks)")
