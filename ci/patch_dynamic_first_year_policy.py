from pathlib import Path
import re


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    s = p.read_text()
    if old not in s:
        raise SystemExit(f"Anchor not found in {path}: {old[:120]!r}")
    p.write_text(s.replace(old, new, 1))


# Registration: promotion becomes an open numeric field so future cohorts do
# not require an app update merely to add Promo 8, Promo 9, etc.
p = Path("source/lib/screens/auth_screen.dart")
s = p.read_text()
s = s.replace("import '../data/intern_promotions.dart';\n", "")
s = s.replace(
    "  final _regPasswordCtrl = TextEditingController();\n  String _regService = kServices.first;\n  MedicalGrade _regGrade = MedicalGrade.junior;\n  int _regPromotion = 7;",
    "  final _regPasswordCtrl = TextEditingController();\n  final _regPromotionCtrl = TextEditingController();\n  String _regService = kServices.first;\n  MedicalGrade _regGrade = MedicalGrade.junior;",
)
s = s.replace(
    "    _regPhoneCtrl.dispose();\n    _regPasswordCtrl.dispose();",
    "    _regPhoneCtrl.dispose();\n    _regPasswordCtrl.dispose();\n    _regPromotionCtrl.dispose();",
)
s = s.replace(
    "      promotionNumber: _regGrade == MedicalGrade.junior ? _regPromotion : null,",
    "      promotionNumber: _regGrade == MedicalGrade.junior\n          ? int.tryParse(_regPromotionCtrl.text.trim())\n          : null,",
)
pattern = re.compile(
    r"        if \(_regGrade == MedicalGrade\.junior\) \.\.\.\[\n"
    r"          SizedBox\(height: 16\),\n"
    r"          Text\('Promotion d’internat'.*?\n"
    r"        \],\n"
    r"        SizedBox\(height: 20\),",
    re.S,
)
replacement = """        if (_regGrade == MedicalGrade.junior) ...[
          SizedBox(height: 16),
          Text('Promotion d’internat', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.inkSoft)),
          SizedBox(height: 8),
          TextField(
            controller: _regPromotionCtrl,
            keyboardType: TextInputType.number,
            decoration: _glassInputDecoration(
              hint: 'Numéro de promotion (ex. 7)',
              icon: Icons.school_outlined,
            ),
          ),
          SizedBox(height: 7),
          Text(
            'La promotion la plus récente devient automatiquement la 1re année. Les années d’internat sont recalculées sans modifier l’application.',
            style: TextStyle(fontSize: 10.8, height: 1.35, color: AppColors.inkFaint, fontWeight: FontWeight.w600),
          ),
        ],
        SizedBox(height: 20),"""
s2, count = pattern.subn(replacement, s, count=1)
if count != 1:
    raise SystemExit("Promotion signup UI block not found exactly once")
p.write_text(s2)

# Backend client: read the global first-year promotion configuration.
p = Path("source/lib/services/supabase_backend_service.dart")
s = p.read_text()
anchor = "  Future<List<PasswordResetRequest>> fetchPasswordResetRequests() async {"
method = """  Future<int> fetchCurrentFirstYearPromotion() async {
    final row = await client
        .from('internship_promotion_config')
        .select('current_first_year_promotion')
        .eq('id', 1)
        .single();
    final value = (row['current_first_year_promotion'] as num?)?.toInt();
    return value != null && value > 0 ? value : 7;
  }

"""
if "fetchCurrentFirstYearPromotion" not in s:
    if anchor not in s:
        raise SystemExit("Backend promotion config insertion anchor missing")
    s = s.replace(anchor, method + anchor, 1)
p.write_text(s)

# App state: cache the global first-year cohort, fall back to the highest active
# local promotion, and enforce the restriction for every transfer/exchange.
p = Path("source/lib/state/app_state.dart")
s = p.read_text()
users_anchor = "  final List<AppUser> _users=[];\n  List<AppUser> get users=>List.unmodifiable(_users);\n  AppUser? currentUser;"
users_replacement = """  final List<AppUser> _users=[];
  List<AppUser> get users=>List.unmodifiable(_users);
  int _currentFirstYearPromotion=7;
  int get currentFirstYearPromotion {
    final local=InternPromotions.highestPromotion(_users);
    if(!backendEnabled)return local??_currentFirstYearPromotion;
    return _currentFirstYearPromotion>0?_currentFirstYearPromotion:(local??7);
  }
  bool promotionExchangeBlocked(AppUser? a,AppUser? b)=>InternPromotions.crossYearBlocked(
    a,b,firstYearPromotion:currentFirstYearPromotion);
  AppUser? currentUser;"""
if "promotionExchangeBlocked" not in s:
    if users_anchor not in s:
        raise SystemExit("AppState users anchor missing")
    s = s.replace(users_anchor, users_replacement, 1)

s = s.replace(
    "    final profilesFuture = backend.fetchVisibleProfiles();\n    final planningFuture = backend.fetchPlanning();",
    "    final profilesFuture = backend.fetchVisibleProfiles();\n    final firstYearPromotionFuture = backend.fetchCurrentFirstYearPromotion();\n    final planningFuture = backend.fetchPlanning();",
    1,
)
s = s.replace(
    "    final profiles = await profilesFuture;\n    final planning = await planningFuture;",
    "    final profiles = await profilesFuture;\n    final firstYearPromotion = await firstYearPromotionFuture;\n    final planning = await planningFuture;",
    1,
)
s = s.replace(
    "    _users\n      ..clear()\n      ..addAll(profiles);",
    "    _users\n      ..clear()\n      ..addAll(profiles);\n    _currentFirstYearPromotion=firstYearPromotion;",
    1,
)
s = s.replace(
    "if(grade==MedicalGrade.junior&&(promotionNumber==null||promotionNumber<1||promotionNumber>7))return 'Sélectionnez votre promotion d’internat.';",
    "if(grade==MedicalGrade.junior&&(promotionNumber==null||promotionNumber<1||promotionNumber>999))return 'Renseignez un numéro de promotion valide.';",
)
s = s.replace("InternPromotions.crossYearBlocked(me,targetUser)", "promotionExchangeBlocked(me,targetUser)")
s = s.replace("InternPromotions.crossYearBlocked(fromUser,toUser)", "promotionExchangeBlocked(fromUser,toUser)")
s = s.replace(
    "if(entry.shiftId.startsWith('urg-')&&promotionExchangeBlocked(me,targetUser))return 'Les gardes d’Urgences ne peuvent pas être transférées entre la première année (Promo 7) et les promotions plus anciennes (Promo 6, 5, 4…).';",
    "if(promotionExchangeBlocked(me,targetUser))return 'La promotion de première année (Promo $currentFirstYearPromotion) ne peut transférer des gardes qu’avec la même promotion.';",
)
s = s.replace(
    "    final sourceIsUrgence=entry.shiftId.startsWith('urg-');\n    final targetIsUrgence=targetEntry.shiftId.startsWith('urg-');\n    final targetUser=_users.where((u)=>u.id==target.id||u.phone==target.phone).firstOrNull;\n    if((sourceIsUrgence||targetIsUrgence)&&promotionExchangeBlocked(me,targetUser)){\n      return 'Les échanges impliquant une garde d’Urgences sont interdits entre la première année (Promo 7) et les promotions plus anciennes (Promo 6, 5, 4…).';\n    }",
    "    final targetUser=_users.where((u)=>u.id==target.id||u.phone==target.phone).firstOrNull;\n    if(promotionExchangeBlocked(me,targetUser)){\n      return 'La promotion de première année (Promo $currentFirstYearPromotion) ne peut échanger des gardes qu’avec la même promotion.';\n    }",
)
s = s.replace(
    "    final involvesUrgence=source.shiftId.startsWith('urg-')||target.shiftId.startsWith('urg-');\n    if(involvesUrgence&&promotionExchangeBlocked(fromUser,toUser))return 'Les échanges impliquant une garde d’Urgences sont interdits entre la première année (Promo 7) et les promotions plus anciennes (Promo 6, 5, 4…).';",
    "    if(promotionExchangeBlocked(fromUser,toUser))return 'La promotion de première année (Promo $currentFirstYearPromotion) ne peut échanger des gardes qu’avec la même promotion.';",
)
p.write_text(s)

# Exchange sheet: use AppState's dynamic policy for all guards, not only Urgences.
p = Path("source/lib/screens/exchange_request_sheet.dart")
s = p.read_text()
s = s.replace(
    "      if (sourceIsUrgence && InternPromotions.crossYearBlocked(me, targetUser)) {",
    "      if (state.promotionExchangeBlocked(me, targetUser)) {",
)
s = s.replace(
    "    final crossYearWithSelected =\n        InternPromotions.crossYearBlocked(me, selectedDoctorUser);",
    "    final crossYearWithSelected =\n        state.promotionExchangeBlocked(me, selectedDoctorUser);",
)
s = s.replace(
    "            final targetIsUrgence = e.shiftId.startsWith('urg-');\n            if (targetIsService && selectedDoctor.service != state.currentUser?.service) return false;\n            if (crossYearWithSelected && (sourceIsUrgence || targetIsUrgence)) return false;",
    "            if (targetIsService && selectedDoctor.service != state.currentUser?.service) return false;\n            if (crossYearWithSelected) return false;",
)
s = s.replace(
    "    final promotionLabel = InternPromotions.labelFor(me);",
    "    final promotionLabel = InternPromotions.labelFor(\n      me,\n      firstYearPromotion: state.currentFirstYearPromotion,\n    );",
)
old_notice = """              text: _mode == _Mode.transfer
                  ? sourceIsUrgence
                      ? 'Transfert Urgences : même hôpital. La Promo 7 (1re année) reste séparée des promotions plus anciennes. Les Promo 6, 5, 4… peuvent transférer entre elles. Le destinataire accepte, puis l’admin valide.'
                      : 'Transfert Service : même hôpital. Les transferts de garde de Service restent possibles entre Promo 6 et Promo 7. Le destinataire accepte, puis l’admin valide.'
                  : sourceIsService
                      ? 'Échange Service : uniquement avec un médecin de votre service. Les échanges de Service restent possibles entre Promo 6 et Promo 7. Si les deux gardes sont de Service, l’échange est appliqué dès l’acceptation du collègue, sans validation admin.'
                      : 'Échange Urgences : même hôpital. La Promo 7 (1re année) ne peut échanger qu’avec la Promo 7. Les Promo 6, 5, 4… peuvent échanger entre elles. Validation admin obligatoire.',"""
new_notice = """              text: _mode == _Mode.transfer
                  ? sourceIsService
                      ? 'Transfert Service : même hôpital. La Promo ${state.currentFirstYearPromotion} (1re année) ne peut transférer qu’avec la même promotion. Les promotions antérieures peuvent transférer entre elles. Le destinataire accepte, puis l’admin valide.'
                      : 'Transfert Urgences : même hôpital. La Promo ${state.currentFirstYearPromotion} (1re année) ne peut transférer qu’avec la même promotion. Les promotions antérieures peuvent transférer entre elles. Le destinataire accepte, puis l’admin valide.'
                  : sourceIsService
                      ? 'Échange Service : uniquement avec un médecin de votre service. La Promo ${state.currentFirstYearPromotion} (1re année) ne peut échanger qu’avec la même promotion. Les promotions antérieures peuvent échanger entre elles. Entre deux gardes de Service, pas de validation admin.'
                      : 'Échange Urgences : même hôpital. La Promo ${state.currentFirstYearPromotion} (1re année) ne peut échanger qu’avec la même promotion. Les promotions antérieures peuvent échanger entre elles. Validation admin obligatoire.',"""
if old_notice not in s:
    raise SystemExit("Exchange rule notice anchor missing")
s = s.replace(old_notice, new_notice, 1)
s = s.replace(
    "                rawTargets.isNotEmpty && sourceIsUrgence\n                    ? 'Aucun médecin compatible avec votre groupe d’ancienneté pour cette garde d’Urgences.'",
    "                rawTargets.isNotEmpty\n                    ? 'Aucun médecin compatible avec votre groupe d’ancienneté pour cette garde.'",
)
s = s.replace(
    "                          final crossYear = InternPromotions.crossYearBlocked(me, doctorUser);",
    "                          final crossYear = state.promotionExchangeBlocked(me, doctorUser);",
)
s = s.replace(
    "                            final targetIsUrgence = e.shiftId.startsWith('urg-');\n                            if (targetIsService && doctor.service != state.currentUser?.service) return false;\n                            if (crossYear && (sourceIsUrgence || targetIsUrgence)) return false;",
    "                            if (targetIsService && doctor.service != state.currentUser?.service) return false;\n                            if (crossYear) return false;",
)
p.write_text(s)

# Ensure no obsolete fixed-Promo-7 business-rule text remains in the two edited files.
for path in ["source/lib/state/app_state.dart", "source/lib/screens/exchange_request_sheet.dart"]:
    text = Path(path).read_text()
    if "Promo 7 (1re année)" in text or "Première année (Promo 7)" in text:
        raise SystemExit(f"Fixed Promo 7 policy still present in {path}")
