#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def replace_once(path: str, old: str, new: str) -> None:
    p = ROOT / path
    text = p.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly 1 occurrence, found {count}: {old[:80]!r}")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")


def regex_once(path: str, pattern: str, repl: str) -> None:
    p = ROOT / path
    text = p.read_text(encoding="utf-8")
    updated, count = re.subn(pattern, repl, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly 1 regex match, found {count}: {pattern[:80]!r}")
    p.write_text(updated, encoding="utf-8")


# ---------------------------------------------------------------------------
# 1) Central business-rule semantics.
# ---------------------------------------------------------------------------
(ROOT / "source/lib/config/business_rules.dart").write_text(
    """/// Règles métier GardeFlow centralisées.\n"
    "///\n"
    "/// Les helpers ci-dessous décrivent la règle fonctionnelle. L'UI ne doit\n"
    "/// jamais être la seule barrière : les mêmes contraintes sont réappliquées\n"
    "/// côté PostgreSQL/RLS/RPC.\n"
    "class BusinessRules {\n"
    "  BusinessRules._();\n\n"
    "  static const bool sameHospitalRequired = true;\n"
    "  static const bool sameGradeRequiredForExchange = false;\n"
    "  static const bool firstYearSamePromotionRequiredForEmergency = true;\n\n"
    "  /// Une garde de Service impliquée dans un échange impose le même service.\n"
    "  /// Un échange 100 % Urgences n'impose pas le même service.\n"
    "  static bool exchangeRequiresSameService(\n"
    "    String sourceShiftId,\n"
    "    String? targetShiftId,\n"
    "  ) =>\n"
    "      sourceShiftId.startsWith('service-') ||\n"
    "      (targetShiftId?.startsWith('service-') ?? false);\n\n"
    "  /// La restriction de promotion de la 1re année ne s'applique qu'aux\n"
    "  /// demandes impliquant les Urgences (transfert ou échange).\n"
    "  static bool requestInvolvesEmergency(\n"
    "    String sourceShiftId,\n"
    "    String? targetShiftId,\n"
    "  ) =>\n"
    "      sourceShiftId.startsWith('urg-') ||\n"
    "      (targetShiftId?.startsWith('urg-') ?? false);\n\n"
    "  // 0 = pas de blocage automatique tant qu'une durée officielle n'a pas\n"
    "  // été validée par l'établissement.\n"
    "  static const int minimumRestHours = 0;\n"
    "}\n""",
    encoding="utf-8",
)

# ---------------------------------------------------------------------------
# 2) AppState: PDF zero-assignment is valid, submitted state is real, and the
#    promotion restriction only applies to requests involving Urgences.
# ---------------------------------------------------------------------------
replace_once(
    "source/lib/state/app_state.dart",
    """    if (myAssignments.isEmpty) {\n      throw StateError(\n        'Le PDF ${resource.displayName} est lisible mais le nom de ${profile.prenom} ${profile.nom} n’y a pas été reconnu. La synchronisation sera retentée automatiquement.',\n      );\n    }\n\n    final result = await backend.importOfficialEmergencyRosterForProfile(\n""",
    """    // Zéro affectation est un résultat valide : un médecin peut simplement\n    // ne pas avoir de garde Urgences sur ce planning. Le backend versionne tout\n    // de même cette synchronisation et conserve les cellules non reconnues pour\n    // audit, ce qui évite une boucle de retraitement à chaque connexion.\n    final result = await backend.importOfficialEmergencyRosterForProfile(\n""",
)

replace_once(
    "source/lib/state/app_state.dart",
    """    // V10.2 : le médecin verrouille lui-même son mois. Les anciens états\n    // submitted/rejected de V10.1 sont donc traités comme des brouillons.\n    return status != PlanningMonthStatus.approved;\n""",
    """    // Un mois soumis est figé en attente de validation finale. Un mois\n    // rejeté redevient modifiable afin que le médecin puisse le corriger.\n    return status == PlanningMonthStatus.draft ||\n        status == PlanningMonthStatus.rejected;\n""",
)

replace_once(
    "source/lib/state/app_state.dart",
    """  bool promotionExchangeBlocked(AppUser? a, AppUser? b) =>\n      InternPromotions.crossYearBlocked(\n        a,\n        b,\n        firstYearPromotion: currentFirstYearPromotion,\n      );\n""",
    """  bool promotionExchangeBlocked(\n    AppUser? a,\n    AppUser? b, {\n    required String sourceShiftId,\n    String? targetShiftId,\n  }) {\n    if (!BusinessRules.firstYearSamePromotionRequiredForEmergency ||\n        !BusinessRules.requestInvolvesEmergency(\n          sourceShiftId,\n          targetShiftId,\n        )) {\n      return false;\n    }\n    return InternPromotions.crossYearBlocked(\n      a,\n      b,\n      firstYearPromotion: currentFirstYearPromotion,\n    );\n  }\n""",
)

replace_once(
    "source/lib/state/app_state.dart",
    """      if ((sameServiceOnly || BusinessRules.sameServiceRequiredForExchange) &&\n          u.service != me.service)\n        continue;\n""",
    """      if (sameServiceOnly && u.service != me.service) continue;\n""",
)

replace_once(
    "source/lib/state/app_state.dart",
    """    final status = myPlanningMonth(date)?.status ?? PlanningMonthStatus.draft;\n    if (status == PlanningMonthStatus.approved)\n      return 'Ce calendrier est validé définitivement. Utilisez ensuite transfert/échange ou contactez un administrateur.';\n""",
    """    final status = myPlanningMonth(date)?.status ?? PlanningMonthStatus.draft;\n    if (status == PlanningMonthStatus.submitted)\n      return 'Ce calendrier est soumis et en attente de validation finale. Il ne peut plus être modifié.';\n    if (status == PlanningMonthStatus.approved)\n      return 'Ce calendrier est validé définitivement. Utilisez ensuite transfert/échange ou contactez un administrateur.';\n""",
)

replace_once(
    "source/lib/state/app_state.dart",
    """    final status = myPlanningMonth(date)?.status ?? PlanningMonthStatus.draft;\n    if (status == PlanningMonthStatus.approved)\n      return 'Un calendrier validé ne peut plus être modifié directement. Seul un administrateur peut supprimer une garde validée.';\n""",
    """    final status = myPlanningMonth(date)?.status ?? PlanningMonthStatus.draft;\n    if (status == PlanningMonthStatus.submitted)\n      return 'Ce calendrier est soumis et en attente de validation finale. Il ne peut plus être modifié.';\n    if (status == PlanningMonthStatus.approved)\n      return 'Un calendrier validé ne peut plus être modifié directement. Seul un administrateur peut supprimer une garde validée.';\n""",
)

replace_once(
    "source/lib/state/app_state.dart",
    """    if (status == PlanningMonthStatus.approved)\n      return 'Ce calendrier est déjà validé définitivement.';\n    try {\n""",
    """    if (status == PlanningMonthStatus.submitted)\n      return 'Ce calendrier est déjà soumis et attend sa validation finale.';\n    if (status == PlanningMonthStatus.approved)\n      return 'Ce calendrier est déjà validé définitivement.';\n    try {\n""",
)

replace_once(
    "source/lib/state/app_state.dart",
    """          PlanningMonthStatus.approved,\n        );\n        r.submittedAt = DateTime.now();\n""",
    """          PlanningMonthStatus.submitted,\n        );\n        r.submittedAt = DateTime.now();\n""",
)

replace_once(
    "source/lib/state/app_state.dart",
    """      return 'Validation définitive du calendrier impossible : $e';\n    }\n  }\n\n  Future<String?> requestLeave(String dateStr) =>\n""",
    """      return 'Soumission du calendrier impossible : $e';\n    }\n  }\n\n  Future<String?> reviewPlanningMonth(\n    AppUser doctor,\n    DateTime month, {\n    required bool approve,\n    String? reason,\n  }) async {\n    final me = currentUser;\n    if (me == null || me.role != UserRole.admin) {\n      return 'Action réservée à l’administrateur.';\n    }\n    final record = planningMonthForUser(doctor.id, month.year, month.month);\n    if (record?.status != PlanningMonthStatus.submitted) {\n      return 'Ce calendrier n’est plus en attente de validation.';\n    }\n    if (doctor.id == me.id || doctor.phone == me.phone) {\n      return 'Un administrateur ne peut pas valider ou rejeter son propre calendrier.';\n    }\n    final cleanReason = reason?.trim() ?? '';\n    if (!approve && cleanReason.length < 3) {\n      return 'Indiquez un motif de rejet.';\n    }\n    try {\n      if (backendEnabled) {\n        await SupabaseBackendService.instance.reviewPlanningMonth(\n          ownerId: doctor.id,\n          year: month.year,\n          month: month.month,\n          action: approve ? 'approve' : 'reject',\n          reason: approve ? null : cleanReason,\n        );\n        await _reloadFromBackend();\n        if (approve) await rescheduleAllReminders();\n      } else {\n        record!\n          ..status = approve\n              ? PlanningMonthStatus.approved\n              : PlanningMonthStatus.rejected\n          ..reviewedAt = DateTime.now()\n          ..reviewedBy = me.id\n          ..rejectionReason = approve ? null : cleanReason;\n        _persist();\n        notifyListeners();\n      }\n      return null;\n    } catch (e) {\n      return approve\n          ? 'Validation finale impossible : $e'\n          : 'Rejet du calendrier impossible : $e';\n    }\n  }\n\n  Future<String?> requestLeave(String dateStr) =>\n""",
)

replace_once(
    "source/lib/state/app_state.dart",
    """    if (promotionExchangeBlocked(me, targetUser))\n      return 'La promotion de première année (Promo $currentFirstYearPromotion) ne peut transférer des gardes qu’avec la même promotion.';\n""",
    """    if (promotionExchangeBlocked(\n      me,\n      targetUser,\n      sourceShiftId: entry.shiftId,\n    ))\n      return 'Pour les gardes des Urgences, la promotion de première année (Promo $currentFirstYearPromotion) ne peut transférer qu’avec la même promotion.';\n""",
)

replace_once(
    "source/lib/state/app_state.dart",
    """    if (promotionExchangeBlocked(me, targetUser)) {\n      return 'La promotion de première année (Promo $currentFirstYearPromotion) ne peut échanger des gardes qu’avec la même promotion.';\n    }\n""",
    """    if (promotionExchangeBlocked(\n      me,\n      targetUser,\n      sourceShiftId: entry.shiftId,\n      targetShiftId: targetEntry.shiftId,\n    )) {\n      return 'Pour les gardes des Urgences, la promotion de première année (Promo $currentFirstYearPromotion) ne peut échanger qu’avec la même promotion.';\n    }\n""",
)

replace_once(
    "source/lib/state/app_state.dart",
    """    if (promotionExchangeBlocked(fromUser, toUser))\n      return 'La promotion de première année (Promo $currentFirstYearPromotion) ne peut échanger des gardes qu’avec la même promotion.';\n""",
    """    if (promotionExchangeBlocked(\n      fromUser,\n      toUser,\n      sourceShiftId: source.shiftId,\n      targetShiftId: target.shiftId,\n    ))\n      return 'Pour les gardes des Urgences, la promotion de première année (Promo $currentFirstYearPromotion) ne peut échanger qu’avec la même promotion.';\n""",
)

replace_once(
    "source/lib/state/app_state.dart",
    """    for (final p in _planningMonths) {\n      if (p.status == PlanningMonthStatus.submitted ||\n          p.status == PlanningMonthStatus.rejected) {\n        p.status = PlanningMonthStatus.draft;\n        p.reviewedAt = null;\n        p.reviewedBy = null;\n        p.rejectionReason = null;\n      }\n    }\n""",
    """    // Les états submitted/rejected font désormais partie du workflow\n    // courant et doivent être restaurés tels quels.\n""",
)

# ---------------------------------------------------------------------------
# 3) Backend RPC for final admin review.
# ---------------------------------------------------------------------------
replace_once(
    "source/lib/services/supabase_backend_service.dart",
    """  Future<void> adminReopenPlanningMonth({\n""",
    """  Future<void> reviewPlanningMonth({\n    required String ownerId,\n    required int year,\n    required int month,\n    required String action,\n    String? reason,\n  }) async {\n    await client.rpc(\n      'review_planning_month',\n      params: {\n        'p_owner_id': ownerId,\n        'p_year': year,\n        'p_month': month,\n        'p_action': action,\n        'p_reason': reason,\n      },\n    );\n  }\n\n  Future<void> adminReopenPlanningMonth({\n""",
)

# ---------------------------------------------------------------------------
# 4) PlanningMonth semantics.
# ---------------------------------------------------------------------------
replace_once(
    "source/lib/models/planning_month.dart",
    """  bool get isEditable => status != PlanningMonthStatus.approved;\n  bool get isSubmitted => status == PlanningMonthStatus.submitted; // état historique V10.1\n""",
    """  bool get isEditable =>\n      status == PlanningMonthStatus.draft ||\n      status == PlanningMonthStatus.rejected;\n  bool get isSubmitted => status == PlanningMonthStatus.submitted;\n""",
)

# ---------------------------------------------------------------------------
# 5) Doctor planning UI: submit != final approve.
# ---------------------------------------------------------------------------
replace_once(
    "source/lib/screens/home_screen.dart",
    """      case PlanningMonthStatus.draft:\n      case PlanningMonthStatus.submitted:\n      case PlanningMonthStatus.rejected:\n        reopenReason = record?.rejectionReason?.trim();\n        final reopened = reopenReason != null && reopenReason.isNotEmpty;\n        statusLabel = reopened ? 'Rouvert' : 'En préparation';\n        statusIcon =\n            reopened ? Icons.lock_open_rounded : Icons.edit_calendar_rounded;\n        statusBg = reopened ? Color(0xFFB3261E) : AppColors.paperAlt;\n        statusFg = reopened ? Colors.white : AppColors.ink;\n        break;\n    }\n\n    final canSubmit = !isPastMonth && status != PlanningMonthStatus.approved;\n""",
    """      case PlanningMonthStatus.submitted:\n        statusLabel = 'Soumis · en attente';\n        statusIcon = Icons.hourglass_top_rounded;\n        statusBg = const Color(0xFFF3A712);\n        statusFg = Colors.white;\n        break;\n      case PlanningMonthStatus.rejected:\n        reopenReason = record?.rejectionReason?.trim();\n        statusLabel = 'À corriger';\n        statusIcon = Icons.error_outline_rounded;\n        statusBg = const Color(0xFFB3261E);\n        statusFg = Colors.white;\n        break;\n      case PlanningMonthStatus.draft:\n        reopenReason = record?.rejectionReason?.trim();\n        final reopened = reopenReason != null && reopenReason.isNotEmpty;\n        statusLabel = reopened ? 'Rouvert' : 'En préparation';\n        statusIcon =\n            reopened ? Icons.lock_open_rounded : Icons.edit_calendar_rounded;\n        statusBg = reopened ? const Color(0xFFB3261E) : AppColors.paperAlt;\n        statusFg = reopened ? Colors.white : AppColors.ink;\n        break;\n    }\n\n    final canSubmit = !isPastMonth &&\n        (status == PlanningMonthStatus.draft ||\n            status == PlanningMonthStatus.rejected);\n""",
)

replace_once(
    "source/lib/screens/home_screen.dart",
    """      case PlanningMonthStatus.draft:\n      case PlanningMonthStatus.submitted:\n      case PlanningMonthStatus.rejected:\n        if (reopenReason != null && reopenReason.isNotEmpty) {\n          title = 'Calendrier rouvert par un administrateur';\n          detail =\n              'Motif : $reopenReason. Modifiez vos tuiles puis validez à nouveau le mois. Sans validation manuelle, le calendrier sera automatiquement validé 7 jours après la publication ou le remplacement du planning officiel.';\n        } else {\n          title = 'Calendrier en préparation';\n          detail =\n              'Placez vos tuiles Service, Urgences et Congé puis validez définitivement le mois. Sans validation manuelle, le calendrier sera automatiquement validé 7 jours après la publication ou le remplacement du planning officiel.';\n        }\n        break;\n""",
    """      case PlanningMonthStatus.submitted:\n        title = 'Calendrier soumis';\n        detail =\n            'Le mois est figé en attente d’une validation finale par un administrateur. À défaut, l’auto-validation peut intervenir à J+7 du planning officiel.';\n        break;\n      case PlanningMonthStatus.rejected:\n        title = 'Calendrier à corriger';\n        detail =\n            'Motif : ${reopenReason?.isNotEmpty == true ? reopenReason : 'correction demandée par l’administration'}. Corrigez les tuiles puis soumettez à nouveau le mois.';\n        break;\n      case PlanningMonthStatus.draft:\n        if (reopenReason != null && reopenReason.isNotEmpty) {\n          title = 'Calendrier rouvert par un administrateur';\n          detail =\n              'Motif : $reopenReason. Modifiez vos tuiles puis soumettez à nouveau le mois.';\n        } else {\n          title = 'Calendrier en préparation';\n          detail =\n              'Placez vos tuiles Service, Urgences et Congé puis soumettez le mois. Il sera ensuite validé par un administrateur ou automatiquement à J+7 du planning officiel.';\n        }\n        break;\n""",
)

replace_once(
    "source/lib/screens/home_screen.dart",
    """              title: const Text('Valider définitivement ce calendrier ?'),\n              content: const Text(\n                'Après validation, vous ne pourrez plus déplacer, remplacer ni retirer vos tuiles. '\n                'Seul un administrateur pourra supprimer une garde validée ou rouvrir le mois pour correction. '\n                'Les tuiles Congé seront envoyées à l’administration pour approbation.',\n              ),\n""",
    """              title: const Text('Soumettre ce calendrier ?'),\n              content: const Text(\n                'Après soumission, le mois sera figé en attente de validation finale. '\n                'Un administrateur pourra l’approuver ou demander une correction. '\n                'À défaut, l’auto-validation reste possible à J+7 du planning officiel. '\n                'Les tuiles Congé seront envoyées séparément à l’administration pour approbation.',\n              ),\n""",
)
replace_once(
    "source/lib/screens/home_screen.dart",
    """                  child: const Text('Valider définitivement'),\n""",
    """                  child: const Text('Soumettre'),\n""",
)
replace_once(
    "source/lib/screens/home_screen.dart",
    """            SnackBar(content: Text(err ?? 'Calendrier validé définitivement.')),\n""",
    """            SnackBar(content: Text(err ?? 'Calendrier soumis à validation.')),\n""",
)
replace_once(
    "source/lib/screens/home_screen.dart",
    """        child: const Text('Valider'),\n""",
    """        child: const Text('Soumettre'),\n""",
)

# ---------------------------------------------------------------------------
# 6) Admin UI: submitted months get explicit approve / reject actions.
# ---------------------------------------------------------------------------
replace_once(
    "source/lib/screens/admin_screen.dart",
    """                onReopen:\n                    monthRecord?.status == PlanningMonthStatus.approved &&\n                        !DateTime(\n                          _visibleMonth.year,\n                          _visibleMonth.month,\n                          1,\n                        ).isBefore(\n                          DateTime(\n                            DateTime.now().year,\n                            DateTime.now().month,\n                            1,\n                          ),\n                        )\n                    ? () => _confirmReopenPlanningMonth(\n                        context,\n                        appState,\n                        selectedDoctor,\n                      )\n                    : null,\n              ),\n""",
    """                onApprove:\n                    monthRecord?.status == PlanningMonthStatus.submitted &&\n                        selectedDoctor.id != appState.currentUser?.id\n                    ? () => _confirmReviewPlanningMonth(\n                        context,\n                        appState,\n                        selectedDoctor,\n                        approve: true,\n                      )\n                    : null,\n                onReject:\n                    monthRecord?.status == PlanningMonthStatus.submitted &&\n                        selectedDoctor.id != appState.currentUser?.id\n                    ? () => _confirmReviewPlanningMonth(\n                        context,\n                        appState,\n                        selectedDoctor,\n                        approve: false,\n                      )\n                    : null,\n                onReopen:\n                    monthRecord?.status == PlanningMonthStatus.approved &&\n                        !DateTime(\n                          _visibleMonth.year,\n                          _visibleMonth.month,\n                          1,\n                        ).isBefore(\n                          DateTime(\n                            DateTime.now().year,\n                            DateTime.now().month,\n                            1,\n                          ),\n                        )\n                    ? () => _confirmReopenPlanningMonth(\n                        context,\n                        appState,\n                        selectedDoctor,\n                      )\n                    : null,\n              ),\n""",
)

replace_once(
    "source/lib/screens/admin_screen.dart",
    """  Future<void> _confirmReopenPlanningMonth(\n""",
    """  Future<void> _confirmReviewPlanningMonth(\n    BuildContext context,\n    AppState appState,\n    AppUser doctor, {\n    required bool approve,\n  }) async {\n    if (_adminActionOpen) return;\n    _adminActionOpen = true;\n    final month = _visibleMonth;\n    final monthLabel = _capitalize(DateFormat.yMMMM('fr_FR').format(month));\n    try {\n      String? reason;\n      if (approve) {\n        final confirmed = await showDialog<bool>(\n          context: context,\n          builder: (dialogContext) => AlertDialog(\n            title: const Text('Valider définitivement ce calendrier ?'),\n            content: Text(\n              '${doctor.fullName} · $monthLabel. Le mois sera verrouillé et les échanges/transferts pourront ensuite utiliser ses gardes validées.',\n            ),\n            actions: [\n              TextButton(\n                onPressed: () => Navigator.pop(dialogContext, false),\n                child: const Text('Annuler'),\n              ),\n              FilledButton(\n                onPressed: () => Navigator.pop(dialogContext, true),\n                child: const Text('Approuver'),\n              ),\n            ],\n          ),\n        );\n        if (confirmed != true || !context.mounted) return;\n      } else {\n        reason = await showDialog<String>(\n          context: context,\n          builder: (_) => AdminReasonDialog(\n            title: 'Demander une correction ?',\n            subject: '${doctor.fullName} · $monthLabel',\n            explanation:\n                'Le calendrier redeviendra modifiable. Les demandes de congé encore en attente créées par cette soumission seront annulées et recréées à la prochaine soumission.',\n            actionLabel: 'Rejeter et rouvrir',\n          ),\n        );\n        if (reason == null || !context.mounted) return;\n      }\n      final error = await appState.reviewPlanningMonth(\n        doctor,\n        month,\n        approve: approve,\n        reason: reason,\n      );\n      if (!context.mounted) return;\n      ScaffoldMessenger.of(context).showSnackBar(\n        SnackBar(\n          content: Text(\n            error ??\n                (approve\n                    ? 'Calendrier validé définitivement.'\n                    : 'Correction demandée au médecin.'),\n          ),\n        ),\n      );\n    } finally {\n      _adminActionOpen = false;\n    }\n  }\n\n  Future<void> _confirmReopenPlanningMonth(\n""",
)

regex_once(
    "source/lib/screens/admin_screen.dart",
    r"class _PlanningValidationBar extends StatelessWidget \{.*?\n\}\n\nclass _DoctorHeader extends StatelessWidget",
    """class _PlanningValidationBar extends StatelessWidget {\n  final AppUser doctor;\n  final DateTime month;\n  final PlanningMonth? record;\n  final VoidCallback? onApprove;\n  final VoidCallback? onReject;\n  final VoidCallback? onReopen;\n\n  const _PlanningValidationBar({\n    required this.doctor,\n    required this.month,\n    required this.record,\n    this.onApprove,\n    this.onReject,\n    this.onReopen,\n  });\n\n  @override\n  Widget build(BuildContext context) {\n    final status = record?.status ?? PlanningMonthStatus.draft;\n    late String label;\n    late String detail;\n    late IconData icon;\n    late Color bg;\n    late Color fg;\n\n    switch (status) {\n      case PlanningMonthStatus.approved:\n        label = 'Calendrier validé définitivement';\n        detail = onReopen != null\n            ? 'Le mois est verrouillé. Un administrateur peut le rouvrir avec un motif.'\n            : 'Le mois est verrouillé. Les mois passés restent en lecture seule.';\n        icon = Icons.verified_outlined;\n        bg = AppColors.conge.withOpacity(0.18);\n        fg = AppColors.congeText;\n        break;\n      case PlanningMonthStatus.submitted:\n        label = 'Calendrier soumis · validation requise';\n        detail = doctor.id == context.read<AppState>().currentUser?.id\n            ? 'Votre propre calendrier doit être validé par un autre administrateur ou par l’auto-validation J+7.'\n            : 'Vérifiez le mois puis approuvez-le ou demandez une correction.';\n        icon = Icons.hourglass_top_rounded;\n        bg = const Color(0xFFF3A712).withOpacity(0.16);\n        fg = const Color(0xFF9A6200);\n        break;\n      case PlanningMonthStatus.rejected:\n        label = 'Correction demandée';\n        detail = record?.rejectionReason?.trim().isNotEmpty == true\n            ? 'Motif : ${record!.rejectionReason!.trim()}'\n            : 'Le médecin peut corriger puis soumettre à nouveau le mois.';\n        icon = Icons.error_outline_rounded;\n        bg = AppColors.danger.withOpacity(0.12);\n        fg = AppColors.danger;\n        break;\n      case PlanningMonthStatus.draft:\n        label = record?.rejectionReason?.trim().isNotEmpty == true\n            ? 'Calendrier rouvert'\n            : 'Calendrier en préparation';\n        detail = record?.rejectionReason?.trim().isNotEmpty == true\n            ? 'Motif : ${record!.rejectionReason!.trim()}'\n            : '${doctor.fullName} peut encore modifier ses tuiles avant soumission.';\n        icon = Icons.edit_calendar_outlined;\n        bg = AppColors.paperAlt;\n        fg = AppColors.ink;\n        break;\n    }\n\n    return Container(\n      margin: EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.sm),\n      padding: EdgeInsets.all(AppSpace.md),\n      decoration: BoxDecoration(\n        color: bg,\n        borderRadius: AppRadius.mdR,\n        border: Border.all(color: fg.withOpacity(0.28)),\n      ),\n      child: Column(\n        crossAxisAlignment: CrossAxisAlignment.start,\n        children: [\n          Row(\n            children: [\n              Icon(icon, size: 19, color: fg),\n              SizedBox(width: AppSpace.sm),\n              Expanded(\n                child: Text(label, style: Theme.of(context).textTheme.titleSmall),\n              ),\n            ],\n          ),\n          const SizedBox(height: 4),\n          Text(detail, style: Theme.of(context).textTheme.bodySmall),\n          if (status == PlanningMonthStatus.submitted &&\n              (onApprove != null || onReject != null)) ...[\n            const SizedBox(height: 8),\n            Wrap(\n              spacing: 8,\n              runSpacing: 8,\n              alignment: WrapAlignment.end,\n              children: [\n                if (onReject != null)\n                  OutlinedButton.icon(\n                    onPressed: onReject,\n                    icon: const Icon(Icons.edit_calendar_outlined, size: 16),\n                    label: const Text('Demander correction'),\n                  ),\n                if (onApprove != null)\n                  FilledButton.icon(\n                    onPressed: onApprove,\n                    icon: const Icon(Icons.verified_rounded, size: 16),\n                    label: const Text('Approuver'),\n                  ),\n              ],\n            ),\n          ],\n          if (status == PlanningMonthStatus.approved && onReopen != null)\n            Align(\n              alignment: Alignment.centerRight,\n              child: OutlinedButton.icon(\n                onPressed: onReopen,\n                icon: const Icon(Icons.lock_open_rounded, size: 16),\n                label: const Text('Dévalider'),\n              ),\n            ),\n        ],\n      ),\n    );\n  }\n}\n\nclass _DoctorHeader extends StatelessWidget""",
)

print("Hardening source patch applied successfully.")
