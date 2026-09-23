from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    s = p.read_text()
    if old not in s:
        raise SystemExit(f"Anchor not found in {path}: {old[:120]!r}")
    p.write_text(s.replace(old, new, 1))


# AppUser persists the selected promotion without breaking old local state.
replace_once(
    "source/lib/models/app_user.dart",
    "  final String hospital;\n  final UserRole role;",
    "  final String hospital;\n  final int? promotionNumber;\n  final UserRole role;",
)
replace_once(
    "source/lib/models/app_user.dart",
    "    required this.hospital,\n    this.role = UserRole.medecin,",
    "    required this.hospital,\n    this.promotionNumber,\n    this.role = UserRole.medecin,",
)
replace_once(
    "source/lib/models/app_user.dart",
    "        'hospital': hospital,\n        'role': role.name,",
    "        'hospital': hospital,\n        'promotionNumber': promotionNumber,\n        'role': role.name,",
)
replace_once(
    "source/lib/models/app_user.dart",
    "      hospital: json['hospital'] as String,\n      role: UserRole.values.byName",
    "      hospital: json['hospital'] as String,\n      promotionNumber: (json['promotionNumber'] as num?)?.toInt() ??\n          (json['promotion_number'] as num?)?.toInt(),\n      role: UserRole.values.byName",
)

# Promotion catalogue: Promo 5, Zaghrari aliases, automatic year calculation,
# and one Urgences rule: Promo 7 cannot exchange with older cohorts.
p = Path("source/lib/data/intern_promotions.dart")
s = p.read_text()
if "static const Set<String> _promo5" not in s:
    anchor = "  static const Set<String> _promo6 = {"
    if anchor not in s:
        raise SystemExit("Promo 6 anchor not found")
    s = s.replace(
        anchor,
        "  static const Set<String> _promo5 = {\n"
        "    'najid saad', 'saad najid',\n"
        "  };\n\n"
        + anchor,
        1,
    )
old_zaghrari = "'wiame khalifi', 'yazid marfoq', 'zaghrari dahmane', 'zahid mohamed amine',"
new_zaghrari = "'wiame khalifi', 'yazid marfoq', 'zaghrari dahmane',\n    'zaghrari mohammed dahmane', 'zaghrari mohamed dahmane',\n    'mohammed dahmane zaghrari', 'mohamed dahmane zaghrari',\n    'dahmane mohammed zaghrari', 'dahmane mohamed zaghrari',\n    'zahid mohamed amine',"
if old_zaghrari not in s:
    raise SystemExit("Zaghrari anchor not found")
s = s.replace(old_zaghrari, new_zaghrari, 1)
tail_start = s.index("  static int? numberForNames")
s = s[:tail_start] + """  static int? numberForNames(String nom, String prenom) {
    final key = _key(nom, prenom);
    if (_promo7.contains(key)) return 7;
    if (_promo6.contains(key)) return 6;
    if (_promo5.contains(key)) return 5;

    // Tolère les comptes saisis avec Nom/Prénom inversés.
    final reverse = _key(prenom, nom);
    if (_promo7.contains(reverse)) return 7;
    if (_promo6.contains(reverse)) return 6;
    if (_promo5.contains(reverse)) return 5;
    return null;
  }

  static int? numberFor(AppUser? user) => user == null
      ? null
      : user.promotionNumber ?? numberForNames(user.nom, user.prenom);

  /// Promo 7 = 1re année, Promo 6 = 2e année, Promo 5 = 3e année, etc.
  static int? trainingYearForPromotion(int? promo) {
    if (promo == null || promo < 1 || promo > 7) return null;
    return 8 - promo;
  }

  static String? yearLabelForPromotion(int? promo) {
    final year = trainingYearForPromotion(promo);
    if (year == null) return null;
    return year == 1 ? '1re année' : '${year}e année';
  }

  static String? labelFor(AppUser? user) {
    final promo = numberFor(user);
    final year = yearLabelForPromotion(promo);
    if (promo == null || year == null) return null;
    return '$year · Promo $promo';
  }

  /// Pour les gardes d'Urgences, la première année (Promo 7) reste
  /// séparée des internes plus avancés. Les Promo 6, 5, 4... peuvent
  /// en revanche transférer/échanger entre elles.
  static bool crossYearBlocked(AppUser? a, AppUser? b) {
    final pa = numberFor(a);
    final pb = numberFor(b);
    if (pa == null || pb == null) return false;
    final aFirstYear = pa == 7;
    final bFirstYear = pb == 7;
    final aOlder = pa >= 1 && pa <= 6;
    final bOlder = pb >= 1 && pb <= 6;
    return (aFirstYear && bOlder) || (bFirstYear && aOlder);
  }

  /// Alias du planning officiel quand le compte contient plusieurs prénoms.
  /// Le compte « Mohammed Dahmane Zaghrari » doit reconnaître « Dahmane Zaghrari ».
  static Set<String> officialRosterAliasesFor(AppUser user) {
    final key = _key(user.nom, user.prenom);
    final reverse = _key(user.prenom, user.nom);
    const zaghrariKeys = <String>{
      'zaghrari mohammed dahmane',
      'zaghrari mohamed dahmane',
      'mohammed dahmane zaghrari',
      'mohamed dahmane zaghrari',
      'dahmane mohammed zaghrari',
      'dahmane mohamed zaghrari',
    };
    if (zaghrariKeys.contains(key) || zaghrariKeys.contains(reverse)) {
      return const <String>{'dahmane zaghrari', 'zaghrari dahmane'};
    }
    return const <String>{};
  }
}
"""
p.write_text(s)

# Registration UI: explicit promotion for juniors; year is derived automatically.
replace_once(
    "source/lib/screens/auth_screen.dart",
    "import '../data/hospitals.dart';\nimport '../data/services.dart';",
    "import '../data/hospitals.dart';\nimport '../data/intern_promotions.dart';\nimport '../data/services.dart';",
)
replace_once(
    "source/lib/screens/auth_screen.dart",
    "  MedicalGrade _regGrade = MedicalGrade.junior;",
    "  MedicalGrade _regGrade = MedicalGrade.junior;\n  int _regPromotion = 7;",
)
replace_once(
    "source/lib/screens/auth_screen.dart",
    "      grade: _regGrade,\n      hospital: _hospital,",
    "      grade: _regGrade,\n      hospital: _hospital,\n      promotionNumber: _regGrade == MedicalGrade.junior ? _regPromotion : null,",
)
replace_once(
    "source/lib/screens/auth_screen.dart",
    "Important : renseignez votre nom et prénom exactement comme ils apparaissent sur le PDF du planning de garde. Cela permet à GardeFlow de reconnaître automatiquement vos gardes.",
    "Important : renseignez vos nom et prénoms complets. GardeFlow rapproche automatiquement les variantes usuelles du planning officiel (par exemple un prénom composé abrégé).",
)
grade_block = """        Row(children: [
          Expanded(child: _gradeOption(MedicalGrade.junior, 'Junior')),
          SizedBox(width: 10),
          Expanded(child: _gradeOption(MedicalGrade.senior, 'Senior')),
        ]),
        SizedBox(height: 20),
        _GradientPrimaryButton"""
promotion_block = """        Row(children: [
          Expanded(child: _gradeOption(MedicalGrade.junior, 'Junior')),
          SizedBox(width: 10),
          Expanded(child: _gradeOption(MedicalGrade.senior, 'Senior')),
        ]),
        if (_regGrade == MedicalGrade.junior) ...[
          SizedBox(height: 16),
          Text('Promotion d’internat', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.inkSoft)),
          SizedBox(height: 8),
          DropdownButtonFormField<int>(
            value: _regPromotion,
            isExpanded: true,
            decoration: _glassInputDecoration(hint: 'Promotion', icon: Icons.school_outlined),
            items: List<int>.generate(7, (index) => 7 - index)
                .map((promo) => DropdownMenuItem<int>(
                      value: promo,
                      child: Text(
                        'Promo $promo · ${InternPromotions.yearLabelForPromotion(promo)}',
                        style: TextStyle(fontSize: 12.5),
                      ),
                    ))
                .toList(),
            onChanged: (value) => setState(() => _regPromotion = value ?? _regPromotion),
          ),
          SizedBox(height: 7),
          Text(
            'Votre année d’internat est calculée automatiquement à partir de la promotion.',
            style: TextStyle(fontSize: 10.8, height: 1.35, color: AppColors.inkFaint, fontWeight: FontWeight.w600),
          ),
        ],
        SizedBox(height: 20),
        _GradientPrimaryButton"""
replace_once("source/lib/screens/auth_screen.dart", grade_block, promotion_block)

# AppState carries the promotion to backend/local mode and enforces the same Urgences rule.
replace_once(
    "source/lib/state/app_state.dart",
    "required String service,required MedicalGrade grade,required String hospital}) async {",
    "required String service,required MedicalGrade grade,required String hospital,int? promotionNumber}) async {",
)
replace_once(
    "source/lib/state/app_state.dart",
    "    if(password.length<8)return 'Le mot de passe doit contenir au moins 8 caractères.';",
    "    if(password.length<8)return 'Le mot de passe doit contenir au moins 8 caractères.';\n"
    "    if(grade==MedicalGrade.junior&&(promotionNumber==null||promotionNumber<1||promotionNumber>7))return 'Sélectionnez votre promotion d’internat.';",
)
replace_once(
    "source/lib/state/app_state.dart",
    "password:password,service:service,grade:grade,hospital:hospital);",
    "password:password,service:service,grade:grade,hospital:hospital,promotionNumber:promotionNumber);",
)
replace_once(
    "source/lib/state/app_state.dart",
    "      service:service,grade:grade,hospital:hospital);",
    "      service:service,grade:grade,hospital:hospital,promotionNumber:promotionNumber);",
)
p = Path("source/lib/state/app_state.dart")
s = p.read_text()
s = s.replace(
    "Les transferts de gardes d’Urgences sont interdits entre première année (Promo 7) et deuxième année (Promo 6).",
    "Les gardes d’Urgences ne peuvent pas être transférées entre la première année (Promo 7) et les promotions plus anciennes (Promo 6, 5, 4…).",
)
s = s.replace(
    "Les échanges impliquant une garde d’Urgences sont interdits entre première année (Promo 7) et deuxième année (Promo 6).",
    "Les échanges impliquant une garde d’Urgences sont interdits entre la première année (Promo 7) et les promotions plus anciennes (Promo 6, 5, 4…).",
)
p.write_text(s)

# Supabase client: sign-up metadata + promotion field when profiles are reloaded.
replace_once(
    "source/lib/services/supabase_backend_service.dart",
    "    required String hospital,\n  }) async {",
    "    required String hospital,\n    int? promotionNumber,\n  }) async {",
)
replace_once(
    "source/lib/services/supabase_backend_service.dart",
    "        'hospital': hospital,\n      },",
    "        'hospital': hospital,\n        if (promotionNumber != null) 'promotion_number': promotionNumber,\n      },",
)
replace_once(
    "source/lib/services/supabase_backend_service.dart",
    ".select('id,nom,prenom,phone,role,service,medical_grade,hospital,account_status')",
    ".select('id,nom,prenom,phone,role,service,medical_grade,hospital,account_status,promotion_number')",
)
replace_once(
    "source/lib/services/supabase_backend_service.dart",
    "      hospital: j['hospital'] as String,\n      role: UserRole.values.byName",
    "      hospital: j['hospital'] as String,\n      promotionNumber: (j['promotion_number'] as num?)?.toInt(),\n      role: UserRole.values.byName",
)

# Official PDF recognition: explicit Dahmane Zaghrari alias in normal and disciplinary matching.
replace_once(
    "source/lib/services/official_roster_import_service.dart",
    "import '../models/app_user.dart';",
    "import '../data/intern_promotions.dart';\nimport '../models/app_user.dart';",
)
p = Path("source/lib/services/official_roster_import_service.dart")
s = p.read_text().replace("'parser_revision': 'v11.6.52-r1'", "'parser_revision': 'v11.6.70-r2'")
normal_variants = """      final variants = <String>{
        _normalizeName('${profile.prenom} ${profile.nom}'),
        _normalizeName('${profile.nom} ${profile.prenom}'),
      }..removeWhere((v) => v.isEmpty);"""
alias_variants = """      final variants = <String>{
        _normalizeName('${profile.prenom} ${profile.nom}'),
        _normalizeName('${profile.nom} ${profile.prenom}'),
        ...InternPromotions.officialRosterAliasesFor(profile).map(_normalizeName),
      }..removeWhere((v) => v.isEmpty);"""
if s.count(normal_variants) < 1:
    raise SystemExit("Expected profile variants block in official roster parser")
s = s.replace(normal_variants, alias_variants)
p.write_text(s)

# Exchange sheet copy follows the new cohort rule; Service exchanges stay unchanged.
p = Path("source/lib/screens/exchange_request_sheet.dart")
s = p.read_text()
s = s.replace(
    "Transfert Urgences : même hôpital et même promotion d’internat. Première année (Promo 7) et deuxième année (Promo 6) ne peuvent pas se transférer une garde d’Urgences. Le destinataire accepte, puis l’admin valide.",
    "Transfert Urgences : même hôpital. La Promo 7 (1re année) reste séparée des promotions plus anciennes. Les Promo 6, 5, 4… peuvent transférer entre elles. Le destinataire accepte, puis l’admin valide.",
)
s = s.replace(
    "Échange Urgences : même hôpital et même promotion d’internat. Première année (Promo 7) et deuxième année (Promo 6) ne peuvent pas échanger une garde d’Urgences entre elles. Validation admin obligatoire.",
    "Échange Urgences : même hôpital. La Promo 7 (1re année) ne peut échanger qu’avec la Promo 7. Les Promo 6, 5, 4… peuvent échanger entre elles. Validation admin obligatoire.",
)
s = s.replace(
    "'Aucun médecin compatible avec votre promotion pour cette garde d’Urgences.'",
    "'Aucun médecin compatible avec votre groupe d’ancienneté pour cette garde d’Urgences.'",
)
p.write_text(s)

# Focused regression tests for the requested cases.
Path("source/test/intern_promotions_test.dart").write_text("""import 'package:flutter_test/flutter_test.dart';
import 'package:huim6_planning/data/intern_promotions.dart';
import 'package:huim6_planning/models/app_user.dart';

AppUser user(String nom, String prenom, {int? promotion}) => AppUser(
      id: '$nom-$prenom',
      nom: nom,
      prenom: prenom,
      phone: '0600000000',
      passwordHash: '',
      passwordSalt: '',
      service: 'Imagerie médicale',
      grade: MedicalGrade.junior,
      hospital: 'Test',
      promotionNumber: promotion,
    );

void main() {
  test('Zaghrari account is Promo 6 and recognizes PDF short identity', () {
    final zaghrari = user('zaghrari', 'mohammed dahmane');
    expect(InternPromotions.numberFor(zaghrari), 6);
    expect(
      InternPromotions.officialRosterAliasesFor(zaghrari),
      contains('dahmane zaghrari'),
    );
  });

  test('Najid is Promo 5 and automatic training year is third year', () {
    final najid = user('NAJID', 'Saad');
    expect(InternPromotions.numberFor(najid), 5);
    expect(InternPromotions.trainingYearForPromotion(5), 3);
    expect(InternPromotions.labelFor(najid), '3e année · Promo 5');
  });

  test('Urgences isolates first year but allows older cohorts together', () {
    final promo7 = user('A', 'Seven', promotion: 7);
    final promo6 = user('B', 'Six', promotion: 6);
    final promo5 = user('C', 'Five', promotion: 5);
    final promo4 = user('D', 'Four', promotion: 4);

    expect(InternPromotions.crossYearBlocked(promo7, promo6), isTrue);
    expect(InternPromotions.crossYearBlocked(promo7, promo5), isTrue);
    expect(InternPromotions.crossYearBlocked(promo6, promo5), isFalse);
    expect(InternPromotions.crossYearBlocked(promo5, promo4), isFalse);
  });
}
""")

print("Promotion signup patch applied")
