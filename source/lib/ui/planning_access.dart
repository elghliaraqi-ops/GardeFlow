import '../models/exchange_request.dart';
import '../models/directory_contact.dart';
import '../models/planning_entry.dart';
import '../models/shift_type.dart';
import '../state/app_state.dart';

/// UI availability only. AppState and server checks remain authoritative.
String? planningEditReason(AppState state, DateTime date, PlanningEntry? entry) {
  if (state.currentUser == null) return 'Connectez-vous pour modifier votre planning.';
  if (state.dateIsPast(AppState.dateKey(date))) return 'Cette journée est en consultation uniquement.';
  if (entry?.isDisciplinary == true) return 'Garde disciplinaire : seul un administrateur peut intervenir.';
  if (entry != null && state.isApprovedLeaveEntry(entry)) return 'Ce congé est approuvé. Contactez un administrateur pour le modifier.';
  if (entry != null && hasActiveRequest(state, entry)) return 'Une demande est déjà en cours pour cette garde.';
  if (!state.canEditMyPlanningMonth(date)) return 'Planning verrouillé. Contactez un administrateur pour le rouvrir.';
  if (entry != null && entry.shiftId != 'conge' && state.guardHasStarted(entry)) return 'Cette garde a déjà commencé.';
  return null;
}
bool hasActiveRequest(AppState state, PlanningEntry entry) => state.exchanges.any((x) =>
  (x.status == ExchangeStatus.pendingB || x.status == ExchangeStatus.pendingAdmin) &&
  (x.planningEntryId == entry.id || x.targetPlanningEntryId == entry.id));
String? exchangeDisabledReason(AppState state, PlanningEntry entry) {
  final me = state.currentUser;
  if (me == null) return 'Connectez-vous pour proposer cette garde.';
  if (!state.planning.any((e) => e.id == entry.id && (e.ownerId == me.id || e.ownerPhone == me.phone))) {
    return 'Cette garde ne vous appartient plus.';
  }
  if (entry.isDisciplinary) return 'Une garde disciplinaire ne peut être ni échangée ni transférée.';
  if (!ShiftCatalog.byId(entry.shiftId).hasSchedule) return 'Un congé ne peut pas être échangé ou transféré.';
  if (state.guardHasStarted(entry)) return 'Cette garde a déjà commencé.';
  if (!state.isPlanningEntryApproved(entry)) return 'Validez votre planning avant de proposer un échange ou un transfert.';
  if (hasActiveRequest(state, entry)) return 'Une demande est déjà en cours pour cette garde.';
  return null;
}

String? transferTargetDisabledReason(AppState state, PlanningEntry source, DirectoryContact doctor) {
  if (!state.isUserPlanningMonthApproved(doctor.id, source.dateStr)) {
    return 'Planning du destinataire non validé pour ce mois.';
  }
  if (state.planning.any((e) => e.dateStr == source.dateStr && (e.ownerId == doctor.id || e.ownerPhone == doctor.phone))) {
    return 'Ce médecin a déjà une affectation ce jour-là.';
  }
  return null;
}

String? swapTargetDisabledReason(AppState state, PlanningEntry source, DirectoryContact doctor, PlanningEntry target) {
  final me = state.currentUser;
  if (me == null) return 'Session expirée.';
  if (!state.isUserPlanningMonthApproved(me.id, target.dateStr) ||
      !state.isUserPlanningMonthApproved(doctor.id, source.dateStr)) {
    return 'Les mois de destination doivent aussi être validés.';
  }
  if (state.planning.any((e) => e.id != target.id && e.dateStr == source.dateStr && (e.ownerId == doctor.id || e.ownerPhone == doctor.phone))) {
    return 'Ce médecin a une autre affectation à la date proposée.';
  }
  if (state.planning.any((e) => e.id != source.id && e.dateStr == target.dateStr && (e.ownerId == me.id || e.ownerPhone == me.phone))) {
    return 'Vous avez déjà une autre affectation à cette date.';
  }
  return null;
}
bool shiftHasStarted(DateTime date, ShiftType shift, {DateTime? now}) {
  if (!shift.hasSchedule) return false;
  final parts = shift.start!.split(':').map(int.parse).toList();
  return !(now ?? DateTime.now()).isBefore(DateTime(date.year, date.month, date.day, parts[0], parts[1]));
}
