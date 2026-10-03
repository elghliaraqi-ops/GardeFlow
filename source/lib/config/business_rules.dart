/// Règles métier GardeFlow centralisées.
///
/// L'interface ne doit jamais être la seule barrière : les mêmes
/// contraintes critiques sont aussi imposées côté PostgreSQL/RLS/RPC.
class BusinessRules {
  BusinessRules._();

  static const bool sameHospitalRequired = true;
  static const bool sameGradeRequiredForExchange = false;
  static const bool firstYearSamePromotionRequiredForEmergency = true;

  /// Toute demande d'échange impliquant une garde de Service impose
  /// que les deux médecins appartiennent au même service.
  static bool exchangeRequiresSameService(
    String sourceShiftId,
    String? targetShiftId,
  ) =>
      sourceShiftId.startsWith('service-') ||
      (targetShiftId?.startsWith('service-') ?? false);

  /// La restriction de promotion de la première année ne s'applique
  /// qu'aux demandes impliquant les Urgences.
  static bool requestInvolvesEmergency(
    String sourceShiftId,
    String? targetShiftId,
  ) =>
      sourceShiftId.startsWith('urg-') ||
      (targetShiftId?.startsWith('urg-') ?? false);

  static const int minimumRestHours = 0;
}
