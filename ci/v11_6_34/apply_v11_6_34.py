from pathlib import Path
import shutil

EXPECTED = "version: 11.6.33+193"
TARGET = "version: 11.6.34+194"
ASSET = "assets/branding/elghali_signature.webp"

repo_root = Path(__file__).resolve().parents[2]
source_asset = repo_root / ASSET
target_asset = Path(ASSET)

if not source_asset.exists():
    raise SystemExit("V11.6.34: signature asset missing from repository")

target_asset.parent.mkdir(parents=True, exist_ok=True)
shutil.copyfile(source_asset, target_asset)

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.34: base version mismatch")
pub = pub.replace(EXPECTED, TARGET, 1)

asset_line = "    - assets/branding/elghali_signature.webp\n"
if asset_line not in pub:
    anchor = "    - assets/branding/gardeflow_logo.png\n"
    if anchor not in pub:
        raise SystemExit("V11.6.34: pubspec branding anchor missing")
    pub = pub.replace(anchor, anchor + asset_line, 1)

pubspec.write_text(pub)

profile = Path("lib/screens/profile_screen.dart")
text = profile.read_text()

old = """        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _logout(context),
            icon: const Icon(Icons.logout_rounded, color: AppColors.danger),
            label: const Text('Se déconnecter', style: TextStyle(color: AppColors.danger)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.danger.withOpacity(0.28)),
              backgroundColor: AppColors.card,
            ),
          ),
        ),
      ],"""

new = """        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _logout(context),
            icon: const Icon(Icons.logout_rounded, color: AppColors.danger),
            label: const Text('Se déconnecter', style: TextStyle(color: AppColors.danger)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.danger.withOpacity(0.28)),
              backgroundColor: AppColors.card,
            ),
          ),
        ),
        const SizedBox(height: 28),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Opacity(
                opacity: 0.92,
                child: Image.asset(
                  'assets/branding/elghali_signature.webp',
                  width: 190,
                  height: 88,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                'Elghali Production © 2026',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.inkFaint,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.25,
                ),
              ),
            ],
          ),
        ),
      ],"""

if old not in text:
    raise SystemExit("V11.6.34: profile footer anchor not found")

profile.write_text(text.replace(old, new, 1))

print("GardeFlow V11.6.34: signature Elghali + Elghali Production © 2026")
