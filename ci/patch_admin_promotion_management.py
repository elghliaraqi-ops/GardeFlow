from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f"anchor not found: {label}")
    return text.replace(old, new, 1)


# auth_screen.dart
p = Path('source/lib/screens/auth_screen.dart')
s = p.read_text()
s = replace_once(
    s,
    "import '../data/hospitals.dart';\nimport '../data/services.dart';",
    "import '../data/hospitals.dart';\nimport '../data/intern_promotions.dart';\nimport '../data/services.dart';",
    'auth import intern promotions',
)
s = replace_once(
    s,
    "  final _regPromotionCtrl = TextEditingController();\n",
    "  int? _regPromotion;\n",
    'auth promotion state',
)
s = replace_once(
    s,
    "    _regPromotionCtrl.dispose();\n",
    "",
    'auth promotion controller dispose',
)
s = replace_once(
    s,
    "    _entranceController.forward();\n",
    "    _entranceController.forward();\n    WidgetsBinding.instance.addPostFrameCallback((_) {\n      if (mounted) context.read<AppState>().refreshPromotionConfig();\n    });\n",
    'auth public promotion refresh',
)
s = replace_once(
    s,
    "      promotionNumber: _regGrade == MedicalGrade.junior\n          ? int.tryParse(_regPromotionCtrl.text.trim())\n          : null,",
    "      promotionNumber: _regGrade == MedicalGrade.junior\n          ? (_regPromotion ?? appState.currentFirstYearPromotion)\n          : null,",
    'auth submit promotion',
)
s = replace_once(
    s,
    "  Widget _buildRegisterForm() {\n    return Column(",
    "  Widget _buildRegisterForm() {\n    final appState = context.watch<AppState>();\n    final latestPromotion = appState.currentFirstYearPromotion;\n    final selectedPromotion = _regPromotion != null &&\n            _regPromotion! >= 1 &&\n            _regPromotion! <= latestPromotion\n        ? _regPromotion!\n        : latestPromotion;\n    final promotions = List<int>.generate(\n      latestPromotion,\n      (index) => latestPromotion - index,\n    );\n\n    return Column(",
    'auth register computed promotions',
)
old_promo_field = """        if (_regGrade == MedicalGrade.junior) ...[
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
        ],"""
new_promo_field = """        if (_regGrade == MedicalGrade.junior) ...[
          SizedBox(height: 16),
          Text('Promotion d’internat', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.inkSoft)),
          SizedBox(height: 8),
          DropdownButtonFormField<int>(
            value: selectedPromotion,
            isExpanded: true,
            decoration: _glassInputDecoration(
              hint: 'Promotion',
              icon: Icons.school_outlined,
            ),
            items: promotions.map((promo) {
              final year = InternPromotions.yearLabelForPromotion(
                promo,
                firstYearPromotion: latestPromotion,
              );
              return DropdownMenuItem<int>(
                value: promo,
                child: Text(
                  'Promo $promo${year == null ? '' : ' · $year'}',
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: (value) => setState(() => _regPromotion = value),
          ),
          SizedBox(height: 7),
          Text(
            'La Promo $latestPromotion est actuellement la 1re année. Une nouvelle promotion n’apparaît ici qu’après son ajout par un administrateur.',
            style: TextStyle(fontSize: 10.8, height: 1.35, color: AppColors.inkFaint, fontWeight: FontWeight.w600),
          ),
        ],"""
s = replace_once(s, old_promo_field, new_promo_field, 'auth promotion dropdown')
p.write_text(s)


# supabase_backend_service.dart
p = Path('source/lib/services/supabase_backend_service.dart')
s = p.read_text()
old_backend = """  Future<int> fetchCurrentFirstYearPromotion() async {
    final row = await client
        .from('internship_promotion_config')
        .select('current_first_year_promotion')
        .eq('id', 1)
        .single();
    final value = (row['current_first_year_promotion'] as num?)?.toInt();
    return value != null && value > 0 ? value : 7;
  }
"""
new_backend = old_backend + """
  Future<int> adminAddInternshipPromotion() async {
    final result = await client.rpc('admin_add_internship_promotion');
    final value = result is num
        ? result.toInt()
        : int.tryParse(result?.toString() ?? '');
    if (value == null || value < 1) {
      throw StateError('La nouvelle promotion n’a pas pu être créée.');
    }
    return value;
  }
"""
s = replace_once(s, old_backend, new_backend, 'backend admin add promotion rpc')
p.write_text(s)


# app_state.dart
p = Path('source/lib/state/app_state.dart')
s = p.read_text()
old_state = """  int _currentFirstYearPromotion=7;
  int get currentFirstYearPromotion {
    final local=InternPromotions.highestPromotion(_users);
    if(!backendEnabled)return local??_currentFirstYearPromotion;
    return _currentFirstYearPromotion>0?_currentFirstYearPromotion:(local??7);
  }
  bool promotionExchangeBlocked(AppUser? a,AppUser? b)=>InternPromotions.crossYearBlocked(
    a,b,firstYearPromotion:currentFirstYearPromotion);
"""
new_state = """  int _currentFirstYearPromotion=7;
  int get currentFirstYearPromotion {
    final local=InternPromotions.highestPromotion(_users);
    if(local!=null && local>_currentFirstYearPromotion)return local;
    return _currentFirstYearPromotion>0?_currentFirstYearPromotion:(local??7);
  }

  Future<void> refreshPromotionConfig() async {
    if(!backendEnabled)return;
    try {
      final value=await SupabaseBackendService.instance.fetchCurrentFirstYearPromotion();
      if(value>0 && value!=_currentFirstYearPromotion){
        _currentFirstYearPromotion=value;
        notifyListeners();
      }
    } catch(e) {
      debugPrint('Configuration des promotions indisponible: $e');
    }
  }

  Future<String?> adminAddPromotion() async {
    final me=currentUser;
    if(me==null || me.role!=UserRole.admin){
      return 'Cette action est réservée aux administrateurs.';
    }
    try {
      if(backendEnabled){
        _currentFirstYearPromotion=await SupabaseBackendService.instance.adminAddInternshipPromotion();
      }else{
        _currentFirstYearPromotion=currentFirstYearPromotion+1;
      }
      await _persistNow();
      notifyListeners();
      return null;
    } catch(e) {
      final text=e.toString();
      return text.startsWith('StateError: ') ? text.substring(12) : text;
    }
  }

  bool promotionExchangeBlocked(AppUser? a,AppUser? b)=>InternPromotions.crossYearBlocked(
    a,b,firstYearPromotion:currentFirstYearPromotion);
"""
s = replace_once(s, old_state, new_state, 'app state promotion management')
p.write_text(s)


# admin_screen.dart
p = Path('source/lib/screens/admin_screen.dart')
s = p.read_text()
old_summary = """            _AdminSummary(
              pendingAccounts: appState.pendingUsers.length,
              pendingExchanges: appState.exchangeActionableCount(),
              pendingLeaves: appState.leaveActionableCount(),
              onAccountsTap: () => _showPendingAccounts(context, appState),
              onExchangesTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsScreen(initialIndex: 1))),
              onLeavesTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsScreen(initialIndex: 2))),
            ),
"""
new_summary = old_summary + """            _PromotionManagementCard(
              currentPromotion: appState.currentFirstYearPromotion,
              onAdd: () => _confirmAddPromotion(context, appState),
            ),
"""
s = replace_once(s, old_summary, new_summary, 'admin promotion card insertion')
admin_method = """  Future<void> _confirmAddPromotion(BuildContext context, AppState appState) async {
    if (_adminActionOpen) return;
    final current = appState.currentFirstYearPromotion;
    final next = current + 1;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Ajouter la Promo $next ?'),
        content: Text(
          'La Promo $next deviendra immédiatement la nouvelle 1re année. '
          'La Promo $current passera en 2e année et pourra échanger/transférer '
          'avec les promotions plus anciennes. Cette action ne modifie pas les '
          'promotions déjà attribuées aux comptes existants.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text('Ajouter Promo $next'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    _adminActionOpen = true;
    try {
      final error = await appState.adminAddPromotion();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error ?? 'Promo ${appState.currentFirstYearPromotion} ajoutée : elle devient la 1re année.',
          ),
        ),
      );
    } finally {
      _adminActionOpen = false;
    }
  }

"""
s = replace_once(
    s,
    "  Future<void> _showPendingAccounts(BuildContext context, AppState appState) async {",
    admin_method + "  Future<void> _showPendingAccounts(BuildContext context, AppState appState) async {",
    'admin add promotion handler',
)
card_class = """class _PromotionManagementCard extends StatelessWidget {
  final int currentPromotion;
  final VoidCallback onAdd;

  const _PromotionManagementCard({
    required this.currentPromotion,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final next = currentPromotion + 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.brandSoft,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(Icons.school_rounded, color: AppColors.brand),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Promotions d’internat',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Promo $currentPromotion = 1re année · prochaine : Promo $next',
                          style: TextStyle(color: AppColors.inkSoft, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded),
                  label: Text('Ajouter la Promo $next'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

"""
s = replace_once(
    s,
    "class _AdminSummary extends StatelessWidget {",
    card_class + "class _AdminSummary extends StatelessWidget {",
    'admin promotion card class',
)
p.write_text(s)

print('Promotion management patch applied.')
