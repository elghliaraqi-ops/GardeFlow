import '../widgets/month_navigation.dart';
import '../widgets/planning_calendar.dart';
import '../ui/components.dart';
import '../widgets/admin_reason_dialog.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/hospitals.dart';
import '../data/services.dart';
import '../models/app_user.dart';
import '../models/leave_request.dart';
import '../models/planning_entry.dart';
import '../models/planning_month.dart';
import '../models/shift_type.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import 'audit_screen.dart';
import 'notifications_screen.dart';

const String _kAllHospitals = '__all_hospitals__';

class AdminScreen extends StatefulWidget {
  final bool showAccountsOnOpen;
  const AdminScreen({super.key, this.showAccountsOnOpen = false});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final TextEditingController _doctorSearchController = TextEditingController();
  String _hospital = _kAllHospitals;
  String? _doctorId;
  String _doctorQuery = '';
  bool _adminActionOpen = false;
  DateTime _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void initState() {
    super.initState();
    if (widget.showAccountsOnOpen) WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && context.read<AppState>().currentUser?.role == UserRole.admin) {
        _showPendingAccounts(context, context.read<AppState>());
      }
    });
  }

  @override
  void dispose() {
    _doctorSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    if (appState.currentUser?.role != UserRole.admin) return const Scaffold(body: SafeArea(child: EmptyState(icon: Icons.lock_outline, title: 'Accès réservé aux administrateurs')));
    final hospitalItems = kHospitals.toSet().toList();
    final query = _doctorQuery.trim().toLowerCase();
    final doctors = appState.users.where((user) {
      if (user.accountStatus != AccountStatus.active) return false;
      if (_hospital != _kAllHospitals && user.hospital != _hospital) return false;
      if (query.isEmpty) return true;
      final searchable = [
        user.fullName,
        user.nom,
        user.prenom,
        user.phone,
        user.service,
        user.gradeLabel,
        user.roleLabel,
        hospitalDisplayName(user.hospital),
      ].join(' ').toLowerCase();
      return searchable.contains(query);
    }).toList()
      ..sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));

    final selectedId = doctors.any((u) => u.id == _doctorId)
        ? _doctorId
        : null;
    final selectedDoctor = selectedId == null
        ? null
        : doctors.firstWhere((u) => u.id == selectedId);

    final doctorEntries = selectedDoctor == null
        ? <PlanningEntry>[]
        : appState.planning.where((e) => e.ownerId == selectedDoctor.id || e.ownerPhone == selectedDoctor.phone).toList()
      ..sort((a, b) => a.dateStr.compareTo(b.dateStr));

    final monthPrefix = '${_visibleMonth.year}-${_visibleMonth.month.toString().padLeft(2, '0')}-';
    final monthEntries = doctorEntries.where((e) => e.dateStr.startsWith(monthPrefix)).toList();
    final monthRecord = selectedDoctor == null ? null : appState.planningMonthForUser(selectedDoctor.id, _visibleMonth.year, _visibleMonth.month);

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: GardeFlowTitle('Gestion des gardes'),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: AppSpace.md),
            child: SoftIconButton(
              icon: Icons.history_rounded,
              tooltip: 'Journal des actions',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AuditScreen())),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, 6, 16, 10),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 700;
                  final hospitalFilter = DropdownButtonFormField<String>(
                    value: _hospital,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Établissement',
                      prefixIcon: Icon(Icons.local_hospital_outlined, size: 19),
                    ),
                    items: [
                      const DropdownMenuItem(value: _kAllHospitals, child: Text('Tous les établissements')),
                      ...hospitalItems.map((h) => DropdownMenuItem(value: h, child: Text(hospitalDisplayName(h), overflow: TextOverflow.ellipsis))),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() { _hospital = value; _doctorId = null; });
                    },
                  );
                  final doctorSearch = TextField(
                    controller: _doctorSearchController,
                    decoration: InputDecoration(
                      labelText: 'Rechercher un médecin',
                      hintText: 'Nom, prénom, téléphone ou service',
                      prefixIcon: const Icon(Icons.search_rounded, size: 19),
                      suffixIcon: _doctorQuery.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Effacer la recherche',
                              onPressed: () {
                                _doctorSearchController.clear();
                                setState(() { _doctorQuery = ''; _doctorId = null; });
                              },
                              icon: const Icon(Icons.close_rounded, size: 18),
                            ),
                    ),
                    onChanged: (value) => setState(() { _doctorQuery = value; _doctorId = null; }),
                  );
                  final doctorFilter = DropdownButtonFormField<String>(
                    value: selectedId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Médecin',
                      prefixIcon: Icon(Icons.person_search_outlined, size: 19),
                    ),
                    hint: Text(doctors.isEmpty ? 'Aucun médecin disponible' : 'Choisir un médecin'),
                    items: doctors.map((doctor) => DropdownMenuItem(
                      value: doctor.id,
                      child: Text(
                        '${doctor.fullName} — ${doctor.gradeLabel}${doctor.role == UserRole.admin ? ' · Admin' : ''}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    )).toList(),
                    onChanged: doctors.isEmpty ? null : (value) => setState(() => _doctorId = value),
                  );
                  if (narrow) {
                    return Column(children: [
                      hospitalFilter,
                      const SizedBox(height: 8),
                      doctorSearch,
                      const SizedBox(height: 8),
                      doctorFilter,
                    ]);
                  }
                  return Row(children: [
                    Expanded(child: hospitalFilter),
                    const SizedBox(width: 10),
                    Expanded(child: doctorSearch),
                    const SizedBox(width: 10),
                    Expanded(child: doctorFilter),
                  ]);
                },
              ),
            ),
            if (selectedDoctor != null) ...[
              _DoctorHeader(
                doctor: selectedDoctor,
                totalAssignments: doctorEntries.length,
                monthAssignments: monthEntries.length,
              ),
              _MonthHeader(
                month: _visibleMonth,
                onPrevious: () => setState(() => _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1)),
                onNext: () => setState(() => _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1)),
                onToday: () {
                  final now = DateTime.now();
                  setState(() => _visibleMonth = DateTime(now.year, now.month));
                },
              ),
              _PlanningValidationBar(
                doctor: selectedDoctor,
                month: _visibleMonth,
                record: monthRecord,
                onReopen: monthRecord?.status == PlanningMonthStatus.approved &&
                        !DateTime(_visibleMonth.year, _visibleMonth.month, 1).isBefore(
                          DateTime(DateTime.now().year, DateTime.now().month, 1),
                        )
                    ? () => _confirmReopenPlanningMonth(context, appState, selectedDoctor)
                    : null,
              ),
              _DoctorCalendar(
                month: _visibleMonth,
                entries: doctorEntries,
                onDeleteEntry: (entry) => _confirmDeleteShift(context, appState, entry),
              ),
              const _CalendarLegend(),
            ] else
              const _EmptyAdminView(),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmReopenPlanningMonth(BuildContext context, AppState appState, AppUser doctor) async {
    if (_adminActionOpen) return;
    _adminActionOpen = true;
    final month = _visibleMonth;
    final monthLabel = _capitalize(DateFormat.yMMMM('fr_FR').format(month));
    try {
      final reason = await showDialog<String>(
        context: context,
        builder: (_) => AdminReasonDialog(
          title: doctor.id == appState.currentUser?.id
              ? 'Dévalider votre calendrier ?'
              : 'Dévalider ce calendrier ?',
          subject: '${doctor.fullName} · $monthLabel',
          explanation: doctor.id == appState.currentUser?.id
              ? 'Votre calendrier redeviendra modifiable dans Mon planning. Vous pourrez placer, remplacer ou retirer vos tuiles puis le valider à nouveau. '
                'Les échanges et transferts en cours sur ce mois seront annulés. '
                'Les congés en attente seront recréés à la prochaine validation. '
                'Les congés déjà approuvés restent protégés et peuvent être supprimés avec votre droit administrateur.'
              : 'Le médecin pourra modifier ses tuiles puis valider à nouveau son calendrier. '
                'Les échanges et transferts en cours sur ce mois seront annulés. '
                'Les congés en attente seront recréés à la prochaine validation. '
                'Les congés déjà approuvés restent protégés.',
          actionLabel: 'Dévalider',
        ),
      );
      if (!context.mounted || reason == null) return;
      final error = await appState.adminReopenPlanningMonth(doctor, month, reason: reason);
      if (!context.mounted) return;
      final isOwnCalendar = doctor.id == appState.currentUser?.id;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        error ?? (isOwnCalendar
            ? 'Votre calendrier est dévalidé. Vous pouvez maintenant le modifier dans Mon planning puis le valider à nouveau.'
            : 'Calendrier dévalidé. ${doctor.fullName} peut le modifier puis le valider à nouveau.'))));
    } finally {
      _adminActionOpen = false;
    }
  }

  Future<void> _showPendingAccounts(BuildContext context, AppState appState) async {
    final pending = appState.pendingUsers.toList()
      ..sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: Text('Comptes en attente (${pending.length})'),
        content: SizedBox(
          width: 520,
          child: pending.isEmpty
              ? const Text('Aucun compte en attente de validation.')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: pending.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final user = pending[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(user.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${user.gradeLabel} · ${user.service}\n${hospitalDisplayName(user.hospital)} · ${user.phone}'),
                      isThreeLine: true,
                      trailing: Wrap(
                        spacing: 6,
                        children: [
                          IconButton(
                            tooltip: 'Refuser / suspendre',
                            onPressed: () async {
                              final confirmed = await confirmAction(context,
                                title: 'Refuser ce compte ?',
                                message: '${user.fullName} ne pourra pas se connecter à GardeFlow.',
                                actionLabel: 'Refuser le compte', destructive: true);
                              if (!confirmed || !dialogContext.mounted) return;
                              final err = await appState.reviewAccount(user.id, false);
                              if (!dialogContext.mounted) return;
                              if (err != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                              Navigator.pop(dialogContext);
                            },
                            icon: Icon(Icons.block_outlined, color: AppColors.danger),
                          ),
                          IconButton(
                            tooltip: 'Vérifier et valider le compte',
                            onPressed: () async {
                              Navigator.pop(dialogContext);
                              await _verifyAndApproveAccount(context, appState, user);
                            },
                            icon: Icon(Icons.check_circle_outline, color: AppColors.success),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Fermer'))],
      ),
    );
  }

  Future<void> _verifyAndApproveAccount(BuildContext context, AppState appState, AppUser user) async {
    var hospital = kHospitals.contains(user.hospital) ? user.hospital : kHospitals.first;
    var service = kServices.contains(user.service) ? user.service : kServices.first;
    var grade = user.grade;

    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          scrollable: true,
          title: Text('Vérifier le compte'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.fullName, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  SizedBox(height: 2),
                  Text(user.phone, style: TextStyle(color: AppColors.inkSoft)),
                  SizedBox(height: 14),
                  Text(
                    'Vérifiez les informations déclarées avant d’activer le compte. Elles peuvent être corrigées ici.',
                    style: TextStyle(fontSize: 12, color: AppColors.inkSoft, height: 1.4),
                  ),
                  SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: hospital,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: 'Établissement validé'),
                    items: kHospitals.map((h) => DropdownMenuItem(value: h, child: Text(hospitalDisplayName(h), overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (v) { if (v != null) setLocalState(() => hospital = v); },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: service,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Service validé'),
                    items: kServices.map((v) => DropdownMenuItem(value: v, child: Text(v, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (v) { if (v != null) setLocalState(() => service = v); },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<MedicalGrade>(
                    value: grade,
                    decoration: const InputDecoration(labelText: 'Grade médical validé'),
                    items: const [
                      DropdownMenuItem(value: MedicalGrade.junior, child: Text('Junior')),
                      DropdownMenuItem(value: MedicalGrade.senior, child: Text('Senior')),
                    ],
                    onChanged: (v) { if (v != null) setLocalState(() => grade = v); },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuler')),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.verified_user_outlined, size: 18),
              label: const Text('Valider le compte'),
            ),
          ],
        ),
      ),
    );
    if (approved != true) return;
    final err = await appState.reviewAccount(user.id, true, hospital: hospital, service: service, grade: grade);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? 'Compte validé.')));
  }

  Future<void> _confirmDeleteShift(BuildContext context, AppState appState, PlanningEntry entry) async {
    if (_adminActionOpen) return;
    _adminActionOpen = true;
    final shift = ShiftCatalog.byId(entry.shiftId);
    final dateLabel = DateFormat('dd/MM/yyyy', 'fr_FR').format(DateTime.parse(entry.dateStr));
    final isLeave = entry.shiftId == 'conge';
    try {
      final reason = await showDialog<String>(
        context: context,
        builder: (_) => AdminReasonDialog(
          title: isLeave ? 'Supprimer ce congé ?' : 'Supprimer cette garde ?',
          subject: '${entry.ownerName} · $dateLabel · ${shift.label}',
          explanation: isLeave
              ? 'Ce congé sera retiré du calendrier. L’historique de l’action administrateur reste conservé.'
              : 'La garde sera archivée, y compris après un échange ou un transfert. Les demandes actives liées seront annulées.',
          actionLabel: 'Supprimer',
        ),
      );
      if (!context.mounted || reason == null) return;
      final error = await appState.adminDeleteShift(entry.id, reason: reason);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        error ?? (isLeave ? 'Congé supprimé.' : 'Garde supprimée.'))));
    } finally {
      _adminActionOpen = false;
    }
  }

}

class _PlanningValidationBar extends StatelessWidget {
  final AppUser doctor;
  final DateTime month;
  final PlanningMonth? record;
  final VoidCallback? onReopen;
  const _PlanningValidationBar({required this.doctor, required this.month, required this.record, this.onReopen});

  @override
  Widget build(BuildContext context) {
    final status = record?.status ?? PlanningMonthStatus.draft;
    final validated = status == PlanningMonthStatus.approved;
    final label = validated ? 'Calendrier validé définitivement' : 'Calendrier en préparation';
    final detail = validated
        ? (onReopen != null
            ? 'Validé par ${doctor.fullName}. Un administrateur peut le dévalider pour autoriser une correction, y compris lorsqu’il s’agit de son propre calendrier.'
            : 'Validé par ${doctor.fullName}. Les mois passés restent verrouillés.')
        : '${doctor.fullName} peut placer, remplacer ou retirer ses tuiles avant sa prochaine validation.';
    final icon = validated ? Icons.verified_outlined : Icons.edit_calendar_outlined;
    final bg = Theme.of(context).colorScheme.surfaceContainer;
    return Container(
      margin: EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.sm),
      padding: EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.mdR,
        border: Border.all(color: validated ? AppColors.conge.withOpacity(0.4) : AppColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 19, color: Theme.of(context).colorScheme.primary),
          SizedBox(width: AppSpace.sm),
          Expanded(child: Text(label, style: Theme.of(context).textTheme.titleSmall)),
        ]),
        SizedBox(height: 4),
        Text(detail, style: Theme.of(context).textTheme.bodySmall),
        if (validated && onReopen != null)
          Align(alignment: Alignment.centerRight, child: OutlinedButton.icon(
            onPressed: onReopen,
            icon: Icon(Icons.lock_open_rounded, size: 16),
            label: Text('Dévalider'),
          )),
      ]),
    );
  }
}

class _DoctorHeader extends StatelessWidget {
  final AppUser doctor;
  final int totalAssignments;
  final int monthAssignments;
  const _DoctorHeader({required this.doctor, required this.totalAssignments, required this.monthAssignments});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      DoctorTile(
        name: doctor.fullName,
        subtitle: '${doctor.gradeLabel} · ${doctor.service}\n${hospitalDisplayName(doctor.hospital)}${doctor.role == UserRole.admin ? ' · Administrateur' : ''}',
      ),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Wrap(spacing: 16, runSpacing: 8, children: [
        Text('$monthAssignments affectations ce mois', style: Theme.of(context).textTheme.titleSmall),
        Text('$totalAssignments au total', style: Theme.of(context).textTheme.bodySmall),
      ])),
    ]),
  );
}

class _MonthHeader extends StatelessWidget {
  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;
  const _MonthHeader({required this.month, required this.onPrevious, required this.onNext, required this.onToday});

  @override
  Widget build(BuildContext context) {
    final label = _capitalize(DateFormat.yMMMM('fr_FR').format(month));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        MonthNavigation(label: label, onPrevious: onPrevious, onNext: onNext),
        TextButton.icon(onPressed: onToday, icon: const Icon(Icons.today_rounded, size: 16),
          label: const Text("Aujourd'hui")),
      ]),
    );
  }
}

class _WeekdaysRow extends StatelessWidget {
  const _WeekdaysRow();
  @override
  Widget build(BuildContext context) {
    const days = ['L', 'Ma', 'Me', 'J', 'V', 'S', 'D'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Row(children: days.map((day) => Expanded(child: Text(day, textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelMedium))).toList()),
    );
  }
}

class _DoctorCalendar extends StatelessWidget {
  final DateTime month;
  final List<PlanningEntry> entries;
  final ValueChanged<PlanningEntry> onDeleteEntry;
  const _DoctorCalendar({required this.month, required this.entries, required this.onDeleteEntry});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: PlanningCalendar(month: month, entries: {for (final e in entries) e.dateStr: e},
      onDayTap: (date) {
        final matches = entries.where((e) => e.dateStr == AppState.dateKey(date));
        final entry = matches.isEmpty ? null : matches.first;
        AppBottomSheet.show<void>(context, builder: (ctx) => SafeArea(top: false,
          child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(DateFormat('EEEE d MMMM', 'fr_FR').format(date), style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 16),
              if (entry == null) const Text('Aucune affectation') else ...[
                ShiftBadge(shift: ShiftCatalog.byId(entry.shiftId)),
                const SizedBox(height: 16), Text(entry.ownerName),
                if (ShiftCatalog.byId(entry.shiftId).hasSchedule)
                  Text('${ShiftCatalog.byId(entry.shiftId).start} → ${ShiftCatalog.byId(entry.shiftId).end}'),
                if (entry.isDisciplinary) const Padding(padding: EdgeInsets.only(top: 12), child: DisciplinaryBadge()),
                const SizedBox(height: 20),
                PrimaryButton(label: 'Supprimer cette affectation', icon: Icons.delete_outline,
                  onPressed: context.read<AppState>().canAdminDeleteEntry(entry)
                    ? () { Navigator.pop(ctx); onDeleteEntry(entry); } : null),
              ],
            ]),
          ),
        ));
      }),
  );
}

class _CalendarLegend extends StatelessWidget {
  const _CalendarLegend();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.md),
    child: Wrap(alignment: WrapAlignment.center, spacing: AppSpace.lg, runSpacing: AppSpace.xs, children: [
      _LegendItem(color: AppColors.catService, label: 'Service'),
      _LegendItem(color: AppColors.catUrgence, label: 'Urgences'),
      _LegendItem(color: AppColors.conge, label: 'Congé'),
    ]),
  );
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    SizedBox(width: 5),
    Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.inkSoft)),
  ]);
}

class _EmptyAdminView extends StatelessWidget {
  const _EmptyAdminView();
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.person_search_rounded, size: 40, color: AppColors.inkFaint),
        SizedBox(height: AppSpace.md),
        Text('Aucun médecin ne correspond à cet établissement.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.inkSoft)),
      ]),
    ),
  );
}

String _shiftGroup(String shiftId) {
  if (shiftId.startsWith('service-')) return 'service';
  if (shiftId.startsWith('urg-')) return 'urgences';
  return 'conge';
}

String _capitalize(String value) => value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);
String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  final values = parts.take(2).map((p) => p[0].toUpperCase()).join();
  return values.isEmpty ? '?' : values;
}
