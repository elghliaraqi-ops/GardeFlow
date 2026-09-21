import '../widgets/month_navigation.dart';
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
  const AdminScreen({super.key});

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
  void dispose() {
    _doctorSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
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
        : (doctors.isNotEmpty ? doctors.first.id : null);
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
            _AdminSummary(
              pendingAccounts: appState.pendingUsers.length,
              pendingExchanges: appState.exchangeActionableCount(),
              pendingLeaves: appState.leaveActionableCount(),
              onAccountsTap: () => _showPendingAccounts(context, appState),
              onExchangesTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsScreen(initialIndex: 1))),
              onLeavesTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsScreen(initialIndex: 2))),
            ),
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
                    hint: Text(query.isEmpty ? 'Aucun médecin disponible' : 'Aucun résultat'),
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
                              final err = await appState.reviewAccount(user.id, false);
                              if (!dialogContext.mounted) return;
                              if (err != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                              Navigator.pop(dialogContext);
                            },
                            icon: const Icon(Icons.block_outlined, color: AppColors.danger),
                          ),
                          IconButton(
                            tooltip: 'Vérifier et valider le compte',
                            onPressed: () async {
                              Navigator.pop(dialogContext);
                              await _verifyAndApproveAccount(context, appState, user);
                            },
                            icon: const Icon(Icons.check_circle_outline, color: AppColors.success),
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
          title: Text('Vérifier le compte'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.fullName, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  SizedBox(height: 2),
                  Text(user.phone, style: TextStyle(color: AppColors.inkSoft)),
                  SizedBox(height: 14),
                  Text(
                    'Vérifiez les informations déclarées avant d’activer le compte. Elles peuvent être corrigées ici.',
                    style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft, height: 1.4),
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

class _AdminSummary extends StatelessWidget {
  final int pendingAccounts;
  final int pendingExchanges;
  final int pendingLeaves;
  final VoidCallback onAccountsTap;
  final VoidCallback onExchangesTap;
  final VoidCallback onLeavesTap;
  const _AdminSummary({
    required this.pendingAccounts,
    required this.pendingExchanges,
    required this.pendingLeaves,
    required this.onAccountsTap,
    required this.onExchangesTap,
    required this.onLeavesTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.sm),
      child: Row(children: [
        Expanded(child: _SummaryChip(icon: Icons.person_add_alt_1_rounded, count: pendingAccounts, label: 'comptes', accent: AppColors.catService, onTap: onAccountsTap)),
        const SizedBox(width: AppSpace.sm),
        Expanded(child: _SummaryChip(icon: Icons.swap_horiz_rounded, count: pendingExchanges, label: 'échanges', accent: AppColors.catUrgence, onTap: onExchangesTap)),
        const SizedBox(width: AppSpace.sm),
        Expanded(child: _SummaryChip(icon: Icons.beach_access_rounded, count: pendingLeaves, label: 'congés', accent: AppColors.conge, onTap: onLeavesTap)),
      ]),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final int count;
  final String label;
  final Color accent;
  final VoidCallback? onTap;
  const _SummaryChip({required this.icon, required this.count, required this.label, required this.accent, this.onTap});

  @override
  Widget build(BuildContext context) {
    final active = count > 0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: AppRadius.mdR,
        onTap: onTap,
        child: AppCard(
          padding: EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Icon(icon, size: 16, color: active ? accent : AppColors.inkFaint),
                Spacer(),
                Text(
                  '$count',
                  style: TextStyle(
                    fontFamily: 'SpaceGrotesk',
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: active ? AppColors.ink : AppColors.inkFaint,
                  ),
                ),
              ]),
              SizedBox(height: 2),
              Text(label, style: Theme.of(context).textTheme.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
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
    final bg = validated ? AppColors.conge.withOpacity(0.18) : AppColors.paperAlt;
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
          Icon(icon, size: 19, color: validated ? AppColors.congeText : AppColors.ink),
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
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.md),
      child: AppCard(
        padding: EdgeInsets.all(AppSpace.md),
        child: Row(children: [
          CircleAvatar(
            radius: 21,
            backgroundColor: AppColors.paperAlt,
            child: Text(_initials(doctor.fullName), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.ink)),
          ),
          SizedBox(width: AppSpace.md),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(doctor.fullName, style: Theme.of(context).textTheme.titleMedium, overflow: TextOverflow.ellipsis)),
              if (doctor.role == UserRole.admin) ...[
                SizedBox(width: 6),
                Pill(text: 'ADMIN', background: AppColors.ink, foreground: Colors.white, fontSize: 9),
              ],
            ]),
            SizedBox(height: 2),
            Text('${doctor.gradeLabel} · ${doctor.service} · ${hospitalDisplayName(doctor.hospital)}',
                style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
          ])),
          SizedBox(width: AppSpace.sm),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('$monthAssignments',
                style: TextStyle(fontFamily: 'SpaceGrotesk', fontSize: 19, fontWeight: FontWeight.w600, color: AppColors.ink)),
            Text('ce mois', style: Theme.of(context).textTheme.labelSmall),
            SizedBox(height: 3),
            Text('$totalAssignments au total', style: Theme.of(context).textTheme.labelSmall),
          ]),
        ]),
      ),
    );
  }
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
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    final firstWeekday = DateTime(month.year, month.month, 1).weekday - 1;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final todayKey = AppState.dateKey(DateTime.now());
    final entriesByDate = <String, PlanningEntry>{for (final entry in entries) entry.dateStr: entry};
    final cells = <Widget>[];
    for (var i = 0; i < firstWeekday; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(month.year, month.month, day);
      final key = AppState.dateKey(date);
      final entry = entriesByDate[key];
      VoidCallback? deleteCallback;
      if (entry != null && appState.canAdminDeleteEntry(entry)) {
        final currentEntry = entry;
        deleteCallback = () => onDeleteEntry(currentEntry);
      }
      cells.add(_AdminDayCell(
        day: day,
        isToday: key == todayKey,
        entry: entry,
        onDelete: deleteCallback,
      ));
    }

    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md),
      padding: EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppRadius.lgR,
        border: Border.all(color: AppColors.line),
        boxShadow: AppShadow.low,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final veryNarrow = width < 430;
          final narrow = width < 650;
          final gap = veryNarrow ? 4.0 : narrow ? 5.0 : 8.0;
          final cellWidth = (width - gap * 6) / 7;
          final targetHeight = veryNarrow
              ? (cellWidth * 1.66).clamp(70.0, 88.0).toDouble()
              : narrow
                  ? (cellWidth * 1.34).clamp(80.0, 106.0).toDouble()
                  : (cellWidth * 1.08).clamp(96.0, 148.0).toDouble();
          final weekdayLabels = veryNarrow
              ? const ['L', 'Ma', 'Me', 'J', 'V', 'S', 'D']
              : const ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(0, 2, 0, veryNarrow ? 5 : 7),
                child: Row(
                  children: weekdayLabels
                      .map((day) => Expanded(
                            child: Text(
                              day,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                    fontSize: veryNarrow ? 10.5 : 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.inkSoft,
                                  ),
                            ),
                          ))
                      .toList(),
                ),
              ),
              GridView.count(
                padding: EdgeInsets.zero,
                crossAxisCount: 7,
                mainAxisSpacing: gap,
                crossAxisSpacing: gap,
                mainAxisExtent: targetHeight,
                shrinkWrap: true,
                primary: false,
                physics: NeverScrollableScrollPhysics(),
                children: cells,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AdminDayCell extends StatelessWidget {
  final int day;
  final bool isToday;
  final PlanningEntry? entry;
  final VoidCallback? onDelete;
  const _AdminDayCell({required this.day, required this.isToday, required this.entry, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final currentEntry = entry;
    final shift = currentEntry == null ? null : ShiftCatalog.byId(currentEntry.shiftId);
    final group = currentEntry == null ? null : _shiftGroup(currentEntry.shiftId);
    final leave = currentEntry != null && currentEntry.shiftId == 'conge'
        ? context.read<AppState>().leaveRequestForEntry(currentEntry)
        : null;
    final pendingLeave = leave?.status == LeaveRequestStatus.pendingAdmin;

    return Semantics(
      label: 'Jour $day${currentEntry == null ? '' : ' · ${shift!.label}'}',
      child: Container(
        padding: EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: AppRadius.mdR,
          border: Border.all(color: isToday ? AppColors.ink : AppColors.line, width: isToday ? 1.6 : 1),
          boxShadow: entry == null ? null : AppShadow.low,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tiny = constraints.maxWidth < 50 || constraints.maxHeight < 60;
            final compact = constraints.maxWidth < 72 || constraints.maxHeight < 86;
            final headerHeight = tiny ? 19.0 : 23.0;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: headerHeight,
                  child: Row(
                    children: [
                      Container(
                        constraints: BoxConstraints(
                          minWidth: tiny ? 18 : 22,
                          minHeight: tiny ? 18 : 22,
                        ),
                        alignment: Alignment.center,
                        padding: EdgeInsets.symmetric(horizontal: tiny ? 2 : 4),
                        decoration: BoxDecoration(
                          color: isToday ? AppColors.ink : Colors.transparent,
                          borderRadius: AppRadius.smR,
                        ),
                        child: Text(
                          '$day',
                          style: TextStyle(
                            fontFamily: 'SpaceGrotesk',
                            fontSize: tiny ? 9.5 : 11.5,
                            fontWeight: FontWeight.w700,
                            color: isToday ? Colors.white : AppColors.ink,
                          ),
                        ),
                      ),
                      Spacer(),
                      if (onDelete != null)
                        Tooltip(
                          message: 'Supprimer cette garde',
                          child: Material(
                            color: Color(0xFFFFECE9),
                            borderRadius: BorderRadius.circular(999),
                            child: InkWell(
                              onTap: onDelete,
                              borderRadius: BorderRadius.circular(999),
                              child: SizedBox(
                                width: tiny ? 18 : 22,
                                height: tiny ? 18 : 22,
                                child: Icon(
                                  Icons.delete_outline_rounded,
                                  size: tiny ? 12 : 14,
                                  color: AppColors.danger,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(height: tiny ? 1 : 2),
                Expanded(
                  child: shift == null
                      ? SizedBox.shrink()
                      : _AdminShiftTile(
                          shift: shift,
                          group: group,
                          pendingLeave: pendingLeave,
                          compact: compact,
                          tiny: tiny,
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AdminShiftTile extends StatelessWidget {
  final ShiftType shift;
  final String? group;
  final bool pendingLeave;
  final bool compact;
  final bool tiny;

  const _AdminShiftTile({
    required this.shift,
    required this.group,
    required this.pendingLeave,
    required this.compact,
    required this.tiny,
  });

  @override
  Widget build(BuildContext context) {
    final groupLabel = shift.id == 'conge'
        ? 'Congé'
        : group == 'service'
            ? (tiny ? 'SERV' : 'Service')
            : (tiny ? 'URG' : 'Urgences');
    final secondLabel = shift.id == 'conge'
        ? (pendingLeave ? 'Attente' : null)
        : shift.label == 'Jour'
            ? 'Jour'
            : shift.label == 'Nuit'
                ? 'Nuit'
                : '24H';

    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: tiny ? 2 : 4, vertical: tiny ? 1 : 3),
      decoration: BoxDecoration(
        color: shift.color,
        borderRadius: AppRadius.smR,
        border: Border.all(color: Colors.white.withOpacity(0.36), width: 1.1),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showIcon = !tiny && constraints.maxHeight >= 42;
          return FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showIcon) ...[
                  Icon(shift.icon, size: compact ? 17 : 23, color: shift.textColor),
                  SizedBox(height: compact ? 1 : 2),
                ],
                Text(
                  groupLabel,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: tiny ? 9.5 : compact ? 10.5 : 13,
                    height: 1.0,
                    fontWeight: FontWeight.w900,
                    color: shift.textColor,
                  ),
                ),
                if (secondLabel != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    secondLabel,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: tiny ? 9 : compact ? 10 : 11.5,
                      height: 1.0,
                      fontWeight: FontWeight.w800,
                      color: shift.textColor.withOpacity(0.94),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
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
    Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.inkSoft)),
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
