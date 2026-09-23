/// Règles institutionnelles centralisées.
/// Les contraintes dont la valeur dépend du règlement local sont volontairement
/// explicites ici au lieu d'être dispersées dans l'UI.
class BusinessRules {
  BusinessRules._();

  static const bool sameHospitalRequired = true;

  // À activer uniquement si le règlement HUIM6 l'impose formellement.
  static const bool sameServiceRequiredForExchange = false;
  static const bool sameGradeRequiredForExchange = false;

  // 0 = pas de blocage automatique tant qu'une durée officielle n'a pas été
  // validée par l'établissement. La structure est prête pour une règle future.
  static const int minimumRestHours = 0;
}
