from pathlib import Path

EXPECTED = "version: 11.6.60+220"
TARGET = "version: 11.6.61+221"

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.61: base version mismatch")
pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

home = Path("lib/screens/home_screen.dart")
s = home.read_text()

old_status = """        statusBg = reopened ? AppColors.serviceJour : AppColors.paperAlt;
        statusFg = AppColors.ink;
"""
new_status = """        statusBg = reopened ? const Color(0xFFB3261E) : AppColors.paperAlt;
        statusFg = reopened ? Colors.white : AppColors.ink;
"""
if old_status not in s:
    raise SystemExit("V11.6.61: reopened badge color anchor missing")
s = s.replace(old_status, new_status, 1)

old_row = """              if (canSubmit) ...[
                SizedBox(width: 8),
                _ValidateButton(appState: appState, month: month),
              ],
            ],
          ),
        ],
      ),
    );
"""
new_row = """              if (canSubmit) ...[
                SizedBox(width: 8),
                _ValidateButton(appState: appState, month: month),
              ],
            ],
          ),
          if (canSubmit) ...[
            const SizedBox(height: 5),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'Validation automatique : 7 jours après la publication ou le remplacement du planning officiel.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.inkSoft,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ],
      ),
    );
"""
if old_row not in s:
    raise SystemExit("V11.6.61: month status row anchor missing")
s = s.replace(old_row, new_row, 1)

old_reopened_detail = """          detail =
              'Motif : $reopenReason. Modifiez vos tuiles puis validez à nouveau le mois.';
"""
new_reopened_detail = """          detail =
              'Motif : $reopenReason. Modifiez vos tuiles puis validez à nouveau le mois. Sans validation manuelle, le calendrier sera automatiquement validé 7 jours après la publication ou le remplacement du planning officiel.';
"""
if old_reopened_detail not in s:
    raise SystemExit("V11.6.61: reopened detail anchor missing")
s = s.replace(old_reopened_detail, new_reopened_detail, 1)

old_draft_detail = """          detail =
              'Placez vos tuiles Service, Urgences et Congé puis validez définitivement le mois.';
"""
new_draft_detail = """          detail =
              'Placez vos tuiles Service, Urgences et Congé puis validez définitivement le mois. Sans validation manuelle, le calendrier sera automatiquement validé 7 jours après la publication ou le remplacement du planning officiel.';
"""
if old_draft_detail not in s:
    raise SystemExit("V11.6.61: draft detail anchor missing")
s = s.replace(old_draft_detail, new_draft_detail, 1)

home.write_text(s)

final = home.read_text()
checks = [
    "0xFFB3261E",
    "reopened ? Colors.white : AppColors.ink",
    "Validation automatique : 7 jours après la publication ou le remplacement du planning officiel.",
    "le calendrier sera automatiquement validé 7 jours après la publication ou le remplacement du planning officiel.",
]
for needle in checks:
    if needle not in final:
        raise SystemExit(f"V11.6.61: missing {needle!r}")

if TARGET not in pubspec.read_text():
    raise SystemExit("V11.6.61: version bump missing")

print("GardeFlow V11.6.61: auto-validation timing visible + reopened badge contrast fixed")
