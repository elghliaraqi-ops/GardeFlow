from pathlib import Path

EXPECTED = "version: 11.6.43+203"
TARGET = "version: 11.6.44+204"

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.44: base version mismatch")
pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

auth = Path("lib/screens/auth_screen.dart")
s = auth.read_text()

method_marker = "Widget _buildRegisterForm()"
method_start = s.find(method_marker)
if method_start < 0:
    raise SystemExit("V11.6.44: _buildRegisterForm not found")

brace = s.find("{", method_start)
if brace < 0:
    raise SystemExit("V11.6.44: register method opening brace missing")

depth = 0
method_end = None
for i in range(brace, len(s)):
    if s[i] == "{":
        depth += 1
    elif s[i] == "}":
        depth -= 1
        if depth == 0:
            method_end = i + 1
            break

if method_end is None:
    raise SystemExit("V11.6.44: register method closing brace missing")

method = s[method_start:method_end]

if "nom et prénom exactement comme ils apparaissent" in method.lower():
    print("V11.6.44: registration planning-name notice already present")
else:
    children_anchor = "children: ["
    pos = method.find(children_anchor)
    if pos < 0:
        raise SystemExit("V11.6.44: register children anchor missing")
    insert_at = pos + len(children_anchor)

    notice = r"""
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          decoration: BoxDecoration(
            color: AppColors.brandSoft,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.brand.withOpacity(0.16),
            ),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: AppColors.brand,
                size: 20,
              ),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Important : renseignez votre nom et prénom exactement comme ils apparaissent sur le PDF du planning de garde. Cela permet à GardeFlow de reconnaître automatiquement vos gardes.',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 11.5,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
"""
    method = method[:insert_at] + notice + method[insert_at:]
    s = s[:method_start] + method + s[method_end:]
    auth.write_text(s)

print("GardeFlow V11.6.44: registration now explains using the exact PDF planning name")
